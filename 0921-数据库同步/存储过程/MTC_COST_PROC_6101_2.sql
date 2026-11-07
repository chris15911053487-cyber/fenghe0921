CREATE PROCEDURE "MTC_COST_PROC_6101_2"
(
  UserCode NVARCHAR(50),
  FcCode NVARCHAR(50),
  IsSum NVARCHAR(30)
)
AS
BEGIN
	
	DECLARE sdate DATE;
	DECLARE edate DATE;
	
	SELECT '2024-01-01',"T_RefDate" INTO sdate,edate FROM "OFPR" WHERE "Code"=:FcCode;
	--SELECT "F_RefDate","T_RefDate" INTO sdate,edate FROM "OFPR" WHERE "Code"=:FcCode;

	TMP=
	SELECT T0."U_SalOrdType" AS "Type"
	,T0."CardCode",T0."CardName",T0."DocDate",T0."U_OldSysNo" AS "OPOROldSN",T0."U_OldSysNo" AS "OPDNOldSN"
	,T0."ObjType" AS "CalObjType",T0."DocEntry" AS "CalDocEntry",T0."DocNum" AS "CalDocNum",T1."LineNum" AS "CalLineNum"
	,T0."ObjType",T0."DocEntry",T0."DocNum",T1."LineNum",T1."U_ItemCode"
	,T1."ItemCode"
	,CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END*T1."Quantity" AS "Qty"
	,T1."U_InitPrice" AS "Price"
	,CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END
			*T1."Quantity"*T1."U_InitPrice" AS "Amt"
	,CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END*T1."LineTotal" AS "LineTotal"
	,CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END*T1."GTotal" AS "GTotal"
	FROM "ODLN" T0
	INNER JOIN "DLN1" T1 ON T0."DocEntry"=T1."DocEntry"
	INNER JOIN "OITM" T2 ON T1."ItemCode"=T2."ItemCode"
	WHERE 1=1
	AND T0."DocDate">=:sdate
	AND T0."DocDate"<=:edate
	
	UNION ALL
	SELECT T0."U_SalOrdType" AS "Type"
	,T0."CardCode",T0."CardName",T0."DocDate",T2."OPOROldSN",T2."OPDNOldSN"
	,T0."ObjType" AS "CalObjType",T0."DocEntry" AS "CalDocEntry",T0."DocNum" AS "CalDocNum",T1."LineNum" AS "CalLineNum"
	,T0."ObjType",T0."DocEntry",T0."DocNum",T1."LineNum",T1."U_ItemCode"
	,T1."ItemCode"
	,CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END*T1."Quantity" AS "Qty"
	,T1."U_InitPrice" AS "Price"
	,CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END
			*T1."Quantity"*T1."U_InitPrice" AS "Amt"
	,CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END*T1."LineTotal" AS "LineTotal"
	,CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END*T1."GTotal" AS "GTotal"
	FROM "ORDN" T0
	INNER JOIN "RDN1" T1 ON T0."DocEntry"=T1."DocEntry"
	LEFT JOIN (SELECT M."ObjType",D."DocEntry",M."DocNum",D."LineNum"
			,CASE WHEN IFNULL(D."U_InitPrice",0)<>0 THEN D."U_InitPrice" ELSE D."Price" END AS "Price"
			,M."U_OldSysNo" "OPOROldSN",M."U_OldSysNo" "OPDNOldSN"
			 FROM "ODLN" M
			 JOIN "DLN1" D ON M."DocEntry"=D."DocEntry"
			 ) T2 ON T1."BaseType"=T2."ObjType" AND T1."BaseEntry"=T2."DocEntry" AND T1."BaseLine"=T2."LineNum"
	WHERE 1=1
	AND T0."DocDate">=:sdate
	AND T0."DocDate"<=:edate
	
	--针对来源于采购收货，才需要冲销暂估，需要按照采购收货的价格进行（冲暂估的金额，所以价格的取数要和采购收货单的一致）
	UNION ALL
	SELECT T0."U_SalOrdType" AS "Type"
	,T0."CardCode",T0."CardName",T0."DocDate",T2."OPOROldSN",T2."OPDNOldSN"
	,T2."ObjType" AS "CalObjType",T2."DocEntry" AS "CalDocEntry",T2."DocNum" AS "CalDocNum",T2."LineNum" AS "CalLineNum"
	,T0."ObjType",T0."DocEntry",T0."DocNum",T1."LineNum",T1."U_ItemCode"
	,T1."ItemCode"
	,CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END*T1."Quantity" AS "Qty"
	,T2."Price" AS "Price"
	,CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END
			*T1."Quantity"*T2."Price" AS "Amt"
	,CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END*T1."LineTotal" AS "LineTotal"
	,CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END*T1."GTotal" AS "GTotal"
	FROM "OINV" T0
	INNER JOIN "INV1" T1 ON T0."DocEntry"=T1."DocEntry"
	JOIN (SELECT M."ObjType",D."DocEntry",M."DocNum",D."LineNum"
			,D."U_InitPrice" AS "Price"
			,M."U_OldSysNo" "OPOROldSN",M."U_OldSysNo" "OPDNOldSN"
			FROM "ODLN" M
			 JOIN "DLN1" D ON M."DocEntry"=D."DocEntry"
			 ) T2 ON T1."BaseType"=T2."ObjType" AND T1."BaseEntry"=T2."DocEntry" AND T1."BaseLine"=T2."LineNum"
	WHERE 1=1
	AND T0."DocDate">=:sdate
	AND T0."DocDate"<=:edate
	AND T0."CANCELED"='N'
	
	UNION ALL
	SELECT T0."U_SalOrdType" AS "Type"
	,T0."CardCode",T0."CardName",T0."DocDate",'' AS "OPOROldSN",'' AS "OPDNOldSN"
	,T2."ObjType" AS "CalObjType",T2."DocEntry" AS "CalDocEntry",T2."DocNum" AS "CalDocNum",T2."LineNum" AS "CalLineNum"
	,T0."ObjType",T0."DocEntry",T0."DocNum",T1."LineNum",T1."U_ItemCode"
	,T1."ItemCode"
	,CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END*T1."Quantity" AS "Qty"
	,T2."Price" AS "Price"
	,CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END
			*T1."Quantity"*T2."Price" AS "Amt"
	,CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END*T1."LineTotal" AS "LineTotal"
	,CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END*T1."GTotal" AS "GTotal"
	FROM "ORIN" T0
	INNER JOIN "RIN1" T1 ON T0."DocEntry"=T1."DocEntry"
	JOIN (SELECT M."ObjType",D."DocEntry",M."DocNum",D."LineNum"
			,D."U_InitPrice" AS "Price"
			 FROM "ORDN" M
			 JOIN "RDN1" D ON M."DocEntry"=D."DocEntry"
			 ) T2 ON T1."BaseType"=T2."ObjType" AND T1."BaseEntry"=T2."DocEntry" AND T1."BaseLine"=T2."LineNum"
	WHERE 1=1
	AND T0."DocDate">=:sdate
	AND T0."DocDate"<=:edate
	AND T0."CANCELED"='N';
	
	IF :IsSum=0 THEN
		
		SELECT '当月应付暂估计提' AS "Memo",T0."Type",NULL AS "CardCode",NULL AS "CardName",T0."ObjType"
		,T4."AcctCode",T4."AcctName"
		,SUM(T0."Amt") AS "Debit",0.00 AS "Credit"
		FROM :TMP T0 
		JOIN OITM T2 ON T0."ItemCode"=T2."ItemCode"
		LEFT JOIN (SELECT "ItmsGrpCod",MAX("StockAct") AS "StockAct" FROm OGAR WHERE "PeriodCat"=LEFT('2024-12',4) GROUP BY "ItmsGrpCod"
				) T3 ON T2."ItmsGrpCod"=T3."ItmsGrpCod"
		LEFT JOIN OACT T4 ON T4."AcctCode"=CASE WHEN T0."Type"='委外费用' THEN '140802' ELSE T3."StockAct" END
		WHERE T0."ObjType" IN (15,16)
		GROUP BY T0."Type",T0."ObjType",T4."AcctCode",T4."AcctName"
		
		UNION ALL
		SELECT '当月应付暂估计提' AS "Memo",T0."Type",T0."CardCode",T0."CardName",T0."ObjType"
		,T4."AcctCode",T4."AcctName",0.00
		,SUM(T0."Amt") AS "Credit"
		FROM :TMP T0 
		LEFT JOIN OACT T4 ON T4."AcctCode"='220202'
		WHERE T0."ObjType" IN (20,21)
		GROUP BY T0."Type",T0."CardCode",T0."CardName",T0."ObjType",T4."AcctCode",T4."AcctName"
		
		UNION ALL
		SELECT '当月冲销应付暂估' AS "Memo",T0."Type",T0."CardCode",T0."CardName",T0."ObjType"
		,T4."AcctCode",T4."AcctName",0.00
		,SUM(T0."Amt") AS "Amt"
		FROM :TMP T0 
		LEFT JOIN OACT T4 ON T4."AcctCode"='220202'
		WHERE T0."ObjType" IN (18,19)
		GROUP BY T0."Type",T0."ObjType",T4."AcctCode",T4."AcctName",T0."CardCode",T0."CardName"
		
		;
		
	ELSE 
		SELECT T0."Type" AS "类型",T2."GroupCode"
		,CASE WHEN T0."ObjType"='15' THEN '销售交货' WHEN T0."ObjType"='16' THEN '销售退货'
			 WHEN T0."ObjType"='13' THEN '应收发票' WHEN T0."ObjType"='14' THEN '应收贷项凭证' END AS "单据类型"
		,T0."CardCode" AS "客户编码",T0."CardName" AS "客户名称",T0."DocDate" AS "过账日期"
		,T0."OPOROldSN" AS "采购订单OldSN",T0."OPDNOldSN" AS "采购收货OldSN"
		,T0."ItemCode" AS "物料编码",T1."ItemName" AS "物料名称",T0."U_ItemCode" AS "委外物料编码"
		,T0."Qty" AS "数量"
		,T0."Price" AS "未税成本单价"
		,T0."Amt" AS "未税成本金额"
		,T0."LineTotal" AS "参考未税金额"
		,T0."GTotal" AS "参考含税金额"
		,T0."CalObjType",T0."CalDocEntry",T0."CalDocNum",T0."CalLineNum"
		,T0."ObjType",T0."DocEntry",T0."DocNum",T0."LineNum"
		FROM :TMP T0
		LEFT JOIN OITM T1 ON T0."ItemCode"=T1."ItemCode"
		LEFT JOIN OCRD T2 ON T0."CardCode"=T2."CardCode"
		;
	END IF;
	

END