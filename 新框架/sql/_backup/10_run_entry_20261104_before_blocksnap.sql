-- =====================================================================
-- 新成本框架：入口过程（设计稿第 4 节）
-- CALL "MTC_CA_P_RUN"('2026-09', 'F', '', 'manager', 'USER');
--   参数：账期 OFPR.Code、F 正式 / S 模拟、模拟场景（正式为空串）、用户、发起方 USER / AI
--   返回：Code 0 成功 / -1 参数或运行错误 / -2 计算前检查阻断 / -3 未收敛；Msg；RunId
-- 步骤：P00 准备 → P20 快照 → P10 计算前检查 → P30 初始化与固定价格 →（模拟）P31 场景假设 → P40 迭代 → P50 定稿
--       → P60 计算后校验与指标快照 → P65 新旧比对 → P71 发出商品 → P73 应付暂估 → P74 应付暂估凭证 → P70 凭证 → P75 凭证校验 → P80 收尾
-- 未收敛：不定稿、不出凭证，上一次成功运行的结果保留，迭代日志 MTC_CA_RUN_ITER / MTC_CA_RUN_ITER_ITEM 保留供排查；
--   参数 KEEP_NOCONV = Y（默认，2026-10-29）时本次快照和最后一轮的中间结果也保留（运行状态 NOCONV，下次同类运行成功时删掉），N 时删除。
--   P40 及以后出错（运行状态 FAIL，2026-10-30）同样按 KEEP_NOCONV 保留快照和出错前最后一次提交的中间结果（P40 每轮提交）。
-- 依赖 03、07、08、12、13、14、16、17，部署顺序在它们之后。
-- 账期状态（2026-10-19）：正式计算先过 MTC_CA_P_PERIOD_GUARD（已生成凭单的账期拒绝，上期未生成凭单等只警告，警告写在 P00 步骤），成功后账期状态记为 CALC。
-- =====================================================================
CREATE OR REPLACE PROCEDURE "MTC_CA_P_RUN" (
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
    DECLARE conv  NVARCHAR(1);
    DECLARE iters INT;
    DECLARE nFail INT;
    DECLARE postFail NVARCHAR(1000);
    DECLARE warn  NVARCHAR(2000) := '';
    DECLARE keepNc NVARCHAR(10);
    DECLARE stage NVARCHAR(4) := '';      -- 进入 P40 后为 P40（2026-10-30）
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        DECLARE em NVARCHAR(2000) := 'SQL ' || ::SQL_ERROR_CODE || ': ' || LEFT(::SQL_ERROR_MESSAGE, 1900);
        DECLARE m BIGINT;
        ROLLBACK;
        BEGIN
            -- 清理失败也不能盖掉原始错误
            DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN END;
            -- P40 及以后出错（2026-10-30，#14 迭代发散到第 50 轮溢出）：快照、P30 和已完成的迭代轮次都已提交，
            -- KEEP_NOCONV = Y 时和未收敛一样保留供排查（只回滚了出错那一步），下次同类运行成功时删掉
            IF :stage = 'P40' AND IFNULL("MTC_CA_F_PARAM"('KEEP_NOCONV', :FcCode), 'Y') = 'Y' THEN
                CALL "MTC_CA_P_RUN_CLEAN"(:RunId, 'NCV', m);
                COMMIT;
                em := LEFT(:em, 1950) || '（快照和出错前的中间结果已保留供排查）';
            ELSE
                CALL "MTC_CA_P_RUN_CLEAN"(:RunId, 'FAIL', m);
                COMMIT;
            END IF;
        END;
        CALL "MTC_CA_P_RUN_END"(:RunId, 'FAIL', :em);
        SELECT -1 AS "Code", :em AS "Msg", :RunId AS "RunId" FROM DUMMY;
    END;

    -- 先把 B1 @MTC_CA_PARAM / 费用池抽取到 MTC_CA_C_*，账期检查、运行记录和后面各步都用抽取后的值（用户 2026-10-29：
    -- 每次发起先读 B1 再算；P20 快照里还会再同步一次并记 P05 步骤）
    CALL "MTC_CA_P05_CFG_SYNC"(NULL);
    COMMIT;

    -- P00 准备：正式计算先看账期状态（已生成凭单的账期拒绝，不建运行头；用户 2026-10-19）
    IF IFNULL(:RunType, '') = 'F' THEN
        CALL "MTC_CA_P_PERIOD_GUARD"(:FcCode, 'CALC', Code, warn);
        IF :Code <> 0 THEN
            SELECT :Code AS "Code", :warn AS "Msg", CAST(NULL AS BIGINT) AS "RunId" FROM DUMMY;
            RETURN;
        END IF;
    END IF;
    CALL "MTC_CA_P_RUN_BEGIN"(:FcCode, :RunType, :Scenario, :UserCode, IFNULL(:Initiator, 'USER'), RunId, Code, Msg);
    IF :Code <> 0 THEN
        SELECT :Code AS "Code", :Msg AS "Msg", :RunId AS "RunId" FROM DUMMY;
        RETURN;
    END IF;
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P00', CASE WHEN :warn <> '' THEN 'WARN' ELSE 'OK' END, NULL,
                             '参数、账期、并发检查通过' || CASE WHEN :warn <> '' THEN '；' || :warn ELSE '' END);

    -- P20 快照（先取快照，P10 在快照上检查）
    CALL "MTC_CA_P20_SNAPSHOT"(:RunId);
    COMMIT;

    -- P10 计算前检查：有阻断项就停止，保留检查结果、删除本次快照
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P10', 'RUNNING', NULL, NULL);
    CALL "MTC_CA_P10_PRECHECK"(:RunId, nBlk);
    CALL "MTC_CA_P10_QCP"(:RunId, n);       -- PRE-23 需要维护期初成本价的物料（警告，不阻断）
    CALL "MTC_CA_P10_HOURS"(:RunId, n);     -- PRE-14 按物料汇总的需要维护工时的产品（清单，阻断时也保留）
    COMMIT;
    IF :nBlk > 0 THEN
        CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P10', 'FAIL', :nBlk, '阻断项数');
        CALL "MTC_CA_P_RUN_CLEAN"(:RunId, 'BLK', n);
        COMMIT;
        CALL "MTC_CA_P_RUN_END"(:RunId, 'BLOCKED', :nBlk || ' 项计算前检查未通过，见 MTC_CA_R_CHECK / MTC_CA_R_CHECK_DTL');
        SELECT -2 AS "Code", :nBlk || ' 项计算前检查未通过，见 MTC_CA_R_CHECK' AS "Msg", :RunId AS "RunId" FROM DUMMY;
        RETURN;
    END IF;
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P10', 'OK', 0, '阻断项数');

    -- P30 初始化与固定价格
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P30', 'RUNNING', NULL, NULL);
    CALL "MTC_CA_P30_INIT"(:RunId, n);
    COMMIT;
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P30', 'OK', :n, '单据行数');

    -- P31 模拟场景假设（只在 RunType = S 时调整，设计稿第 8 节）
    IF :RunType = 'S' THEN
        CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P31', 'RUNNING', NULL, NULL);
        CALL "MTC_CA_P31_SCENARIO"(:RunId, n, Msg);
        COMMIT;
        CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P31', 'OK', :n, :Msg);
    END IF;

    -- P40 迭代
    stage := 'P40';
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P40', 'RUNNING', NULL, NULL);
    CALL "MTC_CA_P40_ITERATE"(:RunId, conv, iters);
    UPDATE "MTC_CA_RUN" SET "IterCount" = :iters, "Converged" = :conv WHERE "RunId" = :RunId;
    COMMIT;
    IF :conv <> 'Y' THEN
        CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P40', 'FAIL', :iters, '达到最大迭代轮数仍未收敛，见 MTC_CA_RUN_ITER / MTC_CA_RUN_ITER_ITEM');
        keepNc := IFNULL("MTC_CA_F_PARAM"('KEEP_NOCONV', :FcCode), 'Y');
        IF :keepNc = 'Y' THEN
            CALL "MTC_CA_P_RUN_CLEAN"(:RunId, 'NCV', n);
            Msg := '未定稿，最后一轮的中间结果保留供排查；';
        ELSE
            CALL "MTC_CA_P_RUN_CLEAN"(:RunId, 'FAIL', n);
            Msg := '未写结果；';
        END IF;
        COMMIT;
        CALL "MTC_CA_P_RUN_END"(:RunId, 'NOCONV', '迭代 ' || :iters || ' 轮未收敛，' || :Msg || '上一次成功运行的结果保留');
        SELECT -3 AS "Code", '迭代 ' || :iters || ' 轮未收敛，见 MTC_CA_RUN_ITER' AS "Msg", :RunId AS "RunId" FROM DUMMY;
        RETURN;
    END IF;
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P40', 'OK', :iters, '迭代轮数');

    -- P50 定稿
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P50', 'RUNNING', NULL, NULL);
    CALL "MTC_CA_P50_FINALIZE"(:RunId, :iters);
    CALL "MTC_CA_P55_REVAL"(:RunId, n);     -- 库存重估清单（用户 2026-11-04），只写清单，不写 B1
    COMMIT;
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P50', 'OK', NULL, NULL);

    -- P60 计算后校验、指标快照
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P60', 'RUNNING', NULL, NULL);
    CALL "MTC_CA_P60_POSTCHECK"(:RunId, nFail);
    COMMIT;
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P60', CASE WHEN :nFail > 0 THEN 'BLOCKED' ELSE 'OK' END, :nFail, '未通过的校验数（计算后校验不通过即阻断）');

    -- P65 新旧比对
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P65', 'RUNNING', NULL, NULL);
    CALL "MTC_CA_P65_COMPARE"(:RunId, n);
    COMMIT;
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P65', 'OK', :n, '有差异的物料 / 订单数');

    -- P71 发出商品与交货成本、P73 应付暂估、P74 应付暂估凭证、P70 凭证、P75 凭证与暂估校验
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P71', 'RUNNING', NULL, NULL);
    CALL "MTC_CA_P71_SALES"(:RunId, n);
    COMMIT;
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P71', 'OK', :n, '未清交货 / 退货行数');
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P73', 'RUNNING', NULL, NULL);
    CALL "MTC_CA_P73_AP_ACCR"(:RunId, n);
    COMMIT;
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P73', 'OK', :n, '未清收货 / 退货行数');
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P74', 'RUNNING', NULL, NULL);
    CALL "MTC_CA_P74_AP_JDT"(:RunId, n);
    COMMIT;
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P74', 'OK', :n, '应付暂估凭证来源行数');
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P70', 'RUNNING', NULL, NULL);
    CALL "MTC_CA_P70_JDT"(:RunId, n);
    COMMIT;
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P70', 'OK', :n, '凭证行数');
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P75', 'RUNNING', NULL, NULL);
    CALL "MTC_CA_P75_POSTCHECK"(:RunId, nFail);
    COMMIT;
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P75', CASE WHEN :nFail > 0 THEN 'BLOCKED' ELSE 'OK' END, :nFail, '未通过的校验数（计算后校验不通过即阻断）');

    -- P80 收尾：删除同运行键下旧明细
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P80', 'RUNNING', NULL, NULL);
    CALL "MTC_CA_P_RUN_CLEAN"(:RunId, 'OK', n);
    COMMIT;
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P80', 'OK', :n, '删除旧明细行数');
    -- 计算后校验不通过一律阻断（用户 2026-10-14）：结果保留供排查，运行说明里写明哪几项阻断、处理前不能过账
    SELECT COUNT(*) INTO nFail
      FROM "MTC_CA_R_CHECK" WHERE "RunId" = :RunId AND "Stage" = 'POST' AND "Result" = 'FAIL';
    postFail := '';
    IF :nFail > 0 THEN
        SELECT LEFT(STRING_AGG("CheckId", '、' ORDER BY "CheckId"), 900) INTO postFail
          FROM "MTC_CA_R_CHECK" WHERE "RunId" = :RunId AND "Stage" = 'POST' AND "Result" = 'FAIL';
    END IF;
    Msg := '计算完成，迭代 ' || :iters || ' 轮'
           || CASE WHEN :nFail > 0 THEN '；计算后校验 ' || :nFail || ' 项未通过（阻断）：' || :postFail || '，处理前不能过账' ELSE '' END;
    -- 账期状态：正式计算成功 → CALC，记下这次运行（计算后校验不通过也记，生成凭单时再拦）
    IF :RunType = 'F' THEN
        CALL "MTC_CA_P_PERIOD_SET"(:FcCode, 'CALC', :RunId, :UserCode, :Msg);
        COMMIT;
    END IF;
    CALL "MTC_CA_P_RUN_END"(:RunId, 'OK', :Msg);
    SELECT 0 AS "Code", :Msg AS "Msg", :RunId AS "RunId" FROM DUMMY;
END
