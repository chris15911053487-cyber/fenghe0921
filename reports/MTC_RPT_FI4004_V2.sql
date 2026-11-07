/* =====================================================================
 * 新报表（未部署，用户 2026-11-02）：MTC_RPT_FI4004_V2 销售交退货明细表（替代 MTC_RPT_FI4004，旧版原样见 0921-存储过程/MTC_RPT_FI4004销售交退货明细表）
 * 参数和列同旧版（TYPE 旧版也没有用到，保留），一行 = 一条交货行或销售退货行（含取消单，符号同旧版：交货为正、退货为负）。
 * 与旧 FI4004 的区别：
 *   - 成本取成本报表同一取数规则（MTC_CA_F_RPT_RUN）：承接账期 BOOTSTRAP_FC 及以前取旧框架回填的历史运行，以后取新框架结果
 *     （MTC_CA_S_LINE / R_LINE，同一单据行多条库存变动合计）；成本金额 = −库存变动金额，交货、退货、取消单符号自然正确。
 *     还没有回填的历史账期退回旧 0302（只有总额）；LEGACY_INITPRICE_DATE（默认 2024-12-31）及以前的单据仍按行上 U_InitPrice（同旧版、同 P71；为 0 时取上面的结果）。
 *   - 新增列：成本·材料 / 成本·人工 / 成本·制造（委外加工费并入材料，用户 2026-11-02；三项合计 = 成本金额；历史期是按旧框架完工比例拆分的估算；
 *     U_InitPrice 的行按该行库存变动的构成拆，没有构成时全部记材料；退回旧 0302 的行不拆，为空）、成本来源。
 *   - 已开票数量 / 金额、发票日期、发票号码、财务凭证号只算截止日 Edate 及以前的发票（贷项），截至 Edate 已被取消的不算，
 *     重查历史日期结果不变。
 *   - 未清数量、行状态改为截至 Edate（用户 2026-11-02，原来是单据当前的 OpenCreQty / LineStatus）：口径同 MTC_CA_F_GOODS_OPEN（AR03 / AR04 计提）——
 *     交货 = 数量 − 截至 Edate 有效的发票 − 截至 Edate 有效的基于交货的退货；独立退货（不基于交货）= −(数量 − 截至 Edate 有效的贷项)；
 *     基于交货的退货本身为 0（数量已从交货里扣掉）；取消单、截至 Edate 已被取消的原单为 0。行状态 = 未清数量 ≠ 0 时 O，否则 C。
 *     手工关闭的交货行仍按未清列示（同新框架计提）。
 *   - 成本金额(计提暂估) = 成本金额 × 未清数量 ÷ 发货数量（原来只扣已开票、不扣退货，退货行另按全额冲；改后与 R_GOODS_OUT 数量口径一致），
 *     并新增 计提暂估·材料 / 人工 / 制造（用户 2026-11-02，按同一比例拆，委外并入材料）。料工费三项的分差都挤进材料，三项合计 = 对应总额。
 *   - 成本单价 = 成本金额 ÷ 发货数量（单据单位），不再取 0302 的 Price。
 *   样品税额口径不变（13%，国外客户 × 1.5）。
 * 依赖：新框架 MTC_CA_F_RPT_RUN / MTC_CA_F_PARAM / MTC_CA_S_LINE / MTC_CA_R_LINE（21_reports.sql、07、11 先部署）。
 * 调用：CALL "MTC_RPT_FI4004_V2"(2, '', '2026-10-01', '2026-10-31', '');
 * ===================================================================== */
