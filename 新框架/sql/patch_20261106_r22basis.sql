-- R22 加“口径”参数 Basis：0 本级（默认）/ 1 成本还原（用户 2026-11-06）。只重建过程 MTC_CA_RPT_22_COSTTREND，定义同 21_reports.sql；过程多了一个参数，执行台要同时更新，B1 查询管理器里已登记的 R22 要重新登记（新框架/tools/sl_import_queries.py）。离线写的，还没编译。
CREATE OR REPLACE PROCEDURE "MTC_CA_RPT_22_COSTTREND" (
    IN FcFrom NVARCHAR(10), IN FcTo NVARCHAR(10), IN Item NVARCHAR(5000), IN ItemGrp NVARCHAR(5000), IN WorType NVARCHAR(100), IN Basis NVARCHAR(1), IN STYPE NVARCHAR(1))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE nItem INT; DECLARE nGrp INT; DECLARE nWt INT; DECLARE f0 NVARCHAR(10); DECLARE f1 NVARCHAR(10); DECLARE bs NVARCHAR(1);
    bs := CASE WHEN :Basis = '1' THEN '1' ELSE '0' END;
    f0 := NULLIF(TRIM(IFNULL(:FcFrom, '')), ''); f1 := NULLIF(TRIM(IFNULL(:FcTo, '')), '');
    IF :f0 IS NULL THEN SELECT MIN("Code") INTO f0 FROM "OFPR"; END IF;
    IF :f1 IS NULL THEN SELECT MAX("Code") INTO f1 FROM "OFPR"; END IF;
    runs = SELECT "FcCode", "RunId" FROM "MTC_CA_F_RPT_RUN"(:f0, :f1) WHERE "RunId" IS NOT NULL;
    lItem = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Item);    SELECT COUNT(*) INTO nItem FROM :lItem;
    lGrp  = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:ItemGrp); SELECT COUNT(*) INTO nGrp FROM :lGrp;
    lWt   = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:WorType); SELECT COUNT(*) INTO nWt FROM :lWt;
    ord = SELECT U."FcCode", O."ItemCode", M."ItemName", TO_NVARCHAR(M."ItmsGrpCod") AS "Grp", G."ItmsGrpNam" AS "GrpName",
                 O."RecvQty", O."CostAmt",
                 CASE WHEN :bs = '1' THEN O."CostMat" ELSE O."CostAmt" - O."AllocLab" - O."AllocMfg" - IFNULL(F."CarSub", 0) END AS "CostMat",
                 CASE WHEN :bs = '1' THEN O."CostLab" ELSE O."AllocLab" END AS "CostLab",
                 CASE WHEN :bs = '1' THEN O."CostMfg" ELSE O."AllocMfg" END AS "CostMfg",
                 CASE WHEN :bs = '1' THEN O."CostSub" ELSE IFNULL(F."CarSub", 0) END AS "CostSub"
            FROM :runs U
            JOIN "MTC_CA_R_ORDER" O ON O."RunId" = U."RunId"
            LEFT JOIN "MTC_CA_R_ORDER_MAT" F ON F."RunId" = O."RunId" AND F."OrderType" = O."OrderType" AND F."OrderEntry" = O."OrderEntry" AND F."ItemCode" = '#SUBFEE'
            LEFT JOIN "OITM" M ON M."ItemCode" = O."ItemCode"
            LEFT JOIN "OITB" G ON G."ItmsGrpCod" = M."ItmsGrpCod"
           WHERE (O."RecvQty" <> 0 OR O."CostAmt" <> 0)
             AND (:nItem = 0 OR EXISTS (SELECT 1 FROM :lItem X WHERE O."ItemCode" LIKE X."P"))
             AND (:nGrp = 0 OR EXISTS (SELECT 1 FROM :lGrp X WHERE TO_NVARCHAR(M."ItmsGrpCod") = X."V"))
             AND (:nWt = 0 OR EXISTS (SELECT 1 FROM :lWt X WHERE O."WorType" = X."V"));
    IF :STYPE = '1' THEN
        SELECT "Grp" AS "物料组", MAX("GrpName") AS "物料组名称", "ItemCode" AS "产品", MAX("ItemName") AS "名称",
               COUNT(DISTINCT "FcCode") AS "有完工月数", MIN("FcCode") AS "最早账期", MAX("FcCode") AS "最晚账期",
               CAST(SUM("RecvQty") AS DECIMAL(19,6)) AS "完工数量", CAST(SUM("CostAmt") AS DECIMAL(19,2)) AS "完工成本",
               CAST(SUM("CostAmt") / NULLIF(SUM("RecvQty"), 0) AS DECIMAL(19,6)) AS "单位成本·合计",
               CAST(SUM("CostMat") / NULLIF(SUM("RecvQty"), 0) AS DECIMAL(19,6)) AS "单位成本·材料", CAST(SUM("CostLab") / NULLIF(SUM("RecvQty"), 0) AS DECIMAL(19,6)) AS "单位成本·人工",
               CAST(SUM("CostMfg") / NULLIF(SUM("RecvQty"), 0) AS DECIMAL(19,6)) AS "单位成本·制造", CAST(SUM("CostSub") / NULLIF(SUM("RecvQty"), 0) AS DECIMAL(19,6)) AS "单位成本·委外"
          FROM :ord
         GROUP BY "Grp", "ItemCode"
         ORDER BY LPAD(IFNULL("Grp", ''), 10, '0'), "ItemCode";
    ELSE
        m = SELECT "FcCode", "Grp", MAX("GrpName") AS "GrpName", "ItemCode", MAX("ItemName") AS "ItemName",
                   SUM("RecvQty") AS "Qty", SUM("CostMat") AS "Mat", SUM("CostLab") AS "Lab", SUM("CostMfg") AS "Mfg", SUM("CostSub") AS "Sub", SUM("CostAmt") AS "Amt"
              FROM :ord GROUP BY "FcCode", "Grp", "ItemCode";
        SELECT "FcCode" AS "账期", "Grp" AS "物料组", "GrpName" AS "物料组名称", "ItemCode" AS "产品", "ItemName" AS "名称",
               CAST("Qty" AS DECIMAL(19,6)) AS "完工数量", CAST("Amt" AS DECIMAL(19,2)) AS "完工成本",
               CAST("UC" AS DECIMAL(19,6)) AS "单位成本·合计",
               CAST("Mat" / NULLIF("Qty", 0) AS DECIMAL(19,6)) AS "单位成本·材料", CAST("Lab" / NULLIF("Qty", 0) AS DECIMAL(19,6)) AS "单位成本·人工",
               CAST("Mfg" / NULLIF("Qty", 0) AS DECIMAL(19,6)) AS "单位成本·制造", CAST("Sub" / NULLIF("Qty", 0) AS DECIMAL(19,6)) AS "单位成本·委外",
               CAST(("UC" - "PrevUC") * 100 / NULLIF(ABS("PrevUC"), 0) AS DECIMAL(19,2)) AS "单位成本环比 %"
          FROM (SELECT A.*, A."Amt" / NULLIF(A."Qty", 0) AS "UC",
                       LAG(A."Amt" / NULLIF(A."Qty", 0)) OVER (PARTITION BY A."ItemCode" ORDER BY A."FcCode") AS "PrevUC"
                  FROM :m A)
         ORDER BY LPAD(IFNULL("Grp", ''), 10, '0'), "ItemCode", "FcCode";
    END IF;
END
@@
