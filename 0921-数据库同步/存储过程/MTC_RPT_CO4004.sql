CREATE PROCEDURE "MTC_RPT_CO4004"
(
  IN STYPE INT,	--0汇总  1明细
  IN FcCode NVARCHAR(30),
  IN ItemCode NVARCHAR(50)
 )
LANGUAGE SQLSCRIPT
AS
BEGIN 

	SELECT  
	T0."FcCode" AS "期间",
	T0."DocType",
	(CASE T0."WorType" WHEN 10 THEN '生产计划单' WHEN 20 THEN '包装计划单' WHEN 30 THEN '返工计划单' WHEN 40 THEN '生产试打' WHEN 50 THEN '委外工单' END) AS "工单类型",
	T0."DocDate" AS "订单日期",
	T0."CloseDate" AS "订单关单日期",
	CASE WHEN T0."Status"='R' THEN '已下达' WHEN T0."Status"='L' THEN '已结算' WHEN T0."Status"='P' THEN '已计划' END  AS "订单状态",
	T9."U_SupNum" AS "订单号",
	T0."WorEntry" AS "生产订单号Entry",
	T0."WorNum",
	T10."CardCode",
	T10."CardName",
	T0."ItemCode" AS "物料编码" ,
	T0."ItemName" AS "物料名称",
	T0."ItmsGrpCod" AS "物料组",
	T0."WorQty" AS "订单数量",
	T0."IgnQty" AS "当期入库数量",
	TO_CHAR(CAST(T0."Price" AS DECIMAL(19,6))) AS "完工入库单价",
	T0."IgnQty"*T0."Price" AS "当期入库成本金额",
	T0."Amount" AS "当期成本合计",
	T0."1Material" AS "当期材料金额",
	T0."2ManExp" AS "当期人工费用",
	T0."3LabAmount" AS "当期制造费用",
	T0."4WWExp" AS "当期委外费用",
	IFNULL(T0."CloseDifAmt",0) AS "关单差异",
	T21."IgnQty" AS "财务入库数量",
	T21."IgnAmt" AS "财务入库金额",
	IFNULL(T0."Amount",0)-IFNULL(T21."IgnAmt",0) AS "差异[当期成本合计-财务入库金额]"
	FROM MTC_COST_0321_OWOR_SUM T0
	JOIN OITM T2 ON T0."ItemCode"=T2."ItemCode"
	LEFT JOIN (SELECT "ItmsGrpCod",MAX("StockAct") AS "StockAct" FROM OGAR WHERE "PeriodCat"=LEFT(:FcCode,4) GROUP BY "ItmsGrpCod"
					) T3 ON T2."ItmsGrpCod"=T3."ItmsGrpCod"
	LEFT JOIN
			(SELECT '202' AS "DocType","DocEntry","DocNum","U_SupNum","U_OldSysNo","U_CardCode","U_CardName" FROM OWOR
				UNION ALL
			SELECT "Object","DocEntry","DocNum","U_SupNum","U_OldSysNo","U_CardCode","U_CardName" FROM "@MTC_OWOR"
			) T9 ON T0."WorEntry"=T9."DocEntry" AND T0."DocType"=T9."DocType"
	LEFT JOIN OCRD T10 ON T10."CardCode"=T9."U_CardCode"
	LEFT JOIN (SELECT "BaseType","BaseEntry",SUM("Quantity") AS "IgnQty",SUM("Amount") AS "IgnAmt"
			   FROM MTC_COST_0302_INVNTDETAIL1 T0
			   JOIN "@U_CIOTRN" T6 ON T0."BusiType"=T6."Code"
			   WHERE "FcCode"=:FcCode AND "CostCode"='20' AND T6."U_TransType"='B01'
			   GROUP BY "BaseType","BaseEntry"
			) T21 ON T0."DocType"=T21."BaseType" AND T0."WorEntry"=T21."BaseEntry"
	WHERE T0."FcCode" = :FcCode
	AND IFNULL(T0."IgnQty",0)<>0
	;
END