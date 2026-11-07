/* =====================================================================
 * 委外加工费 · 取数 SQL（只读，直接从 B1 单据取）
 *
 * 结果：本期每一笔委外加工费（采购收货、采购退货、委外重估 ProWW），以及它记到了哪张订单、怎么匹配上的。
 * 对应：新框架 MTC_CA_P20_SUBFEE（快照 MTC_CA_S_SUBFEE），之后 P30 按订单汇总成订单的委外加工费（#SUBFEE）。
 *       两边口径相同，执行台“与计算结果比对”逐行核对。旧模块的对应：0306_WW（MTC_VIEW_ProductDetail ID 3）。
 * 金额符号：收货为正、退货为负、取消单取反；ProWW 取重估行 U_Amount。
 * 金额口径（用户 2026-10-30 方案 B，与 PUR4 暂估同一口径）：指定单价 U_InitPrice 不为 0 → 数量 × U_InitPrice；U_IsPrice = 'Y' → 数量 × Price；
 *   否则 LineTotal。基于收货的退货按所基于收货行的暂估单价 × 数量。旧 0306（视图 ID 3）一律 LineTotal。
 *   计算里退货若是把收货行全部冲完的那一笔，按“整行暂估 − 以前已冲回”清余数（ap_accr.sql），这里按 数量 × 单价，可能差几分。
 * 匹配不到订单的（MatchNote 为“找不到…”“…对不上”）金额不进任何订单，由计算前检查 PRE-12 报出。
 * 委外加工费的发票差异不在这里，见 ap_accr.sql（APDIF，计入产品的 I11）。
 * 用法：第 ① 段的参数换成账期，例如 '2026-09'，整段执行。
 *       排查时可以把最后的 SELECT 换成 SELECT * FROM 某一段（如 FEE、RCPT_ORDER、CAND），看中间结果。
 * ===================================================================== */
WITH
-- ① 账期：起止日取 OFPR
P AS (
    SELECT O."Code" AS "FC", TO_DATE(O."F_RefDate") AS "D0", TO_DATE(O."T_RefDate") AS "D1"
      FROM "OFPR" O
     WHERE O."Code" = ?
),

-- ② 加工费单据行（本期）：
--    a. 采购收货行 PDN1.U_BaseType = '59'（指向生产收货 U_BaseEntry），行上带订单号 U_OWORNum / 返工单 U_OWORType + U_MTCOWORNum；
--    b. 基于这些收货的采购退货（RPD1 → PDN1），订单信息取所基于的收货行；
--    c. 没有关联采购收货的加工费退货（物料 X 开头，用户 2026-10-15），用退货行自己的 U_ 字段
FEE AS (
    SELECT 'PDN' AS "Src", D."DocEntry" || '-' || D."LineNum" AS "SrcKey", M."DocNum", TO_DATE(M."DocDate") AS "DocDate",
           D."ItemCode", CASE WHEN M."CANCELED" = 'C' THEN -1 ELSE 1 END * D."Quantity" AS "Qty",
           CASE WHEN M."CANCELED" = 'C' THEN -1 ELSE 1 END
             * ROUND(CASE WHEN IFNULL(D."U_InitPrice", 0) <> 0 THEN D."Quantity" * D."U_InitPrice"
                          WHEN D."U_IsPrice" = 'Y' THEN D."Quantity" * D."Price" ELSE D."LineTotal" END, 2) AS "Amount",
           TO_NVARCHAR(D."U_BaseEntry") AS "RcptEntry", TO_NVARCHAR(D."U_OWORNum") AS "OWORNum",
           TO_NVARCHAR(D."U_OWORType") AS "OWORType", TO_NVARCHAR(D."U_MTCOWORNum") AS "MTCOWORNum"
      FROM "OPDN" M JOIN "PDN1" D ON D."DocEntry" = M."DocEntry" CROSS JOIN P
     WHERE TO_NVARCHAR(D."U_BaseType") = '59' AND M."DocDate" BETWEEN P."D0" AND P."D1"
    UNION ALL
    SELECT 'RPD', D."DocEntry" || '-' || D."LineNum", M."DocNum", TO_DATE(M."DocDate"),
           D."ItemCode", CASE WHEN M."CANCELED" = 'C' THEN 1 ELSE -1 END * D."Quantity",
           CASE WHEN M."CANCELED" = 'C' THEN 1 ELSE -1 END
             * ROUND(D."Quantity" * CASE WHEN IFNULL(R."U_InitPrice", 0) <> 0 THEN R."U_InitPrice" WHEN R."U_IsPrice" = 'Y' THEN R."Price"
                                        ELSE R."LineTotal" / NULLIF(R."Quantity", 0) END, 2),
           TO_NVARCHAR(R."U_BaseEntry"), TO_NVARCHAR(R."U_OWORNum"), TO_NVARCHAR(R."U_OWORType"), TO_NVARCHAR(R."U_MTCOWORNum")
      FROM "ORPD" M JOIN "RPD1" D ON D."DocEntry" = M."DocEntry"
      JOIN "PDN1" R ON D."BaseType" = 20 AND R."DocEntry" = D."BaseEntry" AND R."LineNum" = D."BaseLine"
      CROSS JOIN P
     WHERE TO_NVARCHAR(R."U_BaseType") = '59' AND M."DocDate" BETWEEN P."D0" AND P."D1"
    UNION ALL
    SELECT 'RPD', D."DocEntry" || '-' || D."LineNum", M."DocNum", TO_DATE(M."DocDate"),
           D."ItemCode", CASE WHEN M."CANCELED" = 'C' THEN 1 ELSE -1 END * D."Quantity",
           CASE WHEN M."CANCELED" = 'C' THEN 1 ELSE -1 END
             * ROUND(CASE WHEN IFNULL(D."U_InitPrice", 0) <> 0 THEN D."Quantity" * D."U_InitPrice"
                          WHEN D."U_IsPrice" = 'Y' THEN D."Quantity" * D."Price" ELSE D."LineTotal" END, 2),
           CASE WHEN TO_NVARCHAR(D."U_BaseType") = '59' THEN TO_NVARCHAR(D."U_BaseEntry") END, TO_NVARCHAR(D."U_OWORNum"),
           TO_NVARCHAR(D."U_OWORType"), TO_NVARCHAR(D."U_MTCOWORNum")
      FROM "ORPD" M JOIN "RPD1" D ON D."DocEntry" = M."DocEntry" CROSS JOIN P
     WHERE IFNULL(D."BaseType", -1) <> 20 AND D."ItemCode" LIKE 'X%' AND M."DocDate" BETWEEN P."D0" AND P."D1"
),

