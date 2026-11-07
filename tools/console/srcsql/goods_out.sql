/* =====================================================================
 * 发出商品 · 取数 SQL（只读，直接从 B1 单据算）
 *
 * 结果：截至期末“已交货、未开票”的每一行（交货行，或不基于交货的销售退货行），
 *       列出交货数量、已开票、已退货、未清数量，以及客户类型、是否样品。
 * 对应：新框架函数 MTC_CA_F_GOODS_OPEN（期末日）→ P71 写入结果表 MTC_CA_R_GOODS_OUT。
 *       两边口径相同，执行台“与计算结果比对”逐行核对。旧模块的对应：0801 AR03 / AR04、reports/MTC_RPT_CO6103。
 * 不在本语句里的：单位成本和成本金额。单位成本按优先级取：
 *   LEGACY_INITPRICE_DATE 及以前的单据取行上 U_InitPrice → 本次计算的出库单价 → 以前账期新框架结果 → 旧 0302（只取 BOOTSTRAP_FC 及以前，2026-11-02）；
 *   成本金额 = 行金额 − 已开票 / 已退货冲回的金额（尾差在全部消耗完时清掉），见过程 MTC_CA_P71_SALES。
 * 用法：第 ① 段的参数换成账期，例如 '2026-09'，整段执行。
 *       排查时可以把最后的 SELECT 换成 SELECT * FROM 某一段（如 CANCELLED、CONSUMED），看中间结果。
 * ===================================================================== */
WITH
-- ① 账期：只用期末日 D1（截至期末）
P AS (
    SELECT O."Code" AS "FC", TO_DATE(O."T_RefDate") AS "D1"
      FROM "OFPR" O
     WHERE O."Code" = ?
),

-- ② 客户类型和样品：销售订单类型 @MTC_SALORDTYPE（按单据表头 U_SalOrdType 对应 Name），
--    U_CustType 是国内 / 国外（决定 AR03 / AR04），U_BusiType = '样品销售' 的是样品
SAL_TYPE AS (
    SELECT "Name", MAX("U_CustType") AS "CustType", MAX("U_BusiType") AS "BusiType"
      FROM "@MTC_SALORDTYPE" GROUP BY "Name"
),

-- ③ 截至期末已被取消的原单：取消单（CANCELED = 'C'）的 BaseType / BaseEntry 指回原单
CANCELLED AS (
    SELECT DISTINCT D."BaseType" AS "ObjType", D."BaseEntry" AS "DocEntry"
      FROM "ODLN" M JOIN "DLN1" D ON M."DocEntry" = D."DocEntry" CROSS JOIN P
     WHERE M."CANCELED" = 'C' AND M."DocDate" <= P."D1" AND D."BaseType" = 15
    UNION
    SELECT DISTINCT D."BaseType", D."BaseEntry"
      FROM "ORDN" M JOIN "RDN1" D ON M."DocEntry" = D."DocEntry" CROSS JOIN P
     WHERE M."CANCELED" = 'C' AND M."DocDate" <= P."D1" AND D."BaseType" = 16
    UNION
    SELECT DISTINCT D."BaseType", D."BaseEntry"
      FROM "OINV" M JOIN "INV1" D ON M."DocEntry" = D."DocEntry" CROSS JOIN P
     WHERE M."CANCELED" = 'C' AND M."DocDate" <= P."D1" AND D."BaseType" = 13
    UNION
    SELECT DISTINCT D."BaseType", D."BaseEntry"
      FROM "ORIN" M JOIN "RIN1" D ON M."DocEntry" = D."DocEntry" CROSS JOIN P
     WHERE M."CANCELED" = 'C' AND M."DocDate" <= P."D1" AND D."BaseType" = 14
),

