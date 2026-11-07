CREATE PROCEDURE "MTC_COST_PROC_0306_WW"(IN BPLId INT,IN FcCode NVARCHAR(10),IN UserCode NVARCHAR(50))
LANGUAGE SQLSCRIPT
AS
BEGIN
	
	/* created by chri.li 2024.11.23
     * 费用归集表 MTC_COST_0312_PRODUCTEXP_PRC
     * CALL "MTC_COST_PROC_0312_PRODUCTEXP_PRC"(0,'2024-01','manager');
    */
    --w委外

    
  	IF EXISTS(SELECT 1 FROM "OFPR" WHERE "PeriodStat"='Y' AND "Code"=:FcCode) THEN
  		SELECT -1 AS "Code",'账期已锁定，无法计算成本' AS "Msg" FROM DUMMY;
  		RETURN;
  	END IF;

    DELETE FROM MTC_COST_0321_OWOR2 WHERE "FcCode"=:FcCode AND "CostCode"='20';
    
	INSERT INTO MTC_COST_0321_OWOR2("BPLId"
	,"FcCode"
	,"DocType"
	,"WorType"
	,"WorEntry"
	,"WorNum"
	,"CostCode"	--制造费用/人工费用
	,"ExpType"  --费用类型
	,"IgeQty"  
	,"Amount"
	,"CreateDate"   --创建时间
	,"Creator"
	)
	SELECT :BPLId AS "BPLId"
	,:FcCode AS "FcCode"
	,T0."DocType"
	,T0."WorType"
	,T0."WorEntry"
	,T0."WorNum"
	,'20' AS "CostCode"
	,'委外费用' AS "ExpType"
	,-1*"Detail_Qty" AS "IgeQty"
	,-1*ROUND(T1."Detail_Amt",2) AS "ExpAmt"
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM MTC_COST_0321_OWOR T0
	JOIN (
			SELECT "OWOREntry"
  			,SUM(-1*"Quantity") AS "Detail_Qty"
  			,SUM(-1*ROUND("Amt",2)) AS "Detail_Amt"
  			FROM "MTC_VIEW_ProductDetail" T0
  			WHERE "Type" = '子件' AND LEFT(T0."DocDate",7)=:FcCode
  			AND "ID" IN (3,4)
  			GROUP BY "OWOREntry"
			) T1 ON T0."WorEntry"=T1."OWOREntry"
	WHERE 1=1
	AND T0."DocType"='202'
	AND T0."FcCode"=:FcCode
	;
	
	INSERT INTO MTC_COST_0321_OWOR2("BPLId"
	,"FcCode"
	,"DocType"
	,"WorType"
	,"WorEntry"
	,"WorNum"
	,"CostCode"	--制造费用/人工费用
	,"ExpType"  --费用类型
	,"IgeQty"  
	,"Amount"
	,"CreateDate"   --创建时间
	,"Creator"
	)
	SELECT :BPLId AS "BPLId"
	,:FcCode AS "FcCode"
	,T."DocType"
	,T."WorType"
	,T."WorEntry"
	,T."WorNum"
	,'20' AS "CostCode"
	,'委外费用' AS "ExpType"
	,IFNULL(T1."U_Quantity",0) AS "IgeQty"	--订单数量
	,ROUND(-1*T1."U_Amount",2) AS "ExpAmt"
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM "@MTC_OMRV" T0
	JOIN "@MTC_OMRV1" T1 ON T0."DocEntry"=T1."DocEntry"
	LEFT JOIN OITM P1 ON T1."U_ItemCode"=P1."ItemCode"
	LEFT JOIN OITB P2 ON P1."ItmsGrpCod"=P2."ItmsGrpCod"
	LEFT JOIN U_COILV P3 ON P3."FcCode"=:FcCode AND T1."U_ItemCode"=P3."ItemCode"
	JOIN MTC_COST_0101_COSTTYPE P5 ON P5."CostTypeCode"='20'	--材料
	JOIN (SELECT ROW_NUMBER() OVER (PARTITION BY "DocType","WorEntry" ORDER BY "FcCode" DESC) AS "ID"
				,"DocType","WorType","WorEntry","WorNum"
				FROM MTC_COST_0321_OWOR
			   WHERE "FcCode"<=:FcCode
		) T ON T1."U_BaseType"=T."DocType" AND T1."U_BaseEntry"=T."WorEntry" AND T."ID"=1
	WHERE 1=1
	AND T0."Canceled"='N'
	AND T0."U_BaseType"='ProWW'
	AND LEFT(T0."U_DocDate",7)=:FcCode;
	
	
	UPDATE T0 SET T0."4WWExp"=IFNULL(T1."Amount",0),T0."Amount"=IFNULL(T0."1Material",0)+IFNULL(T1."Amount",0)
	FROM MTC_COST_0321_OWOR T0
	JOIN (SELECT MAX("FcCode") AS "FcCode","DocType","WorEntry",-1*SUM(ROUND("Amount",2)) AS "Amount"
		FROM MTC_COST_0321_OWOR2 WHERE "CostCode"='20' GROUP BY "DocType","WorEntry"
		) T1 ON T0."FcCode"=T1."FcCode" AND T0."WorEntry"=T1."WorEntry" AND T0."DocType"=T1."DocType"
	WHERE 1=1
	AND T0."FcCode"=:FcCode;
	
	SELECT '委外费用计算成功' FROM DUMMY;
	

END