/* =====================================================================
 * 新报表（未部署，用户 2026-10-30）：MTC_RPT_FI5009_V2 采购收货明细大表（替代 MTC_COST_PROC_FI5009）
 * 一行 = 一条暂估行（收货行 / 不基于收货的退货行）的一笔变动：暂估、开票、退货、换货，以及它们的取消，按日期排列，
 * 每行带“截至这一笔的未清数量 / 未清暂估”和这条暂估行截至 edate 的期末未清。口径与 PUR1–PUR5 凭证一致（220202 就是这样记的）：
 *   计提暂估 = PUR1 / PUR4；开票冲回暂估 = PUR2 / PUR3 借 220202；发票差额 = 发票 − 冲回暂估（材料进存货，委外加工费进 140803）。
 * 先部署 MTC_RPT_F_AP_MOVE。参数同旧版：sdate / edate = 收退货过账日期范围（'17530101' = 不限；edate 同时是“截至”日期，不限时取今天），
 *   CardCode = 供应商编码或名称片段，IsOnlyOpen = 'Y' 只列截至 edate 仍未清的暂估行。
 * 与旧 FI5009 的区别：
 *   - 截至 edate 计算：edate 以后的发票 / 退货 / 取消不计；edate 以后才取消的发票在 edate 时仍算有效
 *   - 开票、退货关联收货行时同时比 BaseType（旧版只比 BaseEntry + BaseLine，基于采购订单的同号发票会被算进来）
 *   - 冲回按暂估价（数量 × 暂估单价，最后一次清余数），不是按发票金额；退货按收货行的暂估单价
 *   - 新列：暂估口径（指定单价 / 已确认价 / 未确认）、变动类型、冲回规则、发票差额、截至这一笔的未清、变动账期（按账期筛本月变动）
 *   - 去掉“暂估剩余金额(老)”“当月剩余金额”（用户 2026-10-30 换成新口径）
 *   - 手工关闭的收货行不释放暂估（用户 2026-10-30），“B1 行状态”显示“已关闭”
 * 调用：CALL "MTC_RPT_FI5009_V2"('2026-09-01', '2026-09-30', '', 'N');
 * ===================================================================== */
