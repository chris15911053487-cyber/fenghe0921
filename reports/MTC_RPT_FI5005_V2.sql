/* =====================================================================
 * 新报表（未部署，用户 2026-10-30）：MTC_RPT_FI5005_V2 截至期末未清的采购收退货明细（替代 MTC_RPT_FI5005）
 * 一行 = 一条截至 edate 仍有暂估的收货行 / 不基于收货的退货行。按供应商合计 = 220202 应付暂估（PUR1–PUR5 记账后、按 U_VendorCode），
 * 与新框架 POST-11、执行台“应付暂估”同一口径。先部署 MTC_RPT_F_AP_MOVE。
 * 参数同旧版：sdate / edate = 收退货过账日期范围（'17530101' = 不限；edate 同时是“截至”日期，不限时取今天），CardCode = 供应商编码或名称片段。
 * 与旧 FI5005 的区别：
 *   - 截至 edate 计算（只计 edate 以前的发票、退货、取消），不用 LineStatus / OpenCreQty 当前值，重查历史日期结果不变
 *   - 基于收货的退货不再单独列负数（旧版收货行的未清数量已扣掉它，又列一次，重复扣）；只列不基于收货的退货
 *   - 金额 = 整行暂估 − 已冲回暂估（每次 数量 × 暂估单价，最后一次清余数），已确认价 U_IsPrice='Y' 取 Price，否则 LineTotal
 *   - 手工关闭的收货行照样列出（暂估不释放，用户 2026-10-30），“B1 行状态”列显示“已关闭”
 * 调用：CALL "MTC_RPT_FI5005_V2"('17530101', '2026-09-30', '');
 * ===================================================================== */
