/* =====================================================================
 * 应付暂估 · 取数 SQL（只读，直接从 B1 单据算）
 *
 * 结果：截至期末“已收货、未开票”的每个暂估行（收货行，或不基于收货的退货行），
 *       列出暂估数量、已开票、已退货、未清数量、暂估单价和未清暂估金额。
 * 对应：新框架 MTC_CA_P20_AP（快照 S_AP_MOVE）+ MTC_CA_P73_AP_ACCR（结果 R_AP_ACCR），
 *       两边口径相同；执行台“应付暂估 → 与计算结果比对”逐行核对。改口径时两边一起改。
 *       旧模块的对应：6101_1（PUR1–PUR5）、reports/MTC_RPT_CO6102。
 * 用法：第 ① 段的参数换成账期，例如 '2026-09'，整段执行。
 *       排查时可以把最后的 SELECT 换成 SELECT * FROM 某一段（如 ACCR_LINE、MOVES），看中间结果。
 * ===================================================================== */
WITH
-- ① 账期：起止日取 OFPR；委外加工费物料取参数 SUBFEE_ITEM（默认 X0510001）
P AS (
    SELECT O."Code" AS "FC", TO_DATE(O."F_RefDate") AS "D0", TO_DATE(O."T_RefDate") AS "D1",
           IFNULL("MTC_CA_F_PARAM"('SUBFEE_ITEM', O."Code"), 'X0510001') AS "FEE_ITEM"
      FROM "OFPR" O
     WHERE O."Code" = ?
),

-- ② 暂估行：截至期末、未取消的采购收货行（不基于退货），和不基于收货的采购退货行。
--    退货行方向为负（BaseSign = -1）。
BASE_LINE AS (
    SELECT '20' AS "BaseObj", M."DocEntry" AS "BaseEntry", D."LineNum" AS "BaseLine", M."DocNum",
           TO_DATE(M."DocDate") AS "BaseDate", 1 AS "BaseSign", D."Quantity" AS "BaseQty",
           M."CardCode", D."ItemCode", D."U_InitPrice", D."U_IsPrice", D."Price", D."LineTotal"
      FROM "OPDN" M JOIN "PDN1" D ON D."DocEntry" = M."DocEntry" CROSS JOIN P
     WHERE M."CANCELED" <> 'C' AND M."DocDate" <= P."D1" AND IFNULL(D."BaseType", -1) <> 21
    UNION ALL
    SELECT '21', M."DocEntry", D."LineNum", M."DocNum",
           TO_DATE(M."DocDate"), -1, D."Quantity",
           M."CardCode", D."ItemCode", D."U_InitPrice", D."U_IsPrice", D."Price", D."LineTotal"
      FROM "ORPD" M JOIN "RPD1" D ON D."DocEntry" = M."DocEntry" CROSS JOIN P
     WHERE M."CANCELED" <> 'C' AND M."DocDate" <= P."D1" AND IFNULL(D."BaseType", -1) <> 20
),

-- ③ 暂估范围和暂估价：只暂估库存物料（OITM.InvntItem = 'Y'）和委外加工费物料。
--    单价 UP：U_InitPrice 不为 0 取它；否则 U_IsPrice = 'Y' 取 Price；否则 LineTotal / 数量。
--    整行暂估 FullAmt 按同样顺序取 数量 × 单价 或 LineTotal，保留 2 位。
ACCR_LINE AS (
    SELECT B.*,
           CASE WHEN B."ItemCode" = P."FEE_ITEM" THEN 'SUBFEE' ELSE 'MAT' END AS "AccrType",
           CASE WHEN IFNULL(B."U_InitPrice", 0) <> 0 THEN B."U_InitPrice"
                WHEN B."U_IsPrice" = 'Y' THEN B."Price"
                ELSE B."LineTotal" / NULLIF(B."BaseQty", 0) END AS "UP",
           ROUND(CASE WHEN IFNULL(B."U_InitPrice", 0) <> 0 THEN B."BaseQty" * B."U_InitPrice"
                      WHEN B."U_IsPrice" = 'Y' THEN B."BaseQty" * B."Price"
                      ELSE B."LineTotal" END, 2) AS "FullAmt"
      FROM BASE_LINE B JOIN "OITM" I ON I."ItemCode" = B."ItemCode" CROSS JOIN P
     WHERE I."InvntItem" = 'Y' OR B."ItemCode" = P."FEE_ITEM"
),

