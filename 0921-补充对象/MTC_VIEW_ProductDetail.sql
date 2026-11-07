CREATE VIEW "FH100"."MTC_VIEW_ProductDetail" ( "ID",
     "Type",
     "BusiType",
     "ObjType",
     "OWOREntry",
     "OWORNum",
     "DocEntry",
     "DocNum",
     "LineNum",
     "BaseLine",
     "CreateDate",
     "DocDate",
     "ItemCode",
     "WhsCode",
     "Quantity",
     "unitMsr",
     "Price",
     "Amt" ) AS (((((((((SELECT
     1 AS "ID" ,
     '主件' AS "Type" ,
     '生产收货' AS "BusiType" ,
     T0."ObjType",
     T2."DocEntry" AS "OWOREntry" ,
     T2."DocNum" AS "OWORNum" ,
     T0."DocEntry",
     T0."DocNum" AS "DocNum" ,
     T1."LineNum",
     T1."BaseLine",
     T0."CreateDate",
     T0."DocDate" ,
     T1."ItemCode" ,
     T1."WhsCode" ,
     T1."Quantity" ,
     T1."unitMsr" ,
     T1."StockPrice" AS "Price" ,
     (T5."SumStock"+T5."PriceDiff"+T5."VarVal") "Amt"
                                    FROM OIGN T0 JOIN IGN1 T1 ON T0."DocEntry" = T1."DocEntry" JOIN OWOR T2 ON T2."DocNum" = IFNULL(T1."BaseRef",
     0)
                                    AND T1."BaseType" = '202'
                                    AND T1."BaseLine" IS NULL
                                    LEFT JOIN OIVL T5 ON T5."TransType" = T0."ObjType"
                                    AND T5."CreatedBy" = T0."DocEntry"
                                    AND T1."LineNum" = T5."DocLineNum")
                                UNION ALL (SELECT
     2 AS "ID" ,
     '子件' AS "Type" ,
     '生产发料' "BusiType" ,
     T0."ObjType",
     T2."DocEntry" AS "OWOREntry" ,
     T2."DocNum" AS "OWORNum" ,
     T0."DocEntry",
     T0."DocNum" AS "DocNum1" ,
     T1."LineNum",
     T1."BaseLine",
     T0."CreateDate",
     T0."DocDate" ,
     T1."ItemCode" ,
     T1."WhsCode" ,
     -T1."Quantity" ,
     T1."unitMsr" ,
     T1."StockPrice" AS "Price" ,
     (T5."SumStock"+T5."PriceDiff"+T5."VarVal") "Amt"
                                    FROM OIGE T0 JOIN IGE1 T1 ON T0."DocEntry" = T1."DocEntry" JOIN OWOR T2 ON T2."DocNum" = IFNULL(T1."BaseRef",
     0)
                                    AND T1."BaseType" = '202'
                                    AND T1."BaseLine" IS NOT NULL JOIN OIVL T5 ON T5."TransType" = T0."ObjType"
                                    AND T5."CreatedBy" = T0."DocEntry"
                                    AND T1."LineNum" = T5."DocLineNum"))
                            UNION ALL (SELECT
     1 AS "ID" ,
     '子件' AS "Type" ,
     '子件退货' "BusiType" ,
     T0."ObjType",
     T2."DocEntry" AS "OWOREntry" ,
     T2."DocNum" AS "OWORNum" ,
     T0."DocEntry",
     T0."DocNum" AS "DocNum1" ,
     T1."LineNum",
     T1."BaseLine",
     T0."CreateDate",
     T0."DocDate" ,
     T1."ItemCode" ,
     T1."WhsCode" ,
     T1."Quantity" ,
     T1."unitMsr" ,
     T1."StockPrice" AS "Price" ,
     (T5."SumStock"+T5."PriceDiff"+ T5."VarVal")
                                FROM OIGN T0 JOIN IGN1 T1 ON T0."DocEntry" = T1."DocEntry" JOIN OWOR T2 ON T2."DocNum" = IFNULL(T1."BaseRef",
     0)
                                AND T1."BaseType" = '202'
                                AND T1."BaseLine" IS NOT NULL JOIN OIVL T5 ON T5."TransType" = T0."ObjType"
                                AND T5."CreatedBy" = T0."DocEntry"
                                AND T1."LineNum" = T5."DocLineNum"))
                        UNION ALL (SELECT
     2 AS "ID" ,
     '主件' AS "Type" ,
     '分拆发货' "BusiType" ,
     T0."ObjType",
     T2."DocEntry" AS "OWOREntry",
     T2."DocNum" AS "OWORNum" ,
     T0."DocEntry",
     T0."DocNum" AS "DocNum1" ,
     T1."LineNum",
     T1."BaseLine",
     T0."CreateDate",
     T0."DocDate" ,
     T1."ItemCode" ,
     T1."WhsCode" ,
     -T1."Quantity" ,
     T1."unitMsr" ,
     T1."StockPrice" AS "Price" ,
     (T5."SumStock"+T5."PriceDiff"+ T5."VarVal")
                            FROM OIGE T0 JOIN IGE1 T1 ON T0."DocEntry" = T1."DocEntry" JOIN OWOR T2 ON T2."DocNum" = IFNULL(T1."BaseRef",
     0)
                            AND T1."BaseType" = '202'
                            AND T1."BaseLine" IS NULL JOIN OIVL T5 ON T5."TransType" = T0."ObjType"
                            AND T5."CreatedBy" = T0."DocEntry"
                            AND T1."LineNum" = T5."DocLineNum"))
                    UNION ALL (SELECT
     2 AS "ID" ,
     '子件' AS "Type" ,
     '费用' "BusiType" ,
     T0."ObjType",
     T2."DocEntry" AS "OWOREntry" ,
     T2."DocNum" AS "OWORNum" ,
     T0."DocEntry",
     T0."DocNum" AS "DocNum1" ,
     T1."LineNum",
     T1."BaseLine",
     T0."CreateDate",
     T0."DocDate" ,
     T1."ItemCode" ,
     T1."WhsCode" ,
     -T1."Quantity" ,
     T1."unitMsr" ,
     T1."StockPrice" AS "Price" ,
     -T1."LineTotal" AS "Amt"
                        FROM OIGE T0 JOIN IGE1 T1 ON T0."DocEntry" = T1."DocEntry" JOIN OWOR T2 ON T2."DocNum" = IFNULL(T1."BaseRef",
     0)
                        AND T1."BaseType" = '202'
                        AND T1."BaseLine" IS NOT NULL JOIN OITM T3 ON T1."ItemCode"=T3."ItemCode"
                        WHERE 1=1
                        AND T3."InvntItem" = 'N'))
                UNION ALL (SELECT
     3 AS "ID" ,
     '子件' AS "Type" ,
     '委外费用收货' "BusiType" ,
     T0."ObjType",
     T3."DocEntry" AS "OWOREntry",
     T3."DocNum" AS "OWORNum" ,
     T0."DocEntry",
     T0."DocNum" AS "DocNum1" ,
     T1."LineNum",
     T1."BaseLine",
     T0."CreateDate",
     T0."DocDate" ,
     T1."ItemCode" ,
     T1."WhsCode" ,
     CASE WHEN T0."CANCELED"='C'
                    THEN 1
                    ELSE -1
                    END*(T1."Quantity"-IFNULL(T4."RpdQty",
     0)) AS "Quantity" ,
     T1."unitMsr" ,
     T1."Price" AS "Price" ,
     CASE WHEN T0."CANCELED"='C'
                    THEN 1
                    ELSE -1
                    END*(T1."LineTotal"-IFNULL(T4."RpdTotal",
     0)) AS "LineTotal"
                    FROM OPDN T0 JOIN PDN1 T1 ON T0."DocEntry" = T1."DocEntry" JOIN (SELECT
     "ObjType",
     "DocEntry",
     "BaseRef",
     SUM("Quantity") AS "Quantity"
                        FROM IGN1
                        GROUP BY "ObjType",
     "DocEntry",
     "BaseRef") T2 ON T1."U_BaseType"=T2."ObjType"
                    AND T1."U_BaseEntry"=T2."DocEntry"
                    AND T1."U_OWORNum"=IFNULL(T2."BaseRef",
     0) JOIN OWOR T3 ON T3."DocNum" = IFNULL(T2."BaseRef",
     0)
                    LEFT JOIN (SELECT
     D."BaseType",
     D."BaseEntry",
     D."BaseLine",
     SUM(D."Quantity") AS "RpdQty",
     SUM(D."LineTotal") AS "RpdTotal"
                        FROM ORPD M JOIN "RPD1" D ON M."DocEntry"=D."DocEntry"
                        WHERE M."CANCELED"='N'
                        GROUP BY D."BaseType",
     D."BaseEntry",
     D."BaseLine" ) T4 ON T1."ObjType"=T4."BaseType"
                    AND T1."DocEntry"=T4."BaseEntry"
                    AND T1."LineNum"=T4."BaseLine"))
            UNION ALL (SELECT
     4 AS "ID" ,
     '子件' AS "Type" ,
     '委外费用发票暂估差异' "BusiType" ,
     T0."ObjType",
     T13."DocEntry" AS "OWOREntry",
     T13."DocNum" AS "OWORNum" ,
     T0."DocEntry",
     T0."DocNum" AS "DocNum1" ,
     T1."LineNum",
     T1."BaseLine",
     T0."CreateDate",
     T0."DocDate" ,
     T1."ItemCode" ,
     T1."WhsCode" ,
     0 AS "Quantity" ,
     T1."unitMsr" ,
     T1."Price" AS "Price" ,
     CASE WHEN T0."CANCELED"='C'
                THEN 1
                ELSE -1
                END*(T1."LineTotal"-T1."Quantity"*T2."Price") AS "LineTotal"
                FROM "OPCH" T0
                INNER JOIN "PCH1" T1 ON T0."DocEntry"=T1."DocEntry" JOIN (SELECT
     M."ObjType",
     D."DocEntry",
     M."DocNum",
     D."LineNum",
     D."U_BaseType",
     D."U_BaseEntry",
     D."U_OWORNum" ,
     CASE WHEN IFNULL(D."U_InitPrice",
     0)<>0
                    THEN D."U_InitPrice"
                    ELSE D."Price"
                    END AS "Price" ,
     M2."U_OldSysNo" "OPOROldSN",
     M."U_OldSysNo" "OPDNOldSN"
                    FROM "OPDN" M JOIN "PDN1" D ON M."DocEntry"=D."DocEntry"
                    LEFT JOIN "POR1" D2 ON D."BaseEntry" =D2."DocEntry"
                    AND D."BaseLine" =D2."LineNum"
                    AND D."BaseType"=D2."ObjType"
                    LEFT JOIN "OPOR" M2 ON D2."DocEntry" =M2."DocEntry" ) T2 ON T1."BaseType"=T2."ObjType"
                AND T1."BaseEntry"=T2."DocEntry"
                AND T1."BaseLine"=T2."LineNum" JOIN (SELECT
     "ObjType",
     "DocEntry",
     "BaseRef",
     SUM("Quantity") AS "Quantity"
                    FROM IGN1
                    GROUP BY "ObjType",
     "DocEntry",
     "BaseRef") T12 ON T2."U_BaseType"=T12."ObjType"
                AND T2."U_BaseEntry"=T12."DocEntry"
                AND T2."U_OWORNum"=IFNULL(T12."BaseRef",
     0) JOIN OWOR T13 ON T13."DocNum" = IFNULL(T12."BaseRef",
     0)
                WHERE 1=0
                AND T0."CANCELED"='N'))
        UNION ALL (SELECT
     9 AS "ID" ,
     '日记账分录' AS "Type" ,
     '日记账分录' "BusiType" ,
     '30',
     T0."DocEntry" AS "OWOREntry" ,
     T0."DocNum" AS "OWORNum" ,
     T0."TransId",
     T0."TransId" AS "DocNum1" ,
     0 as "LineNum",
     0 AS "BaseLine",
     T0."CreateDate",
     T2."RefDate" ,
     T0."ItemCode" ,
     T0."Warehouse" ,
     T0."PlannedQty" ,
     '' AS "unit" ,
     0 AS "Price" ,
     -T3."Amt" AS "Amt"
            FROM OWOR T0 JOIN OJDT T2 ON T0."TransId"=T2."TransId" JOIN (SELECT
     "TransId",
     SUM("Debit"-"Credit") AS "Amt"
                FROM "JDT1"
                WHERE "Account"='500101'
                GROUP BY "TransId") T3 ON T2."TransId"=T3."TransId"
            WHERE 1=1))
    UNION ALL (SELECT
     10 AS "ID" ,
     '主件' AS "Type" ,
     '生产退货' AS "BusiType" ,
     T0."ObjType",
     T2."DocEntry" AS "OWOREntry" ,
     T2."DocNum" AS "OWORNum" ,
     T0."DocEntry",
     T0."DocNum" AS "DocNum" ,
     T1."LineNum",
     T1."BaseLine",
     T0."CreateDate",
     T0."DocDate" ,
     T1."ItemCode" ,
     T1."WhsCode" ,
     -1*T1."Quantity" ,
     T1."unitMsr" ,
     T1."StockPrice" AS "Price" ,
     -1*(T5."SumStock"+T5."PriceDiff"+T5."VarVal") "Amt"
        FROM OIGE T0 JOIN IGE1 T1 ON T0."DocEntry" = T1."DocEntry" JOIN OWOR T2 ON T2."DocNum" = IFNULL(T1."U_OWORNum",
     0)
        AND T1."U_OWORType" = '202'
        AND T1."BaseLine" IS NULL
        LEFT JOIN OIVL T5 ON T5."TransType" = T0."ObjType"
        AND T5."CreatedBy" = T0."DocEntry"
        AND T1."LineNum" = T5."DocLineNum"
        WHERE T0."U_Type"='OWOR1')) WITH READ ONLY
