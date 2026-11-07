-- =====================================================================
-- 排查：140801 差异里有多少来自已关闭的历史委外订单（用户 2026-11-04，“历史委外差异转出”第 1 步）
-- 只读，不进部署包。旧 CO4001 委外订单关单日期 >= 2026-08 才把在产品转关单差异，更早关闭的留在 140801；
-- 期初承接只取未关闭订单，所以这些订单业务端为 0、总账仍有余额。
-- 用法：改掉每段 P 里的账期（= BOOTSTRAP_FC），逐段执行。金额看过自己判断，按数据边界不用贴给 AI。
-- 未在库上执行过。
-- =====================================================================

-- ① 总数：“未解释”接近 0，说明差异基本都来自已关闭订单；差得多，先看 ④。总账含手工分录，空代码合计单独列出，2026-09 已转的那笔在里面
WITH P AS (SELECT '2026-09' AS "Fc" FROM DUMMY),
D AS (SELECT P."Fc", TO_DATE(O."T_RefDate") AS "D1", "MTC_CA_F_ACCT"('WW_MAT', P."Fc") AS "Acct",
             IFNULL("MTC_CA_F_PARAM"('WW_WORTYPES', P."Fc"), ',50,') AS "WwWt"
        FROM P JOIN "OFPR" O ON O."Code" = P."Fc"),
-- 每张订单截至承接账期最后一次出现在旧在产品表的记录
Z AS (SELECT * FROM (
          SELECT IFNULL(T."DocType", '202') AS "OrderType", T."WorEntry" AS "OrderEntry", T."期间" AS "LastFc",
                 MAX(T."WorType") AS "WorType", SUM(IFNULL(T."在产品新", 0)) AS "Wip",
                 ROW_NUMBER() OVER (PARTITION BY IFNULL(T."DocType", '202'), T."WorEntry" ORDER BY T."期间" DESC) AS "Rn"
            FROM "MTC_COST_0322_OWOR_ZCP" T, D
           WHERE T."期间" <= D."Fc"
           GROUP BY IFNULL(T."DocType", '202'), T."WorEntry", T."期间")
       WHERE "Rn" = 1),
-- 截至承接账期期末不算未关闭的订单：和 MTC_CA_P_BOOTSTRAP 的“未关闭”条件互补
C AS (SELECT '202' AS "OrderType", W."DocEntry" AS "OrderEntry", W."DocNum", W."ItemCode", W."Status",
             IFNULL(TO_DATE(W."CloseDate"), D."D1") AS "CloseDate"
        FROM "OWOR" W, D
       WHERE (W."Status" = 'C' AND TO_DATE(W."UpdateDate") <= D."D1") OR (W."Status" = 'L' AND IFNULL(TO_DATE(W."CloseDate"), D."D1") <= D."D1")
      UNION ALL
      SELECT 'MTC_OWOR', W."DocEntry", W."DocNum", W."U_ItemCode", W."U_Status",
             IFNULL(TO_DATE(W."U_CloseDate"), D."D1")
        FROM "@MTC_OWOR" W, D
       WHERE (W."U_Status" = 'C' AND TO_DATE(W."UpdateDate") <= D."D1") OR (W."U_Status" = 'L' AND IFNULL(TO_DATE(W."U_CloseDate"), D."D1") <= D."D1")),
W AS (SELECT Z.*, C."DocNum", C."ItemCode", C."Status", C."CloseDate", CASE WHEN C."OrderEntry" IS NULL THEN 'N' ELSE 'Y' END AS "IsClosed"
        FROM Z CROSS JOIN D
        LEFT JOIN C ON C."OrderType" = Z."OrderType" AND C."OrderEntry" = Z."OrderEntry"
       WHERE LOCATE(D."WwWt", ',' || IFNULL(Z."WorType", '') || ',') > 0 AND Z."Wip" <> 0),
G AS (SELECT SUM(J."Debit" - J."Credit") AS "Amt",
             SUM(CASE WHEN IFNULL(H."TransCode", '') = '' THEN J."Debit" - J."Credit" ELSE 0 END) AS "Blank"
        FROM "OJDT" H JOIN "JDT1" J ON J."TransId" = H."TransId", D
       WHERE H."RefDate" <= D."D1" AND J."Account" = D."Acct"),
V AS (SELECT SUM(T1."Debit" - T1."Credit") AS "Amt"
        FROM "OBTF" T0 JOIN "BTF1" T1 ON T1."TransId" = T0."TransId" AND T1."BatchNum" = T0."BatchNum", D
       WHERE T0."BtfStatus" = 'O' AND T0."RefDate" <= D."D1" AND T1."Account" = D."Acct"),
