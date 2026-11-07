CREATE VIEW "FH100"."MTC_VIEW_ProductDetail_MTCOWOR" ( "Type",
     "TransType",
     "DocName",
     "CreatedBy",
     "BASE_REF",
     "DocLineNum",
     "DocDate",
     "BusiType",
     "BusiTypeN",
     "TransCode",
     "TransName",
     "ItemCode",
     "ItemName",
     "ItmsGrpCod",
     "Quantity",
     "BaseType",
     "BaseEntry",
     "BaseLine",
     "MainItemCode",
     "AcctCode",
     "AcctName" ) AS SELECT
     CASE WHEN T14."DocEntry" IS NULL
THEN '子件'
ELSE '主件'
END AS "Type",
     T0."TransType",
     T9."DocName",
     T0."CreatedBy",
     T0."BASE_REF",
     T0."DocLineNum",
     T0."DocDate",
     T10."Code" AS "BusiType",
     T10."Name" AS "BusiTypeN",
     T11."Code" AS "TransCode",
     T11."Name" AS "TransName",
     T0."ItemCode",
     T2."ItemName",
     T2."ItmsGrpCod",
     T0."InQty"-T0."OutQty" AS "Quantity",
     T4."U_OWORType" AS "BaseType",
     COALESCE(T13."DocEntry",
     T14."DocEntry") AS "BaseEntry",
     T12."LineId" AS "BaseLine",
     COALESCE(T13."U_ItemCode",
     T14."U_ItemCode") AS "MainItemCode",
     T4."AcctCode" AS "AcctCode",
     T52."AcctName" AS "AcctName"
FROM OIVL T0
LEFT JOIN OITM T2 ON T0."ItemCode"=T2."ItemCode" JOIN ( SELECT
     M."ObjType",
     M."DocEntry",
     D."LineNum",
     D."AcctCode",
     M."U_TrsName",
     D."U_OWORType",
     D."U_MTCOWORNum",
     D."U_MTCOWORLineNum"
    FROM IGN1 D JOIN OIGN M ON M."DocEntry"=D."DocEntry"
    UNION ALL SELECT
     M."ObjType",
     M."DocEntry",
     D."LineNum",
     D."AcctCode",
     M."U_TrsName",
     D."U_OWORType",
     D."U_MTCOWORNum",
     D."U_MTCOWORLineNum"
    FROM IGE1 D JOIN OIGE M ON M."DocEntry"=D."DocEntry" ) T4 ON T0."TransType"=T4."ObjType"
AND T0."CreatedBy"=T4."DocEntry"
AND T0."DocLineNum"=T4."LineNum"
LEFT JOIN "MTC_DocType" T9 ON TO_CHAR(T0."TransType")=T9."ObjType"
LEFT JOIN "@U_CIOTRN" T10 ON T4."U_TrsName"=T10."Code"
LEFT JOIN "@MTC_COST_IOTYPE" T11 ON T10."U_IOType"=T11."Code"
LEFT JOIN "@MTC_WOR1" T12 ON T4."U_OWORType"=T12."Object"
AND T4."U_MTCOWORNum"=TO_CHAR(T12."DocEntry")
AND T4."U_MTCOWORLineNum"=TO_CHAR(T12."LineId")
LEFT JOIN "@MTC_OWOR" T13 ON T12."DocEntry"=T13."DocEntry"
LEFT JOIN "@MTC_OWOR" T14 ON T4."U_OWORType"=T14."Object"
AND T4."U_MTCOWORNum"=TO_CHAR(T14."DocEntry")
AND IFNULL(T4."U_MTCOWORLineNum",
     '')=''
LEFT JOIN OACT T52 ON T4."AcctCode"=T52."AcctCode"
WHERE 1=1
AND T4."U_OWORType"='MTC_OWOR' WITH READ ONLY
