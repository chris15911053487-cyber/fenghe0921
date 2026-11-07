-- R24 其他领用明细表（用户 2026-11-06）：只新建过程 MTC_CA_RPT_24_OTHERUSE，定义同 21_reports.sql。离线写的，还没编译。依赖 @MTC_CSIGE1、@MTC_CSOIGE、@MTC_CSIGN1、@MTC_CSOIGN。
CREATE OR REPLACE PROCEDURE "MTC_CA_RPT_24_OTHERUSE" (
    IN FcFrom NVARCHAR(10), IN FcTo NVARCHAR(10), IN Item NVARCHAR(5000), IN ItemGrp NVARCHAR(5000), IN Busi NVARCHAR(500),
    IN Dept NVARCHAR(500), IN CostType NVARCHAR(100), IN STYPE NVARCHAR(1))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE nItem INT; DECLARE nGrp INT; DECLARE nBusi INT; DECLARE nDept INT; DECLARE nTr INT;
    DECLARE dB DATE; DECLARE dE DATE;
    runs = SELECT "FcCode", "RunId", "D0", "D1" FROM "MTC_CA_F_RPT_RUN"(:FcFrom, :FcTo) WHERE "RunId" IS NOT NULL;
    SELECT MIN("D0"), MAX("D1") INTO dB, dE FROM :runs;
    lItem = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Item);    SELECT COUNT(*) INTO nItem FROM :lItem;
    lGrp  = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:ItemGrp); SELECT COUNT(*) INTO nGrp FROM :lGrp;
    lBusi = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Busi);    SELECT COUNT(*) INTO nBusi FROM :lBusi;
    lDept = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Dept);    SELECT COUNT(*) INTO nDept FROM :lDept;
    lTr   = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:CostType); SELECT COUNT(*) INTO nTr FROM :lTr;
    lnx = SELECT U."FcCode", L."RunId", L."LineId", D."ObjType", D."DocEntry", D."DocNum", D."LineNum", D."DocDate", D."BusiType", L."TransCode",
                 L."ItemCode", M."ItemName", M."ItmsGrpCod", I."iLevel", L."Qty", L."Price", L."Amount", L."MatAmt", L."LabAmt", L."MfgAmt", L."SubAmt",
                 L."PriceSrc", CASE WHEN L."IsShared" = 'Y' THEN L."PoolCode" END AS "SharedPool",
                 D."OcrCode", D."WhsCode", D."AcctCode", D."BaseType", D."BaseEntry", D."BaseLine"
            FROM :runs U
            JOIN "MTC_CA_R_LINE" L ON L."RunId" = U."RunId"
            JOIN "MTC_CA_S_LINE" D ON D."RunId" = L."RunId" AND D."LineId" = L."LineId"
            LEFT JOIN "MTC_CA_R_ITEM" I ON I."RunId" = L."RunId" AND I."ItemCode" = L."ItemCode"
            LEFT JOIN "OITM" M ON M."ItemCode" = L."ItemCode"
           WHERE L."TransCode" IN ('I04', 'O04', 'I10', 'O10')
             AND (:nItem = 0 OR EXISTS (SELECT 1 FROM :lItem X WHERE L."ItemCode" LIKE X."P"))
             AND (:nGrp = 0 OR EXISTS (SELECT 1 FROM :lGrp X WHERE TO_NVARCHAR(M."ItmsGrpCod") = X."V"))
             AND (:nBusi = 0 OR EXISTS (SELECT 1 FROM :lBusi X WHERE D."BusiType" LIKE X."P"))
             AND (:nDept = 0 OR EXISTS (SELECT 1 FROM :lDept X WHERE D."OcrCode" LIKE X."P"))
             AND (:nTr = 0 OR EXISTS (SELECT 1 FROM :lTr X WHERE L."TransCode" = X."V"));
    IF :STYPE = '0' THEN
        SELECT L."BusiType" AS "领用类型编码", MAX(C."Name") AS "领用类型名称", L."OcrCode" AS "部门编码", MAX(P."PrcName") AS "部门名称",
               L."AcctCode" AS "其他领用科目编码", MAX(A."AcctName") AS "其他领用科目名称", COUNT(*) AS "行数",
               CAST(-SUM(L."Amount") AS DECIMAL(19,2)) AS "成本金额",
               CAST(-SUM(L."MatAmt") AS DECIMAL(19,2)) AS "构成·材料", CAST(-SUM(L."LabAmt") AS DECIMAL(19,2)) AS "构成·人工",
               CAST(-SUM(L."MfgAmt") AS DECIMAL(19,2)) AS "构成·制造", CAST(-SUM(L."SubAmt") AS DECIMAL(19,2)) AS "构成·委外"
          FROM :lnx L
          LEFT JOIN "@U_CIOTRN" C ON C."Code" = L."BusiType"
          LEFT JOIN "OPRC" P ON P."PrcCode" = L."OcrCode"
          LEFT JOIN "OACT" A ON A."AcctCode" = L."AcctCode"
         GROUP BY L."BusiType", L."OcrCode", L."AcctCode"
         ORDER BY L."BusiType", L."OcrCode", L."AcctCode";
    ELSE
        ge = SELECT TO_NVARCHAR(T0."ObjType") AS "ObjType", T0."DocEntry", T0."LineNum", MAX(T0."Project") AS "Project", MAX(T."CreateDate") AS "CreateDate",
                    STRING_AGG(TO_NVARCHAR(T2."U_Remark"), ',') AS "Remark", STRING_AGG(TO_NVARCHAR(T2."U_Remark2"), ',') AS "Remark2", STRING_AGG(TO_NVARCHAR(T2."U_Remark3"), ',') AS "Remark3",
                    STRING_AGG(TO_NVARCHAR(COALESCE(U."U_NAME", T."U_Creator")), ',') AS "Creator", STRING_AGG(TO_NVARCHAR(T2."U_SupNum"), ',') AS "SupNum",
                    MAX(TO_NVARCHAR(T2."U_OARequestID")) AS "OaId"
               FROM "IGE1" T0
               JOIN "OIGE" T ON T0."DocEntry" = T."DocEntry"
               LEFT JOIN "@MTC_CSIGE1" T1 ON T1."Object" = T0."U_BaseType" AND T1."DocEntry" = T0."U_BaseEntry" AND T1."LineId" = T0."U_BaseLine"
               LEFT JOIN "@MTC_CSOIGE" T2 ON T2."DocEntry" = T1."DocEntry"
               LEFT JOIN "OUSR" U ON U."USER_CODE" = T2."U_Creator"
              WHERE T."DocDate" BETWEEN :dB AND :dE
              GROUP BY T0."ObjType", T0."DocEntry", T0."LineNum";
        gn = SELECT TO_NVARCHAR(T0."ObjType") AS "ObjType", T0."DocEntry", T0."LineNum", MAX(T0."Project") AS "Project", MAX(T."CreateDate") AS "CreateDate",
                    STRING_AGG(TO_NVARCHAR(T2."U_Remark"), ',') AS "Remark", STRING_AGG(TO_NVARCHAR(T2."U_Remark2"), ',') AS "Remark2", STRING_AGG(TO_NVARCHAR(T2."U_Remark3"), ',') AS "Remark3",
                    STRING_AGG(TO_NVARCHAR(COALESCE(U."U_NAME", T."U_Creator")), ',') AS "Creator", STRING_AGG(TO_NVARCHAR(T2."U_SupNum"), ',') AS "SupNum"
               FROM "IGN1" T0
               JOIN "OIGN" T ON T0."DocEntry" = T."DocEntry"
               LEFT JOIN "@MTC_CSIGN1" T1 ON T1."Object" = T0."U_BaseType" AND T1."DocEntry" = T0."U_BaseEntry" AND T1."LineId" = T0."U_BaseLine"
               LEFT JOIN "@MTC_CSOIGN" T2 ON T2."DocEntry" = T1."DocEntry"
               LEFT JOIN "OUSR" U ON U."USER_CODE" = T2."U_Creator"
              WHERE T."DocDate" BETWEEN :dB AND :dE
              GROUP BY T0."ObjType", T0."DocEntry", T0."LineNum";
        ext = SELECT "ObjType", "DocEntry", "LineNum", "Project", "CreateDate", "Remark", "Remark2", "Remark3", "Creator", "SupNum", "OaId" FROM :ge
              UNION ALL
              SELECT "ObjType", "DocEntry", "LineNum", "Project", "CreateDate", "Remark", "Remark2", "Remark3", "Creator", "SupNum", CAST(NULL AS NVARCHAR(100)) FROM :gn;
        vd = SELECT TO_NVARCHAR("ObjType") AS "ObjType", TO_NVARCHAR("DocEntry") AS "DocEntry", TO_NVARCHAR("LineNum") AS "LineNum", TO_NVARCHAR("BaseRef") AS "BaseRef"
               FROM "MTC_VIEW_Document" WHERE TO_NVARCHAR("ObjType") IN ('59', '60') AND "DocDate" BETWEEN :dB AND :dE;
        SELECT L."FcCode" AS "账期", L."ObjType" AS "单据类型", T9."DocName" AS "单据类型名称", L."DocEntry" AS "单号 Entry", L."DocNum" AS "单号 Num", L."LineNum" AS "行号",
               L."DocDate" AS "过账日期", L."BusiType" AS "领用类型编码", C."Name" AS "领用类型名称", L."TransCode" AS "成本类型编码",
               L."ItemCode" AS "物料编码", L."ItemName" AS "物料名称", TO_NVARCHAR(L."ItmsGrpCod") AS "物料组编码",
               CAST(-L."Qty" AS DECIMAL(19,6)) AS "数量", CAST(L."Price" AS DECIMAL(19,6)) AS "成本单价", CAST(-L."Amount" AS DECIMAL(19,2)) AS "成本金额",
               CAST(-L."MatAmt" AS DECIMAL(19,2)) AS "构成·材料", CAST(-L."LabAmt" AS DECIMAL(19,2)) AS "构成·人工",
               CAST(-L."MfgAmt" AS DECIMAL(19,2)) AS "构成·制造", CAST(-L."SubAmt" AS DECIMAL(19,2)) AS "构成·委外",
               L."OcrCode" AS "部门编码", P."PrcName" AS "部门名称", E."Project" AS "研发项目编码", R."PrjName" AS "研发项目名称",
               L."SharedPool" AS "公摊费用池", L."WhsCode" AS "仓库代码", W."WhsName" AS "仓库名称", L."iLevel" AS "层级",
               G."StockAct" AS "库存科目编码", A1."AcctName" AS "库存科目名称", L."AcctCode" AS "其他领用科目编码", A2."AcctName" AS "其他领用科目名称",
               L."BaseType" AS "来源类型", L."BaseEntry" AS "来源单号 Entry", V."BaseRef" AS "来源单号 Num", L."BaseLine" AS "来源行号",
               E."Remark" AS "备注", E."Remark2" AS "领用说明", E."Remark3" AS "领用人", E."CreateDate" AS "创建日期", E."Creator" AS "创建人",
               CASE WHEN L."ObjType" = '60' THEN E."SupNum" END AS "出库申请单号", CASE WHEN L."ObjType" = '59' THEN E."SupNum" END AS "入库申请单号",
               L."PriceSrc" AS "定价来源", E."OaId" AS "领料申请表ID"
          FROM :lnx L
          LEFT JOIN "MTC_DocType" T9 ON T9."ObjType" = L."ObjType"
          LEFT JOIN "@U_CIOTRN" C ON C."Code" = L."BusiType"
          LEFT JOIN "OPRC" P ON P."PrcCode" = L."OcrCode"
          LEFT JOIN "OWHS" W ON W."WhsCode" = L."WhsCode"
          LEFT JOIN :ext E ON E."ObjType" = L."ObjType" AND E."DocEntry" = L."DocEntry" AND E."LineNum" = L."LineNum"
          LEFT JOIN :vd V ON V."ObjType" = L."ObjType" AND V."DocEntry" = TO_NVARCHAR(L."DocEntry") AND V."LineNum" = TO_NVARCHAR(L."LineNum")
          LEFT JOIN "OPRJ" R ON R."PrjCode" = E."Project"
          LEFT JOIN (SELECT "PeriodCat", "ItmsGrpCod", MAX("StockAct") AS "StockAct" FROM "OGAR" GROUP BY "PeriodCat", "ItmsGrpCod") G
                 ON G."PeriodCat" = LEFT(L."FcCode", 4) AND G."ItmsGrpCod" = L."ItmsGrpCod"
          LEFT JOIN "OACT" A1 ON A1."AcctCode" = G."StockAct"
          LEFT JOIN "OACT" A2 ON A2."AcctCode" = L."AcctCode"
         ORDER BY L."DocDate", L."ObjType", L."DocEntry", L."LineNum", L."LineId";
    END IF;
END
@@