-- ④ 冲减暂估的单据（原单，不含取消单）：
--    INV = 基于收货 / 退货的应付发票（18）和应付贷项（19，金额取负）；
--    RET = 基于收货的退货（21）、基于退货的收货（20，换货）。
CONSUME AS (
    SELECT '18' AS "ObjType", M."DocEntry", D."LineNum", TO_DATE(M."DocDate") AS "DocDate",
           TO_NVARCHAR(D."BaseType") AS "BaseObj", D."BaseEntry", D."BaseLine", D."Quantity" AS "Q",
           D."LineTotal" AS "DocAmt", 'INV' AS "MoveType"
      FROM "OPCH" M JOIN "PCH1" D ON D."DocEntry" = M."DocEntry" CROSS JOIN P
     WHERE M."CANCELED" <> 'C' AND M."DocDate" <= P."D1" AND D."BaseType" IN (20, 21)
    UNION ALL
    SELECT '19', M."DocEntry", D."LineNum", TO_DATE(M."DocDate"),
           TO_NVARCHAR(D."BaseType"), D."BaseEntry", D."BaseLine", D."Quantity",
           -D."LineTotal", 'INV'
      FROM "ORPC" M JOIN "RPC1" D ON D."DocEntry" = M."DocEntry" CROSS JOIN P
     WHERE M."CANCELED" <> 'C' AND M."DocDate" <= P."D1" AND D."BaseType" IN (20, 21)
    UNION ALL
    SELECT '21', M."DocEntry", D."LineNum", TO_DATE(M."DocDate"),
           '20', D."BaseEntry", D."BaseLine", D."Quantity", NULL, 'RET'
      FROM "ORPD" M JOIN "RPD1" D ON D."DocEntry" = M."DocEntry" CROSS JOIN P
     WHERE M."CANCELED" <> 'C' AND M."DocDate" <= P."D1" AND D."BaseType" = 20
    UNION ALL
    SELECT '20', M."DocEntry", D."LineNum", TO_DATE(M."DocDate"),
           '21', D."BaseEntry", D."BaseLine", D."Quantity", NULL, 'RET'
      FROM "OPDN" M JOIN "PDN1" D ON D."DocEntry" = M."DocEntry" CROSS JOIN P
     WHERE M."CANCELED" <> 'C' AND M."DocDate" <= P."D1" AND D."BaseType" = 21
),

-- ⑤ 取消单（CANCELED = 'C'）：通过 BaseType / BaseEntry / BaseLine 指回被取消的原单行。
CANCEL_DOC AS (
    SELECT '20' AS "ObjType", M."DocEntry", D."LineNum", TO_DATE(M."DocDate") AS "DocDate",
           '20' AS "OrigObj", D."BaseEntry" AS "OrigEntry", D."BaseLine" AS "OrigLine"
      FROM "OPDN" M JOIN "PDN1" D ON D."DocEntry" = M."DocEntry" CROSS JOIN P
     WHERE M."CANCELED" = 'C' AND D."BaseType" = 20 AND M."DocDate" <= P."D1"
    UNION ALL
    SELECT '21', M."DocEntry", D."LineNum", TO_DATE(M."DocDate"), '21', D."BaseEntry", D."BaseLine"
      FROM "ORPD" M JOIN "RPD1" D ON D."DocEntry" = M."DocEntry" CROSS JOIN P
     WHERE M."CANCELED" = 'C' AND D."BaseType" = 21 AND M."DocDate" <= P."D1"
    UNION ALL
    SELECT '18', M."DocEntry", D."LineNum", TO_DATE(M."DocDate"), '18', D."BaseEntry", D."BaseLine"
      FROM "OPCH" M JOIN "PCH1" D ON D."DocEntry" = M."DocEntry" CROSS JOIN P
     WHERE M."CANCELED" = 'C' AND D."BaseType" = 18 AND M."DocDate" <= P."D1"
    UNION ALL
    SELECT '19', M."DocEntry", D."LineNum", TO_DATE(M."DocDate"), '19', D."BaseEntry", D."BaseLine"
      FROM "ORPC" M JOIN "RPC1" D ON D."DocEntry" = M."DocEntry" CROSS JOIN P
     WHERE M."CANCELED" = 'C' AND D."BaseType" = 19 AND M."DocDate" <= P."D1"
),

