/* =====================================================================
 * 新报表草稿：MTC_RPT_CO6103 发出商品暂估表（未部署，仅供审阅）
 * 作用：截至账期期末，已交货（含销售退货）但尚未开应收发票（或应收贷项）的部分，按成本价出具汇总、明细和与总账 140601 的核对。
 * 参数：STYPE 0 汇总（按客户） / 1 明细（按单据行） / 2 与总账核对
 *       FcCode 账期（OFPR.Code），CardCode 客户编码或名称片段，空 = 全部
 * 口径（与 0801 的 DN01 / DN03 / AR03 / AR04 一致）：
 *   - 范围：库存物料；样品销售（@MTC_SALORDTYPE.U_BusiType='样品销售'）不在发出商品中（DN02/DN04 交货当月就转了样品成本），单独标出不计入合计
 *   - 成本单价：交货/退货行在 MTC_COST_0302_INVNTDETAIL1 中的成本（同一行多条时按金额/数量加权）；
 *     2024-12-31 及以前的单据用 DLN1/RDN1.U_InitPrice（与 DN03、AR03 相同）。当期尚未计算成本时单价为空，“成本状态”标出
 *   - 交货行未清数量 = 交货数量 − 截至期末已开发票数量 − 截至期末已退货数量（基于该交货行的销售退货）
 *   - 独立销售退货（不基于交货）为负数，未清数量 = 退货数量 − 已开应收贷项数量
 *   - “截至期末”的处理同 MTC_RPT_CO6102：只看过账日期 <= 期末的单据，取消单过账日期 <= 期末才视为已取消。
 *     AR03/AR04 用的是 DLN1.OpenQty 当前值，历史账期重跑时会与本报表不同。
 * 调用：CALL "MTC_RPT_CO6103"(0, '2026-08', '');
 * ===================================================================== */
