-- =====================================================================
-- 排查：期初承接数据是否正确（用户 2026-11-04）
-- 只读，不进部署包。前提：已执行 MTC_CA_P_BOOTSTRAP；③ 要已部署 MTC_CA_WW_HIST，④ 要起始账期跑过计算或只做检查。
-- 用法：改掉每段 P 里的账期（= BOOTSTRAP_FC），逐段执行。金额看过自己判断，按数据边界只需反馈哪一行不通过。
-- 未在库上执行过。
-- =====================================================================

-- ① 承接表和旧框架来源逐项核对：全部应为“通过”
WITH P AS (SELECT '2026-09' AS "Fc" FROM DUMMY),
D AS (SELECT P."Fc", TO_DATE(O."T_RefDate") AS "D1" FROM P JOIN "OFPR" O ON O."Code" = P."Fc"),
-- 截至承接账期期末未关闭的订单，条件同 MTC_CA_P_BOOTSTRAP
ORD AS (SELECT '202' AS "OT", W."DocEntry" AS "OE" FROM "OWOR" W, D
         WHERE (W."Status" <> 'C' OR TO_DATE(W."UpdateDate") > D."D1") AND IFNULL(TO_DATE(W."PostDate"), D."D1") <= D."D1"
           AND NOT (W."Status" = 'L' AND IFNULL(TO_DATE(W."CloseDate"), D."D1") <= D."D1")
        UNION ALL
        SELECT 'MTC_OWOR', W."DocEntry" FROM "@MTC_OWOR" W, D
         WHERE (W."U_Status" <> 'C' OR TO_DATE(W."UpdateDate") > D."D1") AND IFNULL(TO_DATE(W."U_PostDate"), D."D1") <= D."D1"
           AND NOT (W."U_Status" = 'L' AND IFNULL(TO_DATE(W."U_CloseDate"), D."D1") <= D."D1")),
Z1 AS (SELECT T."DocType" AS "OT", T."WorEntry" AS "OE", SUM(IFNULL(T."Amount", 0)) AS "W"
         FROM "MTC_COST_0322_OWOR_ZCP1" T, P WHERE T."FcCode" = P."Fc" GROUP BY T."DocType", T."WorEntry"),
Z AS (SELECT IFNULL(T."DocType", '202') AS "OT", T."WorEntry" AS "OE", SUM(IFNULL(T."在产品新", 0)) AS "W"
        FROM "MTC_COST_0322_OWOR_ZCP" T, P WHERE T."期间" = P."Fc" GROUP BY IFNULL(T."DocType", '202'), T."WorEntry"),
R AS (
    SELECT 1 AS "No", '物料期末金额 = 旧 0301' AS "Item",
           (SELECT SUM(B."Amount") FROM "MTC_CA_BOOT_ITEM" B, P WHERE B."FcCode" = P."Fc") AS "A",
           (SELECT SUM(IFNULL(O."QM_Amount", 0)) FROM "MTC_COST_0301_INVNT" O, P WHERE O."FcCode" = P."Fc" AND O."CostCode" = '20') AS "B" FROM DUMMY
    UNION ALL
    SELECT 2, '物料期末数量 = 旧 0301',
           (SELECT SUM(B."Qty") FROM "MTC_CA_BOOT_ITEM" B, P WHERE B."FcCode" = P."Fc"),
           (SELECT SUM(IFNULL(O."QM_Qty", 0)) FROM "MTC_COST_0301_INVNT" O, P WHERE O."FcCode" = P."Fc" AND O."CostCode" = '20') FROM DUMMY
    UNION ALL
    SELECT 3, '料工费四项合计不等于金额的物料数（应为 0）',
           (SELECT COUNT(*) FROM "MTC_CA_BOOT_ITEM" B, P WHERE B."FcCode" = P."Fc"
             AND ABS(B."MatAmt" + B."MfgAmt" + B."LabAmt" + B."SubAmt" - B."Amount") >= 0.01), 0 FROM DUMMY
    UNION ALL
    SELECT 4, '比例四项合计不等于 1 的物料数（应为 0）',
           (SELECT COUNT(*) FROM "MTC_CA_BOOT_RATIO" B, P WHERE B."FcCode" = P."Fc"
             AND ABS(B."RMat" + B."RMfg" + B."RLab" + B."RSub" - 1) > 0.000001), 0 FROM DUMMY
    UNION ALL
    SELECT 5, '未关闭订单在产品 = 旧 ZCP1',
           (SELECT SUM(B."WipAmt") FROM "MTC_CA_BOOT_ORDER_MAT" B, P WHERE B."FcCode" = P."Fc"),
           (SELECT SUM(X."W") FROM Z1 X JOIN ORD O ON O."OT" = X."OT" AND O."OE" = X."OE") FROM DUMMY
    UNION ALL
    SELECT 6, '未关闭订单在产品 = 旧 ZCP 在产品新',
           (SELECT SUM(B."WipAmt") FROM "MTC_CA_BOOT_ORDER_MAT" B, P WHERE B."FcCode" = P."Fc"),
           (SELECT SUM(X."W") FROM Z X JOIN ORD O ON O."OT" = X."OT" AND O."OE" = X."OE") FROM DUMMY
    UNION ALL
    SELECT 7, 'ZCP1 与 ZCP 不一致的未关闭订单数（BOOT-01，应为 0）',
           (SELECT COUNT(*) FROM "MTC_CA_V_BOOT_CHECK" V, P WHERE V."FcCode" = P."Fc" AND V."Issue" = 'ZCP1≠ZCP'), 0 FROM DUMMY
    UNION ALL
    SELECT 8, '在产品大于累计领料的行数（应为 0，有行时看明细）',
           (SELECT COUNT(*) FROM "MTC_CA_V_BOOT_CHECK" V, P WHERE V."FcCode" = P."Fc" AND V."Issue" = '在产品>累计领料'), 0 FROM DUMMY
)
SELECT "No" AS "序号", "Item" AS "核对项", "A" AS "承接表", "B" AS "来源", IFNULL("A", 0) - IFNULL("B", 0) AS "差额",
       CASE WHEN ABS(IFNULL("A", 0) - IFNULL("B", 0)) < 0.01 THEN '通过' ELSE '不通过' END AS "结果"
  FROM R ORDER BY "No";