S AS (SELECT SUM(CASE WHEN "IsClosed" = 'N' THEN "Wip" ELSE 0 END) AS "OpenWip",
             SUM(CASE WHEN "IsClosed" = 'Y' THEN 1 ELSE 0 END) AS "Cnt",
             SUM(CASE WHEN "IsClosed" = 'Y' AND "Wip" > 0 THEN "Wip" ELSE 0 END) AS "Pos",
             SUM(CASE WHEN "IsClosed" = 'Y' AND "Wip" < 0 THEN "Wip" ELSE 0 END) AS "Neg"
        FROM W)
SELECT IFNULL(G."Amt", 0) + IFNULL(V."Amt", 0) AS "财务 140801（含未清凭单）",
       IFNULL(S."OpenWip", 0) AS "业务 未关闭委外在产品",
       IFNULL(G."Amt", 0) + IFNULL(V."Amt", 0) - IFNULL(S."OpenWip", 0) AS "差异",
       IFNULL(S."Cnt", 0) AS "已关闭订单数", IFNULL(S."Pos", 0) AS "已关闭 正数合计", IFNULL(S."Neg", 0) AS "已关闭 负数合计",
       IFNULL(S."Pos", 0) + IFNULL(S."Neg", 0) AS "已关闭 净额",
       IFNULL(G."Amt", 0) + IFNULL(V."Amt", 0) - IFNULL(S."OpenWip", 0) - IFNULL(S."Pos", 0) - IFNULL(S."Neg", 0) AS "未解释",
       IFNULL(G."Blank", 0) AS "其中 空代码手工分录"
  FROM G, V, S;

-- ② 候选清单：以后勾选转出的就是这些订单，负数订单也要一起转
WITH P AS (SELECT '2026-09' AS "Fc" FROM DUMMY),
D AS (SELECT P."Fc", TO_DATE(O."T_RefDate") AS "D1", "MTC_CA_F_ACCT"('WW_MAT', P."Fc") AS "Acct",
             IFNULL("MTC_CA_F_PARAM"('WW_WORTYPES', P."Fc"), ',50,') AS "WwWt"
        FROM P JOIN "OFPR" O ON O."Code" = P."Fc"),
-- 每张订单截至承接账期最后一次出现在旧在产品表的记录
Z AS (SELECT * FROM (
          SELECT IFNULL(T."DocType", '202') AS "OrderType", T."WorEntry" AS "OrderEntry", T."期间" AS "LastFc",
                 MAX(T."WorType") AS "WorType", SUM(IFNULL(T."在产品新", 0)) AS "Wip",
                 ROW_NUMBER() OVER (PARTITION BY IFNULL(T."DocType", '202'), T."WorEntry" ORDER BY T."期间" DESC) AS "Rn"
            FROM "MTC_COST_0322_OWOR_ZCP" T, D
           WHERE T."期间" <= D."Fc"
           GROUP BY IFNULL(T."DocType", '202'), T."WorEntry", T."期间")
       WHERE "Rn" = 1),
-- 截至承接账期期末不算未关闭的订单：和 MTC_CA_P_BOOTSTRAP 的“未关闭”条件互补
C AS (SELECT '202' AS "OrderType", W."DocEntry" AS "OrderEntry", W."DocNum", W."ItemCode", W."Status",
             IFNULL(TO_DATE(W."CloseDate"), D."D1") AS "CloseDate"
        FROM "OWOR" W, D
       WHERE (W."Status" = 'C' AND TO_DATE(W."UpdateDate") <= D."D1") OR (W."Status" = 'L' AND IFNULL(TO_DATE(W."CloseDate"), D."D1") <= D."D1")
      UNION ALL
      SELECT 'MTC_OWOR', W."DocEntry", W."DocNum", W."U_ItemCode", W."U_Status",
             IFNULL(TO_DATE(W."U_CloseDate"), D."D1")
        FROM "@MTC_OWOR" W, D
       WHERE (W."U_Status" = 'C' AND TO_DATE(W."UpdateDate") <= D."D1") OR (W."U_Status" = 'L' AND IFNULL(TO_DATE(W."U_CloseDate"), D."D1") <= D."D1")),
W AS (SELECT Z.*, C."DocNum", C."ItemCode", C."Status", C."CloseDate", CASE WHEN C."OrderEntry" IS NULL THEN 'N' ELSE 'Y' END AS "IsClosed"
        FROM Z CROSS JOIN D
        LEFT JOIN C ON C."OrderType" = Z."OrderType" AND C."OrderEntry" = Z."OrderEntry"
       WHERE LOCATE(D."WwWt", ',' || IFNULL(Z."WorType", '') || ',') > 0 AND Z."Wip" <> 0)
