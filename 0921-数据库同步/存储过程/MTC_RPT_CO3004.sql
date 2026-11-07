CREATE Procedure "MTC_RPT_CO3004"
(
	IN FcCode		NVARCHAR(30)
)
LANGUAGE SQLSCRIPT

AS	
BEGIN


SELECT 
		T2."ItmsGrpCod"			"物料组编码"
		,T6."ItmsGrpNam"		"物料组名称"
		,T3."StockAct"			"存货科目"
		,T5."AcctName"			"存货科目名称"
		,T1."TransCode"			"交易代码"
		,T4."Name"				"交易名称"
		,ROUND(SUM(T1."Quantity"),2)		"发生数量"
		,ROUND(SUM(T1."Amount"),2) 		"发生金额"
		,T4."U_TransCode"
	FROM MTC_COST_0302_INVNTDETAIL1 T1
	LEFT JOIN OITM T2 ON T1."ItemCode"=T2."ItemCode"
	LEFT JOIN (
				SELECT "ItmsGrpCod",MAX("StockAct") AS "StockAct" 
				FROm OGAR 
				WHERE "PeriodCat"='2025' 
				GROUP BY "ItmsGrpCod"
				) T3 ON T2."ItmsGrpCod"=T3."ItmsGrpCod"
	LEFT JOIN "@MTC_COST_IOTYPE" T4 ON T1."TransCode"=T4."Code"
	LEFT JOIN OACT T5 ON T5."AcctCode"=T3."StockAct"
	LEFT JOIN OITB T6 ON T6."ItmsGrpCod"=T2."ItmsGrpCod"
	WHERE 1=1
	AND T1."FcCode"=:FcCode
	GROUP BY T2."ItmsGrpCod",T6."ItmsGrpNam",T3."StockAct",T5."AcctName",T1."TransCode"	,T4."Name",T4."U_TransCode"	
	ORDER BY T3."StockAct"
	;
	
	
END