CREATE PROCEDURE "MTC_RPT_FI5005_V2"
(
  IN sdate DATE,
  IN edate DATE,
  IN CardCode NVARCHAR(50)
)
AS
BEGIN
	DECLARE d1 DATE;
	d1 := CASE WHEN :edate IS NULL OR :edate = '17530101' THEN CURRENT_DATE ELSE :edate END;

	mv = SELECT * FROM "MTC_RPT_F_AP_MOVE"(:d1);
	ln = SELECT "BaseObj", "BaseEntry", "BaseLine",
	            MAX("BaseDocNum") AS "BaseDocNum", MAX("BaseDate") AS "BaseDate", MAX("BaseSign") AS "BaseSign", MAX("BaseQty") AS "BaseQty",
	            MAX("CardCode") AS "CardCode", MAX("ItemCode") AS "ItemCode", MAX("AccrType") AS "AccrType", MAX("PriceRule") AS "PriceRule",
	            MAX("UnitPrice") AS "UnitPrice", MAX("FullAmt") AS "FullAmt",
	            SUM(CASE WHEN "MoveType" = 'INV' THEN -"Qty" ELSE 0 END) AS "InvQty",
	            SUM(CASE WHEN "MoveType" = 'RET' THEN -"Qty" ELSE 0 END) AS "RetQty",
	            SUM("Qty") AS "OpenQty",
	            SUM(CASE WHEN "MoveType" = 'INV' THEN -"AccrAmt" ELSE 0 END) AS "InvAccr",
	            SUM(CASE WHEN "MoveType" = 'RET' THEN -"AccrAmt" ELSE 0 END) AS "RetAccr",
	            SUM(CASE WHEN "MoveType" = 'INV' THEN IFNULL("DocAmt", 0) ELSE 0 END) AS "InvAmt",
	            SUM("AccrAmt") AS "OpenAmt"
	       FROM :mv
	      GROUP BY "BaseObj", "BaseEntry", "BaseLine"
	     HAVING ABS(SUM("Qty")) > 0.000001 OR ABS(SUM("AccrAmt")) >= 0.005;
	dl = SELECT '20' AS "ObjType", D."DocEntry", D."LineNum", D."Dscription", D."U_ItemCode", D."U_Specs", D."U_BtchNum", D."U_InitPrice", D."Price",
	            D."LineStatus", D."BaseType", D."BaseEntry", D."BaseLine"
	       FROM "PDN1" D WHERE D."DocEntry" IN (SELECT "BaseEntry" FROM :ln WHERE "BaseObj" = '20')
	     UNION ALL
	     SELECT '21', D."DocEntry", D."LineNum", D."Dscription", D."U_ItemCode", D."U_Specs", D."U_BtchNum", D."U_InitPrice", D."Price",
	            D."LineStatus", D."BaseType", D."BaseEntry", D."BaseLine"
	       FROM "RPD1" D WHERE D."DocEntry" IN (SELECT "BaseEntry" FROM :ln WHERE "BaseObj" = '21');
	hd = SELECT '20' AS "ObjType", "DocEntry", "U_SupNum", "U_OldSysNo", "CardName", "NumAtCard" FROM "OPDN" WHERE "DocEntry" IN (SELECT "BaseEntry" FROM :ln WHERE "BaseObj" = '20')
	     UNION ALL
	     SELECT '21', "DocEntry", "U_SupNum", "U_OldSysNo", "CardName", "NumAtCard" FROM "ORPD" WHERE "DocEntry" IN (SELECT "BaseEntry" FROM :ln WHERE "BaseObj" = '21');

	SELECT CASE WHEN L."BaseObj" = '20' THEN '采购收货单' ELSE '采购退货' END AS "单据类型"
	,T9."DocNum" AS "采购订单Num"
	,T9."U_SupNum" AS "采购订单号"
	,L."BaseDocNum" AS "收退货Num"
	,H."U_SupNum" AS "收退货单号"
	,H."U_OldSysNo" AS "老系统单号"
	,H."NumAtCard" AS "参考号"
	,L."CardCode" AS "供应商代码"
	,H."CardName" AS "供应商名称"
	,T6."U_OldSysCode" AS "老系统编码"
	,L."BaseDate" AS "过账日期"
	,L."ItemCode" AS "物料号"
	,CASE WHEN LEFT(L."ItemCode", 1) = 'X' THEN D."U_ItemCode" ELSE '' END AS "料号"
	,T5."ItemName" AS "描述"
	,CASE WHEN LEFT(L."ItemCode", 1) = 'X' THEN D."Dscription" ELSE '' END AS "物料描述"
	,T5."InvntryUom" AS "单位"
	,T5."U_Specs" AS "规格"
	,D."U_BtchNum" AS "批次号"
	,CASE WHEN L."AccrType" = 'SUBFEE' THEN '委外费用' ELSE '材料' END AS "类型"
	,CASE L."PriceRule" WHEN 'INIT' THEN '指定单价' WHEN 'CONF' THEN '已确认价' ELSE '未确认（LineTotal）' END AS "暂估口径"
	,D."U_InitPrice" AS "指定单价"
	,D."Price" AS "未税单价"
	,L."UnitPrice" AS "暂估单价"
	,L."BaseSign" * L."BaseQty" AS "暂估数量"
	,L."BaseSign" * L."InvQty" AS "已开票数量"
	,L."BaseSign" * L."RetQty" AS "已退货数量"
	,L."BaseSign" * L."OpenQty" AS "未清数量"
	,L."BaseSign" * L."FullAmt" AS "整行暂估金额"
	,L."InvAccr" AS "开票冲回暂估"
	,L."RetAccr" AS "退货冲回暂估"
	,L."InvAmt" AS "已开票未税金额"
	,L."InvAmt" - L."InvAccr" AS "发票差额"
	,L."OpenAmt" AS "未清暂估金额"
	,CASE WHEN D."LineStatus" = 'C' THEN '已关闭' ELSE '未清' END AS "B1 行状态"
	,CASE WHEN D."LineStatus" = 'C' THEN '行已关闭但截至期末仍有暂估：手工关闭或期末后开票 / 退货，暂估不释放' ELSE '' END AS "说明"
	,L."BaseObj" AS "ObjType"
	,L."BaseEntry" AS "DocEntry"
	,L."BaseLine" AS "LineNum"
	FROM :ln L
	LEFT JOIN :dl D ON D."ObjType" = L."BaseObj" AND D."DocEntry" = L."BaseEntry" AND D."LineNum" = L."BaseLine"
	LEFT JOIN :hd H ON H."ObjType" = L."BaseObj" AND H."DocEntry" = L."BaseEntry"
	LEFT JOIN "OITM" T5 ON T5."ItemCode" = L."ItemCode"
	LEFT JOIN "OCRD" T6 ON T6."CardCode" = L."CardCode"
	LEFT JOIN "OPOR" T9 ON L."BaseObj" = '20' AND D."BaseType" = 22 AND T9."DocEntry" = D."BaseEntry"
	WHERE (L."BaseDate" >= :sdate OR :sdate = '17530101')
	  AND (L."CardCode" LIKE '%' || :CardCode || '%' OR H."CardName" LIKE '%' || :CardCode || '%' OR :CardCode = '')
	ORDER BY L."BaseDate", L."BaseDocNum", L."BaseLine";
END;
