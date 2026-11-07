-- =====================================================================
-- 新成本框架 第 4 期：执行台与 AI 工具用到的过程（设计稿第 8 节，清单 R4、R6）
--   MTC_CA_P_PRECHECK       只做计算前检查（cost.precheck）：快照 → P10 → 删快照，保留检查结果
--   MTC_CA_P31_SCENARIO     模拟运行（RunType=S）套用场景假设（MTC_CA_C_SCENARIO_OVR），在 P30 之后、迭代之前
--   MTC_CA_P_SCEN_*         执行台维护模拟场景（只写 MTC_CA_C_SCENARIO / _OVR）
-- 解释、比较、说明书等只读功能是 tools/console/actions.json 中登记的查询，不另建过程。
-- 部署在 10 之前（10 的入口过程调用 P31）。
-- =====================================================================

-- 场景假设类型（Value 为百分比，10 = +10%，-5 = −5%；KeyCode 为空串 = 全部）：
--   ITEM_PRICE_PCT  物料的采购收货、退货、发票差额金额（KeyCode = 物料编码）
--   POOL_PCT        费用池中来自凭证、重估的金额（KeyCode = 费用池编码）；公摊材料、关单差异随计算变化，不调整
--   HOURS_PCT       产品单位工时（KeyCode = 物料编码），影响费用在订单之间的分摊
CREATE OR REPLACE PROCEDURE "MTC_CA_P31_SCENARIO" (IN RunId BIGINT, OUT RowCnt BIGINT, OUT Msg NVARCHAR(1000))
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE fc NVARCHAR(10); DECLARE rt NVARCHAR(1); DECLARE scen NVARCHAR(30); DECLARE d0 DATE; DECLARE d1 DATE;
    DECLARE n BIGINT; DECLARE nOvr INT; DECLARE bad NVARCHAR(500);
    CALL "MTC_CA_P_RUN_CTX"(:RunId, fc, rt, scen, d0, d1);
    RowCnt := 0; Msg := '';
    IF :rt <> 'S' THEN
        Msg := '正式运行，不套用场景'; RETURN;
    END IF;

    ovr = SELECT "LineNo", "OvrType", IFNULL("KeyCode", '') AS "KeyCode", 1 + "Value" / 100 AS "F"
            FROM "MTC_CA_C_SCENARIO_OVR" WHERE "Scenario" = :scen;
    SELECT COUNT(*) INTO nOvr FROM :ovr;
    SELECT STRING_AGG("OvrType", '、') INTO bad FROM :ovr WHERE "OvrType" NOT IN ('ITEM_PRICE_PCT', 'POOL_PCT', 'HOURS_PCT');

    -- 同一对象有多行假设时连乘（物料专项 × 全部）
    itemF = SELECT L."LineId", EXP(SUM(LN(O."F"))) AS "F"
              FROM "MTC_CA_R_LINE" L
              JOIN "MTC_CA_S_LINE" S ON S."RunId" = L."RunId" AND S."LineId" = L."LineId"
              JOIN :ovr O ON O."OvrType" = 'ITEM_PRICE_PCT' AND (O."KeyCode" = '' OR O."KeyCode" = L."ItemCode")
             WHERE L."RunId" = :RunId AND L."Cat" = 'FIX' AND S."ObjType" IN ('18', '19', '20', '21') AND O."F" > 0
             GROUP BY L."LineId";
    UPDATE T0 SET T0."MatAmt" = ROUND(T0."MatAmt" * X."F", 2), T0."SubAmt" = ROUND(T0."SubAmt" * X."F", 2),
                  T0."Amount" = ROUND(T0."MatAmt" * X."F", 2) + ROUND(T0."SubAmt" * X."F", 2),
                  T0."PriceSrc" = IFNULL(T0."PriceSrc", '') || '（模拟：× ' || TO_NVARCHAR(ROUND(X."F", 4)) || '）'
      FROM "MTC_CA_R_LINE" T0 JOIN :itemF X ON X."LineId" = T0."LineId"
     WHERE T0."RunId" = :RunId;
    n := ::ROWCOUNT; RowCnt := :RowCnt + :n;

    poolF = SELECT P."PoolCode", P."Elem", P."Src", EXP(SUM(LN(O."F"))) AS "F"
              FROM "MTC_CA_R_POOL" P
              JOIN :ovr O ON O."OvrType" = 'POOL_PCT' AND (O."KeyCode" = '' OR O."KeyCode" = P."PoolCode")
             WHERE P."RunId" = :RunId AND P."Src" IN ('JDT', 'MRV', 'PROWW') AND O."F" > 0
             GROUP BY P."PoolCode", P."Elem", P."Src";
    UPDATE T0 SET T0."Amount" = ROUND(T0."Amount" * X."F", 2)
      FROM "MTC_CA_R_POOL" T0 JOIN :poolF X ON X."PoolCode" = T0."PoolCode" AND X."Elem" = T0."Elem" AND X."Src" = T0."Src"
     WHERE T0."RunId" = :RunId;
    n := ::ROWCOUNT; RowCnt := :RowCnt + :n;

    hourF = SELECT H."ItemCode", EXP(SUM(LN(O."F"))) AS "F"
              FROM "MTC_CA_S_HOURS" H
              JOIN :ovr O ON O."OvrType" = 'HOURS_PCT' AND (O."KeyCode" = '' OR O."KeyCode" = H."ItemCode")
             WHERE H."RunId" = :RunId AND O."F" > 0
             GROUP BY H."ItemCode";
    UPDATE T0 SET T0."Hours" = T0."Hours" * X."F"
      FROM "MTC_CA_S_HOURS" T0 JOIN :hourF X ON X."ItemCode" = T0."ItemCode"
     WHERE T0."RunId" = :RunId;
    n := ::ROWCOUNT; RowCnt := :RowCnt + :n;

    Msg := '场景 ' || :scen || '：' || :nOvr || ' 项假设，调整 ' || :RowCnt || ' 行'
           || CASE WHEN :bad IS NOT NULL THEN '；不认识的类型（未套用）：' || :bad ELSE '' END;
