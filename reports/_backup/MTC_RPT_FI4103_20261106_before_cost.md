CREATE PROCEDURE "MTC_RPT_FI4103"
(
  Type INT,
  GroupCode NVARCHAR(50),
  EndDate DATE,
  CardCode NVARCHAR(50),
  IsOJDT NVARCHAR(10) DEFAULT 'N'
 )
LANGUAGE SQLSCRIPT
AS
BEGIN 
	
	DECLARE MAXEntry INT;
	DECLARE TransCode NVARCHAR(30); --交易代码
	DECLARE RevDate DATE;   --下个月初的冲销日期
	DECLARE FcCode NVARCHAR(30);
	DECLARE LastFcCode NVARCHAR(30); --上一期间

	IF :EndDate = '17530101' THEN
		SELECT CURRENT_DATE INTO EndDate FROM DUMMY;
	END IF;
	
	IF :IsOJDT = 'Y' THEN
	  	IF EXISTS(SELECT 1 FROM "OFPR" WHERE "PeriodStat"='Y' AND "Code"=:FcCode) THEN
	  		SELECT -1 AS "Code",'账期已锁定，无法计算成本' AS "Msg" FROM DUMMY;
	  		RETURN;
	  	END IF;
	END IF;
	
	SELECT CASE WHEN :GroupCode = '100' THEN 'AR01' WHEN :GroupCode='106' THEN 'AR02' END INTO TransCode FROM DUMMY;
	SELECT "Code" INTO FcCode FROM OFPR WHERE :EndDate BETWEEN "F_RefDate" AND "T_RefDate"; 
	SELECT MIN("F_RefDate") INTO RevDate FROM OFPR WHERE "Code">:FcCode; 
	SELECT MAX("Code") INTO LastFcCode FROM OFPR WHERE "Code"<:FcCode;

	TMP=
	SELECT T0."ObjType",'交货单' AS "单据类型",T1."BaseRef" as "订单号",T0."DocEntry",T0."DocNum" as "交货单号Num",T1."LineNum" AS "行号"
	,T0."CardCode" as "客户代码",T0."CardName" as "客户名称"
	,T0."DocCur" AS "单据货币",T0."DocRate" AS "单据汇率"
	,T0."DocDate" as "过账日期",T5."ItemCode" as "物料号",T5."ItemName" as "描述",T5."U_Specs" AS "规格",T1."U_BtchNum" AS "批次号"
	,T1."Quantity" AS "数量"
	,T1."Quantity"-ifnull(T3."FPQTY",0)-ifnull(t4."XSTHQTY",0)-ifnull(t6."XSTHQTY",0) AS "未清数量"
	,T1."Price" AS "未税单价(原币)"
	,ROUND((T1."Quantity"-ifnull(T3."FPQTY",0)-ifnull(t4."XSTHQTY",0)-ifnull(t6."XSTHQTY",0))*T1."Price",2) AS "未税金额(原币)"
	,ROUND((T1."Quantity"-ifnull(T3."FPQTY",0)-ifnull(t4."XSTHQTY",0)-ifnull(t6."XSTHQTY",0))*T1."Price",2)*T0."DocRate" AS "未税金额(本币)"
	,T1."OpenQty" AS "系统未清数量"
	,T1."PriceAfVAT" AS "含税单价(原币)"
	,T1."OpenQty"*T1."PriceAfVAT" AS "含税金额(原币)"
	,T1."OpenQty"*T1."PriceAfVAT"*T0."DocRate" AS "含税金额(本币)"
	,CASE WHEN T0."DocDate"<='2024-12-31' THEN IFNULL(T1."U_InitPrice",0) ELSE T9."Price" END AS "成本单价"
	,T1."OpenQty" * CASE WHEN T0."DocDate"<='2024-12-31' THEN IFNULL(T1."U_InitPrice",0) ELSE T9."Price" END AS "成本金额"
	,T32."GroupName" AS "客户类型",T0."U_OldSysNo" AS "老系统单号"
	,T0."U_SalOrdType" AS "销售类型"
	,T1."AcctCode",T1."CogsAcct"
	,T1."OpenCreQty" AS "未清数量(Cre)"
	,T1."WhsCode"
	FROM ODLN T0
	INNER JOIN DLN1 T1 ON T1."DocEntry"=T0."DocEntry"
	LEFT JOIN (
	           ------扣除应付发票数量----
	           SELECT T1."BaseEntry",T1."BaseType",T1."BaseLine",SUM(T1."Quantity") as "FPQTY"
	           FROM OINV T0
	           INNER JOIN INV1 T1 ON T1."DocEntry"=T0."DocEntry"
	           WHERE T0."isIns"='N' AND T0."CANCELED"='N'
	           GROUP BY T1."BaseEntry",T1."BaseType",T1."BaseLine" 
	           ) T3 ON T3."BaseEntry"=T1."DocEntry" AND T3."BaseType"=T0."ObjType" AND T3."BaseLine"=T1."LineNum"
	LEFT JOIN (
	           -----扣除基于退货请求的销售退货数量------
	           SELECT T1."BaseEntry",T1."BaseLine",T1."BaseType",SUM(T2."XSTHQTY") AS "XSTHQTY"
	           FROM ORRR T0
	           INNER JOIN RRR1 T1 ON T1."DocEntry"=T0."DocEntry"
	           left join (SELECT T1."BaseEntry",T1."BaseType",T1."BaseLine",sum(t1."Quantity") as "XSTHQTY"
	                      FROM ORDN T0
	                      INNER JOIN RDN1 T1 ON T1."DocEntry"=T0."DocEntry"
	                      where T0."CANCELED"='N'
	                      GROUP BY T1."BaseEntry",T1."BaseType",T1."BaseLine"
	                     ) T2 ON T2."BaseEntry"=T1."DocEntry" and T2."BaseType"=T0."ObjType" and T2."BaseLine"=T1."LineNum"
	           where T0."CANCELED"='N'
	           GROUP BY T1."BaseEntry",T1."BaseLine",T1."BaseType"
	           ) T4 ON T4."BaseEntry"=T1."DocEntry" and T4."BaseLine"=T1."LineNum" and T4."BaseType"=T1."ObjType"
	LEFT JOIN (
	           -----扣除基于销售交货的退货数量------
	           SELECT T1."BaseEntry",T1."BaseType",T1."BaseLine",sum(t1."Quantity") as "XSTHQTY"
	                      FROM ORDN T0
	                      INNER JOIN RDN1 T1 ON T1."DocEntry"=T0."DocEntry"
	                      where T0."CANCELED"='N'
	                      AND T1."BaseType"='15'
	                      GROUP BY T1."BaseEntry",T1."BaseType",T1."BaseLine"
	           ) T6 ON T6."BaseEntry"=T1."DocEntry" and T6."BaseLine"=T1."LineNum" and T6."BaseType"=T1."ObjType"
	left join OITM T5 ON T5."ItemCode"=T1."ItemCode"  
	LEFT JOIN (SELECT * FROM MTC_COST_0302_INVNTDETAIL1 WHERE "CostCode"='20') T9 ON T0."ObjType"=T9."ObjType" AND T1."DocEntry"=T9."DocEntry" AND T1."LineNum"=T9."LineNum"
	JOIN OCRD T31 ON T0."CardCode"=T31."CardCode"
	JOIN OCRG T32 ON T31."GroupCode"=T32."GroupCode"               
	WHERE T0."CANCELED"='N' 
	AND T1."LineStatus"='O'
	AND (T0."DocDate" <= :EndDate OR :EndDate='')
	AND (T31."GroupCode"=:GroupCode OR :GroupCode='')
	AND (T0."CardCode" LIKE '%'||:CardCode||'%' OR T0."CardName" LIKE '%'||:CardCode||'%' OR :CardCode='')
	
	UNION ALL
	SELECT T0."ObjType",'退货单' AS "单据类型",T1."BaseRef" as "销售订单号",T0."DocEntry",T0."DocNum" as "发货单号",T1."LineNum" AS "行号"
	,T0."CardCode" as "客户代码",T0."CardName" as "客户名称"
	,T0."DocCur" AS "单据货币",T0."DocRate" AS "单据汇率"
	,T0."DocDate" as "过账日期",T5."ItemCode" as "物料号",T5."ItemName" as "描述",T5."U_Specs" AS "规格",T1."U_BtchNum" AS "批次号"
	,-1*T1."Quantity" AS "数量"
	,-1*(T1."Quantity") AS "未清数量"
	,T1."Price" AS "未税单价(原币)"
	,ROUND(-1*T1."Quantity"*T1."Price",2) AS "未税金额(原币)"
	,ROUND(-1*T1."Quantity"*T1."Price",2)*T0."DocRate" AS "未税金额(本币)"
	,-1*T1."OpenQty" AS "系统未清数量"
	,T1."PriceAfVAT" AS "含税单价(原币)",-1*T1."OpenQty"*T1."PriceAfVAT" AS "含税金额(原币)"
	,-1*T1."OpenQty"*T1."PriceAfVAT"*T0."DocRate" AS "含税金额(本币)"
	,CASE WHEN T0."DocDate"<='2024-12-31' THEN IFNULL(T1."U_InitPrice",0) ELSE T6."Price" END AS "成本单价"
	,-1*T1."OpenQty" * CASE WHEN T0."DocDate"<='2024-12-31' THEN IFNULL(T1."U_InitPrice",0) ELSE T6."Price" END AS "成本金额",T32."GroupName" AS "客户类型",T0."U_OldSysNo" AS "老系统单号"
	,T0."U_SalOrdType" AS "销售类型"
	,T1."AcctCode",T1."CogsAcct"
	,-1*T1."OpenCreQty" AS "未清数量(Cre)"
	,T1."WhsCode"
	FROM ORDN T0
	INNER JOIN RDN1 T1 ON T1."DocEntry"=T0."DocEntry"
	left join OITM T5 ON T5."ItemCode"=T1."ItemCode"
	LEFT JOIN (SELECT * FROM MTC_COST_0302_INVNTDETAIL1 WHERE "CostCode"='20') T6 ON T0."ObjType"=T6."ObjType" AND T1."DocEntry"=T6."DocEntry" AND T1."LineNum"=T6."LineNum"
	JOIN OCRD T31 ON T0."CardCode"=T31."CardCode"
	JOIN OCRG T32 ON T31."GroupCode"=T32."GroupCode"                     
	WHERE T0."CANCELED"='N' 
	AND T1."LineStatus"='O'
	AND (T0."DocDate" <= :EndDate OR :EndDate='')
	AND (T31."GroupCode"=:GroupCode OR :GroupCode='')
	AND (T0."CardCode" LIKE '%'||:CardCode||'%' OR T0."CardName" LIKE '%'||:CardCode||'%' OR :CardCode='')
	ORDER BY "过账日期","交货单号Num";
	
	
	IF :Type = 1 THEN 
		
		SELECT * FROM :TMP ORDER BY "过账日期","交货单号Num";
		
	ELSEIF :Type=0 THEN
		TMP_OJDT=
		SELECT 'Y' AS "flag",NULL AS "TransId",T31."TrnsCode" AS "TransCode",T31."TrnsCodDsc",:EndDate AS "RefDate"
		,T31."TrnsCodDsc"||','||:FcCode||'月' AS "Memo"
		,NULL AS "AcctCode",NULL AS "AcctName"
		,NULL AS "CardCode",NULL AS "CardName",NULL AS "FCCurrency"
		,NULL AS "FCDebit",NULL AS "FCCredit",NULL AS "Debit",NULL AS "Credit"
		FROM DUMMY T1
		LEFT JOIN OTRC T31 ON T31."TrnsCode"=:TransCode
		WHERE 1=0
		
		UNION ALL
		SELECT 'N' AS "flag",NULL AS "TransId",T31."TrnsCode" AS "TransCode",T31."TrnsCodDsc",:EndDate AS "RefDate"
		,T31."TrnsCodDsc"||','||:FcCode||'月' AS "Memo",T2."AcctCode" AS "Account",T2."AcctName"
		,T1."CardCode" AS "ShortName",T1."CardName",T0."单据货币" AS "DocCur"
		,CASE WHEN T0."单据货币"='RMB' THEN NULL ELSE SUM(T0."含税金额(原币)") END AS "FCDebit",NULL AS "FCCredit"
		,SUM(T0."含税金额(本币)") AS "Debit",0.00 AS "Credit"
		FROM :TMP T0
		LEFT JOIN OCRD T1 ON T0."客户代码"=T1."CardCode"
		LEFT JOIN OACT T2 ON CASE WHEN T1."GroupCode"='100' THEN '112203' WHEN T1."GroupCode"='106' THEN '112204' END=T2."AcctCode"
		LEFT JOIN OTRC T31 ON T31."TrnsCode"=:TransCode
		WHERE IFNULL(T0."销售类型",'') NOT IN ('国内样品','外贸样品')
		GROUP BY T2."AcctCode",T2."AcctName",T31."TrnsCode",T31."TrnsCodDsc"
		,T1."CardCode",T1."CardName",T0."单据货币"
		
		UNION ALL
		SELECT 'N' AS "flag",NULL AS "TransId",T31."TrnsCode" AS "TransCode",T31."TrnsCodDsc",:EndDate AS "RefDate"
		,T31."TrnsCodDsc"||','||:FcCode||'月' AS "Memo",T2."AcctCode" AS "Account",T2."AcctName"
		,NULL AS "ShortName",NULL AS "CardName",T0."单据货币" AS "DocCur"
		,NULL AS "FCDebit",CASE WHEN T0."单据货币"='RMB' THEN NULL ELSE SUM(T0."未税金额(原币)") END AS "FCCredit"
		,0.00 AS "Debit",SUM(T0."未税金额(本币)") AS "Credit"
		FROM :TMP T0
		LEFT JOIN OCRD T1 ON T0."客户代码"=T1."CardCode"
		LEFT JOIN OACT T2 ON T0."AcctCode"=T2."AcctCode"
		LEFT JOIN OTRC T31 ON T31."TrnsCode"=:TransCode
		WHERE IFNULL(T0."销售类型",'') NOT IN ('国内样品','外贸样品')
		GROUP BY T2."AcctCode",T2."AcctName",T31."TrnsCode",T31."TrnsCodDsc",T0."单据货币"
		
		UNION ALL
		SELECT 'N' AS "flag",NULL AS "TransId",T31."TrnsCode" AS "TransCode",T31."TrnsCodDsc",:EndDate AS "RefDate"
		,T31."TrnsCodDsc"||','||:FcCode||'月' AS "Memo",T2."AcctCode" AS "Account",T2."AcctName"
		,NULL AS "ShortName",NULL AS "CardName",T0."单据货币" AS "DocCur"
		,NULL AS "FCDebit",CASE WHEN T0."单据货币"='RMB' THEN NULL ELSE SUM(T0."含税金额(原币)"-T0."未税金额(原币)") END AS "FCCredit"
		,0.00 AS "Debit",SUM(T0."含税金额(本币)"-T0."未税金额(本币)") AS "Credit"
		FROM :TMP T0
		LEFT JOIN OCRD T1 ON T0."客户代码"=T1."CardCode"
		LEFT JOIN OACT T2 ON T2."AcctCode"='22210106'
		LEFT JOIN OTRC T31 ON T31."TrnsCode"=:TransCode
		WHERE IFNULL(T0."销售类型",'') NOT IN ('国内样品','外贸样品')
		GROUP BY T2."AcctCode",T2."AcctName",T31."TrnsCode",T31."TrnsCodDsc",T0."单据货币"
		
		;
		
		
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
				,T0."TransCode",T0."Memo",'Y',TO_VARCHAR(:RevDate,'YYYYMMDD')
				FROM :TMP_OJDT T0;
			
			INSERT INTO "@MTC_COST_OJDT1"(
				"DocEntry","LineId","U_LineMemo"
				,"U_AcctCode","U_AcctName","U_CardCode","U_CardName","U_FCCurrency"
				,"U_FCDebit","U_FCCredit","U_Debit","U_Credit"
				)
			SELECT :MAXEntry+1 AS "DocEntry"
				,ROW_NUMBER() OVER (PARTITION BY "TransCode","RefDate" ORDER BY T0."AcctCode",T0."CardCode") AS "LineId","Memo"
				,T0."AcctCode",T0."AcctName",T0."CardCode",T0."CardName",T0."FCCurrency"
				,ROUND(T0."FCDebit",2),ROUND(T0."FCCredit",2),ROUND(T0."Debit",2),ROUND(T0."Credit",2)
				FROM :TMP_OJDT T0 
				WHERE 1=1
				AND (ABS(IFNULL(ROUND(T0."Debit",2),0))+ABS(IFNULL(ROUND(T0."Credit",2),0))+ABS(IFNULL(ROUND(T0."FCDebit",2),0))+ABS(IFNULL(ROUND(T0."FCCredit",2),0)))<>0
			;
			
			
			INSERT INTO "@MTC_COST_OJDT2"(
					"DocEntry","LineId","VisOrder",
					"Object","LogInst","U_Type",
					"U_ObjType","U_DocEntry","U_DocNum","U_LineNum",
					"U_BaseType","U_BaseEntry","U_BaseRef","U_BaseLine",
					"U_ItemCode","U_ItemName","U_Quantity",
					"U_CardCode","U_CardName","U_AcctCode","U_AcctName",
					"U_Price","U_LineTotal","U_PriceAfVAT","U_GTotal","U_GTotalFc",
					"U_Debit","U_Credit","U_Point","U_FCDebit","U_FCCredit",
					"U_Project","U_OcrCode1","U_OcrCode2","U_OcrCode3","U_OcrCode4","U_OcrCode5",
					"U_CostPrice","U_CostAmt","U_VatSum","U_StockAcctCode","U_StockAcctName","U_DocDate","U_WhsCode"	
					,"U_Currency"		
					)
				SELECT :MAXEntry+1 AS "DocEntry"
				,ROW_NUMBER() OVER(ORDER BY P0."交货单号Num") AS "LineId"
				,ROW_NUMBER() OVER(ORDER BY P0."交货单号Num") AS "VisOrder"
				,'MTC_COST_OJDT' AS "Object",NULL AS "LogInst",P0."销售类型" AS "U_Type"
				,P0."ObjType" AS "U_ObjType",P0."交货单号Num" AS "U_DocEntry",P0."订单号" AS "U_DocNum",P0."行号" AS "U_LineNum"
				,NULL AS "U_BaseType",NULL AS "U_BaseEntry",NULL AS "U_BaseRef",NULL AS "U_BaseLine"
				,P0."物料号" "U_ItemCode",P0."描述" "U_ItemName",P0."系统未清数量" AS "U_Quantity"
				,T1."CardCode" AS "U_CardCode",T1."CardName" AS "U_CardName"
				,T2."AcctCode" AS "U_AcctCode",T2."AcctName" AS "U_AcctName"
				,"未税单价(原币)" AS "U_Price",P0."未税金额(本币)" AS "U_LineTotal",0.00 AS "U_PriceAfVAT","含税金额(本币)" AS "U_GTotal","含税金额(原币)" AS "U_GtotalFC"
				
				,0.00 AS "U_Debit",P0."含税金额(本币)" AS "U_Credit",NULL AS "U_Point"
				,0.00 AS "FCDebit"
				,CASE WHEN P0."单据货币"='RMB' THEN NULL ELSE (P0."含税金额(原币)") END AS "FCCredit"
				,NULL AS "U_Project",NULL AS "U_OcrCode1",NULL AS "U_OcrCode2",NULL AS "U_OcrCode3",NULL AS "U_OcrCode4",NULL AS "U_OcrCode5"			
				,"成本单价" AS "CostPrice","成本金额" AS "CostAmt"
				,P0."含税金额(本币)"-P0."未税金额(本币)" AS "VatSum",NULL AS "StockAcctCode",NULL AS "StockAcctName"
				,P0."过账日期" AS "DocDate",P0."WhsCode",P0."单据货币"
				FROM :TMP P0
				LEFT JOIN OCRD T1 ON P0."客户代码"=T1."CardCode"
				LEFT JOIN OACT T2 ON P0."AcctCode"=T2."AcctCode"
				LEFT JOIN OTRC T31 ON T31."TrnsCode"=:TransCode
				WHERE IFNULL(P0."销售类型",'') NOT IN ('国内样品','外贸样品');
			
			SELECT 'Y' AS "flag",T0."DocEntry",T1."LineId",TO_VARCHAR(T0."U_RefDate",'YYYYMMDD') AS "RefDate"
				,T0."U_TransCode" AS "TransCode",NULL AS "TransName",T0."U_Memo" AS "Memo"
				,T1."U_AcctCode" AS "AcctCode",T1."U_AcctName" AS "AcctName",T1."U_CardCode" AS "CardCode"
				,T1."U_CardName" AS "CardName",T1."U_FCCurrency" AS "FCCurrency"
				,T1."U_FCDebit" AS "FCDebit",T1."U_FCCredit" AS "FCCredit",T1."U_Debit" AS "Debit",T1."U_Credit" AS "Credit"
				,T0."U_IsRev" AS "IsRev",TO_VARCHAR(T0."U_RevDate",'YYYYMMDD') AS "RevDate"
			FROM "@MTC_COST_OJDT" T0
			JOIN "@MTC_COST_OJDT1" T1 ON T0."DocEntry"=T1."DocEntry"
			WHERE T0."U_FcCode"=:FcCode AND T0."U_TransCode"=:TransCode
			AND (ABS(IFNULL(T1."U_Debit",0))+ABS(IFNULL(T1."U_Credit",0))+ABS(IFNULL(T1."U_FCDebit",0))+ABS(IFNULL(T1."U_FCCredit",0)))<>0
			;
			
		END IF;
	END IF;
	
	
	
END