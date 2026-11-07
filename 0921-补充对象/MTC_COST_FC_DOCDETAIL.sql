CREATE FUNCTION MTC_COST_FC_DOCDETAIL
(
     BPLId     INT
    ,FcCode NVARCHAR(50)
    ,ItemCode NVARCHAR(50) DEFAULT ''
)
RETURNS TABLE (
     "BPLId"            INT
    ,"ObjType"            NVARCHAR(50)
    ,"DocEntry"            INT
    ,"DocNum"            INT
    ,"CardCode"            NVARCHAR(50)
    ,"CardName"            NVARCHAR(50)
    ,"LineNum"            INT
    ,"FcCode"            NVARCHAR(7)
    ,"DocDate"            DATE
    ,"CostCode"            NVARCHAR(50)        --归入成本计价类型
    ,"TransCode"        NVARCHAR(50)        --实际交易类型
    ,"BaseType"            NVARCHAR(50)
    ,"BaseEntry"        INT
    ,"BaseNum"            NVARCHAR(50)
    ,"BaseLine"            INT
    ,"ItemCode"            NVARCHAR(100)
    ,"ItemName"            NVARCHAR(254)
    ,"EvalSystem"        NVARCHAR(50)
    ,"ItmsGrpCod"        NVARCHAR(100)
    ,"CalType"            NVARCHAR(100)    --成本计价类型
    ,"Quantity"            DECIMAL(19,6)
    ,"Amount"            DECIMAL(19,6)
    ,"Price"            DECIMAL(19,6)
    ,"WhsCode"            NVARCHAR(50)
    ,"WorType"            NVARCHAR(50)
    ,"WorEntry"            INT
    ,"WorNum"            NVARCHAR(50)
    ,"WorLineNum"        INT
    ,"CJCode"            NVARCHAR(50)
    ,"CJName"            NVARCHAR(50)
    ,"OcrCode1"            NVARCHAR(50)
    ,"OcrCode2"            NVARCHAR(50)
    ,"OcrCode3"            NVARCHAR(50)
    ,"OcrCode4"            NVARCHAR(50)
    ,"OcrCode5"            NVARCHAR(50)
    ,"User"                NVARCHAR(100)
    ,"TransId"            INT
    ,"Comments"            NVARCHAR(500)
)
LANGUAGE SQLSCRIPT
AS