CREATE PROCEDURE "MTC_RPT_FI5009_V2"
(
  IN sdate DATE,
  IN edate DATE,
  IN CardCode NVARCHAR(50),
  IN IsOnlyOpen NVARCHAR(10) DEFAULT 'N'
)
AS
BEGIN
	DECLARE d1 DATE;
	d1 := CASE WHEN :edate IS NULL OR :edate = '17530101' THEN CURRENT_DATE ELSE :edate END;

	mv0 = SELECT * FROM "MTC_RPT_F_AP_MOVE"(:d1)
	       WHERE ("BaseDate" >= :sdate OR :sdate = '17530101');
	-- 每条暂估行截至 edate 的未清
	lo = SELECT "BaseObj", "BaseEntry", "BaseLine", SUM("Qty") AS "EndQty", SUM("AccrAmt") AS "EndAmt"
	       FROM :mv0 GROUP BY "BaseObj", "BaseEntry", "BaseLine";
	mv = SELECT M.*, O."EndQty", O."EndAmt",
	            SUM(M."Qty") OVER (PARTITION BY M."BaseObj", M."BaseEntry", M."BaseLine"
	                               ORDER BY M."DocDate", M."SortKey", M."IsCancel", M."ObjType", M."DocEntry", M."LineNum" ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS "CumQty",
	            SUM(M."AccrAmt") OVER (PARTITION BY M."BaseObj", M."BaseEntry", M."BaseLine"
	                                   ORDER BY M."DocDate", M."SortKey", M."IsCancel", M."ObjType", M."DocEntry", M."LineNum" ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS "CumAmt"
	       FROM :mv0 M
	       JOIN :lo O ON O."BaseObj" = M."BaseObj" AND O."BaseEntry" = M."BaseEntry" AND O."BaseLine" = M."BaseLine"
	      WHERE :IsOnlyOpen <> 'Y' OR ABS(O."EndQty") > 0.000001 OR ABS(O."EndAmt") >= 0.005;

	-- 暂估行的行信息
	dl = SELECT '20' AS "ObjType", D."DocEntry", D."LineNum", D."Dscription", D."U_ItemCode", D."U_Specs", D."U_InitPrice", D."Price", D."PriceAfVAT",
	            D."LineTotal", D."GTotal", D."LineStatus", D."BaseType", D."BaseEntry", D."BaseLine", D."WhsCode", D."AcctCode",
	            TO_NVARCHAR(D."U_BaseType") AS "UBaseType", D."U_BaseEntry"
	       FROM "PDN1" D WHERE D."DocEntry" IN (SELECT "BaseEntry" FROM :mv WHERE "BaseObj" = '20')
	     UNION ALL
	     SELECT '21', D."DocEntry", D."LineNum", D."Dscription", D."U_ItemCode", D."U_Specs", D."U_InitPrice", D."Price", D."PriceAfVAT",
	            D."LineTotal", D."GTotal", D."LineStatus", D."BaseType", D."BaseEntry", D."BaseLine", D."WhsCode", D."AcctCode",
	            TO_NVARCHAR(D."U_BaseType"), D."U_BaseEntry"
	       FROM "RPD1" D WHERE D."DocEntry" IN (SELECT "BaseEntry" FROM :mv WHERE "BaseObj" = '21');
	-- 单据头（暂估行和变动单据都从这里取单号）
	hd = SELECT '20' AS "ObjType", "DocEntry", "DocNum", "U_SupNum", "U_OldSysNo", "NumAtCard", "CardName", "DocCur", "DocRate", "U_TrsName", "TransId" FROM "OPDN"
	      WHERE "DocEntry" IN (SELECT "BaseEntry" FROM :mv WHERE "BaseObj" = '20' UNION SELECT "DocEntry" FROM :mv WHERE "ObjType" = '20')
	     UNION ALL
	     SELECT '21', "DocEntry", "DocNum", "U_SupNum", "U_OldSysNo", "NumAtCard", "CardName", "DocCur", "DocRate", "U_TrsName", "TransId" FROM "ORPD"
	      WHERE "DocEntry" IN (SELECT "BaseEntry" FROM :mv WHERE "BaseObj" = '21' UNION SELECT "DocEntry" FROM :mv WHERE "ObjType" = '21')
	     UNION ALL
	     SELECT '18', "DocEntry", "DocNum", NULL, NULL, "NumAtCard", "CardName", "DocCur", "DocRate", NULL, "TransId" FROM "OPCH"
	      WHERE "DocEntry" IN (SELECT "DocEntry" FROM :mv WHERE "ObjType" = '18')
	     UNION ALL
	     SELECT '19', "DocEntry", "DocNum", NULL, NULL, "NumAtCard", "CardName", "DocCur", "DocRate", NULL, "TransId" FROM "ORPC"
	      WHERE "DocEntry" IN (SELECT "DocEntry" FROM :mv WHERE "ObjType" = '19');

	SELECT CASE WHEN M."BaseObj" = '20' THEN '采购收货单' ELSE '采购退货' END AS "类型"
	,CASE WHEN M."MoveType" = 'ACCR' AND M."IsCancel" = 'N' THEN CASE WHEN M."BaseObj" = '20' THEN '收货暂估' ELSE '退货暂估' END
	      WHEN M."MoveType" = 'ACCR' THEN CASE WHEN M."BaseObj" = '20' THEN '收货取消' ELSE '退货取消' END
	      WHEN M."MoveType" = 'INV' THEN CASE WHEN M."ObjType" = '18' THEN '应付发票' ELSE '应付贷项' END || CASE WHEN M."IsCancel" = 'Y' THEN '取消' ELSE '' END
	      ELSE CASE WHEN M."ObjType" = '21' THEN '采购退货' ELSE '基于退货的收货' END || CASE WHEN M."IsCancel" = 'Y' THEN '取消' ELSE '' END
	      END AS "变动类型"
	,H."DocNum" AS "收退货Num"
	,H."U_SupNum" AS "收退货单号"
	,H."U_OldSysNo" AS "老系统单号"
	,H."NumAtCard" AS "参考号"
	,M."BaseDate" AS "过账日期"
	,H."DocCur" AS "币种"
	,H."DocRate" AS "汇率"
	,T3."Name" AS "单据类型"
	,M."CardCode" AS "供应商编码"
	,H."CardName" AS "供应商名称"
	,M."ItemCode" AS "物料编号"
	,D."U_ItemCode" AS "料号"
	,D."Dscription" AS "物料名称"
	,T11."InvntryUom" AS "单位"
	,D."U_Specs" AS "规格"
	,T7."BatchNumber" AS "批次"
	,T91."ItmsGrpNam" AS "物料组"
	,CASE WHEN M."AccrType" = 'SUBFEE' THEN '委外费用' ELSE '材料' END AS "暂估类型"
	,CASE M."PriceRule" WHEN 'INIT' THEN '指定单价' WHEN 'CONF' THEN '已确认价' ELSE '未确认（LineTotal）' END AS "暂估口径"
	,M."BaseSign" * M."BaseQty" AS "暂估数量"
	,D."Price" AS "未税单价"
	,D."PriceAfVAT" AS "含税单价"
	,M."BaseSign" * D."LineTotal" AS "未税金额（本币）"
	,M."BaseSign" * D."GTotal" AS "含税金额（本币）"
	,D."U_InitPrice" AS "指定单价"
	,M."UnitPrice" AS "暂估单价"
	,M."BaseSign" * M."FullAmt" AS "整行暂估金额"
	-- 这一笔变动
	,M."DocDate" AS "变动日期"
	,TO_CHAR(M."DocDate", 'YYYY-MM') AS "变动账期"
	,V."DocNum" AS "变动单据Num"
	,V."NumAtCard" AS "变动单据参考号"
	,M."BaseSign" * M."Qty" AS "变动数量"
	,M."DocAmt" AS "发票未税金额"
	,M."AccrAmt" AS "暂估变动"
	,CASE WHEN M."MoveType" = 'INV' THEN IFNULL(M."DocAmt", 0) + M."AccrAmt" END AS "发票差额"
	,CASE M."AmtRule" WHEN 'FULL' THEN '整行' WHEN 'ROUND' THEN '数量 × 暂估单价' WHEN 'LAST' THEN '最后一笔清余数' WHEN 'CANCEL' THEN '取消（原单反向）' END AS "冲回规则"
	,CASE WHEN M."MoveType" = 'ACCR' THEN CASE WHEN M."AccrType" = 'SUBFEE' THEN 'PUR4' ELSE 'PUR1' END
	      WHEN M."MoveType" = 'INV' THEN CASE WHEN M."AccrType" = 'SUBFEE' THEN 'PUR3' ELSE 'PUR2' END
	      ELSE CASE WHEN M."AccrType" = 'SUBFEE' THEN 'PUR4' ELSE 'PUR1' END END AS "对应凭证"
	,J."U_CWNum" AS "财务凭证号"
	,M."BaseSign" * M."CumQty" AS "截至该笔未清数量"
	,M."CumAmt" AS "截至该笔未清暂估"
	-- 这条暂估行截至 edate
	,M."BaseSign" * M."EndQty" AS "期末未清数量"
	,M."EndAmt" AS "期末未清暂估"
	,CASE WHEN D."LineStatus" = 'C' THEN '已关闭' ELSE '未清' END AS "B1 行状态"
	,CASE WHEN D."LineStatus" = 'C' AND (ABS(M."EndQty") > 0.000001 OR ABS(M."EndAmt") >= 0.005)
	      THEN '行已关闭但截至期末仍有暂估：手工关闭或期末后开票 / 退货，暂估不释放' ELSE '' END AS "说明"
	-- 来源
	,T9."DocNum" AS "采购订单号Num"
	,T9."U_SupNum" AS "采购订单号"
	,T12."DocNum" AS "采购申请单号Num"
	,T12."U_SupNum" AS "采购申请单号"
	,T8."Project" AS "项目"
	,T22."OcrName" AS "部门"
	,T14."U_SupNum" AS "生产收/退货单号"
	,D."AcctCode" AS "收入科目"
	,M."BaseObj" AS "ObjType"
	,M."BaseEntry" AS "DocEntry"
	,M."BaseLine" AS "LineNum"
	,M."ObjType" AS "变动ObjType"
	,M."DocEntry" AS "变动DocEntry"
	,M."LineNum" AS "变动LineNum"
	FROM :mv M
	LEFT JOIN :dl D ON D."ObjType" = M."BaseObj" AND D."DocEntry" = M."BaseEntry" AND D."LineNum" = M."BaseLine"
	LEFT JOIN :hd H ON H."ObjType" = M."BaseObj" AND H."DocEntry" = M."BaseEntry"
	LEFT JOIN :hd V ON V."ObjType" = M."ObjType" AND V."DocEntry" = M."DocEntry"
	LEFT JOIN "OJDT" J ON M."MoveType" = 'INV' AND J."TransId" = V."TransId"
	LEFT JOIN "@U_CIOTRN" T3 ON T3."Code" = H."U_TrsName"
	LEFT JOIN "OITM" T11 ON T11."ItemCode" = M."ItemCode"
	LEFT JOIN "OITB" T91 ON T91."ItmsGrpCod" = T11."ItmsGrpCod"
	LEFT JOIN (SELECT "ObjType", "DocEntry", "LineNum", "WhsCode", STRING_AGG("BatchNumber", ',') AS "BatchNumber"
	             FROM "MTC_VW_DOCLINE" GROUP BY "ObjType", "DocEntry", "LineNum", "WhsCode") T7
	       ON TO_NVARCHAR(T7."ObjType") = M."BaseObj" AND T7."DocEntry" = M."BaseEntry" AND T7."LineNum" = M."BaseLine" AND T7."WhsCode" = D."WhsCode"
	LEFT JOIN "POR1" T8 ON M."BaseObj" = '20' AND D."BaseType" = 22 AND T8."DocEntry" = D."BaseEntry" AND T8."LineNum" = D."BaseLine"
	LEFT JOIN "OPOR" T9 ON T9."DocEntry" = T8."DocEntry"
	LEFT JOIN "OPRQ" T12 ON T8."BaseType" = 1470000113 AND T12."DocEntry" = T8."BaseEntry"
	LEFT JOIN "OOCR" T22 ON T22."OcrCode" = T8."OcrCode"
	LEFT JOIN "OIGN" T14 ON D."UBaseType" = '59' AND T14."DocEntry" = D."U_BaseEntry"
	WHERE (M."CardCode" LIKE '%' || :CardCode || '%' OR H."CardName" LIKE '%' || :CardCode || '%' OR :CardCode = '')
	ORDER BY M."CardCode", M."BaseDate", H."DocNum", M."BaseLine", M."DocDate", M."SortKey", M."IsCancel", M."ObjType", M."DocEntry";
END;
