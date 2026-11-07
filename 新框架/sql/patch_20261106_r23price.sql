-- R23 单据行加“销售单价”“成本单价”两列（用户 2026-11-06）：只重建过程 MTC_CA_RPT_23_MARGINTREND，定义同 21_reports.sql
CREATE OR REPLACE PROCEDURE "MTC_CA_RPT_23_MARGINTREND" (
    IN FcFrom NVARCHAR(10), IN FcTo NVARCHAR(10), IN Item NVARCHAR(5000), IN ItemGrp NVARCHAR(5000), IN Cust NVARCHAR(5000),
    IN CustType NVARCHAR(200), IN SalType NVARCHAR(500), IN InclSample NVARCHAR(1), IN Basis NVARCHAR(1), IN STYPE NVARCHAR(1))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE bs NVARCHAR(1);
    DECLARE dA DATE; DECLARE dB DATE; DECLARE f0 NVARCHAR(10); DECLARE f1 NVARCHAR(10);
    DECLARE nItem INT; DECLARE nGrp INT; DECLARE nCust INT; DECLARE nCt INT; DECLARE nSt INT;
    f0 := NULLIF(TRIM(IFNULL(:FcFrom, '')), ''); f1 := NULLIF(TRIM(IFNULL(:FcTo, '')), '');
    IF :f0 IS NULL THEN SELECT MIN("Code") INTO f0 FROM "OFPR"; END IF;
    IF :f1 IS NULL THEN f1 := TO_NVARCHAR(CURRENT_DATE, 'YYYY-MM'); END IF;
    SELECT MIN(TO_DATE("F_RefDate")), MAX(TO_DATE("T_RefDate")) INTO dA, dB FROM "OFPR" WHERE "Code" BETWEEN :f0 AND :f1;
    bs := CASE WHEN :Basis = '1' THEN '1' ELSE '0' END;
    -- 已结账账期：已生成凭单、B1 已锁定且已计算、承接及以前的历史期。EndTime = 该期所用运行完成时间
    pd = SELECT "FcCode", "EndTime" FROM "MTC_CA_F_RPT_RUN"(:f0, :f1)
          WHERE "PStatus" IN ('POSTED', 'HIST') OR ("PStatus" = 'LOCKED' AND "RunId" IS NOT NULL);
    lItem = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Item);     SELECT COUNT(*) INTO nItem FROM :lItem;
    lGrp  = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:ItemGrp);  SELECT COUNT(*) INTO nGrp FROM :lGrp;
    lCust = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Cust);     SELECT COUNT(*) INTO nCust FROM :lCust;
    lCt   = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:CustType); SELECT COUNT(*) INTO nCt FROM :lCt;
    lSt   = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:SalType);  SELECT COUNT(*) INTO nSt FROM :lSt;
    al = SELECT E.*, CAST(CASE WHEN E."Kind" = 'NOI' THEN '(未归属产品)' ELSE E."ItemCode" END AS NVARCHAR(50)) AS "KItem",
                TO_NVARCHAR(I."ItmsGrpCod") AS "Grp", G."ItmsGrpNam" AS "GrpName", I."ItemName", C."CardName"
           FROM "MTC_CA_F_SALE_TREND"(:dA, :dB, :bs) E
           LEFT JOIN "OITM" I ON I."ItemCode" = E."ItemCode"
           LEFT JOIN "OITB" G ON G."ItmsGrpCod" = I."ItmsGrpCod"
           LEFT JOIN "OCRD" C ON C."CardCode" = E."CardCode";
    -- 单据创建日：只用来标“结账后补单”，随时看不用
    crt = SELECT '13' AS "ObjType", "DocEntry", "CreateDate" FROM "OINV" UNION ALL SELECT '14', "DocEntry", "CreateDate" FROM "ORIN"
          UNION ALL SELECT '15', "DocEntry", "CreateDate" FROM "ODLN" UNION ALL SELECT '16', "DocEntry", "CreateDate" FROM "ORDN";
    f = SELECT A.*, CASE WHEN :bs = '1' AND TO_DATE(C."CreateDate") > TO_DATE(P."EndTime") THEN 1 ELSE 0 END AS "Late"
          FROM :al A
          LEFT JOIN :pd P ON P."FcCode" = A."FcCode"
          LEFT JOIN :crt C ON C."ObjType" = A."ObjType" AND C."DocEntry" = A."DocEntry"
         WHERE (IFNULL(:InclSample, 'N') = 'Y' OR A."IsSample" = 'N')
           AND (:bs = '0' OR P."FcCode" IS NOT NULL)
           AND (:nItem = 0 OR EXISTS (SELECT 1 FROM :lItem X WHERE A."KItem" LIKE X."P"))
           AND (:nGrp = 0 OR EXISTS (SELECT 1 FROM :lGrp X WHERE A."Grp" = X."V"))
           AND (:nCust = 0 OR EXISTS (SELECT 1 FROM :lCust X WHERE A."CardCode" LIKE X."P"))
           AND (:nCt = 0 OR EXISTS (SELECT 1 FROM :lCt X WHERE A."CustType" = X."V"))
           AND (:nSt = 0 OR EXISTS (SELECT 1 FROM :lSt X WHERE A."SalType" = X."V"));
    IF :STYPE = '3' THEN
        SELECT F."FcCode" AS "账期", CASE F."Kind" WHEN 'INV' THEN '已开票' WHEN 'ACC' THEN CASE WHEN :bs = '1' THEN '暂估变动' ELSE '暂估（至今未开票）' END ELSE '未归属' END AS "类别",
               CASE F."ObjType" WHEN '13' THEN '应收发票' WHEN '14' THEN '应收贷项' WHEN '15' THEN '交货' ELSE '销售退货' END AS "单据",
               COALESCE(H13."DocNum", H14."DocNum", H15."DocNum", H16."DocNum") AS "单号 Num", F."DocEntry" AS "单号 Entry", F."LineNum" AS "行号", F."DocDate" AS "日期",
               F."CardCode" AS "客户", F."CardName" AS "客户名称", F."CustType" AS "客户类型", F."SalType" AS "销售订单类型", F."IsSample" AS "样品",
               F."ItemCode" AS "物料", F."ItemName" AS "物料名称", F."Qty" AS "数量",
               CAST(F."Rev" / NULLIF(F."Qty", 0) AS DECIMAL(19,6)) AS "销售单价", CAST(F."Rev" AS DECIMAL(19,2)) AS "收入",   -- 单价 = 金额 ÷ 数量（用户 2026-11-06），纯金额行没有数量时留空
               CAST(CASE WHEN F."NoCost" = 1 THEN NULL ELSE F."Cost" / NULLIF(F."Qty", 0) END AS DECIMAL(19,6)) AS "成本单价", CAST(F."Cost" AS DECIMAL(19,2)) AS "成本",   -- 缺成本单价的行留空，不显示 0
               CAST(F."Rev" - F."Cost" AS DECIMAL(19,2)) AS "毛利", F."SrcKey" AS "来源行",
               CASE WHEN F."NoCost" = 1 THEN '缺成本单价' WHEN F."NoPrice" = 1 THEN '交货行金额为 0' WHEN F."Late" = 1 THEN '结账后补单' END AS "说明"
          FROM :f F
          LEFT JOIN "OINV" H13 ON F."ObjType" = '13' AND H13."DocEntry" = F."DocEntry"
          LEFT JOIN "ORIN" H14 ON F."ObjType" = '14' AND H14."DocEntry" = F."DocEntry"
          LEFT JOIN "ODLN" H15 ON F."ObjType" = '15' AND H15."DocEntry" = F."DocEntry"
          LEFT JOIN "ORDN" H16 ON F."ObjType" = '16' AND H16."DocEntry" = F."DocEntry"
         ORDER BY F."DocDate", F."ObjType", F."DocEntry", F."LineNum", F."Kind";
    ELSE
        -- 分组键先在子查询里算好（HANA 不认 SELECT / GROUP BY 中带参数的 CASE 是同一表达式）
        SELECT F."KFc" AS "账期", F."KGrp" AS "物料组", MAX(F."KGrpName") AS "物料组名称", F."KIt" AS "物料", MAX(F."KName") AS "物料名称",
               CAST(SUM(F."QtyInv") AS DECIMAL(19,6)) AS "数量·已开票", CAST(SUM(F."QtyAcc") AS DECIMAL(19,6)) AS "数量·暂估", CAST(SUM(F."QtyInv" + F."QtyAcc") AS DECIMAL(19,6)) AS "数量·合计",
               CAST(SUM(F."RevInv") AS DECIMAL(19,2)) AS "收入·已开票", CAST(SUM(F."RevAcc") AS DECIMAL(19,2)) AS "收入·暂估", CAST(SUM(F."Rev") AS DECIMAL(19,2)) AS "收入·合计",
               CAST(SUM(F."CostInv") AS DECIMAL(19,2)) AS "成本·已开票", CAST(SUM(F."CostAcc") AS DECIMAL(19,2)) AS "成本·暂估", CAST(SUM(F."Cost") AS DECIMAL(19,2)) AS "成本·合计",
               CAST(SUM(F."Rev") - SUM(F."Cost") AS DECIMAL(19,2)) AS "毛利",
               CAST((SUM(F."Rev") - SUM(F."Cost")) * 100 / NULLIF(SUM(F."Rev"), 0) AS DECIMAL(19,2)) AS "毛利率 %",
               CAST(SUM(F."Rev") / NULLIF(SUM(F."QtyInv" + F."QtyAcc"), 0) AS DECIMAL(19,6)) AS "单位售价",
               CAST(SUM(F."Cost") / NULLIF(SUM(F."QtyInv" + F."QtyAcc"), 0) AS DECIMAL(19,6)) AS "单位成本",
               SUM(F."NoCost") AS "缺成本单价行数", SUM(F."NoPrice") AS "缺销售单价行数", SUM(F."Late") AS "结账后补单行数"
          FROM (SELECT B."Rev", B."Cost", B."NoCost", B."NoPrice", B."Late",
                       CASE WHEN :STYPE = '1' THEN NULL ELSE B."FcCode" END AS "KFc",
                       CASE WHEN :STYPE = '2' THEN NULL ELSE B."KItem" END AS "KIt",
                       CASE WHEN :STYPE = '2' OR B."Kind" = 'NOI' THEN NULL ELSE B."Grp" END AS "KGrp",
                       CASE WHEN :STYPE = '2' OR B."Kind" = 'NOI' THEN NULL ELSE B."GrpName" END AS "KGrpName",
                       CASE WHEN :STYPE = '2' THEN NULL WHEN B."Kind" = 'NOI' THEN '服务、直接开票、纯金额贷项' ELSE B."ItemName" END AS "KName",
                       CASE WHEN B."Kind" = 'ACC' THEN 0 ELSE B."Qty" END AS "QtyInv", CASE WHEN B."Kind" = 'ACC' THEN B."Qty" ELSE 0 END AS "QtyAcc",
                       CASE WHEN B."Kind" = 'ACC' THEN 0 ELSE B."Rev" END AS "RevInv", CASE WHEN B."Kind" = 'ACC' THEN B."Rev" ELSE 0 END AS "RevAcc",
                       CASE WHEN B."Kind" = 'ACC' THEN 0 ELSE B."Cost" END AS "CostInv", CASE WHEN B."Kind" = 'ACC' THEN B."Cost" ELSE 0 END AS "CostAcc"
                  FROM :f B) F
         GROUP BY F."KFc", F."KGrp", F."KIt"
         ORDER BY LPAD(IFNULL(F."KGrp", 'zzzzzzzzzz'), 10, '0'), F."KIt", F."KFc";
    END IF;
END
@@