-- ③ 生产收货 → 订单（取完工 / 主件行，订单行为空）。与收发存 inv_line.sql ③ / ③b、订单 order.sql 同一规则（新框架 MTC_CA_F_GI_ORDER，2026-10-31）；
--    不限日期（加工费可能对上月的生产收货）：
--    a. 视图 MTC_VIEW_Document 改写后的来源：202 生产订单（BaseRef = 订单 DocNum）；U_OWORType = 'MTC_OWOR' 时为返工单（BaseEntry = U_MTCOWORNum）；
--    b. 视图没给出订单的行，按行上 U_OWORType 补：'202' → U_OWORNum（OWOR.DocNum）找 DocEntry（对上多张不关联）、行号 U_OWORLineNum；
--       'MTC_OWOR' → U_MTCOWORNum（DocEntry）、行号 U_MTCOWORLineNum。形态转换 204 / 205 不动。
RCPT_V AS (
    SELECT TO_NVARCHAR(V."DocEntry") AS "DocEntry", TO_NVARCHAR(V."LineNum") AS "LineNum", TO_NVARCHAR(V."U_BusiType") AS "U_BusiType",
           TO_NVARCHAR(V."BaseType") AS "BaseType", TO_NVARCHAR(V."BaseEntry") AS "BaseEntry",
           TO_NVARCHAR(V."BaseRef") AS "BaseRef", TO_NVARCHAR(V."BaseLine") AS "BaseLine"
      FROM "MTC_VIEW_Document" V
     WHERE TO_NVARCHAR(V."ObjType") = '59' AND TO_NVARCHAR(V."DocEntry") IN (SELECT "RcptEntry" FROM FEE)
),
RCPT_F AS (
    SELECT TO_NVARCHAR(D."DocEntry") AS "DocEntry", TO_NVARCHAR(D."LineNum") AS "LineNum", MAX(TRIM(TO_NVARCHAR(D."U_OWORType"))) AS "OT",
           CASE WHEN MAX(TRIM(TO_NVARCHAR(D."U_OWORType"))) = 'MTC_OWOR' THEN MAX(NULLIF(TRIM(TO_NVARCHAR(D."U_MTCOWORNum")), ''))
                WHEN COUNT(DISTINCT W."DocEntry") = 1 THEN TO_NVARCHAR(MAX(W."DocEntry")) END AS "OEntry",
           CASE WHEN MAX(TRIM(TO_NVARCHAR(D."U_OWORType"))) = 'MTC_OWOR' THEN MAX(NULLIF(TRIM(TO_NVARCHAR(D."U_MTCOWORNum")), ''))
                ELSE MAX(NULLIF(TRIM(TO_NVARCHAR(D."U_OWORNum")), '')) END AS "ORef",
           CASE WHEN MAX(TRIM(TO_NVARCHAR(D."U_OWORType"))) = '202' THEN MAX(TO_NVARCHAR(D."U_OWORLineNum"))
                ELSE MAX(TO_NVARCHAR(D."U_MTCOWORLineNum")) END AS "OLine"
      FROM "IGN1" D
      LEFT JOIN "OWOR" W ON TRIM(TO_NVARCHAR(D."U_OWORType")) = '202' AND TO_NVARCHAR(W."DocNum") = NULLIF(TRIM(TO_NVARCHAR(D."U_OWORNum")), '')
     WHERE TRIM(TO_NVARCHAR(D."U_OWORType")) IN ('202', 'MTC_OWOR') AND TO_NVARCHAR(D."DocEntry") IN (SELECT "RcptEntry" FROM FEE)
     GROUP BY D."DocEntry", D."LineNum"
),
RCPT_ORDER AS (
    SELECT DISTINCT X."RcptEntry", X."OrderType", X."OrderEntry", X."OrderRef"
      FROM (SELECT V."DocEntry" AS "RcptEntry",
                   CASE WHEN F."OEntry" IS NOT NULL THEN F."OT" ELSE V."BaseType" END AS "OrderType",
                   CASE WHEN F."OEntry" IS NOT NULL THEN F."OEntry" ELSE V."BaseEntry" END AS "OrderEntry",
                   CASE WHEN F."OEntry" IS NOT NULL THEN F."ORef" ELSE V."BaseRef" END AS "OrderRef",
                   CASE WHEN F."OEntry" IS NOT NULL THEN F."OLine" ELSE V."BaseLine" END AS "OrderLine"
              FROM RCPT_V V
              LEFT JOIN RCPT_F F ON F."DocEntry" = V."DocEntry" AND F."LineNum" = V."LineNum"
                                AND IFNULL(V."BaseType", '') NOT IN ('202', 'MTC_OWOR')
                                AND IFNULL(V."U_BusiType", '') NOT IN ('204', '205')) X
     WHERE X."OrderType" IN ('202', 'MTC_OWOR') AND IFNULL(X."OrderLine", '') = ''
),

