-- 只读：成本结转分录清单（用户 2026-11-05）。三段各自单独执行，执行前改掉每段 P 里的账期。
-- ① 执行台生成的分录，一张一行，带冲销情况（要冲销的就是这个清单）
-- ② 同一批分录的逐行明细
-- ③ 本期其他带成本凭证代码的分录（不是执行台生成的，如手工录入，不用冲销）

-- ① 分录清单
WITH P AS (SELECT '2026-10' AS "FcCode" FROM DUMMY),
     F AS (SELECT O."Code", TO_DATE(O."F_RefDate") AS "D0", TO_DATE(O."T_RefDate") AS "D1"
             FROM "OFPR" O JOIN P ON P."FcCode" = O."Code"),
     S AS (SELECT "TransId", SUM("Debit") AS "Debit", SUM("Credit") AS "Credit", COUNT(*) AS "Lines" FROM "JDT1" GROUP BY "TransId"),
     SV AS (SELECT "BatchNum", "TransId", SUM("Debit") AS "Debit", SUM("Credit") AS "Credit", COUNT(*) AS "Lines" FROM "BTF1" GROUP BY "BatchNum", "TransId")
SELECT J."TransCode" AS "凭证代码", C."TrnsCodDsc" AS "凭证名称", J."BatchNum" AS "批号", J."RunId" AS "运行号",
       H."Number" AS "凭证编号 Number", H."TransId" AS "交易号 TransId", TO_DATE(H."RefDate") AS "过账日期",
       COALESCE(S."Debit", SV."Debit") AS "借方合计", COALESCE(S."Credit", SV."Credit") AS "贷方合计", COALESCE(S."Lines", SV."Lines") AS "行数",
       IFNULL(H."Ref1", T."Ref1") AS "参考1", IFNULL(H."Memo", T."Memo") AS "备注",
       R."Number" AS "冲销凭证编号", R."TransId" AS "冲销交易号", TO_DATE(R."RefDate") AS "冲销日期",
       CASE WHEN T."BatchNum" IS NOT NULL THEN '未过账：在 B1 删除凭单'
            WHEN H."TransId" IS NULL THEN '已在 B1 删除'
            WHEN R."TransId" IS NULL THEN '已过账未冲销：要冲销'
            WHEN TO_DATE(R."RefDate") BETWEEN F."D0" AND F."D1" THEN '本期内已冲销'
            ELSE '冲销日期不在本账期' END AS "状态"
  FROM "MTC_CA_JV" J
  JOIN F ON F."Code" = J."FcCode"
  LEFT JOIN "OTRC" C ON C."TrnsCode" = J."TransCode"
  LEFT JOIN "OBTF" T ON T."BatchNum" = J."BatchNum" AND T."BtfStatus" = 'O'
  LEFT JOIN SV ON SV."BatchNum" = T."BatchNum" AND SV."TransId" = T."TransId"
  LEFT JOIN "OJDT" H ON H."BatchNum" = J."BatchNum" AND H."StornoToTr" IS NULL
  LEFT JOIN S ON S."TransId" = H."TransId"
  LEFT JOIN "OJDT" R ON R."StornoToTr" = H."TransId"
 WHERE J."Status" = 'CREATED'
 ORDER BY J."TransCode", H."TransId";

-- ② 分录明细
WITH P AS (SELECT '2026-10' AS "FcCode" FROM DUMMY)
SELECT J."TransCode" AS "凭证代码", H."Number" AS "凭证编号 Number", H."TransId" AS "交易号 TransId", L."Line_ID" + 1 AS "行号",
       TO_DATE(H."RefDate") AS "过账日期", L."Account" AS "科目", A."AcctName" AS "科目名称", L."Debit" AS "借方", L."Credit" AS "贷方",
       L."ProfitCode" AS "成本中心", L."Project" AS "项目", L."LineMemo" AS "行备注"
  FROM "MTC_CA_JV" J
  JOIN P ON P."FcCode" = J."FcCode"
  JOIN "OJDT" H ON H."BatchNum" = J."BatchNum" AND H."StornoToTr" IS NULL
  JOIN "JDT1" L ON L."TransId" = H."TransId"
  LEFT JOIN "OACT" A ON A."AcctCode" = L."Account"
 WHERE J."Status" = 'CREATED'
 ORDER BY J."TransCode", H."TransId", L."Line_ID";

-- ③ 本期其他成本凭证（不是执行台生成的）
WITH P AS (SELECT '2026-10' AS "FcCode" FROM DUMMY),
     F AS (SELECT O."Code", TO_DATE(O."F_RefDate") AS "D0", TO_DATE(O."T_RefDate") AS "D1"
             FROM "OFPR" O JOIN P ON P."FcCode" = O."Code")
SELECT H."TransCode" AS "凭证代码", C."TrnsCodDsc" AS "凭证名称", H."Number" AS "凭证编号 Number", H."TransId" AS "交易号 TransId",
       TO_DATE(H."RefDate") AS "过账日期", H."Ref1" AS "参考1", H."Memo" AS "备注",
       CASE WHEN H."StornoToTr" IS NOT NULL THEN '这是冲销凭证' END AS "说明"
  FROM "OJDT" H
  JOIN F ON TO_DATE(H."RefDate") BETWEEN F."D0" AND F."D1"
  LEFT JOIN "OTRC" C ON C."TrnsCode" = H."TransCode"
 WHERE LOCATE("MTC_CA_F_PARAM"('COST_TRANSCODES', F."Code"), ',' || H."TransCode" || ',') > 0
   AND NOT EXISTS (SELECT 1 FROM "MTC_CA_JV" J WHERE J."BatchNum" = H."BatchNum")
 ORDER BY H."TransCode", H."TransId";