-- ② 存货科目：承接金额和总账（含未清凭单）。差额是承接前就有的财务业务差异，应等于执行台“财务对账”起始账期的期初差额
WITH P AS (SELECT '2026-09' AS "Fc" FROM DUMMY),
D AS (SELECT P."Fc", TO_DATE(O."T_RefDate") AS "D1" FROM P JOIN "OFPR" O ON O."Code" = P."Fc"),
A AS (SELECT "ItmsGrpCod", MAX("StockAct") AS "Acct" FROM "OGAR", P WHERE "PeriodCat" = LEFT(P."Fc", 4) GROUP BY "ItmsGrpCod"),
BZ AS (SELECT A."Acct", SUM(B."Amount") AS "Amt"
         FROM "MTC_CA_BOOT_ITEM" B JOIN P ON P."Fc" = B."FcCode"
         JOIN "OITM" I ON I."ItemCode" = B."ItemCode" LEFT JOIN A ON A."ItmsGrpCod" = I."ItmsGrpCod"
        GROUP BY A."Acct"),
GL AS (SELECT X."Acct", SUM(X."Amt") AS "Amt" FROM (
           SELECT J."Account" AS "Acct", J."Debit" - J."Credit" AS "Amt" FROM "OJDT" H JOIN "JDT1" J ON J."TransId" = H."TransId", D
            WHERE H."RefDate" <= D."D1"
           UNION ALL
           SELECT T1."Account", T1."Debit" - T1."Credit" FROM "OBTF" T0 JOIN "BTF1" T1 ON T1."TransId" = T0."TransId" AND T1."BatchNum" = T0."BatchNum", D
            WHERE T0."BtfStatus" = 'O' AND T0."RefDate" <= D."D1") X
        WHERE X."Acct" IN (SELECT "Acct" FROM A) GROUP BY X."Acct")
SELECT IFNULL(G."Acct", B."Acct") AS "存货科目", G."Amt" AS "总账", B."Amt" AS "承接金额", IFNULL(G."Amt", 0) - IFNULL(B."Amt", 0) AS "差额"
  FROM GL G FULL JOIN BZ B ON B."Acct" = G."Acct"
 ORDER BY ABS(IFNULL(G."Amt", 0) - IFNULL(B."Amt", 0)) DESC;

-- ③ 在产品科目：140801 总账 − 未关闭委外在产品 − 历史委外待转 应接近 0；500101 没有待转，差额看生产在产品
WITH P AS (SELECT '2026-09' AS "Fc" FROM DUMMY),
D AS (SELECT P."Fc", TO_DATE(O."T_RefDate") AS "D1", "MTC_CA_F_ACCT"('WW_MAT', P."Fc") AS "WwAcct", "MTC_CA_F_ACCT"('WIP_PROD', P."Fc") AS "ProdAcct",
             IFNULL("MTC_CA_F_PARAM"('WW_WORTYPES', P."Fc"), ',50,') AS "WwWt"
        FROM P JOIN "OFPR" O ON O."Code" = P."Fc"),
T AS (SELECT '202' AS "OT", "DocEntry" AS "OE", TO_NVARCHAR("U_OrdType") AS "WorType" FROM "OWOR"
      UNION ALL SELECT 'MTC_OWOR', "DocEntry", TO_NVARCHAR("U_OrdType") FROM "@MTC_OWOR"),