CREATE PROCEDURE "MTC_RPT_FI4004_V2"
(
 IN TYPE		INT  --1.汇总  2.明细  3.MTC_RPT_FI4013计提坏账（旧版也没有区分，保留参数）
,IN GroupCode	NVARCHAR(50)
,IN Sdate		DATE
,IN Edate		DATE
,IN CardCode	NVARCHAR(100)
)
LANGUAGE SQLSCRIPT
AS
BEGIN
	DECLARE f0 NVARCHAR(10); DECLARE f1 NVARCHAR(10); DECLARE boot NVARCHAR(10); DECLARE legacy DATE;
	-- 日期范围覆盖的账期
	SELECT MIN("Code") INTO f0 FROM "OFPR" WHERE TO_DATE("T_RefDate") >= :Sdate;
	SELECT MAX("Code") INTO f1 FROM "OFPR" WHERE TO_DATE("F_RefDate") <= :Edate;
	f0 := IFNULL(:f0, :f1); f1 := IFNULL(:f1, :f0);
	boot := IFNULL("MTC_CA_F_PARAM"('BOOTSTRAP_FC', :f1), '0000-00');
	legacy := TO_DATE(IFNULL("MTC_CA_F_PARAM"('LEGACY_INITPRICE_DATE', :f1), '1900-01-01'));

	-- 成本：每个账期取成本报表所用的那次运行（新框架 / 历史运行），按单据行合计库存变动金额和四项
	runs = SELECT "FcCode", "RunId" FROM "MTC_CA_F_RPT_RUN"(:f0, :f1) WHERE "RunId" IS NOT NULL;
	nc = SELECT S."ObjType", S."DocEntry", S."LineNum", MAX(R."RunType") AS "RT",
	            SUM(L."Amount") AS "A", SUM(L."MatAmt") AS "M", SUM(L."LabAmt") AS "L", SUM(L."MfgAmt") AS "F", SUM(L."SubAmt") AS "S"
	       FROM :runs U
	       JOIN "MTC_CA_RUN" R ON R."RunId" = U."RunId"
	       JOIN "MTC_CA_S_LINE" S ON S."RunId" = U."RunId" AND S."ObjType" IN ('15', '16')
	       JOIN "MTC_CA_R_LINE" L ON L."RunId" = S."RunId" AND L."LineId" = S."LineId"
	      GROUP BY S."ObjType", S."DocEntry", S."LineNum";
	-- 还没有回填的历史账期：退回旧 0302（只取承接账期及以前，同 P71）
	old = SELECT "ObjType", "DocEntry", "LineNum", SUM("Amount") AS "A"
	        FROM "MTC_COST_0302_INVNTDETAIL1"
	       WHERE "CostCode" = '20' AND "ObjType" IN ('15', '16') AND "FcCode" <= :boot AND "FcCode" BETWEEN :f0 AND :f1
	       GROUP BY "ObjType", "DocEntry", "LineNum";

	-- 截至 Edate 已开票：截至 Edate 已被取消的发票 / 贷项不算（取消单 CANCELED = 'C' 的 BaseType = 13 / 14 指回原单）
	cxl = SELECT DISTINCT 13 AS "ObjType", D."BaseEntry" AS "DocEntry"
	        FROM "OINV" M JOIN "INV1" D ON D."DocEntry" = M."DocEntry"
	       WHERE M."CANCELED" = 'C' AND M."DocDate" <= :Edate AND D."BaseType" = 13
	      UNION
	      SELECT DISTINCT 14, D."BaseEntry"
	        FROM "ORIN" M JOIN "RIN1" D ON D."DocEntry" = M."DocEntry"
	       WHERE M."CANCELED" = 'C' AND M."DocDate" <= :Edate AND D."BaseType" = 14
	      UNION
	      SELECT DISTINCT 15, D."BaseEntry"
	        FROM "ODLN" M JOIN "DLN1" D ON D."DocEntry" = M."DocEntry"
	       WHERE M."CANCELED" = 'C' AND M."DocDate" <= :Edate AND D."BaseType" = 15
	      UNION
	      SELECT DISTINCT 16, D."BaseEntry"
	        FROM "ORDN" M JOIN "RDN1" D ON D."DocEntry" = M."DocEntry"
	       WHERE M."CANCELED" = 'C' AND M."DocDate" <= :Edate AND D."BaseType" = 16;
	-- 截至 Edate 有效的基于交货的退货（扣交货的未清数量，同 MTC_CA_F_GOODS_OPEN）
	ret = SELECT T1."BaseEntry", T1."BaseLine", SUM(T1."Quantity") AS "Quantity"
	        FROM "ORDN" T0
	        JOIN "RDN1" T1 ON T0."DocEntry" = T1."DocEntry"
	       WHERE T0."CANCELED" <> 'C' AND T0."DocDate" <= :Edate AND T1."BaseType" = 15
	         AND NOT EXISTS (SELECT 1 FROM :cxl X WHERE X."ObjType" = 16 AND X."DocEntry" = T0."DocEntry")
	       GROUP BY T1."BaseEntry", T1."BaseLine";
	inv = SELECT T1."BaseType", T1."BaseEntry", T1."BaseLine",
	             SUM(T1."Quantity") AS "Quantity", SUM(T1."GTotal") AS "GTotal", SUM(T1."GTotalFC") AS "GTotalFC",
	             STRING_AGG(LEFT(T0."DocDate", 10), ',') AS "OINVTaxDate", STRING_AGG(T2."Ref2", ',') AS "OINVRef2", STRING_AGG(T2."U_CWNum", ',') AS "OINVCWNum"
	        FROM "OINV" T0
	        JOIN "INV1" T1 ON T0."DocEntry" = T1."DocEntry"
	        LEFT JOIN "OJDT" T2 ON T2."TransId" = T0."TransId"
	       WHERE T0."CANCELED" <> 'C' AND T0."DocDate" <= :Edate AND T1."BaseType" = 15
	         AND NOT EXISTS (SELECT 1 FROM :cxl X WHERE X."ObjType" = 13 AND X."DocEntry" = T0."DocEntry")
	       GROUP BY T1."BaseType", T1."BaseEntry", T1."BaseLine";
	rin = SELECT T1."BaseType", T1."BaseEntry", T1."BaseLine",
	             SUM(T1."Quantity") AS "Quantity", SUM(T1."GTotal") AS "GTotal", SUM(T1."GTotalFC") AS "GTotalFC",
	             STRING_AGG(LEFT(T0."DocDate", 10), ',') AS "OINVTaxDate", STRING_AGG(T2."Ref2", ',') AS "OINVRef2", STRING_AGG(T2."U_CWNum", ',') AS "OINVCWNum"
	        FROM "ORIN" T0
	        JOIN "RIN1" T1 ON T0."DocEntry" = T1."DocEntry"
	        LEFT JOIN "OJDT" T2 ON T2."TransId" = T0."TransId"
	       WHERE T0."CANCELED" <> 'C' AND T0."DocDate" <= :Edate AND T1."BaseType" = 16
	         AND NOT EXISTS (SELECT 1 FROM :cxl X WHERE X."ObjType" = 14 AND X."DocEntry" = T0."DocEntry")
	       GROUP BY T1."BaseType", T1."BaseEntry", T1."BaseLine";

	-- 单据行（除成本、已开票外同旧版）；"_Sg" 交货 / 退货 / 取消单的符号，"_Qty" 单据行数量，"_InitPrice" 行上 U_InitPrice
	ln = SELECT
		'销售交货' AS "类型"
		,CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END AS "_Sg"
		,T1."Quantity" AS "_Qty"
		,T1."U_InitPrice" AS "_InitPrice"
		,T4."Quantity" AS "_InvQty"
		,T0."U_SalOrdType" AS "销售类型"
		,CASE WHEN IFNULL(T94."DeName",'')='' THEN P2."PrcName" ELSE T94."DeName" END AS "部门"
		,T9."U_SupNum" AS "表体订单号"
		,T0."U_SupNum" AS "补充编码"
		,T0."DocNum" AS "单号"
		,T1."LineNum" AS "行号"
		,T0."NumAtCard" AS "参考号"
		,T9.U_APPRDATE AS "审批日期"
		,T0."DocDate" AS "过账日期"
		,T0."DocCur" AS "币种"
		,T0."DocRate" AS "汇率"
		,T0."CardCode" AS "客户编码"
		,T0."CardName" AS "客户名称"
		, T5."U_MnemoniCode" AS "助记码"
		, T84."Country" AS "国家"
		, CASE WHEN T5."U_SysNo"='CRM'THEN IFNULL(T5."U_State",'')||IFNULL(T5."U_City",'') ELSE T85."descript" END AS "销售区域"
		, CASE WHEN T0."U_SysNo"='CRM'THEN T0."U_TER"ELSE T86."Name"END  AS "销售省份"
		, T6."GroupName" AS "客户组"
		, T81."U_ItmsGrpCod2" AS "存货大类"
		, T81."U_RegisteredNo" AS "注册证号"
		, T81."U_RegisteredName" AS "注册名称"
		, T82."Name" AS "核算分类"
		, T0."U_PINO" AS "PI"
		, T1."U_IsCPOD" AS "是否集采"
		, T93."U_BtchNum" AS "批号"
		, T1."ItemCode" AS "物料编号"
		, T1."Dscription" AS "物料名称"
		, T81."U_Specs" AS "规格型号"
		, T8."unitMsr" AS "计量单位"
		, T8."Quantity" AS "订单数量"
		, CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END * T1."Quantity" AS "发货数量"
		, T1."U_BasePrice" AS "折扣前含税单价"
		, CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END * T1."Quantity"*T1."U_BasePrice" AS "折扣前含税金额"
		, CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END * T1."U_Rebate" AS "折扣金额"
		, CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END * T1."DistribSum" AS "运保费（本币）"
		, CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END * T1."DstrbSumFC" AS "运保费（外币）"
		, T1."Price" AS "未税单价"
		, T1."PriceAfVAT" AS "含税单价"
		, CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END * T1."LineTotal" AS "未税金额（本币）"
		, CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END * T1."VatSum" AS "税额（本币）"
		, CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END * T1."GTotal"  AS "含税金额（本币）"
		, CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END * T1."TotalFrgn" AS "未税金额（外币）"
		, CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END * T1."VatSumFrgn" AS "税额（外币）"
		, CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END * T1."GTotalFC" AS "含税金额（外币）"
		, CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END * T4."Quantity" AS "已开票数量"
		, CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END * T4."GTotal" AS "已开票含税金额(本币)"
		, CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END * T4."GTotalFC" AS "已开票含税金额(外币)"
		, P1."PrcCode" AS "成本部门编码"
		, P1."PrcName" AS "成本部门名称"
		, CASE WHEN T0."U_SysNo"='CRM'THEN T0."U_SlpCode"ELSE T83."SlpName"END  AS "业务员"
		, T0."U_Address" AS "实际出货地址"
		, T0."U_CntctName" AS "联系人"
		, T0."U_PhoneNum" AS "联系电话"
		, T87."WhsName" AS "仓库"
		, T0."Comments" AS "备注"
		, T9."Comments" AS "订单备注"
		,T0."TransId" AS "交易编码"
		, T1."AcctCode" AS "收入科目"
		, T1."CogsAcct" AS "成本科目"
		,T0."ObjType"
		,T0."DocEntry"
		,T1."LineNum" AS "_LineNum"
		, T9."DocNum"  AS "订单/交货单号"
		,T0."U_HospName" AS "医院"
		,T0."U_OldSysNo" AS "老系统单号"
		,T91."U_BusiType" AS "_BusiType"
		,T91."U_CustType" AS "_CustType"
		,T92."U_Price" AS "_PtPrice"
		,T0."U_BLNo" AS "提单号/物流单号"
		,T9."U_PriceTerm" AS "贸易条款"
		,T4."OINVTaxDate" AS "单据日期"
		,T4."OINVRef2" AS"发票号码"
		,T4."OINVCWNum"  AS"财务凭证号"
		-- 截至 Edate 未清（2026-11-02，原来是当前 OpenCreQty / LineStatus）
		,CASE WHEN T0."CANCELED"='C' OR XC."DocEntry" IS NOT NULL THEN 0
		      ELSE T1."Quantity" - IFNULL(T4."Quantity",0) - IFNULL(TR."Quantity",0) END AS "未清数量"
		,CASE WHEN T0."CANCELED"='C' OR XC."DocEntry" IS NOT NULL
		        OR ABS(T1."Quantity" - IFNULL(T4."Quantity",0) - IFNULL(TR."Quantity",0)) <= 0.000001 THEN 'C' ELSE 'O' END AS "行状态"
		,T8."U_SalOrdType"  AS "订单类型"
		,T8."U_SamPacType"  AS "样品包装"
		,T8."U_SamUSE"  	AS "样品用途"
		,T8."U_STState" 	AS "是否灭菌"
		FROM ODLN T0
		INNER JOIN DLN1 T1 ON T0."DocEntry" = T1."DocEntry"
		LEFT JOIN :inv T4 ON T4."BaseType"=T0."ObjType" AND T4."BaseEntry"=T1."DocEntry" AND T4."BaseLine"=T1."LineNum"
		LEFT JOIN :ret TR ON TR."BaseEntry"=T1."DocEntry" AND TR."BaseLine"=T1."LineNum"
		LEFT JOIN :cxl XC ON XC."ObjType"=15 AND XC."DocEntry"=T0."DocEntry"
		LEFT JOIN OPRC P1 ON T1."OcrCode"=P1."PrcCode"
		LEFT JOIN OPRC P2 ON T0."U_OcrCode"=P2."PrcCode"
		LEFT JOIN "OCRD" T5 ON T0."CardCode"=T5."CardCode"
		LEFT JOIN "OCRG" T6 ON T5."GroupCode"=T6."GroupCode"
		LEFT JOIN RDR1 T8 ON T1."BaseEntry" =T8."DocEntry" AND T1."BaseLine" =T8."LineNum"
		LEFT JOIN ORDR T9 ON T8."DocEntry" =T9."DocEntry"
		LEFT JOIN OITM T81 ON T1."ItemCode"=T81."ItemCode"
		LEFT JOIN "@MTC_FINTYPE" T82 ON T81."U_FinType"=T82."Code"
		LEFT JOIN OSLP T83 ON T0."SlpCode"=T83."SlpCode"
		LEFT JOIN (SELECT DISTINCT U0."CardCode",U1."Name" AS "Country"
					FROM CRD1 U0
					INNER JOIN OCRY U1 ON U0."Country"=U1."Code"
					WHERE U0."AdresType"='S') T84 ON T0."CardCode"=T84."CardCode"
		LEFT JOIN OTER T85 ON T5."Territory"=T85."territryID"
		LEFT JOIN OCST T86 ON T0."U_TER"=T86."Code"
		LEFT JOIN OWHS T87 ON T1."WhsCode"=T87."WhsCode"
		LEFT JOIN OFPR T90 ON T90."Code"=LEFT(T0."DocDate",7)
		LEFT JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE") T91 ON T0."U_SalOrdType"=T91."Name"
		LEFT JOIN (SELECT T0."U_FcCode",T1."U_ItemCode",MAX(T1."U_Price") AS "U_Price"
					FROM "@MTC_PTPRICE" T0
					INNER JOIN "@MTC_PTPRICE1" T1 ON T0."DocEntry"=T1."DocEntry"
					WHERE T0."Canceled"='N' GROUP BY T0."U_FcCode",T1."U_ItemCode") T92 ON T92."U_FcCode"=T90."Code" AND T1."ItemCode"=T92."U_ItemCode"
		LEFT JOIN (	SELECT T0."DocEntry",T0."LineNum",STRING_AGG(T0."U_BtchNum",',') "U_BtchNum"
					FROM (
							SELECT T0."DocEntry",T0."LineNum",IFNULL(T3."U_BtchNum",T5."U_BtchNum") "U_BtchNum"
							FROM DLN1 T0
							LEFT JOIN OITL T1 ON T1."ApplyEntry"=T0."DocEntry" AND  T1."ApplyType" ='15' AND T1."ApplyLine" =T0."LineNum" AND T1."LocCode"=T0."WhsCode"
							INNER JOIN ITL1 T2 ON T1."LogEntry" = T2."LogEntry"
							LEFT JOIN OBTN T3 ON T3."AbsEntry" =T2."MdAbsEntry" AND T1."ManagedBy" = 10000044
							LEFT JOIN OSRN T5 ON T5."AbsEntry" =T2."MdAbsEntry" AND T1."ManagedBy" = 10000045
							GROUP BY T0."DocEntry",T0."LineNum",IFNULL(T3."U_BtchNum",T5."U_BtchNum")
						  )T0
					GROUP BY T0."DocEntry",T0."LineNum"
					)T93 ON T93."DocEntry"=T1."DocEntry" AND T93."LineNum"=T1."LineNum"
		LEFT JOIN "MTC_VC_OUSR" T94 ON T94."USERCODE"=T9."U_Creator"
		WHERE 1=1
		--AND T0."CANCELED"='N' chris.li 2025.6.20  因为5月份有单据 取消到6月份
		AND (T5."GroupCode"=:GroupCode OR :GroupCode='')
		AND T0."DocDate" BETWEEN :Sdate AND :Edate

		UNION ALL

		SELECT
		'销售退货' AS "类型"
		,CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END AS "_Sg"
		,T1."Quantity" AS "_Qty"
		,T1."U_InitPrice" AS "_InitPrice"
		,T7."Quantity" AS "_InvQty"
		,T0."U_SalOrdType" AS "销售类型"
		,P2."PrcName" AS "部门"
		,T1."U_ORDRSupNum" AS "表体订单号"
		,T0."U_SupNum" AS "补充编码"
		,T0."DocNum" AS "单号"
		,T1."LineNum" AS "行号"
		,T0."NumAtCard" AS "参考号"
		,T20.U_APPRDATE AS "审批日期"
		,T0."DocDate" AS "过账日期"
		,T0."DocCur" AS "币种"
		,T0."DocRate" AS "汇率"
		,T0."CardCode" AS "客户编码"
		,T0."CardName" AS "客户名称"
		, T5."U_MnemoniCode" AS "助记码"
		, T84."Country" AS "国家"
		, CASE WHEN T5."U_SysNo"='CRM'THEN IFNULL(T5."U_State",'')||IFNULL(T5."U_City",'') ELSE T85."descript" END AS "销售区域"
		, CASE WHEN T0."U_SysNo"='CRM'THEN T0."U_TER"ELSE T86."Name"END  AS "销售省份"
		, T6."GroupName" AS "客户组"
		, T81."U_ItmsGrpCod2" AS "存货大类"
		, T81."U_RegisteredNo" AS "注册证号"
		, T81."U_RegisteredName" AS "注册名称"
		, T82."Name" AS "核算分类"
		, T0."U_PINO" AS "PI"
		, T1."U_IsCPOD" AS "是否集采"
		, T93."U_BtchNum" AS "批号"
		, T1."ItemCode" AS "物料编号"
		, T1."Dscription" AS "物料名称"
		, T81."U_Specs" AS "规格型号"
		, T1."unitMsr" AS "计量单位"
		, 0 AS "订单数量"
		, CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END * T1."Quantity" AS "发货数量"
		, T1."U_BasePrice" AS "折扣前含税单价"
		, CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END * T1."Quantity"*T1."U_BasePrice" AS "折扣前含税金额"
		, CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END * T1."U_Rebate" AS "折扣金额"
		, CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END * T1."DistribSum" AS "运保费（本币）"
		, CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END * T1."DstrbSumFC" AS "运保费（外币）"
		, T1."Price" AS "未税单价"
		, T1."PriceAfVAT" AS "含税单价"
		, CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END * T1."LineTotal" AS "未税金额（本币）"
		, CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END * T1."VatSum" AS "税额（本币）"
		, CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END * T1."GTotal"  AS "含税金额（本币）"
		, CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END * T1."TotalFrgn" AS "未税金额（外币）"
		, CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END * T1."VatSumFrgn" AS "税额（外币）"
		, CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END * T1."GTotalFC" AS "含税金额（外币）"
		, CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END * T7."Quantity" AS "已开票数量"
		, CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END * T7."GTotal" AS "已开票含税金额(本币)"
		, CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END * T7."GTotalFC" AS "已开票含税金额(外币)"
		,P1."PrcCode" AS "成本部门编码"
		,P1."PrcName" AS "成本部门名称"
		, CASE WHEN T0."U_SysNo"='CRM'THEN T0."U_SlpCode"ELSE T83."SlpName"END  AS "业务员"
		, T0."U_Address" AS "实际出货地址"
		, T0."U_CntctName" AS "联系人"
		, T0."U_PhoneNum" AS "联系电话"
		, T87."WhsName" AS "仓库"
		--, T0."Comments" AS "备注"
		, '' AS "备注"
		, '' AS "订单备注"
		,T0."TransId" AS "交易编码"
		,T1."AcctCode" AS "收入科目"
		,T1."CogsAcct" AS "成本科目"
		,T0."ObjType"
		,T0."DocEntry"
		,T1."LineNum" AS "_LineNum"
		,T11."DocNum"  AS "订单/交货单号"
		,T0."U_HospName" AS "医院"
		,T0."U_OldSysNo" AS "老系统单号"
		,T91."U_BusiType" AS "_BusiType"
		,T91."U_CustType" AS "_CustType"
		,T92."U_Price" AS "_PtPrice"
		,T0."U_BLNo" AS "提单号/物流单号"
		,T20."U_PriceTerm" AS "贸易条款"
		,T7."OINVTaxDate" AS "单据日期"
		,T7."OINVRef2" AS"发票号码"
		,T7."OINVCWNum"  AS"财务凭证号"
		-- 截至 Edate 未清（2026-11-02）：基于交货的退货已从交货里扣掉，本行为 0
		,CASE WHEN T0."CANCELED"='C' OR XC."DocEntry" IS NOT NULL OR IFNULL(T1."BaseType",-1)=15 THEN 0
		      ELSE -1*(T1."Quantity" - IFNULL(T7."Quantity",0)) END AS "未清数量"
		,CASE WHEN T0."CANCELED"='C' OR XC."DocEntry" IS NOT NULL OR IFNULL(T1."BaseType",-1)=15
		        OR ABS(T1."Quantity" - IFNULL(T7."Quantity",0)) <= 0.000001 THEN 'C' ELSE 'O' END AS "行状态"
		,T19."U_SalOrdType"  AS "订单类型"
		,T19."U_SamPacType"  AS "样品包装"
		,T19."U_SamUSE"  	AS "样品用途"
		,T19."U_STState" 	AS "是否灭菌"
		FROM ORDN T0
		INNER JOIN RDN1 T1 ON T0."DocEntry" = T1."DocEntry"
		LEFT JOIN OPRC P1 ON T1."OcrCode"=P1."PrcCode"
		LEFT JOIN OPRC P2 ON T0."U_OcrCode"=P2."PrcCode"
		LEFT JOIN "OCRD" T5 ON T0."CardCode"=T5."CardCode"
		LEFT JOIN "OCRG" T6 ON T5."GroupCode"=T6."GroupCode"
		LEFT JOIN :rin T7 ON T7."BaseType"=T0."ObjType" AND T7."BaseEntry"=T1."DocEntry" AND T7."BaseLine"=T1."LineNum"
		LEFT JOIN :cxl XC ON XC."ObjType"=16 AND XC."DocEntry"=T0."DocEntry"
		LEFT JOIN RRR1 T9 ON T1."BaseEntry" =T9."DocEntry" AND T1."BaseLine" =T9."LineNum"
		LEFT JOIN DLN1 T10 ON T9."BaseEntry" =T10."DocEntry" AND T9."BaseLine" =T10."LineNum"
		LEFT JOIN ODLN T11 ON T10."DocEntry" =T11."DocEntry"
		LEFT JOIN RDR1 T19 ON T10."BaseType"=T19."ObjType" AND T10."BaseEntry"=T19."DocEntry" AND T10."BaseLine" =T19."LineNum" 	--20260203新增
		LEFT JOIN ORDR T20 ON T10."BaseType"=T20."ObjType" AND T10."BaseEntry"=T20."DocEntry"
		LEFT JOIN OITM T81 ON T1."ItemCode"=T81."ItemCode"
		LEFT JOIN "@MTC_FINTYPE" T82 ON T81."U_FinType"=T82."Code"
		LEFT JOIN OSLP T83 ON T0."SlpCode"=T83."SlpCode"
		LEFT JOIN (SELECT DISTINCT U0."CardCode",U1."Name" AS "Country"
					FROM CRD1 U0
					INNER JOIN OCRY U1 ON U0."Country"=U1."Code"
					WHERE U0."AdresType"='S') T84 ON T0."CardCode"=T84."CardCode"
		LEFT JOIN OTER T85 ON T5."Territory"=T85."territryID"
		LEFT JOIN OCST T86 ON T0."U_TER"=T86."Code"
		LEFT JOIN OWHS T87 ON T1."WhsCode"=T87."WhsCode"
		LEFT JOIN OFPR T90 ON T90."Code"=LEFT(T0."DocDate",7)
		LEFT JOIN (SELECT DISTINCT"Name","U_CustType","U_BusiType" FROM "@MTC_SALORDTYPE") T91 ON T0."U_SalOrdType"=T91."Name"
		LEFT JOIN (SELECT T0."U_FcCode",T1."U_ItemCode",MAX(T1."U_Price") AS "U_Price"
					FROM "@MTC_PTPRICE" T0
					INNER JOIN "@MTC_PTPRICE1" T1 ON T0."DocEntry"=T1."DocEntry"
					WHERE T0."Canceled"='N' GROUP BY T0."U_FcCode",T1."U_ItemCode") T92 ON T92."U_FcCode"=T90."Code" AND T1."ItemCode"=T92."U_ItemCode"
		LEFT JOIN (	SELECT T0."DocEntry",T0."LineNum",STRING_AGG(T0."U_BtchNum",',') "U_BtchNum"
					FROM (
							SELECT T0."DocEntry",T0."LineNum",IFNULL(T3."U_BtchNum",T5."U_BtchNum") "U_BtchNum"
							FROM RDN1 T0
							LEFT JOIN OITL T1 ON T1."ApplyEntry"=T0."DocEntry" AND  T1."ApplyType" ='16' AND T1."ApplyLine" =T0."LineNum" AND T1."LocCode"=T0."WhsCode"
							INNER JOIN ITL1 T2 ON T1."LogEntry" = T2."LogEntry"
							LEFT JOIN OBTN T3 ON T3."AbsEntry" =T2."MdAbsEntry" AND T1."ManagedBy" = 10000044
							LEFT JOIN OSRN T5 ON T5."AbsEntry" =T2."MdAbsEntry" AND T1."ManagedBy" = 10000045
							GROUP BY T0."DocEntry",T0."LineNum",IFNULL(T3."U_BtchNum",T5."U_BtchNum")
						  )T0
					GROUP BY T0."DocEntry",T0."LineNum"
					)T93 ON T93."DocEntry"=T1."DocEntry" AND T93."LineNum"=T1."LineNum"
		WHERE 1=1
		--AND T0."CANCELED"='N' chris.li 2025.6.20  因为5月份有单据 取消到6月份
		AND (T5."GroupCode"=:GroupCode OR :GroupCode='')
		AND T0."DocDate" BETWEEN :Sdate AND :Edate;

	-- 成本：U_InitPrice（LEGACY_INITPRICE_DATE 及以前）→ 新框架 / 历史运行 → 旧 0302（未回填）；成本金额与发货数量同号
	ct = SELECT L.*,
	            CASE WHEN L."过账日期" <= :legacy AND IFNULL(L."_InitPrice", 0) <> 0 THEN 'INIT'
	                 WHEN N."A" IS NOT NULL THEN CASE WHEN N."RT" = 'H' THEN 'HIST' ELSE 'NEW' END
	                 WHEN O."A" IS NOT NULL THEN 'OLD' END AS "_Src",
	            CASE WHEN L."过账日期" <= :legacy AND IFNULL(L."_InitPrice", 0) <> 0 THEN L."_Sg" * L."_Qty" * L."_InitPrice"
	                 WHEN N."A" IS NOT NULL THEN -N."A"
	                 WHEN O."A" IS NOT NULL THEN -O."A" END AS "_Cost",
	            N."A" AS "_NA", N."M" AS "_NM", N."L" AS "_NL", N."F" AS "_NF", N."S" AS "_NS"
	       FROM :ln L
	       LEFT JOIN :nc N ON N."ObjType" = TO_NVARCHAR(L."ObjType") AND N."DocEntry" = L."DocEntry" AND N."LineNum" = L."_LineNum"
	       LEFT JOIN :old O ON O."ObjType" = TO_NVARCHAR(L."ObjType") AND O."DocEntry" = L."DocEntry" AND O."LineNum" = L."_LineNum";
	-- 料工费三项（委外并入材料，用户 2026-11-02）：新框架 / 历史运行按本行库存变动的构成；U_InitPrice 的行有构成时按构成拆、没有时全部记材料；旧 0302 不拆（为空）
	-- "_R" = 截至 Edate 未清数量 ÷ 发货数量，计提暂估按它拆
	cs = SELECT C.*,
	            CASE WHEN C."_Src" IN ('NEW', 'HIST') THEN -C."_NL"
	                 WHEN C."_Src" = 'INIT' THEN CASE WHEN IFNULL(C."_NA", 0) <> 0 THEN C."_Cost" * C."_NL" / C."_NA" ELSE 0 END END AS "_CL",
	            CASE WHEN C."_Src" IN ('NEW', 'HIST') THEN -C."_NF"
	                 WHEN C."_Src" = 'INIT' THEN CASE WHEN IFNULL(C."_NA", 0) <> 0 THEN C."_Cost" * C."_NF" / C."_NA" ELSE 0 END END AS "_CF",
	            IFNULL(C."未清数量" / NULLIF(C."发货数量", 0), 0) AS "_R"
	       FROM :ct C;

	SELECT T0."类型" AS "交货性质"
	,T0."ObjType"
	,T0."DocEntry"
	,T0."补充编码"
	,T0."表体订单号"
	,T0."老系统单号"
	,T0."单号"
	,T0."行号"
	,T0."参考号"
	,T0."审批日期"
	,T0."过账日期"
	,T0."销售类型"
	,T0."部门"
	,T0."客户编码"
	,T0."客户名称"
	,T0."助记码"
	,IFNULL(T0."国家",'中国') "国家"
	,T0."销售区域"
	,T0."销售省份"
	,T0."客户组"
	,T0."PI"
	,T0."是否集采"
	,T0."存货大类"
	,T0."核算分类"
	,T0."注册证号"
	,T0."注册名称"
	,T0."物料编号"
	,T0."物料名称"
	,T0."医院"
	,T0."规格型号"
	,T0."计量单位"
	,T0."批号"
	,T0."单据日期" AS "发票日期"
	,T0."发票号码"
	,T0."财务凭证号"
	,T0."订单数量"
	,T0."发货数量"
	,T0."折扣前含税单价"
	,T0."折扣前含税金额"
	,T0."折扣金额"
	,T0."运保费（外币）"
	,T0."运保费（本币）"
	,T0."币种"
	,CAST(CAST(T0."汇率" AS DECIMAL(19,4)) AS NVARCHAR(30)) "汇率"
	,T0."未税单价"
	,T0."含税单价"
	,T0."未税金额（外币）"
	,T0."税额（外币）"
	,T0."含税金额（外币）"
	,T0."未税金额（本币）"
	,T0."税额（本币）"
	,T0."含税金额（本币）"
	,T0."已开票数量"
	,T0."已开票含税金额(外币)"
	,T0."已开票含税金额(本币)"
	,CAST(CAST(T0."_Cost" / NULLIF(T0."发货数量", 0) AS DECIMAL(19,6)) AS NVARCHAR(30)) AS "成本单价"
	,CAST(ROUND(T0."_Cost", 2) AS DECIMAL(19,2)) AS "成本金额"
	-- 料工费三项（委外并入材料，用户 2026-11-02）：分差挤进材料，三项合计 = 成本金额；旧 0302 不拆（为空）
	,CAST(CASE WHEN T0."_CL" IS NOT NULL THEN ROUND(T0."_Cost", 2) - ROUND(T0."_CL", 2) - ROUND(T0."_CF", 2) END AS DECIMAL(19,2)) AS "成本·材料"
	,CAST(ROUND(T0."_CL", 2) AS DECIMAL(19,2)) AS "成本·人工"
	,CAST(ROUND(T0."_CF", 2) AS DECIMAL(19,2)) AS "成本·制造"
	,CASE T0."_Src" WHEN 'NEW' THEN '新框架'
	                WHEN 'HIST' THEN '历史运行（旧框架回填，料工费按完工比例估算）'
	                WHEN 'INIT' THEN '行上指定单价 U_InitPrice'
	                WHEN 'OLD' THEN '旧框架 0302（该期未回填，不分料工费）'
	                ELSE '没有成本结果（不在成本计算范围或该期未计算）' END AS "成本来源"
	-- 样品税额同旧版：国内 = 样品价 × 数量 ÷ 1.13 × 0.13；国外 = 成本单价 × 数量 × 1.5 × 0.13（成本单价改取本报表的成本单价）
	,T0."_Sg" * ROUND(CASE WHEN T0."_BusiType"='样品销售' AND T0."_CustType"='国内客户' THEN (IFNULL(T0."_PtPrice",0)*T0."_Qty"/1.13*0.13)
	                       WHEN T0."_BusiType"='样品销售' AND T0."_CustType"='国外客户' THEN (IFNULL(T0."_Cost" / NULLIF(T0."发货数量", 0), 0)*T0."_Qty"*1.5*0.13)
	                       ELSE 0 END,2) AS "样品税额"
	,T0."成本部门编码"
	,T0."成本部门名称"
	,T0."业务员"
	,T0."实际出货地址"
	,T0."联系人"
	,T0."联系电话"
	,T0."仓库"
	,T0."备注"
	,T0."订单备注"
	,T0."交易编码"
	,T0."收入科目"
	,T0."成本科目"
	,T0."提单号/物流单号"
	,T0."贸易条款"
	,T0."未清数量"
	,T0."行状态"
	,T0."订单类型"
	,T0."样品包装"
	,T0."样品用途"
	,T0."是否灭菌"
	-- 截至 Edate 未清部分的成本 = 成本 × 未清数量 ÷ 发货数量（2026-11-02 改：未清扣发票和基于交货的退货，同 F_GOODS_OPEN）；同一比例拆料工费，分差挤进材料
	,CAST(ROUND(T0."_Cost" * T0."_R", 2) AS DECIMAL(19,2)) AS "成本金额(计提暂估)"
	,CAST(CASE WHEN T0."_CL" IS NOT NULL THEN ROUND(T0."_Cost" * T0."_R", 2) - ROUND(T0."_CL" * T0."_R", 2) - ROUND(T0."_CF" * T0."_R", 2) END AS DECIMAL(19,2)) AS "计提暂估·材料"
	,CAST(ROUND(T0."_CL" * T0."_R", 2) AS DECIMAL(19,2)) AS "计提暂估·人工"
	,CAST(ROUND(T0."_CF" * T0."_R", 2) AS DECIMAL(19,2)) AS "计提暂估·制造"
		FROM :cs T0
		WHERE (T0."客户编码" LIKE '%'||:CardCode||'%' OR T0."客户名称" LIKE '%'||:CardCode||'%' OR T0."助记码" LIKE '%'||:CardCode||'%' OR :CardCode='')
		ORDER BY T0."类型",T0."单号" DESC;
END
