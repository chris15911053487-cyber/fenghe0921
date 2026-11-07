-- =====================================================================
-- 新成本框架 第 5 期：生成 SAP 日记账凭单（用户 2026-10-19，设计稿 8.6；Q36 OBTF、Q41 用操作人自己的 B1 账号、
-- Q42 一种凭证代码一张、Q43 计算后校验不通过不能生成、Q44 本期 B1 已有的凭证代码自动排除）
--   MTC_CA_F_JV_PLAN    生成计划：本期最近一次成功正式运行的凭证底稿（R_JDT）按凭证代码汇总，标出能否生成（只读）
--   MTC_CA_P_JV_BEGIN   生成前检查：账期未锁定、有成功的正式运行、没有正在运行的正式计算、计算后校验全部通过
--   MTC_CA_P_JV_LOG     记一张凭单的生成结果（MTC_CA_JV）
--   MTC_CA_P_JV_FINISH  本次生成结束：有已生成的凭单 → 账期状态 POSTED
--   MTC_CA_P_JV_UNDO    撤销：凭单已在 B1 删除（或已过账的已冲销）后，记为 DELETED，账期状态回到 CALC
-- 凭单本身由执行台服务（tools/console/dev_server.py，服务器模式）经 Service Layer JournalVouchers 建，不用 SQL 写 B1 表；
-- 表头 UDF OJDT.U_MTC_CARunId（OBTF 共用，由用户在 B1 前台手工添加）记运行号，服务端据此找回批号。
-- 替代：旧流程 0801 只生成中间表，过账在库外完成；6101_1 写 UDO @MTC_COST_OJDT。
-- 依赖 01（MTC_CA_JV）、03（P_PERIOD_SET）、06（R_CHECK）、15（R_JDT）。
-- =====================================================================
CREATE OR REPLACE FUNCTION "MTC_CA_F_JV_PLAN" (IN FcCode NVARCHAR(10))
RETURNS TABLE ("RunId" BIGINT, "TransCode" NVARCHAR(10), "TransName" NVARCHAR(100), "RefDate" DATE, "LineCnt" INT,
               "Debit" DECIMAL(19,2), "Credit" DECIMAL(19,2), "BadAcct" INT, "State" NVARCHAR(10), "BatchNum" INT, "StateMsg" NVARCHAR(500))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE rid BIGINT; DECLARE d0 DATE; DECLARE d1 DATE;
    SELECT MAX("RunId") INTO rid FROM "MTC_CA_RUN" WHERE "FcCode" = :FcCode AND "RunType" = 'F' AND "Scenario" = '' AND "Status" = 'OK';
    SELECT MAX(TO_DATE("F_RefDate")), MAX(TO_DATE("T_RefDate")) INTO d0, d1 FROM "OFPR" WHERE "Code" = :FcCode;
    -- 本模块生成过的批号（含已撤销的）：它们以及由它们过账出的 OJDT 不算“B1 里已有”
    mine = SELECT DISTINCT "BatchNum" FROM "MTC_CA_JV" WHERE "BatchNum" IS NOT NULL;
    done = SELECT "TransCode", MAX("BatchNum") AS "BatchNum" FROM "MTC_CA_JV"
            WHERE "FcCode" = :FcCode AND "Status" = 'CREATED' GROUP BY "TransCode";
    -- Q44：本期 B1 里已有同一凭证代码的凭证（已过账、不是冲销）或未清凭单 → 整个代码不生成（如 2026-09 手工过账的 PUR1、MR02）
    b1 = SELECT DISTINCT "TransCode" FROM (
             SELECT H."TransCode" FROM "OJDT" H
              WHERE H."RefDate" BETWEEN :d0 AND :d1 AND H."StornoToTr" IS NULL
                AND NOT EXISTS (SELECT 1 FROM :mine M WHERE M."BatchNum" = H."BatchNum")
             UNION ALL
             SELECT T."TransCode" FROM "OBTF" T
              WHERE T."BtfStatus" = 'O' AND T."RefDate" BETWEEN :d0 AND :d1
                AND NOT EXISTS (SELECT 1 FROM :mine M WHERE M."BatchNum" = T."BatchNum"))
          WHERE IFNULL("TransCode", '') <> '';
    -- 科目：底稿里是内部科目代码；万一是显示代码（FormatCode）也认
    ln = SELECT J."TransCode", J."TransName", J."RefDate", J."Debit", J."Credit",
                CASE WHEN A1."AcctCode" IS NOT NULL THEN A1."Postable" ELSE A2."Postable" END AS "Postable",
                IFNULL(A1."AcctCode", A2."AcctCode") AS "Acct"
           FROM "MTC_CA_R_JDT" J
           LEFT JOIN "OACT" A1 ON A1."AcctCode" = J."AcctCode"
           LEFT JOIN (SELECT "FormatCode", MAX("AcctCode") AS "AcctCode", MAX("Postable") AS "Postable" FROM "OACT"
                       WHERE IFNULL("FormatCode", '') <> '' GROUP BY "FormatCode") A2 ON A2."FormatCode" = J."AcctCode"
          WHERE J."RunId" = :rid AND (J."Debit" <> 0 OR J."Credit" <> 0);
    agg = SELECT L."TransCode", MAX(L."TransName") AS "TransName", MAX(L."RefDate") AS "RefDate", COUNT(*) AS "LineCnt",
                 SUM(L."Debit") AS "Debit", SUM(L."Credit") AS "Credit",
                 SUM(CASE WHEN L."Acct" IS NULL OR IFNULL(L."Postable", 'N') <> 'Y' THEN 1 ELSE 0 END) AS "BadAcct",
                 MAX(D."BatchNum") AS "BatchNum", MAX(B."TransCode") AS "B1Code"
            FROM :ln L
            LEFT JOIN :done D ON D."TransCode" = L."TransCode"
            LEFT JOIN :b1 B ON B."TransCode" = L."TransCode"
           GROUP BY L."TransCode";
    RETURN SELECT :rid AS "RunId", "TransCode", "TransName", "RefDate", "LineCnt", "Debit", "Credit", "BadAcct",
                  CASE WHEN "BatchNum" IS NOT NULL THEN 'CREATED'
                       WHEN "B1Code" IS NOT NULL THEN 'B1'
                       WHEN "Debit" <> "Credit" THEN 'UNBAL'
                       WHEN "BadAcct" > 0 THEN 'BADACCT'
                       ELSE 'READY' END AS "State",
                  "BatchNum",
                  CASE WHEN "BatchNum" IS NOT NULL THEN '已生成，B1 批号 ' || TO_VARCHAR("BatchNum")
                       WHEN "B1Code" IS NOT NULL THEN '本期 B1 已有这个凭证代码的凭证或未清凭单，不生成'
                       WHEN "Debit" <> "Credit" THEN '借贷不平，不能生成'
                       WHEN "BadAcct" > 0 THEN TO_VARCHAR("BadAcct") || ' 行科目不存在或不能记账，不能生成'
                       ELSE '可以生成' END AS "StateMsg"
             FROM :agg ORDER BY "TransCode";
