/* =====================================================================
 * 订单成本 · 取数 SQL（只读，直接从 B1 单据取）
 *
 * 结果：本期参与计算的每张订单（生产订单 OWOR = 202、返工单 @MTC_OWOR = MTC_OWOR），
 *       带订单类型、产品、计划数、截至期末的状态、是否本期关单、本期完工入库数和本期关联的领料行数。
 * 对应：新框架 MTC_CA_P20_ORDER（快照 MTC_CA_S_ORDER）。两边口径相同，执行台“与计算结果比对”逐行核对。
 *       旧模块的对应：0321_OWOR / 0106_OWORLIST。
 * 不在本语句里的：
 *   · 订单成本（材料、制造、人工、委外）和在产品：由计算（P30–P50）算出，见“订单成本”页点行；
 *   · 订单领了哪些料、入了多少库：来自收发存的库存变动，见 inv_line.sql（OrderType / OrderEntry 列）；
 *   · 委外加工费记到哪张订单：见 subfee.sql。本期只有加工费、没有领料入库、又不在范围内的订单，
 *     本语句列不出来，比对时不算差异；
 *   · 期初累计领料 / 累计入库：取上期计算结果或期初承接。
 * 用法：第 ① 段的参数换成账期，例如 '2026-09'，整段执行。
 *       排查时可以把最后的 SELECT 换成 SELECT * FROM 某一段（如 ORD、ORDER_LINE），看中间结果。
 * ===================================================================== */
WITH
-- ① 账期：起止日取 OFPR
P AS (
    SELECT O."Code" AS "FC", TO_DATE(O."F_RefDate") AS "D0", TO_DATE(O."T_RefDate") AS "D1"
      FROM "OFPR" O
     WHERE O."Code" = ?
),

-- ② 全部订单：生产订单 OWOR（订单类型 U_OrdType：10 生产计划、20 包装计划、30 返工计划、40 试打、50 委外），
--    和返工单 @MTC_OWOR（自定义 UDO，字段带 U_）。两张表的 DocEntry 各自编号，按订单关联时必须同时带 OrderType。
--    B1Status：P 计划、R 已下达、L 已关闭、C 已取消
ORD AS (
    SELECT '202' AS "OrderType", W."DocEntry" AS "OrderEntry", TO_NVARCHAR(W."DocNum") AS "OrderNum",
           TO_NVARCHAR(W."U_OrdType") AS "WorType", W."ItemCode", W."PlannedQty", TO_DATE(W."PostDate") AS "PostDate",
           TO_NVARCHAR(W."Status") AS "B1Status", TO_DATE(W."CloseDate") AS "CloseDate", W."CardCode",
           CASE WHEN W."Status" = 'C' THEN TO_DATE(W."UpdateDate") END AS "CancelDate"
      FROM "OWOR" W
    UNION ALL
    SELECT 'MTC_OWOR', M."DocEntry", TO_NVARCHAR(M."DocNum"), TO_NVARCHAR(M."U_OrdType"), M."U_ItemCode", M."U_PlannedQty",
           TO_DATE(M."U_PostDate"), TO_NVARCHAR(M."U_Status"), TO_DATE(M."U_CloseDate"), M."U_CardCode",
           CASE WHEN M."U_Status" = 'C' THEN TO_DATE(M."UpdateDate") END
      FROM "@MTC_OWOR" M
),

