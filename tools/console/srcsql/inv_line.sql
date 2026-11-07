/* =====================================================================
 * 收发存 · 取数 SQL（只读，直接从 B1 单据取）
 *
 * 结果：本期参与成本计算的每一条库存变动（收发存明细的来源），带交易类型、方向、所属订单、
 *       数量、B1 金额，以及有固定来源金额的行（采购、发票差异、重估）的金额。
 * 对应：新框架 MTC_CA_P20_LINE（快照 MTC_CA_S_LINE）。两边口径相同，执行台“与计算结果比对”逐行核对。
 *       旧模块的对应：0303_INVNTDETAIL2 / 0302_INVNTDETAIL1。
 * 不在本语句里的：
 *   · 单价和出库金额：由计算（P30–P50，按层级加权平均、迭代）算出，见“物料单价”“收发存汇总”页；
 *   · 期初：取上期计算结果或期初承接，不是 B1 单据；
 *   · 库存物料的采购收货 / 退货 / 发票差额，最终改用应付暂估口径（见 ap_accr.sql），
 *     本语句的 SrcAmt 列是旧 0303 规则的金额，仅供参考，比对时不比这几类单据的金额；
 *   · 委外加工费发票差异（APDIF，I11）同样来自 ap_accr.sql。
 * 用法：第 ① 段的参数换成账期，例如 '2026-09'，整段执行。
 *       排查时可以把最后的 SELECT 换成 SELECT * FROM 某一段（如 DOC、PUR_AMT），看中间结果。
 * ===================================================================== */
WITH
-- ① 账期：起止日取 OFPR；公摊材料的科目前缀取 MFG_EXP_PREFIX（默认 5101）
P AS (
    SELECT O."Code" AS "FC", TO_DATE(O."F_RefDate") AS "D0", TO_DATE(O."T_RefDate") AS "D1",
           IFNULL("MTC_CA_F_ACCT"('MFG_EXP_PREFIX', O."Code"), '5101') AS "MFGP"
      FROM "OFPR" O
     WHERE O."Code" = ?
),

-- ② 计价仓库：OWHS.U_IsCost = 'Y'；新框架配置表 MTC_CA_C_WHS 里单独登记的仓库以配置为准（= 视图 MTC_CA_V_WHS）
WHS AS (
    SELECT W."WhsCode"
      FROM "OWHS" W
      LEFT JOIN "MTC_CA_C_WHS" C ON C."WhsCode" = W."WhsCode"
     WHERE COALESCE(C."IsCost", CASE WHEN W."U_IsCost" = 'Y' THEN 'Y' ELSE 'N' END) = 'Y'
),

-- ③ 单据行的业务含义：视图 MTC_VIEW_Document 把各类单据行映射成交易类型 TransCode（I01…O10），
--    收货 / 发货（59/60）的 BaseType / BaseEntry / BaseLine 被改写为所属订单（202 生产订单、MTC_OWOR 返工单），
--    形态转换（业务类型 204/205）改写为配对的出库单行
DOC0 AS (
    SELECT TO_NVARCHAR(V."ObjType") AS "ObjType", TO_NVARCHAR(V."DocEntry") AS "DocEntry", TO_NVARCHAR(V."LineNum") AS "LineNum",
           V."CANCELED", V."CardCode", TO_NVARCHAR(V."BaseType") AS "BaseType", TO_NVARCHAR(V."BaseEntry") AS "BaseEntry",
           TO_NVARCHAR(V."BaseLine") AS "BaseLine", NULLIF(V."TransCode", '') AS "TransCode", V."U_BusiType", V."AcctCode", V."OcrCode"
      FROM "MTC_VIEW_Document" V CROSS JOIN P
     WHERE V."DocDate" BETWEEN P."D0" AND P."D1"
),

-- ③b 收货 / 发货行的订单兜底（与 P20_LINE 同口径，2026-10-29）：视图只在 IGN1 / IGE1.BaseType = -1 时看 U_OWORType；
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