END
@@
-- 只做计算前检查：建一条运行记录（Status = CHECKED 通过 / BLOCKED 有阻断），取快照、执行 P10，然后删掉快照，
-- 检查结果（R_CHECK / R_CHECK_DTL）保留到同一运行键下一次成功计算为止。不影响已有的计算结果。
-- CALL "MTC_CA_P_PRECHECK"('2026-09', 'F', '', 'manager', 'USER');
CREATE OR REPLACE PROCEDURE "MTC_CA_P_PRECHECK" (
    IN FcCode    NVARCHAR(10),
    IN RunType   NVARCHAR(1),
    IN Scenario  NVARCHAR(30),
    IN UserCode  NVARCHAR(50),
    IN Initiator NVARCHAR(10)
)
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE RunId BIGINT;
    DECLARE Code  INT;
    DECLARE Msg   NVARCHAR(2000);
    DECLARE n     BIGINT;
    DECLARE nBlk  INT;
    DECLARE nWarn INT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        DECLARE em NVARCHAR(2000) := 'SQL ' || ::SQL_ERROR_CODE || ': ' || LEFT(::SQL_ERROR_MESSAGE, 1900);
        DECLARE m BIGINT;
        ROLLBACK;
        BEGIN
            DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN END;
            CALL "MTC_CA_P_RUN_CLEAN"(:RunId, 'FAIL', m);
            COMMIT;
        END;
        CALL "MTC_CA_P_RUN_END"(:RunId, 'FAIL', :em);
        SELECT -1 AS "Code", :em AS "Msg", :RunId AS "RunId" FROM DUMMY;
    END;

    -- 先把 B1 @MTC_CA_PARAM / 费用池抽取到 MTC_CA_C_*，账期检查、运行记录和后面各步都用抽取后的值（用户 2026-10-29：
    -- 每次发起先读 B1 再算；P20 快照里还会再同步一次并记 P05 步骤）
    CALL "MTC_CA_P05_CFG_SYNC"(NULL);
    COMMIT;

    CALL "MTC_CA_P_RUN_BEGIN"(:FcCode, :RunType, :Scenario, :UserCode, IFNULL(:Initiator, 'USER'), RunId, Code, Msg);
    IF :Code <> 0 THEN
        SELECT :Code AS "Code", :Msg AS "Msg", :RunId AS "RunId" FROM DUMMY;
        RETURN;
    END IF;
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P00', 'OK', NULL, '只做计算前检查');

    CALL "MTC_CA_P20_SNAPSHOT"(:RunId);
    COMMIT;

    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P10', 'RUNNING', NULL, NULL);
    CALL "MTC_CA_P10_PRECHECK"(:RunId, nBlk);
    CALL "MTC_CA_P10_QCP"(:RunId, n);       -- PRE-23 需要维护期初成本价的物料（警告，不阻断）
    CALL "MTC_CA_P10_HOURS"(:RunId, n);     -- PRE-14 按物料汇总的需要维护工时的产品（清单，阻断时也保留）
    SELECT COUNT(*) INTO nWarn FROM "MTC_CA_R_CHECK" WHERE "RunId" = :RunId AND "Stage" = 'PRE' AND "Result" = 'WARN';
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P10', CASE WHEN :nBlk > 0 THEN 'FAIL' WHEN :nWarn > 0 THEN 'WARN' ELSE 'OK' END, :nBlk, '阻断项数');
    COMMIT;

    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P80', 'RUNNING', NULL, NULL);
    CALL "MTC_CA_P_RUN_CLEAN"(:RunId, 'BLK', n);
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P80', 'OK', :n, '删除快照行数（检查结果保留）');
    COMMIT;

    IF :nBlk > 0 THEN
        CALL "MTC_CA_P_RUN_END"(:RunId, 'BLOCKED', '只做检查：' || :nBlk || ' 项阻断、' || :nWarn || ' 项警告');
        SELECT -2 AS "Code", '计算前检查：' || :nBlk || ' 项阻断、' || :nWarn || ' 项警告' AS "Msg", :RunId AS "RunId" FROM DUMMY;
    ELSE
        CALL "MTC_CA_P_RUN_END"(:RunId, 'CHECKED', '只做检查：没有阻断项，' || :nWarn || ' 项警告');
        SELECT 0 AS "Code", '计算前检查通过，' || :nWarn || ' 项警告' AS "Msg", :RunId AS "RunId" FROM DUMMY;
    END IF;