-- ⑥ 冲减事件 = 原单 + 取消单（取消单数量取反）。每笔先按 ROUND(数量 × 暂估单价, 2) 计 Simple。
EVENT_RAW AS (
    SELECT A."BaseObj", A."BaseEntry", A."BaseLine", C."ObjType", C."DocEntry", C."LineNum", C."DocDate",
           'N' AS "IsCancel", C."ObjType" AS "OrigObj", C."DocEntry" AS "OrigEntry", C."LineNum" AS "OrigLine",
           C."Q" AS "CQ", ROUND(C."Q" * A."UP", 2) AS "Simple", C."DocAmt", C."MoveType"
      FROM CONSUME C
      JOIN ACCR_LINE A ON A."BaseObj" = C."BaseObj" AND A."BaseEntry" = C."BaseEntry" AND A."BaseLine" = C."BaseLine"
    UNION ALL
    SELECT A."BaseObj", A."BaseEntry", A."BaseLine", X."ObjType", X."DocEntry", X."LineNum", X."DocDate",
           'Y', C."ObjType", C."DocEntry", C."LineNum",
           -C."Q", -ROUND(C."Q" * A."UP", 2), -C."DocAmt", C."MoveType"
      FROM CANCEL_DOC X
      JOIN CONSUME C ON C."ObjType" = X."OrigObj" AND C."DocEntry" = X."OrigEntry" AND C."LineNum" = X."OrigLine"
      JOIN ACCR_LINE A ON A."BaseObj" = C."BaseObj" AND A."BaseEntry" = C."BaseEntry" AND A."BaseLine" = C."BaseLine"
),