-- ④ 采购类单据的来源金额（旧 0303 规则，参考）：
--    收货 = 数量 × 暂估单价（U_InitPrice 优先，否则 Price）；退货 = −(数量 × U_InitPrice，否则 LineTotal)；
--    发票 / 贷项基于收货 / 退货时 = 行金额 − 数量 × 收货暂估单价（差额），否则 = 行金额；取消单 = 原单金额取反
REC_PRICE AS (
    SELECT '20' AS "ObjType", D."DocEntry", D."LineNum",
           CASE WHEN IFNULL(D."U_InitPrice", 0) <> 0 THEN D."U_InitPrice" ELSE D."Price" END AS "Price"
      FROM "PDN1" D
    UNION ALL
    SELECT '21', D."DocEntry", D."LineNum",
           CASE WHEN IFNULL(D."U_InitPrice", 0) <> 0 THEN D."U_InitPrice" ELSE D."Price" END
      FROM "RPD1" D
),
INV18 AS (
    SELECT D."DocEntry", D."LineNum", TO_DATE(M."DocDate") AS "DocDate", M."CANCELED", D."BaseType", D."BaseEntry", D."BaseLine",
           CASE WHEN D."BaseType" IN (20, 21) THEN D."LineTotal" - D."Quantity" * IFNULL(R."Price", 0) ELSE D."LineTotal" END AS "Amt"
      FROM "OPCH" M JOIN "PCH1" D ON D."DocEntry" = M."DocEntry"
      LEFT JOIN REC_PRICE R ON R."ObjType" = TO_NVARCHAR(D."BaseType") AND R."DocEntry" = D."BaseEntry" AND R."LineNum" = D."BaseLine"
),
INV19 AS (
    SELECT D."DocEntry", D."LineNum", TO_DATE(M."DocDate") AS "DocDate", M."CANCELED", D."BaseType", D."BaseEntry", D."BaseLine",
           CASE WHEN D."BaseType" IN (20, 21) THEN D."LineTotal" - D."Quantity" * IFNULL(R."Price", 0) ELSE D."LineTotal" END AS "Amt"
      FROM "ORPC" M JOIN "RPC1" D ON D."DocEntry" = M."DocEntry"
      LEFT JOIN REC_PRICE R ON R."ObjType" = TO_NVARCHAR(D."BaseType") AND R."DocEntry" = D."BaseEntry" AND R."LineNum" = D."BaseLine"
),
PUR_AMT AS (
    SELECT '20' AS "ObjType", D."DocEntry", D."LineNum",
           CASE WHEN M."CANCELED" = 'C' THEN -1 ELSE 1 END
           * CASE WHEN IFNULL(D."U_InitPrice", 0) <> 0 THEN D."U_InitPrice" * D."Quantity" ELSE D."Price" * D."Quantity" END AS "Amt"
      FROM "OPDN" M JOIN "PDN1" D ON D."DocEntry" = M."DocEntry" CROSS JOIN P
     WHERE M."DocDate" BETWEEN P."D0" AND P."D1"
    UNION ALL
    SELECT '21', D."DocEntry", D."LineNum",
           CASE WHEN M."CANCELED" = 'C' THEN 1 ELSE -1 END
           * CASE WHEN IFNULL(D."U_InitPrice", 0) <> 0 THEN D."U_InitPrice" * D."Quantity" ELSE D."LineTotal" END
      FROM "ORPD" M JOIN "RPD1" D ON D."DocEntry" = M."DocEntry" CROSS JOIN P
     WHERE M."DocDate" BETWEEN P."D0" AND P."D1"
    UNION ALL
    SELECT '18', A."DocEntry", A."LineNum", CASE WHEN A."CANCELED" = 'C' THEN -IFNULL(O."Amt", 0) ELSE A."Amt" END
      FROM INV18 A
      LEFT JOIN INV18 O ON A."CANCELED" = 'C' AND A."BaseType" = 18 AND O."DocEntry" = A."BaseEntry" AND O."LineNum" = A."BaseLine"
      CROSS JOIN P
     WHERE A."DocDate" BETWEEN P."D0" AND P."D1"
    UNION ALL
    SELECT '19', A."DocEntry", A."LineNum", CASE WHEN A."CANCELED" = 'C' THEN IFNULL(O."Amt", 0) ELSE -A."Amt" END
      FROM INV19 A
      LEFT JOIN INV19 O ON A."CANCELED" = 'C' AND A."BaseType" = 19 AND O."DocEntry" = A."BaseEntry" AND O."LineNum" = A."BaseLine"
      CROSS JOIN P
     WHERE A."DocDate" BETWEEN P."D0" AND P."D1"
),