END
@@
-- 模拟场景维护（执行台调用；只写 MTC_CA_C_SCENARIO / MTC_CA_C_SCENARIO_OVR）。返回 Code 0 / -1、Msg
CREATE OR REPLACE PROCEDURE "MTC_CA_P_SCEN_SAVE" (
    IN Scenario NVARCHAR(30), IN Title NVARCHAR(100), IN Descr NVARCHAR(1000), IN UserCode NVARCHAR(50)
)
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE cu NVARCHAR(50);
    IF IFNULL(:Scenario, '') = '' OR IFNULL(:Title, '') = '' THEN
        SELECT -1 AS "Code", '场景编码和标题不能为空' AS "Msg" FROM DUMMY; RETURN;
    END IF;
    SELECT IFNULL(MAX("CreateUser"), :UserCode) INTO cu FROM "MTC_CA_C_SCENARIO" WHERE "Scenario" = :Scenario;
    UPSERT "MTC_CA_C_SCENARIO" ("Scenario", "Title", "Descr", "CreateUser") VALUES (:Scenario, :Title, :Descr, :cu) WITH PRIMARY KEY;
    SELECT 0 AS "Code", '已保存场景 ' || :Scenario AS "Msg" FROM DUMMY;
END
@@
CREATE OR REPLACE PROCEDURE "MTC_CA_P_SCEN_DEL" (IN Scenario NVARCHAR(30))
LANGUAGE SQLSCRIPT AS
BEGIN
    DELETE FROM "MTC_CA_C_SCENARIO_OVR" WHERE "Scenario" = :Scenario;
    DELETE FROM "MTC_CA_C_SCENARIO" WHERE "Scenario" = :Scenario;
    SELECT 0 AS "Code", '已删除场景 ' || :Scenario || '（已有的模拟运行记录保留）' AS "Msg" FROM DUMMY;
