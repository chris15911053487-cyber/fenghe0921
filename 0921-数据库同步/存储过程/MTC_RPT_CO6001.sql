CREATE PROCEDURE "MTC_RPT_CO6001"
(
  UserId INT,
  FcCode NVARCHAR(30),
  IsOBTF NVARCHAR(10) --是否包含凭单
 )
LANGUAGE SQLSCRIPT
AS
BEGIN 


	TMP_YW=
	SELECT 
	T4."AcctCode",
	T4."AcctName",
	SUM(ROUND(T0."QM_Amount",2)) AS "QM_Amount"
	FROM MTC_COST_0301_INVNT T0
	JOIN OITM T1 ON T0."ItemCode"=T1."ItemCode"
	LEFT JOIN OITB T2 ON T0."ItmsGrpCod"=T2."ItmsGrpCod"
	LEFT JOIN (SELECT "ItmsGrpCod",MAX("StockAct") AS "StockAct",MAX("ShpdGdsAct") AS "ShpdGdsAct"
			FROM OGAR WHERE "PeriodCat"=LEFT(:FcCode,4) GROUP BY "ItmsGrpCod"
		) T3 ON T2."ItmsGrpCod"=T3."ItmsGrpCod"
	LEFT JOIN "OACT" T4 ON T3."StockAct"=T4."AcctCode"
	WHERE T0."FcCode" = :FcCode
	--AND T1."InvntItem"='Y'
	AND T0."CostCode"='20'
	GROUP BY T0."FcCode",
	T4."AcctCode",
	T4."AcctName"
	
	--业务端的归集的制造费用和人工费用
	UNION ALL	
	SELECT "AcctCode","AcctName"
	,SUM(ROUND("Amount",2)) AS "Amount"
	FROM MTC_COST_0311_PRODUCTEXP_ADD
	WHERE "FcCode"=:FcCode
	AND IFNULL("Amount",0)<>0
	GROUP BY "AcctCode","AcctName"
	
	
	--业务端的归集的制造费用（500103）
	UNION ALL	
	SELECT T3."AcctCode",T3."AcctName"
	,SUM(ROUND(T0."Amount",2)) AS "Amount"
	FROM MTC_COST_0311_PRODUCTEXP_ADD T0
	LEFT JOIn "OACT" T3 ON T3."AcctCode"='500103'
	WHERE "FcCode"=:FcCode
	AND IFNULL("Amount",0)<>0
	AND LEFT(T0."AcctCode",4)='5101'
	GROUP BY T3."AcctCode",T3."AcctName"
	
	--在产品
	UNION ALL
	SELECT  
	T3."AcctCode",T3."AcctName"
	,SUM(ROUND(IFNULL(T0."在产品新",0),2)) AS "在产品金额"
	FROM "MTC_COST_0322_OWOR_ZCP" T0
	LEFT JOIN OACT T3 ON CASE WHEN T0."WorType" IN ('10','20','30') THEN '500101' WHEN T0."WorType"='50' THEN '140801' END=T3."AcctCode"
	WHERE T0."期间"=:FcCode
	GROUP BY T3."AcctCode",T3."AcctName"
	;
	
	TMP_OJDT=
	SELECT T2."AcctCode",T2."AcctName",SUM(T1."Debit"-T1."Credit") AS "CW_Amount"
	FROM "OJDT" T0
	JOIN "JDT1" T1 ON T0."TransId"=T1."TransId"
	JOIN "OACT" T2 ON T1."Account"=T2."AcctCode"
	--JOIN "OFPR" T3 ON T0."RefDate" BETWEEN T3."F_RefDate" AND T3."T_RefDate"
	WHERE 1=1
	--去掉调整交易
	--AND T0."AdjTran"='N'
	AND LEFT(T0."RefDate",7)<=:FcCode
	AND (LEFT(T2."AcctCode",4) IN ('1403','1404','1405','1406','1408','1409') OR T2."AcctCode"='500101')
	GROUP BY T2."AcctCode",T2."AcctName"
	
	--期初发出商品金额减掉
	UNION ALL
    SELECT T2."AcctCode",T2."AcctName",-1*SUM(T1."Debit"-T1."Credit") AS "CW_Amount"
	FROM "OJDT" T0
	JOIN "JDT1" T1 ON T0."TransId"=T1."TransId"
	JOIN "OACT" T2 ON T1."Account"=T2."AcctCode"
	--JOIN "OFPR" T3 ON T0."RefDate" BETWEEN T3."F_RefDate" AND T3."T_RefDate"
	WHERE 1=1
	--去掉调整交易
	--AND T0."AdjTran"='N'
	AND LEFT(T0."RefDate",7)<:FcCode
	AND LEFT(T2."AcctCode",4) IN ('1406')
	GROUP BY T2."AcctCode",T2."AcctName"
	
	--5101制造费用排除掉结转制造费用的分录（PP04）
	UNION ALL
	SELECT T2."AcctCode",T2."AcctName",SUM(T1."Debit"-T1."Credit") AS "CW_Amount"
	FROM "OJDT" T0
	JOIN "JDT1" T1 ON T0."TransId"=T1."TransId"
	JOIN "OACT" T2 ON T1."Account"=T2."AcctCode"
	--JOIN "OFPR" T3 ON T0."RefDate" BETWEEN T3."F_RefDate" AND T3."T_RefDate"
	WHERE 1=1
	--去掉调整交易
	--AND T0."AdjTran"='N'
	AND (LEFT(T0."RefDate",7)<:FcCode OR (LEFT(T0."RefDate",7)=:FcCode AND IFNULL(T0."TransCode",'') NOT IN ('PP04')))
	AND LEFT(T2."AcctCode",4) IN ('5101')
	GROUP BY T2."AcctCode",T2."AcctName"
	
	--5001排除掉5001开头的，需要取PP04
	UNION ALL
	SELECT T2."AcctCode",T2."AcctName",SUM(T1."Debit"-T1."Credit") AS "CW_Amount"
	FROM "OJDT" T0
	JOIN "JDT1" T1 ON T0."TransId"=T1."TransId"
	JOIN "OACT" T2 ON T1."Account"=T2."AcctCode"
	--JOIN "OFPR" T3 ON T0."RefDate" BETWEEN T3."F_RefDate" AND T3."T_RefDate"
	WHERE 1=1
	--去掉调整交易
	--AND T0."AdjTran"='N'
	AND (LEFT(T0."RefDate",7)<:FcCode OR (LEFT(T0."RefDate",7)=:FcCode AND IFNULL(T0."TransCode",'') IN ('PP04','')))
	AND T2."AcctCode" IN ('500102','500103')
	GROUP BY T2."AcctCode",T2."AcctName"
	;
	
	TMP_MTC_COST_0801_TOOJDT=
	SELECT "AcctCode","AcctName",SUM("Debit"-"Credit") AS "0801Amount"
	FROM MTC_COST_0801_TOOJDT
	WHERE "FcCode"=:FcCode
	AND LEFT("AcctCode",4) IN ('1403','1404','1405','1406','1408','1409','5101','5001')
	--排除结转制造费用的分录
	AND "TransCode" NOT IN ('PP04')
	GROUP BY "AcctCode","AcctName"
	;
	
	
	TMP_OpenOBTF=
	SELECT T2."AcctCode",T2."AcctName"
    ,SUM(IFNULL(T1."Debit",0)-IFNULL(T1."Credit",0)) AS "BtfAmount"   ---金额
    FROM OBTF T0
    JOIN BTF1 T1 ON T0."TransId" = T1."TransId" AND T0."BatchNum" = T1."BatchNum"
    JOIN OACT T2 ON T1."Account" = T2."AcctCode"
    WHERE T0."BtfStatus"='O'
    AND LEFT(T0."RefDate",7)=:FcCode
	AND LEFT("AcctCode",4) IN ('1403','1404','1405','1406','1408','1409','5101','5001')
	--排除结转制造费用的分录
	AND T0."TransCode" NOT IN ('PP04')
     GROUP BY T2."AcctCode",T2."AcctName"
	;
	
	SELECT 
	:FcCode AS "FcCode",CASE WHEN LEFT(T0."AcctCode",4) IN ('1403','1404','1405','1408','1409') OR T0."AcctCode"='500101'
	  THEN '核对余额'
	ELSE '核对发生额'
	END AS "核对口径"
	,T0."AcctCode",T2."AcctName" AS "科目名称"
	,SUM(T0."QM_Amount") AS "业务余额"
	,SUM(T0."CW_Amount") AS "财务余额"
	,SUM(IFNULL(T0."QM_Amount",0))-SUM(IFNULL(T0."CW_Amount",0)) AS "差异金额[业务-财务]"
	,SUM(T0."0801Amount") AS "中间分录发生额"
	,SUM(IFNULL(T0."QM_Amount",0))-SUM(IFNULL(T0."CW_Amount",0))-SUM(T0."0801Amount") AS "差异金额[业务-财务-中间表]"
	,SUM(T0."BtfAmount") AS "凭单发生额"
	,SUM(IFNULL(T0."QM_Amount",0))-SUM(IFNULL(T0."CW_Amount",0))-SUM(T0."BtfAmount") AS "差异金额[业务-财务-凭单表]"
	FROM
	(
		SELECT "AcctCode","AcctName","QM_Amount",0 AS "CW_Amount",0 AS "0801Amount",0 AS "BtfAmount"  FROM :TMP_YW
		UNION ALL
		SELECT "AcctCode","AcctName",0 AS "QM_Amount","CW_Amount",0,0 FROM :TMP_OJDT
		UNION ALL
		SELECT "AcctCode","AcctName",0 AS "QM_Amount",0 AS "CW_Amount","0801Amount",0 AS "BtfAmount"
		FROM :TMP_MTC_COST_0801_TOOJDT
		UNION ALL
		SELECT "AcctCode","AcctName",0 AS "QM_Amount",0 AS "CW_Amount",0,"BtfAmount" AS "BtfAmount"
		FROM :TMP_OpenOBTF
	) T0
	LEFT JOIN OACT T2 ON T0."AcctCode"=T2."AcctCode"
	GROUP BY T0."AcctCode",T2."AcctName",CASE WHEN LEFT(T0."AcctCode",4) IN ('1403','1404','1405','1406','1408','1409','5001') OR T0."AcctCode"='500101'
	  THEN '核对余额'
	ELSE '核对发生额'
	END
	ORDER BY T0."AcctCode"
	;

END