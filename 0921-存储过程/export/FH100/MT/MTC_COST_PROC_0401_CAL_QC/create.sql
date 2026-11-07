CREATE PROCEDURE "MTC_COST_PROC_0401_CAL_QC"(IN BPLId INT,IN FcCode NVARCHAR(10),IN UserCode NVARCHAR(50))
LANGUAGE SQLSCRIPT
AS
BEGIN
	
	/* created by chri.li 2024.11.23
     * 抽取物料等级 到 明细到静态表 MTC_COST_0105_ITEM
     * CALL "MTC_COST_PROC_0401_CAL"(0,'2024-01','manager');
    */
    
    DECLARE CNT INT = 0;
    DECLARE ILEVEL INT = 1;
    DECLARE MAXLEVEL INT = 0;
    
    
	UPDATE T1 SET T1."Price"=T2."Price",T1."Amount"=T1."IgeQty"*T2."Price"
	FROM "MTC_COST_0321_OWOR1" T1
	JOIN (SELECT "U_Text1" AS "ItemCode",ROUND("U_Dec2"/NULLIF("U_Dec1",0),6) AS "Price"
			FROM "@MTC_IMPT1" WHERE "DocEntry"=1
		) T2 ON T1."ItemCode"=T2."ItemCode"
	WHERE T1."FcCode"='2024-11';
	
	--写入期初委外价格错误的
	INSERT INTO MTC_COST_0321_OWOR2("BPLId"
	,"FcCode"
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
	,T0."WorType"
	,T0."WorEntry"
	,T0."WorNum"
	,'20' AS "CostCode"
	,'委外费用' AS "ExpType"
	,-1*T0."IgnQty" AS "IgeQty"
	,-1*T0."IgnQty"*T3."U_Dec1" AS "ExpAmt"
	,CURRENT_TIMESTAMP
	,'9999'	--特殊标识
	FROM MTC_COST_0321_OWOR T0
	LEFT JOIN (SELECT * FROm MTC_COST_0321_OWOR2 WHERE "FcCode"='2024-11') T1 ON T0."WorEntry"=T1."WorEntry" 
	JOIN OWOR T2 ON T0."WorNum"=T2."DocNum"
	LEFT JOIN (SELECT * FROM "@MTC_IMPT1" WHERE "DocEntry"=4) T3 ON T3."U_Text3"=T0."ItemCode" AND T3."U_Text2"=TO_ChAR(T2."DocEntry")
	WHERE 1=1
	AND T1."WorEntry" IS NULL
	AND T0."FcCode"='2024-11'
	;
	
	--委外(对期初的委外工单对应的材料进行更新价格)
	UPDATE T1 SET T1."Price"=T2."Price",T1."Amount"=T1."IgeQty"*T2."Price"
	FROM "MTC_COST_0321_OWOR1" T1
	JOIN OWOR T0 ON T1."WorEntry"=T0."DocEntry"
	JOIN (SELECT "U_Text1" AS "CardCode","U_Text4" AS "ItemCode"
			,ROUND("U_Dec2"/NULLIF("U_Dec1",0),6) AS "Price"
			FROM "@MTC_IMPT1" WHERE "DocEntry"=3
		) T2 ON T1."ItemCode"=T2."ItemCode" AND T0."U_CardCode"=T2."CardCode"
	WHERE T1."FcCode"='2024-11'
	AND T1."WorType"='50'
	--AND T1."ItemCode"='142000081'
	; 
    
    UPDATE T0 SET T0."Amount"=(IFNULL(T1."Amount",0)+IFNULL(T3."Amount",0))
	,T0."1Material"=T1."Amount"
	,T0."2ManExp"=T3."2ManExp"
	,T0."3LabAmount"=T3."3LabAmount"
	,T0."4WWExp"=T3."4ExpAmt"
	FROM MTC_COST_0321_OWOR T0
	--材料费用
	LEFT JOIN (
			SELECT T1."BPLId",'2024-11' AS "FcCode",T1."WorEntry",SUM(T1."IgeQty") AS "IgeQty"
			,-1*SUM(T1."Amount") AS "Amount"
			--,SUM(T1."Amount"/NULLIF(T1."IgeQty",0)*T0."IgnQty") AS "Amount"
			FROM MTC_COST_0321_OWOR1 T1
			JOIN MTC_COST_0321_OWOR T0 ON  T1."WorEntry"=T0."WorEntry" AND T0."FcCode"=T1."FcCode"
			WHERE T1."FcCode"='2024-11' GROUP BY T1."BPLId",T1."WorEntry"
		) T1 ON T0."BPLId"=T1."BPLId" AND T0."FcCode"=T1."FcCode" AND T0."WorEntry"=T1."WorEntry"
	--制造费用+人工费用+委外费用
	LEFT JOIN (
			SELECT T2."BPLId",'2024-11' AS "FcCode",T2."WorEntry"
			,-1*SUM(T2."Amount") AS "Amount"
			,-1*SUM(CASE WHEN T2."CostCode"='20' THEN T2."Amount" ELSE 0 END) AS "4ExpAmt" --20委外
			,-1*SUM(CASE WHEN T2."CostCode"='30' THEN T2."Amount" ELSE 0 END) AS "3LabAmount"	--30制造费用
			,-1*SUM(CASE WHEN T2."CostCode"='40' THEN T2."Amount" ELSE 0 END) AS "2ManExp"	--40人工费用
			--,SUM(T2."Amount"/NULLIF(T2."IgeQty",0)*T0."IgnQty") AS "Amount"
			FROM MTC_COST_0321_OWOR2 T2
			JOIN MTC_COST_0321_OWOR T0 ON T2."FcCode"=T0."FcCode" AND T2."WorEntry"=T0."WorEntry"
			WHERE T2."FcCode"='2024-11' GROUP BY T2."BPLId",T2."WorEntry"
		) T3 ON T0."BPLId"=T3."BPLId" AND T0."FcCode"=T3."FcCode" AND T0."WorEntry"=T3."WorEntry"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
	WHERE 1=1
	AND T0."FcCode"='2024-11';
    
    
	SELECT '写入物料成本计算等级成功！' FROM DUMMY;

END