-- ⑦ 清余数：按日期累计数量，累计刚好达到暂估数量的那一笔（Rule = LAST）
--    金额 = 整行暂估 − 之前已冲回，把四舍五入的尾差清掉；其余各笔（ROUND）用 Simple。
EVENT_CUM AS (
    SELECT E.*, A."BaseQty", A."FullAmt",
           SUM(E."CQ") OVER (PARTITION BY E."BaseObj", E."BaseEntry", E."BaseLine"
                             ORDER BY E."DocDate", E."IsCancel", E."ObjType", E."DocEntry", E."LineNum"
                             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS "CumQ",
           SUM(E."Simple") OVER (PARTITION BY E."BaseObj", E."BaseEntry", E."BaseLine"
                                 ORDER BY E."DocDate", E."IsCancel", E."ObjType", E."DocEntry", E."LineNum"
                                 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS "CumS"
      FROM EVENT_RAW E
      JOIN ACCR_LINE A ON A."BaseObj" = E."BaseObj" AND A."BaseEntry" = E."BaseEntry" AND A."BaseLine" = E."BaseLine"
),
EVENT_AMT AS (
    SELECT W.*,
           CASE WHEN W."IsCancel" = 'N' AND W."CumQ" >= W."BaseQty" - 0.000001 AND W."CumQ" - W."CQ" < W."BaseQty" - 0.000001
                THEN W."FullAmt" - (W."CumS" - W."Simple") ELSE W."Simple" END AS "Mag",
           CASE WHEN W."IsCancel" = 'N' AND W."CumQ" >= W."BaseQty" - 0.000001 AND W."CumQ" - W."CQ" < W."BaseQty" - 0.000001
                THEN 'LAST' ELSE 'ROUND' END AS "Rule"
      FROM EVENT_CUM W
),
-- ⑧ 取消单的金额 = 原单最终金额的相反数（原单是清余数那一笔时，也按清余数后的金额反向）
EVENT_FINAL AS (
    SELECT E."BaseObj", E."BaseEntry", E."BaseLine", E."ObjType", E."DocEntry", E."LineNum", E."DocDate",
           E."IsCancel", E."CQ", E."MoveType", E."DocAmt",
           CASE WHEN E."IsCancel" = 'Y' THEN -O."Mag" ELSE E."Mag" END AS "Mag",
           CASE WHEN E."IsCancel" = 'Y' THEN 'CANCEL' ELSE E."Rule" END AS "Rule"
      FROM EVENT_AMT E
      LEFT JOIN EVENT_AMT O ON E."IsCancel" = 'Y' AND O."IsCancel" = 'N'
                           AND O."ObjType" = E."OrigObj" AND O."DocEntry" = E."OrigEntry" AND O."LineNum" = E."OrigLine"
                           AND O."BaseObj" = E."BaseObj" AND O."BaseEntry" = E."BaseEntry" AND O."BaseLine" = E."BaseLine"
),

-- ⑨ 暂估行的全部变动（= 快照表 MTC_CA_S_AP_MOVE）。Qty、AccrAmt 为正表示增加暂估：
--    ACCR 暂估本身（+整行）；暂估行本身被取消（−整行）；INV / RET 冲回（−Mag）。
MOVES AS (
    SELECT A."BaseObj", A."BaseEntry", A."BaseLine", 'ACCR' AS "MoveType", 'N' AS "IsCancel",
           A."BaseObj" AS "ObjType", A."BaseEntry" AS "DocEntry", A."BaseLine" AS "LineNum", A."BaseDate" AS "DocDate",
           A."BaseQty" AS "Qty", A."BaseSign" * A."FullAmt" AS "AccrAmt", CAST(NULL AS DECIMAL(19,2)) AS "DocAmt", 'FULL' AS "AmtRule"
      FROM ACCR_LINE A
    UNION ALL
    SELECT A."BaseObj", A."BaseEntry", A."BaseLine", 'ACCR', 'Y', X."ObjType", X."DocEntry", X."LineNum", X."DocDate",
           -A."BaseQty", -A."BaseSign" * A."FullAmt", NULL, 'CANCEL'
      FROM CANCEL_DOC X
      JOIN ACCR_LINE A ON A."BaseObj" = X."OrigObj" AND A."BaseEntry" = X."OrigEntry" AND A."BaseLine" = X."OrigLine"
    UNION ALL
    SELECT F."BaseObj", F."BaseEntry", F."BaseLine", F."MoveType", F."IsCancel", F."ObjType", F."DocEntry", F."LineNum", F."DocDate",
           -F."CQ", -A."BaseSign" * F."Mag", F."DocAmt", F."Rule"
      FROM EVENT_FINAL F
      JOIN ACCR_LINE A ON A."BaseObj" = F."BaseObj" AND A."BaseEntry" = F."BaseEntry" AND A."BaseLine" = F."BaseLine"
),

-- ⑩ 按暂估行汇总，只留截至期末仍未清的（= 结果表 MTC_CA_R_AP_ACCR）
ACCR_OPEN AS (
    SELECT M."BaseObj" AS "ObjType", MAX(A."DocNum") AS "DocNum", M."BaseEntry" AS "DocEntry", M."BaseLine" AS "LineNum",
           MAX(A."BaseDate") AS "DocDate", MAX(A."CardCode") AS "CardCode", MAX(A."AccrType") AS "AccrType", MAX(A."ItemCode") AS "ItemCode",
           MAX(A."BaseSign" * A."BaseQty") AS "DocQty",
           SUM(CASE WHEN M."MoveType" = 'INV' THEN -M."Qty" ELSE 0 END) AS "InvQty",
           SUM(CASE WHEN M."MoveType" = 'RET' THEN -M."Qty" ELSE 0 END) AS "RetQty",
           MAX(A."BaseSign") * SUM(M."Qty") AS "OpenQty",
           MAX(A."UP") AS "UnitPrice",
           SUM(M."AccrAmt") AS "OpenAmt"
      FROM MOVES M
      JOIN ACCR_LINE A ON A."BaseObj" = M."BaseObj" AND A."BaseEntry" = M."BaseEntry" AND A."BaseLine" = M."BaseLine"
     GROUP BY M."BaseObj", M."BaseEntry", M."BaseLine"
    HAVING ABS(SUM(M."Qty")) > 0.000001 OR ABS(SUM(M."AccrAmt")) >= 0.005
)
-- @result 以下是输出；执行台“与计算结果比对”会把这一段换成比对语句
SELECT * FROM ACCR_OPEN
 ORDER BY "CardCode", "DocDate", "DocEntry", "LineNum"
