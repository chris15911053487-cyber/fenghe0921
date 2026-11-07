-- 只读：已生成凭单的账期里，这批凭单在 B1 的过账和冲销情况（用户 2026-11-05）。不含金额。
-- 改掉 P 里的账期后执行。“判断”不是“本期内已冲销”的，撤销后重新生成会让总账重复，先处理。
WITH P AS (SELECT '2026-10' AS "FcCode" FROM DUMMY),
     F AS (SELECT O."Code", TO_DATE(O."F_RefDate") AS "D0", TO_DATE(O."T_RefDate") AS "D1"
             FROM "OFPR" O JOIN P ON P."FcCode" = O."Code")
SELECT J."TransCode" AS "凭证代码", J."BatchNum" AS "批号", H."TransId" AS "交易号 TransId", TO_DATE(H."RefDate") AS "过账日期",
       R."TransId" AS "冲销交易号", TO_DATE(R."RefDate") AS "冲销日期", H."AutoStorno" AS "自动冲销", TO_DATE(H."StornoDate") AS "计划冲销日期",
       CASE WHEN T."BatchNum" IS NOT NULL THEN '未过账：在 B1 删除'
            WHEN H."TransId" IS NULL THEN '已在 B1 删除'
            WHEN R."TransId" IS NULL THEN '已过账未冲销：冲销，日期选本账期内'
            WHEN TO_DATE(R."RefDate") BETWEEN F."D0" AND F."D1" THEN '本期内已冲销'
            ELSE '冲销日期不在本账期：本期总账还含旧金额' END AS "判断"
  FROM "MTC_CA_JV" J
  JOIN F ON F."Code" = J."FcCode"
  LEFT JOIN "OBTF" T ON T."BatchNum" = J."BatchNum" AND T."BtfStatus" = 'O'
  LEFT JOIN "OJDT" H ON H."BatchNum" = J."BatchNum" AND H."StornoToTr" IS NULL
  LEFT JOIN "OJDT" R ON R."StornoToTr" = H."TransId"
 WHERE J."Status" = 'CREATED'
 ORDER BY J."TransCode", H."TransId"
