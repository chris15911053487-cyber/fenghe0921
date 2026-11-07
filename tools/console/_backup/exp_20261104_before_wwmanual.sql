/* =====================================================================
 * 费用归集 · 取数 SQL（只读，直接从 B1 凭证和重估单取）
 *
 * 结果：本期进入费用池的每一笔固定来源费用（已过账凭证行、库存重估行、找不到订单的委外重估行），
 *       带要素（制造 MFG / 人工 LAB）、科目、成本中心，以及按成本中心归到的费用池。
 * 对应：新框架 MTC_CA_P20_EXP（快照 MTC_CA_S_EXP），P30 按成本中心归池写入 MTC_CA_R_POOL（Src = JDT / MRV / PROWW）。
 *       两边口径相同，执行台“与计算结果比对”逐行核对。旧模块的对应：0311_PRODUCTEXP_ADD。
 * 不在本语句里的（费用池的另外两部分，由计算产生）：
 *   · 公摊材料 SHARED：其他出库 / 盘点中科目为制造费用的材料（inv_line.sql 中 SharedExp = Y 的行），金额按计算出的单价；
 *   · 关单差异 CLOSEDIF：本期关闭订单的在产品，全部进参数 CLOSE_DIF_POOL 指定的池。
 * 历史委外差异 WWHIST 不是 B1 单据，取自执行台“历史委外差异”页的计划表 MTC_CA_WW_HIST（见 ③-2）。
 * 与旧 0311 的差别：不再读 JZ01 / JZ03 关单差异草稿和 MRV2 尾差重估。
 * 用法：第 ① 段的参数换成账期，例如 '2026-09'，整段执行。
 *       排查时可以把最后的 SELECT 换成 SELECT * FROM 某一段（如 JDT_EXP、MRV_EXP），看中间结果。
 * ===================================================================== */
WITH
-- ① 账期和归集参数（在 B1 主数据 @MTC_CA_EXPSET 维护，每次计算同步到新框架参数表）：
--    LAB_EXP 人工费用科目（默认 500102）、MFG_EXP_PREFIX 制造费用科目前缀（默认 5101）、
--    EXP_JDT_TRANSCODES 计入费用的凭证代码清单（逗号分隔，首尾带逗号；空代码写成 ,, 表示手工凭证）
P AS (
    SELECT O."Code" AS "FC", TO_DATE(O."F_RefDate") AS "D0", TO_DATE(O."T_RefDate") AS "D1",
           IFNULL("MTC_CA_F_ACCT"('LAB_EXP', O."Code"), '500102') AS "LAB",
           IFNULL("MTC_CA_F_ACCT"('MFG_EXP_PREFIX', O."Code"), '5101') AS "MFGP",
           IFNULL("MTC_CA_F_PARAM"('EXP_JDT_TRANSCODES', O."Code"), ',,') AS "CODES"
      FROM "OFPR" O
     WHERE O."Code" = ?
),

-- ② 已过账凭证（OJDT / JDT1）：过账日期在本期，科目是人工科目或以制造费用前缀开头，
--    凭证代码 OJDT.TransCode 在 EXP_JDT_TRANSCODES 中。金额 = 借 − 贷；人工科目记 LAB，其余记 MFG
JDT_EXP AS (
    SELECT 'JDT' AS "Src", T1."TransId" || '-' || T1."Line_ID" AS "SrcKey", IFNULL(T0."TransCode", '') AS "SrcTrans",
           TO_NVARCHAR(T0."TransType") AS "SrcObj", T0."CreatedBy" AS "SrcDoc", T0."Number" AS "JdtNum",
           TO_DATE(T0."RefDate") AS "DocDate", T1."Account" AS "AcctCode", T1."ProfitCode" AS "OcrCode",
           CASE WHEN T1."Account" = P."LAB" THEN 'LAB' ELSE 'MFG' END AS "Elem",
           T1."Debit" - T1."Credit" AS "Amount", CAST(NULL AS NVARCHAR(200)) AS "Note"
      FROM "OJDT" T0
      JOIN "JDT1" T1 ON T1."TransId" = T0."TransId"
      CROSS JOIN P
     WHERE T0."RefDate" BETWEEN P."D0" AND P."D1"
       AND (T1."Account" = P."LAB" OR T1."Account" LIKE P."MFGP" || '%')
       AND LOCATE(P."CODES", ',' || IFNULL(T0."TransCode", '') || ',') > 0
),

