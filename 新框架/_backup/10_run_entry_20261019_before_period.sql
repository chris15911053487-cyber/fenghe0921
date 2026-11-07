-- =====================================================================
-- 新成本框架：入口过程（设计稿第 4 节）
-- CALL "MTC_CA_P_RUN"('2026-09', 'F', '', 'manager', 'USER');
--   参数：账期 OFPR.Code、F 正式 / S 模拟、模拟场景（正式为空串）、用户、发起方 USER / AI
--   返回：Code 0 成功 / -1 参数或运行错误 / -2 计算前检查阻断 / -3 未收敛；Msg；RunId
-- 步骤：P00 准备 → P20 快照 → P10 计算前检查 → P30 初始化与固定价格 →（模拟）P31 场景假设 → P40 迭代 → P50 定稿
--       → P60 计算后校验与指标快照 → P65 新旧比对 → P71 发出商品 → P73 应付暂估 → P74 应付暂估凭证 → P70 凭证 → P75 凭证校验 → P80 收尾
-- 未收敛：不写结果（删除本次快照和结果，保留上一次成功运行），迭代日志 MTC_CA_RUN_ITER 保留供排查。
-- 依赖 03、07、08、12、13、14、16、17，部署顺序在它们之后。
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
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        DECLARE em NVARCHAR(2000) := 'SQL ' || ::SQL_ERROR_CODE || ': ' || LEFT(::SQL_ERROR_MESSAGE, 1900);
        DECLARE m BIGINT;
        ROLLBACK;
        BEGIN
            -- 清理失败也不能盖掉原始错误
            DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN END;
            CALL "MTC_CA_P_RUN_CLEAN"(:RunId, 'FAIL', m);
            COMMIT;
        END;
        CALL "MTC_CA_P_RUN_END"(:RunId, 'FAIL', :em);
        SELECT -1 AS "Code", :em AS "Msg", :RunId AS "RunId" FROM DUMMY;
    END;

    -- P00 准备
    CALL "MTC_CA_P_RUN_BEGIN"(:FcCode, :RunType, :Scenario, :UserCode, IFNULL(:Initiator, 'USER'), RunId, Code, Msg);
    IF :Code <> 0 THEN
        SELECT :Code AS "Code", :Msg AS "Msg", :RunId AS "RunId" FROM DUMMY;
        RETURN;
    END IF;
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P00', 'OK', NULL, '参数、账期、并发检查通过');

    -- P20 快照（先取快照，P10 在快照上检查）
    CALL "MTC_CA_P20_SNAPSHOT"(:RunId);
    COMMIT;

    -- P10 计算前检查：有阻断项就停止，保留检查结果、删除本次快照
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P10', 'RUNNING', NULL, NULL);
    CALL "MTC_CA_P10_PRECHECK"(:RunId, nBlk);
    CALL "MTC_CA_P10_QCP"(:RunId, n);       -- PRE-23 需要维护期初成本价的物料（警告，不阻断）
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
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P40', 'RUNNING', NULL, NULL);
    CALL "MTC_CA_P40_ITERATE"(:RunId, conv, iters);
    UPDATE "MTC_CA_RUN" SET "IterCount" = :iters, "Converged" = :conv WHERE "RunId" = :RunId;
    COMMIT;
    IF :conv <> 'Y' THEN
        CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P40', 'FAIL', :iters, '达到最大迭代轮数仍未收敛，见 MTC_CA_RUN_ITER');
        CALL "MTC_CA_P_RUN_CLEAN"(:RunId, 'FAIL', n);
        COMMIT;
        CALL "MTC_CA_P_RUN_END"(:RunId, 'NOCONV', '迭代 ' || :iters || ' 轮未收敛，未写结果；上一次成功运行的结果保留');
        SELECT -3 AS "Code", '迭代 ' || :iters || ' 轮未收敛，见 MTC_CA_RUN_ITER' AS "Msg", :RunId AS "RunId" FROM DUMMY;
        RETURN;
    END IF;
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P40', 'OK', :iters, '迭代轮数');

    -- P50 定稿
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P50', 'RUNNING', NULL, NULL);
    CALL "MTC_CA_P50_FINALIZE"(:RunId, :iters);
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
    SELECT COUNT(*), LEFT(STRING_AGG("CheckId", '、' ORDER BY "CheckId"), 900) INTO nFail, postFail
      FROM "MTC_CA_R_CHECK" WHERE "RunId" = :RunId AND "Stage" = 'POST' AND "Result" = 'FAIL';
    Msg := '计算完成，迭代 ' || :iters || ' 轮'
           || CASE WHEN :nFail > 0 THEN '；计算后校验 ' || :nFail || ' 项未通过（阻断）：' || :postFail || '，处理前不能过账' ELSE '' END;
    CALL "MTC_CA_P_RUN_END"(:RunId, 'OK', :Msg);
    SELECT 0 AS "Code", :Msg AS "Msg", :RunId AS "RunId" FROM DUMMY;
END