SELECT "OrderType" AS "订单类型", "OrderEntry" AS "订单 Entry", "DocNum" AS "订单号 Num", "ItemCode" AS "产品", "Status" AS "状态",
       "CloseDate" AS "关单日期", "LastFc" AS "在产品最后账期", "Wip" AS "在产品金额"
  FROM W WHERE "IsClosed" = 'Y'
 ORDER BY ABS("Wip") DESC;

-- ③ 按关单月份：正常应集中在 2026-08 以前；2026-08 及以后还有金额的，要单独查为什么没转关单差异
WITH P AS (SELECT '2026-09' AS "Fc" FROM DUMMY),
D AS (SELECT P."Fc", TO_DATE(O."T_RefDate") AS "D1", "MTC_CA_F_ACCT"('WW_MAT', P."Fc") AS "Acct",
             IFNULL("MTC_CA_F_PARAM"('WW_WORTYPES', P."Fc"), ',50,') AS "WwWt"
        FROM P JOIN "OFPR" O ON O."Code" = P."Fc"),
-- 每张订单截至承接账期最后一次出现在旧在产品表的记录
Z AS (SELECT * FROM (
          SELECT IFNULL(T."DocType", '202') AS "OrderType", T."WorEntry" AS "OrderEntry", T."期间" AS "LastFc",
                 MAX(T."WorType") AS "WorType", SUM(IFNULL(T."在产品新", 0)) AS "Wip",
                 ROW_NUMBER() OVER (PARTITION BY IFNULL(T."DocType", '202'), T."WorEntry" ORDER BY T."期间" DESC) AS "Rn"
            FROM "MTC_COST_0322_OWOR_ZCP" T, D
           WHERE T."期间" <= D."Fc"
           GROUP BY IFNULL(T."DocType", '202'), T."WorEntry", T."期间")
       WHERE "Rn" = 1),
-- 截至承接账期期末不算未关闭的订单：和 MTC_CA_P_BOOTSTRAP 的“未关闭”条件互补
C AS (SELECT '202' AS "OrderType", W."DocEntry" AS "OrderEntry", W."DocNum", W."ItemCode", W."Status",
             IFNULL(TO_DATE(W."CloseDate"), D."D1") AS "CloseDate"
        FROM "OWOR" W, D
       WHERE (W."Status" = 'C' AND TO_DATE(W."UpdateDate") <= D."D1") OR (W."Status" = 'L' AND IFNULL(TO_DATE(W."CloseDate"), D."D1") <= D."D1")
      UNION ALL
      SELECT 'MTC_OWOR', W."DocEntry", W."DocNum", W."U_ItemCode", W."U_Status",
             IFNULL(TO_DATE(W."U_CloseDate"), D."D1")
        FROM "@MTC_OWOR" W, D
       WHERE (W."U_Status" = 'C' AND TO_DATE(W."UpdateDate") <= D."D1") OR (W."U_Status" = 'L' AND IFNULL(TO_DATE(W."U_CloseDate"), D."D1") <= D."D1")),
W AS (SELECT Z.*, C."DocNum", C."ItemCode", C."Status", C."CloseDate", CASE WHEN C."OrderEntry" IS NULL THEN 'N' ELSE 'Y' END AS "IsClosed"
        FROM Z CROSS JOIN D
        LEFT JOIN C ON C."OrderType" = Z."OrderType" AND C."OrderEntry" = Z."OrderEntry"
       WHERE LOCATE(D."WwWt", ',' || IFNULL(Z."WorType", '') || ',') > 0 AND Z."Wip" <> 0)
SELECT TO_NVARCHAR("CloseDate", 'YYYY-MM') AS "关单月份", COUNT(*) AS "订单数", SUM("Wip") AS "在产品金额"
  FROM W WHERE "IsClosed" = 'Y'
 GROUP BY TO_NVARCHAR("CloseDate", 'YYYY-MM')
 ORDER BY 1;

-- ④ 140801 总账按凭证代码：只用来查 ① 的“未解释”，旧 WW03 按总账结转 140802 的差额也会落在这里
WITH P AS (SELECT '2026-09' AS "Fc" FROM DUMMY),
D AS (SELECT TO_DATE(O."T_RefDate") AS "D1", "MTC_CA_F_ACCT"('WW_MAT', P."Fc") AS "Acct"
        FROM P JOIN "OFPR" O ON O."Code" = P."Fc")
SELECT IFNULL(H."TransCode", '') AS "凭证代码", COUNT(*) AS "分录行数", SUM(J."Debit") AS "借方", SUM(J."Credit") AS "贷方",
       SUM(J."Debit" - J."Credit") AS "净额"
  FROM "OJDT" H JOIN "JDT1" J ON J."TransId" = H."TransId", D
 WHERE H."RefDate" <= D."D1" AND J."Account" = D."Acct"
 GROUP BY IFNULL(H."TransCode", '')
 ORDER BY ABS(SUM(J."Debit" - J."Credit")) DESC;
