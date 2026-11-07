CREATE PROCEDURE "MTC_COST_PROC_0101_COSTTYPE"(IN UserCode NVARCHAR(50))
LANGUAGE SQLSCRIPT
AS
BEGIN
	

	
	/* created by chri.li 2024.11.23
     * 抽取物料等级 到 明细到静态表 MTC_COST_0105_ITEM
     * CALL "MTC_COST_PROC_0101_COSTTYPE"('manager');
    */
	
	--DELETE FROM MTC_COST_0101_COSTTYPE;
	
	INSERT INTO MTC_COST_0101_COSTTYPE(
	 "CostTypeCode"
	,"CostTypeName"
	,"IsMain"
	,"CreateDate"		--创建时间
	,"Creator")
	SELECT
	 '10','总成本','Y'
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM DUMMY
	
	UNION ALL
	SELECT
	 '20','材料','Y'
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM DUMMY
	
	UNION ALL
	SELECT
	 '30','制造费用','Y'
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM DUMMY
	
	UNION ALL
	SELECT
	 '40','人工费用','Y'
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM DUMMY
	;

END