CREATE PROCEDURE "MTC_RPT_CO3006" (
IN USERId INT
      ,IN sFcCode NVARCHAR(50)
      ,IN eFcCode NVARCHAR(50)
      ,IN ItemCode NVARCHAR(100)
  )
  LANGUAGE SQLSCRIPT
  SQL SECURITY INVOKER
  AS
  BEGIN

	SELECT
      -- 基本信息
      T."FcCode"                                          AS "期间",
      T."ItemCode"                                        AS "物料编号",
      T."ItemName"                                        AS "物料名称",
      T."iLevel"                                          AS "BOM层级",
      T."Status"                                          AS "状态",
  
      -- =====================================================
      -- 期初
      -- =====================================================
      T."OpenQty"                                         AS "期初数量",
      T."OpenMaterial"                                    AS "期初材料金额",
      T."OpenManExp"                                      AS "期初制造费用",
      T."OpenLabAmount"                                   AS "期初人工费用",
      T."OpenWWExp"                                       AS "期初外协费用",
      T."OpenAmount"                                      AS "期初合计",
      CASE WHEN T."OpenQty" > 0
           THEN ROUND(T."OpenAmount" / T."OpenQty", 6)
           ELSE 0 END                                     AS "期初单位成本",
  
      -- =====================================================
      -- 本期入库
      -- =====================================================
      T."InQty"                                           AS "入库数量",
      T."InMaterial"                                      AS "入库材料金额",
      T."InManExp"                                        AS "入库制造费用",
      T."InLabAmount"                                     AS "入库人工费用",
      T."InWWExp"                                         AS "入库外协费用",
      T."InAmount"                                        AS "入库合计",
      CASE WHEN T."InQty" > 0
           THEN ROUND(T."InAmount" / T."InQty", 6)
           ELSE 0 END                                     AS "入库单位成本",
  
      -- =====================================================
      -- 本期出库
      -- =====================================================
      T."OutQty"                                          AS "出库数量",
      T."OutMaterial"                                     AS "出库材料金额",
      T."OutManExp"                                       AS "出库制造费用",
      T."OutLabAmount"                                    AS "出库人工费用",
      T."OutWWExp"                                        AS "出库外协费用",
      T."OutAmount"                                       AS "出库合计",
      CASE WHEN T."OutQty" > 0
           THEN ROUND(T."OutAmount" / T."OutQty", 6)
           ELSE 0 END                                     AS "出库单位成本",
  
      -- =====================================================
      -- 期末
      -- =====================================================
      T."CloseQty"                                        AS "期末数量",
      T."CloseMaterial"                                   AS "期末材料金额",
      T."CloseManExp"                                     AS "期末制造费用",
      T."CloseLabAmount"                                  AS "期末人工费用",
      T."CloseWWExp"                                      AS "期末外协费用",
      T."CloseAmount"                                     AS "期末合计",
  
      -- =====================================================
      -- 期末单位成本
      -- =====================================================
      T."UnitMaterial"                                    AS "期末单位材料成本",
      T."UnitManExp"                                      AS "期末单位制造费用",
      T."UnitLabAmount"                                   AS "期末单位人工费用",
      T."UnitWWExp"                                       AS "期末单位外协费用",
      T."UnitCost"                                        AS "期末单位总成本",
  
      -- =====================================================
      -- 成本结构比例
      -- =====================================================
      ROUND(IFNULL(T."PrcMaterial",  0) * 100, 2)        AS "材料占比%",
      ROUND(IFNULL(T."PrcManExp",    0) * 100, 2)        AS "制造费用占比%",
      ROUND(IFNULL(T."PrcLabAmount", 0) * 100, 2)        AS "人工费用占比%",
      ROUND(IFNULL(T."PrcWWExp",     0) * 100, 2)        AS "外协费用占比%",
      ROUND((  IFNULL(T."PrcMaterial",  0)
             + IFNULL(T."PrcManExp",    0)
             + IFNULL(T."PrcLabAmount", 0)
             + IFNULL(T."PrcWWExp",     0)) * 100, 2)    AS "比例合计%",
  
      -- =====================================================
      -- 校验：数量平衡（应=0）
      -- =====================================================
      ROUND(T."OpenQty" + T."InQty" - T."OutQty" - T."CloseQty", 6)  AS "数量差异",
  
      -- 校验：金额平衡（应=0）
      ROUND(T."OpenAmount" + T."InAmount" - T."OutAmount" - T."CloseAmount", 2) AS "金额差异"
  
  FROM "MTC_COST_STOCK" T
  WHERE  1=1
  AND T."FcCode" >= :sFcCode     -- 替换为目标期间
  AND T."FcCode" <= :eFcCode     -- 替换为目标期间
    AND T."Status" = 'C'
    AND (T."ItemCode"=:ItemCode OR :ItemCode='')
  ORDER BY T."iLevel", T."ItemCode";
  
 END