END
@@
-- 生成前检查（Q43）。返回 Code 0 / -1、Msg、RunId（生成所用的运行）
CREATE OR REPLACE PROCEDURE "MTC_CA_P_JV_BEGIN" (IN FcCode NVARCHAR(10), IN UserCode NVARCHAR(50))
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE n INT; DECLARE stat NVARCHAR(1); DECLARE rid BIGINT; DECLARE ids NVARCHAR(1000);
    SELECT COUNT(*), MAX("PeriodStat") INTO n, stat FROM "OFPR" WHERE "Code" = :FcCode;
    IF :n = 0 THEN
        SELECT -1 AS "Code", '账期不存在：' || IFNULL(:FcCode, '') AS "Msg", CAST(NULL AS BIGINT) AS "RunId" FROM DUMMY; RETURN;
    END IF;
    IF :stat = 'Y' THEN
        SELECT -1 AS "Code", '账期 ' || :FcCode || ' 已在 B1 锁定，不能生成凭单' AS "Msg", CAST(NULL AS BIGINT) AS "RunId" FROM DUMMY; RETURN;
    END IF;
    SELECT COUNT(*) INTO n FROM "MTC_CA_RUN" WHERE "FcCode" = :FcCode AND "RunType" = 'F' AND "Scenario" = '' AND "Status" = 'RUNNING';
    IF :n > 0 THEN
        SELECT -1 AS "Code", '账期 ' || :FcCode || ' 有正在运行的正式计算，等它结束再生成' AS "Msg", CAST(NULL AS BIGINT) AS "RunId" FROM DUMMY; RETURN;
    END IF;
    SELECT MAX("RunId") INTO rid FROM "MTC_CA_RUN" WHERE "FcCode" = :FcCode AND "RunType" = 'F' AND "Scenario" = '' AND "Status" = 'OK';
    IF :rid IS NULL THEN
        SELECT -1 AS "Code", '账期 ' || :FcCode || ' 还没有成功的正式计算' AS "Msg", CAST(NULL AS BIGINT) AS "RunId" FROM DUMMY; RETURN;
    END IF;
    -- 已生成过凭单的运行必须就是这次（正常情况下生成后不能再正式计算，这里兜底）
    SELECT COUNT(*) INTO n FROM "MTC_CA_JV" WHERE "FcCode" = :FcCode AND "Status" = 'CREATED' AND "RunId" <> :rid;
    IF :n > 0 THEN
        SELECT -1 AS "Code", '账期 ' || :FcCode || ' 已有其他运行生成的凭单，先撤销' AS "Msg", CAST(NULL AS BIGINT) AS "RunId" FROM DUMMY; RETURN;
    END IF;
    SELECT COUNT(*), LEFT(STRING_AGG("CheckId", '、' ORDER BY "CheckId"), 900) INTO n, ids
      FROM "MTC_CA_R_CHECK" WHERE "RunId" = :rid AND "Stage" = 'POST' AND "Result" = 'FAIL';
    IF :n > 0 THEN
        SELECT -1 AS "Code", '运行 #' || TO_VARCHAR(:rid) || ' 计算后校验 ' || :n || ' 项未通过（' || :ids || '），处理后重新计算再生成凭单' AS "Msg",
               CAST(NULL AS BIGINT) AS "RunId" FROM DUMMY; RETURN;
    END IF;
    SELECT 0 AS "Code", '' AS "Msg", :rid AS "RunId" FROM DUMMY;