BEGIN

    /*
     * created BY Chris.li 2024.11.23
     * 获取成本计算的所有出入库的单据
     * SELECT * FROM "MTC_COST_FC_DOCDETAIL"(0,'2024-01');
     * 数量Quantity和金额Amount展示形式 入库表示正数  出库表示负数
    */

    TMP_DETAIL=
    --20 采购收货单
    SELECT T0."BPLId",T0."ObjType",T0."DocEntry",T0."DocNum",T0."CardCode",T0."CardName",T1."LineNum",LEFT(T0."DocDate",7) AS "FcCode"
    ,T0."DocDate",'' AS "CostCode",'' AS "TransCode",TO_CHAR(T1."BaseType") AS "BaseType",T1."BaseEntry",T1."BaseRef" AS "BaseNum",T1."BaseLine"
    ,T1."ItemCode",T1."Dscription" AS "ItemName",T2."EvalSystem",T2."ItmsGrpCod",T3."U_ItemGrpType" AS "CalType"
    ,CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END * T1."Quantity" AS "Quantity"
    ,CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END * T1."LineTotal" AS "Amount",T1."Price",T1."WhsCode"
    ,NULL AS "WorType",NULL AS "WorEntry",NULL AS "WorNum",NULL AS "WorLineNum"
    ,NULL AS "CJCode",NULL AS "CJName"
    ,T1."OcrCode" AS "OcrCode1",T1."OcrCode2",T1."OcrCode3",T1."OcrCode4",T1."OcrCode5"
    ,T0."UserSign" AS "User",T0."TransId",T0."Comments"
    FROM "OPDN" T0
    JOIN "PDN1" T1 ON T0."DocEntry"=T1."DocEntry"
    JOIN "OITM" T2 ON T1."ItemCode"=T2."ItemCode"
    JOIN "OITB" T3 ON T2."ItmsGrpCod"=T3."ItmsGrpCod"
    WHERE 1=1
    AND LEFT(T0."DocDate",7) = :FcCode
    AND (T1."ItemCode" = :ItemCode OR :ItemCode = '')

    --21 采购退货单
    UNION ALL
    SELECT T0."BPLId",T0."ObjType",T0."DocEntry",T0."DocNum",T0."CardCode",T0."CardName",T1."LineNum",LEFT(T0."DocDate",7) AS "FcCode"
    ,T0."DocDate",'' AS "CostCode",'' AS "TransCode",TO_CHAR(T1."BaseType") AS "BaseType",T1."BaseEntry",T1."BaseRef" AS "BaseNum",T1."BaseLine"
    ,T1."ItemCode",T1."Dscription" AS "ItemName",T2."EvalSystem",T2."ItmsGrpCod",T3."U_ItemGrpType" AS "CalType"
    ,CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END * T1."Quantity" AS "Quantity"
    ,CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END * T1."LineTotal" AS "Amount",T1."Price",T1."WhsCode"
    ,NULL AS "WorType",NULL AS "WorEntry",NULL AS "WorNum",NULL AS "WorLineNum"
    ,NULL AS "CJCode",NULL AS "CJName"
    ,T1."OcrCode" AS "OcrCode1",T1."OcrCode2",T1."OcrCode3",T1."OcrCode4",T1."OcrCode5"
    ,T0."UserSign" AS "User",T0."TransId",T0."Comments"
    FROM "ORPD" T0
    JOIN "RPD1" T1 ON T0."DocEntry"=T1."DocEntry"
    JOIN "OITM" T2 ON T1."ItemCode"=T2."ItemCode"
    JOIN "OITB" T3 ON T2."ItmsGrpCod"=T3."ItmsGrpCod"
    WHERE 1=1
    AND LEFT(T0."DocDate",7) = :FcCode
    AND (T1."ItemCode" = :ItemCode OR :ItemCode = '')

    --18  应付发票
    UNION ALL
    SELECT T0."BPLId",T0."ObjType",T0."DocEntry",T0."DocNum",T0."CardCode",T0."CardName",T1."LineNum",LEFT(T0."DocDate",7) AS "FcCode"
    ,T0."DocDate",'' AS "CostCode",'' AS "TransCode",TO_CHAR(T1."BaseType"),T1."BaseEntry",T1."BaseRef" AS "BaseNum",T1."BaseLine"
    ,T1."ItemCode",T1."Dscription" AS "ItemName",T2."EvalSystem",T2."ItmsGrpCod",T3."U_ItemGrpType" AS "CalType"
    ,CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END * T1."Quantity" AS "Quantity"
    ,CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END * T1."LineTotal" AS "Amount",T1."Price",T1."WhsCode"
    ,NULL AS "WorType",NULL AS "WorEntry",NULL AS "WorNum",NULL AS "WorLineNum"
    ,NULL AS "CJCode",NULL AS "CJName"
    ,T1."OcrCode" AS "OcrCode1",T1."OcrCode2",T1."OcrCode3",T1."OcrCode4",T1."OcrCode5"
    ,T0."UserSign" AS "User",T0."TransId",T0."Comments"
    FROM "OPCH" T0
    JOIN "PCH1" T1 ON T0."DocEntry"=T1."DocEntry"
    JOIN "OITM" T2 ON T1."ItemCode"=T2."ItemCode"
    JOIN "OITB" T3 ON T2."ItmsGrpCod"=T3."ItmsGrpCod"
    WHERE 1=1
    AND LEFT(T0."DocDate",7) = :FcCode
    AND (T1."ItemCode" = :ItemCode OR :ItemCode = '')

    --19 应付贷项凭证
    UNION ALL
    SELECT T0."BPLId",T0."ObjType",T0."DocEntry",T0."DocNum",T0."CardCode",T0."CardName",T1."LineNum",LEFT(T0."DocDate",7) AS "FcCode"
    ,T0."DocDate",'' AS "CostCode",'' AS "TransCode",TO_CHAR(T1."BaseType"),T1."BaseEntry",T1."BaseRef" AS "BaseNum",T1."BaseLine"
    ,T1."ItemCode",T1."Dscription" AS "ItemName",T2."EvalSystem",T2."ItmsGrpCod",T3."U_ItemGrpType" AS "CalType"
    ,CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END * T1."Quantity" AS "Quantity"
    ,CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END * T1."LineTotal" AS "Amount",T1."Price",T1."WhsCode"
    ,NULL AS "WorType",NULL AS "WorEntry",NULL AS "WorNum",NULL AS "WorLineNum"
    ,NULL AS "CJCode",NULL AS "CJName"
    ,T1."OcrCode" AS "OcrCode1",T1."OcrCode2",T1."OcrCode3",T1."OcrCode4",T1."OcrCode5"
    ,T0."UserSign" AS "User",T0."TransId",T0."Comments"
    FROM "ORPC" T0
    JOIN "RPC1" T1 ON T0."DocEntry"=T1."DocEntry"
    JOIN "OITM" T2 ON T1."ItemCode"=T2."ItemCode"
    JOIN "OITB" T3 ON T2."ItmsGrpCod"=T3."ItmsGrpCod"
    WHERE 1=1
    AND LEFT(T0."DocDate",7) = :FcCode
    AND (T1."ItemCode" = :ItemCode OR :ItemCode = '')

    --59  库存收货&生产收货
    UNION ALL
    SELECT T0."BPLId",T0."ObjType",T0."DocEntry",T0."DocNum",T0."CardCode",T0."CardName",T1."LineNum",LEFT(T0."DocDate",7) AS "FcCode"
    ,T0."DocDate",'' AS "CostCode",T0."U_TrsName" AS "TransCode",
     CASE WHEN T1."BaseType"=-1 AND T1."U_OWORType"='202' THEN '202' WHEN T1."BaseType"=-1 AND T1."U_OWORType"='MTC_OWOR' THEN 'MTC_OWOR' ELSE TO_CHAR(T1."BaseType") END AS "BaseType",
     COALESCE(T4."DocEntry",T1."BaseEntry",T1."U_MTCOWORNum") AS "BaseEntry",
     TO_CHAR(COALESCE(T4."DocNum",T1."BaseRef",T1."U_MTCOWORNum")) AS "BaseNum",
     CASE WHEN T1."BaseType"=-1 AND T1."U_OWORType"='202' THEN T1."U_OWORLineNum" WHEN T1."BaseType"=-1 AND T1."U_OWORType"='MTC_OWOR' THEN T1."U_MTCOWORLineNum" ELSE T1."BaseLine" END
    ,T1."ItemCode",T1."Dscription" AS "ItemName",T2."EvalSystem",T2."ItmsGrpCod",T3."U_ItemGrpType" AS "CalType"
    ,T1."Quantity" AS "Quantity",T1."LineTotal" AS "Amount",T1."Price",T1."WhsCode"
    ,NULL AS "WorType",NULL AS "WorEntry",NULL AS "WorNum",NULL AS "WorLineNum"
    ,NULL AS "CJCode",NULL AS "CJName"
    ,T1."OcrCode" AS "OcrCode1",T1."OcrCode2",T1."OcrCode3",T1."OcrCode4",T1."OcrCode5"
    ,T0."UserSign" AS "User",T0."TransId",T0."Comments"
    FROM "OIGN" T0
    JOIN "IGN1" T1 ON T0."DocEntry"=T1."DocEntry"
    JOIN "OITM" T2 ON T1."ItemCode"=T2."ItemCode"
    JOIN "OITB" T3 ON T2."ItmsGrpCod"=T3."ItmsGrpCod"
    LEFT JOIN OWOR T4 ON CASE WHEN T1."BaseType"=-1 AND T1."U_OWORType"='202' THEN '202' ELSE T1."BaseType" END='202'
                AND CASE WHEN T1."BaseType"=-1 AND T1."U_OWORType"='202' THEN T1."U_OWORNum" ELSE T1."BaseRef" END=T4."DocNum"
    WHERE 1=1
    AND LEFT(T0."DocDate",7) = :FcCode
    AND (T1."ItemCode" = :ItemCode OR :ItemCode = '')

    --60 库存发货&生产发货
    UNION ALL
    SELECT T0."BPLId",T0."ObjType",T0."DocEntry",T0."DocNum",T0."CardCode",T0."CardName",T1."LineNum",LEFT(T0."DocDate",7) AS "FcCode"
    ,T0."DocDate",'' AS "CostCode",T0."U_TrsName" AS "TransCode",
     CASE WHEN T1."BaseType"=-1 AND T1."U_OWORType"='202' THEN '202' WHEN T1."BaseType"=-1 AND T1."U_OWORType"='MTC_OWOR' THEN 'MTC_OWOR' ELSE TO_CHAR(T1."BaseType") END AS "BaseType",
     COALESCE(T4."DocEntry",T1."BaseEntry",T1."U_MTCOWORNum") AS "BaseEntry",
     TO_CHAR(COALESCE(T4."DocNum",T1."BaseRef",T1."U_MTCOWORNum")) AS "BaseNum",
     CASE WHEN T1."BaseType"=-1 AND T1."U_OWORType"='202' THEN T1."U_OWORLineNum" WHEN T1."BaseType"=-1 AND T1."U_OWORType"='MTC_OWOR' THEN T1."U_MTCOWORLineNum" ELSE T1."BaseLine" END
    ,T1."ItemCode",T1."Dscription" AS "ItemName",T2."EvalSystem",T2."ItmsGrpCod",T3."U_ItemGrpType" AS "CalType"
    ,-1*T1."Quantity" AS "Quantity",-1*T1."LineTotal" AS "Amount",T1."Price",T1."WhsCode"
    ,NULL AS "WorType",NULL AS "WorEntry",NULL AS "WorNum",NULL AS "WorLineNum"
    ,NULL AS "CJCode",NULL AS "CJName"
    ,T1."OcrCode" AS "OcrCode1",T1."OcrCode2",T1."OcrCode3",T1."OcrCode4",T1."OcrCode5"
    ,T0."UserSign" AS "User",T0."TransId",T0."Comments"
    FROM "OIGE" T0
    JOIN "IGE1" T1 ON T0."DocEntry"=T1."DocEntry"
    JOIN "OITM" T2 ON T1."ItemCode"=T2."ItemCode"
    JOIN "OITB" T3 ON T2."ItmsGrpCod"=T3."ItmsGrpCod"
    LEFT JOIN OWOR T4 ON CASE WHEN T1."BaseType"=-1 AND T1."U_OWORType"='202' THEN '202' ELSE T1."BaseType" END='202'
                AND CASE WHEN T1."BaseType"=-1 AND T1."U_OWORType"='202' THEN T1."U_OWORNum" ELSE T1."BaseRef" END=T4."DocNum"
    WHERE 1=1
    AND LEFT(T0."DocDate",7) = :FcCode
    AND (T1."ItemCode" = :ItemCode OR :ItemCode = '')


    --15  销售交货
    UNION ALL
    SELECT T0."BPLId",T0."ObjType",T0."DocEntry",T0."DocNum",T0."CardCode",T0."CardName",T1."LineNum",LEFT(T0."DocDate",7) AS "FcCode"
    ,T0."DocDate",'' AS "CostCode",'' AS "TransCode",TO_CHAR(T1."BaseType"),T1."BaseEntry",T1."BaseRef" AS "BaseNum",T1."BaseLine"
    ,T1."ItemCode",T1."Dscription" AS "ItemName",T2."EvalSystem",T2."ItmsGrpCod",T3."U_ItemGrpType" AS "CalType"
    ,CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END * T1."Quantity" AS "Quantity"
    ,CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END * T1."LineTotal" AS "Amount",T1."Price",T1."WhsCode"
    ,NULL AS "WorType",NULL AS "WorEntry",NULL AS "WorNum",NULL AS "WorLineNum"
    ,NULL AS "CJCode",NULL AS "CJName"
    ,T1."OcrCode" AS "OcrCode1",T1."OcrCode2",T1."OcrCode3",T1."OcrCode4",T1."OcrCode5"
    ,T0."UserSign" AS "User",T0."TransId",T0."Comments"
    FROM "ODLN" T0
    JOIN "DLN1" T1 ON T0."DocEntry"=T1."DocEntry"
    JOIN "OITM" T2 ON T1."ItemCode"=T2."ItemCode"
    JOIN "OITB" T3 ON T2."ItmsGrpCod"=T3."ItmsGrpCod"
    WHERE 1=1
    AND LEFT(T0."DocDate",7) = :FcCode
    AND (T1."ItemCode" = :ItemCode OR :ItemCode = '')

    --16 销售退货
    UNION ALL
    SELECT T0."BPLId",T0."ObjType",T0."DocEntry",T0."DocNum",T0."CardCode",T0."CardName",T1."LineNum",LEFT(T0."DocDate",7) AS "FcCode"
    ,T0."DocDate",'' AS "CostCode",'' AS "TransCode",TO_CHAR(T1."BaseType"),T1."BaseEntry",T1."BaseRef" AS "BaseNum",T1."BaseLine"
    ,T1."ItemCode",T1."Dscription" AS "ItemName",T2."EvalSystem",T2."ItmsGrpCod",T3."U_ItemGrpType" AS "CalType"
    ,CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END * T1."Quantity" AS "Quantity"
    ,CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END * T1."LineTotal" AS "Amount",T1."Price",T1."WhsCode"
    ,NULL AS "WorType",NULL AS "WorEntry",NULL AS "WorNum",NULL AS "WorLineNum"
    ,NULL AS "CJCode",NULL AS "CJName"
    ,T1."OcrCode" AS "OcrCode1",T1."OcrCode2",T1."OcrCode3",T1."OcrCode4",T1."OcrCode5"
    ,T0."UserSign" AS "User",T0."TransId",T0."Comments"
    FROM "ORDN" T0
    JOIN "RDN1" T1 ON T0."DocEntry"=T1."DocEntry"
    JOIN "OITM" T2 ON T1."ItemCode"=T2."ItemCode"
    JOIN "OITB" T3 ON T2."ItmsGrpCod"=T3."ItmsGrpCod"
    WHERE 1=1
    AND LEFT(T0."DocDate",7) = :FcCode
    AND (T1."ItemCode" = :ItemCode OR :ItemCode = '')

    ;

    return

    SELECT "BPLId"
    ,"ObjType"
    ,"DocEntry"
    ,"DocNum"
    ,"CardCode"
    ,"CardName"
    ,"LineNum"
    ,"FcCode"
    ,"DocDate"
    ,"CostCode"        --归入成本计价类型
    ,"TransCode"        --实际交易类型
    ,"BaseType"
    ,"BaseEntry"
    ,"BaseNum"
    ,"BaseLine"
    ,"ItemCode"
    ,"ItemName"
    ,"EvalSystem"
    ,"ItmsGrpCod"
    ,"CalType"    --成本计价类型
    ,"Quantity"
    ,"Amount"
    ,"Price"
    ,"WhsCode"
    ,"WorType"
    ,"WorEntry"
    ,"WorNum"
    ,"WorLineNum"
    ,"CJCode"
    ,"CJName"
    ,"OcrCode1"
    ,"OcrCode2"
    ,"OcrCode3"
    ,"OcrCode4"
    ,"OcrCode5"
    ,"User"
    ,"TransId"
    ,"Comments"
    FROM :TMP_DETAIL;


END
