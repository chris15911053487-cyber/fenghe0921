-- =====================================================================
-- 新成本框架 第 1 期：期初承接（设计稿第 7 节，一次性）
-- CALL "MTC_CA_P_BOOTSTRAP"('2026-08');   -- 承接账期 = MTC_CA_C_PARAM.BOOTSTRAP_FC
-- 从旧框架该期结果取物料期末和订单在产品，写 MTC_CA_BOOT_*；之后起始账期（2026-09）的 P20_OPEN 读这些表。
-- 前提：旧框架该期已按月结顺序跑完（含 CO4001 IsInsert='Y'、两次 CO4011 写 ZCP1）。可重复执行。
-- 旧表符号【读代码】：0321_OWOR1 的领料数量、金额为负（出库为负），这里取反为正。
-- 0321_OWOR1 早期行可能没有 DocType，按 202 处理。
-- 物料期末和订单领料的料工费拆分（用户 2026-10-18）：旧框架期末不分料工费，按旧框架截至承接账期最近一个有完工的账期算比例，
-- 写 MTC_CA_BOOT_RATIO；物料期末在这里拆，订单 × 材料在 P20_OPEN 复制到快照时按领用材料的比例拆。
-- =====================================================================
-- BOOT-01（设计稿 Q8）：ZCP1 合计 ≠ ZCP 订单在产品；另列出在产品大于累计领料（累计结转为负）的材料
CREATE OR REPLACE VIEW "MTC_CA_V_BOOT_CHECK" AS
SELECT "FcCode", 'ZCP1≠ZCP' AS "Issue", "OrderType", "OrderEntry", NULL AS "ItemCode",
       IFNULL("Zcp1Wip", 0) AS "Value1", IFNULL("ZcpWip", 0) AS "Value2"
  FROM "MTC_CA_BOOT_ORDER"
 WHERE ABS(IFNULL("Zcp1Wip", 0) - IFNULL("ZcpWip", 0)) > 0.01
UNION ALL
SELECT "FcCode", '在产品>累计领料', "OrderType", "OrderEntry", "ItemCode", "WipAmt", "CumIssueAmt"
  FROM "MTC_CA_BOOT_ORDER_MAT"
 WHERE "CumCarriedAmt" < -0.01