END
@@
CREATE OR REPLACE PROCEDURE "MTC_CA_P_JV_LOG" (
    IN FcCode NVARCHAR(10), IN RunId BIGINT, IN TransCode NVARCHAR(10), IN BatchNum NVARCHAR(20), IN Status NVARCHAR(10),
    IN Debit NVARCHAR(30), IN Credit NVARCHAR(30), IN LineCnt NVARCHAR(10), IN UserCode NVARCHAR(50), IN Msg NVARCHAR(2000)
)
LANGUAGE SQLSCRIPT AS
BEGIN
    -- 参数按字符串传（执行台统一按 NVARCHAR 绑定），这里转换
    INSERT INTO "MTC_CA_JV" ("JvId", "FcCode", "RunId", "TransCode", "BatchNum", "Status", "Debit", "Credit", "LineCnt",
                             "CreateUser", "CreateTime", "Msg")
    VALUES ("MTC_CA_SEQ_JV".NEXTVAL, :FcCode, :RunId, :TransCode, TO_INT(NULLIF(:BatchNum, '')), :Status,
            TO_DECIMAL(NULLIF(:Debit, ''), 19, 2), TO_DECIMAL(NULLIF(:Credit, ''), 19, 2), TO_INT(NULLIF(:LineCnt, '')),
            :UserCode, CURRENT_TIMESTAMP, LEFT(:Msg, 2000));
    SELECT 0 AS "Code", '' AS "Msg" FROM DUMMY;
END
@@
CREATE OR REPLACE PROCEDURE "MTC_CA_P_JV_FINISH" (IN FcCode NVARCHAR(10), IN RunId BIGINT, IN UserCode NVARCHAR(50))
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE n INT; DECLARE bat NVARCHAR(1000); DECLARE st NVARCHAR(10);
    SELECT COUNT(*), LEFT(STRING_AGG("TransCode" || ' ' || TO_VARCHAR("BatchNum"), '、' ORDER BY "TransCode"), 900) INTO n, bat
      FROM "MTC_CA_JV" WHERE "FcCode" = :FcCode AND "RunId" = :RunId AND "Status" = 'CREATED';
    IF :n = 0 THEN
        SELECT -1 AS "Code", '没有已生成的凭单' AS "Msg" FROM DUMMY; RETURN;
    END IF;
    SELECT IFNULL(MAX("Status"), 'OPEN') INTO st FROM "MTC_CA_PERIOD" WHERE "FcCode" = :FcCode;
    IF :st = 'POSTED' THEN
        -- 已是 POSTED（之后又补生成了取消勾选的代码）：只记日志
        INSERT INTO "MTC_CA_PERIOD_LOG" ("FcCode", "LogTime", "FromStatus", "ToStatus", "RunId", "UserCode", "Msg")
        VALUES (:FcCode, CURRENT_TIMESTAMP, 'POSTED', 'POSTED', :RunId, :UserCode, '补生成凭单，现有：' || :bat);
    ELSE
        CALL "MTC_CA_P_PERIOD_SET"(:FcCode, 'POSTED', :RunId, :UserCode, '生成凭单：' || :bat);
    END IF;
    COMMIT;
    SELECT 0 AS "Code", '已生成 ' || :n || ' 张凭单：' || :bat AS "Msg" FROM DUMMY;