-- ⑤ 库存记录 OIVL：本期、计价仓库、排除库存转储（67）。每条 OIVL 一行。
--    订单关联：只有工单交易 I03/O03/I07/O07/I08/O08/I09/O09 的收货 / 发货（59/60）关联订单，
--    其他交易（如 210 其他辅助领用 O04）填了订单号也不关联、不计入订单成本（用户 2026-10-14）；完工入库的订单行为空。
--    销售退货的原交货：标准来源不是交货时，取 RDN1.U_BaseType = '15' / U_BaseEntry / U_BaseLine。
--    公摊材料 SharedExp：其他收发货、盘点（I04/O04/I10/O10）且科目以制造费用前缀开头的行，出库金额进费用池。
OIVL_LINE AS (
    SELECT 'OIVL' AS "Src", TO_NVARCHAR(L."TransSeq") AS "SrcKey", TO_DATE(L."DocDate") AS "DocDate",
           TO_NVARCHAR(L."TransType") AS "ObjType", TO_NVARCHAR(L."BASE_REF") AS "DocNum", L."CreatedBy" AS "DocEntry", L."DocLineNum" AS "LineNum",
           V."CANCELED" AS "Canceled", L."ItemCode", L."LocCode" AS "WhsCode",
           V."TransCode", IO."U_IOType" AS "Dir", V."U_BusiType" AS "BusiType", C."U_TransType" AS "BusiClass",
           L."InQty" - L."OutQty" AS "Qty", L."SumStock" AS "B1Amt", S."Amt" AS "SrcAmt",
           CASE WHEN V."ObjType" IN ('59', '60') AND IFNULL(V."U_BusiType", '') NOT IN ('204', '205')
                 AND V."TransCode" IN ('I03', 'O03', 'I07', 'O07', 'I08', 'O08', 'I09', 'O09')
                 AND V."BaseType" IN ('202', 'MTC_OWOR') THEN V."BaseType" END AS "OrderType",
           CASE WHEN V."ObjType" IN ('59', '60') AND IFNULL(V."U_BusiType", '') NOT IN ('204', '205')
                 AND V."TransCode" IN ('I03', 'O03', 'I07', 'O07', 'I08', 'O08', 'I09', 'O09')
                 AND V."BaseType" IN ('202', 'MTC_OWOR') AND V."BaseEntry" LIKE_REGEXPR '^[0-9]+$' THEN TO_INTEGER(V."BaseEntry") END AS "OrderEntry",
           CASE WHEN V."ObjType" IN ('59', '60') AND IFNULL(V."U_BusiType", '') NOT IN ('204', '205')
                 AND V."TransCode" IN ('I03', 'O03', 'I07', 'O07', 'I08', 'O08', 'I09', 'O09')
                 AND V."BaseType" IN ('202', 'MTC_OWOR') AND V."BaseLine" LIKE_REGEXPR '^[0-9]+$' THEN TO_INTEGER(V."BaseLine") END AS "OrderLine",
           CASE WHEN V."U_BusiType" IN ('204', '205') AND V."BaseType" IS NOT NULL AND V."BaseEntry" IS NOT NULL AND V."BaseLine" IS NOT NULL
                THEN V."BaseType" || '-' || V."BaseEntry" || '-' || V."BaseLine" END AS "PairKey",
           CASE WHEN R16."DocEntry" IS NOT NULL THEN '15' ELSE V."BaseType" END AS "BaseType",
           CASE WHEN R16."DocEntry" IS NOT NULL THEN TO_NVARCHAR(R16."U_BaseEntry") ELSE V."BaseEntry" END AS "BaseEntry",
           CASE WHEN R16."DocEntry" IS NOT NULL THEN TO_NVARCHAR(R16."U_BaseLine") ELSE V."BaseLine" END AS "BaseLine",
           CASE WHEN V."ObjType" IN ('59', '60') AND V."TransCode" IN ('I04', 'O04', 'I10', 'O10')
                 AND V."AcctCode" LIKE P."MFGP" || '%' THEN 'Y' ELSE 'N' END AS "SharedExp",
           V."AcctCode", V."OcrCode", V."CardCode", 'N' AS "NoCost"
      FROM "OIVL" L
      CROSS JOIN P
      JOIN WHS W ON W."WhsCode" = L."LocCode"
      LEFT JOIN DOC V ON V."ObjType" = TO_NVARCHAR(L."TransType") AND V."DocEntry" = TO_NVARCHAR(L."CreatedBy")
                     AND V."LineNum" = TO_NVARCHAR(L."DocLineNum")
      LEFT JOIN PUR_AMT S ON S."ObjType" = TO_NVARCHAR(L."TransType") AND S."DocEntry" = L."CreatedBy" AND S."LineNum" = L."DocLineNum"
      LEFT JOIN "@MTC_COST_IOTYPE" IO ON IO."Code" = V."TransCode"
      LEFT JOIN "@U_CIOTRN" C ON C."Code" = V."U_BusiType"
      LEFT JOIN "RDN1" R16 ON V."ObjType" = '16' AND IFNULL(V."CANCELED", 'N') <> 'C' AND IFNULL(V."BaseType", '') <> '15'
                          AND R16."DocEntry" = L."CreatedBy" AND R16."LineNum" = L."DocLineNum"
                          AND TO_NVARCHAR(R16."U_BaseType") = '15' AND R16."U_BaseEntry" IS NOT NULL AND R16."U_BaseLine" IS NOT NULL
     WHERE L."DocDate" BETWEEN P."D0" AND P."D1"
       AND L."TransType" <> 67
),