@@
CREATE OR REPLACE PROCEDURE "MTC_CA_P_BOOTSTRAP" (IN FcCode NVARCHAR(10))
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE d1 DATE;
    DECLARE nItem BIGINT; DECLARE nOrd BIGINT; DECLARE nMat BIGINT; DECLARE nDiff BIGINT;
    DECLARE nRatio BIGINT; DECLARE nSplit BIGINT; DECLARE i INT;
    DECLARE gc INT; DECLARE gm NVARCHAR(2000);
    DECLARE rwWt NVARCHAR(200);
    DECLARE bootFc NVARCHAR(10);
    SELECT MAX(TO_DATE("T_RefDate")) INTO d1 FROM "OFPR" WHERE "Code" = :FcCode;
    IF :d1 IS NULL THEN
        SELECT -1 AS "Code", '账期不存在：' || IFNULL(:FcCode, '') AS "Msg" FROM DUMMY;
        RETURN;
    END IF;
    -- 先把 B1 @MTC_CA_PARAM 抽取到 MTC_CA_C_PARAM（用户 2026-10-29），承接账期以抽取后的 BOOTSTRAP_FC 为准：
    -- 执行台按页面上显示的账期发起，页面是上次抽取的值，B1 改过时这里拦住；任务结束后执行台自动刷新承接账期，再点一次即可
    CALL "MTC_CA_P05_CFG_SYNC"(NULL);
    COMMIT;
    bootFc := "MTC_CA_F_PARAM"('BOOTSTRAP_FC', :FcCode);
    IF IFNULL(:bootFc, '') <> :FcCode THEN
        SELECT -1 AS "Code", '承接账期参数 BOOTSTRAP_FC（已从 B1 @MTC_CA_PARAM 读取）是 ' || IFNULL(:bootFc, '（空）') || '，不是 ' || :FcCode
                             || '；执行台已按新值刷新，确认承接账期后再点一次期初承接' AS "Msg" FROM DUMMY;
        RETURN;
    END IF;
    -- 起始账期已生成凭单时不能重做承接（会改掉已出凭单那期的期初；用户 2026-10-19）
    CALL "MTC_CA_P_PERIOD_GUARD"(:FcCode, 'BOOT', gc, gm);
    IF :gc <> 0 THEN
        SELECT -1 AS "Code", :gm AS "Msg" FROM DUMMY;
        RETURN;
    END IF;

    rwWt := IFNULL("MTC_CA_F_PARAM"('REWORK_WORTYPES', :FcCode), ',30,');   -- 返工单的订单类型（参数，2026-10-27）
    DELETE FROM "MTC_CA_BOOT_ITEM" WHERE "FcCode" = :FcCode;
    DELETE FROM "MTC_CA_BOOT_ORDER" WHERE "FcCode" = :FcCode;
    DELETE FROM "MTC_CA_BOOT_ORDER_MAT" WHERE "FcCode" = :FcCode;
    DELETE FROM "MTC_CA_BOOT_RATIO" WHERE "FcCode" = :FcCode;

    -- 物料期末：先全部记材料，下面有料工费比例的再拆分
    -- 0301 每个物料按 MTC_COST_0101_COSTTYPE 每个成本类型一行，0302 回写期末数量时不分成本类型，各行数量相同；
    -- 旧代码只用 CostCode='20' 这一行（金额也只写在这一行），所以只取这一行，不能各行相加（2026-10-13）
    INSERT INTO "MTC_CA_BOOT_ITEM" ("FcCode", "ItemCode", "Qty", "MatAmt", "Amount", "Src", "LoadTime")
    SELECT :FcCode, "ItemCode", SUM(IFNULL("QM_Qty", 0)), SUM(IFNULL("QM_Amount", 0)), SUM(IFNULL("QM_Amount", 0)),
           '旧 0301 期末；没有完工记录，全部记材料', CURRENT_TIMESTAMP
      FROM "MTC_COST_0301_INVNT"
     WHERE "FcCode" = :FcCode AND "CostCode" = '20'
     GROUP BY "ItemCode"
    HAVING SUM(IFNULL("QM_Qty", 0)) <> 0 OR SUM(IFNULL("QM_Amount", 0)) <> 0;
    nItem := ::ROWCOUNT;

    -- 料工费比例（用户 2026-10-18）：每个产品取旧 0321_OWOR_SUM 截至承接账期、最近一个有完工（IgnQty > 0）的账期，
    -- 本期完工成本 1Material / 2ManExp（制造）/ 3LabAmount（人工）/ 4WWExp（委外）。不用返工单（REWORK_WORTYPES，默认 30，领料和产出是同一物料）；
    -- 四项有负数或合计 ≤ 0 的账期跳过，往前找。
    -- 旧框架把领用的半成品成本整个记在 1Material，新框架四项随物料逐级传递，所以 1Material 再按订单累计领料的金额构成
    -- 拆到各领用材料，按材料自己的比例（下层先算）展开；采购件、没有完工记录或还没算出比例的材料按 100% 材料。
    cand = SELECT "ItemCode", "FcCode" AS "RatioFc", MAX("iLevel") AS "Lv",
                  SUM(IFNULL("1Material", 0)) AS "M", SUM(IFNULL("2ManExp", 0)) AS "F",
                  SUM(IFNULL("3LabAmount", 0)) AS "L", SUM(IFNULL("4WWExp", 0)) AS "S"
             FROM "MTC_COST_0321_OWOR_SUM"
            WHERE "FcCode" <= :FcCode AND LOCATE(:rwWt, ',' || IFNULL("WorType", '') || ',') = 0 AND IFNULL("IgnQty", 0) > 0 AND "ItemCode" IS NOT NULL
            GROUP BY "ItemCode", "FcCode"
           HAVING SUM(IFNULL("1Material", 0)) >= 0 AND SUM(IFNULL("2ManExp", 0)) >= 0
              AND SUM(IFNULL("3LabAmount", 0)) >= 0 AND SUM(IFNULL("4WWExp", 0)) >= 0
              AND SUM(IFNULL("1Material", 0) + IFNULL("2ManExp", 0) + IFNULL("3LabAmount", 0) + IFNULL("4WWExp", 0)) > 0;
    pick = SELECT "ItemCode", "RatioFc", "M", "F", "L", "S", "M" + "F" + "L" + "S" AS "T",
                  CASE WHEN IFNULL("Lv", -1) < 0 THEN 20 ELSE LEAST("Lv", 19) END AS "LvKey"
             FROM (SELECT C.*, ROW_NUMBER() OVER (PARTITION BY C."ItemCode" ORDER BY C."RatioFc" DESC) AS "Rn" FROM :cand C) X
            WHERE X."Rn" = 1;
    ordc = SELECT IFNULL(S."DocType", '202') AS "OrderType", S."WorEntry", S."ItemCode", S."FcCode", IFNULL(S."1Material", 0) AS "M"
             FROM "MTC_COST_0321_OWOR_SUM" S
             JOIN :pick P ON P."ItemCode" = S."ItemCode" AND P."RatioFc" = S."FcCode"
            WHERE LOCATE(:rwWt, ',' || IFNULL(S."WorType", '') || ',') = 0 AND IFNULL(S."IgnQty", 0) > 0;
    -- 订单截至该账期的累计领料（净额为正的材料），0321_OWOR1 金额出库为负
    oiss = SELECT O."OrderType", O."WorEntry", O."FcCode", W."ItemCode" AS "Mat", -SUM(IFNULL(W."Amount", 0)) AS "Amt"
             FROM (SELECT DISTINCT "OrderType", "WorEntry", "FcCode" FROM :ordc) O
             JOIN "MTC_COST_0321_OWOR1" W ON IFNULL(W."DocType", '202') = O."OrderType" AND W."WorEntry" = O."WorEntry" AND W."FcCode" <= O."FcCode"
            GROUP BY O."OrderType", O."WorEntry", O."FcCode", W."ItemCode"
           HAVING -SUM(IFNULL(W."Amount", 0)) > 0;
    otot = SELECT "OrderType", "WorEntry", "FcCode", SUM("Amt") AS "Tot" FROM :oiss GROUP BY "OrderType", "WorEntry", "FcCode";
    -- 产品 × 领用材料的完工材料金额；订单没有领料记录的，完工材料记为直接材料（Mat 为空）
    mix = SELECT O."ItemCode" AS "Prod", I."Mat", SUM(O."M" * I."Amt" / T."Tot") AS "W"
            FROM :ordc O
            JOIN :otot T ON T."OrderType" = O."OrderType" AND T."WorEntry" = O."WorEntry" AND T."FcCode" = O."FcCode"
            JOIN :oiss I ON I."OrderType" = O."OrderType" AND I."WorEntry" = O."WorEntry" AND I."FcCode" = O."FcCode"
           GROUP BY O."ItemCode", I."Mat"
          UNION ALL
          SELECT O."ItemCode", CAST(NULL AS NVARCHAR(50)), SUM(O."M")
            FROM :ordc O
           WHERE NOT EXISTS (SELECT 1 FROM :otot T WHERE T."OrderType" = O."OrderType" AND T."WorEntry" = O."WorEntry" AND T."FcCode" = O."FcCode")
           GROUP BY O."ItemCode";
    i := 0;
    WHILE :i <= 20 DO   -- 按层级从下往上（20 = 层级未知）；沿用 P40 写法用 WHILE
        INSERT INTO "MTC_CA_BOOT_RATIO" ("FcCode", "ItemCode", "RatioFc", "RMat", "RMfg", "RLab", "RSub", "Basis", "LoadTime")
        SELECT :FcCode, P."ItemCode", P."RatioFc",
               IFNULL(X."EMat", P."M") / P."T", (P."F" + IFNULL(X."EMfg", 0)) / P."T",
               (P."L" + IFNULL(X."ELab", 0)) / P."T", (P."S" + IFNULL(X."ESub", 0)) / P."T",
               '旧 0321_OWOR_SUM ' || P."RatioFc" || ' 完工成本，材料按领料逐级展开', CURRENT_TIMESTAMP
          FROM :pick P
          LEFT JOIN (SELECT A."Prod",
                            SUM(A."W" * IFNULL(R."RMat", 1)) AS "EMat", SUM(A."W" * IFNULL(R."RMfg", 0)) AS "EMfg",
                            SUM(A."W" * IFNULL(R."RLab", 0)) AS "ELab", SUM(A."W" * IFNULL(R."RSub", 0)) AS "ESub"
                       FROM :mix A
                       LEFT JOIN "MTC_CA_BOOT_RATIO" R ON R."FcCode" = :FcCode AND R."ItemCode" = A."Mat"
                      GROUP BY A."Prod") X ON X."Prod" = P."ItemCode"
         WHERE P."LvKey" = :i;
        i := :i + 1;
    END WHILE;
    SELECT COUNT(*) INTO nRatio FROM "MTC_CA_BOOT_RATIO" WHERE "FcCode" = :FcCode;

    -- 物料期末按比例拆分：制造、人工、委外四舍五入到分，材料 = 金额 − 其余三项（合计不变）
    UPDATE T0 SET T0."MfgAmt" = ROUND(T0."Amount" * R."RMfg", 2), T0."LabAmt" = ROUND(T0."Amount" * R."RLab", 2),
                  T0."SubAmt" = ROUND(T0."Amount" * R."RSub", 2),
                  T0."MatAmt" = T0."Amount" - ROUND(T0."Amount" * R."RMfg", 2) - ROUND(T0."Amount" * R."RLab", 2) - ROUND(T0."Amount" * R."RSub", 2),
                  T0."Src" = '旧 0301 期末；料工费按旧框架 ' || R."RatioFc" || ' 完工比例拆分（MTC_CA_BOOT_RATIO）'
      FROM "MTC_CA_BOOT_ITEM" T0
      JOIN "MTC_CA_BOOT_RATIO" R ON R."FcCode" = T0."FcCode" AND R."ItemCode" = T0."ItemCode"
     WHERE T0."FcCode" = :FcCode;
    nSplit := ::ROWCOUNT;

    -- 截至承接账期期末仍未关闭的订单
    ord = SELECT '202' AS "OrderType", "DocEntry" AS "OrderEntry"
            FROM "OWOR"
           WHERE "Status" <> 'C' AND IFNULL(TO_DATE("PostDate"), :d1) <= :d1
             AND NOT ("Status" = 'L' AND IFNULL(TO_DATE("CloseDate"), :d1) <= :d1)
          UNION ALL
          SELECT 'MTC_OWOR', "DocEntry"
            FROM "@MTC_OWOR"
           WHERE "U_Status" <> 'C' AND IFNULL(TO_DATE("U_PostDate"), :d1) <= :d1
             AND NOT ("U_Status" = 'L' AND IFNULL(TO_DATE("U_CloseDate"), :d1) <= :d1);

    issue = SELECT IFNULL("DocType", '202') AS "OrderType", TO_INTEGER("WorEntry") AS "OrderEntry", "ItemCode",
                   -SUM(IFNULL("IgeQty", 0)) AS "Qty", -SUM(IFNULL("Amount", 0)) AS "Amt"
              FROM "MTC_COST_0321_OWOR1"
             WHERE "FcCode" <= :FcCode AND "WorEntry" LIKE_REGEXPR '^[0-9]+$'
             GROUP BY IFNULL("DocType", '202'), TO_INTEGER("WorEntry"), "ItemCode";
    wip = SELECT "DocType" AS "OrderType", "WorEntry" AS "OrderEntry", "ItemCode",
                 SUM(IFNULL("Quantity", 0)) AS "Qty", SUM(IFNULL("Amount", 0)) AS "Amt"
            FROM "MTC_COST_0322_OWOR_ZCP1"
           WHERE "FcCode" = :FcCode
           GROUP BY "DocType", "WorEntry", "ItemCode";

    INSERT INTO "MTC_CA_BOOT_ORDER_MAT" ("FcCode", "OrderType", "OrderEntry", "ItemCode", "CumIssueQty", "CumIssueAmt",
                                         "WipQty", "WipAmt", "CumCarriedAmt", "LoadTime")
    SELECT :FcCode, K."OrderType", K."OrderEntry", K."ItemCode",
           IFNULL(I."Qty", 0), IFNULL(I."Amt", 0), IFNULL(W."Qty", 0), IFNULL(W."Amt", 0),
           IFNULL(I."Amt", 0) - IFNULL(W."Amt", 0), CURRENT_TIMESTAMP
      FROM (SELECT "OrderType", "OrderEntry", "ItemCode" FROM :issue
            UNION
            SELECT "OrderType", "OrderEntry", "ItemCode" FROM :wip) K
      JOIN :ord O ON O."OrderType" = K."OrderType" AND O."OrderEntry" = K."OrderEntry"
      LEFT JOIN :issue I ON I."OrderType" = K."OrderType" AND I."OrderEntry" = K."OrderEntry" AND I."ItemCode" = K."ItemCode"
      LEFT JOIN :wip W ON W."OrderType" = K."OrderType" AND W."OrderEntry" = K."OrderEntry" AND W."ItemCode" = K."ItemCode";
    nMat := ::ROWCOUNT;

    INSERT INTO "MTC_CA_BOOT_ORDER" ("FcCode", "OrderType", "OrderEntry", "CumRecvQty", "ZcpWip", "Zcp1Wip", "LoadTime")
    SELECT :FcCode, O."OrderType", O."OrderEntry", IFNULL(R."Qty", 0), Z."Wip",
           (SELECT SUM(W."Amt") FROM :wip W WHERE W."OrderType" = O."OrderType" AND W."OrderEntry" = O."OrderEntry"),
           CURRENT_TIMESTAMP
      FROM :ord O
      LEFT JOIN (SELECT IFNULL("DocType", '202') AS "OrderType", TO_INTEGER("WorEntry") AS "OrderEntry", SUM(IFNULL("IgnQty", 0)) AS "Qty"
                   FROM "MTC_COST_0321_OWOR"
                  WHERE "FcCode" <= :FcCode AND TO_NVARCHAR("WorEntry") LIKE_REGEXPR '^[0-9]+$'
                  GROUP BY IFNULL("DocType", '202'), TO_INTEGER("WorEntry")) R
        ON R."OrderType" = O."OrderType" AND R."OrderEntry" = O."OrderEntry"
      LEFT JOIN (SELECT "DocType", "WorEntry", SUM(IFNULL("在产品新", 0)) AS "Wip"
                   FROM "MTC_COST_0322_OWOR_ZCP"
                  WHERE "期间" = :FcCode
                  GROUP BY "DocType", "WorEntry") Z
        ON Z."DocType" = O."OrderType" AND Z."WorEntry" = O."OrderEntry"
     WHERE R."OrderEntry" IS NOT NULL OR Z."WorEntry" IS NOT NULL
        OR EXISTS (SELECT 1 FROM "MTC_CA_BOOT_ORDER_MAT" M
                    WHERE M."FcCode" = :FcCode AND M."OrderType" = O."OrderType" AND M."OrderEntry" = O."OrderEntry");
    nOrd := ::ROWCOUNT;

    SELECT COUNT(*) INTO nDiff FROM "MTC_CA_V_BOOT_CHECK" WHERE "FcCode" = :FcCode;

    SELECT 0 AS "Code",
           '期初承接完成：物料 ' || :nItem || ' 个（其中 ' || :nSplit || ' 个按旧框架完工比例拆分料工费，其余全部记材料；比例见 MTC_CA_BOOT_RATIO，共 '
           || :nRatio || ' 个物料），订单 ' || :nOrd || ' 张，订单 × 材料 ' || :nMat || ' 行；'
           || CASE WHEN :nDiff = 0 THEN '各项核对一致' ELSE :nDiff || ' 项需要核对，见 MTC_CA_V_BOOT_CHECK' END AS "Msg"
      FROM DUMMY;
END
