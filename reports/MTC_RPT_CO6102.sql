/* =====================================================================
 * 新报表草稿：MTC_RPT_CO6102 采购收货应付暂估表（未部署，仅供审阅）
 * 作用：截至账期期末，已收货（含退货）但尚未开应付发票（或应付贷项）的部分，按暂估价出具汇总、明细和与总账 220202 的核对。
 * 参数：STYPE 0 汇总（按供应商 × 类型） / 1 明细（按单据行） / 2 与总账 220202 按供应商核对
 *       FcCode 账期（OFPR.Code），CardCode 供应商编码或名称片段，空 = 全部
 * 口径（与 MTC_COST_PROC_6101_1 的 PUR1/PUR4 计提、PUR2/PUR3 冲回一致）：
 *   - 范围：库存物料（OITM.InvntItem='Y'）和委外加工费 X0510001（类型“委外费用”，计提时借 140802），与 6101_1 的 SUM 口径相同
 *   - 暂估单价：U_InitPrice 不为 0 用 U_InitPrice；U_IsPrice='Y' 用 Price；否则 LineTotal / Quantity
 *   - 收货行未清数量 = 收货数量 − 截至期末已开发票数量 − 截至期末已退货数量（基于该收货行的退货）
 *   - 退货行（不基于收货的独立退货）为负数，未清数量 = 退货数量 − 已开应付贷项数量 − 已基于该退货重新收货的数量
 *   - 基于退货重新收货的收货行不单独列示（它只是关闭那张退货）
 *   - 未清金额：全部未清时取整行暂估金额，部分未清时 = 未清数量 × 暂估单价（与 6101_1 冲回时整行取 LineTotal、部分按单价一致）
 *   - “截至期末”：只计过账日期 <= 期末的单据；被取消的单据，只有取消单过账日期 <= 期末才视为已取消。
 *     因此重跑历史账期结果不变（不依赖 LineStatus / OpenQty 这些当前状态字段）。
 * 与 FI5009 的区别：FI5009 冲减已开票部分用发票金额，本报表用收货暂估价（总账 220202 就是这样冲回的）。
 * 调用：CALL "MTC_RPT_CO6102"(0, '2026-08', '');
 * ===================================================================== */
