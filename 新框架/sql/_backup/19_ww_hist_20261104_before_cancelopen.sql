-- =====================================================================
-- 历史委外差异转出（用户 2026-11-04，设计稿 8.9，清单 S4）
--   旧 CO4001 委外订单关单日期 >= 2026-08 才把在产品转关单差异，更早关闭的留在 140801；期初承接只取未关闭订单，
--   这些订单业务端为 0、总账仍有余额。用户按整张订单选账期转出，P20_EXP 进费用池，P70 生成 JZ05（借 510109 / P016，贷 140801）。
--   MTC_CA_P_WW_HIST_LOAD  从旧在产品表载入待转清单（已计划的行不动）
--   MTC_CA_P_WW_HIST_SET   把一张订单转入某账期 / 取消
--   MTC_CA_P_WW_HIST_MARK  标记已手工做分录转出（Manual = Y）/ 取消：不进计算、不生成 JZ05，只是不能再选
-- 依赖 06（MTC_CA_WW_HIST）、旧表 MTC_COST_0322_OWOR_ZCP。只处理 140801，不含 140802。
-- 只读排查：diag_ww_closed_hist.sql。
-- =====================================================================
CREATE OR REPLACE PROCEDURE "MTC_CA_P_WW_HIST_LOAD" (IN FcCode NVARCHAR(10), IN UserCode NVARCHAR(50))
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE boot NVARCHAR(10); DECLARE wwWt NVARCHAR(200); DECLARE d1 DATE;
    DECLARE n INT; DECLARE amt DECIMAL(19,2);
    boot := "MTC_CA_F_PARAM"('BOOTSTRAP_FC', :FcCode);
    wwWt := IFNULL("MTC_CA_F_PARAM"('WW_WORTYPES', :FcCode), ',50,');
    SELECT MAX(TO_DATE("T_RefDate")) INTO d1 FROM "OFPR" WHERE "Code" = :boot;
    IF :d1 IS NULL THEN
        SELECT -1 AS "Code", '承接账期 ' || IFNULL(:boot, '（空）') || ' 在 OFPR 中不存在' AS "Msg" FROM DUMMY; RETURN;
    END IF;
    -- 每张订单截至承接账期最后一次出现在旧在产品表的记录
    z = SELECT "OrderType", "OrderEntry", "LastFc", "WorType", "Wip" FROM (
            SELECT IFNULL("DocType", '202') AS "OrderType", "WorEntry" AS "OrderEntry", "期间" AS "LastFc",
                   MAX("WorType") AS "WorType", SUM(IFNULL("在产品新", 0)) AS "Wip",
                   ROW_NUMBER() OVER (PARTITION BY IFNULL("DocType", '202'), "WorEntry" ORDER BY "期间" DESC) AS "Rn"
              FROM "MTC_COST_0322_OWOR_ZCP"
             WHERE "期间" <= :boot
             GROUP BY IFNULL("DocType", '202'), "WorEntry", "期间")
         WHERE "Rn" = 1 AND "Wip" <> 0 AND LOCATE(:wwWt, ',' || IFNULL("WorType", '') || ',') > 0;
    -- 截至承接账期期末不算未关闭的订单：和 MTC_CA_P_BOOTSTRAP 的“未关闭”条件互补
    c = SELECT '202' AS "OrderType", "DocEntry" AS "OrderEntry", "DocNum", "ItemCode", "Status",
               IFNULL(TO_DATE("CloseDate"), :d1) AS "CloseDate"
          FROM "OWOR"
         WHERE "Status" = 'C' OR ("Status" = 'L' AND IFNULL(TO_DATE("CloseDate"), :d1) <= :d1)
        UNION ALL
        SELECT 'MTC_OWOR', "DocEntry", "DocNum", "U_ItemCode", "U_Status", IFNULL(TO_DATE("U_CloseDate"), :d1)
          FROM "@MTC_OWOR"
         WHERE "U_Status" = 'C' OR ("U_Status" = 'L' AND IFNULL(TO_DATE("U_CloseDate"), :d1) <= :d1);

    DELETE FROM "MTC_CA_WW_HIST" WHERE "PlanFc" IS NULL;
    INSERT INTO "MTC_CA_WW_HIST" ("OrderType", "OrderEntry", "DocNum", "ItemCode", "B1Status", "CloseDate", "LastFc", "Amount", "LoadFc", "LoadTime")
    SELECT Z."OrderType", Z."OrderEntry", C."DocNum", C."ItemCode", C."Status", C."CloseDate", Z."LastFc", Z."Wip", :boot, CURRENT_TIMESTAMP
      FROM :z Z JOIN :c C ON C."OrderType" = Z."OrderType" AND C."OrderEntry" = Z."OrderEntry"
     WHERE NOT EXISTS (SELECT 1 FROM "MTC_CA_WW_HIST" H WHERE H."OrderType" = Z."OrderType" AND H."OrderEntry" = Z."OrderEntry");
    SELECT COUNT(*), IFNULL(SUM("Amount"), 0) INTO n, amt FROM "MTC_CA_WW_HIST" WHERE "PlanFc" IS NULL;
    SELECT 0 AS "Code", '已载入：待转 ' || :n || ' 张订单，净额 ' || TO_NVARCHAR(:amt) || '（承接账期 ' || :boot || '）' AS "Msg" FROM DUMMY;
