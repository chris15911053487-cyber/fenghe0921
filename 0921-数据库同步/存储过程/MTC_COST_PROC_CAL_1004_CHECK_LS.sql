CREATE PROCEDURE "MTC_COST_PROC_CAL_1004_CHECK_LS"(IN FcCode NVARCHAR(10),IN UserCode NVARCHAR(50),IN IsInsert NVARCHAR(30) DEFAULT 'N')
LANGUAGE SQLSCRIPT
AS
BEGIN

	SELECT T0."FcCode" AS "期间"
	,T0."DocType" AS "生产订单类型"
	,T0."WorType" AS "工单类型"
	,T0."WorEntry" AS "订单号Entry"
	,T0."WorNum" AS "订单号Num"
	,T0."ItemCode" AS "物料编码"
	,T0."ItemName" AS "物料名称"
	,T0."IgnQty" AS "工单入库数量"
	,T0."Amount" AS "成本合计"
	,T0."1Material" AS "工单原材料金额"
	,T0."2ManExp" AS "工单人工费用"
	,T0."3LabAmount" AS "工单制造费用"
	,T0."4WWExp" AS "工单委外费用"
	,T1."IgnAmt" AS "实际入库金额明细"
	,IFNULL(T0."Amount",0)-IFNULL(T1."IgnAmt",0) AS "入库差异"
	,T1."IgeAmt" AS "实际发料金额明细"
	,IFNULL(T0."1Material",0)-IFNULL(T1."IgeAmt",0) AS "发料差异"
	FROM 
		(
		SELECT "FcCode","DocType","WorType","WorEntry","WorNum","ItemCode","ItemName"
		,SUM("IgnQty") AS "IgnQty",SUM("Amount") AS "Amount"
		,SUM("1Material") AS "1Material",SUM("2ManExp") AS "2ManExp",SUM("3LabAmount") AS "3LabAmount",SUM("4WWExp") AS "4WWExp"
		FROM "MTC_COST_0321_OWOR"
		WHERE 1=1
		AND "FcCode"<=:FcCode
		--AND "WorEntry"=49432
		GROUP BY "FcCode","DocType","WorType","WorEntry","WorNum","ItemCode","ItemName"
		) T0
	LEFT JOIN (
		SELECT "FcCode","BaseType","BaseEntry"
		,-1*SUM(CASE WHEN "TransCode" IN ('O03','O07','O08','O09') THEN "Amount" ELSE 0 END) AS "IgeAmt"
		,SUM(CASE WHEN "TransCode" IN ('I03','I07','I08','I09') THEN "Amount" ELSE 0 END) AS "IgnAmt"
		FROM "MTC_COST_0302_INVNTDETAIL1"
		WHERE 1=1
		AND "FcCode"<=:FcCode
		--AND "BaseEntry"=49432
		GROUP BY "FcCode","BaseType","BaseEntry"
		) T1 ON T0."FcCode"=T1."FcCode" AND T0."DocType"=T1."BaseType" AND T0."WorEntry"=T1."BaseEntry"
	WHERE T0."FcCode"=:FcCode
	AND T0."WorType"<>'40'
	AND ( IFNULL(T0."1Material",0)-IFNULL(T1."IgeAmt",0)<>0)
	;
		
END;