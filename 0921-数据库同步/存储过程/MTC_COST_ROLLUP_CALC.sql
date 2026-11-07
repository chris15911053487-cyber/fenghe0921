CREATE PROCEDURE "FH100"."MTC_COST_ROLLUP_CALC" (
    IN iv_FcCode NVARCHAR(50)
)
LANGUAGE SQLSCRIPT
SQL SECURITY INVOKER
AS
BEGIN
    DECLARE lv_depth INTEGER := 0;
    DECLARE lv_count INTEGER := 1;

    -- ========================================
    -- 核心：按物料汇总所有工单的工费
    -- 同一物料、同一期间的多张工单 → 合并为一条
    -- ========================================
    lt_item_cost = 
        SELECT 
            "FcCode",
            "ItemCode",
            MAX("iLevel")           AS "iLevel",
            SUM("2ManExp")          AS "ManExp",        -- 该物料所有工单的人工合计
            SUM("3LabAmount")       AS "LabAmount",     -- 制造费合计
            SUM("4WWExp")           AS "WWExp",         -- 委外费合计
            SUM("Amount")           AS "Amount",        -- 总成本合计
            SUM("Quantity")         AS "TotalQty"       -- 总产出数量
        FROM "FH100"."MTC_COST_0321_OWOR_SUM"
        WHERE "FcCode" = :iv_FcCode
        GROUP BY "FcCode", "ItemCode";

    -- ========================================
    -- 核心：按物料汇总BOM组件（子物料维度）
    -- 同一父物料的所有工单中，相同子物料的投入合并
    -- ========================================
    lt_bom = 
        SELECT 
            S."FcCode",
            S."ItemCode"            AS "ParentItem",
            D."ItemCode"            AS "ChildItem",
            SUM(D."Amount")         AS "ChildMaterialAmt",  -- 该子物料的投入金额合计
            COALESCE(MAX(LV."iLevel"), 1) AS "ChildLevel"
        FROM "FH100"."MTC_COST_0321_OWOR_SUM" S
        INNER JOIN "FH100"."MTC_COST_0321_OWOR1" D
            ON S."WorEntry" = D."WorEntry"
            AND S."FcCode" = D."FcCode"
        LEFT JOIN "FH100"."U_COILV" LV
            ON D."ItemCode" = LV."ItemCode"
        WHERE S."FcCode" = :iv_FcCode
        GROUP BY S."FcCode", S."ItemCode", D."ItemCode";
    
    -- ========================================
    -- 清除旧数据
    -- ========================================
    DELETE FROM "FH100"."MTC_COST_ROLLUP_DETAIL" 
    WHERE "FcCode" = :iv_FcCode;
    
    -- ========================================
    -- 第0层：所有物料作为根节点
    -- ========================================
    INSERT INTO "FH100"."MTC_COST_ROLLUP_DETAIL"
    ("FcCode", "RootItem", "RootLevel", "CurrentItem", "CurrentLevel", 
     "Depth", "ParentItem", "Material", "ManExp", "LabAmount", "WWExp")
    SELECT 
        "FcCode",
        "ItemCode",
        "iLevel",
        "ItemCode",
        "iLevel",
        0,
        NULL,
        0,              -- 顶层材料由下层穿透
        "ManExp",       -- 本物料所有工单人工合计
        "LabAmount",    -- 制造费合计
        "WWExp"         -- 委外费合计
    FROM :lt_item_cost;
    
    -- ========================================
    -- 逐层循环展开
    -- ========================================
    WHILE :lv_count > 0 AND :lv_depth < 10 DO
        lv_depth := :lv_depth + 1;
        
        INSERT INTO "FH100"."MTC_COST_ROLLUP_DETAIL"
        ("FcCode", "RootItem", "RootLevel", "CurrentItem", "CurrentLevel", 
         "Depth", "ParentItem", "Material", "ManExp", "LabAmount", "WWExp")
        SELECT 
            R."FcCode",
            R."RootItem",
            R."RootLevel",
            BR."ChildItem",
            BR."ChildLevel",
            :lv_depth,
            R."CurrentItem",
            -- 材料：仅 iLevel=1 的原材料记录金额
            CASE WHEN BR."ChildLevel" = 1 
                 THEN BR."ChildMaterialAmt" 
                 ELSE 0 END,
            -- 人工：非原材料取该物料汇总后的人工费
            CASE WHEN BR."ChildLevel" > 1 
                 THEN COALESCE(CW."ManExp", 0) 
                 ELSE 0 END,
            -- 制造费
            CASE WHEN BR."ChildLevel" > 1 
                 THEN COALESCE(CW."LabAmount", 0) 
                 ELSE 0 END,
            -- 委外费
            CASE WHEN BR."ChildLevel" > 1 
                 THEN COALESCE(CW."WWExp", 0) 
                 ELSE 0 END
        FROM "FH100"."MTC_COST_ROLLUP_DETAIL" R
        -- BOM关系（已按物料汇总去重，父子物料唯一对应）
        INNER JOIN :lt_bom BR
            ON R."CurrentItem" = BR."ParentItem"
            AND R."FcCode" = BR."FcCode"
        -- 子物料的工费（按物料汇总后的）
        LEFT JOIN :lt_item_cost CW
            ON BR."ChildItem" = CW."ItemCode"
            AND BR."FcCode" = CW."FcCode"
        WHERE R."Depth" = :lv_depth - 1
          AND R."CurrentLevel" > 1;
        
        -- 检查是否还需要继续展开
        SELECT COUNT(*) INTO lv_count 
        FROM "FH100"."MTC_COST_ROLLUP_DETAIL"
        WHERE "FcCode" = :iv_FcCode
          AND "Depth" = :lv_depth 
          AND "CurrentLevel" > 1;
    END WHILE;

END;