-- 收货 / 发货行（视图 MTC_VIEW_Document 已把 59/60 的来源改写为订单），再按 U_OWORType 兜底（同 inv_line.sql ③b）
DOC0 AS (
    SELECT TO_NVARCHAR(V."ObjType") AS "ObjType", TO_NVARCHAR(V."DocEntry") AS "DocEntry", TO_NVARCHAR(V."LineNum") AS "LineNum",
           V."CANCELED", V."CardCode", TO_NVARCHAR(V."BaseType") AS "BaseType", TO_NVARCHAR(V."BaseEntry") AS "BaseEntry",
           TO_NVARCHAR(V."BaseLine") AS "BaseLine", NULLIF(V."TransCode", '') AS "TransCode", V."U_BusiType", V."AcctCode", V."OcrCode"
      FROM "MTC_VIEW_Document" V CROSS JOIN P
     WHERE V."DocDate" BETWEEN P."D0" AND P."D1" AND TO_NVARCHAR(V."ObjType") IN ('59', '60')
),
-- 收货 / 发货行的订单兜底（与 P20_LINE 同口径，2026-10-29）：视图只在 IGN1 / IGE1.BaseType = -1 时看 U_OWORType；
--    视图没给出订单（不是 202 / MTC_OWOR）的 59 / 60 行，按行上 U_OWORType 补：'202' → U_OWORNum（OWOR.DocNum）找 DocEntry、
--    行号 U_OWORLineNum；'MTC_OWOR' → U_MTCOWORNum（DocEntry）、行号 U_MTCOWORLineNum。订单号对上多张订单时不关联。
GL AS (
    SELECT '59' AS "ObjType", TO_NVARCHAR(D."DocEntry") AS "DocEntry", TO_NVARCHAR(D."LineNum") AS "LineNum",
           TRIM(TO_NVARCHAR(D."U_OWORType")) AS "OT", NULLIF(TRIM(TO_NVARCHAR(D."U_OWORNum")), '') AS "ONum",
           TO_NVARCHAR(D."U_OWORLineNum") AS "OLine", NULLIF(TRIM(TO_NVARCHAR(D."U_MTCOWORNum")), '') AS "MNum",
           TO_NVARCHAR(D."U_MTCOWORLineNum") AS "MLine"
      FROM "IGN1" D JOIN "OIGN" H ON H."DocEntry" = D."DocEntry" CROSS JOIN P
     WHERE H."DocDate" BETWEEN P."D0" AND P."D1" AND TRIM(TO_NVARCHAR(D."U_OWORType")) IN ('202', 'MTC_OWOR')
    UNION ALL
    SELECT '60', TO_NVARCHAR(D."DocEntry"), TO_NVARCHAR(D."LineNum"),
           TRIM(TO_NVARCHAR(D."U_OWORType")), NULLIF(TRIM(TO_NVARCHAR(D."U_OWORNum")), ''),
           TO_NVARCHAR(D."U_OWORLineNum"), NULLIF(TRIM(TO_NVARCHAR(D."U_MTCOWORNum")), ''),
           TO_NVARCHAR(D."U_MTCOWORLineNum")
      FROM "IGE1" D JOIN "OIGE" H ON H."DocEntry" = D."DocEntry" CROSS JOIN P
     WHERE H."DocDate" BETWEEN P."D0" AND P."D1" AND TRIM(TO_NVARCHAR(D."U_OWORType")) IN ('202', 'MTC_OWOR')
),
GLO AS (
    SELECT G."ObjType", G."DocEntry", G."LineNum", MAX(G."OT") AS "OT",
           CASE WHEN MAX(G."OT") = 'MTC_OWOR' THEN MAX(G."MNum")
                WHEN COUNT(DISTINCT W."DocEntry") = 1 THEN TO_NVARCHAR(MAX(W."DocEntry")) END AS "OEntry",
           CASE WHEN MAX(G."OT") = '202' THEN MAX(G."OLine") ELSE MAX(G."MLine") END AS "OLine"
      FROM GL G
      LEFT JOIN "OWOR" W ON G."OT" = '202' AND TO_NVARCHAR(W."DocNum") = G."ONum"
     GROUP BY G."ObjType", G."DocEntry", G."LineNum"
),
DOC AS (
    SELECT V."ObjType", V."DocEntry", V."LineNum", V."CANCELED", V."CardCode",
           CASE WHEN F."OEntry" IS NOT NULL THEN F."OT" ELSE V."BaseType" END AS "BaseType",
           CASE WHEN F."OEntry" IS NOT NULL THEN F."OEntry" ELSE V."BaseEntry" END AS "BaseEntry",
           CASE WHEN F."OEntry" IS NOT NULL THEN F."OLine" ELSE V."BaseLine" END AS "BaseLine",
           V."TransCode", V."U_BusiType", V."AcctCode", V."OcrCode"
      FROM DOC0 V
      LEFT JOIN GLO F ON F."ObjType" = V."ObjType" AND F."DocEntry" = V."DocEntry" AND F."LineNum" = V."LineNum"
                     AND IFNULL(V."BaseType", '') NOT IN ('202', 'MTC_OWOR') AND IFNULL(V."U_BusiType", '') NOT IN ('204', '205')
),

