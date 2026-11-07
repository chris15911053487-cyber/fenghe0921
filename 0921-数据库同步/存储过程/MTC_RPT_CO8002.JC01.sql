CREATE PROCEDURE "MTC_RPT_CO8002.JC01"
(
  BPLId NVARCHAR(10),
  FcCode NVARCHAR(30),
  UserId INT
 )
LANGUAGE SQLSCRIPT
AS
BEGIN 

	DECLARE EndDate DATE;
	SELECT "T_RefDate" INTO EndDate FROM OFPR WHERE "Code"=:FcCode;
	
	TMP_OJDT=
	SELECT T2."AcctCode",T2."AcctName"
	,SUM(T1."Debit"-T1."Credit") AS "Amt"
	FROM "OJDT" T0
	JOIN JDT1 T1 ON T0."TransId"=T1."TransId"
	JOIN OACT T2 ON T1."Account"=T2."AcctCode"
	WHERE 1=1
	AND LEFT(T0."RefDate",7)=:FcCode
	GROUP BY T2."AcctCode",T2."AcctName"
	;
	
	TMP_JZ=
	SELECT 
	T0."TransCode",
	T0."TransName",
	T1."AcctCode",
	T1."AcctName",
	SUM(IFNULL("Debit",0)-IFNULL("Credit",0)) AS "Amt"
	FROM MTC_COST_0801_TOOJDT T0
	JOIN "OACT" T1 ON T0."AcctCode"=T1."AcctCode"
	WHERE T0."FcCode"='2025-04' --AND "TransCode"=:TransCode
	GROUP BY T0."TransCode",
	T0."TransName",
	T1."AcctCode",
	T1."AcctName"
	;
	
	CREATE LOCAL TEMPORARY TABLE #Pro(
	 "ID" INT
	,"项目" NVARCHAR(100)
	,"科目编码" NVARCHAR(50)
	,"科目名称" NVARCHAR(100)
	,"金额" DECIMAL(19,6)
	);
	
	INSERT INTO #Pro
	SELECT 1001,'收入',"AcctCode","AcctName",-1*"Amt" FROM :TMP_OJDT WHERE "AcctCode" LIKE '6001%'
	UNION ALL
	SELECT 2001,'成本',"AcctCode","AcctName","Amt" FROM :TMP_OJDT WHERE "AcctCode" LIKE '6401%'
	;
	
	SELECT * FROM #PRO ORDER BY "ID";
	
	DROP TABLE #PRO;
	
END