END
@@
-- LineNo 为 0 时新增一行（取最大行号 + 1）
CREATE OR REPLACE PROCEDURE "MTC_CA_P_SCEN_OVR_SAVE" (
    IN Scenario NVARCHAR(30), IN LineNo INT, IN OvrType NVARCHAR(30), IN KeyCode NVARCHAR(100), IN Val DECIMAL(19,6), IN Descr NVARCHAR(500)
)
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE n INT; DECLARE ln INT := :LineNo;
    SELECT COUNT(*) INTO n FROM "MTC_CA_C_SCENARIO" WHERE "Scenario" = :Scenario;
    IF :n = 0 THEN
        SELECT -1 AS "Code", '场景不存在：' || IFNULL(:Scenario, '') AS "Msg" FROM DUMMY; RETURN;
    END IF;
    IF :OvrType NOT IN ('ITEM_PRICE_PCT', 'POOL_PCT', 'HOURS_PCT') THEN
        SELECT -1 AS "Code", '假设类型只能是 ITEM_PRICE_PCT / POOL_PCT / HOURS_PCT' AS "Msg" FROM DUMMY; RETURN;
    END IF;
    IF :Val <= -100 THEN
        SELECT -1 AS "Code", '百分比必须大于 -100' AS "Msg" FROM DUMMY; RETURN;
    END IF;
    IF IFNULL(:ln, 0) = 0 THEN
        SELECT IFNULL(MAX("LineNo"), 0) + 1 INTO ln FROM "MTC_CA_C_SCENARIO_OVR" WHERE "Scenario" = :Scenario;
    END IF;
    UPSERT "MTC_CA_C_SCENARIO_OVR" ("Scenario", "LineNo", "OvrType", "KeyCode", "Value", "Descr")
    VALUES (:Scenario, :ln, :OvrType, IFNULL(:KeyCode, ''), :Val, :Descr) WITH PRIMARY KEY;
    SELECT 0 AS "Code", '已保存第 ' || :ln || ' 行' AS "Msg" FROM DUMMY;
END
@@
CREATE OR REPLACE PROCEDURE "MTC_CA_P_SCEN_OVR_DEL" (IN Scenario NVARCHAR(30), IN LineNo INT)
LANGUAGE SQLSCRIPT AS
BEGIN
    DELETE FROM "MTC_CA_C_SCENARIO_OVR" WHERE "Scenario" = :Scenario AND "LineNo" = :LineNo;
    SELECT 0 AS "Code", '已删除第 ' || :LineNo || ' 行' AS "Msg" FROM DUMMY;
END
@@
COMMENT ON COLUMN "MTC_CA_RUN"."Status" IS 'RUNNING 运行中 / OK 成功 / FAIL 失败 / BLOCKED 计算前检查阻断 / NOCONV 未收敛 / CHECKED 只做检查且通过'
@@
UPSERT "MTC_CA_C_TOOL" ("ToolName", "Title", "Descr", "ProcName", "IsWrite", "NeedConfirm", "ModelOutput", "Phase") VALUES ('cost.precheck', '计算前检查', '只做计算前检查（快照 + PRE 校验），不计算、不影响已有结果', 'MTC_CA_P_PRECHECK', 'N', 'N', '各检查项是否通过、问题行数', 4) WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_TOOL" ("ToolName", "Title", "Descr", "ProcName", "IsWrite", "NeedConfirm", "ModelOutput", "Phase") VALUES ('jdt.generate', '生成凭证', '凭证在每次计算的 P70 / P74 中生成到 MTC_CA_R_JDT，过账在库外完成', 'MTC_CA_P_RUN', 'Y', 'Y', '是否生成成功、凭证数', 3) WITH PRIMARY KEY
