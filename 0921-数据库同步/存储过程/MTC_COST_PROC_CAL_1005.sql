CREATE PROCEDURE "MTC_COST_PROC_CAL_1005"(IN FcCode NVARCHAR(10))
LANGUAGE SQLSCRIPT
AS
BEGIN
		--CALL "MTC_COST_PROC_CAL_1005"('2026-04')
		TMP_LIST=
		SELECT T0."AcctCode",T0."AcctName"
		,T0."TransCode",T0."TrnsCodDsc"
		,SUM(T0."OJDTFSAmt") AS "OJDTFSAmt"
		,SUM(T0."JZAmount") AS "JZAmount"
		,SUM(T0."InvntFSAmt") AS "InvntFSAmt"
		,SUM(IFNULL(T0."OJDTFSAmt",0)+IFNULL(T0."JZAmount",0)-IFNULL(T0."InvntFSAmt",0)) AS "差异金额"
		FROM
		(
			SELECT T2."AcctCode",T2."AcctName"
			,CASE WHEN LEFT(T0."TransCode",3)='PUR' OR T0."TransType" IN (20,21,18,19) THEN 'PUR' ELSE T0."TransCode" END AS "TransCode"
			,CASE WHEN LEFT(T0."TransCode",3)='PUR' OR T0."TransType" IN (20,21,18,19) THEN '采购暂估' ELSE T3."TrnsCodDsc" END AS "TrnsCodDsc"
			,SUM(T1."Debit"-T1."Credit") AS "OJDTFSAmt"
			,0 AS "JZAmount"
			,0 AS "InvntFSAmt"
			FROM "OJDT" T0
			JOIN "JDT1" T1 ON T0."TransId"=T1."TransId"
			JOIN "OACT" T2 ON T1."Account"=T2."AcctCode"
			LEFT JOIN "OTRC" T3 ON T0."TransCode"=T3."TrnsCode"
			LEFT JOIN "MTC_DocType" T7 ON T0."TransType" = T7."ObjType"
			WHERE 1=1
			AND (TO_CHAR(T0."RefDate",'YYYY-MM') = :FcCode)
			AND LEFT(T2."AcctCode",4) IN ('1403','1404','1405','1406','1408','1409')
			AND LEFT(T2."AcctCode",6)<>'140801'
			GROUP BY T2."AcctCode",T2."AcctName"
			,CASE WHEN LEFT(T0."TransCode",3)='PUR' OR T0."TransType" IN (20,21,18,19) THEN 'PUR' ELSE T0."TransCode" END
			,CASE WHEN LEFT(T0."TransCode",3)='PUR' OR T0."TransType" IN (20,21,18,19) THEN '采购暂估' ELSE T3."TrnsCodDsc" END
			
			UNION ALL
			SELECT "AcctCode","AcctName",T0."TransCode",T6."TrnsCodDsc"
			,0
			,SUM("Debit"-"Credit") AS "JZAmount"
			,0
			FROM MTC_COST_0801_TOOJDT T0
			LEFT JOIN "OTRC" T6 ON T0."TransCode"=T6."TrnsCode"
			WHERE "FcCode"=:FcCode
			AND LEFT(T0."AcctCode",4) IN ('1403','1404','1405','1406','1408','1409')
			AND LEFT(T0."AcctCode",6)<>'140801'
			GROUP BY "AcctCode","AcctName",T0."TransCode",T6."TrnsCodDsc"
			
			UNION ALL
			SELECT 
				T3."StockAct"			"存货科目"
				,T5."AcctName"			"存货科目名称"
				,CASE WHEN LEFT(T4."U_TransCode",3)='PUR' THEN 'PUR' ELSE T6."TrnsCode" END AS			"交易代码"
				,CASE WHEN LEFT(T4."U_TransCode",3)='PUR' THEN '采购暂估' ELSE T6."TrnsCodDsc" END AS			"交易名称"
				,0.00
				,0.00
				,ROUND(SUM(T1."Amount"),2) 		"InvntFSAmt"
			FROM MTC_COST_0302_INVNTDETAIL1 T1
			LEFT JOIN OITM T2 ON T1."ItemCode"=T2."ItemCode"
			LEFT JOIN (
						SELECT "ItmsGrpCod",MAX("StockAct") AS "StockAct" 
						FROm OGAR 
						WHERE "PeriodCat"=LEFT(:FcCode,4) 
						GROUP BY "ItmsGrpCod"
						) T3 ON T2."ItmsGrpCod"=T3."ItmsGrpCod"
			LEFT JOIN "@MTC_COST_IOTYPE" T4 ON T1."TransCode"=T4."Code"
			LEFT JOIN OACT T5 ON T5."AcctCode"=T3."StockAct"
			LEFT JOIN "OTRC" T6 ON T4."U_TransCode"=T6."TrnsCode"
			WHERE 1=1
			AND T1."FcCode"=:FcCode
			AND LEFT(T5."AcctCode",4) IN ('1403','1404','1405','1406','1408','1409')
			AND LEFT(T5."AcctCode",6)<>'140801'
			GROUP BY T3."StockAct",T5."AcctName",CASE WHEN LEFT(T4."U_TransCode",3)='PUR' THEN 'PUR' ELSE T6."TrnsCode" END
			,CASE WHEN LEFT(T4."U_TransCode",3)='PUR' THEN '采购暂估' ELSE T6."TrnsCodDsc" END
			
		) T0
		GROUP BY T0."AcctCode",T0."AcctName"
		,T0."TransCode",T0."TrnsCodDsc"
		ORDER BY T0."AcctCode",T0."TransCode"
		;
		
		SELECT '科目' AS "类型",T0."AcctCode",T0."AcctName" AS "科目名称"
		,T0."TransCode" AS "交易代码",T0."TrnsCodDsc" AS "交易类型"
		,(T0."OJDTFSAmt") AS "分录发生额"
		,(T0."JZAmount") AS "结转分录发生额"
		,(T0."InvntFSAmt") AS "业务发生额"
		,T0."差异金额"
		FROM :TMP_LIST T0
		
		UNION ALL 
		SELECT '合计' AS "类型",T0."AcctCode",T0."AcctName"|| '合计' AS "科目名称"
		,NULL AS "交易代码",NULL AS "交易类型"
		,SUM(T0."OJDTFSAmt") AS "分录发生额"
		,SUM(T0."JZAmount") AS "结转分录发生额"
		,SUM(T0."InvntFSAmt") AS "业务发生额"
		,SUM(IFNULL(T0."OJDTFSAmt",0)+IFNULL(T0."JZAmount",0)-IFNULL(T0."InvntFSAmt",0)) AS "差异金额"
		FROM :TMP_LIST T0 GROUP BY T0."AcctCode",T0."AcctName"
		ORDER BY "AcctCode"
		;
		
END