END
@@
-- 撤销（Q38）：Service Layer 不能删除日记账凭单，先由用户在 B1“日记账凭单”里删除；已过账的要先冲销。
-- 这里核对 B1：本账期已生成的批号都不在未清凭单（OBTF BtfStatus='O'）里，由它们过账出的凭证都已冲销，才记为 DELETED、状态回到 CALC。
CREATE OR REPLACE PROCEDURE "MTC_CA_P_JV_UNDO" (IN FcCode NVARCHAR(10), IN UserCode NVARCHAR(50))
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE n INT; DECLARE calcRun BIGINT; DECLARE lst NVARCHAR(1000);
    SELECT COUNT(*), LEFT(STRING_AGG("TransCode" || ' ' || IFNULL(TO_VARCHAR("BatchNum"), ''), '、' ORDER BY "TransCode"), 900) INTO n, lst
      FROM "MTC_CA_JV" WHERE "FcCode" = :FcCode AND "Status" = 'CREATED';
    IF :n = 0 THEN
        SELECT -1 AS "Code", '账期 ' || :FcCode || ' 没有可撤销的凭单' AS "Msg" FROM DUMMY; RETURN;
    END IF;
    SELECT COUNT(*), LEFT(STRING_AGG(J."TransCode" || ' 批号 ' || TO_VARCHAR(J."BatchNum"), '、' ORDER BY J."TransCode"), 900) INTO n, lst
      FROM "MTC_CA_JV" J
     WHERE J."FcCode" = :FcCode AND J."Status" = 'CREATED'
       AND EXISTS (SELECT 1 FROM "OBTF" T WHERE T."BatchNum" = J."BatchNum" AND T."BtfStatus" = 'O');
    IF :n > 0 THEN
        SELECT -1 AS "Code", '这些凭单还在 B1 未清凭单里，请先在 B1“财务 → 日记账凭单”中删除，再点撤销：' || :lst AS "Msg" FROM DUMMY; RETURN;
    END IF;
    SELECT COUNT(*), LEFT(STRING_AGG(J."TransCode" || ' 凭证 ' || TO_VARCHAR(H."TransId"), '、' ORDER BY J."TransCode"), 900) INTO n, lst
      FROM "MTC_CA_JV" J JOIN "OJDT" H ON H."BatchNum" = J."BatchNum"
     WHERE J."FcCode" = :FcCode AND J."Status" = 'CREATED' AND H."StornoToTr" IS NULL
       AND NOT EXISTS (SELECT 1 FROM "OJDT" R WHERE R."StornoToTr" = H."TransId");
    IF :n > 0 THEN
        SELECT -1 AS "Code", '这些凭单已在 B1 过账、还没冲销，不能撤销；请先在 B1 冲销：' || :lst AS "Msg" FROM DUMMY; RETURN;
    END IF;
    SELECT LEFT(STRING_AGG("TransCode" || ' ' || IFNULL(TO_VARCHAR("BatchNum"), ''), '、' ORDER BY "TransCode"), 900) INTO lst
      FROM "MTC_CA_JV" WHERE "FcCode" = :FcCode AND "Status" = 'CREATED';
    UPDATE "MTC_CA_JV" SET "Status" = 'DELETED', "DelUser" = :UserCode, "DelTime" = CURRENT_TIMESTAMP
     WHERE "FcCode" = :FcCode AND "Status" = 'CREATED';
    SELECT MAX("CalcRunId") INTO calcRun FROM "MTC_CA_PERIOD" WHERE "FcCode" = :FcCode;
    CALL "MTC_CA_P_PERIOD_SET"(:FcCode, 'CALC', :calcRun, :UserCode, '撤销凭单：' || IFNULL(:lst, ''));
    COMMIT;
    SELECT 0 AS "Code", '已撤销，账期回到“已计算”，可以重新计算：' || IFNULL(:lst, '') AS "Msg" FROM DUMMY;
END