-- ⑥ 库存重估单 @MTC_OMRV（U_BaseType = 'MRV1'，未作废、单据日期在本期）→ I11，只有金额没有数量。
--    重估类型 U_CalType = 'InvntCost' 的只调整结存，不参与当期成本计算（NoCost = Y）。
--    WW（旧 6101_1 写的委外发票差异）不再读，改由 ap_accr.sql 从发票直接计算。
MRV_LINE AS (
    SELECT 'OMRV' AS "Src", T1."DocEntry" || '-' || T1."LineId" AS "SrcKey", TO_DATE(T0."U_DocDate") AS "DocDate",
           IFNULL(T0."Object", 'MTC_OMRV') AS "ObjType", TO_NVARCHAR(T0."DocNum") AS "DocNum", T1."DocEntry", T1."LineId" AS "LineNum",
           T0."Canceled", IFNULL(T1."U_ItemCode", '') AS "ItemCode", CAST(NULL AS NVARCHAR(8)) AS "WhsCode",
           'I11' AS "TransCode", IO."U_IOType" AS "Dir", CAST(NULL AS NVARCHAR(50)) AS "BusiType", CAST(NULL AS NVARCHAR(50)) AS "BusiClass",
           0 AS "Qty", NULL AS "B1Amt", T1."U_Amount" AS "SrcAmt",
           NULL AS "OrderType", NULL AS "OrderEntry", NULL AS "OrderLine", NULL AS "PairKey",
           T1."U_BaseType" AS "BaseType", TO_NVARCHAR(T1."U_BaseEntry") AS "BaseEntry", TO_NVARCHAR(T1."U_BaseLine") AS "BaseLine",
           'N' AS "SharedExp", T1."U_AcctCode" AS "AcctCode", NULL AS "OcrCode", NULL AS "CardCode",
           CASE WHEN T1."U_CalType" = 'InvntCost' THEN 'Y' ELSE 'N' END AS "NoCost"
      FROM "@MTC_OMRV" T0
      JOIN "@MTC_OMRV1" T1 ON T1."DocEntry" = T0."DocEntry"
      LEFT JOIN "@MTC_COST_IOTYPE" IO ON IO."Code" = 'I11'
      CROSS JOIN P
     WHERE T0."U_BaseType" = 'MRV1'
       AND IFNULL(T0."Canceled", 'N') = 'N'
       AND T0."U_DocDate" BETWEEN P."D0" AND P."D1"
),

-- ⑦ 全部库存变动（= 快照表 MTC_CA_S_LINE 中 Src 为 OIVL、OMRV 的行）
ALL_LINE AS (
    SELECT "Src", "SrcKey", "DocDate", "ObjType", "DocNum", "DocEntry", "LineNum", "Canceled", "ItemCode", "WhsCode",
           "TransCode", "Dir", "BusiType", "BusiClass", "Qty", "B1Amt", "SrcAmt", "OrderType", "OrderEntry", "OrderLine",
           "PairKey", "BaseType", "BaseEntry", "BaseLine", "SharedExp", "AcctCode", "OcrCode", "CardCode", "NoCost"
      FROM OIVL_LINE
    UNION ALL
    SELECT "Src", "SrcKey", "DocDate", "ObjType", "DocNum", "DocEntry", "LineNum", "Canceled", "ItemCode", "WhsCode",
           "TransCode", "Dir", "BusiType", "BusiClass", "Qty", "B1Amt", "SrcAmt", "OrderType", "OrderEntry", "OrderLine",
           "PairKey", "BaseType", "BaseEntry", "BaseLine", "SharedExp", "AcctCode", "OcrCode", "CardCode", "NoCost"
      FROM MRV_LINE
)
-- @result 以下是输出；执行台“与计算结果比对”会把这一段换成比对语句
SELECT * FROM ALL_LINE
 ORDER BY "ItemCode", "DocDate", "Src", "SrcKey"
