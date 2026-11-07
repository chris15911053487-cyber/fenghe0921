CREATE PROCEDURE "MTC_RPT_CO8003"
(
  FcCode NVARCHAR(30)
 )
LANGUAGE SQLSCRIPT
AS
BEGIN 

	SELECT 
	--主表
	T0."DocEntry"				
	,T0."U_FcCode" "期间"
	,T0."U_RefDate" "过账日期"	
	,'打开明细' AS "打开明细"	
	,T0."U_TransId" "分录"		
	,T0."U_RevOJDT" "取消日记账分录"		
	,T0."U_TransCode" "交易代码"	
	,T3."TrnsCodDsc" AS "交易名称"	
	,T0."U_Memo" "备注"			
	,T0."U_IsRev" "是否下月冲销"		
	,T0."U_RevDate" "冲销日期"
	,T1."U_Debit" AS "分录的借方金额"
	,T1."U_Credit" AS "分录的贷方金额"	
	,T2."U_GTotal" AS "业务端静态表金额"
	,T0."Remark" "备注1"
	FROM "@MTC_COST_OJDT" T0
	LEFT JOIN (	
			SELECT "DocEntry",SUM("U_Debit") AS "U_Debit",SUM("U_Credit") AS "U_Credit"
			FROM "@MTC_COST_OJDT1" GROUP BY "DocEntry"
		) T1 ON T1."DocEntry"=T0."DocEntry"
	LEFT JOIN (	
			SELECT "DocEntry",SUM("U_GTotal") AS "U_GTotal"
			FROM "@MTC_COST_OJDT2" GROUP BY "DocEntry"
		) T2 ON T2."DocEntry"=T0."DocEntry"
	LEFT JOIN OTRC T3 ON T3."TrnsCode"=T0."U_TransCode"
	WHERE 1=1
	AND T0."U_FcCode"=:FcCode
	ORDER BY T0."DocEntry";
END