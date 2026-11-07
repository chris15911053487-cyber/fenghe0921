-- R02 加“本级分摊·制造 / 人工 / 委外”“领料带入·制造 / 人工 / 委外”六列（用户 2026-11-06）：只重建过程 MTC_CA_RPT_02_PRODCOST，定义同 21_reports.sql。离线写的，还没编译。
CREATE OR REPLACE PROCEDURE "MTC_CA_RPT_02_PRODCOST" (
    IN FcFrom NVARCHAR(10), IN FcTo NVARCHAR(10), IN Item NVARCHAR(5000), IN ItemGrp NVARCHAR(5000), IN Lvl NVARCHAR(100),
    IN WorType NVARCHAR(100), IN STYPE NVARCHAR(1))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE nItem INT; DECLARE nGrp INT; DECLARE nLvl INT; DECLARE nWt INT;
    runs = SELECT "FcCode", "RunId" FROM "MTC_CA_F_RPT_RUN"(:FcFrom, :FcTo) WHERE "RunId" IS NOT NULL;
    lItem = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Item);    SELECT COUNT(*) INTO nItem FROM :lItem;
    lGrp  = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:ItemGrp); SELECT COUNT(*) INTO nGrp FROM :lGrp;
    lLvl  = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Lvl);     SELECT COUNT(*) INTO nLvl FROM :lLvl;
    lWt   = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:WorType); SELECT COUNT(*) INTO nWt FROM :lWt;
    ord = SELECT U."FcCode", O."RunId", O."OrderType", O."OrderEntry", S."OrderNum", O."WorType", O."ItemCode", M."ItemName",
                 TO_NVARCHAR(M."ItmsGrpCod") AS "Grp", G."ItmsGrpNam" AS "GrpName", O."iLevel",
                 O."RecvQty", O."CostMat", O."CostLab", O."CostMfg", O."CostSub", O."CostAmt", O."AllocLab", O."AllocMfg",
                 IFNULL(F."CarSub", 0) AS "OwnSub"
            FROM :runs U
            JOIN "MTC_CA_R_ORDER" O ON O."RunId" = U."RunId"
            LEFT JOIN "MTC_CA_S_ORDER" S ON S."RunId" = O."RunId" AND S."OrderType" = O."OrderType" AND S."OrderEntry" = O."OrderEntry"
            LEFT JOIN "MTC_CA_R_ORDER_MAT" F ON F."RunId" = O."RunId" AND F."OrderType" = O."OrderType" AND F."OrderEntry" = O."OrderEntry" AND F."ItemCode" = '#SUBFEE'
            LEFT JOIN "OITM" M ON M."ItemCode" = O."ItemCode"
            LEFT JOIN "OITB" G ON G."ItmsGrpCod" = M."ItmsGrpCod"
           WHERE (O."RecvQty" <> 0 OR O."CostAmt" <> 0)
             AND (:nItem = 0 OR EXISTS (SELECT 1 FROM :lItem X WHERE O."ItemCode" LIKE X."P"))
             AND (:nGrp = 0 OR EXISTS (SELECT 1 FROM :lGrp X WHERE TO_NVARCHAR(M."ItmsGrpCod") = X."V"))
             AND (:nLvl = 0 OR EXISTS (SELECT 1 FROM :lLvl X WHERE TO_NVARCHAR(O."iLevel") = X."V"))
             AND (:nWt = 0 OR EXISTS (SELECT 1 FROM :lWt X WHERE O."WorType" = X."V"));
    IF :STYPE = '1' THEN
        SELECT "ItemCode" AS "产品", "ItemName" AS "名称", "FcCode" AS "账期", "OrderType" AS "订单单据", "OrderNum" AS "订单号 Num",
               "OrderEntry" AS "订单 Entry", "WorType" AS "订单类型",
               CAST("RecvQty" AS DECIMAL(19,6)) AS "完工数量",
               CAST("CostMat" AS DECIMAL(19,2)) AS "完工成本·材料", CAST("CostLab" AS DECIMAL(19,2)) AS "完工成本·人工",
               CAST("CostMfg" AS DECIMAL(19,2)) AS "完工成本·制造", CAST("CostSub" AS DECIMAL(19,2)) AS "完工成本·委外",
               CAST("CostAmt" AS DECIMAL(19,2)) AS "完工成本·合计",
               CAST("AllocMfg" AS DECIMAL(19,2)) AS "本级分摊·制造", CAST("AllocLab" AS DECIMAL(19,2)) AS "本级分摊·人工", CAST("OwnSub" AS DECIMAL(19,2)) AS "本级分摊·委外",
               CAST("CostMfg" - "AllocMfg" AS DECIMAL(19,2)) AS "领料带入·制造", CAST("CostLab" - "AllocLab" AS DECIMAL(19,2)) AS "领料带入·人工", CAST("CostSub" - "OwnSub" AS DECIMAL(19,2)) AS "领料带入·委外",
               CAST("CostAmt" / NULLIF("RecvQty", 0) AS DECIMAL(19,6)) AS "单位成本·合计",
               CAST("CostMat" / NULLIF("RecvQty", 0) AS DECIMAL(19,6)) AS "单位成本·材料", CAST("CostLab" / NULLIF("RecvQty", 0) AS DECIMAL(19,6)) AS "单位成本·人工",
               CAST("CostMfg" / NULLIF("RecvQty", 0) AS DECIMAL(19,6)) AS "单位成本·制造", CAST("CostSub" / NULLIF("RecvQty", 0) AS DECIMAL(19,6)) AS "单位成本·委外"
          FROM :ord ORDER BY "ItemCode", "FcCode", "OrderType", "OrderEntry";
    ELSE
        SELECT "Grp" AS "物料组", MAX("GrpName") AS "物料组名称", "ItemCode" AS "产品", MAX("ItemName") AS "名称", MAX("iLevel") AS "层级",
               COUNT(*) AS "订单数", CAST(SUM("RecvQty") AS DECIMAL(19,6)) AS "完工数量",
               CAST(SUM("CostMat") AS DECIMAL(19,2)) AS "完工成本·材料", CAST(SUM("CostLab") AS DECIMAL(19,2)) AS "完工成本·人工",
               CAST(SUM("CostMfg") AS DECIMAL(19,2)) AS "完工成本·制造", CAST(SUM("CostSub") AS DECIMAL(19,2)) AS "完工成本·委外",
               CAST(SUM("CostAmt") AS DECIMAL(19,2)) AS "完工成本·合计",
               CAST(SUM("AllocMfg") AS DECIMAL(19,2)) AS "本级分摊·制造", CAST(SUM("AllocLab") AS DECIMAL(19,2)) AS "本级分摊·人工", CAST(SUM("OwnSub") AS DECIMAL(19,2)) AS "本级分摊·委外",
               CAST(SUM("CostMfg" - "AllocMfg") AS DECIMAL(19,2)) AS "领料带入·制造", CAST(SUM("CostLab" - "AllocLab") AS DECIMAL(19,2)) AS "领料带入·人工", CAST(SUM("CostSub" - "OwnSub") AS DECIMAL(19,2)) AS "领料带入·委外",
               CAST(SUM("CostAmt") / NULLIF(SUM("RecvQty"), 0) AS DECIMAL(19,6)) AS "单位成本·合计",
               CAST(SUM("CostMat") / NULLIF(SUM("RecvQty"), 0) AS DECIMAL(19,6)) AS "单位成本·材料", CAST(SUM("CostLab") / NULLIF(SUM("RecvQty"), 0) AS DECIMAL(19,6)) AS "单位成本·人工",
               CAST(SUM("CostMfg") / NULLIF(SUM("RecvQty"), 0) AS DECIMAL(19,6)) AS "单位成本·制造", CAST(SUM("CostSub") / NULLIF(SUM("RecvQty"), 0) AS DECIMAL(19,6)) AS "单位成本·委外",
               CAST(SUM("CostMat") * 100 / NULLIF(SUM("CostAmt"), 0) AS DECIMAL(19,2)) AS "构成 %·材料", CAST(SUM("CostLab") * 100 / NULLIF(SUM("CostAmt"), 0) AS DECIMAL(19,2)) AS "构成 %·人工",
               CAST(SUM("CostMfg") * 100 / NULLIF(SUM("CostAmt"), 0) AS DECIMAL(19,2)) AS "构成 %·制造", CAST(SUM("CostSub") * 100 / NULLIF(SUM("CostAmt"), 0) AS DECIMAL(19,2)) AS "构成 %·委外"
          FROM :ord
         GROUP BY "Grp", "ItemCode"
         ORDER BY LPAD(IFNULL("Grp", ''), 10, '0'), "ItemCode";
    END IF;
END
@@
