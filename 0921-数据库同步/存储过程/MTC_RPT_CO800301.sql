CREATE PROCEDURE "MTC_RPT_CO800301"
(
  DocEntry INT
 )
LANGUAGE SQLSCRIPT
AS
BEGIN 
	DECLARE TransCode NVARCHAR(50);
	
	SELECT "U_TransCode" INTO TransCode
	FROM "@MTC_COST_OJDT" T0
	WHERE T0."DocEntry"=:DocEntry;
	
	IF :TransCode = 'AR01' OR :TransCode = 'AR02' THEN
		SELECT T0."DocEntry",T0."LineId" AS "行号"
		,T0."U_ItemCode" AS "物料编码",T0."U_ItemName" AS "物料名称"
		,T0."U_Quantity" AS "数量"
		,T0."U_LineTotal" AS "未税金额"
		,T0."U_VatSum" AS "税额"
		,T0."U_GTotal" AS "含税金额"
		,T0."U_ObjType" AS "来源单据编码" 
		,'' AS "来源单据类型"
		,T0."U_DocEntry" AS "来源单号Entry"
		,T0."U_DocNum" AS "来源单号Num"
		,T0."U_LineNum" AS "来源行号"
		,T0."U_CardCode" AS "业务伙伴编码"
		,T0."U_CardName" AS "业务伙伴名称"
		,T0."U_AcctCode" AS "科目编码"
		,T0."U_AcctName" AS "科目名称"
		,T0."U_StockAcctCode" AS "库存科目编码"
		,T0."U_StockAcctName" AS "库存科目名称"
		FROM "@MTC_COST_OJDT2" T0
		WHERE T0."DocEntry"=:DocEntry;
	ELSEIF :TransCode = 'YF01' OR :TransCode = 'PP01' OR :TransCode = 'WW01' OR :TransCode = 'YF01'
		OR :TransCode = 'DN01' OR :TransCode = 'DN02' OR :TransCode = 'DN03' OR :TransCode = 'DN04'
		OR :TransCode = 'AR03' OR :TransCode = 'AR04'
		THEN
		SELECT T0."DocEntry",T0."LineId" AS "行号"
		,T0."U_ItemCode" AS "物料编码",T0."U_ItemName" AS "物料名称"
		,-1*T0."U_Quantity" AS "数量"
		,-1*T0."U_LineTotal" AS "金额"
		,T0."U_ObjType" AS "来源单据编码" 
		,'' AS "来源单据类型"
		,T0."U_DocEntry" AS "来源单号Entry"
		,T0."U_DocNum" AS "来源单号Num"
		,T0."U_LineNum" AS "来源行号"
		,T0."U_CardCode" AS "业务伙伴编码"
		,T0."U_CardName" AS "业务伙伴名称"
		,T0."U_AcctCode" AS "科目编码"
		,T0."U_AcctName" AS "科目名称"
		,T0."U_StockAcctCode" AS "库存科目编码"
		,T0."U_StockAcctName" AS "库存科目名称"
		FROM "@MTC_COST_OJDT2" T0
		WHERE T0."DocEntry"=:DocEntry;
	ELSE
		SELECT T0."DocEntry",T0."LineId" AS "行号"
		,T0."U_ItemCode" AS "物料编码",T0."U_ItemName" AS "物料名称"
		,T0."U_Quantity" AS "数量"
		,T0."U_LineTotal" AS "未税金额"
		,T0."U_VatSum" AS "税额"
		,T0."U_GTotal" AS "含税金额"
		,T0."U_ObjType" AS "来源单据编码" 
		,'' AS "来源单据类型"
		,T0."U_DocEntry" AS "来源单号Entry"
		,T0."U_DocNum" AS "来源单号Num"
		,T0."U_LineNum" AS "来源行号"
		,T0."U_CardCode" AS "业务伙伴编码"
		,T0."U_CardName" AS "业务伙伴名称"
		,T0."U_AcctCode" AS "科目编码"
		,T0."U_AcctName" AS "科目名称"
		,T0."U_StockAcctCode" AS "库存科目编码"
		,T0."U_StockAcctName" AS "库存科目名称"
		FROM "@MTC_COST_OJDT2" T0
		WHERE T0."DocEntry"=:DocEntry;
	END IF;
END