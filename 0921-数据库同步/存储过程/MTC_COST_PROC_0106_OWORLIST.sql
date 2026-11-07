CREATE PROCEDURE "MTC_COST_PROC_0106_OWORLIST"(IN BPLId INT,IN FcCode NVARCHAR(10),IN UserCode NVARCHAR(50))
LANGUAGE SQLSCRIPT
AS
BEGIN
	
	/* created by chri.li 2024.11.23
     * 抽取物料等级 到 明细到静态表 MTC_COST_0105_ITEM
     * CALL "MTC_COST_PROC_0321_OWOR"(0,'2024-01','manager');
    */

	
  	IF EXISTS(SELECT 1 FROM "OFPR" WHERE "PeriodStat"='Y' AND "Code"=:FcCode) THEN
  		SELECT -1 AS "Code",'账期已锁定，无法计算成本' AS "Msg" FROM DUMMY;
  		RETURN;
  	END IF;
	
	DELETE FROM MTC_COST_0106_OWORLIST WHERE "FcCode" = :FcCode;
	DELETE FROM MTC_COST_0106_OWORLIST1 WHERE "FcCode" = :FcCode;
	
	INSERT INTO MTC_COST_0106_OWORLIST(
	 "BPLId"
	,"FcCode"
	,"DocType"
	,"WorType"
	,"WorEntry"
	,"WorNum"
	,"ItemCode"
	,"ItemName"
	,"ItmsGrpCod"
	,"iLevel"
	,"Quantity"
	,"CreateDate"		--创建时间
	,"Creator")
	SELECT :BPLId AS "BPLId"
	,:FcCode AS "FcCode"
	,'202' AS "DocType"
	,P0."U_OrdType" AS "WorType"
	,P0."DocEntry" AS "WorEntry"
	,P0."DocNum" AS "WorNum"
	,P0."ItemCode"
	,P1."ItemName"
	,P1."ItmsGrpCod"
	,P2."iLevel"
	,P0."PlannedQty" AS "Quantity"
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM "OWOR" P0
	LEFT JOIN OITM P1 ON P0."ItemCode"=P1."ItemCode"
	LEFT JOIN U_COILV P2 ON P2."FcCode"=:FcCode AND P0."ItemCode"=P2."ItemCode"
	WHERE 1=1 AND P0."Status"<>'C'
	;
	
	INSERT INTO MTC_COST_0106_OWORLIST1(
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
	,"iLevel"
	,"Quantity"
	,"CreateDate"
	,"Creator")
	SELECT :BPLId AS "BPLId"
	,:FcCode AS "FcCode"
	,'202' AS "DocType"
	,P0."U_OrdType" AS "WorType"
	,P0."DocEntry" AS "WorEntry"
	,P0."DocNum" AS "WorNum"
	,P3."LineNum"
	,P3."ItemCode"
	,P1."ItemName"
	,P1."ItmsGrpCod"
	,P2."iLevel"
	,P3."PlannedQty"    --领料数量
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM OWOR P0
	JOIN WOR1 P3 ON P0."DocEntry"=P3."DocEntry"
	LEFT JOIN OITM P1 ON P3."ItemCode"=P1."ItemCode"
	LEFT JOIN U_COILV P2 ON P2."FcCode"=:FcCode AND P3."ItemCode"=P2."ItemCode"
	;
	
	
	INSERT INTO MTC_COST_0106_OWORLIST(
	 "BPLId"
	,"FcCode"
	,"DocType"
	,"WorType"
	,"WorEntry"
	,"WorNum"
	,"ItemCode"
	,"ItemName"
	,"ItmsGrpCod"
	,"iLevel"
	,"Quantity"
	,"CreateDate"		--创建时间
	,"Creator")
	SELECT :BPLId AS "BPLId"
	,:FcCode AS "FcCode"
	,P0."Object" AS "DocType"
	,P0."U_OrdType" AS "WorType"
	,P0."DocEntry" AS "WorEntry"
	,P0."DocNum" AS "WorNum"
	,P1."ItemCode"
	,P1."ItemName"
	,P1."ItmsGrpCod"
	,P2."iLevel"
	,P0."U_PlannedQty" AS "Quantity"
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM "@MTC_OWOR" P0
	LEFT JOIN OITM P1 ON P0."U_ItemCode"=P1."ItemCode"
	LEFT JOIN U_COILV P2 ON P2."FcCode"=:FcCode AND P0."U_ItemCode"=P2."ItemCode"
	WHERE 1=1 AND P0."U_Status"<>'C'
	;
	
	INSERT INTO MTC_COST_0106_OWORLIST1(
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
	,"iLevel"
	,"Quantity"
	,"CreateDate"
	,"Creator")
	SELECT :BPLId AS "BPLId"
	,:FcCode AS "FcCode"
	,P0."Object" AS "DocType"
	,P0."U_OrdType" AS "WorType"
	,P0."DocEntry" AS "WorEntry"
	,P0."DocNum" AS "WorNum"
	,P3."LineId"
	,P1."ItemCode"
	,P1."ItemName"
	,P1."ItmsGrpCod"
	,P2."iLevel"
	,P3."U_PlannedQty"    --领料数量
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM "@MTC_OWOR" P0
	JOIN "@MTC_WOR1" P3 ON P0."DocEntry"=P3."DocEntry"
	LEFT JOIN OITM P1 ON P3."U_ItemCode"=P1."ItemCode"
	LEFT JOIN U_COILV P2 ON P2."FcCode"=:FcCode AND P3."U_ItemCode"=P2."ItemCode"
	;
	
	SELECT 0 AS "代码",'获取生产订单结构'||:FcCode||',成功！' AS "信息" FROM DUMMY;

END