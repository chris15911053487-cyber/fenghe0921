-- 修正稿（未部署）：MTC_VIEW_Document 的销售退货段（ORDN/RDN1）补上 U_ 来源。以 0921-数据库同步 版为底稿，只改这一段。
-- RDN1 标准来源不是交货（BaseType<>15）、且行上 U_BaseType='15' 时，BaseType/BaseEntry/BaseRef/BaseLine 改为原交货
-- （U_BaseEntry = DLN1.DocEntry，U_BaseLine = DLN1.LineNum，BaseRef 取交货 DocNum；用户确认 2026-10-13）。取消单（CANCELED='C'）不改。
-- 影响旧模块：0303 把这些字段写进 0302；0401 的 8092(RDN01) / 9003(RD02) 对 ObjType=16 且 BaseType 指向交货的行，
-- 把退货金额改成 −1 × 原交货行金额（不按数量折算）。原来只影响基于交货的退货，改后 U_ 关联的退货也会被改。
CREATE OR REPLACE VIEW "MTC_VIEW_Document" AS (((((((((((((SELECT
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
	 --2026.10.13 销售退货标准来源不是交货时，取行上 U_BaseType='15' / U_BaseEntry（交货 DocEntry）/ U_BaseLine（LineNum），来源单号取交货 DocNum；取消单不改
	 CASE WHEN D."DocEntry" IS NOT NULL THEN '15' ELSE TO_CHAR(T1."BaseType") END,
	 CASE WHEN D."DocEntry" IS NOT NULL THEN D."DocEntry" ELSE T1."BaseEntry" END,
	 CASE WHEN D."DocEntry" IS NOT NULL THEN TO_CHAR(D."DocNum") ELSE TO_CHAR(T1."BaseRef") END,
	 CASE WHEN D."DocEntry" IS NOT NULL THEN TO_INTEGER(T1."U_BaseLine") ELSE T1."BaseLine" END ,
	 '' AS "U_BusiType" ,
	 '' AS "U_YWLX" ,
	 T0."Comments" ,
	 T0."TransId" ,
	 'O06' AS "TransCode",
	 T1."AcctCode",
	 T1."CogsAcct",
	 T0."U_SupNum" 
												FROM "ORDN" T0 JOIN "RDN1" T1 ON T0."DocEntry"=T1."DocEntry" 
												LEFT JOIN "ODLN" D ON T0."CANCELED"<>'C' AND IFNULL(T1."BaseType",-1)<>15
													AND TO_CHAR(T1."U_BaseType")='15' AND T1."U_BaseLine" IS NOT NULL
													AND TO_CHAR(D."DocEntry")=TO_CHAR(T1."U_BaseEntry")
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
		THEN NULLIF(T1."U_BaseEntry", '')
		ELSE COALESCE(T3."DocEntry",
	 T1."BaseEntry",
	 NULLIF(T1."U_MTCOWORNum", ''),
	 NULLIF(T1."U_BaseEntry", '')) END AS "BaseEntry",
	 TO_CHAR(CASE WHEN T2."Code" IN ('204',
	 '205') 
		THEN T1."U_BaseEntry"
		ELSE COALESCE(TO_NVARCHAR(T3."DocNum"),  --2026.10.14 OWOR.DocNum 是整数，不转字符串时 BaseRef 为空串报 SQL 339
	
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
			END=TO_NVARCHAR(T3."DocNum")  --2026.10.14 按字符串比较：BaseRef 为空串时隐式转数字报 SQL 339 
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
		THEN NULLIF(T1."U_BaseEntry", '')
		ELSE COALESCE(T3."DocEntry",
	 T1."BaseEntry",
	 NULLIF(T1."U_MTCOWORNum", ''),
	 NULLIF(T1."U_BaseEntry", '')) END AS "BaseEntry",
	 TO_CHAR(CASE WHEN T2."Code" IN ('204',
	 '205') 
		THEN T1."U_BaseEntry"
		ELSE COALESCE(TO_NVARCHAR(T3."DocNum"),  --2026.10.14 OWOR.DocNum 是整数，不转字符串时 BaseRef 为空串报 SQL 339
	
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
		END=TO_NVARCHAR(T3."DocNum")  --2026.10.14 按字符串比较：BaseRef 为空串时隐式转数字报 SQL 339 
		WHERE 1=1))