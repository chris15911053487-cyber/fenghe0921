CREATE VIEW "FH100"."MTC_VIEW_Document" AS (((((((((((((SELECT
	 T0."ObjType",
	 T0."DocEntry",
	 T0."DocNum" ,
	 T0."CANCELED",
	 T0."CardCode" ,
	 T0."DocDate",
	 T1."LineNum" ,
	 T1."ItemCode",
	 T1."OcrCode" ,
	 T1."OcrCode2",
	 T1."OcrCode3" ,
	 T1."OcrCode4",
	 T1."OcrCode5" ,
	 T1."Project" ,
	 TO_CHAR(T1."BaseType"),
	 T1."BaseEntry",
	 TO_CHAR(T1."BaseRef"),
	 T1."BaseLine" ,
	 '' AS "U_BusiType" ,
	 '' AS "U_YWLX" ,
	 T0."Comments" ,
	 T0."TransId" ,
	 '' AS "TransCode",
	 T1."AcctCode",
	 T1."CogsAcct",
	 T0."U_SupNum" 
													FROM "ORDR" T0 JOIN "RDR1" T1 ON T0."DocEntry"=T1."DocEntry" 
													WHERE 1=1) UNION ALL (SELECT
	 T0."ObjType",
	 T0."DocEntry",
	 T0."DocNum" ,
	 T0."CANCELED",
	 T0."CardCode" ,
	 T0."DocDate",
	 T1."LineNum" ,
	 T1."ItemCode",
	 T1."OcrCode" ,
	 T1."OcrCode2",
	 T1."OcrCode3" ,
	 T1."OcrCode4",
	 T1."OcrCode5" ,
	 T1."Project" ,
	 TO_CHAR(T1."BaseType"),
	 T1."BaseEntry",
	 TO_CHAR(T1."BaseRef"),
	 T1."BaseLine" ,
	 '' AS "U_BusiType" ,
	 '' AS "U_YWLX" ,
	 T0."Comments" ,
	 T0."TransId" ,
	 'O01' AS "TransCode" ,
	 T1."AcctCode",
	 T1."CogsAcct",
	 T0."U_SupNum" 
													FROM "ODLN" T0 JOIN "DLN1" T1 ON T0."DocEntry"=T1."DocEntry" 
													WHERE 1=1)) UNION ALL (SELECT
	 T0."ObjType",
	 T0."DocEntry",
	 T0."DocNum" ,
	 T0."CANCELED",
	 T0."CardCode" ,
	 T0."DocDate",
	 T1."LineNum" ,
	 T1."ItemCode",
	 T1."OcrCode" ,
	 T1."OcrCode2",
	 T1."OcrCode3" ,
	 T1."OcrCode4",
	 T1."OcrCode5" ,
	 T1."Project" ,
	 TO_CHAR(T1."BaseType"),
	 T1."BaseEntry",
	 TO_CHAR(T1."BaseRef"),
	 T1."BaseLine" ,
	 '' AS "U_BusiType" ,
	 '' AS "U_YWLX" ,
	 T0."Comments" ,
	 T0."TransId" ,
	 'O06' AS "TransCode",
	 T1."AcctCode",
	 T1."CogsAcct",
	 T0."U_SupNum" 
												FROM "ORDN" T0 JOIN "RDN1" T1 ON T0."DocEntry"=T1."DocEntry" 
												WHERE 1=1)) UNION ALL (SELECT
	 T0."ObjType",
	 T0."DocEntry",
	 T0."DocNum" ,
	 T0."CANCELED",
	 T0."CardCode" ,
	 T0."DocDate",
	 T1."LineNum" ,
	 T1."ItemCode",
	 T1."OcrCode" ,
	 T1."OcrCode2",
	 T1."OcrCode3" ,
	 T1."OcrCode4",
	 T1."OcrCode5" ,
	 T1."Project" ,
	 TO_CHAR(T1."BaseType"),
	 T1."BaseEntry",
	 TO_CHAR(T1."BaseRef"),
	 T1."BaseLine" ,
	 '' AS "U_BusiType" ,
	 '' AS "U_YWLX" ,
	 T0."Comments" ,
	 T0."TransId" ,
	 '' AS "TransCode",
	 T1."AcctCode",
	 T1."CogsAcct",
	 T0."U_SupNum" 
											FROM "OINV" T0 JOIN "INV1" T1 ON T0."DocEntry"=T1."DocEntry" 
											WHERE 1=1)) UNION ALL (SELECT
	 T0."ObjType",
	 T0."DocEntry",
	 T0."DocNum" ,
	 T0."CANCELED",
	 T0."CardCode" ,
	 T0."DocDate",
	 T1."LineNum" ,
	 T1."ItemCode",
	 T1."OcrCode" ,
	 T1."OcrCode2",
	 T1."OcrCode3" ,
	 T1."OcrCode4",
	 T1."OcrCode5" ,
	 T1."Project" ,
	 TO_CHAR(T1."BaseType"),
	 T1."BaseEntry",
	 TO_CHAR(T1."BaseRef"),
	 T1."BaseLine" ,
	 '' AS "U_BusiType" ,
	 '' AS "U_YWLX" ,
	 T0."Comments" ,
	 T0."TransId" ,
	 '' AS "TransCode",
	 T1."AcctCode",
	 T1."CogsAcct",
	 T0."U_SupNum" 
										FROM "ORIN" T0 JOIN "RIN1" T1 ON T0."DocEntry"=T1."DocEntry" 
										WHERE 1=1)) UNION ALL (SELECT
	 T0."ObjType",
	 T0."DocEntry",
	 T0."DocNum" ,
	 T0."CANCELED",
	 T0."CardCode" ,
	 T0."DocDate",
	 T1."LineNum" ,
	 T1."ItemCode",
	 T1."OcrCode" ,
	 T1."OcrCode2",
	 T1."OcrCode3" ,
	 T1."OcrCode4",
	 T1."OcrCode5" ,
	 T1."Project" ,
	 TO_CHAR(T1."BaseType"),
	 T1."BaseEntry",
	 TO_CHAR(T1."BaseRef"),
	 T1."BaseLine" ,
	 '' AS "U_BusiType" ,
	 '' AS "U_YWLX" ,
	 T0."Comments" ,
	 T0."TransId" ,
	 '' AS "TransCode",
	 T1."AcctCode",
	 T1."CogsAcct",
	 T0."U_SupNum" 
									FROM "OPRQ" T0 JOIN "PRQ1" T1 ON T0."DocEntry"=T1."DocEntry" 
									WHERE 1=1)) UNION ALL (SELECT
	 T0."ObjType",
	 T0."DocEntry",
	 T0."DocNum" ,
	 T0."CANCELED",
	 T0."CardCode" ,
	 T0."DocDate",
	 T1."LineNum" ,
	 T1."ItemCode",
	 T1."OcrCode" ,
	 T1."OcrCode2",
	 T1."OcrCode3" ,
	 T1."OcrCode4",
	 T1."OcrCode5" ,
	 T1."Project" ,
	 TO_CHAR(T1."BaseType"),
	 T1."BaseEntry",
	 TO_CHAR(T1."BaseRef"),
	 T1."BaseLine" ,
	 '' AS "U_BusiType" ,
	 '' AS "U_YWLX" ,
	 T0."Comments" ,
	 T0."TransId" ,
	 '' AS "TransCode",
	 T1."AcctCode",
	 T1."CogsAcct",
	 T0."U_SupNum" 
								FROM "OPOR" T0 JOIN "POR1" T1 ON T0."DocEntry"=T1."DocEntry" 
								WHERE 1=1)) UNION ALL (SELECT
	 T0."ObjType",
	 T0."DocEntry",
	 T0."DocNum" ,
	 T0."CANCELED",
	 T0."CardCode" ,
	 T0."DocDate",
	 T1."LineNum" ,
	 T1."ItemCode",
	 T1."OcrCode" ,
	 T1."OcrCode2",
	 T1."OcrCode3" ,
	 T1."OcrCode4",
	 T1."OcrCode5" ,
	 T1."Project" ,
	 TO_CHAR(T1."BaseType"),
	 T1."BaseEntry",
	 TO_CHAR(T1."BaseRef"),
	 T1."BaseLine" ,
	 '' AS "U_BusiType" ,
	 '' AS "U_YWLX" ,
	 T0."Comments" ,
	 T0."TransId" ,
	 'I01' AS "TransCode",
	 T1."AcctCode",
	 T1."CogsAcct",
	 T0."U_SupNum" 
							FROM "OPDN" T0 JOIN "PDN1" T1 ON T0."DocEntry"=T1."DocEntry" 
							WHERE 1=1)) UNION ALL (SELECT
	 T0."ObjType",
	 T0."DocEntry",
	 T0."DocNum" ,
	 T0."CANCELED",
	 T0."CardCode" ,
	 T0."DocDate",
	 T1."LineNum" ,
	 T1."ItemCode",
	 T1."OcrCode" ,
	 T1."OcrCode2",
	 T1."OcrCode3" ,
	 T1."OcrCode4",
	 T1."OcrCode5" ,
	 T1."Project" ,
	 TO_CHAR(T1."BaseType"),
	 T1."BaseEntry",
	 TO_CHAR(T1."BaseRef"),
	 T1."BaseLine" ,
	 '' AS "U_BusiType" ,
	 '' AS "U_YWLX" ,
	 T0."Comments" ,
	 T0."TransId" ,
	 'I06' AS "TransCode",
	 T1."AcctCode",
	 T1."CogsAcct",
	 T0."U_SupNum" 
						FROM "ORPD" T0 JOIN "RPD1" T1 ON T0."DocEntry"=T1."DocEntry" 
						WHERE 1=1)) UNION ALL (SELECT
	 T0."ObjType",
	 T0."DocEntry",
	 T0."DocNum" ,
	 T0."CANCELED",
	 T0."CardCode" ,
	 T0."DocDate",
	 T1."LineNum" ,
	 T1."ItemCode",
	 T1."OcrCode" ,
	 T1."OcrCode2",
	 T1."OcrCode3" ,
	 T1."OcrCode4",
	 T1."OcrCode5" ,
	 T1."Project" ,
	 TO_CHAR(T1."BaseType"),
	 T1."BaseEntry",
	 TO_CHAR(T1."BaseRef"),
	 T1."BaseLine" ,
	 '' AS "U_BusiType" ,
	 '' AS "U_YWLX" ,
	 T0."Comments" ,
	 T0."TransId" ,
	 'I01' AS "TransCode",
	 T1."AcctCode",
	 T1."CogsAcct",
	 T0."U_SupNum" 
					FROM "OPCH" T0 JOIN "PCH1" T1 ON T0."DocEntry"=T1."DocEntry" 
					WHERE 1=1)) UNION ALL (SELECT
	 T0."ObjType",
	 T0."DocEntry",
	 T0."DocNum" ,
	 T0."CANCELED",
	 T0."CardCode" ,
	 T0."DocDate",
	 T1."LineNum" ,
	 T1."ItemCode",
	 T1."OcrCode" ,
	 T1."OcrCode2",
	 T1."OcrCode3" ,
	 T1."OcrCode4",
	 T1."OcrCode5" ,
	 T1."Project" ,
	 TO_CHAR(T1."BaseType"),
	 T1."BaseEntry",
	 TO_CHAR(T1."BaseRef"),
	 T1."BaseLine" ,
	 '' AS "U_BusiType" ,
	 '' AS "U_YWLX" ,
	 T0."Comments" ,
	 T0."TransId" ,
	 'I06' AS "TransCode",
	 T1."AcctCode",
	 T1."CogsAcct",
	 T0."U_SupNum" 
				FROM "ORPC" T0 JOIN "RPC1" T1 ON T0."DocEntry"=T1."DocEntry" 
				WHERE 1=1)) UNION ALL (SELECT
	 T0."ObjType",
	 T0."DocEntry",
	 T0."DocNum" ,
	 T0."CANCELED",
	 T0."CardCode" ,
	 T0."DocDate",
	 T1."LineNum" ,
	 T1."ItemCode",
	 T1."OcrCode" ,
	 T1."OcrCode2",
	 T1."OcrCode3" ,
	 T1."OcrCode4",
	 T1."OcrCode5" ,
	 T1."Project" ,
	 CASE WHEN T2."Code" IN ('204',
	 '205') 
			THEN T1."U_BaseType" WHEN T1."BaseType"=-1 
			AND T1."U_OWORType"='202' 
			THEN '202' WHEN T1."U_OWORType"='MTC_OWOR' 
			THEN 'MTC_OWOR' 
			ELSE TO_CHAR(T1."BaseType") 
			END AS "BaseType",
	CASE WHEN T2."Code" IN ('204',
	 '205') 
		THEN T1."U_BaseEntry"
		ELSE COALESCE(T3."DocEntry",
	 T1."BaseEntry",
	 T1."U_MTCOWORNum",
	 T1."U_BaseEntry") END AS "BaseEntry",
	 TO_CHAR(CASE WHEN T2."Code" IN ('204',
	 '205') 
		THEN T1."U_BaseEntry"
		ELSE COALESCE(T3."DocNum",
	 T1."BaseRef",
	 T1."U_OWORNum",
	 T1."U_MTCOWORNum",
	 T1."U_BaseEntry") END) AS "BaseRef",
	 CASE WHEN T2."Code" IN ('204',
	 '205') 
			THEN T1."U_BaseLineGrpNum" WHEN T1."BaseType"=-1 
			AND T1."U_OWORType"='202' 
			THEN T1."U_OWORLineNum" WHEN T1."BaseType"=-1 
			AND T1."U_OWORType"='MTC_OWOR' 
			THEN T1."U_MTCOWORLineNum" 
			ELSE T1."BaseLine" 
			END,
	 T2."Code" AS "U_BusiType" ,
	 T2."Name" AS "U_YWLX" ,
	 T0."Comments" ,
	 T0."TransId" ,
	 T2."U_IOType" AS "TransCode",
	 T1."AcctCode",
	 T1."CogsAcct",
	 T0."U_SupNum" 
			FROM "OIGN" T0 JOIN "IGN1" T1 ON T0."DocEntry"=T1."DocEntry" 
			LEFT JOIN "@U_CIOTRN" T2 ON T0."U_TrsName"=T2."Code" 
			LEFT JOIN OWOR T3 ON CASE WHEN T1."BaseType"=-1 
			AND T1."U_OWORType"='202' 
			THEN '202' 
			ELSE T1."BaseType" 
			END='202' 
			AND CASE WHEN T1."BaseType"=-1 
			AND T1."U_OWORType"='202' 
			THEN T1."U_OWORNum" 
			ELSE T1."BaseRef" 
			END=T3."DocNum" 
			WHERE 1=1)) UNION ALL (SELECT
	 T0."ObjType",
	 T0."DocEntry",
	 T0."DocNum" ,
	 T0."CANCELED",
	 T0."CardCode" ,
	 T0."DocDate",
	 T1."LineNum" ,
	 T1."ItemCode",
	 T1."OcrCode" ,
	 T1."OcrCode2",
	 T1."OcrCode3" ,
	 T1."OcrCode4",
	 T1."OcrCode5" ,
	 T1."Project" ,
	 CASE WHEN T2."Code" IN ('204',
	 '205') 
		THEN T1."U_BaseType" WHEN T1."BaseType"=-1 
		AND T1."U_OWORType"='202' 
		THEN '202' WHEN T1."U_OWORType"='MTC_OWOR' 
		THEN 'MTC_OWOR' 
		ELSE TO_CHAR(T1."BaseType") 
		END AS "BaseType",
	 CASE WHEN T2."Code" IN ('204',
	 '205') 
		THEN T1."U_BaseEntry"
		ELSE COALESCE(T3."DocEntry",
	 T1."BaseEntry",
	 T1."U_MTCOWORNum",
	 T1."U_BaseEntry") END AS "BaseEntry",
	 TO_CHAR(CASE WHEN T2."Code" IN ('204',
	 '205') 
		THEN T1."U_BaseEntry"
		ELSE COALESCE(T3."DocNum",
	 T1."BaseRef",
	 T1."U_MTCOWORNum",
	 T1."U_BaseEntry") END) AS "BaseRef",
	 CASE WHEN T2."Code" IN ('204',
	 '205') 
		THEN T1."U_BaseLineGrpNum" WHEN T1."BaseType"=-1 
		AND T1."U_OWORType"='202' 
		THEN T1."U_OWORLineNum" WHEN T1."BaseType"=-1 
		AND T1."U_OWORType"='MTC_OWOR' 
		THEN T1."U_MTCOWORLineNum" 
		ELSE T1."BaseLine" 
		END,
	 T2."Code" AS "U_BusiType" ,
	 T2."Name" AS "U_YWLX" ,
	 T0."Comments" ,
	 T0."TransId" ,
	 T2."U_IOType" AS "TransCode" ,
	 T1."AcctCode",
	 T1."CogsAcct",
	 T0."U_SupNum" 
		FROM "OIGE" T0 JOIN "IGE1" T1 ON T0."DocEntry"=T1."DocEntry" 
		LEFT JOIN "@U_CIOTRN" T2 ON T0."U_TrsName"=T2."Code" 
		LEFT JOIN OWOR T3 ON CASE WHEN T1."BaseType"=-1 
		AND T1."U_OWORType"='202' 
		THEN '202' 
		ELSE T1."BaseType" 
		END='202' 
		AND CASE WHEN T1."BaseType"=-1 
		AND T1."U_OWORType"='202' 
		THEN T1."U_OWORNum" 
		ELSE T1."BaseRef" 
		END=T3."DocNum" 
		WHERE 1=1))