W AS (SELECT SUM(CASE WHEN LOCATE(D."WwWt", ',' || IFNULL(T."WorType", '') || ',') > 0 THEN B."WipAmt" ELSE 0 END) AS "Ww",
             SUM(CASE WHEN LOCATE(D."WwWt", ',' || IFNULL(T."WorType", '') || ',') = 0 THEN B."WipAmt" ELSE 0 END) AS "Prod"
        FROM "MTC_CA_BOOT_ORDER_MAT" B CROSS JOIN D
        LEFT JOIN T ON T."OT" = B."OrderType" AND T."OE" = B."OrderEntry"
       WHERE B."FcCode" = D."Fc"),
G AS (SELECT X."Acct", SUM(X."Amt") AS "Amt" FROM (
          SELECT J."Account" AS "Acct", J."Debit" - J."Credit" AS "Amt" FROM "OJDT" H JOIN "JDT1" J ON J."TransId" = H."TransId", D
           WHERE H."RefDate" <= D."D1"
          UNION ALL
          SELECT T1."Account", T1."Debit" - T1."Credit" FROM "OBTF" T0 JOIN "BTF1" T1 ON T1."TransId" = T0."TransId" AND T1."BatchNum" = T0."BatchNum", D
           WHERE T0."BtfStatus" = 'O' AND T0."RefDate" <= D."D1") X, D
       WHERE X."Acct" IN (D."WwAcct", D."ProdAcct") GROUP BY X."Acct"),
H AS (SELECT IFNULL(SUM("Amount"), 0) AS "Amt" FROM "MTC_CA_WW_HIST" WHERE "Manual" = 'N')
SELECT D."WwAcct" AS "科目", IFNULL(G."Amt", 0) AS "总账", IFNULL(W."Ww", 0) AS "未关闭在产品", H."Amt" AS "历史待转",
       IFNULL(G."Amt", 0) - IFNULL(W."Ww", 0) - H."Amt" AS "差额"
  FROM D CROSS JOIN W CROSS JOIN H LEFT JOIN G ON G."Acct" = D."WwAcct"
UNION ALL
SELECT D."ProdAcct", IFNULL(G."Amt", 0), IFNULL(W."Prod", 0), 0, IFNULL(G."Amt", 0) - IFNULL(W."Prod", 0)
  FROM D CROSS JOIN W LEFT JOIN G ON G."Acct" = D."ProdAcct";

-- ④ 起始账期最近一次运行读到的期初 = 承接表；全部应为“通过”
WITH P AS (SELECT '2026-09' AS "Fc", "MTC_CA_F_PARAM"('START_FC', '2026-09') AS "Start" FROM DUMMY),
U AS (SELECT MAX(R."RunId") AS "RunId" FROM "MTC_CA_RUN" R, P WHERE R."FcCode" = P."Start" AND R."RunType" = 'F' AND R."Scenario" = ''
       AND EXISTS (SELECT 1 FROM "MTC_CA_S_OPEN" S WHERE S."RunId" = R."RunId")),
R AS (
    SELECT 1 AS "No", '运行读到的物料期初金额 = 承接表' AS "Item",
           (SELECT SUM(S."Amount") FROM "MTC_CA_S_OPEN" S, U WHERE S."RunId" = U."RunId") AS "A",
           (SELECT SUM(B."Amount") FROM "MTC_CA_BOOT_ITEM" B, P WHERE B."FcCode" = P."Fc") AS "B" FROM DUMMY
    UNION ALL
    SELECT 2, '运行读到的订单累计领料 = 承接表',
           (SELECT SUM(S."CumIssueMat" + S."CumIssueMfg" + S."CumIssueLab" + S."CumIssueSub") FROM "MTC_CA_S_ORDER_OPEN" S, U
             WHERE S."RunId" = U."RunId" AND S."ItemCode" <> '#SUBFEE'),
           (SELECT SUM(B."CumIssueAmt") FROM "MTC_CA_BOOT_ORDER_MAT" B, P WHERE B."FcCode" = P."Fc") FROM DUMMY
    UNION ALL
    SELECT 3, '运行读到的订单在产品（累计领料 − 累计结转）= 承接表',
           (SELECT SUM(S."CumIssueMat" + S."CumIssueMfg" + S."CumIssueLab" + S."CumIssueSub"
                       - S."CumCarriedMat" - S."CumCarriedMfg" - S."CumCarriedLab" - S."CumCarriedSub") FROM "MTC_CA_S_ORDER_OPEN" S, U
             WHERE S."RunId" = U."RunId" AND S."ItemCode" <> '#SUBFEE'),
           (SELECT SUM(B."WipAmt") FROM "MTC_CA_BOOT_ORDER_MAT" B, P WHERE B."FcCode" = P."Fc") FROM DUMMY
)
SELECT (SELECT "RunId" FROM U) AS "运行号", "Item" AS "核对项", "A" AS "运行", "B" AS "承接表", IFNULL("A", 0) - IFNULL("B", 0) AS "差额",
       CASE WHEN ABS(IFNULL("A", 0) - IFNULL("B", 0)) < 0.01 THEN '通过' ELSE '不通过' END AS "结果"
  FROM R ORDER BY "No";
