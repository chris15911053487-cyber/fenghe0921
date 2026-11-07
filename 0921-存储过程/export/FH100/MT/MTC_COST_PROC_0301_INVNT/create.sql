CREATE PROCEDURE "MTC_COST_PROC_0301_INVNT"(IN BPLId INT,IN FcCode NVARCHAR(10),IN UserCode NVARCHAR(50))
LANGUAGE SQLSCRIPT
AS
BEGIN
	
	DECLARE LastFcCode NVARCHAR(30);	--上期
	SELECT "Code" INTO LastFcCode
	FROM "OFPR" WHERE "Code" IN (SELECT MAX("Code") AS "Code" FROM "OFPR" WHERE "Code"<:FcCode);
	
	/* created by chri.li 2024.11.23
     * 仅入库数据明细到静态表 MTC_COST_0302_INVNTDETAIL1
     * CALL "MTC_COST_PROC_0301_INVNT"(0,'2024-01','manager');
    */
	
  	IF EXISTS(SELECT 1 FROM "OFPR" WHERE "PeriodStat"='Y' AND "Code"=:FcCode) THEN
  		SELECT -1 AS "Code",'账期已锁定，无法计算成本' AS "Msg" FROM DUMMY;
  		RETURN;
  	END IF;
	
	DELETE FROM MTC_COST_0301_INVNT WHERE "FcCode" = :FcCode;
	
	--写入期初数据（开账期初数据，初始化时使用）
	INSERT INTO MTC_COST_0301_INVNT(
	 "BPLId"
	 ,"FcCode"
	 ,"CalType"
	 ,"CostCode"
	 ,"ItemCode"
	 ,"ItemName"
	 ,"ItmsGrpCod"
	 ,"iLevel"
	 ,"QM_Qty"
	 ,"QM_Price"
	 ,"QM_Amount"
	,"CreateDate"		--创建时间
	,"Creator")
	SELECT :BPLId
	,:FcCode
	,T."U_ItemProp"
	,T1."CostTypeCode" AS "CostCode"
	,T."ItemCode"
	,T."ItemName"
	,T."ItmsGrpCod"
	,P1."iLevel"
	,IFNULL(P0."QC_Qty",0)		AS "QC_Qty"
	,IFNULL(P0."QC_Price",0)		AS "QC_Price"
	,IFNULL(P0."QC_Amount",0)		AS "QC_Amount"
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM OITM T
	LEFT JOIN MTC_COST_0101_COSTTYPE T1 ON 1=1
	LEFT JOIN (SELECT * FROM MTC_COST_INVNT_QC WHERE "FcCode"=:FcCode
			) P0 ON T."ItemCode"=P0."ItemCode"
	LEFT JOIN U_COILV P1 ON T."ItemCode"=P1."ItemCode"
	WHERE 1=1 AND P1."FcCode"='2024-11'
	AND P1."FcCode"=:FcCode
	;
	
	--写入期初数据(正常期间的)
	INSERT INTO MTC_COST_0301_INVNT(
	 "BPLId"
	 ,"FcCode"
	 ,"CalType"
	 ,"CostCode"
	 ,"ItemCode"
	 ,"ItemName"
	 ,"ItmsGrpCod"
	 ,"iLevel"
	 ,"QC_Qty"
	 ,"QC_Price"
	 ,"QC_Amount"
	,"CreateDate"		--创建时间
	,"Creator")
	SELECT 0 AS "BPLId"
	,T0."FcCode"
	,P0."CalType"
	,T1."CostTypeCode" AS "CostCode"
	,T0."ItemCode"
	,T0."ItemName"
	,T2."ItmsGrpCod"
	,T0."iLevel"
	,IFNULL(P0."QM_Qty",0)		AS "QC_Qty"
	,IFNULL(P0."QM_Price",0)		AS "QC_Price"
	,IFNULL(P0."QM_Amount",0)		AS "QC_Amount"
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM U_COILV T0
	LEFT JOIN MTC_COST_0101_COSTTYPE T1 ON 1=1
	LEFT JOIN (SELECT * FROM MTC_COST_0301_INVNT WHERE "FcCode"=:LastFcCode
			) P0 ON T0."ItemCode"=P0."ItemCode" AND T1."CostTypeCode"=P0."CostCode"
	JOIN OITM T2 ON T0."ItemCode"=T2."ItemCode"
	WHERE 1=1
	AND T0."FcCode"=:FcCode
	AND T0."FcCode">='2024-12'
	;
	
	UPDATE T0 SET T0."QC_Qty"=T1."OIVLQty"
	FROM "MTC_COST_0301_INVNT" T0
	LEFT JOIN (SELECT "ItemCode",SUM("InQty"-"OutQty") AS "OIVLQty"
				FROM "OIVL" WHERE "DocDate"<='2025-03-31'
				GROUP BY "ItemCode"
			) T1 ON T0."ItemCode"=T1."ItemCode"
	WHERE 1=1
	AND T0."FcCode"=:FcCode
	AND T0."FcCode"='2025-04'
	AND T0."ItemCode" IN
	('072000285-B3',
	'012000633',
	'072000284-B3',
	'031100175',
	'070600046',
	'070600048',
	'070600051',
	'091300008',
	'031100144',
	'071100018',
	'141300006',
	'012000098',
	'132000095',
	'012000632',
	'012000634',
	'012000631',
	'082000043',
	'012000093',
	'131300005',
	'042000032',
	'011100388',
	'012000697',
	'012000698',
	'102000794',
	'012000097');
	
	UPDATE MTC_COST_0301_INVNT SET "QC_Qty"=8,"QC_Price"=ROUND("QC_Amount"/8,6) WHERE "FcCode"=:FcCode AND "FcCode"='2025-04' AND "ItemCode"='071100055';
	UPDATE MTC_COST_0301_INVNT SET "QC_Qty"=88,"QC_Price"=ROUND("QC_Amount"/8,6) WHERE "FcCode"=:FcCode AND "FcCode"='2025-04' AND "ItemCode"='071100054';
	
	
	
	SELECT 0 AS "代码",'建立库存结构'||:FcCode||',成功！' AS "信息" FROM DUMMY;

END