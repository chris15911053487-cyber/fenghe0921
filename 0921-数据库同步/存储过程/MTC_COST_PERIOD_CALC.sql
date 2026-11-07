CREATE PROCEDURE "MTC_COST_PERIOD_CALC" (
      IN iv_FcCode NVARCHAR(50)
  )
  LANGUAGE SQLSCRIPT
  SQL SECURITY INVOKER
  AS
  BEGIN
      DECLARE lv_level     INTEGER := 1;
      DECLARE lv_max_level INTEGER := 1;
      DECLARE lv_count     INTEGER := 0;
  
      -- 清除当期明细旧数据
      DELETE FROM "MTC_COST_ROLLUP_DETAIL" WHERE "FcCode" = :iv_FcCode;
  
      -- 获取最大物料等级
      SELECT COALESCE(MAX("iLevel"), 1) INTO lv_max_level
      FROM "U_COILV" WHERE "FcCode" = :iv_FcCode;
  
      -- =====================================================
      -- 收发存数量+金额基准
      -- =====================================================
      lt_invnt =
          SELECT
              T0."FcCode",
              T0."ItemCode",
              T0."ItemName",
              IFNULL(T0."QC_Qty",    0)  AS "OpenQty",
              IFNULL(T0."QC_Amount", 0)  AS "OpenAmount",
              IFNULL(T1."In_Qty",    0)  AS "InQty",
              IFNULL(T1."In_Amount", 0)  AS "InAmount",
              IFNULL(T1."Out_Qty",   0)  AS "OutQty",
              IFNULL(T0."QC_Qty",    0)
                  + IFNULL(T1."In_Qty",  0)
                  - IFNULL(T1."Out_Qty", 0) AS "CloseQty"
          FROM "MTC_COST_0301_INVNT" T0
          LEFT JOIN (
              SELECT
                  T1."FcCode",
                  T1."ItemCode",
                  SUM(CASE WHEN T2."U_IOType" = 'I' THEN  T1."Quantity" ELSE 0 END) AS "In_Qty",
                  SUM(CASE WHEN T2."U_IOType" = 'I' THEN  T1."Amount"   ELSE 0 END) AS "In_Amount",
                  SUM(CASE WHEN T2."U_IOType" = 'O' THEN -1 * T1."Quantity" ELSE 0 END) AS "Out_Qty"
              FROM "MTC_COST_0302_INVNTDETAIL1" T1
              JOIN "@MTC_COST_IOTYPE" T2 ON T1."TransCode" = T2."Code"
              WHERE T1."FcCode" = :iv_FcCode
              GROUP BY T1."FcCode", T1."ItemCode"
          ) T1 ON T0."FcCode" = T1."FcCode" AND T0."ItemCode" = T1."ItemCode"
          WHERE T0."FcCode"   = :iv_FcCode
            AND T0."CostCode" = '20';
  
      -- 按物料汇总工单工费
      lt_item_cost =
          SELECT
              S."FcCode",
              S."ItemCode",
              MAX(S."ItemName")             AS "ItemName",
              COALESCE(MAX(LV."iLevel"), 1) AS "iLevel",
              SUM(S."2ManExp")              AS "ManExp",
              SUM(S."3LabAmount")           AS "LabAmount",
              SUM(S."4WWExp")               AS "WWExp"
          FROM "MTC_COST_0321_OWOR_SUM" S
          LEFT JOIN "U_COILV" LV
              ON S."ItemCode" = LV."ItemCode" AND S."FcCode" = LV."FcCode"
          WHERE S."FcCode" = :iv_FcCode
          GROUP BY S."FcCode", S."ItemCode";
  
      -- BOM关系：子物料投入金额
      lt_bom =
          SELECT
              S."FcCode",
              S."ItemCode"                  AS "ParentItem",
              D."ItemCode"                  AS "ChildItem",
              SUM(IFNULL(D."Amount", 0))    AS "ChildAmount",
              COALESCE(MAX(LV."iLevel"), 1) AS "ChildLevel"
          FROM "MTC_COST_0321_OWOR_SUM" S
          INNER JOIN "MTC_COST_0321_OWOR1_REG" D
              ON S."WorEntry" = D."WorEntry" AND S."FcCode" = D."FcCode"
          LEFT JOIN "U_COILV" LV
              ON D."ItemCode" = LV."ItemCode" AND S."FcCode" = LV."FcCode"
          WHERE S."FcCode" = :iv_FcCode
          GROUP BY S."FcCode", S."ItemCode", D."ItemCode";
  
      -- =====================================================
      -- 无工单物料：整理成中间表再UPDATE
      -- =====================================================
      lt_no_order =
          SELECT
              IV."FcCode",
              IV."ItemCode",
              IV."OpenQty",
              IV."OpenAmount",
              IV."InQty",
              IV."InAmount",
              IV."OutQty",
              IV."CloseQty",
              -- 加权平均单位成本分母
              IV."OpenQty" + IV."InQty"                                AS "TotalQty",
              -- 加权平均单位成本分子
              IFNULL(ST."OpenMaterial", 0) + IV."InAmount"             AS "TotalMaterial",
              IFNULL(ST."OpenAmount",   0) + IV."InAmount"             AS "TotalAmount",
              -- 加权平均单位成本
              CASE WHEN (IV."OpenQty" + IV."InQty") > 0
                   THEN (IFNULL(ST."OpenAmount", 0) + IV."InAmount")
                      / (IV."OpenQty" + IV."InQty")
                   ELSE 0 END                                          AS "AvgUnitCost",
              -- 出库金额
              CASE WHEN (IV."OpenQty" + IV."InQty") > 0
                   THEN (IFNULL(ST."OpenAmount", 0) + IV."InAmount")
                      / (IV."OpenQty" + IV."InQty") * IV."OutQty"
                   ELSE 0 END                                          AS "OutAmount",
              -- 期末金额
              CASE WHEN (IV."OpenQty" + IV."InQty") > 0
                   THEN (IFNULL(ST."OpenAmount", 0) + IV."InAmount")
                      - (IFNULL(ST."OpenAmount", 0) + IV."InAmount")
                      / (IV."OpenQty" + IV."InQty") * IV."OutQty"
                   ELSE IFNULL(ST."OpenAmount", 0) + IV."InAmount" END AS "CloseAmount"
          FROM :lt_invnt IV
          LEFT JOIN "MTC_COST_STOCK" ST
              ON ST."ItemCode" = IV."ItemCode" AND ST."FcCode" = IV."FcCode"
          WHERE IV."ItemCode" NOT IN (SELECT "ItemCode" FROM :lt_item_cost);
  
      -- 无工单物料 UPDATE
      UPDATE "MTC_COST_STOCK" T
      SET
          T."InQty"          = IFNULL((SELECT S."InQty"      FROM :lt_no_order S WHERE S."ItemCode" = T."ItemCode"), 0),
          T."InMaterial"     = IFNULL((SELECT S."InAmount"   FROM :lt_no_order S WHERE S."ItemCode" = T."ItemCode"), 0),
          T."InManExp"       = 0,
          T."InLabAmount"    = 0,
          T."InWWExp"        = 0,
          T."InAmount"       = IFNULL((SELECT S."InAmount"   FROM :lt_no_order S WHERE S."ItemCode" = T."ItemCode"), 0),
          T."OutQty"         = IFNULL((SELECT S."OutQty"     FROM :lt_no_order S WHERE S."ItemCode" = T."ItemCode"), 0),
          T."OutMaterial"    = IFNULL((SELECT S."OutAmount"  FROM :lt_no_order S WHERE S."ItemCode" = T."ItemCode"), 0),
          T."OutManExp"      = 0,
          T."OutLabAmount"   = 0,
          T."OutWWExp"       = 0,
          T."OutAmount"      = IFNULL((SELECT S."OutAmount"  FROM :lt_no_order S WHERE S."ItemCode" = T."ItemCode"), 0),
          T."CloseQty"       = IFNULL((SELECT S."CloseQty"   FROM :lt_no_order S WHERE S."ItemCode" = T."ItemCode"), T."OpenQty"),
          T."CloseMaterial"  = IFNULL((SELECT S."CloseAmount" FROM :lt_no_order S WHERE S."ItemCode" = T."ItemCode"), T."OpenAmount"),
          T."CloseManExp"    = 0,
          T."CloseLabAmount" = 0,
          T."CloseWWExp"     = 0,
          T."CloseAmount"    = IFNULL((SELECT S."CloseAmount" FROM :lt_no_order S WHERE S."ItemCode" = T."ItemCode"), T."OpenAmount"),
          T."UnitMaterial"   = IFNULL((SELECT S."AvgUnitCost" FROM :lt_no_order S WHERE S."ItemCode" = T."ItemCode"), 0),
          T."UnitManExp"     = 0,
          T."UnitLabAmount"  = 0,
          T."UnitWWExp"      = 0,
          T."UnitCost"       = IFNULL((SELECT S."AvgUnitCost" FROM :lt_no_order S WHERE S."ItemCode" = T."ItemCode"), 0),
          T."PrcMaterial"    = 1,
          T."PrcManExp"      = 0,
          T."PrcLabAmount"   = 0,
          T."PrcWWExp"       = 0,
          T."Status"         = 'C'
      WHERE T."FcCode"   = :iv_FcCode
        AND T."ItemCode" IN (SELECT "ItemCode" FROM :lt_no_order);
  
      -- =====================================================
      -- 逐级计算（有工单物料）
      -- =====================================================
      WHILE :lv_level <= :lv_max_level DO
  
          SELECT COUNT(*) INTO lv_count
          FROM :lt_item_cost WHERE "iLevel" = :lv_level;
  
          IF :lv_count > 0 THEN
  
              -- 写入明细表
              INSERT INTO "MTC_COST_ROLLUP_DETAIL"
              (
                  "FcCode", "ParentItem", "ParentLevel", "ChildItem", "ChildLevel",
                  "ChildAmount", "ChildUnitCost", "ChildUnitMaterial", "ChildUnitManExp",
                  "ChildUnitLabAmt", "ChildUnitWWExp",
                  "SplitMaterial", "SplitManExp", "SplitLabAmount", "SplitWWExp",
                  "SplitTotal", "MaterialPct"
              )
              SELECT
                  BR."FcCode",
                  BR."ParentItem",
                  :lv_level,
                  BR."ChildItem",
                  BR."ChildLevel",
                  BR."ChildAmount",
                  IFNULL(ST."UnitCost",      0),
                  IFNULL(ST."UnitMaterial",  0),
                  IFNULL(ST."UnitManExp",    0),
                  IFNULL(ST."UnitLabAmount", 0),
                  IFNULL(ST."UnitWWExp",     0),
                  BR."ChildAmount" * IFNULL(ST."PrcMaterial",  1),
                  BR."ChildAmount" * IFNULL(ST."PrcManExp",    0),
                  BR."ChildAmount" * IFNULL(ST."PrcLabAmount", 0),
                  BR."ChildAmount" * IFNULL(ST."PrcWWExp",     0),
                  BR."ChildAmount",
                  ROUND(IFNULL(ST."PrcMaterial", 1) * 100.0, 2)
              FROM :lt_bom BR
              LEFT JOIN "MTC_COST_STOCK" ST
                  ON BR."ChildItem" = ST."ItemCode"
                  AND BR."FcCode"   = ST."FcCode"
              WHERE BR."ParentItem" IN (
                  SELECT "ItemCode" FROM :lt_item_cost WHERE "iLevel" = :lv_level
              );
  
              -- 汇总子料真实成本分类
              lt_child_cost =
                  SELECT
                      BR."FcCode",
                      BR."ParentItem",
                      SUM(BR."ChildAmount" * IFNULL(ST."PrcMaterial",  1)) AS "ChildMaterialTotal",
                      SUM(BR."ChildAmount" * IFNULL(ST."PrcManExp",    0)) AS "ChildManExpTotal",
                      SUM(BR."ChildAmount" * IFNULL(ST."PrcLabAmount", 0)) AS "ChildLabTotal",
                      SUM(BR."ChildAmount" * IFNULL(ST."PrcWWExp",     0)) AS "ChildWWExpTotal"
                  FROM :lt_bom BR
                  LEFT JOIN "MTC_COST_STOCK" ST
                      ON BR."ChildItem" = ST."ItemCode"
                      AND BR."FcCode"   = ST."FcCode"
                  WHERE BR."ParentItem" IN (
                      SELECT "ItemCode" FROM :lt_item_cost WHERE "iLevel" = :lv_level
                  )
                  GROUP BY BR."FcCode", BR."ParentItem";
  
              -- 构建入库+出库数据
              lt_level_in =
                  SELECT
                      IC."FcCode",
                      IC."ItemCode",
                      IC."ItemName",
                      IC."iLevel",
                      IFNULL(IV."OpenQty",            0)                             AS "OpenQty",
                      IFNULL(IV."InQty",              0)                             AS "InQty",
                      IFNULL(IV."OutQty",             0)                             AS "OutQty",
                      IFNULL(IV."CloseQty",           0)                             AS "CloseQty",
                      IFNULL(CC."ChildMaterialTotal", 0)                             AS "InMaterial",
                      IFNULL(CC."ChildManExpTotal",   0) + IFNULL(IC."ManExp",    0) AS "InManExp",
                      IFNULL(CC."ChildLabTotal",      0) + IFNULL(IC."LabAmount", 0) AS "InLabAmount",
                      IFNULL(CC."ChildWWExpTotal",    0) + IFNULL(IC."WWExp",     0) AS "InWWExp",
                      IFNULL(IV."OpenQty", 0) + IFNULL(IV."InQty", 0)               AS "TotalInQty"
                  FROM :lt_item_cost IC
                  LEFT JOIN :lt_child_cost CC
                      ON IC."ItemCode" = CC."ParentItem" AND IC."FcCode" = CC."FcCode"
                  LEFT JOIN :lt_invnt IV
                      ON IC."ItemCode" = IV."ItemCode"   AND IC."FcCode" = IV."FcCode"
                  WHERE IC."iLevel" = :lv_level;
  
              -- MERGE 写入
              MERGE INTO "MTC_COST_STOCK" T
              USING (
                  SELECT
                      S."FcCode",
                      S."ItemCode",
                      S."ItemName",
                      S."iLevel",
                      S."OpenQty",
                      S."InQty",
                      S."OutQty",
                      S."CloseQty",
                      S."InMaterial",
                      S."InManExp",
                      S."InLabAmount",
                      S."InWWExp",
                      S."TotalInQty",
                      CASE WHEN S."TotalInQty" > 0
                           THEN (IFNULL(T2."OpenMaterial",  0) + S."InMaterial")  / S."TotalInQty"
                           ELSE 0 END AS "AvgUnitMaterial",
                      CASE WHEN S."TotalInQty" > 0
                           THEN (IFNULL(T2."OpenManExp",    0) + S."InManExp")    / S."TotalInQty"
                           ELSE 0 END AS "AvgUnitManExp",
                      CASE WHEN S."TotalInQty" > 0
                           THEN (IFNULL(T2."OpenLabAmount", 0) + S."InLabAmount") / S."TotalInQty"
                           ELSE 0 END AS "AvgUnitLabAmount",
                      CASE WHEN S."TotalInQty" > 0
                           THEN (IFNULL(T2."OpenWWExp",     0) + S."InWWExp")     / S."TotalInQty"
                           ELSE 0 END AS "AvgUnitWWExp",
                      CASE WHEN S."TotalInQty" > 0
                           THEN (IFNULL(T2."OpenAmount",    0) + S."InMaterial"
                                 + S."InManExp" + S."InLabAmount" + S."InWWExp") / S."TotalInQty"
                           ELSE 0 END AS "AvgUnitCost"
                  FROM :lt_level_in S
                  LEFT JOIN "MTC_COST_STOCK" T2
                      ON T2."ItemCode" = S."ItemCode" AND T2."FcCode" = S."FcCode"
              ) S
              ON T."FcCode" = S."FcCode" AND T."ItemCode" = S."ItemCode"
              WHEN MATCHED THEN UPDATE SET
                  T."ItemName"       = S."ItemName",
                  T."iLevel"         = S."iLevel",
                  T."OpenQty"        = S."OpenQty",
                  T."InQty"          = S."InQty",
                  T."InMaterial"     = S."InMaterial",
                  T."InManExp"       = S."InManExp",
                  T."InLabAmount"    = S."InLabAmount",
                  T."InWWExp"        = S."InWWExp",
                  T."InAmount"       = S."InMaterial" + S."InManExp" + S."InLabAmount" + S."InWWExp",
                  T."OutQty"         = S."OutQty",
                  T."OutMaterial"    = S."AvgUnitMaterial"  * S."OutQty",
                  T."OutManExp"      = S."AvgUnitManExp"    * S."OutQty",
                  T."OutLabAmount"   = S."AvgUnitLabAmount" * S."OutQty",
                  T."OutWWExp"       = S."AvgUnitWWExp"     * S."OutQty",
                  T."OutAmount"      = S."AvgUnitCost"      * S."OutQty",
                  T."CloseQty"       = S."CloseQty",
                  T."CloseMaterial"  = IFNULL(T."OpenMaterial",  0) + S."InMaterial"
                                     - S."AvgUnitMaterial"  * S."OutQty",
                  T."CloseManExp"    = IFNULL(T."OpenManExp",    0) + S."InManExp"
                                     - S."AvgUnitManExp"    * S."OutQty",
                  T."CloseLabAmount" = IFNULL(T."OpenLabAmount", 0) + S."InLabAmount"
                                     - S."AvgUnitLabAmount" * S."OutQty",
                  T."CloseWWExp"     = IFNULL(T."OpenWWExp",     0) + S."InWWExp"
                                     - S."AvgUnitWWExp"     * S."OutQty",
                  T."CloseAmount"    = IFNULL(T."OpenAmount",    0) + S."InMaterial"
                                     + S."InManExp" + S."InLabAmount" + S."InWWExp"
                                     - S."AvgUnitCost"      * S."OutQty",
                  T."Status"         = 'C'
              WHEN NOT MATCHED THEN INSERT (
                  "FcCode", "ItemCode", "ItemName", "iLevel",
                  "OpenQty", "OpenMaterial", "OpenManExp", "OpenLabAmount", "OpenWWExp", "OpenAmount",
                  "InQty",  "InMaterial",  "InManExp",  "InLabAmount",  "InWWExp",  "InAmount",
                  "OutQty", "OutMaterial", "OutManExp", "OutLabAmount", "OutWWExp", "OutAmount",
                  "CloseQty", "CloseMaterial", "CloseManExp", "CloseLabAmount", "CloseWWExp", "CloseAmount",
                  "Status"
              ) VALUES (
                  S."FcCode", S."ItemCode", S."ItemName", S."iLevel",
                  S."OpenQty", 0, 0, 0, 0, 0,
                  S."InQty",  S."InMaterial",  S."InManExp",  S."InLabAmount",  S."InWWExp",
                  S."InMaterial" + S."InManExp" + S."InLabAmount" + S."InWWExp",
                  S."OutQty",
                  S."AvgUnitMaterial"  * S."OutQty",
                  S."AvgUnitManExp"    * S."OutQty",
                  S."AvgUnitLabAmount" * S."OutQty",
                  S."AvgUnitWWExp"     * S."OutQty",
                  S."AvgUnitCost"      * S."OutQty",
                  S."CloseQty",
                  S."InMaterial"  - S."AvgUnitMaterial"  * S."OutQty",
                  S."InManExp"    - S."AvgUnitManExp"    * S."OutQty",
                  S."InLabAmount" - S."AvgUnitLabAmount" * S."OutQty",
                  S."InWWExp"     - S."AvgUnitWWExp"     * S."OutQty",
                  S."InMaterial" + S."InManExp" + S."InLabAmount" + S."InWWExp"
                  - S."AvgUnitCost" * S."OutQty",
                  'C'
              );
  
              -- 计算单位成本
              UPDATE "MTC_COST_STOCK"
              SET
                  "UnitMaterial"  = CASE WHEN "CloseQty" > 0 THEN "CloseMaterial"  / "CloseQty" ELSE 0 END,
                  "UnitManExp"    = CASE WHEN "CloseQty" > 0 THEN "CloseManExp"    / "CloseQty" ELSE 0 END,
                  "UnitLabAmount" = CASE WHEN "CloseQty" > 0 THEN "CloseLabAmount" / "CloseQty" ELSE 0 END,
                  "UnitWWExp"     = CASE WHEN "CloseQty" > 0 THEN "CloseWWExp"     / "CloseQty" ELSE 0 END,
                  "UnitCost"      = CASE WHEN "CloseQty" > 0 THEN "CloseAmount"    / "CloseQty" ELSE 0 END
              WHERE "FcCode"   = :iv_FcCode
                AND "iLevel"   = :lv_level
                AND "CloseQty" > 0;
  
              -- 每级计算完立即更新 Prc
              UPDATE "MTC_COST_STOCK"
              SET
                  "PrcMaterial"  = "CloseMaterial"  / NULLIF("CloseAmount", 0),
                  "PrcManExp"    = "CloseManExp"     / NULLIF("CloseAmount", 0),
                  "PrcLabAmount" = "CloseLabAmount"  / NULLIF("CloseAmount", 0),
                  "PrcWWExp"     = "CloseWWExp"      / NULLIF("CloseAmount", 0)
              WHERE "FcCode"      = :iv_FcCode
                AND "iLevel"      = :lv_level
                AND "CloseAmount" > 0;
  
              -- 兜底
              UPDATE "MTC_COST_STOCK"
              SET
                  "PrcMaterial"  = CASE WHEN "iLevel" = 1 THEN 1 ELSE 0 END,
                  "PrcManExp"    = 0,
                  "PrcLabAmount" = 0,
                  "PrcWWExp"     = 0
              WHERE "FcCode"      = :iv_FcCode
                AND "iLevel"      = :lv_level
                AND "CloseAmount" = 0;
  
          END IF;
  
          lv_level := :lv_level + 1;
  
      END WHILE;
  
      -- 最终差值法修正 PrcMaterial
      UPDATE "MTC_COST_STOCK"
      SET
          "PrcMaterial" = 1 - IFNULL("PrcManExp",    0)
                            - IFNULL("PrcLabAmount",  0)
                            - IFNULL("PrcWWExp",      0)
      WHERE "FcCode" = :iv_FcCode;
  
  END;