END
@@
-- OnOff：Y 转入 FcCode，N 取消。已生成凭单或正在计算的账期不能改；改完要重新计算。
CREATE OR REPLACE PROCEDURE "MTC_CA_P_WW_HIST_SET" (
    IN FcCode NVARCHAR(10), IN OrderType NVARCHAR(20), IN OrderEntry INT, IN OnOff NVARCHAR(1),
    IN Note NVARCHAR(500), IN UserCode NVARCHAR(50))
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE n INT; DECLARE planFc NVARCHAR(10); DECLARE startFc NVARCHAR(10); DECLARE st NVARCHAR(10); DECLARE man NVARCHAR(1);
    SELECT COUNT(*), MAX("PlanFc"), MAX("Manual") INTO n, planFc, man FROM "MTC_CA_WW_HIST"
     WHERE "OrderType" = :OrderType AND "OrderEntry" = :OrderEntry;
    IF :n = 0 THEN
        SELECT -1 AS "Code", '订单 ' || :OrderType || '-' || :OrderEntry || ' 不在待转清单里' AS "Msg" FROM DUMMY; RETURN;
    END IF;
    IF :man = 'Y' THEN
        SELECT -1 AS "Code", '订单 ' || :OrderType || '-' || :OrderEntry || ' 已在 ' || :planFc || ' 手工转出' AS "Msg" FROM DUMMY; RETURN;
    END IF;
    startFc := "MTC_CA_F_PARAM"('START_FC', :FcCode);
    IF :FcCode < :startFc THEN
        SELECT -1 AS "Code", '账期 ' || :FcCode || ' 早于新框架起始账期 ' || :startFc AS "Msg" FROM DUMMY; RETURN;
    END IF;
    IF :OnOff = 'Y' AND :planFc IS NOT NULL AND :planFc <> :FcCode THEN
        SELECT -1 AS "Code", '订单 ' || :OrderType || '-' || :OrderEntry || ' 已计划在 ' || :planFc || ' 转出，不能重复转' AS "Msg" FROM DUMMY; RETURN;
    END IF;
    IF :OnOff = 'N' AND IFNULL(:planFc, '') <> :FcCode THEN
        SELECT -1 AS "Code", '订单 ' || :OrderType || '-' || :OrderEntry || ' 没有计划在 ' || :FcCode || ' 转出' AS "Msg" FROM DUMMY; RETURN;
    END IF;
    IF :OnOff = 'Y' AND LENGTH(TRIM(IFNULL(:Note, ''))) = 0 THEN
        SELECT -1 AS "Code", '请写转出理由' AS "Msg" FROM DUMMY; RETURN;
    END IF;
    SELECT MAX("Status") INTO st FROM "MTC_CA_PERIOD" WHERE "FcCode" = :FcCode;
    SELECT COUNT(*) INTO n FROM "MTC_CA_JV" WHERE "FcCode" = :FcCode AND "Status" = 'CREATED';
    IF IFNULL(:st, '') = 'POSTED' OR :n > 0 THEN
        SELECT -1 AS "Code", '账期 ' || :FcCode || ' 已生成凭单，不能改；需要改时先撤销凭单' AS "Msg" FROM DUMMY; RETURN;
    END IF;
    SELECT COUNT(*) INTO n FROM "MTC_CA_RUN" WHERE "FcCode" = :FcCode AND "Status" = 'RUNNING';
    IF :n > 0 THEN
        SELECT -1 AS "Code", '账期 ' || :FcCode || ' 正在计算，等它结束再改' AS "Msg" FROM DUMMY; RETURN;
    END IF;
    UPDATE "MTC_CA_WW_HIST"
       SET "PlanFc" = CASE WHEN :OnOff = 'Y' THEN :FcCode END,
           "PlanUser" = CASE WHEN :OnOff = 'Y' THEN :UserCode END,
           "PlanTime" = CASE WHEN :OnOff = 'Y' THEN CURRENT_TIMESTAMP END,
           "PlanNote" = CASE WHEN :OnOff = 'Y' THEN :Note END
     WHERE "OrderType" = :OrderType AND "OrderEntry" = :OrderEntry;
    SELECT 0 AS "Code", CASE WHEN :OnOff = 'Y' THEN '已转入 ' || :FcCode ELSE '已取消' END AS "Msg" FROM DUMMY;
