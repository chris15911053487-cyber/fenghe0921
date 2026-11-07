CREATE PROCEDURE "MTC_COST_ROLLUP_PROC" (
    IN iv_FcCode NVARCHAR(50)  -- 输入：核算期间代码
)
LANGUAGE SQLSCRIPT
SQL SECURITY INVOKER
AS
BEGIN
    -- 临时表：存放递归展开结果
    DECLARE lt_result TABLE (
        "FcCode"        NVARCHAR(50),
        "RootItem"      NVARCHAR(50),
        "RootLevel"     INTEGER,
        "CurrentItem"   NVARCHAR(50),
        "CurrentLevel"  INTEGER,
        "Depth"         INTEGER,
        "Material"      DECIMAL(19,6),
        "ManExp"        DECIMAL(19,6),
        "LabAmount"     DECIMAL(19,6),
        "WWExp"         DECIMAL(19,6)
    );
    
    DECLARE lv_depth INTEGER := 0;
    DECLARE lv_count INTEGER := 1;
    
    -- ========================================
    -- 第一层：所有工单的产出物料（作为根节点）
    -- ========================================
    INSERT INTO :lt_result
    SELECT 
        S."FcCode",
        S."ItemCode"    AS "RootItem",
        S."iLevel"      AS "RootLevel",
        S."ItemCode"    AS "CurrentItem",
        S."iLevel"      AS "CurrentLevel",
        0               AS "Depth",
        0               AS "Material",      -- 顶层材料由下层穿透汇上来
        S."2ManExp"     AS "ManExp",        -- 顶层本身的人工
        S."3LabAmount"  AS "LabAmount",     -- 顶层本身的制造费
        S."4WWExp"      AS "WWExp"          -- 顶层本身的委外费
    FROM "MTC_COST_0321_OWOR_SUM" S
    WHERE S."FcCode" = :iv_FcCode;
    
    -- ========================================
    -- 逐层展开（循环代替递归CTE，更可控）
    -- ========================================
    WHILE :lv_count > 0 AND :lv_depth < 10 DO
        lv_depth := :lv_depth + 1;
        
        INSERT INTO :lt_result
        SELECT 
            R."FcCode",
            R."RootItem",
            R."RootLevel",
            BR."ChildItem"      AS "CurrentItem",
            BR."ChildLevel"     AS "CurrentLevel",
            :lv_depth           AS "Depth",
            -- 材料：只有原材料(iLevel=1)才记录材料金额
            CASE WHEN BR."ChildLevel" = 1 
                 THEN BR."ChildMaterialAmt" 
                 ELSE 0 END     AS "Material",
            -- 人工：非原材料层取其工单的人工费
            CASE WHEN BR."ChildLevel" > 1 
                 THEN COALESCE(CS."2ManExp", 0) 
                 ELSE 0 END     AS "ManExp",
            -- 制造费
            CASE WHEN BR."ChildLevel" > 1 
                 THEN COALESCE(CS."3LabAmount", 0) 
                 ELSE 0 END     AS "LabAmount",
            -- 委外费
            CASE WHEN BR."ChildLevel" > 1 
                 THEN COALESCE(CS."4WWExp", 0) 
                 ELSE 0 END     AS "WWExp"
        FROM :lt_result R
        -- 关联BOM关系：当前物料作为父物料，找其子物料
        INNER JOIN (
            SELECT 
                S."FcCode",
                S."ItemCode"  AS "ParentItem",
                D."ItemCode"  AS "ChildItem",
                D."Amount"    AS "ChildMaterialAmt",
                COALESCE(LV."iLevel", 1) AS "ChildLevel"
            FROM "MTC_COST_0321_OWOR_SUM" S
            INNER JOIN "MTC_COST_0321_OWOR1" D
                ON S."WorEntry" = D."WorEntry"
                AND S."FcCode" = D."FcCode"
            LEFT JOIN "U_COILV" LV
                ON D."ItemCode" = LV."ItemCode"
            WHERE S."FcCode" = :iv_FcCode
        ) BR
            ON R."CurrentItem" = BR."ParentItem"
            AND R."FcCode" = BR."FcCode"
        -- 关联子物料的工单（获取其工费）
        LEFT JOIN "MTC_COST_0321_OWOR_SUM" CS
            ON BR."ChildItem" = CS."ItemCode"
            AND BR."FcCode" = CS."FcCode"
        WHERE R."Depth" = :lv_depth - 1    -- 只展开上一轮新增的记录
          AND R."CurrentLevel" > 1;         -- 原材料不再展开
        
        -- 检查本轮是否有新增（是否还需要继续展开）
        SELECT COUNT(*) INTO lv_count 
        FROM :lt_result 
        WHERE "Depth" = :lv_depth AND "CurrentLevel" > 1;
    END WHILE;
    
    -- ========================================
    -- 最终汇总：按根物料 + 核算期间 汇总
    -- ========================================
    SELECT 
        R."FcCode",
        R."RootItem"            AS "ItemCode",
        MAX(S."ItemName")       AS "ItemName",
        MAX(S."ItmsGrpCod")    AS "ItmsGrpCod",
        R."RootLevel"           AS "iLevel",
        
        -- 料工费卷积结果
        SUM(R."Material")       AS "Material_Rolled",   -- 材料费（穿透到原材料）
        SUM(R."ManExp")         AS "ManExp_Rolled",     -- 人工费（各层累加）
        SUM(R."LabAmount")      AS "LabAmount_Rolled",  -- 制造费（各层累加）
        SUM(R."WWExp")          AS "WWExp_Rolled",      -- 委外费（各层累加）
        SUM(R."Material") + SUM(R."ManExp") 
        + SUM(R."LabAmount") + SUM(R."WWExp") 
                                AS "TotalCost_Rolled",  -- 成本合计
        
        -- 对比原始成本（验证用）
        MAX(S."Amount")         AS "Amount_Original",   -- 原始合计
        MAX(S."1Material")      AS "Material_Original", -- 原始材料费
        MAX(S."2ManExp")        AS "ManExp_Original",   -- 原始人工费
        MAX(S."3LabAmount")     AS "LabAmount_Original",-- 原始制造费
        MAX(S."4WWExp")         AS "WWExp_Original",    -- 原始委外费
        
        -- 差异分析
        SUM(R."Material") + SUM(R."ManExp") 
        + SUM(R."LabAmount") + SUM(R."WWExp") 
        - MAX(S."Amount")       AS "CostDifference"     -- 卷积差异

    FROM :lt_result R
    LEFT JOIN "MTC_COST_0321_OWOR_SUM" S
        ON R."RootItem" = S."ItemCode" 
        AND R."FcCode" = S."FcCode"
    GROUP BY R."FcCode", R."RootItem", R."RootLevel"
    ORDER BY R."RootLevel" DESC, R."RootItem";

END;