-- ④ 截至期末有效的后续单据（未取消、也没有在期末前被取消），按来源行汇总数量：
--    INV = 基于交货的应收发票（13）、基于独立退货的应收贷项（14）；RET = 基于交货的销售退货（16）
CONSUMED AS (
    SELECT D."BaseType", D."BaseEntry", D."BaseLine", SUM(D."Quantity") AS "Qty", 'INV' AS "K"
      FROM "OINV" M JOIN "INV1" D ON M."DocEntry" = D."DocEntry" CROSS JOIN P
     WHERE M."CANCELED" <> 'C' AND M."DocDate" <= P."D1" AND D."BaseType" = 15
       AND NOT EXISTS (SELECT 1 FROM CANCELLED X WHERE X."ObjType" = 13 AND X."DocEntry" = M."DocEntry")
     GROUP BY D."BaseType", D."BaseEntry", D."BaseLine"
    UNION ALL
    SELECT D."BaseType", D."BaseEntry", D."BaseLine", SUM(D."Quantity"), 'INV'
      FROM "ORIN" M JOIN "RIN1" D ON M."DocEntry" = D."DocEntry" CROSS JOIN P
     WHERE M."CANCELED" <> 'C' AND M."DocDate" <= P."D1" AND D."BaseType" = 16
       AND NOT EXISTS (SELECT 1 FROM CANCELLED X WHERE X."ObjType" = 14 AND X."DocEntry" = M."DocEntry")
     GROUP BY D."BaseType", D."BaseEntry", D."BaseLine"
    UNION ALL
    SELECT D."BaseType", D."BaseEntry", D."BaseLine", SUM(D."Quantity"), 'RET'
      FROM "ORDN" M JOIN "RDN1" D ON M."DocEntry" = D."DocEntry" CROSS JOIN P
     WHERE M."CANCELED" <> 'C' AND M."DocDate" <= P."D1" AND D."BaseType" = 15
       AND NOT EXISTS (SELECT 1 FROM CANCELLED X WHERE X."ObjType" = 16 AND X."DocEntry" = M."DocEntry")
     GROUP BY D."BaseType", D."BaseEntry", D."BaseLine"
),

-- ⑤ 发出行：截至期末、未取消的交货行（方向 +），和不基于交货的销售退货行（方向 −，Sign = -1）
SRC_LINE AS (
    SELECT '15' AS "ObjType", M."DocEntry", M."DocNum", D."LineNum", TO_DATE(M."DocDate") AS "DocDate", M."CardCode", M."U_SalOrdType",
           D."ItemCode", 1 AS "Sign", D."Quantity"
      FROM "ODLN" M JOIN "DLN1" D ON M."DocEntry" = D."DocEntry" CROSS JOIN P
     WHERE M."CANCELED" <> 'C' AND M."DocDate" <= P."D1"
       AND NOT EXISTS (SELECT 1 FROM CANCELLED X WHERE X."ObjType" = 15 AND X."DocEntry" = M."DocEntry")
    UNION ALL
    SELECT '16', M."DocEntry", M."DocNum", D."LineNum", TO_DATE(M."DocDate"), M."CardCode", M."U_SalOrdType",
           D."ItemCode", -1, D."Quantity"
      FROM "ORDN" M JOIN "RDN1" D ON M."DocEntry" = D."DocEntry" CROSS JOIN P
     WHERE M."CANCELED" <> 'C' AND M."DocDate" <= P."D1" AND IFNULL(D."BaseType", -1) <> 15
       AND NOT EXISTS (SELECT 1 FROM CANCELLED X WHERE X."ObjType" = 16 AND X."DocEntry" = M."DocEntry")
),

-- ⑥ 未清 = 发出数量 − 已开票 − 已退货，只留库存物料（OITM.InvntItem = 'Y'）且未清不为 0 的行
--    （= 结果表 MTC_CA_R_GOODS_OUT 的数量部分）
GOODS_OPEN AS (
    SELECT S."ObjType", S."DocNum", S."DocEntry", S."LineNum", S."DocDate", S."CardCode",
           T."CustType", CASE WHEN T."BusiType" = '样品销售' THEN 'Y' ELSE 'N' END AS "IsSample", S."ItemCode",
           S."Sign" * S."Quantity" AS "DocQty", IFNULL(N1."Qty", 0) AS "InvQty", IFNULL(N2."Qty", 0) AS "RetQty",
           S."Sign" * (S."Quantity" - IFNULL(N1."Qty", 0) - IFNULL(N2."Qty", 0)) AS "OpenQty"
      FROM SRC_LINE S
      JOIN "OITM" I ON I."ItemCode" = S."ItemCode" AND I."InvntItem" = 'Y'
      LEFT JOIN SAL_TYPE T ON T."Name" = S."U_SalOrdType"
      LEFT JOIN CONSUMED N1 ON N1."K" = 'INV' AND TO_NVARCHAR(N1."BaseType") = S."ObjType" AND N1."BaseEntry" = S."DocEntry" AND N1."BaseLine" = S."LineNum"
      LEFT JOIN CONSUMED N2 ON N2."K" = 'RET' AND TO_NVARCHAR(N2."BaseType") = S."ObjType" AND N2."BaseEntry" = S."DocEntry" AND N2."BaseLine" = S."LineNum"
     WHERE ABS(S."Quantity" - IFNULL(N1."Qty", 0) - IFNULL(N2."Qty", 0)) > 0.000001
)
-- @result 以下是输出；执行台“与计算结果比对”会把这一段换成比对语句
SELECT * FROM GOODS_OPEN
 ORDER BY "CardCode", "DocDate", "ObjType", "DocEntry", "LineNum"