-- ③ 库存重估单 @MTC_OMRV（未作废、单据日期在本期），费用 = −U_Amount，全部记制造 MFG：
--    U_BaseType = 'MRV1' 的全部行（含 InvntCost）；
--    U_BaseType = 'ProWW' 中行上 U_BaseType / U_BaseEntry 找不到订单的行（找得到的记到订单，见 subfee.sql）
MRV_EXP AS (
    SELECT CASE WHEN T0."U_BaseType" = 'ProWW' THEN 'PROWW' ELSE 'MRV' END AS "Src",
           T1."DocEntry" || '-' || T1."LineId" AS "SrcKey", T0."U_BaseType" AS "SrcTrans",
           IFNULL(T0."Object", 'MTC_OMRV') AS "SrcObj", T1."DocEntry" AS "SrcDoc", T0."DocNum" AS "JdtNum",
           TO_DATE(T0."U_DocDate") AS "DocDate", T1."U_AcctCode" AS "AcctCode", CAST(NULL AS NVARCHAR(8)) AS "OcrCode",
           'MFG' AS "Elem", -T1."U_Amount" AS "Amount",
           CASE WHEN T0."U_BaseType" = 'ProWW' THEN '没有关联到订单的委外重估' ELSE '重估类型 ' || IFNULL(T1."U_CalType", '') END AS "Note"
      FROM "@MTC_OMRV" T0
      JOIN "@MTC_OMRV1" T1 ON T1."DocEntry" = T0."DocEntry"
      LEFT JOIN "OWOR" W ON T1."U_BaseType" = '202' AND W."DocEntry" = T1."U_BaseEntry"
      LEFT JOIN "@MTC_OWOR" M ON T1."U_BaseType" = 'MTC_OWOR' AND M."DocEntry" = T1."U_BaseEntry"
      CROSS JOIN P
     WHERE IFNULL(T0."Canceled", 'N') = 'N'
       AND T0."U_DocDate" BETWEEN P."D0" AND P."D1"
       AND (T0."U_BaseType" = 'MRV1'
            OR (T0."U_BaseType" = 'ProWW' AND W."DocEntry" IS NULL AND M."DocEntry" IS NULL))
),

-- ③-2 历史委外差异转出（用户 2026-11-04）：本期计划转出的已关闭委外订单，科目和成本中心取参数 WW_HIST_EXP、WW_HIST_OCR
HIST_EXP AS (
    SELECT 'WWHIST' AS "Src", H."OrderType" || '-' || H."OrderEntry" AS "SrcKey", 'JZ05' AS "SrcTrans",
           H."OrderType" AS "SrcObj", H."OrderEntry" AS "SrcDoc", CAST(NULL AS INTEGER) AS "JdtNum",
           P."D1" AS "DocDate", "MTC_CA_F_ACCT"('WW_HIST_EXP', P."FC") AS "AcctCode",
           CAST("MTC_CA_F_PARAM"('WW_HIST_OCR', P."FC") AS NVARCHAR(8)) AS "OcrCode",
           'MFG' AS "Elem", H."Amount", '历史委外差异转出：订单号 Num ' || IFNULL(TO_NVARCHAR(H."DocNum"), '') AS "Note"
      FROM "MTC_CA_WW_HIST" H
      CROSS JOIN P
     WHERE H."PlanFc" = P."FC"
),

-- ④ 费用池：按成本中心（凭证行 ProfitCode）归池。成本中心 → 池在 B1 主数据 @MTC_CA_POOL（子表 1）维护，
--    也可按成本中心 OPRC.U_CalType 归池；每次计算由 P05 同步到 MTC_CA_C_POOL_SRC。
--    没配置或没有成本中心（重估行）的进默认池（@MTC_CA_POOL 中 U_IsDefault = Y 的池）
DEF_POOL AS (
    SELECT MAX("PoolCode") AS "PoolCode" FROM "MTC_CA_C_POOL" WHERE "IsDefault" = 'Y'
),
EXP_LINE AS (
    SELECT E.*, IFNULL(PS."PoolCode", D."PoolCode") AS "PoolCode",
           CASE WHEN PS."PoolCode" IS NOT NULL THEN '成本中心归池' ELSE '默认池' END AS "PoolBasis"
      FROM (SELECT * FROM JDT_EXP UNION ALL SELECT * FROM MRV_EXP UNION ALL SELECT * FROM HIST_EXP) E
      CROSS JOIN P
      CROSS JOIN DEF_POOL D
      LEFT JOIN "MTC_CA_C_POOL_SRC" PS ON PS."OcrCode" = E."OcrCode" AND P."FC" BETWEEN PS."FromFc" AND PS."ToFc"
),
-- ⑤ 输出（= 快照表 MTC_CA_S_EXP，加上归到的池）
EXP_OUT AS (
    SELECT L."PoolCode", C."PoolName", L."PoolBasis", L."Elem", L."Src", L."SrcTrans", L."DocDate", L."AcctCode", A."AcctName",
           L."OcrCode", L."SrcObj", L."SrcDoc", L."JdtNum", L."Amount", L."Note", L."SrcKey"
      FROM EXP_LINE L
      LEFT JOIN "MTC_CA_C_POOL" C ON C."PoolCode" = L."PoolCode"
      LEFT JOIN "OACT" A ON A."AcctCode" = L."AcctCode"
)
-- @result 以下是输出；执行台“与计算结果比对”会把这一段换成比对语句
SELECT * FROM EXP_OUT
 ORDER BY "PoolCode", "Elem", "Src", "SrcTrans", "AcctCode", "DocDate", "SrcKey"
