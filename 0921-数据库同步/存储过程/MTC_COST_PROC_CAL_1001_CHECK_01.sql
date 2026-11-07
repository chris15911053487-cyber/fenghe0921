CREATE PROCEDURE "MTC_COST_PROC_CAL_1001_CHECK_01"(
 IN DocEntry INT
)
LANGUAGE SQLSCRIPT
AS
BEGIN
	
	DECLARE FcCode NVARCHAR(30);
	DECLARE LastFcCode NVARCHAR(30);
	SELECT "U_FcCode" INTO FcCode FROM "@MTC_COST_QCPRICE" WHERE "DocEntry"=:DocEntry;
	SELECT MAX("Code") INTO LastFcCode FROM OFPR WHERE "Code"<:FcCode;
	
	
  	IF EXISTS(SELECT 1 FROM "OFPR" WHERE "PeriodStat"='Y' AND "Code"=:FcCode) THEN
  		SELECT -1 AS "Code",'账期已锁定，无法计算成本' AS "Msg" FROM DUMMY;
  		RETURN;
  	END IF;
	
	--更新期初单价，把入库单价更新进入
	--上期库存+本期入库
	Onhand_SUM=
	SELECT "ItemCode",SUM("Amount") AS "Amount",SUM("Qty") AS "Qty",SUM("Amount")/NULLIF(SUM("Qty"),0) AS "Price"
	FROM (
			SELECT "ItemCode","QM_Amount" AS "Amount","QM_Qty" AS "Qty" FROM MTC_COST_0301_INVNT T0
			WHERE T0."FcCode"=:LastFcCode AND "CostCode"='20'
			--当期入库
			UNION ALL
			SELECT "ItemCode","Amount","Quantity" FROM MTC_COST_0302_INVNTDETAIL1
			WHERE 1=1
			--AND "ObjType" IN ('20','21','18','19') 
			AND "ObjType" IN ('20','59') 
			AND "FcCode"=:FcCode
		) T0
	--WHERE T0."ItemCode"='102002076'
	GROUP BY "ItemCode"	
	;
	
	TMP=
	SELECT T2."DocEntry" AS "单号",T2."U_ItemCode" AS "物料编码",T2."U_ItemName" AS "物料名称"
	,T2."U_Price" AS "更改前单价"
	,T1."Price" AS "更改后单价"
	FROM :Onhand_SUM T1
	JOIN "@MTC_COST_QCPRICE1" T2 ON T1."ItemCode"=T2."U_ItemCode"
	WHERE T2."DocEntry"=:DocEntry
	and IFNULL(T2."U_Price",0)=0
	AND IFNULL(T1."Price",0)<>0
	;
	
	
	UPDATE T2 SET T2."U_Price"=T1."Price"
	,T2."U_LineMemo"='关联入库单价更新，原单价为'||T2."U_Price"
	FROM :Onhand_SUM T1
	JOIN "@MTC_COST_QCPRICE1" T2 ON T1."ItemCode"=T2."U_ItemCode"
	WHERE T2."DocEntry"=:DocEntry
	and IFNULL(T2."U_Price",0)=0
	AND IFNULL(T1."Price",0)<>0
	;
	
	
	SELECT '更改成功!' AS "Message",* FROM :TMP T0
	ORDER BY T0."物料编码";
	
	
	/*
	--还需要对出入库处理
	--TMP_SUM=
	SELECT T0."ItemCode",SUM("Quantity") AS "Quantity",T1."Price"
	,LEFT(STRING_AGG(T2."Name",','),250) AS "IOName"
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	LEFT JOIN :Onhand_SUM T1 ON T0."ItemCode"=T1."ItemCode"
	LEFT JOIN "@MTC_COST_IOTYPE" T2 ON T0."TransCode"=T2."Code"
	WHERE T0."TransCode" IN ('I03','I04','O04','I05','O06','I10','I07','I08')
	AND T0."FcCode"='2025-10'
	AND T0."ItemCode"='102002076'
	--AND T0."Quantity">0 --入库
	GROUP BY T0."ItemCode",T1."Price";*/
END