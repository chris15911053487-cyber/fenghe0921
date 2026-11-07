CREATE PROCEDURE "MTC_COST_PROC_CAL_1004_CHECK"(IN FcCode NVARCHAR(10),IN UserCode NVARCHAR(50),IN IsInsert NVARCHAR(30) DEFAULT 'N')
LANGUAGE SQLSCRIPT
AS
BEGIN

	SELECT T0."FcCode" AS "期间"
	,T0."DocType" AS "生产订单类型"
	,T0."WorType" AS "工单类型"
	,T0."WorEntry" AS "订单号Entry"
	,T0."WorNum" AS "订单号Num"
	,T0."LineNum" AS "行号"
	,T0."ItemCode" AS "材料编码"
	,T0."ItemName" AS "材料名称"
	,T0."IgeQty" AS "工单领料数量"
	,T0."Amount" AS "工单领料金额"
	,T1."IgeQty" AS "实际领料数量"
	,T1."IgeAmt" AS "实际领料金额"
	,IFNULL(T0."IgeQty",0)-IFNULL(T1."IgeQty",0) AS "数量差异"
	,IFNULL(T0."Amount",0)-IFNULL(T1."IgeAmt",0) AS "金额差异"
	FROM 
		(
		SELECT "FcCode","DocType","WorType","WorEntry","WorNum","ItemCode","ItemName","LineNum"
		,-1*SUM("IgeQty") AS "IgeQty",-1*SUM("Amount") AS "Amount"
		FROM "MTC_COST_0321_OWOR1"
		WHERE 1=1
		AND "FcCode"<=:FcCode
		--AND "WorEntry"=71907
		GROUP BY "FcCode","DocType","WorType","WorEntry","WorNum","ItemCode","ItemName","LineNum"
		) T0
	LEFT JOIN (
		SELECT "FcCode","BaseType","BaseEntry","BaseLine"
		,-1*SUM(CASE WHEN "TransCode" IN ('O03','O07','O08','O09') THEN "Quantity" ELSE 0 END) AS "IgeQty"
		,-1*SUM(CASE WHEN "TransCode" IN ('O03','O07','O08','O09') THEN "Amount" ELSE 0 END) AS "IgeAmt"
		,SUM(CASE WHEN "TransCode" IN ('I03','I07','I08','I09') THEN "Amount" ELSE 0 END) AS "IgnAmt"
		FROM "MTC_COST_0302_INVNTDETAIL1"
		WHERE 1=1
		AND "FcCode"<=:FcCode
		--AND "BaseEntry"=71907
		GROUP BY "FcCode","BaseType","BaseEntry","BaseLine"
		) T1 ON T0."FcCode"=T1."FcCode" AND T0."DocType"=T1."BaseType" AND T0."WorEntry"=T1."BaseEntry" AND T0."LineNum"=T1."BaseLine"
	WHERE T0."FcCode"=:FcCode
	AND T0."WorType"<>'40'
	AND (IFNULL(T0."IgeQty",0)-IFNULL(T1."IgeQty",0)<>0 OR IFNULL(T0."Amount",0)-IFNULL(T1."IgeAmt",0)<>0)
	;
		
END;