-- ④ 候选订单：加工费行的生产收货对应的订单。Hit = 1 表示订单号也对得上
--    （202 比 U_OWORNum = 订单 DocNum；返工单比 U_MTCOWORNum = 返工单 DocEntry）
CAND AS (
    SELECT F."Src", F."SrcKey", R."OrderType", R."OrderEntry",
           CASE WHEN R."OrderType" = '202' AND R."OrderRef" = F."OWORNum" THEN 1
                WHEN R."OrderType" = 'MTC_OWOR' AND F."OWORType" = 'MTC_OWOR' AND R."OrderEntry" = F."MTCOWORNum" THEN 1
                ELSE 0 END AS "Hit",
           COUNT(*) OVER (PARTITION BY F."Src", F."SrcKey") AS "Cnt"
      FROM FEE F JOIN RCPT_ORDER R ON R."RcptEntry" = F."RcptEntry"
),
CAND2 AS (
    SELECT C.*, SUM(C."Hit") OVER (PARTITION BY C."Src", C."SrcKey") AS "Hits" FROM CAND C
),
-- ⑤ 选定订单：先按“生产收货 + 订单号”唯一匹配；订单号对不上但生产收货只对应一张订单时也用它
PICK0 AS (
    SELECT "Src", "SrcKey", "OrderType", "OrderEntry",
           CASE WHEN "Hit" = 1 THEN '按生产收货 + 订单号匹配' ELSE '生产收货只对应一张订单' END AS "Note"
      FROM CAND2
     WHERE ("Hits" = 1 AND "Hit" = 1) OR ("Hits" = 0 AND "Cnt" = 1)
),
-- ⑥ 找不到生产收货时，直接按行上的订单号找：返工单（U_OWORType = 'MTC_OWOR'）比 DocEntry，否则比 OWOR.DocNum；
--    一个单号对应多张订单时不取，避免重复计入
DIRECT AS (
    SELECT F."Src", F."SrcKey", 'MTC_OWOR' AS "OrderType", TO_NVARCHAR(R."DocEntry") AS "OrderEntry", '按退货行上的返工单号匹配' AS "Note"
      FROM FEE F JOIN "@MTC_OWOR" R ON TO_NVARCHAR(R."DocEntry") = F."MTCOWORNum"
     WHERE F."OWORType" = 'MTC_OWOR'
    UNION ALL
    SELECT F."Src", F."SrcKey", '202', TO_NVARCHAR(W."DocEntry"), '按退货行上的生产订单号匹配'
      FROM FEE F JOIN "OWOR" W ON TO_NVARCHAR(W."DocNum") = F."OWORNum"
     WHERE IFNULL(F."OWORType", '') <> 'MTC_OWOR'
),
PICK AS (
    SELECT "Src", "SrcKey", "OrderType", "OrderEntry", "Note" FROM PICK0
    UNION ALL
    SELECT D."Src", D."SrcKey", D."OrderType", D."OrderEntry", D."Note"
      FROM (SELECT X.*, COUNT(*) OVER (PARTITION BY X."Src", X."SrcKey") AS "Cnt" FROM DIRECT X) D
     WHERE D."Cnt" = 1
       AND NOT EXISTS (SELECT 1 FROM PICK0 P0 WHERE P0."Src" = D."Src" AND P0."SrcKey" = D."SrcKey")
),

