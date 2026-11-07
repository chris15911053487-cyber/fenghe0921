CREATE PROCEDURE "MTC_RPT_COJZ_03"
(
  Type INT,  		--1 查看明细 0查看分录
  TransCode NVARCHAR(50),
  FcCode NVARCHAR(10),
  IsOJDT NVARCHAR(10) DEFAULT 'N'		--是否生成分录  Y生成分录  N不生成分录
 )
LANGUAGE SQLSCRIPT
AS
BEGIN 
	--JZ03结转委外关单差异
	
	DECLARE MAXEntry INT;
	DECLARE RevDate DATE;   --下个月初的冲销日期	
	DECLARE EndDate	DATE;	--当月结束日期
	DECLARE LastFcCode NVARCHAR(30); --上一期间
	
	SELECT "T_RefDate" INTO EndDate FROM OFPR WHERE "Code"=:FcCode;
	SELECT MIN("F_RefDate") INTO RevDate FROM OFPR WHERE "Code">:FcCode; 
	SELECT MAX("Code") INTO LastFcCode FROM OFPR WHERE "Code"<:FcCode;
	
	IF :IsOJDT = 'Y' THEN
	  	IF EXISTS(SELECT 1 FROM "OFPR" WHERE "PeriodStat"='Y' AND "Code"=:FcCode) THEN
	  		SELECT -1 AS "Code",'账期已锁定，无法计算成本' AS "Msg" FROM DUMMY;
	  		RETURN;
	  	END IF;
	END IF;
	
	DELETE FROM MTC_COST_0801_TOOJDT WHERE "FcCode"=:FcCode AND "TransCode"='JZ03';
	DELETE FROM MTC_COST_0802_OJDTBASEDETAIL WHERE "FcCode"=:FcCode AND "TransCode"='JZ03';
	
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
	SELECT 0,T0."期间",T1."TrnsCode",T1."TrnsCodDsc",:EndDate,T1."TrnsCodDsc",0
	,T2."AcctCode",T2."AcctName"
	,-1*ROUND(SUM(ROUND(T0."关单差异",2)),2) AS "Debit"
	,0.00 AS "Credit",NULL,NULL,NULL
	,T1."TrnsCodDsc"
	,CURRENT_TIMESTAMP
	,''
	FROM "MTC_COST_0322_OWOR_ZCP" T0
	JOIN OTRC T1 ON T1."TrnsCode"='JZ03'
	JOIN OACT T2 ON T2."AcctCode"='140801'
	WHERE T0."WorType" IN ('50') 
	AND T0."订单状态"='已结算' AND T0."期间"=:FcCode AND T0."关单结算期间"=:FcCode
	GROUP BY T0."期间",T1."TrnsCode",T1."TrnsCodDsc",T1."TrnsCodDsc",T2."AcctCode",T2."AcctName"
	HAVING ROUND(SUM(T0."关单差异"),2)<>0
	UNION ALL
	SELECT 0,T0."期间",T1."TrnsCode",T1."TrnsCodDsc",:EndDate,T1."TrnsCodDsc",0
	,T2."AcctCode",T2."AcctName"
	,ROUND(SUM(ROUND(T0."关单差异",2)),2) AS "Debit"
	,0.00 AS "Credit",NULL,NULL,NULL
	,T1."TrnsCodDsc"
	,CURRENT_TIMESTAMP
	,''
	FROM "MTC_COST_0322_OWOR_ZCP" T0
	JOIN OTRC T1 ON T1."TrnsCode"='JZ03'
	JOIN OACT T2 ON T2."AcctCode"='510198'
	WHERE T0."WorType" IN ('50') 
	AND T0."订单状态"='已结算' AND T0."期间"=:FcCode AND T0."关单结算期间"=:FcCode
	GROUP BY T0."期间",T1."TrnsCode",T1."TrnsCodDsc",T1."TrnsCodDsc",T2."AcctCode",T2."AcctName"
	HAVING ROUND(SUM(T0."关单差异"),2)<>0;
	
	
	INSERT INTO "MTC_COST_0802_OJDTBASEDETAIL"
	("FcCode","DocDate","TransCode","TransName","U_Type",
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
	SELECT T0."期间",T0."订单关单日期",T1."TrnsCode",T1."TrnsCodDsc",'结转关单差异JZ03' AS "U_Type",
	T0."DocType",T0."WorEntry",T0."WorNum",0 AS "LineId",
	NULL,NULL,NULL,NULL,
	T0."物料编码",T0."物料名称",NULL,NULL,
	0,0,T0."关单差异",0,T0."关单差异",0 AS "U_GTotalFc",'结转关单差异JZ03' AS "U_LineMemo",
	T3."AcctCode" AS "U_AcctCode",T3."AcctName" AS "U_AcctName",T2."AcctCode" AS "U_StockCode",T2."AcctName" AS "U_StockName",
	T0."关单差异",0.00 AS "U_Credit",
	0,0,0,NULL,NULL,NULL,NULL,
	NULL,NULL,NULL,NULL,NULL,NULL
	FROM "MTC_COST_0322_OWOR_ZCP" T0
	JOIN OTRC T1 ON T1."TrnsCode"='JZ03'
	LEFT JOIN OACT T2 ON T2."AcctCode"='140801'
	LEFT JOIN OACT T3 ON T3."AcctCode"='510198'
	WHERE T0."WorType" IN ('50') 
	AND T0."订单状态"='已结算' AND T0."期间"=:FcCode AND T0."关单结算期间"=:FcCode
	;

	TMP=
	SELECT "BPLId",
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
	"Project",
	"ProfitCode",
	"OcrName1",
	"OcrCode2",
	"OcrName2",
	"LineMemo",
	"CreateDate",
	"Creator",
	"DocEntry",
	"CardCode",
	"CardName",
	CASE WHEN IFNULL("FCCurrency",'')='' THEN 'RMB' ELSE "FCCurrency" END AS "FCCurrency",
	"FCDebit",
	"FCCredit",
	"DocDate"
	FROM MTC_COST_0801_TOOJDT WHERE "FcCode"=:FcCode AND "TransCode"=:TransCode;
	
	
	IF :Type = 1 THEN 
		
		SELECT * FROM :TMP;
		
	ELSEIF :Type=0 THEN
		TMP_OJDT=
		SELECT 'Y' AS "flag",NULL AS "TransId",T31."TrnsCode" AS "TransCode",T31."TrnsCodDsc",:EndDate AS "RefDate"
		,T31."TrnsCodDsc"||','||:FcCode||'月' AS "Memo"
		,NULL AS "AcctCode",NULL AS "AcctName"
		,NULL AS "CardCode",NULL AS "CardName",NULL AS "FCCurrency"
		,NULL AS "FCDebit",NULL AS "FCCredit",NULL AS "Debit",NULL AS "Credit",NULL AS "ProfitCode",NULL AS "Project"
		FROM DUMMY T1
		LEFT JOIN OTRC T31 ON T31."TrnsCode"=:TransCode
		WHERE 1=0
		
		UNION ALL
		SELECT 'N' AS "flag",NULL AS "TransId",T31."TrnsCode" AS "TransCode",T31."TrnsCodDsc",:EndDate AS "RefDate"
		,T31."TrnsCodDsc"||','||:FcCode||'月' AS "Memo",T2."AcctCode" AS "Account",T2."AcctName"
		,T1."CardCode" AS "ShortName",T1."CardName",T0."FCCurrency" AS "DocCur"
		,T0."FCDebit",T0."FCCredit",T0."Debit",T0."Credit",T0."ProfitCode",T0."Project"
		FROM :TMP T0
		LEFT JOIN OCRD T1 ON T0."CardCode"=T1."CardCode"
		LEFT JOIN OACT T2 ON T0."AcctCode"=T2."AcctCode"
		LEFT JOIN OTRC T31 ON T31."TrnsCode"=:TransCode
		WHERE 1=1;
		
		IF :IsOJDT = 'N' THEN
			SELECT * FROM :TMP_OJDT;
		ELSEIF :IsOJDT = 'Y' THEN
			SELECT IFNULL(MAX("DocEntry"),0) INTO MAXEntry FROM "@MTC_COST_OJDT";
			DELETE FROM "@MTC_COST_OJDT" WHERE "U_FcCode"=:FcCode AND "U_TransCode"=:TransCode;
			DELETE FROM "@MTC_COST_OJDT1" WHERE "DocEntry" NOT IN (SELECT "DocEntry" FROM "@MTC_COST_OJDT");
			DELETE FROM "@MTC_COST_OJDT2" WHERE "DocEntry" NOT IN (SELECT "DocEntry" FROM "@MTC_COST_OJDT");
			
			INSERT INTO "@MTC_COST_OJDT"("DocEntry","DocNum","Object","Canceled","U_RefDate","U_FcCode"
			,"U_TransCode","U_Memo","U_IsRev","U_RevDate")
			SELECT TOP 1 :MAXEntry+1 AS "DocEntry",:MAXEntry+1 AS "DocNum",'MTC_COST_OJDT','N',T0."RefDate",:FcCode
				,T0."TransCode",T0."Memo"
				,CASE WHEN T0."TransCode" IN ('AR03','AR04') THEN 'Y' ELSE 'N' END AS "U_IsRev"
				,CASE WHEN T0."TransCode" IN ('AR03','AR04') THEN :RevDate ELSE NULL END AS "U_RevDate"
				FROM :TMP_OJDT T0;
			
			INSERT INTO "@MTC_COST_OJDT1"(
				"DocEntry","LineId","U_LineMemo"
				,"U_AcctCode","U_AcctName","U_CardCode","U_CardName","U_FCCurrency"
				,"U_FCDebit","U_FCCredit","U_Debit","U_Credit","U_OcrCode1","U_OcrCode5" --"Project"
				)
			SELECT :MAXEntry+1 AS "DocEntry"
				,ROW_NUMBER() OVER (PARTITION BY "TransCode","RefDate" ORDER BY T0."AcctCode",T0."CardCode") AS "LineId","Memo"
				,T0."AcctCode",T0."AcctName",T0."CardCode",T0."CardName",T0."FCCurrency"
				,T0."FCDebit",T0."FCCredit",T0."Debit",T0."Credit",T0."ProfitCode",T0."Project"
				FROM :TMP_OJDT T0;
				
			INSERT INTO "@MTC_COST_OJDT2"(
					"DocEntry","LineId","VisOrder",
					"Object","LogInst","U_Type",
					"U_ObjType","U_DocEntry","U_DocNum","U_LineNum",
					"U_BaseType","U_BaseEntry","U_BaseRef","U_BaseLine",
					"U_ItemCode","U_ItemName","U_Quantity",
					"U_CardCode","U_CardName","U_AcctCode","U_AcctName",
					"U_Price","U_LineTotal","U_PriceAfVAT","U_GTotal",
					"U_Debit","U_Credit","U_Point",
					"U_Project","U_OcrCode1","U_OcrCode2","U_OcrCode3","U_OcrCode4","U_OcrCode5",
					"U_CostPrice","U_CostAmt","U_VatSum","U_StockAcctCode","U_StockAcctName","U_DocDate","U_WhsCode"			
					)
				SELECT :MAXEntry+1 AS "DocEntry"
				,ROW_NUMBER() OVER(ORDER BY P0."U_Type") AS "LineId"
				,ROW_NUMBER() OVER(ORDER BY P0."U_Type") AS "VisOrder"
				,'MTC_COST_OJDT' AS "Object",NULL AS "LogInst",P0."U_Type"
				,P0."U_ObjType",P0."U_DocEntry",P0."U_DocNum",P0."U_LineNum"
				,P0."U_BaseType",P0."U_BaseEntry",P0."U_BaseRef",P0."U_BaseLine"
				,P0."U_ItemCode",P1."ItemName",P0."U_Quantity"
				,P0."U_CardCode",P0."U_CardName",P0."U_AcctCode",P0."U_AcctName"
				,P0."U_Price",P0."U_LineTotal",P0."U_PriceAfVAT",P0."U_GTotal"
				,P0."U_Debit",P0."U_Credit",P0."U_Point"
				,P0."U_Project",P0."U_OcrCode1",P0."U_OcrCode2",P0."U_OcrCode3",P0."U_OcrCode4",P0."U_OcrCode5"			
				,P0."CostPrice",P0."CostAmt",P0."VatSum",P0."StockAcctCode",P0."StockAcctName",P0."DocDate",P0."WhsCode"	
				FROM "MTC_COST_0802_OJDTBASEDETAIL" P0 
				LEFT JOIN OITM P1 ON P0."U_ItemCode"=P1."ItemCode"
				WHERE P0."FcCode"=:FcCode AND P0."TransCode"=:TransCode;
				
			SELECT 'Y' AS "flag",T0."DocEntry",T1."LineId",TO_VARCHAR(T0."U_RefDate",'YYYYMMDD') AS "RefDate"
				,T0."U_TransCode" AS "TransCode",NULL AS "TransName",T0."U_Memo" AS "Memo"
				,T1."U_AcctCode" AS "AcctCode",T1."U_AcctName" AS "AcctName",T1."U_CardCode" AS "CardCode"
				,T1."U_CardName" AS "CardName",T1."U_FCCurrency" AS "FCCurrency"
				,T1."U_FCDebit" AS "FCDebit",T1."U_FCCredit" AS "FCCredit",T1."U_Debit" AS "Debit",T1."U_Credit" AS "Credit"
				,T1."U_OcrCode5" AS "Project"
				,T1."U_OcrCode1" AS "ProfitCode"
				,T0."U_IsRev" AS "IsRev",TO_VARCHAR(T0."U_RevDate",'YYYYMMDD') AS "RevDate"
			FROM "@MTC_COST_OJDT" T0
			JOIN "@MTC_COST_OJDT1" T1 ON T0."DocEntry"=T1."DocEntry"
			WHERE T0."U_FcCode"=:FcCode AND T0."U_TransCode"=:TransCode;
			
		END IF;
	END IF;
	
	
	
END