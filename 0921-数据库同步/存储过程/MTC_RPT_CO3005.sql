CREATE Procedure "MTC_RPT_CO3005"
(
 IN SFcCode		NVARCHAR(30)
,IN EFcCode		NVARCHAR(30)
,IN ItemCode	NVARCHAR(50)
,IN ItmsGrpCod  INT DEFAULT 0
,IN TransCode NVARCHAR(50)
,IN IOType NVARCHAR(10)
)
LANGUAGE SQLSCRIPT

AS	
BEGIN
	
	DECLARE sdate date;
	DECLARE edate date;
	
	SELECT "F_RefDate" INTO sdate FROM OFPR WHERE "Code"=:SFcCode;
	SELECT "T_RefDate" INTO edate FROM OFPR WHERE "Code"=:EFcCode;
	
	TMP_LIST=
	SELECT -1 AS "ID",
	T0."BPLId",
	:SFcCode AS "FcCode",
	T0."ItemCode",
	T0."ItemName",
	T5."ItmsGrpNam",
	'-1' AS "ObjType",
	'期初余额' AS "DocName",
	NULL AS "DocEntry",
	NULL AS "DocNum",
	NULL AS "DocSupNum",
	NULL AS "LineNum",
	:sdate AS "DocDate",
	NULL AS "TransCode",
	NULL AS "TransName",
	NULL AS "BusiType",
	NULL AS "BusiTypeN",
	NULL AS "BaseType",
	NULL AS "BaseTypeN",
	NULL AS "BaseEntry",
	NULL AS "BaseNum",
	NULL AS "BaseDocSupNum",
	NULL AS "BaseLine",
	NULL AS "Quantity",
	NULL AS "Price",
	NULL AS "Amount",
	T0."QC_Qty" AS "BalQty",
	T0."QC_Amount" AS "Balance",
	T2."InvntryUom" AS "单位",
	NULL AS "部门编码",
	NULL AS "部门名称",
	T51."AcctCode" AS "库存科目编码",
	T51."AcctCode" AS "库存科目名称",
	NULL AS "其他领用科目编码",
	NULL AS "其他领用科目名称",
	NULL AS "仓库编码",
	NULL"CreateDate",
	NULL"Creator",
	NULL"iLevel",
	NULL AS "价格备注",
	NULL AS "价格标识"
	FROM MTC_COST_0301_INVNT T0
	LEFT JOIN OITM T2 ON T0."ItemCode"=T2."ItemCode"
	LEFT JOIN (SELECT "ItmsGrpCod",MAX("StockAct") AS "StockAct" FROm OGAR WHERE "PeriodCat"='2024' GROUP BY "ItmsGrpCod"
		) T3 ON T2."ItmsGrpCod"=T3."ItmsGrpCod"
	LEFT JOIN OITB T5 ON T2."ItmsGrpCod"=T5."ItmsGrpCod"
	LEFT JOIN OACT T51 ON T3."StockAct"=T51."AcctCode"
	WHERE 1=0
	AND (T0."FcCode" = :SFcCode)
	AND (T0."ItemCode"=:ItemCode OR :ItemCode='')
	AND (T2."ItmsGrpCod"=:ItmsGrpCod OR :ItmsGrpCod=0)
	AND T0."CostCode"='20'
	
	UNION ALL
	SELECT ROW_NUMBER() OVER(PARTITION BY T0."ItemCode" ORDER BY T0."FcCode",T0."DocDate") AS "ID",
	T0."BPLId",
	T0."FcCode",
	T0."ItemCode",
	T0."ItemName",
	T5."ItmsGrpNam",
	T0."ObjType",
	T9."DocName",
	T0."DocEntry",
	T0."DocNum",
	T0."DocSupNum",
	T0."LineNum",
	T0."DocDate",
	T10."Code" AS "TransCode",
	T10."Code"||'-'||T10."Name" AS "TransName",
	T0."BusiType",
	T0."BusiTypeN",
	T0."BaseType",
	T11."DocName" AS "BaseTypeN",
	T0."BaseEntry",
	T0."BaseNum",
	T0."BaseDocSupNum",
	T0."BaseLine",
	T0."Quantity",
	CAST(CAST(T0."Price" AS DECIMAL(19,6)) AS NVARCHAR(50)) AS "Price",
	T0."Amount",
	T0."Quantity" AS "BalQty",
	T0."Amount" AS "Balance",
	T2."InvntryUom" AS "单位",
	T0."OcrCode1" AS "部门编码",
	P."PrcName" AS "部门名称",
	T3."StockAct" AS "库存科目编码",
	T51."AcctName" AS "库存科目名称",
	T4."AcctCode" AS "其他领用科目编码",
	T52."AcctName" AS "其他领用科目名称",
	T0."WhsCode" AS "仓库编码",
	T0."CreateDate",
	T0."Creator",
	T0."iLevel",
	T0."PriceMemo" AS "价格备注",
	T0."IsUpdatePrice" AS "价格标识"
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	LEFT JOIN (SELECT * FROM MTC_COST_0301_INVNT WHERE "FcCode"='[%0]' AND "CostCode"='20') T1 ON T0."ItemCode"=T1."ItemCode"
	LEFT JOIN OITM T2 ON T0."ItemCode"=T2."ItemCode"
	LEFT JOIN (SELECT "ItmsGrpCod",MAX("StockAct") AS "StockAct" FROm OGAR WHERE "PeriodCat"=:EFcCode GROUP BY "ItmsGrpCod"
		) T3 ON T2."ItmsGrpCod"=T3."ItmsGrpCod"
	LEFT JOIN (
		SELECT "ObjType","DocEntry","LineNum","AcctCode" FROM IGN1
			UNION ALL
		SELECT "ObjType","DocEntry","LineNum","AcctCode" FROM IGE1
		) T4 ON T0."ObjType"=TO_CHAR(T4."ObjType") AND T0."DocEntry"=T4."DocEntry" AND T0."LineNum"=T4."LineNum"
	LEFT JOIN OITB T5 ON T0."ItmsGrpCod"=T5."ItmsGrpCod"
	LEFT JOIN "MTC_DocType" T9 ON T0."ObjType"=T9."ObjType"
	LEFT JOIN "MTC_DocType" T11 ON T0."BaseType"=T11."ObjType"
	LEFT JOIN "@MTC_COST_IOTYPE" T10 ON T0."TransCode"=T10."Code"
	LEFT JOIN OACT T51 ON T3."StockAct"=T51."AcctCode"
	LEFT JOIN OACT T52 ON T4."AcctCode"=T52."AcctCode"
	LEFT JOIN OPRC P ON T0."OcrCode1"=P."PrcCode"
	WHERE 1=1
	AND (T0."FcCode" >= :SFcCode OR :SFcCode='')
	AND (T0."FcCode" <= :EFcCode OR :EFcCode='')
	AND (T0."ItemCode"=:ItemCode OR :ItemCode='')
	AND (T2."ItmsGrpCod"=:ItmsGrpCod OR :ItmsGrpCod=0)
	AND T0."CostCode"='20'
	
	;
	
	SELECT 
	T0."FcCode",
	T0."ItemCode",
	T0."ItemName",
	T0."ItmsGrpNam",
	T0."DocDate",
	T0."ObjType",
	T0."DocName",
	T0."DocEntry",
	T0."DocNum",
	T1."U_SupNum" AS "业务单号",
	T0."LineNum",
	T0."TransName",
	T0."BusiType",
	T0."BusiTypeN",
	T0."Quantity",
	T0."Price",
	T0."Amount",
	CASE WHEN T0."ID"=99999999 THEN "BalQty" ELSE SUM(T0."BalQty") OVER (PARTITION BY T0."ItemCode" ORDER BY T0."ID") END AS "累计数量",
	TO_CHAR(CAST((SUM(T0."Balance") OVER (PARTITION BY T0."ItemCode" ORDER BY T0."ID")/
	NULLIF(SUM(T0."BalQty") OVER (PARTITION BY T0."ItemCode" ORDER BY T0."ID"),0)) AS DECIMAL(19,6)))
	 AS "累计成本单价",
	CASE WHEN T0."ID"=99999999 THEN "Balance" ELSE SUM(T0."Balance") OVER (PARTITION BY T0."ItemCode" ORDER BY T0."ID") END AS "累计余额",
	T0."BaseType",
	T0."BaseTypeN"||'-'||T2."U_OrdType",
	T0."BaseEntry",
	T0."BaseNum",
	T0."BaseLine",
	T2."ItemCode" AS "产成品的物料编码",
	T2."ItemName" AS "产成品的物料名称",
	T2."U_SupNum" AS "生产订单的业务单号",
	P1."OcrCode" AS "生产订单的部门编码",
	P1."OcrName" AS "生产订单的部门名称",
	T0."单位",
	T0."部门编码",
	T0."部门名称",
	T0."库存科目编码",
	T0."库存科目名称",
	T0."其他领用科目编码",
	T0."其他领用科目名称",
	T0."仓库编码",
	T0."CreateDate",
	T0."Creator",
	T0."iLevel",
	T0."价格备注",
	T0."价格标识",
	CASE WHEN T10."U_IOType"='I' THEN '入库' WHEN T10."U_IOType"='O' THEN '出库' END AS "出入库类型"
	FROM :TMP_LIST T0
	LEFT JOIN (SELECT DISTINCT "ObjType","DocEntry","LineNum","U_SupNum" FROM "MTC_VIEW_Document") T1 ON T0."ObjType"=T1."ObjType" AND T0."DocEntry"=T1."DocEntry" AND T0."LineNum"=T1."LineNum"
	LEFT JOIN (SELECT '202' AS "ObjType","DocEntry","U_SupNum","U_OrdType","ItemCode","ProdName" AS "ItemName","OcrCode" FROM OWOR
				UNION ALL
			   SELECT "Object","DocEntry","U_SupNum","U_OrdType","U_ItemCode","U_ProdName","U_OcrCode" FROM "@MTC_OWOR"
			) T2 ON T0."BaseType"='202' AND T0."BaseEntry"=T2."DocEntry"
	LEFT JOIN "@MTC_COST_IOTYPE" T10 ON T0."TransCode"=T10."Code"
	LEFT JOIN OOCR P1 ON T2."OcrCode"=P1."OcrCode"
	WHERE 1=1
	AND (T0."TransCode"=:TransCode OR :TransCode='')
	AND (T10."U_IOType"=:IOType OR :IOType='')
	ORDER BY T0."ItemCode",T0."ID";
	
	
	
END