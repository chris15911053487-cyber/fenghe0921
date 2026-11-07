CREATE PROCEDURE "MTC_COST_PROC_0201_DOCDETAIL"(IN BPLId INT,IN FcCode NVARCHAR(10),IN UserCode NVARCHAR(50))
LANGUAGE SQLSCRIPT
AS
BEGIN
	
	/* created by chri.li 2024.11.23
     * 抽取出入库明细到静态表 MTC_COST_0201_DOCDETAL
     * CALL "MTC_COST_PROC_20_DOCDETAIL"(0,'2024-01','manager');
    */
	
  	IF EXISTS(SELECT 1 FROM "OFPR" WHERE "PeriodStat"='Y' AND "Code"=:FcCode) THEN
  		SELECT -1 AS "Code",'账期已锁定，无法计算成本' AS "Msg" FROM DUMMY;
  		RETURN;
  	END IF;
  	
	DELETE FROM MTC_COST_0201_DOCDETAL WHERE "FcCode" = :FcCode;
	
	UPDATE PCH1 SET "BaseRef"=NULL WHERE "BaseRef"='';
	
	INSERT INTO MTC_COST_0201_DOCDETAL("BPLId"
	,"ObjType"
	,"DocEntry"
	,"DocNum"
	,"CardCode"
	,"CardName"
	,"LineNum"
	,"FcCode"
	,"DocDate"
	,"CostCode"		--归入成本计价类型
	,"TransCode"		--实际交易类型
	,"BaseType"
	,"BaseEntry"
	,"BaseNum"
	,"BaseLine"
	,"ItemCode"
	,"ItemName"
	,"EvalSystem"
	,"ItmsGrpCod"
	,"CalType"	--成本计价类型
	,"Quantity"
	,"Amount"
	,"Price"
	,"WhsCode"
	,"WorType"
	,"WorEntry"
	,"WorNum"
	,"WorLineNum"
	,"CJCode"
	,"CJName"
	,"OcrCode1"
	,"OcrCode2"
	,"OcrCode3"
	,"OcrCode4"
	,"OcrCode5"
	,"User"
	,"TransId"
	,"Comments"
	,"CreateDate"		--创建时间
	,"Creator")
	SELECT "BPLId"
	,"ObjType"
	,"DocEntry"
	,"DocNum"
	,"CardCode"
	,"CardName"
	,"LineNum"
	,"FcCode"
	,"DocDate"
	,"CostCode"		--归入成本计价类型
	,"TransCode"		--实际交易类型
	,"BaseType"
	,"BaseEntry"
	,"BaseNum"
	,"BaseLine"
	,"ItemCode"
	,"ItemName"
	,"EvalSystem"
	,"ItmsGrpCod"
	,"CalType"	--成本计价类型
	,"Quantity"
	,"Amount"
	,"Price"
	,"WhsCode"
	,"WorType"
	,"WorEntry"
	,"WorNum"
	,"WorLineNum"
	,"CJCode"
	,"CJName"
	,"OcrCode1"
	,"OcrCode2"
	,"OcrCode3"
	,"OcrCode4"
	,"OcrCode5"
	,"User"
	,"TransId"
	,"Comments"
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM "MTC_COST_FC_DOCDETAIL"(:BPLId,:FcCode);
	
	SELECT 0 AS "代码",'收集出入库信息'||:FcCode||',成功！' AS "信息" FROM DUMMY;

END