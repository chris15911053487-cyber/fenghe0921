CREATE PROCEDURE "MTC_COST_PROC_0000"(IN BPLId INT,IN FcCode NVARCHAR(10),IN UserCode NVARCHAR(50))
LANGUAGE SQLSCRIPT
AS
BEGIN
	
	/* created by chri.li 2024.11.23
     * 成本一键计算
     * CALL "MTC_COST_PROC_0000"(0,:FcCode,:UserCode);
    */
    
    DECLARE Stime NVARCHAR(50);
    DECLARE Etime NVARCHAR(50);
    
    
  	IF EXISTS(SELECT 1 FROM "OFPR" WHERE "PeriodStat"='Y' AND "Code"=:FcCode) THEN
  		SELECT -1 AS "Code",'账期已锁定，无法计算成本' AS "Msg" FROM DUMMY;
  		RETURN;
  	END IF;
  	
	SELECT CURRENT_TIMESTAMP INTO Stime FROM DUMMY;
	
	--1.获取物料等级
	CALL "MTC_CO_001GetItemLevel"(:FcCode);
 	--期初价格
	--CALL MTC_COST_PROC_0210_QCPRICE(:FcCode);
  	--生产订单的结构，用于计算在产品的比
  	CALL "MTC_COST_PROC_0106_OWORLIST"(0,:FcCode,:UserCode);
  	
  	--收集出入库信息（用于生产订单）
	CALL MTC_COST_PROC_0201_DOCDETAIL(0,:FcCode,:UserCode);
	
	--收集期初生产订单（根据实际出入库的明细）——数据来自（MTC_COST_0201_DOCDETAL）
	CALL "MTC_COST_PROC_0321_OWOR"(0,:FcCode,:UserCode);
	
	--2.建立库存清单 MTC_COST_PROC_0301_INVNT  （结构+当期的期初QC_QTY）
	CALL "MTC_COST_PROC_0301_INVNT"(0,:FcCode,:UserCode);
	
	--3.建立数据进销存结构MTC_COST_PROC_0302_INVNTDETAIL1 1.收集入明细。2.数量写入INVNT和INVNTLIST，3.计算原材料成本
	CALL "MTC_COST_PROC_0302_INVNTDETAIL1"(0,:FcCode,:UserCode);
	
	--费用归集（包含领用后要归集入费用的部分）
	CALL "MTC_COST_PROC_0311_PRODUCTEXP_ADD"(0,:FcCode,:UserCode);
	--费用分摊（不分摊到委外工单）
	CALL "MTC_COST_PROC_0312_PRODUCTEXP_PRC"(0,:FcCode,:UserCode);
	--委外费用
	CALL "MTC_COST_PROC_0306_WW"(0,:FcCode,:UserCode);
	--成本计算（当期），会扩展执行MTC_COST_PROC_0402_CAL_OWOR 将处理在产品过后的信息写入。同时循环更新生产订单的单价，
	CALL "MTC_COST_PROC_0401_CAL"(0,:FcCode,:UserCode);
	--处理期末差异
	CALL "MTC_COST_PROC_0501_Diff"(0,:FcCode,:UserCode);
	--写入在产品静态表
	CALL "MTC_PRT_CO4001"('',:FcCode,'', '','','Y','Y');
	--写入在产品静态明细表
	CALL "MTC_RPT_CO4011"(0,:FcCode,'生产工单','','','Y','Y');
	CALL "MTC_RPT_CO4011"(0,:FcCode,'委外工单','','','Y','Y');
	--生成期末分录
	CALL MTC_COST_PROC_0801_TOOJDT(0,:FcCode,:UserCode);
	
	SELECT CURRENT_TIMESTAMP INTO Etime FROM DUMMY;
	SELECT 0 AS "Err",:FcCode||'的成本计算成功。开始时间：'||:Stime||',结束时间：'||:Etime AS "Msg" FROM DUMMY;

END