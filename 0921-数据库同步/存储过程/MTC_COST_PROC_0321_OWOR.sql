CREATE PROCEDURE "MTC_COST_PROC_0321_OWOR"(IN BPLId INT,IN FcCode NVARCHAR(10),IN UserCode NVARCHAR(50))
LANGUAGE SQLSCRIPT
AS
BEGIN
	
	/* created by chri.li 2024.11.23
     * 抽取物料等级 到 明细到静态表 MTC_COST_0105_ITEM
     * CALL "MTC_COST_PROC_0321_OWOR"(0,'2024-01','manager');
    */
	DECLARE LastFcCode NVARCHAR(30);	--上期
	SELECT "Code" INTO LastFcCode
	FROM "OFPR" WHERE "Code" IN (SELECT MAX("Code") AS "Code" FROM "OFPR" WHERE "Code"<:FcCode);
	
	
  	IF EXISTS(SELECT 1 FROM "OFPR" WHERE "PeriodStat"='Y' AND "Code"=:FcCode) THEN
  		SELECT -1 AS "Code",'账期已锁定，无法计算成本' AS "Msg" FROM DUMMY;
  		RETURN;
  	END IF;
  	
	DELETE FROM MTC_COST_0321_OWOR WHERE "FcCode" = :FcCode;
	DELETE FROM MTC_COST_0321_OWOR1 WHERE "FcCode" = :FcCode;
	
	--1.1OWOR
	INSERT INTO MTC_COST_0321_OWOR(
	 "BPLId"
	,"FcCode"
	,"DocType"
	,"WorType"
	,"WorEntry"
	,"WorNum"
	,"ItemCode"
	,"ItemName"
	,"ItmsGrpCod"
	,"WorQty"
	,"Quantity"
	,"StdPrice"
	,"StdAmount"
	,"IgnQty"		--完工入库数量
	,"Amount"
	,"1Material"
	,"2ManExp"
	,"3LabAmount"
	--,"5ClosedAmt"
	,"CostMemo"
	,"iLevel"
	,"Memo"
	,"CreateDate"		--创建时间
	,"Creator")
	SELECT :BPLId AS "BPLId"
	,:FcCode AS "FcCode"
	,'202' AS "DocType"
	,P."U_OrdType" AS "WorType"
	,P."DocEntry" AS "WorEntry"
	,P."DocNum" AS "WorNum"
	,P1."ItemCode"
	,P1."ItemName"
	,P1."ItmsGrpCod"
	,P."PlannedQty" AS "WorQty"
	,P."PlannedQty" AS "Quantity"
	,0 AS "StdPrice"
	,0 AS "StdAmount"
	,IFNULL(P0."IgnQty",0)    --完工入库数量
	,0 AS "Amount"
	,0 AS "1Material"
	,0 AS "2ManExp"
	,0 AS "3LabAmount"
	--,IFNULL(P3."关单差异",0) AS "5ClosedAmt"
	,'' AS "CostMemo"
	,P2."iLevel"
	,'' AS "Memo"
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM "OWOR" P
	LEFT JOIN
	(
			SELECT T1."U_OrdType" AS "WorType",T1."DocEntry" AS "WorEntry",T1."DocNum" AS "WorNum"
			,T1."ItemCode",T1."PlannedQty" AS "Quantity",SUM(T0."Quantity") AS "IgnQty"
			FROM "MTC_COST_0201_DOCDETAL" T0
			JOIN "OWOR" T1 ON T0."BaseType"='202' AND T0."BaseEntry"=T1."DocEntry" AND T0."BaseLine" IS NULL
			LEFT JOIN "@U_CIOTRN" T2 ON T0."TransCode"=T2."Code"
			JOIN OWHS T9 ON T0."WhsCode"=T9."WhsCode"
			WHERE 1=1
			AND T9."U_IsCost"='Y'
			AND T2."U_TransType" IN ('B01')		--B01工单产出类
			AND T0."FcCode"=:FcCode
			GROUP BY T1."U_OrdType",T1."DocEntry",T1."DocNum",T1."ItemCode",T1."PlannedQty"
		) P0 ON P."DocEntry"=P0."WorEntry"
	--LEFT JOIN (SELECT * FROM MTC_COST_0322_OWOR_ZCP
	--			WHERE "期间"=:LastFcCode AND "DocType"='202'
	--	) P3 ON P."DocEntry"=P3."WorEntry"
	LEFT JOIN OITM P1 ON P."ItemCode"=P1."ItemCode"
	LEFT JOIN U_COILV P2 ON P2."FcCode"=:FcCode AND P."ItemCode"=P2."ItemCode"
	WHERE P."Status"<>'C'
	;
	
	--1.2OWOR
	INSERT INTO MTC_COST_0321_OWOR1(
	"BPLId"
	,"FcCode"
	,"DocType"
	,"WorType"
	,"WorEntry"
	,"WorNum"
	,"LineNum"
	,"ItemCode"
	,"ItemName"
	,"ItmsGrpCod"
	,"IgeQty"
	,"Price"	
	,"Amount"
	,"CreateDate"
	,"Creator")
	SELECT :BPLId AS "BPLId"
	,:FcCode AS "FcCode"
	,'202' AS "ObjType"
	,P0."WorType"
	,P0."WorEntry"
	,P0."WorNum"
	,P0."LineNum"
	,P0."ItemCode"
	,P1."ItemName"
	,P1."ItmsGrpCod"
	,P0."IgeQty"    --完工入库数量
	,0 AS "Price"
	,0 AS "Amount"
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM (
			SELECT T1."U_OrdType" AS "WorType",T1."DocEntry" AS "WorEntry",T1."DocNum" AS "WorNum"
			,T0."ItemCode",T0."BaseLine" AS "LineNum",SUM(T0."Quantity") AS "IgeQty"
			FROM "MTC_COST_0201_DOCDETAL" T0
			JOIN "OWOR" T1 ON T0."BaseType"='202' AND T0."BaseEntry"=T1."DocEntry" AND T0."BaseLine" IS NOT NULL
			LEFT JOIN "@U_CIOTRN" T2 ON T0."TransCode"=T2."Code"
			JOIN OWHS T9 ON T0."WhsCode"=T9."WhsCode"
			WHERE 1=1
			AND T9."U_IsCost"='Y'
			AND T2."U_TransType" IN ('B03')		--B01工单投入类
			AND T0."FcCode"=:FcCode
			GROUP BY T1."U_OrdType",T1."DocEntry",T1."DocNum",T0."ItemCode",T0."BaseLine"
		) P0
	LEFT JOIN OITM P1 ON P0."ItemCode"=P1."ItemCode"
	;
	
	--2.1"@MTC_OWOR" 返工工单
	INSERT INTO MTC_COST_0321_OWOR(
	 "BPLId"
	,"FcCode"
	,"DocType"
	,"WorType"
	,"WorEntry"
	,"WorNum"
	,"ItemCode"
	,"ItemName"
	,"ItmsGrpCod"
	,"WorQty"
	,"Quantity"
	,"StdPrice"
	,"StdAmount"
	,"IgnQty"		--完工入库数量
	,"Amount"
	,"1Material"
	,"2ManExp"
	,"3LabAmount"
	--,"5ClosedAmt"
	,"CostMemo"
	,"iLevel"
	,"Memo"
	,"CreateDate"		--创建时间
	,"Creator")
	SELECT :BPLId AS "BPLId"
	,:FcCode AS "FcCode"
	,P."Object" AS "DocType"
	,P."U_OrdType" AS "WorType"
	,P."DocEntry" AS "WorEntry"
	,P."DocNum" AS "WorNum"
	,P1."ItemCode"
	,P1."ItemName"
	,P1."ItmsGrpCod"
	,P."U_PlannedQty" AS "WorQty"
	,P."U_PlannedQty" AS "Quantity"
	,0 AS "StdPrice"
	,0 AS "StdAmount"
	,IFNULL(P0."IgnQty",0)    --完工入库数量
	,0 AS "Amount"
	,0 AS "1Material"
	,0 AS "2ManExp"
	,0 AS "3LabAmount"
	--,IFNULL(P3."关单差异",0) AS "5ClosedAmt"
	,'' AS "CostMemo"
	,P2."iLevel"
	,'' AS "Memo"
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM "@MTC_OWOR" P
	LEFT JOIN
	(
			SELECT T1."U_OrdType" AS "WorType",T1."DocEntry" AS "WorEntry",T1."DocNum" AS "WorNum"
			,T1."U_ItemCode" AS "ItemCode",T1."U_PlannedQty" AS "Quantity",SUM(T0."Quantity") AS "IgnQty"
			FROM "MTC_COST_0201_DOCDETAL" T0
			JOIN "@MTC_OWOR" T1 ON T0."BaseType"=T1."Object" AND T0."BaseEntry"=T1."DocEntry" AND T0."BaseLine" IS NULL
			LEFT JOIN "@U_CIOTRN" T2 ON T0."TransCode"=T2."Code"
			JOIN OWHS T9 ON T0."WhsCode"=T9."WhsCode"
			WHERE 1=1
			AND T9."U_IsCost"='Y'
			AND T2."U_TransType" IN ('B01')		--B01工单产出类
			AND T0."FcCode"=:FcCode
			GROUP BY T1."U_OrdType",T1."DocEntry",T1."DocNum",T1."U_ItemCode",T1."U_PlannedQty"
		) P0 ON P."DocEntry"=P0."WorEntry"
	--LEFT JOIN (SELECT * FROM MTC_COST_0322_OWOR_ZCP
	--			WHERE "期间"=:LastFcCode AND "DocType"='MTC_OWOR'
	--	) P3 ON P."DocEntry"=P3."WorEntry"
	LEFT JOIN OITM P1 ON P."U_ItemCode"=P1."ItemCode"
	LEFT JOIN U_COILV P2 ON P2."FcCode"=:FcCode AND P."U_ItemCode"=P2."ItemCode"
	WHERE P."U_Status"<>'C'
	;

	--2.2 "@MTC_OWOR"返工工单
	INSERT INTO MTC_COST_0321_OWOR1(
	"BPLId"
	,"FcCode"
	,"DocType"
	,"WorType"
	,"WorEntry"
	,"WorNum"
	,"LineNum"
	,"ItemCode"
	,"ItemName"
	,"ItmsGrpCod"
	,"IgeQty"
	,"Price"	
	,"Amount"
	,"CreateDate"
	,"Creator")
	SELECT :BPLId AS "BPLId"
	,:FcCode AS "FcCode"
	,P0."ObjType"
	,P0."WorType"
	,P0."WorEntry"
	,P0."WorNum"
	,P0."LineNum"
	,P0."ItemCode"
	,P1."ItemName"
	,P1."ItmsGrpCod"
	,P0."IgeQty"    --完工入库数量
	,0 AS "Price"
	,0 AS "Amount"
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM (
			SELECT T1."Object" AS "ObjType",T1."U_OrdType" AS "WorType",T1."DocEntry" AS "WorEntry",T1."DocNum" AS "WorNum"
			,T0."ItemCode",T0."BaseLine" AS "LineNum",SUM(T0."Quantity") AS "IgeQty"
			FROM "MTC_COST_0201_DOCDETAL" T0
			JOIN "@MTC_OWOR" T1 ON T0."BaseType"=T1."Object" AND T0."BaseEntry"=T1."DocEntry" AND T0."BaseLine" IS NOT NULL
			LEFT JOIN "@U_CIOTRN" T2 ON T0."TransCode"=T2."Code"
			JOIN OWHS T9 ON T0."WhsCode"=T9."WhsCode"
			WHERE 1=1
			AND T9."U_IsCost"='Y'
			AND T2."U_TransType" IN ('B03')		--B01工单投入类
			AND T0."FcCode"=:FcCode
			GROUP BY T1."Object",T1."U_OrdType",T1."DocEntry",T1."DocNum",T0."ItemCode",T0."BaseLine"
		) P0
	LEFT JOIN OITM P1 ON P0."ItemCode"=P1."ItemCode"
	;
	
	SELECT '成功' FROM DUMMY;
END