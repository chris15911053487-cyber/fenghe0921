-- 修正稿（未部署，用户 2026-10-30，用户自己改库）：MTC_VIEW_ProductDetail 的 ID 3「委外费用收货」。以 0921-数据库同步 版为底稿，只改 ID 3 这一段（其他 ID 原样）。
-- ① 金额按暂估口径（方案 B）：U_InitPrice ≠ 0 → 数量 × U_InitPrice；U_IsPrice='Y' → 数量 × Price；否则 LineTotal，保留 2 位。与 PUR4 借 140802 同一口径。
-- ② 加工费退货按退货日期计入（原来从收货行上扣掉全部退货，不论哪天退的：跨月退货会改动已算过的账期、当期又不计入）；退货金额 = 退货数量 × 收货行暂估单价。
--    退货的取消单经原退货行找到收货行，按取消日期反向（原来只取 CANCELED='N' 的退货）。
-- ③ 不基于收货的加工费退货（物料 X 开头，行上 U_OWORNum 指向生产订单）也计入（原来不计入）。
-- 三段都保留 ID 3、Type 子件，符号同原来（收货为负、退货为正）：0306 取 ID 3、4，CO4013 排除 ID 3，CO401101 按 ≤ 截止日累计，都不用改。
-- 返工单（MTC_OWOR）的加工费不放进这个视图：CO401101 和计算前检查按 OWOREntry 连 OWOR，返工单 DocEntry 与生产订单同号会被错连；
--   改在 0306 里另取，见 fixes/MTC_COST_PROC_0306_WW.sql。
-- 使用这个视图的：MTC_COST_PROC_0306_WW、CAL_1001_CHECK / _DETAIL、MTC_RPT_CO4013、MTC_RPT_CO401101。改完后对它们 ALTER PROCEDURE … RECOMPILE。
-- 库里不支持 CREATE OR REPLACE VIEW 时，像 MTC_VIEW_Document 那次一样在库中原定义上改 ID 3 这一段。
-- 新框架 P20_SUBFEE 不读这个视图，口径相同（金额取 S_AP_MOVE、退货按退货账期、含返工单和不基于收货的退货）。
CREATE OR REPLACE VIEW "FH100"."MTC_VIEW_ProductDetail" AS (((((((((SELECT
	 1 AS "ID" ,
	 '主件' AS "Type" ,
	 '生产收货' AS "BusiType" ,
	 T0."ObjType",
	 T2."DocEntry" AS "OWOREntry" ,
	 T2."DocNum" AS "OWORNum" ,
	 T0."U_TrsName",
	 T0."DocEntry",
	 T0."DocNum" AS "DocNum" ,
	 T1."LineNum",
	 T1."BaseLine",
	 T0."CreateDate",
	 T0."DocDate" ,
	 T1."ItemCode" ,
	 T1."WhsCode" ,
	 T1."Quantity" ,
	 T1."unitMsr" ,
	 T1."StockPrice" AS "Price" ,
	 (T5."SumStock"+T5."PriceDiff"+T5."VarVal") "Amt" 
									FROM OIGN T0 JOIN IGN1 T1 ON T0."DocEntry" = T1."DocEntry" JOIN OWOR T2 ON T2."DocNum" = IFNULL(T1."BaseRef",
	 0) 
									AND T1."BaseType" = '202' 
									AND T1."BaseLine" IS NULL 
									LEFT JOIN OIVL T5 ON T5."TransType" = T0."ObjType" 
									AND T5."CreatedBy" = T0."DocEntry" 
									AND T1."LineNum" = T5."DocLineNum") UNION ALL (SELECT
	 2 AS "ID" ,
	 '子件' AS "Type" ,
	 '生产发料' "BusiType" ,
	 T0."ObjType",
	 T2."DocEntry" AS "OWOREntry" ,
	 T2."DocNum" AS "OWORNum" ,
	 T0."U_TrsName",
	 T0."DocEntry",
	 T0."DocNum" AS "DocNum1" ,
	 T1."LineNum",
	 T1."BaseLine",
	 T0."CreateDate",
	 T0."DocDate" ,
	 T1."ItemCode" ,
	 T1."WhsCode" ,
	 -T1."Quantity" ,
	 T1."unitMsr" ,
	 T1."StockPrice" AS "Price" ,
	 (T5."SumStock"+T5."PriceDiff"+T5."VarVal") "Amt" 
									FROM OIGE T0 JOIN IGE1 T1 ON T0."DocEntry" = T1."DocEntry" JOIN OWOR T2 ON T2."DocNum" = IFNULL(T1."BaseRef",
	 0) 
									AND T1."BaseType" = '202' 
									AND T1."BaseLine" IS NOT NULL JOIN OIVL T5 ON T5."TransType" = T0."ObjType" 
									AND T5."CreatedBy" = T0."DocEntry" 
									AND T1."LineNum" = T5."DocLineNum")) UNION ALL (SELECT
	 1 AS "ID" ,
	 '子件' AS "Type" ,
	 '子件退货' "BusiType" ,
	 T0."ObjType",
	 T2."DocEntry" AS "OWOREntry" ,
	 T2."DocNum" AS "OWORNum" ,
	 T0."U_TrsName",
	 T0."DocEntry",
	 T0."DocNum" AS "DocNum1" ,
	 T1."LineNum",
	 T1."BaseLine",
	 T0."CreateDate",
	 T0."DocDate" ,
	 T1."ItemCode" ,
	 T1."WhsCode" ,
	 T1."Quantity" ,
	 T1."unitMsr" ,
	 T1."StockPrice" AS "Price" ,
	 (T5."SumStock"+T5."PriceDiff"+ T5."VarVal") 
								FROM OIGN T0 JOIN IGN1 T1 ON T0."DocEntry" = T1."DocEntry" JOIN OWOR T2 ON T2."DocNum" = IFNULL(T1."BaseRef",
	 0) 
								AND T1."BaseType" = '202' 
								AND T1."BaseLine" IS NOT NULL JOIN OIVL T5 ON T5."TransType" = T0."ObjType" 
								AND T5."CreatedBy" = T0."DocEntry" 
								AND T1."LineNum" = T5."DocLineNum")) UNION ALL (SELECT
	 2 AS "ID" ,
	 '主件' AS "Type" ,
	 '分拆发货' "BusiType" ,
	 T0."ObjType",
	 T2."DocEntry" AS "OWOREntry",
	 T2."DocNum" AS "OWORNum" ,
	 T0."U_TrsName",
	 T0."DocEntry",
	 T0."DocNum" AS "DocNum1" ,
	 T1."LineNum",
	 T1."BaseLine",
	 T0."CreateDate",
	 T0."DocDate" ,
	 T1."ItemCode" ,
	 T1."WhsCode" ,
	 -T1."Quantity" ,
	 T1."unitMsr" ,
	 T1."StockPrice" AS "Price" ,
	 (T5."SumStock"+T5."PriceDiff"+ T5."VarVal") 
							FROM OIGE T0 JOIN IGE1 T1 ON T0."DocEntry" = T1."DocEntry" JOIN OWOR T2 ON T2."DocNum" = IFNULL(T1."BaseRef",
	 0) 
							AND T1."BaseType" = '202' 
							AND T1."BaseLine" IS NULL JOIN OIVL T5 ON T5."TransType" = T0."ObjType" 
							AND T5."CreatedBy" = T0."DocEntry" 
							AND T1."LineNum" = T5."DocLineNum")) UNION ALL (SELECT
	 2 AS "ID" ,
	 '子件' AS "Type" ,
	 '费用' "BusiType" ,
	 T0."ObjType",
	 T2."DocEntry" AS "OWOREntry" ,
	 T2."DocNum" AS "OWORNum" ,
	 T0."U_TrsName",
	 T0."DocEntry",
	 T0."DocNum" AS "DocNum1" ,
	 T1."LineNum",
	 T1."BaseLine",
	 T0."CreateDate",
	 T0."DocDate" ,
	 T1."ItemCode" ,
	 T1."WhsCode" ,
	 -T1."Quantity" ,
	 T1."unitMsr" ,
	 T1."StockPrice" AS "Price" ,
	 -T1."LineTotal" AS "Amt" 
						FROM OIGE T0 JOIN IGE1 T1 ON T0."DocEntry" = T1."DocEntry" JOIN OWOR T2 ON T2."DocNum" = IFNULL(T1."BaseRef",
	 0) 
						AND T1."BaseType" = '202' 
						AND T1."BaseLine" IS NOT NULL JOIN OITM T3 ON T1."ItemCode"=T3."ItemCode" 
						WHERE 1=1 
						AND T3."InvntItem" = 'N')) UNION ALL (SELECT
	 -- 2026-10-30 修正（用户 2026-10-30 方案 B）：ID 3 拆成三段，都是 ID 3 / 子件：
	 --   a. 加工费收货：按收货日期；金额按暂估口径（U_InitPrice → U_IsPrice='Y' 的 Price × 数量 → LineTotal），不再扣退货
	 --   b. 基于收货的加工费退货：按退货日期单独列出（原来不论哪天退都冲在收货所在账期）；金额 = 退货数量 × 所基于收货行的暂估单价；
	 --      退货的取消单（CANCELED='C'，BaseType=21）经原退货行找到收货行，按取消日期反向
	 --   c. 不基于收货的加工费退货（物料 X 开头）：按行上的 U_OWORNum 找生产订单，金额按退货行自己的暂估口径（原来不计入）
	 --   符号同原来：收货为负、退货为正（0306 取反后加工费为正）。只关联 202 生产订单；返工单的加工费在 0306 里另取（fixes/MTC_COST_PROC_0306_WW.sql）
	 3 AS "ID" ,
	 '子件' AS "Type" ,
	 '委外费用收货' "BusiType" ,
	 T0."ObjType",
	 T3."DocEntry" AS "OWOREntry",
	 T3."DocNum" AS "OWORNum" ,
	 T0."U_TrsName",
	 T0."DocEntry",
	 T0."DocNum" AS "DocNum1" ,
	 T1."LineNum",
	 T1."BaseLine",
	 T0."CreateDate",
	 T0."DocDate" ,
	 T1."ItemCode" ,
	 T1."WhsCode" ,
	 CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END*T1."Quantity" AS "Quantity" ,
	 T1."unitMsr" ,
	 CASE WHEN IFNULL(T1."U_InitPrice", 0)<>0 THEN T1."U_InitPrice" WHEN T1."U_IsPrice"='Y' THEN T1."Price" ELSE T1."LineTotal"/NULLIF(T1."Quantity", 0) END AS "Price" ,
	 CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END*ROUND(CASE WHEN IFNULL(T1."U_InitPrice", 0)<>0 THEN T1."Quantity"*T1."U_InitPrice" WHEN T1."U_IsPrice"='Y' THEN T1."Quantity"*T1."Price" ELSE T1."LineTotal" END, 2) AS "LineTotal"
	FROM OPDN T0 JOIN PDN1 T1 ON T0."DocEntry" = T1."DocEntry"
	 JOIN (SELECT "ObjType", "DocEntry", "BaseRef", SUM("Quantity") AS "Quantity" FROM IGN1 GROUP BY "ObjType", "DocEntry", "BaseRef") T2
	   ON T1."U_BaseType"=T2."ObjType" AND T1."U_BaseEntry"=T2."DocEntry" AND T1."U_OWORNum"=IFNULL(T2."BaseRef", 0)
	 JOIN OWOR T3 ON T3."DocNum" = IFNULL(T2."BaseRef", 0)
	UNION ALL
	SELECT 3, '子件', '委外费用退货', R0."ObjType", T3."DocEntry", T3."DocNum", T0."U_TrsName", R0."DocEntry", R0."DocNum", R1."LineNum", R1."BaseLine",
	 R0."CreateDate", R0."DocDate", R1."ItemCode", R1."WhsCode",
	 CASE WHEN R0."CANCELED"='C' THEN -1 ELSE 1 END*R1."Quantity", R1."unitMsr",
	 CASE WHEN IFNULL(T1."U_InitPrice", 0)<>0 THEN T1."U_InitPrice" WHEN T1."U_IsPrice"='Y' THEN T1."Price" ELSE T1."LineTotal"/NULLIF(T1."Quantity", 0) END,
	 CASE WHEN R0."CANCELED"='C' THEN -1 ELSE 1 END*ROUND(R1."Quantity"*(CASE WHEN IFNULL(T1."U_InitPrice", 0)<>0 THEN T1."U_InitPrice" WHEN T1."U_IsPrice"='Y' THEN T1."Price" ELSE T1."LineTotal"/NULLIF(T1."Quantity", 0) END), 2)
	FROM ORPD R0 JOIN RPD1 R1 ON R0."DocEntry" = R1."DocEntry"
	 LEFT JOIN RPD1 O1 ON R0."CANCELED"='C' AND R1."BaseType"=21 AND O1."DocEntry"=R1."BaseEntry" AND O1."LineNum"=R1."BaseLine"
	 JOIN PDN1 T1 ON IFNULL(O1."BaseType", R1."BaseType")=20 AND T1."DocEntry"=IFNULL(O1."BaseEntry", R1."BaseEntry") AND T1."LineNum"=IFNULL(O1."BaseLine", R1."BaseLine")
	 JOIN OPDN T0 ON T0."DocEntry" = T1."DocEntry"
	 JOIN (SELECT "ObjType", "DocEntry", "BaseRef", SUM("Quantity") AS "Quantity" FROM IGN1 GROUP BY "ObjType", "DocEntry", "BaseRef") T2
	   ON T1."U_BaseType"=T2."ObjType" AND T1."U_BaseEntry"=T2."DocEntry" AND T1."U_OWORNum"=IFNULL(T2."BaseRef", 0)
	 JOIN OWOR T3 ON T3."DocNum" = IFNULL(T2."BaseRef", 0)
	UNION ALL
	SELECT 3, '子件', '委外费用退货', R0."ObjType", T3."DocEntry", T3."DocNum", NULL, R0."DocEntry", R0."DocNum", R1."LineNum", R1."BaseLine",
	 R0."CreateDate", R0."DocDate", R1."ItemCode", R1."WhsCode",
	 CASE WHEN R0."CANCELED"='C' THEN -1 ELSE 1 END*R1."Quantity", R1."unitMsr",
	 CASE WHEN IFNULL(R1."U_InitPrice", 0)<>0 THEN R1."U_InitPrice" WHEN R1."U_IsPrice"='Y' THEN R1."Price" ELSE R1."LineTotal"/NULLIF(R1."Quantity", 0) END,
	 CASE WHEN R0."CANCELED"='C' THEN -1 ELSE 1 END*ROUND(CASE WHEN IFNULL(R1."U_InitPrice", 0)<>0 THEN R1."Quantity"*R1."U_InitPrice" WHEN R1."U_IsPrice"='Y' THEN R1."Quantity"*R1."Price" ELSE R1."LineTotal" END, 2)
	FROM ORPD R0 JOIN RPD1 R1 ON R0."DocEntry" = R1."DocEntry"
	 LEFT JOIN RPD1 O1 ON R0."CANCELED"='C' AND R1."BaseType"=21 AND O1."DocEntry"=R1."BaseEntry" AND O1."LineNum"=R1."BaseLine"
	 JOIN OWOR T3 ON TO_NVARCHAR(T3."DocNum") = TO_NVARCHAR(R1."U_OWORNum")
	WHERE IFNULL(CASE WHEN R0."CANCELED"='C' THEN O1."BaseType" ELSE R1."BaseType" END, -1) <> 20
	 AND R1."ItemCode" LIKE 'X%' AND IFNULL(R1."U_OWORType", '') <> 'MTC_OWOR' )) UNION ALL (SELECT
	 4 AS "ID" ,
	 '子件' AS "Type" ,
	 '委外费用发票暂估差异' "BusiType" ,
	 T0."ObjType",
	 T13."DocEntry" AS "OWOREntry",
	 T13."DocNum" AS "OWORNum" ,
	 T0."U_TrsName",
	 T0."DocEntry",
	 T0."DocNum" AS "DocNum1" ,
	 T1."LineNum",
	 T1."BaseLine",
	 T0."CreateDate",
	 T0."DocDate" ,
	 T1."ItemCode" ,
	 T1."WhsCode" ,
	 0 AS "Quantity" ,
	 T1."unitMsr" ,
	 T1."Price" AS "Price" ,
	 CASE WHEN T0."CANCELED"='C' 
				THEN 1 
				ELSE -1 
				END*(T1."LineTotal"-T1."Quantity"*T2."Price") AS "LineTotal" 
				FROM "OPCH" T0 
				INNER JOIN "PCH1" T1 ON T0."DocEntry"=T1."DocEntry" JOIN (SELECT
	 M."ObjType",
	 D."DocEntry",
	 M."DocNum",
	 D."LineNum",
	 D."U_BaseType",
	 D."U_BaseEntry",
	 D."U_OWORNum" ,
	 CASE WHEN IFNULL(D."U_InitPrice",
	 0)<>0 
					THEN D."U_InitPrice" 
					ELSE D."Price" 
					END AS "Price" ,
	 M2."U_OldSysNo" "OPOROldSN",
	 M."U_OldSysNo" "OPDNOldSN" 
					FROM "OPDN" M JOIN "PDN1" D ON M."DocEntry"=D."DocEntry" 
					LEFT JOIN "POR1" D2 ON D."BaseEntry" =D2."DocEntry" 
					AND D."BaseLine" =D2."LineNum" 
					AND D."BaseType"=D2."ObjType" 
					LEFT JOIN "OPOR" M2 ON D2."DocEntry" =M2."DocEntry" ) T2 ON T1."BaseType"=T2."ObjType" 
				AND T1."BaseEntry"=T2."DocEntry" 
				AND T1."BaseLine"=T2."LineNum" JOIN (SELECT
	 "ObjType",
	 "DocEntry",
	 "BaseRef",
	 SUM("Quantity") AS "Quantity" 
					FROM IGN1 
					GROUP BY "ObjType",
	 "DocEntry",
	 "BaseRef") T12 ON T2."U_BaseType"=T12."ObjType" 
				AND T2."U_BaseEntry"=T12."DocEntry" 
				AND T2."U_OWORNum"=IFNULL(T12."BaseRef",
	 0) JOIN OWOR T13 ON T13."DocNum" = IFNULL(T12."BaseRef",
	 0) 
				WHERE 1=0 
				AND T0."CANCELED"='N')) UNION ALL (SELECT
	 9 AS "ID" ,
	 '日记账分录' AS "Type" ,
	 '日记账分录' "BusiType" ,
	 '30',
	 T0."DocEntry" AS "OWOREntry" ,
	 T0."DocNum" AS "OWORNum" ,
	 '' AS "U_TrsName",
	 T0."TransId",
	 T0."TransId" AS "DocNum1" ,
	 0 as "LineNum",
	 0 AS "BaseLine",
	 T0."CreateDate",
	 T2."RefDate" ,
	 T0."ItemCode" ,
	 T0."Warehouse" ,
	 T0."PlannedQty" ,
	 '' AS "unit" ,
	 0 AS "Price" ,
	 -T3."Amt" AS "Amt" 
			FROM OWOR T0 JOIN OJDT T2 ON T0."TransId"=T2."TransId" JOIN (SELECT
	 "TransId",
	 SUM("Debit"-"Credit") AS "Amt" 
				FROM "JDT1" 
				WHERE "Account"='500101' 
				GROUP BY "TransId") T3 ON T2."TransId"=T3."TransId" 
			WHERE 1=1)) UNION ALL (SELECT
	 10 AS "ID" ,
	 '主件' AS "Type" ,
	 '生产退货' AS "BusiType" ,
	 T0."ObjType",
	 T2."DocEntry" AS "OWOREntry" ,
	 T2."DocNum" AS "OWORNum" ,
	 T0."U_TrsName",
	 T0."DocEntry",
	 T0."DocNum" AS "DocNum" ,
	 T1."LineNum",
	 T1."BaseLine",
	 T0."CreateDate",
	 T0."DocDate" ,
	 T1."ItemCode" ,
	 T1."WhsCode" ,
	 -1*T1."Quantity" ,
	 T1."unitMsr" ,
	 T1."StockPrice" AS "Price" ,
	 -1*(T5."SumStock"+T5."PriceDiff"+T5."VarVal") "Amt" 
		FROM OIGE T0 JOIN IGE1 T1 ON T0."DocEntry" = T1."DocEntry" JOIN OWOR T2 ON T2."DocNum" = IFNULL(T1."U_OWORNum",
	 0) 
		AND T1."U_OWORType" = '202' 
		AND T1."BaseLine" IS NULL 
		LEFT JOIN OIVL T5 ON T5."TransType" = T0."ObjType" 
		AND T5."CreatedBy" = T0."DocEntry" 
		AND T1."LineNum" = T5."DocLineNum" 
		WHERE T0."U_Type"='OWOR1'))