-- ③ 本期关联到订单的库存变动（同 inv_line.sql 的订单关联规则）：计价仓库的 OIVL，排除转储；
--    只有工单交易 I03/O03/I07/O07/I08/O08/I09/O09 的收货 / 发货（59/60、不是形态转换 204/205）关联订单。
--    订单行 OrderLine 为空的是完工入库，不为空的是领料；BusiClass 取业务类型 @U_CIOTRN.U_TransType（B01 = 完工入库类）
ORDER_LINE AS (
    SELECT TO_NVARCHAR(V."BaseType") AS "OrderType", TO_INTEGER(V."BaseEntry") AS "OrderEntry",
           CASE WHEN TO_NVARCHAR(V."BaseLine") LIKE_REGEXPR '^[0-9]+$' THEN TO_INTEGER(V."BaseLine") END AS "OrderLine",
           C."U_TransType" AS "BusiClass", L."InQty" - L."OutQty" AS "Qty"
      FROM "OIVL" L
      CROSS JOIN P
      JOIN "OWHS" WH ON WH."WhsCode" = L."LocCode"
      LEFT JOIN "MTC_CA_C_WHS" CW ON CW."WhsCode" = L."LocCode"
      JOIN DOC V ON V."ObjType" = TO_NVARCHAR(L."TransType") AND V."DocEntry" = TO_NVARCHAR(L."CreatedBy")
                AND V."LineNum" = TO_NVARCHAR(L."DocLineNum")
      LEFT JOIN "@U_CIOTRN" C ON C."Code" = V."U_BusiType"
     WHERE L."DocDate" BETWEEN P."D0" AND P."D1" AND L."TransType" <> 67
       AND COALESCE(CW."IsCost", CASE WHEN WH."U_IsCost" = 'Y' THEN 'Y' ELSE 'N' END) = 'Y'
       AND TO_NVARCHAR(V."ObjType") IN ('59', '60') AND IFNULL(V."U_BusiType", '') NOT IN ('204', '205')
       AND V."TransCode" IN ('I03', 'O03', 'I07', 'O07', 'I08', 'O08', 'I09', 'O09')
       AND TO_NVARCHAR(V."BaseType") IN ('202', 'MTC_OWOR') AND TO_NVARCHAR(V."BaseEntry") LIKE_REGEXPR '^[0-9]+$'
),
ORDER_MOVE AS (
    SELECT "OrderType", "OrderEntry",
           SUM(CASE WHEN "BusiClass" = 'B01' AND "OrderLine" IS NULL THEN "Qty" END) AS "RecvQty",
           SUM(CASE WHEN "OrderLine" IS NOT NULL THEN 1 ELSE 0 END) AS "IssueLines"
      FROM ORDER_LINE
     GROUP BY "OrderType", "OrderEntry"
),

-- ④ 订单范围：未取消、过账日期不晚于期末、不是期初前就已关闭的订单（InScope = Y）；
--    范围外但本期有单据关联到的订单也列出（InScope = N，计算前检查 PRE-10 报出）。
--    截至期末状态：当前已关闭且关单日期不晚于期末 → CLOSED，否则 OPEN；关单日期在本期 → ClosedInFc = Y
ORDER_SCOPE AS (
    SELECT O."OrderType", O."OrderEntry", O."OrderNum", O."WorType", O."ItemCode", O."PlannedQty", O."PostDate",
           O."B1Status", O."CloseDate",
           CASE WHEN O."B1Status" = 'L' AND (O."CloseDate" IS NULL OR O."CloseDate" <= P."D1") THEN 'CLOSED'
                WHEN O."CancelDate" BETWEEN P."D0" AND P."D1" THEN 'CLOSED' ELSE 'OPEN' END AS "StatusAtEnd",
           CASE WHEN O."B1Status" = 'L' AND O."CloseDate" BETWEEN P."D0" AND P."D1" THEN 'Y'
                WHEN O."CancelDate" BETWEEN P."D0" AND P."D1" THEN 'Y' ELSE 'N' END AS "ClosedInFc",
           CASE WHEN (O."B1Status" <> 'C' OR O."CancelDate" >= P."D0") AND IFNULL(O."PostDate", P."D0") <= P."D1"
                 AND NOT (O."B1Status" = 'L' AND O."CloseDate" < P."D0") THEN 'Y' ELSE 'N' END AS "InScope",
           O."CardCode", M."RecvQty", IFNULL(M."IssueLines", 0) AS "IssueLines"
      FROM ORD O
      CROSS JOIN P
      LEFT JOIN ORDER_MOVE M ON M."OrderType" = O."OrderType" AND M."OrderEntry" = O."OrderEntry"
     WHERE ((O."B1Status" <> 'C' OR O."CancelDate" >= P."D0") AND IFNULL(O."PostDate", P."D0") <= P."D1" AND NOT (O."B1Status" = 'L' AND O."CloseDate" < P."D0"))
        OR M."OrderEntry" IS NOT NULL
)
-- @result 以下是输出；执行台“与计算结果比对”会把这一段换成比对语句
SELECT * FROM ORDER_SCOPE
 ORDER BY "OrderType", "OrderEntry"
