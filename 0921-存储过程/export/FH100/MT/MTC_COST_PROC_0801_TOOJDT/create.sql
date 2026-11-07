CREATE PROCEDURE "MTC_COST_PROC_0801_TOOJDT"(IN BPLId INT,IN FcCode NVARCHAR(10),IN UserCode NVARCHAR(50))
LANGUAGE SQLSCRIPT
AS
BEGIN
	
	DECLARE edate DATE;
	SELECT "T_RefDate" INTO edate FROM OFPR WHERE "Code"=:FcCode;
	
  	IF EXISTS(SELECT 1 FROM "OFPR" WHERE "PeriodStat"='Y' AND "Code"=:FcCode) THEN
  		SELECT -1 AS "Code",'账期已锁定，无法计算成本' AS "Msg" FROM DUMMY;
  		RETURN;
  	END IF;
	
	DELETE FROM MTC_COST_0801_TOOJDT WHERE "FcCode"=:FcCode;
	DELETE FROM MTC_COST_0802_OJDTBASEDETAIL WHERE "FcCode"=:FcCode;

	--MR01 --委外发票差异
	MR01 = 
	SELECT T0."Object" AS "ObjType",T0."DocEntry",T1."LineId",TO_CHAR(T0."U_DocDate",'YYYY-MM') AS "FcCode"
	,T0."U_BaseType",T1."U_CalType",T1."U_ItemCode",T1."U_Amount"
	,T1."U_StockCode",T1."U_StockName",T1."U_AcctCode",T1."U_AcctName"
	FROM "@MTC_OMRV" T0
	JOIN "@MTC_OMRV1" T1 ON T0."DocEntry"=T1."DocEntry"
	where 1=1
	AND IFNULL(T1."U_CalType",'')='ProCost'
	AND T0."U_BaseType"='WW'
	AND TO_CHAR(T0."U_DocDate",'YYYY-MM')=:FcCode
	;
	
	
	INSERT INTO MTC_COST_0801_TOOJDT(
	"BPLId",
	"FcCode",
	"TransCode",
	"TransName",
	"RefDate",
	"Memo",
	"Line_ID",
	"AcctCode",
	"AcctName",
	"Debit",
	"Credit",
	"ProfitCode",
	"OcrName1",
	"Project",
	"LineMemo",
	"CreateDate",
	"Creator"
	)
	SELECT 0,T0."FcCode",T1."TrnsCode",T1."TrnsCodDsc",:edate,T1."TrnsCodDsc",0
	,T0."U_StockCode",T0."U_StockName",ROUND(SUM(ROUND(T0."U_Amount",2)),2),0.00,NULL,NULL,NULL
	,T1."TrnsCodDsc"
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM :MR01 T0
	JOIN OTRC T1 ON T1."TrnsCode"='MR01'
	GROUP BY T0."FcCode",T1."TrnsCode",T1."TrnsCodDsc",T1."TrnsCodDsc",T0."U_StockCode",T0."U_StockName"
	HAVING ROUND(SUM(T0."U_Amount"),2)<>0
	
	UNION ALL
	SELECT 0,T0."FcCode",T1."TrnsCode",T1."TrnsCodDsc",:edate,T1."TrnsCodDsc",0
	,T0."U_AcctCode",T0."U_AcctName",0.00,ROUND(SUM(ROUND(T0."U_Amount",2)),2),NULL,NULL,NULL
	,T1."TrnsCodDsc"
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM :MR01 T0
	JOIN OTRC T1 ON T1."TrnsCode"='MR01'
	GROUP BY T0."FcCode",T1."TrnsCode",T1."TrnsCodDsc",T1."TrnsCodDsc",T0."U_AcctCode",T0."U_AcctName"
	HAVING ROUND(SUM(T0."U_Amount"),2)<>0;
	
	
	INSERT INTO "MTC_COST_0802_OJDTBASEDETAIL"
	("FcCode","TransCode","TransName","U_Type",
		"U_ObjType","U_DocEntry","U_DocNum","U_LineNum",
		"U_BaseType","U_BaseEntry","U_BaseRef","U_BaseLine",
		"U_ItemCode","U_ItemName","U_CardCode","U_CardName",
		"U_Quantity","U_Price","U_LineTotal",
		"U_PriceAfVAT","U_GTotal","U_GTotalFc","U_LineMemo",
		"U_AcctCode","U_AcctName","StockAcctCode","StockAcctName","U_Debit","U_Credit",
		"CostPrice","CostAmt","VatSum",
		"U_Currency","U_Point","U_FCDebit","U_FCCredit",
		"U_Project","U_OcrCode1","U_OcrCode2","U_OcrCode3","U_OcrCode4","U_OcrCode5"
	)
	SELECT T0."FcCode",T1."TrnsCode",T1."TrnsCodDsc",'库存重估MR01' AS "U_Type",
	T0."ObjType",T0."DocEntry",T0."DocEntry",T0."LineId",
	NULL,NULL,NULL,NULL,
	T0."U_ItemCode",NULL,NULL,NULL,
	0,0,T0."U_Amount",0,T0."U_Amount",0 AS "U_GTotalFc",'库存重估MR01' AS "U_LineMemo",
	T0."U_AcctCode",T0."U_AcctName",T0."U_StockCode",T0."U_StockName",T0."U_Amount",0.00 AS "U_Credit",
	0,0,0,NULL,NULL,NULL,NULL,
	NULL,NULL,NULL,NULL,NULL,NULL
	FROM :MR01 T0
	JOIN OTRC T1 ON T1."TrnsCode"='MR01'
	;
	
	--MR02 --手工重估分录
	MR02 = 
	SELECT T0."Object" AS "ObjType",T0."DocEntry",T1."LineId",TO_CHAR(T0."U_DocDate",'YYYY-MM') AS "FcCode"
	,T0."U_BaseType",T1."U_CalType",T1."U_ItemCode",T1."U_Amount"
	,T1."U_StockCode",T1."U_StockName",T1."U_AcctCode",T1."U_AcctName"
	FROM "@MTC_OMRV" T0
	JOIN "@MTC_OMRV1" T1 ON T0."DocEntry"=T1."DocEntry"
	where 1=1
	--AND IFNULL(T1."U_CalType",'')='ProCost'
	AND T0."U_BaseType" IN ('MRV1','MRV2')
	AND TO_CHAR(T0."U_DocDate",'YYYY-MM')=:FcCode
	;
	
	
	INSERT INTO MTC_COST_0801_TOOJDT(
	"BPLId",
	"FcCode",
	"TransCode",
	"TransName",
	"RefDate",
	"Memo",
	"Line_ID",
	"AcctCode",
	"AcctName",
	"Debit",
	"Credit",
	"ProfitCode",
	"OcrName1",
	"Project",
	"LineMemo",
	"CreateDate",
	"Creator"
	)
	SELECT 0,T0."FcCode",T1."TrnsCode",T1."TrnsCodDsc",:edate,T1."TrnsCodDsc",0
	,T0."U_StockCode",T0."U_StockName"
	,0.00 AS "Debit",-1*ROUND(SUM(ROUND(T0."U_Amount",2)),2) AS "Credit",NULL,NULL,NULL
	,T1."TrnsCodDsc"
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM :MR02 T0
	JOIN OTRC T1 ON T1."TrnsCode"='MR02'
	GROUP BY T0."FcCode",T1."TrnsCode",T1."TrnsCodDsc",T1."TrnsCodDsc",T0."U_StockCode",T0."U_StockName"
	HAVING ROUND(SUM(T0."U_Amount"),2)<>0
	UNION ALL
	SELECT 0,T0."FcCode",T1."TrnsCode",T1."TrnsCodDsc",:edate,T1."TrnsCodDsc",0
	,T0."U_AcctCode",T0."U_AcctName",-1*ROUND(SUM(ROUND(T0."U_Amount",2)),2) AS "Debit",0.00 AS "Credit",NULL,NULL,NULL
	,T1."TrnsCodDsc"
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM :MR02 T0
	JOIN OTRC T1 ON T1."TrnsCode"='MR02'
	GROUP BY T0."FcCode",T1."TrnsCode",T1."TrnsCodDsc",T1."TrnsCodDsc",T0."U_AcctCode",T0."U_AcctName"
	HAVING ROUND(SUM(T0."U_Amount"),2)<>0;
	
	
	INSERT INTO "MTC_COST_0802_OJDTBASEDETAIL"
	("FcCode","TransCode","TransName","U_Type",
		"U_ObjType","U_DocEntry","U_DocNum","U_LineNum",
		"U_BaseType","U_BaseEntry","U_BaseRef","U_BaseLine",
		"U_ItemCode","U_ItemName","U_CardCode","U_CardName",
		"U_Quantity","U_Price","U_LineTotal",
		"U_PriceAfVAT","U_GTotal","U_GTotalFc","U_LineMemo",
		"U_AcctCode","U_AcctName","StockAcctCode","StockAcctName","U_Debit","U_Credit",
		"CostPrice","CostAmt","VatSum",
		"U_Currency","U_Point","U_FCDebit","U_FCCredit",
		"U_Project","U_OcrCode1","U_OcrCode2","U_OcrCode3","U_OcrCode4","U_OcrCode5"
	)
	SELECT T0."FcCode",T1."TrnsCode",T1."TrnsCodDsc",'库存重估MR02' AS "U_Type",
	T0."ObjType",T0."DocEntry",T0."DocEntry",T0."LineId",
	NULL,NULL,NULL,NULL,
	T0."U_ItemCode",NULL,NULL,NULL,
	0,0,T0."U_Amount",0,T0."U_Amount",0 AS "U_GTotalFc",'库存重估MR02' AS "U_LineMemo",
	T0."U_AcctCode",T0."U_AcctName",T0."U_StockCode",T0."U_StockName",T0."U_Amount",0.00 AS "U_Credit",
	0,0,0,NULL,NULL,NULL,NULL,
	NULL,NULL,NULL,NULL,NULL,NULL
	FROM :MR02 T0
	JOIN OTRC T1 ON T1."TrnsCode"='MR02'
	;
	
	YF01=
	SELECT T0."BPLId",
			T0."FcCode",
			T0."ObjType",
			T0."DocEntry",
			T0."DocNum",
			T0."LineNum",
			T0."DocDate",
			T0."CostCode",
			T0."TransCode",
			T0."BaseType",
			T0."BaseEntry",
			T0."BaseNum",
			T0."BaseLine",
			T0."ItemCode",
			T0."ItemName",
			T0."ItmsGrpCod",
			T0."Quantity",
			T0."Price",
			T0."Amount",
			T0."CreateDate",
			T0."Creator",
			T0."WhsCode",
			T0."VarVal",
			T0."iLevel",
			T0."OcrCode1",
			T4."Project",
			T3."StockAct",
			T4."AcctCode" AS "其他领用科目"
			FROM MTC_COST_0302_INVNTDETAIL1 T0
			LEFT JOIN (SELECT * FROM MTC_COST_0301_INVNT WHERE "FcCode"=:FcCode AND "CostCode"='20') T1 ON T0."ItemCode"=T1."ItemCode"
			LEFT JOIN OITM T2 ON T0."ItemCode"=T2."ItemCode"
			LEFT JOIN (SELECT "ItmsGrpCod",MAX("StockAct") AS "StockAct" FROm OGAR WHERE "PeriodCat"=LEFT(:FcCode,4) GROUP BY "ItmsGrpCod"
				) T3 ON T2."ItmsGrpCod"=T3."ItmsGrpCod"
			LEFT JOIN (
				SELECT "ObjType","DocEntry","LineNum","AcctCode","Project" FROM IGN1
					UNION ALL
				SELECT "ObjType","DocEntry","LineNum","AcctCode","Project" FROM IGE1
				) T4 ON T0."ObjType"=T4."ObjType" AND T0."DocEntry"=T4."DocEntry" AND T0."LineNum"=T4."LineNum"
			WHERE T0."FcCode" = :FcCode
			--AND LEFT(T4."AcctCode",4)<>'5001'
			AND T0."CostCode"='20'
			AND T0."TransCode" IN ('I04','O04');

	INSERT INTO MTC_COST_0801_TOOJDT(
	"BPLId",
	"FcCode",
	"TransCode",
	"TransName",
	"RefDate",
	"Memo",
	"Line_ID",
	"AcctCode",
	"AcctName",
	"Debit",
	"Credit",
	"ProfitCode",
	"OcrName1",
	"Project",
	"LineMemo",
	"CreateDate",
	"Creator"
	)
	SELECT 0,:FcCode,'YF01','其他领用（物料消耗）结转',:edate,'其他领用（物料消耗）结转',0
	,T1."AcctCode",T1."AcctName",-1*ROUND(SUM(ROUND(T0."Amount",2)),2),0.00,P1."PrcCode",P1."PrcName",T0."Project"
	,'其他领用（物料消耗）结转'
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM :YF01 T0
	LEFT JOIN OACT T1 ON T0."其他领用科目"=T1."AcctCode"
	LEFT JOIN OPRC P1 ON T0."OcrCode1"=P1."PrcCode"
	GROUP BY T1."AcctCode",T1."AcctName",P1."PrcCode",P1."PrcName",T0."Project"
	HAVING ROUND(SUM(T0."Amount"),2)<>0
	UNION ALL
	SELECT 0,:FcCode,'YF01','其他领用（物料消耗）结转',:edate,'其他领用（物料消耗）结转',0
	,T1."AcctCode",T1."AcctName",0.00,-1*ROUND(SUM(ROUND(T0."Amount",2)),2),NULL,NULL,NULL
	,'其他领用（物料消耗）结转'
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM :YF01 T0
	LEFT JOIN OACT T1 ON T0."StockAct"=T1."AcctCode"
	GROUP BY T1."AcctCode",T1."AcctName";
	
	INSERT INTO "MTC_COST_0802_OJDTBASEDETAIL"
	("FcCode","TransCode","TransName","U_Type",
		"U_ObjType","U_DocEntry","U_DocNum","U_LineNum","DocDate",
		"U_BaseType","U_BaseEntry","U_BaseRef","U_BaseLine",
		"U_ItemCode","U_ItemName","U_CardCode","U_CardName",
		"U_Quantity","U_Price","U_LineTotal",
		"U_PriceAfVAT","U_GTotal","U_GTotalFc","U_LineMemo",
		"U_AcctCode","U_AcctName","StockAcctCode","StockAcctName","U_Debit","U_Credit",
		"CostPrice","CostAmt","VatSum",
		"U_Currency","U_Point","U_FCDebit","U_FCCredit",
		"U_Project","U_OcrCode1","U_OcrCode2","U_OcrCode3","U_OcrCode4","U_OcrCode5",
		"WhsCode"
	)
	SELECT T0."FcCode",T90."TrnsCode",T90."TrnsCodDsc",T90."TrnsCodDsc" AS "U_Type",
	T0."ObjType",T0."DocEntry",T0."DocEntry",T0."LineNum",T0."DocDate",
	T0."BaseType",T0."BaseEntry",CASE WHEN T0."BaseNum"='' THEN NULL ELSE T0."BaseNum" END,T0."BaseLine",
	T0."ItemCode",T0."ItemName",NULL,NULL,
	T0."Quantity",T0."Price",T0."Amount",T0."Price",T0."Amount",0 AS "U_GTotalFc",T90."TrnsCodDsc" AS "U_LineMemo",
	T1."AcctCode",T1."AcctName",T3."AcctCode" AS "U_StockCode",T3."AcctName" AS "U_StockName",
	0.00 AS "U_Debit",T0."Amount" AS "U_Credit",
	0,0,0,NULL,NULL,NULL,NULL,
	T0."Project",T0."OcrCode1",NULL,NULL,NULL,NULL,
	T0."WhsCode"
	FROM :YF01 T0
	LEFT JOIN OACT T1 ON T0."其他领用科目"=T1."AcctCode"
	LEFT JOIN OPRC P1 ON T0."OcrCode1"=P1."PrcCode"
	LEFT JOIN OACT T3 ON T0."StockAct"=T3."AcctCode"
	JOIN OTRC T90 ON T90."TrnsCode"='YF01'
	;
	
	PP1=
	SELECT T0."BPLId",
			T0."FcCode",
			T0."ObjType",
			T0."DocEntry",
			T0."DocNum",
			T0."LineNum",
			T0."DocDate",
			T0."CostCode",
			T0."TransCode",
			T0."BaseType",
			T0."BaseEntry",
			T0."BaseNum",
			T0."BaseLine",
			T0."ItemCode",
			T0."ItemName",
			T0."ItmsGrpCod",
			T0."Quantity",
			T0."Price",
			T0."Amount",
			T0."CreateDate",
			T0."Creator",
			T0."WhsCode",
			T0."VarVal",
			T0."iLevel",
			T0."OcrCode1",
			T3."StockAct",
			CASE WHEN T0."BaseType" IN ('202','MTC_OWOR') 
				THEN 
					CASE WHEN T5."U_OrdType"='50' THEN '140801' ELSE '500101' END
				WHEN T0."ObjType" IN ('15','16') THEN T0."CogsAcct"
				ELSE T0."AcctCode" END AS "AcctCode",
			T6."U_TransType",		--B01工单产出类  B03工单投入类
			T5."U_OrdType",NULL AS "CJ",NULL AS "Project"
			FROM MTC_COST_0302_INVNTDETAIL1 T0
			LEFT JOIN (SELECT * FROM MTC_COST_0301_INVNT WHERE "FcCode"=:FcCode AND "CostCode"='20') T1 ON T0."ItemCode"=T1."ItemCode"
			LEFT JOIN OITM T2 ON T0."ItemCode"=T2."ItemCode"
			LEFT JOIN (SELECT "ItmsGrpCod",MAX("StockAct") AS "StockAct" FROm OGAR WHERE "PeriodCat"=LEFT(:FcCode,4) GROUP BY "ItmsGrpCod"
				) T3 ON T2."ItmsGrpCod"=T3."ItmsGrpCod"
			LEFT JOIN (
				SELECT "ObjType","DocEntry","LineNum","AcctCode" FROM IGN1
					UNION ALL
				SELECT "ObjType","DocEntry","LineNum","AcctCode" FROM IGE1
				) T4 ON T0."ObjType"=T4."ObjType" AND T0."DocEntry"=T4."DocEntry" AND T0."LineNum"=T4."LineNum"
			LEFT JOIN (SELECT '202' AS "ObjType",T0."U_OrdType",T0."DocEntry",T1."ItmsGrpCod"
						,CASE WHEN T2."U_ItemGrpType"='A' THEN 'P017' WHEN T2."U_ItemGrpType"='B' THEN 'P016' 
								WHEN T2."U_ItemGrpType"='C' THEN 'P019' END AS "CJ"	--车间
						FROM OWOR T0
						JOIN "OITM" T1 ON T0."ItemCode"=T1."ItemCode"
						JOIN "OITB" T2 ON T1."ItmsGrpCod"=T2."ItmsGrpCod"
						UNION ALL
						SELECT 'MTC_OWOR',"U_OrdType",T0."DocEntry",T1."ItmsGrpCod"
						,CASE WHEN T2."U_ItemGrpType"='A' THEN 'P017' WHEN T2."U_ItemGrpType"='B' THEN 'P016' 
								WHEN T2."U_ItemGrpType"='C' THEN 'P019' END AS "CJ"	--车间
						FROM "@MTC_OWOR" T0
						JOIN "OITM" T1 ON T0."U_ItemCode"=T1."ItemCode"
						JOIN "OITB" T2 ON T1."ItmsGrpCod"=T2."ItmsGrpCod"
					) T5 ON T0."BaseEntry"=T5."DocEntry" AND T0."BaseType"=T5."ObjType"
			LEFT JOIN "@U_CIOTRN" T6 ON T0."BusiType"=T6."Code"
			WHERE 1=1
			AND T0."FcCode" = :FcCode
			AND T0."CostCode"='20'
			--AND T0."BaseType"='202'
			--AND T0."TransCode" NOT IN ('I04','O04')  --I04其他入库 O04其他出库 
			;
			
			INSERT INTO MTC_COST_0801_TOOJDT(
			"BPLId",
			"FcCode",
			"TransCode",
			"TransName",
			"RefDate",
			"Memo",
			"Line_ID",
			"AcctCode",
			"AcctName",
			"Debit",
			"Credit",
			"ProfitCode",
			"OcrName1",
			"LineMemo",
			"CreateDate",
			"Creator"
			)
			---------------生产领料--------------------
			SELECT 0,:FcCode,'PP01','生产领料结转',:edate,'生产领料结转',0
			,T1."AcctCode",T1."AcctName",-1*ROUND(SUM(ROUND(T0."Amount",2)),2),0.00,NULL AS "ProfitCode",NULL
			,'生产领料结转'
			,CURRENT_TIMESTAMP
			,:UserCode
			FROM :PP1 T0
			LEFT JOIN OACT T1 ON T0."AcctCode"=T1."AcctCode"
			LEFT JOIN OPRC P1 ON T0."OcrCode1"=P1."PrcCode"
			WHERE T0."U_TransType"='B03'	--工单投入
			AND T0."TransCode" IN ('O03','O07')
			GROUP BY T1."AcctCode",T1."AcctName"
			
			UNION ALL
			SELECT 0,:FcCode,'PP01','生产领料结转',:edate,'生产领料结转',0
			,T1."AcctCode",T1."AcctName",0.00,-1*ROUND(SUM(ROUND(T0."Amount",2)),2),NULL,NULL
			,'生产领料结转'
			,CURRENT_TIMESTAMP
			,:UserCode
			FROM :PP1 T0
			LEFT JOIN OACT T1 ON T0."StockAct"=T1."AcctCode"
			WHERE T0."U_TransType"='B03'	--工单投入
			AND T0."TransCode" IN ('O03','O07')
			GROUP BY T1."AcctCode",T1."AcctName"
			
			-------------------委外--------------------
			UNION ALL			
			SELECT 0,:FcCode,'WW01','委外领料结转',:edate,'委外领料结转',0
			,T1."AcctCode",T1."AcctName",-1*ROUND(SUM(ROUND(T0."Amount",2)),2),0.00,NULL,NULL
			,'委外领料结转'
			,CURRENT_TIMESTAMP
			,:UserCode
			FROM :PP1 T0
			LEFT JOIN OACT T1 ON T0."AcctCode"=T1."AcctCode"
			LEFT JOIN OPRC P1 ON T0."OcrCode1"=P1."PrcCode"
			WHERE T0."U_TransType"='B03'
			AND T0."TransCode" IN ('O08','O09')
			GROUP BY T1."AcctCode",T1."AcctName"
			
			UNION ALL
			SELECT 0,:FcCode,'WW01','委外领料结转',:edate,'委外领料结转',0
			,T1."AcctCode",T1."AcctName",0.00,-1*ROUND(SUM(ROUND(T0."Amount",2)),2),NULL,NULL
			,'委外领料结转'
			,CURRENT_TIMESTAMP
			,:UserCode
			FROM :PP1 T0
			LEFT JOIN OACT T1 ON T0."StockAct"=T1."AcctCode"
			WHERE T0."U_TransType"='B03'
			AND T0."TransCode" IN ('O08','O09')
			GROUP BY T1."AcctCode",T1."AcctName"
			
			
			-------------------IO02 形态转换单出入库--------------------
			UNION ALL			
			SELECT 0,:FcCode,'IO02','形态转换单出入库',:edate,'形态转换单出入库',0
			,T1."AcctCode",T1."AcctName",ROUND(SUM(ROUND(T0."Amount",2)),2),0.00,NULL,NULL
			,'形态转换单出入库'
			,CURRENT_TIMESTAMP
			,:UserCode
			FROM :PP1 T0
			LEFT JOIN OACT T1 ON T0."StockAct"=T1."AcctCode"
			WHERE 1=1
			AND T0."TransCode" IN ('I05')
			GROUP BY T1."AcctCode",T1."AcctName"
			
			UNION ALL
			SELECT 0,:FcCode,'IO02','形态转换单出入库',:edate,'形态转换单出入库',0
			,T1."AcctCode",T1."AcctName",0.00,-1*ROUND(SUM(ROUND(T0."Amount",2)),2),NULL,NULL
			,'形态转换单出入库'
			,CURRENT_TIMESTAMP
			,:UserCode
			FROM :PP1 T0
			LEFT JOIN OACT T1 ON T0."StockAct"=T1."AcctCode"
			WHERE 1=1
			AND T0."TransCode" IN ('O05')
			GROUP BY T1."AcctCode",T1."AcctName"
			
			
			-------------------盘点--------------------
			UNION ALL			
			SELECT 0,:FcCode,'IO01','盘点出入库结转',:edate,'盘点出入库结转',0
			,T1."AcctCode",T1."AcctName",-1*ROUND(SUM(ROUND(T0."Amount",2)),2),0.00,NULL,NULL
			,'盘点出入库结转'
			,CURRENT_TIMESTAMP
			,:UserCode
			FROM :PP1 T0
			LEFT JOIN OACT T1 ON T0."AcctCode"=T1."AcctCode"
			LEFT JOIN OPRC P1 ON T0."OcrCode1"=P1."PrcCode"
			WHERE 1=1
			AND T0."TransCode" IN ('I10','O10')
			GROUP BY T1."AcctCode",T1."AcctName"
			
			UNION ALL
			SELECT 0,:FcCode,'IO01','盘点出入库结转',:edate,'盘点出入库结转',0
			,T1."AcctCode",T1."AcctName",0.00,-1*ROUND(SUM(ROUND(T0."Amount",2)),2),NULL,NULL
			,'盘点出入库结转'
			,CURRENT_TIMESTAMP
			,:UserCode
			FROM :PP1 T0
			LEFT JOIN OACT T1 ON T0."StockAct"=T1."AcctCode"
			WHERE 1=1
			AND T0."TransCode" IN ('I10','O10')
			GROUP BY T1."AcctCode",T1."AcctName"
			
			
			---------------生产入库--------------------
			
			UNION ALL
			SELECT 0,:FcCode,'PP05','生产入库结转',:edate,'生产入库结转',0
			,T1."AcctCode",T1."AcctName",ROUND(SUM(ROUND(T0."Amount",2)),2),0.00,NULL,NULL
			,'生产入库结转'
			,CURRENT_TIMESTAMP
			,:UserCode
			FROM :PP1 T0
			LEFT JOIN OACT T1 ON T0."StockAct"=T1."AcctCode"
			WHERE T0."U_TransType"='B01'	--工单投入
			AND T0."AcctCode"='500101'		--生产领料
			GROUP BY T1."AcctCode",T1."AcctName"
			
			UNION ALL
			SELECT 0,:FcCode,'PP05','生产入库结转',:edate,'生产入库结转',0
			,T1."AcctCode",T1."AcctName",0.00,ROUND(ROUND(T0."Amount",2)-ROUND(T2."Amount",2),2),T0."CJ",NULL
			,'生产入库结转'
			,CURRENT_TIMESTAMP
			,:UserCode
			FROM (SELECT T0."AcctCode",T0."CJ",ROUND(SUM(ROUND(T0."Amount",2)),2) AS "Amount"
					FROM :PP1 T0 
					WHERE T0."U_TransType"='B01'	--工单投入
					AND T0."AcctCode"='500101' GROUP BY T0."AcctCode",T0."CJ") T0
			LEFT JOIN OACT T1 ON T0."AcctCode"=T1."AcctCode"
			LEFT JOIN (
					SELECT SUM(ROUND(T0."Amount",2)) AS "Amount"
					FROM MTC_COST_0311_PRODUCTEXP_ADD T0 WHERE T0."FcCode"=:FcCode
				) T2 ON 1=1
			
			--费用
			UNION ALL
			SELECT 0,:FcCode,'PP05','生产入库结转',:edate,'生产入库结转',0
			,T1."AcctCode",T1."AcctName",0.00,ROUND((ROUND(T0."Amount",2)),2),NULL,NULL
			,'生产入库结转'
			,CURRENT_TIMESTAMP
			,:UserCode
			FROM (
					SELECT "CalAcctCode"
					,SUM(ROUND(T0."Amount",2)) AS "Amount"
					FROM MTC_COST_0311_PRODUCTEXP_ADD T0 WHERE T0."FcCode"=:FcCode
					GROUP BY "CalAcctCode"
				) T0
			LEFT JOIN OACT T1 ON T0."CalAcctCode"=T1."AcctCode"
			WHERE 1=1
			
			
			-------------------委外入库--------------------
			UNION ALL
			SELECT 0,:FcCode,'WW03','委外入库结转',:edate,'委外入库结转',0
			,T1."AcctCode",T1."AcctName",ROUND(SUM(ROUND(T0."Amount",2)),2),0.00,NULL,NULL
			,'委外入库结转'
			,CURRENT_TIMESTAMP
			,:UserCode
			FROM :PP1 T0
			LEFT JOIN OACT T1 ON T0."StockAct"=T1."AcctCode"
			WHERE T0."U_TransType"='B01'
			AND T0."AcctCode"='140801'
			GROUP BY T1."AcctCode",T1."AcctName"
			
			UNION ALL			
			SELECT 0,:FcCode,'WW03','委外入库结转',:edate,'委外入库结转',0
			,T1."AcctCode",T1."AcctName",0.00,ROUND(T0."Amount",2)-ROUND(IFNULL(T2."Amount",0),2),NULL,NULL
			,'委外入库结转'
			,CURRENT_TIMESTAMP
			,:UserCode
			FROM (SELECT T0."AcctCode",SUM("Amount") AS "Amount" FROM :PP1 T0
					WHERE T0."U_TransType"='B01'
					AND T0."AcctCode"='140801'
					GROUP BY T0."AcctCode"
					) T0
			LEFT JOIN OACT T1 ON T0."AcctCode"=T1."AcctCode"
			LEFT JOIN (SELECT T1."Account",SUM(T1."Debit"-T1."Credit") AS "Amount" FROM "OJDT" T0
					JOIN JDT1 T1 ON T0."TransId"=T1."TransId"
					WHERE LEFT(T0."RefDate",7)=:FcCode AND T1."Account"='140802'
					GROUP BY T1."Account"
				) T2 ON 1=1
			
			--委外费用
			UNION ALL			
			SELECT 0,:FcCode,'WW03','委外入库结转',:edate,'委外入库结转',0
			,T1."AcctCode",T1."AcctName",0.00,ROUND(T0."Amount",2),NULL,NULL
			,'委外入库结转'
			,CURRENT_TIMESTAMP
			,:UserCode
			FROM (SELECT T1."Account",SUM(T1."Debit"-T1."Credit") AS "Amount" FROM "OJDT" T0
					JOIN JDT1 T1 ON T0."TransId"=T1."TransId"
					WHERE LEFT(T0."RefDate",7)=:FcCode AND T1."Account"='140802'
					GROUP BY T1."Account"
				) T0
			LEFT JOIN OACT T1 ON T0."Account"=T1."AcctCode"
			WHERE 1=1
			
			
			-----------------------发出商品（销售交货）-------------------
			UNION ALL
			SELECT 0,:FcCode,'DN01','销售发货发出商品结转',:edate,'销售发货发出商品结转',0
			,T1."AcctCode",T1."AcctName",-1*ROUND(SUM(ROUND(T0."Amount",2)),2),0.00,NULL,NULL
			,'销售发货发出商品结转'
			,CURRENT_TIMESTAMP
			,:UserCode
			FROM :PP1 T0
			LEFT JOIN OACT T1 ON T1."AcctCode"='140601'
			WHERE T0."TransCode" IN ('O01','O06')
			GROUP BY T1."AcctCode",T1."AcctName"
			
			UNION ALL			
			SELECT 0,:FcCode,'DN01','销售发货发出商品结转',:edate,'销售发货发出商品结转',0
			,T1."AcctCode",T1."AcctName",0.00,-1*ROUND(SUM(ROUND(T0."Amount",2)),2),NULL,NULL
			,'销售发货发出商品结转'
			,CURRENT_TIMESTAMP
			,:UserCode
			FROM :PP1 T0
			LEFT JOIN OACT T1 ON T0."StockAct"=T1."AcctCode"
			WHERE T0."TransCode" IN ('O01','O06')
			GROUP BY T1."AcctCode",T1."AcctName"
			
			-----------------------样品成本结转（发出商品转样品成本-国内）-------------------
			UNION ALL
			SELECT 0,:FcCode,'DN02','样品成本结转（内贸）',:edate,'样品成本结转（内贸）',0
			,T9."AcctCode",T9."AcctName",-1*ROUND(SUM(ROUND(T0."Amount",2)+ROUND(T0."Quantity"*IFNULL(T2."U_Price",0)/1.13*0.13,2)),2),0.00
			,T10."PrcCode" AS "ProfitCode",T10."PrcName" AS "OcrName1"
			,'样品成本结转（内贸）'
			,CURRENT_TIMESTAMP
			,:UserCode
			FROM :PP1 T0
			JOIN (SELECT T91."U_CustType",T0."ObjType",T0."DocEntry",T0."U_OcrCode" FROM ODLN T0
						JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE"
								) T91 ON T0."U_SalOrdType"=T91."Name"
						WHERE T91."U_BusiType"='样品销售'
					   UNION ALL
					   SELECT T91."U_CustType",T0."ObjType",T0."DocEntry",T0."U_OcrCode" FROM ORDN T0
						JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE"
								) T91 ON T0."U_SalOrdType"=T91."Name"
						WHERE T91."U_BusiType"='样品销售'
					) T1 ON T0."ObjType"=T1."ObjType" AND T0."DocEntry"=T1."DocEntry"
			LEFT JOIN (SELECT T0."U_FcCode",T1."U_ItemCode",MAX(T1."U_Price") AS "U_Price"
						FROM "@MTC_PTPRICE" T0
						INNER JOIN "@MTC_PTPRICE1" T1 ON T0."DocEntry"=T1."DocEntry"
						WHERE T0."Canceled"='N' GROUP BY T0."U_FcCode",T1."U_ItemCode"
					) T2 ON T0."FcCode"=T2."U_FcCode" AND T0."ItemCode"=T2."U_ItemCode"
			LEFT JOIN OACT T9 ON T9."AcctCode"='660106'
			LEFT JOIN OPRC T10 ON T1."U_OcrCode"=T10."PrcCode"
			WHERE T0."TransCode" IN ('O01','O06')
			AND T1."U_CustType"='国内客户'
			GROUP BY T9."AcctCode",T9."AcctName",T10."PrcCode",T10."PrcName"
			
			UNION ALL			
			SELECT 0,:FcCode,'DN02','样品成本结转（内贸）',:edate,'样品成本结转（内贸）',0
			,T9."AcctCode",T9."AcctName",0.00,-1*ROUND(SUM(ROUND(T0."Amount",2)),2),NULL,NULL
			,'样品成本结转（内贸）'
			,CURRENT_TIMESTAMP
			,:UserCode
			FROM :PP1 T0
			JOIN (SELECT T91."U_CustType",T0."ObjType",T0."DocEntry" FROM ODLN T0
						JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE"
								) T91 ON T0."U_SalOrdType"=T91."Name"
						WHERE T91."U_BusiType"='样品销售'
					   UNION ALL
					   SELECT T91."U_CustType",T0."ObjType",T0."DocEntry" FROM ORDN T0
						JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE"
								) T91 ON T0."U_SalOrdType"=T91."Name"
						WHERE T91."U_BusiType"='样品销售'
					) T1 ON T0."ObjType"=T1."ObjType" AND T0."DocEntry"=T1."DocEntry"
			LEFT JOIN (SELECT T0."U_FcCode",T1."U_ItemCode",MAX(T1."U_Price") AS "U_Price"
						FROM "@MTC_PTPRICE" T0
						INNER JOIN "@MTC_PTPRICE1" T1 ON T0."DocEntry"=T1."DocEntry"
						WHERE T0."Canceled"='N' GROUP BY T0."U_FcCode",T1."U_ItemCode"
					) T2 ON T0."FcCode"=T2."U_FcCode" AND T0."ItemCode"=T2."U_ItemCode"
			LEFT JOIN OACT T9 ON T9."AcctCode"='140601'
			WHERE T0."TransCode" IN ('O01','O06')
			AND T1."U_CustType"='国内客户'
			GROUP BY T9."AcctCode",T9."AcctName"
			
			UNION ALL			
			SELECT 0,:FcCode,'DN02','样品成本结转（内贸）',:edate,'样品成本结转（内贸）',0
			,T9."AcctCode",T9."AcctName",0.00,-1*ROUND(SUM(ROUND(T0."Quantity"*IFNULL(T2."U_Price",0)/1.13*0.13,2)),2),NULL,NULL
			,'样品成本结转（内贸）'
			,CURRENT_TIMESTAMP
			,:UserCode
			FROM :PP1 T0
			JOIN (SELECT T91."U_CustType",T0."ObjType",T0."DocEntry" FROM ODLN T0
						JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE"
								) T91 ON T0."U_SalOrdType"=T91."Name"
						WHERE T91."U_BusiType"='样品销售'
					   UNION ALL
					   SELECT T91."U_CustType",T0."ObjType",T0."DocEntry" FROM ORDN T0
						JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE"
								) T91 ON T0."U_SalOrdType"=T91."Name"
						WHERE T91."U_BusiType"='样品销售'
					) T1 ON T0."ObjType"=T1."ObjType" AND T0."DocEntry"=T1."DocEntry"
			LEFT JOIN (SELECT T0."U_FcCode",T1."U_ItemCode",MAX(T1."U_Price") AS "U_Price"
						FROM "@MTC_PTPRICE" T0
						INNER JOIN "@MTC_PTPRICE1" T1 ON T0."DocEntry"=T1."DocEntry"
						WHERE T0."Canceled"='N' GROUP BY T0."U_FcCode",T1."U_ItemCode"
					) T2 ON T0."FcCode"=T2."U_FcCode" AND T0."ItemCode"=T2."U_ItemCode"
			LEFT JOIN OACT T9 ON T9."AcctCode"='22210106'
			WHERE T0."TransCode" IN ('O01','O06')
			AND T1."U_CustType"='国内客户'
			GROUP BY T9."AcctCode",T9."AcctName"
			
			
			-----------------------样品成本结转（发出商品转样品成本-国际）-------------------
			UNION ALL
			SELECT 0,:FcCode,'DN04','样品成本结转（外贸）',:edate,'样品成本结转（外贸）',0
			,T9."AcctCode",T9."AcctName",-1*ROUND(SUM(ROUND(T0."Amount",2)+ROUND(T0."Amount"*1.5*0.13,2)),2),0.00,T10."PrcCode",T10."PrcName"
			,'样品成本结转（外贸）'
			,CURRENT_TIMESTAMP
			,:UserCode
			FROM :PP1 T0
			JOIN (SELECT T91."U_CustType",T0."ObjType",T0."DocEntry",T0."U_OcrCode" FROM ODLN T0
						JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE"
								) T91 ON T0."U_SalOrdType"=T91."Name"
						WHERE T91."U_BusiType"='样品销售'
					   UNION ALL
					   SELECT T91."U_CustType",T0."ObjType",T0."DocEntry",T0."U_OcrCode" FROM ORDN T0
						JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE"
								) T91 ON T0."U_SalOrdType"=T91."Name"
						WHERE T91."U_BusiType"='样品销售'
					) T1 ON T0."ObjType"=T1."ObjType" AND T0."DocEntry"=T1."DocEntry"
			LEFT JOIN (SELECT T0."U_FcCode",T1."U_ItemCode",MAX(T1."U_Price") AS "U_Price"
						FROM "@MTC_PTPRICE" T0
						INNER JOIN "@MTC_PTPRICE1" T1 ON T0."DocEntry"=T1."DocEntry"
						WHERE T0."Canceled"='N' GROUP BY T0."U_FcCode",T1."U_ItemCode"
					) T2 ON T0."FcCode"=T2."U_FcCode" AND T0."ItemCode"=T2."U_ItemCode"
			LEFT JOIN OACT T9 ON T9."AcctCode"='660106'
			LEFT JOIN OPRC T10 ON T1."U_OcrCode"=T10."PrcCode"
			WHERE T0."TransCode" IN ('O01','O06')
			AND T1."U_CustType"='国外客户'
			GROUP BY T9."AcctCode",T9."AcctName",T10."PrcCode",T10."PrcName"
			
			UNION ALL			
			SELECT 0,:FcCode,'DN04','样品成本结转（外贸）',:edate,'样品成本结转（外贸）',0
			,T9."AcctCode",T9."AcctName",0.00,-1*ROUND(SUM(ROUND(T0."Amount",2)),2),NULL,NULL
			,'样品成本结转（外贸）'
			,CURRENT_TIMESTAMP
			,:UserCode
			FROM :PP1 T0
			JOIN (SELECT T91."U_CustType",T0."ObjType",T0."DocEntry" FROM ODLN T0
						JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE"
								) T91 ON T0."U_SalOrdType"=T91."Name"
						WHERE T91."U_BusiType"='样品销售'
					   UNION ALL
					   SELECT T91."U_CustType",T0."ObjType",T0."DocEntry" FROM ORDN T0
						JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE"
								) T91 ON T0."U_SalOrdType"=T91."Name"
						WHERE T91."U_BusiType"='样品销售'
					) T1 ON T0."ObjType"=T1."ObjType" AND T0."DocEntry"=T1."DocEntry"
			LEFT JOIN (SELECT T0."U_FcCode",T1."U_ItemCode",MAX(T1."U_Price") AS "U_Price"
						FROM "@MTC_PTPRICE" T0
						INNER JOIN "@MTC_PTPRICE1" T1 ON T0."DocEntry"=T1."DocEntry"
						WHERE T0."Canceled"='N' GROUP BY T0."U_FcCode",T1."U_ItemCode"
					) T2 ON T0."FcCode"=T2."U_FcCode" AND T0."ItemCode"=T2."U_ItemCode"
			LEFT JOIN OACT T9 ON T9."AcctCode"='140601'
			WHERE T0."TransCode" IN ('O01','O06')
			AND T1."U_CustType"='国外客户'
			GROUP BY T9."AcctCode",T9."AcctName"
			
			UNION ALL			
			SELECT 0,:FcCode,'DN04','样品成本结转（外贸）',:edate,'样品成本结转（外贸）',0
			,T9."AcctCode",T9."AcctName",0.00,-1*ROUND(SUM(ROUND(T0."Amount"*1.5*0.13,2)),2),NULL,NULL
			,'样品成本结转（外贸）'
			,CURRENT_TIMESTAMP
			,:UserCode
			FROM :PP1 T0
			JOIN (SELECT T91."U_CustType",T0."ObjType",T0."DocEntry" FROM ODLN T0
						JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE"
								) T91 ON T0."U_SalOrdType"=T91."Name"
						WHERE T91."U_BusiType"='样品销售'
					   UNION ALL
					   SELECT T91."U_CustType",T0."ObjType",T0."DocEntry" FROM ORDN T0
						JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE"
								) T91 ON T0."U_SalOrdType"=T91."Name"
						WHERE T91."U_BusiType"='样品销售'
					) T1 ON T0."ObjType"=T1."ObjType" AND T0."DocEntry"=T1."DocEntry"
			LEFT JOIN (SELECT T0."U_FcCode",T1."U_ItemCode",MAX(T1."U_Price") AS "U_Price"
						FROM "@MTC_PTPRICE" T0
						INNER JOIN "@MTC_PTPRICE1" T1 ON T0."DocEntry"=T1."DocEntry"
						WHERE T0."Canceled"='N' GROUP BY T0."U_FcCode",T1."U_ItemCode"
					) T2 ON T0."FcCode"=T2."U_FcCode" AND T0."ItemCode"=T2."U_ItemCode"
			LEFT JOIN OACT T9 ON T9."AcctCode"='22210106'
			WHERE T0."TransCode" IN ('O01','O06')
			AND T1."U_CustType"='国外客户'
			GROUP BY T9."AcctCode",T9."AcctName"
			;
			
			
			INSERT INTO "MTC_COST_0802_OJDTBASEDETAIL"
			("FcCode","TransCode","TransName","U_Type",
				"U_ObjType","U_DocEntry","U_DocNum","U_LineNum","DocDate",
				"U_BaseType","U_BaseEntry","U_BaseRef","U_BaseLine",
				"U_ItemCode","U_ItemName","U_CardCode","U_CardName",
				"U_Quantity","U_Price","U_LineTotal",
				"U_PriceAfVAT","U_GTotal","U_GTotalFc","U_LineMemo",
				"U_AcctCode","U_AcctName","StockAcctCode","StockAcctName","U_Debit","U_Credit",
				"CostPrice","CostAmt","VatSum",
				"U_Currency","U_Point","U_FCDebit","U_FCCredit",
				"U_Project","U_OcrCode1","U_OcrCode2","U_OcrCode3","U_OcrCode4","U_OcrCode5",
				"WhsCode"
			)
			SELECT T0."FcCode",T90."TrnsCode",T90."TrnsCodDsc",T90."TrnsCodDsc" AS "U_Type",
			T0."ObjType",T0."DocEntry",T0."DocEntry",T0."LineNum",T0."DocDate",
			T0."BaseType",T0."BaseEntry",T0."BaseNum",T0."BaseLine",
			T0."ItemCode",T0."ItemName",NULL,NULL,
			T0."Quantity",T0."Price",T0."Amount",T0."Price",T0."Amount",0 AS "U_GTotalFc",T90."TrnsCodDsc" AS "U_LineMemo",
			T1."AcctCode",T1."AcctName",T3."AcctCode" AS "U_StockCode",T3."AcctName" AS "U_StockName",
			0.00 AS "U_Debit",T0."Amount" AS "U_Credit",
			0,0,0,NULL,NULL,NULL,NULL,
			T0."Project",T0."OcrCode1",NULL,NULL,NULL,NULL,
			T0."WhsCode"
			FROM :PP1 T0
			LEFT JOIN OACT T1 ON T0."AcctCode"=T1."AcctCode"
			LEFT JOIN OPRC P1 ON T0."OcrCode1"=P1."PrcCode"
			LEFT JOIN OACT T3 ON T0."StockAct"=T3."AcctCode"
			JOIN OTRC T90 ON T90."TrnsCode"='PP01' --生产领料
			WHERE T0."U_TransType"='B03'	--工单投入
					AND T0."TransCode" IN ('O03','O07')
			;
			
			
			INSERT INTO "MTC_COST_0802_OJDTBASEDETAIL"
			("FcCode","TransCode","TransName","U_Type",
				"U_ObjType","U_DocEntry","U_DocNum","U_LineNum","DocDate",
				"U_BaseType","U_BaseEntry","U_BaseRef","U_BaseLine",
				"U_ItemCode","U_ItemName","U_CardCode","U_CardName",
				"U_Quantity","U_Price","U_LineTotal",
				"U_PriceAfVAT","U_GTotal","U_GTotalFc","U_LineMemo",
				"U_AcctCode","U_AcctName","StockAcctCode","StockAcctName","U_Debit","U_Credit",
				"CostPrice","CostAmt","VatSum",
				"U_Currency","U_Point","U_FCDebit","U_FCCredit",
				"U_Project","U_OcrCode1","U_OcrCode2","U_OcrCode3","U_OcrCode4","U_OcrCode5",
				"WhsCode"
			)
			SELECT T0."FcCode",T90."TrnsCode",T90."TrnsCodDsc",T90."TrnsCodDsc" AS "U_Type",
			T0."ObjType",T0."DocEntry",T0."DocEntry",T0."LineNum",T0."DocDate",
			T0."BaseType",T0."BaseEntry",T0."BaseNum",T0."BaseLine",
			T0."ItemCode",T0."ItemName",NULL,NULL,
			T0."Quantity",T0."Price",T0."Amount",T0."Price",T0."Amount",0 AS "U_GTotalFc",T90."TrnsCodDsc" AS "U_LineMemo",
			T1."AcctCode",T1."AcctName",T3."AcctCode" AS "U_StockCode",T3."AcctName" AS "U_StockName",
			0.00 AS "U_Debit",T0."Amount" AS "U_Credit",
			0,0,0,NULL,NULL,NULL,NULL,
			T0."Project",T0."OcrCode1",NULL,NULL,NULL,NULL,
			T0."WhsCode"
			FROM :PP1 T0
			LEFT JOIN OACT T1 ON T0."AcctCode"=T1."AcctCode"
			LEFT JOIN OPRC P1 ON T0."OcrCode1"=P1."PrcCode"
			LEFT JOIN OACT T3 ON T0."StockAct"=T3."AcctCode"
			JOIN OTRC T90 ON T90."TrnsCode"='WW01'	--委外领料
			WHERE T0."U_TransType"='B03'	--工单投入
			AND T0."TransCode" IN ('O08','O09')
			;
			
			
			INSERT INTO "MTC_COST_0802_OJDTBASEDETAIL"
			("FcCode","TransCode","TransName","U_Type",
				"U_ObjType","U_DocEntry","U_DocNum","U_LineNum","DocDate",
				"U_BaseType","U_BaseEntry","U_BaseRef","U_BaseLine",
				"U_ItemCode","U_ItemName","U_CardCode","U_CardName",
				"U_Quantity","U_Price","U_LineTotal",
				"U_PriceAfVAT","U_GTotal","U_GTotalFc","U_LineMemo",
				"U_AcctCode","U_AcctName","StockAcctCode","StockAcctName","U_Debit","U_Credit",
				"CostPrice","CostAmt","VatSum",
				"U_Currency","U_Point","U_FCDebit","U_FCCredit",
				"U_Project","U_OcrCode1","U_OcrCode2","U_OcrCode3","U_OcrCode4","U_OcrCode5",
				"WhsCode"
			)
			SELECT T0."FcCode",T90."TrnsCode",T90."TrnsCodDsc",T90."TrnsCodDsc" AS "U_Type",
			T0."ObjType",T0."DocEntry",T0."DocEntry",T0."LineNum",T0."DocDate",
			T0."BaseType",T0."BaseEntry",T0."BaseNum",T0."BaseLine",
			T0."ItemCode",T0."ItemName",NULL,NULL,
			T0."Quantity",T0."Price",T0."Amount",T0."Price",T0."Amount",0 AS "U_GTotalFc",T90."TrnsCodDsc" AS "U_LineMemo",
			T3."AcctCode",T3."AcctName",T3."AcctCode" AS "U_StockCode",T3."AcctName" AS "U_StockName",
			CASE WHEN T90."TrnsCode"='I05' THEN T0."Amount" ELSE 0 END AS "U_Debit",
			CASE WHEN T90."TrnsCode"='O05' THEN -1*T0."Amount" ELSE 0 END AS "U_Credit",
			0,0,0,NULL,NULL,NULL,NULL,
			T0."Project",T0."OcrCode1",NULL,NULL,NULL,NULL,
			T0."WhsCode"
			FROM :PP1 T0
			LEFT JOIN OPRC P1 ON T0."OcrCode1"=P1."PrcCode"
			LEFT JOIN OACT T3 ON T0."StockAct"=T3."AcctCode"
			JOIN OTRC T90 ON T90."TrnsCode"='IO02'	--形态转换单入库
			WHERE 1=1
			AND T0."TransCode" IN ('I05','O05')
			;
			
			
			INSERT INTO "MTC_COST_0802_OJDTBASEDETAIL"
			("FcCode","TransCode","TransName","U_Type",
				"U_ObjType","U_DocEntry","U_DocNum","U_LineNum","DocDate",
				"U_BaseType","U_BaseEntry","U_BaseRef","U_BaseLine",
				"U_ItemCode","U_ItemName","U_CardCode","U_CardName",
				"U_Quantity","U_Price","U_LineTotal",
				"U_PriceAfVAT","U_GTotal","U_GTotalFc","U_LineMemo",
				"U_AcctCode","U_AcctName","StockAcctCode","StockAcctName","U_Debit","U_Credit",
				"CostPrice","CostAmt","VatSum",
				"U_Currency","U_Point","U_FCDebit","U_FCCredit",
				"U_Project","U_OcrCode1","U_OcrCode2","U_OcrCode3","U_OcrCode4","U_OcrCode5",
				"WhsCode"
			)
			SELECT T0."FcCode",T90."TrnsCode",T90."TrnsCodDsc",T90."TrnsCodDsc" AS "U_Type",
			T0."ObjType",T0."DocEntry",T0."DocEntry",T0."LineNum",T0."DocDate",
			T0."BaseType",T0."BaseEntry",T0."BaseNum",T0."BaseLine",
			T0."ItemCode",T0."ItemName",NULL,NULL,
			T0."Quantity",T0."Price",T0."Amount",T0."Price",T0."Amount",0 AS "U_GTotalFc",T90."TrnsCodDsc" AS "U_LineMemo",
			T1."AcctCode",T1."AcctName",T3."AcctCode" AS "U_StockCode",T3."AcctName" AS "U_StockName",
			-1*T0."Amount" AS "U_Debit",0.00 AS "U_Credit",
			0,0,0,NULL,NULL,NULL,NULL,
			T0."Project",T0."OcrCode1",NULL,NULL,NULL,NULL,
			T0."WhsCode"
			FROM :PP1 T0
			LEFT JOIN OACT T1 ON T0."AcctCode"=T1."AcctCode"
			LEFT JOIN OPRC P1 ON T0."OcrCode1"=P1."PrcCode"
			LEFT JOIN OACT T3 ON T0."StockAct"=T3."AcctCode"
			JOIN OTRC T90 ON T90."TrnsCode"='IO01'	--盘点
			WHERE 1=1
			AND T0."TransCode" IN ('I10','O10')
			;
			
			INSERT INTO "MTC_COST_0802_OJDTBASEDETAIL"
			("FcCode","TransCode","TransName","U_Type",
				"U_ObjType","U_DocEntry","U_DocNum","U_LineNum","DocDate",
				"U_BaseType","U_BaseEntry","U_BaseRef","U_BaseLine",
				"U_ItemCode","U_ItemName","U_CardCode","U_CardName",
				"U_Quantity","U_Price","U_LineTotal",
				"U_PriceAfVAT","U_GTotal","U_GTotalFc","U_LineMemo",
				"U_AcctCode","U_AcctName","StockAcctCode","StockAcctName","U_Debit","U_Credit",
				"CostPrice","CostAmt","VatSum",
				"U_Currency","U_Point","U_FCDebit","U_FCCredit",
				"U_Project","U_OcrCode1","U_OcrCode2","U_OcrCode3","U_OcrCode4","U_OcrCode5",
				"WhsCode"
			)
			SELECT T0."FcCode",T90."TrnsCode",T90."TrnsCodDsc",T90."TrnsCodDsc" AS "U_Type",
			T0."ObjType",T0."DocEntry",T0."DocEntry",T0."LineNum",T0."DocDate",
			T0."BaseType",T0."BaseEntry",T0."BaseNum",T0."BaseLine",
			T0."ItemCode",T0."ItemName",NULL,NULL,
			T0."Quantity",T0."Price",T0."Amount",T0."Price",T0."Amount",0 AS "U_GTotalFc",T90."TrnsCodDsc" AS "U_LineMemo",
			T3."AcctCode",T3."AcctName",T3."AcctCode" AS "U_StockCode",T3."AcctName" AS "U_StockName",
			ROUND(T0."Amount",2) AS "U_Debit",0.00 AS "U_Credit",
			0,0,0,NULL,NULL,NULL,NULL,
			T0."Project",T0."OcrCode1",NULL,NULL,NULL,NULL,
			T0."WhsCode"
			FROM :PP1 T0
			LEFT JOIN OPRC P1 ON T0."OcrCode1"=P1."PrcCode"
			LEFT JOIN OACT T3 ON T0."StockAct"=T3."AcctCode"
			JOIN OTRC T90 ON T90."TrnsCode"='PP05'
			WHERE T0."U_TransType"='B01'	--工单投入
			AND T0."AcctCode"='500101'		--生产领料
			;
			
			INSERT INTO "MTC_COST_0802_OJDTBASEDETAIL"
			("FcCode","TransCode","TransName","U_Type",
				"U_ObjType","U_DocEntry","U_DocNum","U_LineNum","DocDate",
				"U_BaseType","U_BaseEntry","U_BaseRef","U_BaseLine",
				"U_ItemCode","U_ItemName","U_CardCode","U_CardName",
				"U_Quantity","U_Price","U_LineTotal",
				"U_PriceAfVAT","U_GTotal","U_GTotalFc","U_LineMemo",
				"U_AcctCode","U_AcctName","StockAcctCode","StockAcctName","U_Debit","U_Credit",
				"CostPrice","CostAmt","VatSum",
				"U_Currency","U_Point","U_FCDebit","U_FCCredit",
				"U_Project","U_OcrCode1","U_OcrCode2","U_OcrCode3","U_OcrCode4","U_OcrCode5",
				"WhsCode"
			)
			SELECT T0."FcCode",T90."TrnsCode",T90."TrnsCodDsc",T90."TrnsCodDsc" AS "U_Type",
			T0."ObjType",T0."DocEntry",T0."DocEntry",T0."LineNum",T0."DocDate",
			T0."BaseType",T0."BaseEntry",CASE WHEN T0."BaseNum"='' THEN NULL ELSE T0."BaseNum" END,T0."BaseLine",
			T0."ItemCode",T0."ItemName",NULL,NULL,
			T0."Quantity",T0."Price",T0."Amount",T0."Price",T0."Amount",0 AS "U_GTotalFc",T90."TrnsCodDsc" AS "U_LineMemo",
			T3."AcctCode",T3."AcctName",T3."AcctCode" AS "U_StockCode",T3."AcctName" AS "U_StockName",
			ROUND(T0."Amount",2) AS "U_Debit",0.00 AS "U_Credit",
			0,0,0,NULL,NULL,NULL,NULL,
			T0."Project",T0."OcrCode1",NULL,NULL,NULL,NULL,
			T0."WhsCode"
			FROM :PP1 T0
			LEFT JOIN OPRC P1 ON T0."OcrCode1"=P1."PrcCode"
			LEFT JOIN OACT T3 ON T0."StockAct"=T3."AcctCode"
			JOIN OTRC T90 ON T90."TrnsCode"='WW03'
			WHERE T0."U_TransType"='B01'
			AND T0."AcctCode"='140801'
			;
			
			INSERT INTO "MTC_COST_0802_OJDTBASEDETAIL"
			("FcCode","TransCode","TransName","U_Type",
				"U_ObjType","U_DocEntry","U_DocNum","U_LineNum","DocDate",
				"U_BaseType","U_BaseEntry","U_BaseRef","U_BaseLine",
				"U_ItemCode","U_ItemName","U_CardCode","U_CardName",
				"U_Quantity","U_Price","U_LineTotal",
				"U_PriceAfVAT","U_GTotal","U_GTotalFc","U_LineMemo",
				"U_AcctCode","U_AcctName","StockAcctCode","StockAcctName","U_Debit","U_Credit",
				"CostPrice","CostAmt","VatSum",
				"U_Currency","U_Point","U_FCDebit","U_FCCredit",
				"U_Project","U_OcrCode1","U_OcrCode2","U_OcrCode3","U_OcrCode4","U_OcrCode5",
				"WhsCode"
			)
			SELECT T0."FcCode",T90."TrnsCode",T90."TrnsCodDsc",T90."TrnsCodDsc" AS "U_Type",
			T0."ObjType",T0."DocEntry",T0."DocEntry",T0."LineNum",T0."DocDate",
			T0."BaseType",T0."BaseEntry",CASE WHEN T0."BaseNum"='' THEN NULL ELSE T0."BaseNum" END,T0."BaseLine",
			T0."ItemCode",T0."ItemName",NULL,NULL,
			T0."Quantity",T0."Price",T0."Amount",T0."Price",T0."Amount",0 AS "U_GTotalFc",T90."TrnsCodDsc" AS "U_LineMemo",
			T1."AcctCode",T1."AcctName",T3."AcctCode" AS "U_StockCode",T3."AcctName" AS "U_StockName",
			-1*T0."Amount" AS "U_Debit",0.00 AS "U_Credit",
			0,0,0,NULL,NULL,NULL,NULL,
			T0."Project",T0."OcrCode1",NULL,NULL,NULL,NULL,
			T0."WhsCode"
			FROM :PP1 T0
			LEFT JOIN OACT T1 ON T0."AcctCode"='140601'
			LEFT JOIN OPRC P1 ON T0."OcrCode1"=P1."PrcCode"
			LEFT JOIN OACT T3 ON T0."StockAct"=T3."AcctCode"
			JOIN OTRC T90 ON T90."TrnsCode"='DN01'	--销售发货发出商品结转
			WHERE 1=1
			AND T0."TransCode" IN ('O01','O06')
			;
			
			INSERT INTO "MTC_COST_0802_OJDTBASEDETAIL"
			("FcCode","TransCode","TransName","U_Type",
				"U_ObjType","U_DocEntry","U_DocNum","U_LineNum","DocDate",
				"U_BaseType","U_BaseEntry","U_BaseRef","U_BaseLine",
				"U_ItemCode","U_ItemName","U_CardCode","U_CardName",
				"U_Quantity","U_Price","U_LineTotal",
				"U_PriceAfVAT","U_GTotal","U_GTotalFc","U_LineMemo",
				"U_AcctCode","U_AcctName","StockAcctCode","StockAcctName","U_Debit","U_Credit",
				"CostPrice","CostAmt","VatSum",
				"U_Currency","U_Point","U_FCDebit","U_FCCredit",
				"U_Project","U_OcrCode1","U_OcrCode2","U_OcrCode3","U_OcrCode4","U_OcrCode5",
				"WhsCode"
			)
			SELECT T0."FcCode",T90."TrnsCode",T90."TrnsCodDsc",T90."TrnsCodDsc" AS "U_Type",
			T0."ObjType",T0."DocEntry",T0."DocEntry",T0."LineNum",T0."DocDate",
			T0."BaseType",T0."BaseEntry",CASE WHEN T0."BaseNum"='' THEN NULL ELSE T0."BaseNum" END,T0."BaseLine",
			T0."ItemCode",T0."ItemName",NULL,NULL,
			T0."Quantity",T0."Price",T0."Amount",T0."Price",T0."Amount",0 AS "U_GTotalFc",T90."TrnsCodDsc" AS "U_LineMemo",
			T9."AcctCode",T9."AcctName",T8."AcctCode" AS "U_StockCode",T8."AcctName" AS "U_StockName",
			-1*T0."Amount" AS "U_Debit",0.00 AS "U_Credit",
			0,0,-1*ROUND((ROUND(T0."Quantity"*IFNULL(T2."U_Price",0)/1.13*0.13,2)),2) AS "VatSum",NULL,NULL,NULL,NULL,
			T0."Project",T0."OcrCode1",NULL,NULL,NULL,NULL,
			T0."WhsCode"
			FROM :PP1 T0
			JOIN (SELECT T91."U_CustType",T0."ObjType",T0."DocEntry",T0."U_OcrCode" FROM ODLN T0
						JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE"
								) T91 ON T0."U_SalOrdType"=T91."Name"
						WHERE T91."U_BusiType"='样品销售'
					   UNION ALL
					   SELECT T91."U_CustType",T0."ObjType",T0."DocEntry",T0."U_OcrCode" FROM ORDN T0
						JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE"
								) T91 ON T0."U_SalOrdType"=T91."Name"
						WHERE T91."U_BusiType"='样品销售'
					) T1 ON T0."ObjType"=T1."ObjType" AND T0."DocEntry"=T1."DocEntry"
			LEFT JOIN (SELECT T0."U_FcCode",T1."U_ItemCode",MAX(T1."U_Price") AS "U_Price"
						FROM "@MTC_PTPRICE" T0
						INNER JOIN "@MTC_PTPRICE1" T1 ON T0."DocEntry"=T1."DocEntry"
						WHERE T0."Canceled"='N' GROUP BY T0."U_FcCode",T1."U_ItemCode"
					) T2 ON T0."FcCode"=T2."U_FcCode" AND T0."ItemCode"=T2."U_ItemCode"
			LEFT JOIN OACT T8 ON T8."AcctCode"='660106'
			LEFT JOIN OACT T9 ON T9."AcctCode"='140601'
			LEFT JOIN OPRC T10 ON T1."U_OcrCode"=T10."PrcCode"
			JOIN OTRC T90 ON T90."TrnsCode"='DN02'	--样品成本结转（内贸）
			WHERE T0."TransCode" IN ('O01','O06')
			AND T1."U_CustType"='国内客户'
			;
			
			
			INSERT INTO "MTC_COST_0802_OJDTBASEDETAIL"
			("FcCode","TransCode","TransName","U_Type",
				"U_ObjType","U_DocEntry","U_DocNum","U_LineNum","DocDate",
				"U_BaseType","U_BaseEntry","U_BaseRef","U_BaseLine",
				"U_ItemCode","U_ItemName","U_CardCode","U_CardName",
				"U_Quantity","U_Price","U_LineTotal",
				"U_PriceAfVAT","U_GTotal","U_GTotalFc","U_LineMemo",
				"U_AcctCode","U_AcctName","StockAcctCode","StockAcctName","U_Debit","U_Credit",
				"CostPrice","CostAmt","VatSum",
				"U_Currency","U_Point","U_FCDebit","U_FCCredit",
				"U_Project","U_OcrCode1","U_OcrCode2","U_OcrCode3","U_OcrCode4","U_OcrCode5",
				"WhsCode"
			)
			SELECT T0."FcCode",T90."TrnsCode",T90."TrnsCodDsc",T90."TrnsCodDsc" AS "U_Type",
			T0."ObjType",T0."DocEntry",T0."DocEntry",T0."LineNum",T0."DocDate",
			T0."BaseType",T0."BaseEntry",CASE WHEN T0."BaseNum"='' THEN NULL ELSE T0."BaseNum" END,T0."BaseLine",
			T0."ItemCode",T0."ItemName",NULL,NULL,
			T0."Quantity",T0."Price",T0."Amount",T0."Price",T0."Amount",0 AS "U_GTotalFc",T90."TrnsCodDsc" AS "U_LineMemo",
			T9."AcctCode",T9."AcctName",T8."AcctCode" AS "U_StockCode",T8."AcctName" AS "U_StockName",
			-1*T0."Amount" AS "U_Debit",0.00 AS "U_Credit",
			0,0,-1*ROUND((ROUND(T0."Amount"*1.5*0.13,2)),2) AS "VatSum",NULL,NULL,NULL,NULL,
			T0."Project",T0."OcrCode1",NULL,NULL,NULL,NULL,
			T0."WhsCode"
			FROM :PP1 T0
			JOIN (SELECT T91."U_CustType",T0."ObjType",T0."DocEntry",T0."U_OcrCode" FROM ODLN T0
						JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE"
								) T91 ON T0."U_SalOrdType"=T91."Name"
						WHERE T91."U_BusiType"='样品销售'
					   UNION ALL
					   SELECT T91."U_CustType",T0."ObjType",T0."DocEntry",T0."U_OcrCode" FROM ORDN T0
						JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE"
								) T91 ON T0."U_SalOrdType"=T91."Name"
						WHERE T91."U_BusiType"='样品销售'
					) T1 ON T0."ObjType"=T1."ObjType" AND T0."DocEntry"=T1."DocEntry"
			LEFT JOIN (SELECT T0."U_FcCode",T1."U_ItemCode",MAX(T1."U_Price") AS "U_Price"
						FROM "@MTC_PTPRICE" T0
						INNER JOIN "@MTC_PTPRICE1" T1 ON T0."DocEntry"=T1."DocEntry"
						WHERE T0."Canceled"='N' GROUP BY T0."U_FcCode",T1."U_ItemCode"
					) T2 ON T0."FcCode"=T2."U_FcCode" AND T0."ItemCode"=T2."U_ItemCode"
			LEFT JOIN OACT T8 ON T8."AcctCode"='660106'
			LEFT JOIN OACT T9 ON T9."AcctCode"='140601'
			LEFT JOIN OPRC T10 ON T1."U_OcrCode"=T10."PrcCode"
			JOIN OTRC T90 ON T90."TrnsCode"='DN04'	--样品成本结转（内贸）
			WHERE T0."TransCode" IN ('O01','O06')
			AND T1."U_CustType"='国外客户'
			;
			
			-----------------------销售成本结转（扣除样品）-------------------
			INSERT INTO MTC_COST_0801_TOOJDT(
			"BPLId",
			"FcCode",
			"TransCode",
			"TransName",
			"RefDate",
			"Memo",
			"Line_ID",
			"AcctCode",
			"AcctName",
			"Debit",
			"Credit",
			"ProfitCode",
			"OcrName1",
			"LineMemo",
			"CreateDate",
			"Creator"
			)
			SELECT 0,:FcCode,'DN03','主营业务成本结转',:edate,'主营业务成本结转',0
			,T9."AcctCode",T9."AcctName"
			--,ROUND(SUM(ROUND(T2."InvQty"*CASE WHEN T1."DocDate"<='2024-12-31' THEN T1."U_InitPrice" ELSE T."Price" END,2)),2)
			,ROUND(SUM(ROUND(T2."CostAmt",2)),2)
			,0.00,NULL,NULL
			,'主营业务成本结转'
			,CURRENT_TIMESTAMP
			,:UserCode
			FROM (
					SELECT T91."U_CustType",T0."ObjType",T1."DocEntry",T1."LineNum",T1."BaseType",T1."BaseEntry",T1."BaseLine"
					,CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END*T1."Quantity" AS "InvQty"
					,CASE WHEN T23."DocDate"<='2024-12-31' THEN T21."U_InitPrice" ELSE COALESCE(T22."Price",T32."Price") END
						*CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END *T1."Quantity" AS "CostAmt"
					FROM OINV T0 JOIN INV1 T1 ON T0."DocEntry"=T1."DocEntry"
					
					--关联交货单的单价
					LEFT JOIN DLN1 T21 ON T1."BaseType"=T21."ObjType" AND T1."BaseEntry"=T21."DocEntry" AND T1."BaseLine"=T21."LineNum"
					LEFT JOIN ODLN T23 ON T21."DocEntry"=T23."DocEntry"
					LEFT JOIN (SELECT * FROM MTC_COST_0302_INVNTDETAIL1 WHERE "CostCode"='20') T22 ON T21."ObjType"=T22."ObjType" AND T21."DocEntry"=T22."DocEntry" AND T21."LineNum"=T22."LineNum"
					--关联取消的发票对应的交货单价
					LEFT JOIN INV1 T30 ON T1."BaseType"=T30."ObjType" AND T1."BaseEntry"=T30."DocEntry" AND T1."BaseLine"=T30."LineNum"
					LEFT JOIN DLN1 T31 ON T30."BaseType"=T31."ObjType" AND T30."BaseEntry"=T31."DocEntry" AND T30."BaseLine"=T31."LineNum"
					LEFT JOIN ODLN T33 ON T31."DocEntry"=T33."DocEntry"
					LEFT JOIN (SELECT * FROM MTC_COST_0302_INVNTDETAIL1 WHERE "CostCode"='20') T32 ON T31."ObjType"=T32."ObjType" AND T31."DocEntry"=T32."DocEntry" AND T31."LineNum"=T32."LineNum"

					JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE"
							) T91 ON T0."U_SalOrdType"=T91."Name"
					WHERE IFNULL(T91."U_BusiType",'')<>'样品销售'
					AND LEFT(T0."DocDate",7)=:FcCode
					--AND T0."CANCELED"='N'
					UNION ALL
					SELECT T91."U_CustType",T0."ObjType",T1."DocEntry",T1."LineNum",T1."BaseType",T1."BaseEntry",T1."BaseLine"
					,CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END*T1."Quantity" AS "InvQty"
					,CASE WHEN T23."DocDate"<='2024-12-31' THEN T21."U_InitPrice" ELSE COALESCE(T22."Price",T32."Price") END
						*-1*CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END*T1."Quantity" AS "CostAmt"
					FROM ORIN T0 JOIN RIN1 T1 ON T0."DocEntry"=T1."DocEntry"
					--关联退货单的单价
					LEFT JOIN RDN1 T21 ON T1."BaseType"=T21."ObjType" AND T1."BaseEntry"=T21."DocEntry" AND T1."BaseLine"=T21."LineNum"
					LEFT JOIN ORDN T23 ON T21."DocEntry"=T23."DocEntry"
					LEFT JOIN (SELECT * FROM MTC_COST_0302_INVNTDETAIL1 WHERE "CostCode"='20') T22 ON T21."ObjType"=T22."ObjType" AND T21."DocEntry"=T22."DocEntry" AND T21."LineNum"=T22."LineNum"
					--关联取消的贷项发票对应的退货单价
					LEFT JOIN RIN1 T30 ON T1."BaseType"=T30."ObjType" AND T1."BaseEntry"=T30."DocEntry" AND T1."BaseLine"=T30."LineNum"
					LEFT JOIN RDN1 T31 ON T30."BaseType"=T31."ObjType" AND T30."BaseEntry"=T31."DocEntry" AND T30."BaseLine"=T31."LineNum"
					LEFT JOIN ORDN T33 ON T31."DocEntry"=T33."DocEntry"
					LEFT JOIN (SELECT * FROM MTC_COST_0302_INVNTDETAIL1 WHERE "CostCode"='20') T32 ON T31."ObjType"=T32."ObjType" AND T31."DocEntry"=T32."DocEntry" AND T31."LineNum"=T32."LineNum"
					
					JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE"
							) T91 ON T0."U_SalOrdType"=T91."Name"
					WHERE IFNULL(T91."U_BusiType",'')<>'样品销售'
					AND LEFT(T0."DocDate",7)=:FcCode
					AND T0."CANCELED"='N'
				) T2
			LEFT JOIN OACT T9 ON CASE WHEN T2."U_CustType"='国内客户' THEN '640101' WHEN  T2."U_CustType"='国外客户' THEN '640103' END=T9."AcctCode"
			WHERE 1=1
			GROUP BY T9."AcctCode",T9."AcctName"
			
			UNION ALL
			
			SELECT 0,:FcCode,'DN03','主营业务成本结转',:edate,'主营业务成本结转',0
			,T9."AcctCode",T9."AcctName"
			,0.00
			--,ROUND(SUM(ROUND(T2."InvQty"*CASE WHEN T1."DocDate"<='2024-12-31' THEN T1."U_InitPrice" ELSE T."Price" END,2)),2)
			,ROUND(SUM(ROUND(T2."CostAmt",2)),2)
			,NULL,NULL
			,'主营业务成本结转'
			,CURRENT_TIMESTAMP
			,:UserCode
			FROM (
					SELECT T91."U_CustType",T0."ObjType",T1."DocEntry",T1."LineNum",T1."BaseType",T1."BaseEntry",T1."BaseLine"
					,CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END*T1."Quantity" AS "InvQty"
					,CASE WHEN T23."DocDate"<='2024-12-31' THEN T21."U_InitPrice" ELSE COALESCE(T22."Price",T32."Price") END
						*CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END *T1."Quantity" AS "CostAmt"
					FROM OINV T0 JOIN INV1 T1 ON T0."DocEntry"=T1."DocEntry"
					
					--关联交货单的单价
					LEFT JOIN DLN1 T21 ON T1."BaseType"=T21."ObjType" AND T1."BaseEntry"=T21."DocEntry" AND T1."BaseLine"=T21."LineNum"
					LEFT JOIN ODLN T23 ON T21."DocEntry"=T23."DocEntry"
					LEFT JOIN (SELECT * FROM MTC_COST_0302_INVNTDETAIL1 WHERE "CostCode"='20') T22 ON T21."ObjType"=T22."ObjType" AND T21."DocEntry"=T22."DocEntry" AND T21."LineNum"=T22."LineNum"
					--关联取消的发票对应的交货单价
					LEFT JOIN INV1 T30 ON T1."BaseType"=T30."ObjType" AND T1."BaseEntry"=T30."DocEntry" AND T1."BaseLine"=T30."LineNum"
					LEFT JOIN DLN1 T31 ON T30."BaseType"=T31."ObjType" AND T30."BaseEntry"=T31."DocEntry" AND T30."BaseLine"=T31."LineNum"
					LEFT JOIN ODLN T33 ON T31."DocEntry"=T33."DocEntry"
					LEFT JOIN (SELECT * FROM MTC_COST_0302_INVNTDETAIL1 WHERE "CostCode"='20') T32 ON T31."ObjType"=T32."ObjType" AND T31."DocEntry"=T32."DocEntry" AND T31."LineNum"=T32."LineNum"

					JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE"
							) T91 ON T0."U_SalOrdType"=T91."Name"
					WHERE IFNULL(T91."U_BusiType",'')<>'样品销售'
					AND LEFT(T0."DocDate",7)=:FcCode
					--AND T0."CANCELED"='N'
					UNION ALL
					SELECT T91."U_CustType",T0."ObjType",T1."DocEntry",T1."LineNum",T1."BaseType",T1."BaseEntry",T1."BaseLine"
					,CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END*T1."Quantity" AS "InvQty"
					,CASE WHEN T23."DocDate"<='2024-12-31' THEN T21."U_InitPrice" ELSE T22."Price" END
						*-1*CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END*T1."Quantity" AS "CostAmt"
					FROM ORIN T0 JOIN RIN1 T1 ON T0."DocEntry"=T1."DocEntry"
					
					LEFT JOIN RDN1 T21 ON T1."BaseType"=T21."ObjType" AND T1."BaseEntry"=T21."DocEntry" AND T1."BaseLine"=T21."LineNum"
					LEFT JOIN ORDN T23 ON T21."DocEntry"=T23."DocEntry"
					LEFT JOIN (SELECT * FROM MTC_COST_0302_INVNTDETAIL1 WHERE "CostCode"='20') T22 ON T21."ObjType"=T22."ObjType" AND T21."DocEntry"=T22."DocEntry" AND T21."LineNum"=T22."LineNum"
					
					JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE"
							) T91 ON T0."U_SalOrdType"=T91."Name"
					WHERE IFNULL(T91."U_BusiType",'')<>'样品销售'
					AND LEFT(T0."DocDate",7)=:FcCode
					AND T0."CANCELED"='N'
				) T2
			LEFT JOIN OACT T9 ON T9."AcctCode"='140601'
			WHERE 1=1
			GROUP BY T9."AcctCode",T9."AcctName",T2."U_CustType"
			;
			
			
			INSERT INTO "MTC_COST_0802_OJDTBASEDETAIL"
			("FcCode","TransCode","TransName","U_Type",
				"U_ObjType","U_DocEntry","U_DocNum","U_LineNum","DocDate",
				"U_BaseType","U_BaseEntry","U_BaseRef","U_BaseLine",
				"U_ItemCode","U_ItemName","U_CardCode","U_CardName",
				"U_Quantity","U_Price","U_LineTotal",
				"U_PriceAfVAT","U_GTotal","U_GTotalFc","U_LineMemo",
				"U_AcctCode","U_AcctName","StockAcctCode","StockAcctName","U_Debit","U_Credit",
				"CostPrice","CostAmt","VatSum",
				"U_Currency","U_Point","U_FCDebit","U_FCCredit",
				"U_Project","U_OcrCode1","U_OcrCode2","U_OcrCode3","U_OcrCode4","U_OcrCode5",
				"WhsCode"
			)
			SELECT T2."FcCode",T90."TrnsCode",T90."TrnsCodDsc",T90."TrnsCodDsc" AS "U_Type",
			T2."ObjType",T2."DocEntry",T2."DocNum",T2."LineNum",T2."DocDate",
			T2."BaseType",T2."BaseEntry",T2."BaseRef" AS "BaseNum",T2."BaseLine",
			T2."ItemCode",NULL,NULL,NULL,
			T2."InvQty",T2."CostPrice" AS "Price",
			ROUND((ROUND(T2."CostAmt",2)),2) AS "Amount",
			T2."CostPrice" AS "Price",
			ROUND((ROUND(T2."CostAmt",2)),2) AS "Amount",0 AS "U_GTotalFc",T90."TrnsCodDsc" AS "U_LineMemo",
			T9."AcctCode",T9."AcctName",T10."AcctCode" AS "U_StockCode",T10."AcctName" AS "U_StockName",
			0.00 AS "U_Debit",0.00 AS "U_Credit",
			0,0,0 AS "VatSum",NULL,NULL,NULL,NULL,
			NULL "Project",NULL "OcrCode1",NULL,NULL,NULL,NULL,
			T2."WhsCode"
			FROM (
					SELECT T91."U_CustType",T0."ObjType",T1."DocEntry",T0."DocNum",T1."LineNum",T1."BaseType",T1."BaseEntry",T1."BaseRef",T1."BaseLine"
					,CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END*T1."Quantity" AS "InvQty"
					,CASE WHEN T23."DocDate"<='2024-12-31' THEN T21."U_InitPrice" ELSE COALESCE(T22."Price",T32."Price") END AS "CostPrice"
					,CASE WHEN T23."DocDate"<='2024-12-31' THEN T21."U_InitPrice" ELSE COALESCE(T22."Price",T32."Price") END
						*CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END *T1."Quantity" AS "CostAmt"
					,LEFT(T0."DocDate",7) AS "FcCode",T0."DocDate"
					,T1."ItemCode",T1."WhsCode"
					FROM OINV T0 JOIN INV1 T1 ON T0."DocEntry"=T1."DocEntry"
					
					--关联交货单的单价
					LEFT JOIN DLN1 T21 ON T1."BaseType"=T21."ObjType" AND T1."BaseEntry"=T21."DocEntry" AND T1."BaseLine"=T21."LineNum"
					LEFT JOIN ODLN T23 ON T21."DocEntry"=T23."DocEntry"
					LEFT JOIN (SELECT * FROM MTC_COST_0302_INVNTDETAIL1 WHERE "CostCode"='20') T22 ON T21."ObjType"=T22."ObjType" AND T21."DocEntry"=T22."DocEntry" AND T21."LineNum"=T22."LineNum"
					--关联取消的发票对应的交货单价
					LEFT JOIN INV1 T30 ON T1."BaseType"=T30."ObjType" AND T1."BaseEntry"=T30."DocEntry" AND T1."BaseLine"=T30."LineNum"
					LEFT JOIN DLN1 T31 ON T30."BaseType"=T31."ObjType" AND T30."BaseEntry"=T31."DocEntry" AND T30."BaseLine"=T31."LineNum"
					LEFT JOIN ODLN T33 ON T31."DocEntry"=T33."DocEntry"
					LEFT JOIN (SELECT * FROM MTC_COST_0302_INVNTDETAIL1 WHERE "CostCode"='20') T32 ON T31."ObjType"=T32."ObjType" AND T31."DocEntry"=T32."DocEntry" AND T31."LineNum"=T32."LineNum"

					JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE"
							) T91 ON T0."U_SalOrdType"=T91."Name"
					WHERE IFNULL(T91."U_BusiType",'')<>'样品销售'
					AND LEFT(T0."DocDate",7)=:FcCode
					--AND T0."CANCELED"='N'

					UNION ALL
					SELECT T91."U_CustType",T0."ObjType",T1."DocEntry",T0."DocNum",T1."LineNum",T1."BaseType",T1."BaseEntry",T1."BaseRef",T1."BaseLine"
					,CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END*T1."Quantity" AS "InvQty"					
					,CASE WHEN T23."DocDate"<='2024-12-31' THEN T21."U_InitPrice" ELSE T22."Price" END AS "CostPrice"
					,CASE WHEN T23."DocDate"<='2024-12-31' THEN T21."U_InitPrice" ELSE T22."Price" END
						*-1*CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END*T1."Quantity" AS "CostAmt"
					,LEFT(T0."DocDate",7) AS "FcCode",T0."DocDate"
					,T1."ItemCode",T1."WhsCode"
					FROM ORIN T0 JOIN RIN1 T1 ON T0."DocEntry"=T1."DocEntry"
					
					LEFT JOIN RDN1 T21 ON T1."BaseType"=T21."ObjType" AND T1."BaseEntry"=T21."DocEntry" AND T1."BaseLine"=T21."LineNum"
					LEFT JOIN ORDN T23 ON T21."DocEntry"=T23."DocEntry"
					LEFT JOIN (SELECT * FROM MTC_COST_0302_INVNTDETAIL1 WHERE "CostCode"='20') T22 ON T21."ObjType"=T22."ObjType" AND T21."DocEntry"=T22."DocEntry" AND T21."LineNum"=T22."LineNum"
					
					JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE"
							) T91 ON T0."U_SalOrdType"=T91."Name"
					WHERE IFNULL(T91."U_BusiType",'')<>'样品销售'
					AND LEFT(T0."DocDate",7)=:FcCode
					AND T0."CANCELED"='N'
				) T2
			LEFT JOIN OACT T9 ON CASE WHEN T2."U_CustType"='国内客户' THEN '640101' WHEN  T2."U_CustType"='国外客户' THEN '640103' END=T9."AcctCode"
			LEFT JOIN OACT T10 ON T10."AcctCode"='140601'
			JOIN OTRC T90 ON T90."TrnsCode"='DN03'	--主营业务成本结转（内贸）
			WHERE 1=1
			
			;
			
			
			-----------------------暂估销售成本结转（扣除样品）-------------------
			INSERT INTO MTC_COST_0801_TOOJDT(
			"BPLId",
			"FcCode",
			"TransCode",
			"TransName",
			"RefDate",
			"Memo",
			"Line_ID",
			"AcctCode",
			"AcctName",
			"Debit",
			"Credit",
			"ProfitCode",
			"OcrName1",
			"LineMemo",
			"CreateDate",
			"Creator"
			)
			SELECT 0,:FcCode,'AR03','主营业务成本暂估计提-国内',:edate,'主营业务成本暂估计提-国内',0
			,T9."AcctCode",T9."AcctName",ROUND(SUM(ROUND(T1."Quantity"*CASE WHEN T1."DocDate"<='2024-12-31' THEN T1."U_InitPrice" ELSE T."Price" END,2)),2),0.00,NULL,NULL
			,'主营业务成本暂估计提-国内'
			,CURRENT_TIMESTAMP
			,:UserCode
			FROM (SELECT T91."U_CustType",T0."ObjType",T0."DocEntry",T1."LineNum",T1."U_InitPrice",T0."DocDate"
						,T1."OpenQty" AS "Quantity"
						FROM ODLN T0
						JOIN DLN1 T1 ON T0."DocEntry"=T1."DocEntry"
						JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE"
								) T91 ON T0."U_SalOrdType"=T91."Name"
						WHERE IFNULL(T91."U_BusiType",'')<>'样品销售'
						AND T0."DocDate"<=:edate
						AND T0."CANCELED"='N'
						AND T1."LineStatus"='O'
					   UNION ALL
					   SELECT T91."U_CustType",T0."ObjType",T0."DocEntry",T1."LineNum",T1."U_InitPrice",T0."DocDate"
					   ,-1*T1."OpenQty" AS "Quantity"
					   FROM ORDN T0
						JOIN RDN1 T1 ON T0."DocEntry"=T1."DocEntry"
						JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE"
								) T91 ON T0."U_SalOrdType"=T91."Name"
						WHERE IFNULL(T91."U_BusiType",'')<>'样品销售'
						AND T0."DocDate"<=:edate
						AND T0."CANCELED"='N'
						AND T1."LineStatus"='O'
					) T1
			LEFT JOIN (SELECT * FROM MTC_COST_0302_INVNTDETAIL1 WHERE "CostCode"='20') T ON T1."ObjType"=T."ObjType" AND T1."DocEntry"=T."DocEntry" AND T1."LineNum"=T."LineNum"
			LEFT JOIN OACT T9 ON CASE WHEN T1."U_CustType"='国内客户' THEN '640101' WHEN  T1."U_CustType"='国外客户' THEN '640103' END=T9."AcctCode"
			WHERE 1=1
			AND T1."U_CustType"='国内客户'
			GROUP BY T9."AcctCode",T9."AcctName"
			
			UNION ALL
			
			SELECT 0,:FcCode,'AR03','主营业务成本暂估计提-国内',:edate,'主营业务成本暂估计提-国内',0
			,T9."AcctCode",T9."AcctName"
			,0.00,ROUND(SUM(ROUND(T1."Quantity"*CASE WHEN T1."DocDate"<='2024-12-31' THEN T1."U_InitPrice" ELSE T."Price" END,2)),2),NULL,NULL
			,'主营业务成本暂估计提-国内'
			,CURRENT_TIMESTAMP
			,:UserCode
			FROM (SELECT T91."U_CustType",T0."ObjType",T0."DocEntry",T1."LineNum",T1."U_InitPrice",T0."DocDate"
						,T1."OpenQty" AS "Quantity"
						FROM ODLN T0
						JOIN DLN1 T1 ON T0."DocEntry"=T1."DocEntry"
						JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE"
								) T91 ON T0."U_SalOrdType"=T91."Name"
						WHERE IFNULL(T91."U_BusiType",'')<>'样品销售'
						AND T0."DocDate"<=:edate
						AND T0."CANCELED"='N'
						AND T1."LineStatus"='O'
					   UNION ALL
					   SELECT T91."U_CustType",T0."ObjType",T0."DocEntry",T1."LineNum",T1."U_InitPrice",T0."DocDate"
					   ,-1*T1."OpenQty" AS "Quantity"
					   FROM ORDN T0
						JOIN RDN1 T1 ON T0."DocEntry"=T1."DocEntry"
						JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE"
								) T91 ON T0."U_SalOrdType"=T91."Name"
						WHERE IFNULL(T91."U_BusiType",'')<>'样品销售'
						AND T0."DocDate"<=:edate
						AND T0."CANCELED"='N'
						AND T1."LineStatus"='O'
					) T1
			LEFT JOIN (SELECT * FROM MTC_COST_0302_INVNTDETAIL1 WHERE "CostCode"='20') T ON T1."ObjType"=T."ObjType" AND T1."DocEntry"=T."DocEntry" AND T1."LineNum"=T."LineNum"
			LEFT JOIN OACT T9 ON T9."AcctCode"='140601'
			WHERE 1=1
			AND T1."U_CustType"='国内客户'
			GROUP BY T9."AcctCode",T9."AcctName"
			;
			
			INSERT INTO "MTC_COST_0802_OJDTBASEDETAIL"
			("FcCode","TransCode","TransName","U_Type",
				"U_ObjType","U_DocEntry","U_DocNum","U_LineNum","DocDate",
				"U_BaseType","U_BaseEntry","U_BaseRef","U_BaseLine",
				"U_ItemCode","U_ItemName","U_CardCode","U_CardName",
				"U_Quantity","U_Price","U_LineTotal",
				"U_PriceAfVAT","U_GTotal","U_GTotalFc","U_LineMemo",
				"U_AcctCode","U_AcctName","StockAcctCode","StockAcctName","U_Debit","U_Credit",
				"CostPrice","CostAmt","VatSum",
				"U_Currency","U_Point","U_FCDebit","U_FCCredit",
				"U_Project","U_OcrCode1","U_OcrCode2","U_OcrCode3","U_OcrCode4","U_OcrCode5",
				"WhsCode"
			)
			SELECT :FcCode,T90."TrnsCode",T90."TrnsCodDsc",T90."TrnsCodDsc" AS "U_Type",
			T1."ObjType",T1."DocEntry",T1."DocNum",T1."LineNum",T1."DocDate",
			T1."ObjType" AS "BaseType",T1."DocEntry" AS "BaseEntry",T1."DocNum" AS "BaseNum",T1."LineNum" AS "BaseLine",
			T1."ItemCode",NULL,NULL,NULL,
			T1."Quantity",CASE WHEN T1."DocDate"<='2024-12-31' THEN T1."U_InitPrice" ELSE T."Price" END AS "Price",
			ROUND((ROUND(T1."Quantity"*CASE WHEN T1."DocDate"<='2024-12-31' THEN T1."U_InitPrice" ELSE T."Price" END,2)),2) AS "Amount",CASE WHEN T1."DocDate"<='2024-12-31' THEN T1."U_InitPrice" ELSE T."Price" END AS "Price",
			ROUND((ROUND(T1."Quantity"*CASE WHEN T1."DocDate"<='2024-12-31' THEN T1."U_InitPrice" ELSE T."Price" END,2)),2) AS "Amount",0 AS "U_GTotalFc",T90."TrnsCodDsc" AS "U_LineMemo",
			T9."AcctCode",T9."AcctName",T10."AcctCode" AS "U_StockCode",T10."AcctName" AS "U_StockName",
			0.00 AS "U_Debit",0.00 AS "U_Credit",
			0,0,0 AS "VatSum",NULL,NULL,NULL,NULL,
			NULL "Project",NULL "OcrCode1",NULL,NULL,NULL,NULL,
			T."WhsCode"			
			FROM (SELECT T91."U_CustType",T0."ObjType",T0."DocEntry",T0."DocNum",T1."LineNum",T1."U_InitPrice",T0."DocDate"
						,T1."OpenQty" AS "Quantity",T1."ItemCode"
						FROM ODLN T0
						JOIN DLN1 T1 ON T0."DocEntry"=T1."DocEntry"
						JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE"
								) T91 ON T0."U_SalOrdType"=T91."Name"
						WHERE IFNULL(T91."U_BusiType",'')<>'样品销售'
						AND T0."DocDate"<=:edate
						AND T0."CANCELED"='N'
						AND T1."LineStatus"='O'
					   UNION ALL
					   SELECT T91."U_CustType",T0."ObjType",T0."DocEntry",T0."DocNum",T1."LineNum",T1."U_InitPrice",T0."DocDate"
					   ,-1*T1."OpenQty" AS "Quantity",T1."ItemCode"
					   FROM ORDN T0
						JOIN RDN1 T1 ON T0."DocEntry"=T1."DocEntry"
						JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE"
								) T91 ON T0."U_SalOrdType"=T91."Name"
						WHERE IFNULL(T91."U_BusiType",'')<>'样品销售'
						AND T0."DocDate"<=:edate
						AND T0."CANCELED"='N'
						AND T1."LineStatus"='O'
					) T1
			LEFT JOIN (SELECT * FROM MTC_COST_0302_INVNTDETAIL1 WHERE "CostCode"='20') T ON T1."ObjType"=T."ObjType" AND T1."DocEntry"=T."DocEntry" AND T1."LineNum"=T."LineNum"
			LEFT JOIN OACT T9 ON CASE WHEN T1."U_CustType"='国内客户' THEN '640101' WHEN  T1."U_CustType"='国外客户' THEN '640103' END=T9."AcctCode"
			LEFT JOIN OACT T10 ON T10."AcctCode"='140601'
			JOIN OTRC T90 ON T90."TrnsCode"='AR03'	--主营业务成本结转（内贸）
			WHERE 1=1
			AND T1."U_CustType"='国内客户'
			
			;
			
			
			-----------------------暂估销售成本结转（扣除样品）-------------------
			INSERT INTO MTC_COST_0801_TOOJDT(
			"BPLId",
			"FcCode",
			"TransCode",
			"TransName",
			"RefDate",
			"Memo",
			"Line_ID",
			"AcctCode",
			"AcctName",
			"Debit",
			"Credit",
			"ProfitCode",
			"OcrName1",
			"LineMemo",
			"CreateDate",
			"Creator"
			)
			SELECT 0,:FcCode,'AR04','主营业务成本暂估计提-国际',:edate,'主营业务成本暂估计提-国际',0
			,T9."AcctCode",T9."AcctName",ROUND(SUM(ROUND(T1."Quantity"*CASE WHEN T1."DocDate"<='2024-12-31' THEN T1."U_InitPrice" ELSE T."Price" END,2)),2),0.00,NULL,NULL
			,'主营业务成本暂估计提-国际'
			,CURRENT_TIMESTAMP
			,:UserCode
			FROM (SELECT T91."U_CustType",T0."ObjType",T0."DocEntry",T1."LineNum",T1."U_InitPrice",T0."DocDate"
						,T1."OpenQty" AS "Quantity"
						FROM ODLN T0
						JOIN DLN1 T1 ON T0."DocEntry"=T1."DocEntry"
						JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE"
								) T91 ON T0."U_SalOrdType"=T91."Name"
						WHERE IFNULL(T91."U_BusiType",'')<>'样品销售'
						AND T0."DocDate"<=:edate
						AND T0."CANCELED"='N'
						AND T1."LineStatus"='O'
					   UNION ALL
					   SELECT T91."U_CustType",T0."ObjType",T0."DocEntry",T1."LineNum",T1."U_InitPrice",T0."DocDate"
					   ,-1*T1."OpenQty" AS "Quantity"
					   FROM ORDN T0
						JOIN RDN1 T1 ON T0."DocEntry"=T1."DocEntry"
						JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE"
								) T91 ON T0."U_SalOrdType"=T91."Name"
						WHERE IFNULL(T91."U_BusiType",'')<>'样品销售'
						AND T0."DocDate"<=:edate
						AND T0."CANCELED"='N'
						AND T1."LineStatus"='O'
					) T1
			LEFT JOIN (SELECT * FROM MTC_COST_0302_INVNTDETAIL1 WHERE "CostCode"='20') T ON T1."ObjType"=T."ObjType" AND T1."DocEntry"=T."DocEntry" AND T1."LineNum"=T."LineNum"
			LEFT JOIN OACT T9 ON CASE WHEN T1."U_CustType"='国内客户' THEN '640101' WHEN  T1."U_CustType"='国外客户' THEN '640103' END=T9."AcctCode"
			WHERE 1=1
			AND T1."U_CustType"='国外客户'
			GROUP BY T9."AcctCode",T9."AcctName"
			
			UNION ALL
			
			SELECT 0,:FcCode,'AR04','主营业务成本暂估计提-国际',:edate,'主营业务成本暂估计提-国际',0
			,T9."AcctCode",T9."AcctName"
			,0.00,ROUND(SUM(ROUND(T1."Quantity"*CASE WHEN T1."DocDate"<='2024-12-31' THEN T1."U_InitPrice" ELSE T."Price" END,2)),2),NULL,NULL
			,'主营业务成本暂估计提-国际'
			,CURRENT_TIMESTAMP
			,:UserCode
			FROM (SELECT T91."U_CustType",T0."ObjType",T0."DocEntry",T1."LineNum",T1."U_InitPrice",T0."DocDate"
						,T1."OpenQty" AS "Quantity"
						FROM ODLN T0
						JOIN DLN1 T1 ON T0."DocEntry"=T1."DocEntry"
						JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE"
								) T91 ON T0."U_SalOrdType"=T91."Name"
						WHERE IFNULL(T91."U_BusiType",'')<>'样品销售'
						AND T0."DocDate"<=:edate
						AND T0."CANCELED"='N'
						AND T1."LineStatus"='O'
					   UNION ALL
					   SELECT T91."U_CustType",T0."ObjType",T0."DocEntry",T1."LineNum",T1."U_InitPrice",T0."DocDate"
					   ,-1*T1."OpenQty" AS "Quantity"
					   FROM ORDN T0
						JOIN RDN1 T1 ON T0."DocEntry"=T1."DocEntry"
						JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE"
								) T91 ON T0."U_SalOrdType"=T91."Name"
						WHERE IFNULL(T91."U_BusiType",'')<>'样品销售'
						AND T0."DocDate"<=:edate
						AND T0."CANCELED"='N'
						AND T1."LineStatus"='O'
					) T1
			LEFT JOIN (SELECT * FROM MTC_COST_0302_INVNTDETAIL1 WHERE "CostCode"='20') T ON T1."ObjType"=T."ObjType" AND T1."DocEntry"=T."DocEntry" AND T1."LineNum"=T."LineNum"
			LEFT JOIN OACT T9 ON T9."AcctCode"='140601'
			WHERE 1=1
			AND T1."U_CustType"='国外客户'
			GROUP BY T9."AcctCode",T9."AcctName"
			;
			
			INSERT INTO "MTC_COST_0802_OJDTBASEDETAIL"
			("FcCode","TransCode","TransName","U_Type",
				"U_ObjType","U_DocEntry","U_DocNum","U_LineNum","DocDate",
				"U_BaseType","U_BaseEntry","U_BaseRef","U_BaseLine",
				"U_ItemCode","U_ItemName","U_CardCode","U_CardName",
				"U_Quantity","U_Price","U_LineTotal",
				"U_PriceAfVAT","U_GTotal","U_GTotalFc","U_LineMemo",
				"U_AcctCode","U_AcctName","StockAcctCode","StockAcctName","U_Debit","U_Credit",
				"CostPrice","CostAmt","VatSum",
				"U_Currency","U_Point","U_FCDebit","U_FCCredit",
				"U_Project","U_OcrCode1","U_OcrCode2","U_OcrCode3","U_OcrCode4","U_OcrCode5",
				"WhsCode"
			)
			SELECT :FcCode,T90."TrnsCode",T90."TrnsCodDsc",T90."TrnsCodDsc" AS "U_Type",
			T1."ObjType",T1."DocEntry",T1."DocNum",T1."LineNum",T1."DocDate",
			T1."ObjType" AS "BaseType",T1."DocEntry" AS "BaseEntry",T1."DocNum" AS "BaseNum",T1."LineNum" AS "BaseLine",
			T1."ItemCode",NULL,NULL,NULL,
			T1."Quantity",CASE WHEN T1."DocDate"<='2024-12-31' THEN T1."U_InitPrice" ELSE T."Price" END AS "Price",
			ROUND((ROUND(T1."Quantity"*CASE WHEN T1."DocDate"<='2024-12-31' THEN T1."U_InitPrice" ELSE T."Price" END,2)),2) AS "Amount",CASE WHEN T1."DocDate"<='2024-12-31' THEN T1."U_InitPrice" ELSE T."Price" END AS "Price",
			ROUND((ROUND(T1."Quantity"*CASE WHEN T1."DocDate"<='2024-12-31' THEN T1."U_InitPrice" ELSE T."Price" END,2)),2) AS "Amount",0 AS "U_GTotalFc",T90."TrnsCodDsc" AS "U_LineMemo",
			T9."AcctCode",T9."AcctName",T10."AcctCode" AS "U_StockCode",T10."AcctName" AS "U_StockName",
			0.00 AS "U_Debit",0.00 AS "U_Credit",
			0,0,0 AS "VatSum",NULL,NULL,NULL,NULL,
			NULL "Project",NULL "OcrCode1",NULL,NULL,NULL,NULL,
			T."WhsCode"			
			FROM (SELECT T91."U_CustType",T0."ObjType",T0."DocEntry",T0."DocNum",T1."LineNum",T1."U_InitPrice",T0."DocDate"
						,T1."OpenQty" AS "Quantity",T1."ItemCode"
						FROM ODLN T0
						JOIN DLN1 T1 ON T0."DocEntry"=T1."DocEntry"
						JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE"
								) T91 ON T0."U_SalOrdType"=T91."Name"
						WHERE IFNULL(T91."U_BusiType",'')<>'样品销售'
						AND T0."DocDate"<=:edate
						AND T0."CANCELED"='N'
						AND T1."LineStatus"='O'
					   UNION ALL
					   SELECT T91."U_CustType",T0."ObjType",T0."DocEntry",T0."DocNum",T1."LineNum",T1."U_InitPrice",T0."DocDate"
					   ,-1*T1."OpenQty" AS "Quantity",T1."ItemCode"
					   FROM ORDN T0
						JOIN RDN1 T1 ON T0."DocEntry"=T1."DocEntry"
						JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE"
								) T91 ON T0."U_SalOrdType"=T91."Name"
						WHERE IFNULL(T91."U_BusiType",'')<>'样品销售'
						AND T0."DocDate"<=:edate
						AND T0."CANCELED"='N'
						AND T1."LineStatus"='O'
					) T1
			LEFT JOIN (SELECT * FROM MTC_COST_0302_INVNTDETAIL1 WHERE "CostCode"='20') T ON T1."ObjType"=T."ObjType" AND T1."DocEntry"=T."DocEntry" AND T1."LineNum"=T."LineNum"
			LEFT JOIN OACT T9 ON CASE WHEN T1."U_CustType"='国内客户' THEN '640101' WHEN  T1."U_CustType"='国外客户' THEN '640103' END=T9."AcctCode"
			LEFT JOIN OACT T10 ON T10."AcctCode"='140601'
			JOIN OTRC T90 ON T90."TrnsCode"='AR04'	--主营业务成本结转（内贸）
			WHERE 1=1
			AND T1."U_CustType"='国外客户'
			
			;
			-----------------------PP04结转制造费用-------------------
			PP04=
			SELECT T0."AcctCode",SUM(T0."Debit"-T0."Credit") AS "Amount"
			FROM
			 (SELECT "AcctCode","Debit","Credit"
			  FROM MTC_COST_0801_TOOJDT WHERE "FcCode"=:FcCode AND "TransCode" IN ('YF01','IO01','MR02') AND "AcctCode" LIKE '5101%'
				UNION ALL
			  SELECT T1."Account",T1."Debit",T1."Credit" FROM "OJDT" T0
			  JOIN "JDT1" T1 ON T0."TransId"=T1."TransId"
			  WHERE 1=1
			  AND IFNULL(T0."TransCode",'')<>'PP04'
			  AND LEFT(T0."RefDate",7)=:FcCode AND T1."Account" LIKE '5101%'
			  ) T0
			 GROUP BY T0."AcctCode"
				;
			
	
			INSERT INTO MTC_COST_0801_TOOJDT(
			"BPLId",
			"FcCode",
			"TransCode",
			"TransName",
			"RefDate",
			"Memo",
			"Line_ID",
			"AcctCode",
			"AcctName",
			"Debit",
			"Credit",
			"ProfitCode",
			"OcrName1",
			"LineMemo",
			"CreateDate",
			"Creator"
			)
			
			SELECT 0,:FcCode,'PP04','制造费用结转',:edate,'制造费用结转',0
			,T1."AcctCode",T1."AcctName",SUM(ROUND(T0."Amount",2)) AS "Debit",0.00 AS "Credit",NULL,NULL
			,'制造费用结转'
			,CURRENT_TIMESTAMP
			,:UserCode
			FROM :PP04 T0
			LEFT JOIN OACT T1 ON T1."AcctCode"='500103'
			WHERE 1=1
			GROUP BY T1."AcctCode",T1."AcctName"
			UNION ALL
			SELECT 0,:FcCode,'PP04','制造费用结转',:edate,'制造费用结转',0
			,T1."AcctCode",T1."AcctName",0.00 AS "Debit",ROUND(T0."Amount",2) AS "Credit",NULL,NULL
			,'制造费用结转'
			,CURRENT_TIMESTAMP
			,:UserCode
			FROM :PP04 T0
			LEFT JOIN OACT T1 ON T0."AcctCode"=T1."AcctCode"
			WHERE 1=1;
			
	
		/*
			ZZF=
			SELECT T0."BPLId",
			T0."FcCode",
			T0."ObjType",
			T0."DocEntry",
			T0."DocNum",
			T0."LineNum",
			T0."DocDate",
			T0."CostCode",
			T0."TransCode",
			T0."BaseType",
			T0."BaseEntry",
			T0."BaseNum",
			T0."BaseLine",
			T0."ItemCode",
			T0."ItemName",
			T0."ItmsGrpCod",
			T0."Quantity",
			T1."Price",
			T0."Quantity"*T1."Price" AS "Amount",
			T0."CreateDate",
			T0."Creator",
			T0."WhsCode",
			T0."VarVal",
			T0."iLevel",
			T0."OcrCode1",
			T3."StockAct",
			T4."AcctCode",
			T6."U_TransType",		--B01工单产出类  B03工单投入类
			T6."Name" AS "TransName",
			T5."U_OrdType"
			FROM MTC_COST_0302_INVNTDETAIL1 T0
			LEFT JOIN (SELECT * FROM MTC_COST_0301_INVNT WHERE "FcCode"=:FcCode AND "CostCode"='20') T1 ON T0."ItemCode"=T1."ItemCode"
			LEFT JOIN OITM T2 ON T0."ItemCode"=T2."ItemCode"
			LEFT JOIN (SELECT "ItmsGrpCod",MAX("StockAct") AS "StockAct" FROm OGAR WHERE "PeriodCat"=LEFT(:FcCode,4) GROUP BY "ItmsGrpCod"
				) T3 ON T2."ItmsGrpCod"=T3."ItmsGrpCod"
			LEFT JOIN (
				SELECT "ObjType","DocEntry","LineNum","AcctCode" FROM IGN1
					UNION ALL
				SELECT "ObjType","DocEntry","LineNum","AcctCode" FROM IGE1
				) T4 ON T0."ObjType"=T4."ObjType" AND T0."DocEntry"=T4."DocEntry" AND T0."LineNum"=T4."LineNum"
			LEFT JOIN OWOR T5 ON T0."BaseEntry"=T5."DocEntry"
			LEFT JOIN "@U_CIOTRN" T6 ON REPLACE(REPLACE(T0."TransCode",'59-',''),'60-','')=T6."Code"
			WHERE T0."FcCode" = :FcCode
			AND T0."CostCode"='20'
			AND T0."BaseType"<>'202'
			AND T0."ObjType"  IN ('59','60')
			AND T0."TransCode" NOT IN ('59-203','60-203')
			;
			
			INSERT INTO MTC_COST_0801_TOOJDT(
			"BPLId",
			"FcCode",
			"TransCode",
			"TransName",
			"RefDate",
			"Memo",
			"Line_ID",
			"AcctCode",
			"AcctName",
			"Debit",
			"Credit",
			"ProfitCode",
			"OcrName1",
			"LineMemo",
			"CreateDate",
			"Creator"
			)
			SELECT 0,:FcCode,'PP03','其他领用费用结转',:edate,'其他领用费用结转',0
			,T2."AcctCode",T2."AcctName",-1*ROUND(SUM(T1."Amount"),2),0.00,T1."OcrCode1",T3."PrcName"
			,'其他领用费用结转'
			,CURRENT_TIMESTAMP
			,:UserCode
			FROM :ZZF T1
			LEFT JOIN "OACT" T2 ON T1."AcctCode"=T2."AcctCode"
			LEFT JOIN "OPRC" T3 ON T1."OcrCode1"=T3."PrcCode"
			GROUP BY T2."AcctCode",T2."AcctName",T1."OcrCode1",T3."PrcName"
			
			UNION ALL
			SELECT 0,:FcCode,'PP03','其他领用费用结转',:edate,'其他领用费用结转',0
			,T2."AcctCode",T2."AcctName",0.00,-1*ROUND(SUM(T1."Amount"),2),NULL,NULL
			,'其他领用费用结转'
			,CURRENT_TIMESTAMP
			,:UserCode
			FROM :ZZF T1
			LEFT JOIN OACT T2 ON T1."StockAct"=T2."AcctCode"
			GROUP BY T2."AcctCode",T2."AcctName";
			*/
			
			
	
	
	SELECT * FROM MTC_COST_0801_TOOJDT WHERE "FcCode"=:FcCode;

END