CREATE PROCEDURE "MTC_RPT_CO6102"
(
  IN STYPE INT,					--0汇总 1明细 2与总账核对
  IN FcCode NVARCHAR(10),
  IN CardCode NVARCHAR(50) DEFAULT ''
)
LANGUAGE SQLSCRIPT
AS
BEGIN
	DECLARE edate DATE;
	SELECT "T_RefDate" INTO edate FROM "OFPR" WHERE "Code"=:FcCode;

	--截至期末已被取消的原单（取消单过账日期 <= 期末）
	CXL=
	SELECT DISTINCT D."BaseType" AS "ObjType",D."BaseEntry" AS "DocEntry"
	FROM OPDN M JOIN PDN1 D ON M."DocEntry"=D."DocEntry" WHERE M."CANCELED"='C' AND M."DocDate"<=:edate AND D."BaseType"=20
	UNION
	SELECT DISTINCT D."BaseType",D."BaseEntry" FROM ORPD M JOIN RPD1 D ON M."DocEntry"=D."DocEntry" WHERE M."CANCELED"='C' AND M."DocDate"<=:edate AND D."BaseType"=21
	UNION
	SELECT DISTINCT D."BaseType",D."BaseEntry" FROM OPCH M JOIN PCH1 D ON M."DocEntry"=D."DocEntry" WHERE M."CANCELED"='C' AND M."DocDate"<=:edate AND D."BaseType"=18
	UNION
	SELECT DISTINCT D."BaseType",D."BaseEntry" FROM ORPC M JOIN RPC1 D ON M."DocEntry"=D."DocEntry" WHERE M."CANCELED"='C' AND M."DocDate"<=:edate AND D."BaseType"=19;

	--截至期末有效的后续单据行（发票、贷项、退货、重新收货），按来源行汇总数量
	NXT=
	SELECT D."BaseType",D."BaseEntry",D."BaseLine",SUM(D."Quantity") AS "Qty",'INV' AS "K"
	FROM OPCH M JOIN PCH1 D ON M."DocEntry"=D."DocEntry"
	WHERE M."CANCELED"<>'C' AND M."DocDate"<=:edate AND D."BaseType" IN (20,21)
	AND NOT EXISTS (SELECT 1 FROM :CXL X WHERE X."ObjType"=18 AND X."DocEntry"=M."DocEntry")
	GROUP BY D."BaseType",D."BaseEntry",D."BaseLine"
	UNION ALL
	SELECT D."BaseType",D."BaseEntry",D."BaseLine",SUM(D."Quantity"),'INV'
	FROM ORPC M JOIN RPC1 D ON M."DocEntry"=D."DocEntry"
	WHERE M."CANCELED"<>'C' AND M."DocDate"<=:edate AND D."BaseType"=21
	AND NOT EXISTS (SELECT 1 FROM :CXL X WHERE X."ObjType"=19 AND X."DocEntry"=M."DocEntry")
	GROUP BY D."BaseType",D."BaseEntry",D."BaseLine"
	UNION ALL
	SELECT D."BaseType",D."BaseEntry",D."BaseLine",SUM(D."Quantity"),'RET'
	FROM ORPD M JOIN RPD1 D ON M."DocEntry"=D."DocEntry"
	WHERE M."CANCELED"<>'C' AND M."DocDate"<=:edate AND D."BaseType"=20
	AND NOT EXISTS (SELECT 1 FROM :CXL X WHERE X."ObjType"=21 AND X."DocEntry"=M."DocEntry")
	GROUP BY D."BaseType",D."BaseEntry",D."BaseLine"
	UNION ALL
	SELECT D."BaseType",D."BaseEntry",D."BaseLine",SUM(D."Quantity"),'RET'
	FROM OPDN M JOIN PDN1 D ON M."DocEntry"=D."DocEntry"
	WHERE M."CANCELED"<>'C' AND M."DocDate"<=:edate AND D."BaseType"=21
	AND NOT EXISTS (SELECT 1 FROM :CXL X WHERE X."ObjType"=20 AND X."DocEntry"=M."DocEntry")
	GROUP BY D."BaseType",D."BaseEntry",D."BaseLine";

	--收货行和独立退货行（截至期末有效）
	SRC=
	SELECT '采购收货' AS "单据类型",CAST(M."ObjType" AS INT) AS "ObjType",M."DocEntry",M."DocNum",M."U_SupNum",D."LineNum",M."DocDate",M."CardCode",M."CardName"
	,D."ItemCode",D."Dscription",D."WhsCode",D."AcctCode",1 AS "Sign"
	,D."Quantity",D."U_InitPrice",D."U_IsPrice",D."Price",D."LineTotal"
	FROM OPDN M JOIN PDN1 D ON M."DocEntry"=D."DocEntry"
	WHERE M."CANCELED"<>'C' AND M."DocDate"<=:edate AND IFNULL(D."BaseType",-1)<>21
	AND NOT EXISTS (SELECT 1 FROM :CXL X WHERE X."ObjType"=20 AND X."DocEntry"=M."DocEntry")
	UNION ALL
	SELECT '采购退货',CAST(M."ObjType" AS INT),M."DocEntry",M."DocNum",M."U_SupNum",D."LineNum",M."DocDate",M."CardCode",M."CardName"
	,D."ItemCode",D."Dscription",D."WhsCode",D."AcctCode",-1
	,D."Quantity",D."U_InitPrice",D."U_IsPrice",D."Price",D."LineTotal"
	FROM ORPD M JOIN RPD1 D ON M."DocEntry"=D."DocEntry"
	WHERE M."CANCELED"<>'C' AND M."DocDate"<=:edate AND IFNULL(D."BaseType",-1)<>20
	AND NOT EXISTS (SELECT 1 FROM :CXL X WHERE X."ObjType"=21 AND X."DocEntry"=M."DocEntry");

	DTL=
	SELECT * FROM (
		SELECT S.*
		,CASE WHEN S."ItemCode"='X0510001' THEN '委外费用' ELSE '材料' END AS "类型"
		,CASE WHEN IFNULL(S."U_InitPrice",0)<>0 THEN S."U_InitPrice" WHEN S."U_IsPrice"='Y' THEN S."Price"
			ELSE S."LineTotal"/NULLIF(S."Quantity",0) END AS "暂估单价"
		,ROUND(CASE WHEN IFNULL(S."U_InitPrice",0)<>0 THEN S."Quantity"*S."U_InitPrice" WHEN S."U_IsPrice"='Y' THEN S."Quantity"*S."Price"
			ELSE S."LineTotal" END,2) AS "整行暂估金额"
		,IFNULL(N1."Qty",0) AS "已开票数量",IFNULL(N2."Qty",0) AS "已退货或重收数量"
		,S."Quantity"-IFNULL(N1."Qty",0)-IFNULL(N2."Qty",0) AS "未清数量"
		FROM :SRC S
		JOIN OITM I ON S."ItemCode"=I."ItemCode"
		LEFT JOIN :NXT N1 ON N1."K"='INV' AND N1."BaseType"=S."ObjType" AND N1."BaseEntry"=S."DocEntry" AND N1."BaseLine"=S."LineNum"
		LEFT JOIN :NXT N2 ON N2."K"='RET' AND N2."BaseType"=S."ObjType" AND N2."BaseEntry"=S."DocEntry" AND N2."BaseLine"=S."LineNum"
		WHERE (I."InvntItem"='Y' OR S."ItemCode"='X0510001')
		AND (S."CardCode" LIKE '%'||:CardCode||'%' OR S."CardName" LIKE '%'||:CardCode||'%' OR :CardCode='')
	) T WHERE ABS(T."未清数量")>0.000001;

	DTL2=
	SELECT T.*
	,T."Sign"*T."未清数量" AS "暂估数量"
	,T."Sign"*CASE WHEN ABS(T."未清数量"-T."Quantity")<0.000001 THEN T."整行暂估金额"
		ELSE ROUND(T."未清数量"*T."暂估单价",2) END AS "暂估金额"
	FROM :DTL T;

	IF :STYPE=1 THEN
		SELECT :FcCode AS "期间",T."类型",T."单据类型",T."DocNum" AS "单据号",T."U_SupNum" AS "收退货单号",T."LineNum" AS "行号"
		,T."DocDate" AS "过账日期",T."CardCode" AS "供应商编码",T."CardName" AS "供应商名称"
		,T."ItemCode" AS "物料编码",T."Dscription" AS "物料名称",T."WhsCode" AS "仓库",T."AcctCode" AS "科目"
		,T."Sign"*T."Quantity" AS "单据数量",T."已开票数量",T."已退货或重收数量",T."暂估数量"
		,T."暂估单价",T."暂估金额",T."Sign"*T."LineTotal" AS "单据未税金额"
		,DAYS_BETWEEN(T."DocDate",:edate) AS "账龄天数"
		,T."ObjType",T."DocEntry"
		FROM :DTL2 T
		ORDER BY T."CardCode",T."DocDate",T."DocNum",T."LineNum";
	ELSEIF :STYPE=2 THEN
		--与总账 220202（应付暂估）按供应商核对：总账按 JDT1.U_VendorCode 归属供应商（6101_1 也按这个字段）
		GL=
		SELECT IFNULL(J."U_VendorCode",'') AS "CardCode",SUM(J."Credit"-J."Debit") AS "Bal"
		FROM JDT1 J WHERE J."Account"='220202' AND J."RefDate"<=:edate
		GROUP BY IFNULL(J."U_VendorCode",'');
		BZ=
		SELECT "CardCode",MAX("CardName") AS "CardName",SUM("暂估金额") AS "Amt" FROM :DTL2 GROUP BY "CardCode";
		SELECT :FcCode AS "期间",COALESCE(B."CardCode",G."CardCode") AS "供应商编码",IFNULL(B."CardName",C."CardName") AS "供应商名称"
		,ROUND(IFNULL(B."Amt",0),2) AS "业务暂估余额",ROUND(IFNULL(G."Bal",0),2) AS "总账220202余额"
		,ROUND(IFNULL(G."Bal",0)-IFNULL(B."Amt",0),2) AS "差额[总账-业务]"
		FROM :BZ B
		FULL OUTER JOIN (SELECT * FROM :GL WHERE (:CardCode='' OR "CardCode" LIKE '%'||:CardCode||'%')) G ON G."CardCode"=B."CardCode"
		LEFT JOIN OCRD C ON C."CardCode"=COALESCE(B."CardCode",G."CardCode")
		WHERE ABS(IFNULL(G."Bal",0))>0.005 OR ABS(IFNULL(B."Amt",0))>0.005
		ORDER BY ABS(IFNULL(G."Bal",0)-IFNULL(B."Amt",0)) DESC;
	ELSE
		SELECT :FcCode AS "期间",T."CardCode" AS "供应商编码",MAX(T."CardName") AS "供应商名称",T."类型"
		,COUNT(*) AS "未清行数"
		,SUM(CASE WHEN T."单据类型"='采购收货' THEN T."暂估金额" ELSE 0 END) AS "收货未开票金额"
		,SUM(CASE WHEN T."单据类型"='采购退货' THEN T."暂估金额" ELSE 0 END) AS "退货未开贷项金额"
		,SUM(T."暂估金额") AS "暂估金额合计"
		,MIN(T."DocDate") AS "最早单据日期"
		FROM :DTL2 T
		GROUP BY T."CardCode",T."类型"
		ORDER BY T."CardCode",T."类型";
	END IF;
END