-- ⑦ 委外重估 @MTC_OMRV（U_BaseType = 'ProWW'，未作废、本期）：行上 U_BaseType / U_BaseEntry 能找到订单（202 或返工单）的计入该订单；
--    找不到订单的不在这里，进费用池（见 exp.sql）
PROWW AS (
    SELECT 'PROWW' AS "Src", T1."DocEntry" || '-' || T1."LineId" AS "SrcKey", T0."DocNum", TO_DATE(T0."U_DocDate") AS "DocDate",
           T1."U_ItemCode" AS "ItemCode", T1."U_Quantity" AS "Qty", T1."U_Amount" AS "Amount", NULL AS "RcptEntry",
           T1."U_BaseType" AS "OrderType", TO_INTEGER(T1."U_BaseEntry") AS "OrderEntry", '重估单行上的订单' AS "MatchNote"
      FROM "@MTC_OMRV" T0
      JOIN "@MTC_OMRV1" T1 ON T1."DocEntry" = T0."DocEntry"
      LEFT JOIN "OWOR" W ON T1."U_BaseType" = '202' AND W."DocEntry" = T1."U_BaseEntry"
      LEFT JOIN "@MTC_OWOR" M ON T1."U_BaseType" = 'MTC_OWOR' AND M."DocEntry" = T1."U_BaseEntry"
      CROSS JOIN P
     WHERE T0."U_BaseType" = 'ProWW' AND IFNULL(T0."Canceled", 'N') = 'N'
       AND T0."U_DocDate" BETWEEN P."D0" AND P."D1"
       AND (W."DocEntry" IS NOT NULL OR M."DocEntry" IS NOT NULL)
),

-- ⑧ 全部加工费及其订单（= 快照表 MTC_CA_S_SUBFEE）
SUBFEE AS (
    SELECT F."Src", F."SrcKey", F."DocNum", F."DocDate", F."ItemCode", F."Qty", F."Amount",
           CASE WHEN F."RcptEntry" LIKE_REGEXPR '^[0-9]+$' THEN TO_INTEGER(F."RcptEntry") END AS "RcptEntry",
           K."OrderType", CASE WHEN K."OrderEntry" LIKE_REGEXPR '^[0-9]+$' THEN TO_INTEGER(K."OrderEntry") END AS "OrderEntry",
           IFNULL(K."Note", CASE WHEN X."RcptEntry" IS NOT NULL THEN '生产收货对应多张订单，订单号对不上'
                                 ELSE '找不到生产收货或其订单' END) AS "MatchNote"
      FROM FEE F
      LEFT JOIN PICK K ON K."Src" = F."Src" AND K."SrcKey" = F."SrcKey"
      LEFT JOIN (SELECT DISTINCT "RcptEntry" FROM RCPT_ORDER) X ON X."RcptEntry" = F."RcptEntry"
    UNION ALL
    SELECT "Src", "SrcKey", "DocNum", "DocDate", "ItemCode", "Qty", "Amount", "RcptEntry", "OrderType", "OrderEntry", "MatchNote"
      FROM PROWW
),
-- ⑨ 补上订单号，方便在 SAP 里查
SUBFEE_OUT AS (
    SELECT S."Src", S."SrcKey", S."DocNum", S."DocDate", S."ItemCode", S."Qty", S."Amount", S."RcptEntry",
           S."OrderType", S."OrderEntry", COALESCE(TO_NVARCHAR(W."DocNum"), TO_NVARCHAR(M."DocNum")) AS "OrderNum", S."MatchNote"
      FROM SUBFEE S
      LEFT JOIN "OWOR" W ON S."OrderType" = '202' AND W."DocEntry" = S."OrderEntry"
      LEFT JOIN "@MTC_OWOR" M ON S."OrderType" = 'MTC_OWOR' AND M."DocEntry" = S."OrderEntry"
)
-- @result 以下是输出；执行台“与计算结果比对”会把这一段换成比对语句
SELECT * FROM SUBFEE_OUT
 ORDER BY "OrderType", "OrderEntry", "DocDate", "Src", "SrcKey"