END
@@
-- 已手工做分录转出的订单（如 2026-09 的手工凭证）：FcCode = 手工分录的账期，可以早于起始账期。分录已在总账，这里只标记，不影响计算。
CREATE OR REPLACE PROCEDURE "MTC_CA_P_WW_HIST_MARK" (
    IN FcCode NVARCHAR(10), IN OrderType NVARCHAR(20), IN OrderEntry INT, IN OnOff NVARCHAR(1),
    IN Note NVARCHAR(500), IN UserCode NVARCHAR(50))
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE n INT; DECLARE planFc NVARCHAR(10); DECLARE man NVARCHAR(1);
    SELECT COUNT(*), MAX("PlanFc"), MAX("Manual") INTO n, planFc, man FROM "MTC_CA_WW_HIST"
     WHERE "OrderType" = :OrderType AND "OrderEntry" = :OrderEntry;
    IF :n = 0 THEN
        SELECT -1 AS "Code", '订单 ' || :OrderType || '-' || :OrderEntry || ' 不在待转清单里' AS "Msg" FROM DUMMY; RETURN;
    END IF;
    IF :OnOff = 'Y' AND :planFc IS NOT NULL THEN
        SELECT -1 AS "Code", '订单 ' || :OrderType || '-' || :OrderEntry || ' 已计划在 ' || :planFc || ' 转出' AS "Msg" FROM DUMMY; RETURN;
    END IF;
    IF :OnOff = 'N' AND :man <> 'Y' THEN
        SELECT -1 AS "Code", '订单 ' || :OrderType || '-' || :OrderEntry || ' 没有标记手工转出' AS "Msg" FROM DUMMY; RETURN;
    END IF;
    IF :OnOff = 'Y' AND LENGTH(TRIM(IFNULL(:Note, ''))) = 0 THEN
        SELECT -1 AS "Code", '请写说明' AS "Msg" FROM DUMMY; RETURN;
    END IF;
    UPDATE "MTC_CA_WW_HIST"
       SET "Manual" = :OnOff,
           "PlanFc" = CASE WHEN :OnOff = 'Y' THEN :FcCode END,
           "PlanUser" = CASE WHEN :OnOff = 'Y' THEN :UserCode END,
           "PlanTime" = CASE WHEN :OnOff = 'Y' THEN CURRENT_TIMESTAMP END,
           "PlanNote" = CASE WHEN :OnOff = 'Y' THEN :Note END
     WHERE "OrderType" = :OrderType AND "OrderEntry" = :OrderEntry;
    SELECT 0 AS "Code", CASE WHEN :OnOff = 'Y' THEN '已标记 ' || :FcCode || ' 手工转出' ELSE '已取消标记' END AS "Msg" FROM DUMMY;
END