CREATE PROCEDURE "MTC_RPT_CO6103"
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

	--截至期末已被取消的原单
	CXL=
	SELECT DISTINCT D."BaseType" AS "ObjType",D."BaseEntry" AS "DocEntry"
	FROM ODLN M JOIN DLN1 D ON M."DocEntry"=D."DocEntry" WHERE M."CANCELED"='C' AND M."DocDate"<=:edate AND D."BaseType"=15
	UNION
	SELECT DISTINCT D."BaseType",D."BaseEntry" FROM ORDN M JOIN RDN1 D ON M."DocEntry"=D."DocEntry" WHERE M."CANCELED"='C' AND M."DocDate"<=:edate AND D."BaseType"=16
	UNION
	SELECT DISTINCT D."BaseType",D."BaseEntry" FROM OINV M JOIN INV1 D ON M."DocEntry"=D."DocEntry" WHERE M."CANCELED"='C' AND M."DocDate"<=:edate AND D."BaseType"=13
	UNION
	SELECT DISTINCT D."BaseType",D."BaseEntry" FROM ORIN M JOIN RIN1 D ON M."DocEntry"=D."DocEntry" WHERE M."CANCELED"='C' AND M."DocDate"<=:edate AND D."BaseType"=14;

	--截至期末有效的后续单据行，按来源行汇总数量
	NXT=
	SELECT D."BaseType",D."BaseEntry",D."BaseLine",SUM(D."Quantity") AS "Qty",'INV' AS "K"
	FROM OINV M JOIN INV1 D ON M."DocEntry"=D."DocEntry"
	WHERE M."CANCELED"<>'C' AND M."DocDate"<=:edate AND D."BaseType"=15
	AND NOT EXISTS (SELECT 1 FROM :CXL X WHERE X."ObjType"=13 AND X."DocEntry"=M."DocEntry")
	GROUP BY D."BaseType",D."BaseEntry",D."BaseLine"
	UNION ALL
	SELECT D."BaseType",D."BaseEntry",D."BaseLine",SUM(D."Quantity"),'INV'
	FROM ORIN M JOIN RIN1 D ON M."DocEntry"=D."DocEntry"
	WHERE M."CANCELED"<>'C' AND M."DocDate"<=:edate AND D."BaseType"=16
	AND NOT EXISTS (SELECT 1 FROM :CXL X WHERE X."ObjType"=14 AND X."DocEntry"=M."DocEntry")
	GROUP BY D."BaseType",D."BaseEntry",D."BaseLine"
	UNION ALL
	SELECT D."BaseType",D."BaseEntry",D."BaseLine",SUM(D."Quantity"),'RET'
	FROM ORDN M JOIN RDN1 D ON M."DocEntry"=D."DocEntry"
	WHERE M."CANCELED"<>'C' AND M."DocDate"<=:edate AND D."BaseType"=15
	AND NOT EXISTS (SELECT 1 FROM :CXL X WHERE X."ObjType"=16 AND X."DocEntry"=M."DocEntry")
	GROUP BY D."BaseType",D."BaseEntry",D."BaseLine";

	SRC=
	SELECT '销售交货' AS "单据类型",CAST(M."ObjType" AS INT) AS "ObjType",M."DocEntry",M."DocNum",D."LineNum",M."DocDate"
	,M."CardCode",M."CardName",M."U_SalOrdType",D."ItemCode",D."Dscription",D."WhsCode",1 AS "Sign"
	,D."Quantity",D."U_InitPrice",D."LineTotal"
	FROM ODLN M JOIN DLN1 D ON M."DocEntry"=D."DocEntry"
	WHERE M."CANCELED"<>'C' AND M."DocDate"<=:edate
	AND NOT EXISTS (SELECT 1 FROM :CXL X WHERE X."ObjType"=15 AND X."DocEntry"=M."DocEntry")
	UNION ALL
	SELECT '销售退货',CAST(M."ObjType" AS INT),M."DocEntry",M."DocNum",D."LineNum",M."DocDate"
	,M."CardCode",M."CardName",M."U_SalOrdType",D."ItemCode",D."Dscription",D."WhsCode",-1
	,D."Quantity",D."U_InitPrice",D."LineTotal"
	FROM ORDN M JOIN RDN1 D ON M."DocEntry"=D."DocEntry"
	WHERE M."CANCELED"<>'C' AND M."DocDate"<=:edate AND IFNULL(D."BaseType",-1)<>15
	AND NOT EXISTS (SELECT 1 FROM :CXL X WHERE X."ObjType"=16 AND X."DocEntry"=M."DocEntry");

	--成本单价：0302 中该单据行的成本
	PRC=
	SELECT "ObjType","DocEntry","LineNum",SUM("Amount")/NULLIF(SUM("Quantity"),0) AS "Price"
	FROM MTC_COST_0302_INVNTDETAIL1
	WHERE "CostCode"='20' AND "ObjType" IN ('15','16')
	GROUP BY "ObjType","DocEntry","LineNum";

	DTL=
	SELECT * FROM (
		SELECT S.*
		,T91."U_CustType" AS "客户类型",T91."U_BusiType" AS "销售业务类型"
		,CASE WHEN S."DocDate"<='2024-12-31' THEN S."U_InitPrice" ELSE P."Price" END AS "成本单价"
		,CASE WHEN S."DocDate"<='2024-12-31' THEN '期初单价' WHEN P."Price" IS NULL THEN '成本未计算' ELSE '已计算' END AS "成本状态"
		,IFNULL(N1."Qty",0) AS "已开票数量",IFNULL(N2."Qty",0) AS "已退货数量"
		,S."Quantity"-IFNULL(N1."Qty",0)-IFNULL(N2."Qty",0) AS "未清数量"
		FROM :SRC S
		JOIN OITM I ON S."ItemCode"=I."ItemCode" AND I."InvntItem"='Y'
		LEFT JOIN (SELECT DISTINCT "Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE") T91 ON S."U_SalOrdType"=T91."Name"
		LEFT JOIN :PRC P ON P."ObjType"=TO_NVARCHAR(S."ObjType") AND P."DocEntry"=S."DocEntry" AND P."LineNum"=S."LineNum"
		LEFT JOIN :NXT N1 ON N1."K"='INV' AND N1."BaseType"=S."ObjType" AND N1."BaseEntry"=S."DocEntry" AND N1."BaseLine"=S."LineNum"
		LEFT JOIN :NXT N2 ON N2."K"='RET' AND N2."BaseType"=S."ObjType" AND N2."BaseEntry"=S."DocEntry" AND N2."BaseLine"=S."LineNum"
		WHERE (S."CardCode" LIKE '%'||:CardCode||'%' OR S."CardName" LIKE '%'||:CardCode||'%' OR :CardCode='')
	) T WHERE ABS(T."未清数量")>0.000001;

	DTL2=
	SELECT T.*
	,CASE WHEN IFNULL(T."销售业务类型",'')='样品销售' THEN 'N' ELSE 'Y' END AS "计入发出商品"
	,T."Sign"*T."未清数量" AS "发出数量"
	,T."Sign"*ROUND(T."未清数量"*T."成本单价",2) AS "发出商品成本"
	FROM :DTL T;

	IF :STYPE=1 THEN
		SELECT :FcCode AS "期间",T."单据类型",T."DocNum" AS "单据号",T."LineNum" AS "行号",T."DocDate" AS "过账日期"
		,T."CardCode" AS "客户编码",T."CardName" AS "客户名称",T."客户类型",T."U_SalOrdType" AS "销售订单类型",T."计入发出商品"
		,T."ItemCode" AS "物料编码",T."Dscription" AS "物料名称",T."WhsCode" AS "仓库"
		,T."Sign"*T."Quantity" AS "单据数量",T."已开票数量",T."已退货数量",T."发出数量"
		,T."成本单价",T."发出商品成本",T."成本状态"
		,T."Sign"*T."LineTotal" AS "单据未税售价金额"
		,DAYS_BETWEEN(T."DocDate",:edate) AS "账龄天数"
		,T."ObjType",T."DocEntry"
		FROM :DTL2 T
		ORDER BY T."CardCode",T."DocDate",T."DocNum",T."LineNum";
	ELSEIF :STYPE=2 THEN
		--140601：不含 AR03/AR04 的余额 = 发出商品；AR03/AR04 当期计提 = 按未清交货转出的成本
		GL=
		SELECT SUM(CASE WHEN IFNULL(H."TransCode",'') NOT IN ('AR03','AR04') THEN J."Debit"-J."Credit" ELSE 0 END) AS "BalExAR"
		,SUM(J."Debit"-J."Credit") AS "Bal"
		--0801 的 AR03/AR04 凭证日期为期末日；只取期末日的计提，避免把上月计提的冲回算进来
		,SUM(CASE WHEN H."TransCode"='AR03' AND J."RefDate"=:edate THEN J."Credit"-J."Debit" ELSE 0 END) AS "AR03"
		,SUM(CASE WHEN H."TransCode"='AR04' AND J."RefDate"=:edate THEN J."Credit"-J."Debit" ELSE 0 END) AS "AR04"
		FROM JDT1 J JOIN OJDT H ON H."TransId"=J."TransId"
		WHERE LEFT(J."Account",6)='140601' AND J."RefDate"<=:edate;
		BZ=
		SELECT SUM(CASE WHEN "计入发出商品"='Y' THEN "发出商品成本" ELSE 0 END) AS "All"
		,SUM(CASE WHEN "计入发出商品"='Y' AND "客户类型"='国内客户' THEN "发出商品成本" ELSE 0 END) AS "GN"
		,SUM(CASE WHEN "计入发出商品"='Y' AND "客户类型"='国外客户' THEN "发出商品成本" ELSE 0 END) AS "GW"
		,SUM(CASE WHEN "计入发出商品"='Y' AND IFNULL("客户类型",'') NOT IN ('国内客户','国外客户') THEN "发出商品成本" ELSE 0 END) AS "NoType"
		,SUM(CASE WHEN "计入发出商品"='N' THEN "发出商品成本" ELSE 0 END) AS "Sample"
		,SUM(CASE WHEN "成本状态"='成本未计算' THEN 1 ELSE 0 END) AS "NoCost"
		FROM :DTL2;
		SELECT 1 AS "序号",'140601 余额（不含 AR03/AR04）/ 发出商品合计' AS "项目",ROUND(G."BalExAR",2) AS "总账",ROUND(B."All",2) AS "业务",ROUND(IFNULL(G."BalExAR",0)-IFNULL(B."All",0),2) AS "差额" FROM :GL G,:BZ B
		UNION ALL
		SELECT 2,'AR03 本期计提（国内）/ 国内客户发出商品',ROUND(G."AR03",2),ROUND(B."GN",2),ROUND(IFNULL(G."AR03",0)-IFNULL(B."GN",0),2) FROM :GL G,:BZ B
		UNION ALL
		SELECT 3,'AR04 本期计提（国外）/ 国外客户发出商品',ROUND(G."AR04",2),ROUND(B."GW",2),ROUND(IFNULL(G."AR04",0)-IFNULL(B."GW",0),2) FROM :GL G,:BZ B
		UNION ALL
		SELECT 4,'没有客户类型的发出商品（AR03/AR04 不会计提）',NULL,ROUND(B."NoType",2),NULL FROM :BZ B
		UNION ALL
		SELECT 5,'140601 期末余额（含 AR03/AR04）',ROUND(G."Bal",2),NULL,NULL FROM :GL G
		UNION ALL
		SELECT 6,'样品销售未开票（不计入发出商品，仅供参考）',NULL,ROUND(B."Sample",2),NULL FROM :BZ B
		UNION ALL
		SELECT 7,'成本未计算的未清行数（先运行当期成本计算）',NULL,B."NoCost",NULL FROM :BZ B
		ORDER BY "序号";
	ELSE
		SELECT :FcCode AS "期间",T."CardCode" AS "客户编码",MAX(T."CardName") AS "客户名称",MAX(T."客户类型") AS "客户类型"
		,COUNT(*) AS "未清行数"
		,SUM(CASE WHEN T."单据类型"='销售交货' THEN T."发出商品成本" ELSE 0 END) AS "交货未开票成本"
		,SUM(CASE WHEN T."单据类型"='销售退货' THEN T."发出商品成本" ELSE 0 END) AS "退货未开贷项成本"
		,SUM(T."发出商品成本") AS "发出商品成本合计"
		,SUM(T."Sign"*T."未清数量"*T."LineTotal"/NULLIF(T."Quantity",0)) AS "对应未税售价"
		,SUM(CASE WHEN T."成本状态"='成本未计算' THEN 1 ELSE 0 END) AS "成本未计算行数"
		,MIN(T."DocDate") AS "最早单据日期"
		FROM :DTL2 T
		WHERE T."计入发出商品"='Y'
		GROUP BY T."CardCode"
		ORDER BY T."CardCode";
	END IF;
END
