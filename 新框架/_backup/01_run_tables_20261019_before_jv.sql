-- =====================================================================
-- 新成本框架 第 1 期：运行日志层（设计稿 2.2、3.1；清单 R1）
-- 每次运行都保留；明细结果表只留最后一次成功运行（见 MTC_CA_P_RUN_END）。
-- 语句之间用单独一行 @@ 分隔（部署脚本按它切分）。
-- =====================================================================
CREATE SEQUENCE "MTC_CA_SEQ_RUN" START WITH 1 INCREMENT BY 1 NO CYCLE
@@
CREATE COLUMN TABLE "MTC_CA_RUN" (
    "RunId"      BIGINT        NOT NULL,
    "FcCode"     NVARCHAR(10)  NOT NULL,
    "RunType"    NVARCHAR(1)   NOT NULL,              -- F 正式 / S 模拟
    "Scenario"   NVARCHAR(30)  NOT NULL DEFAULT '',   -- 正式运行为空串
    "Initiator"  NVARCHAR(10)  NOT NULL DEFAULT 'USER',-- USER / AI
    "UserCode"   NVARCHAR(50),
    "StartTime"  TIMESTAMP     NOT NULL,
    "EndTime"    TIMESTAMP,
    "Status"     NVARCHAR(10)  NOT NULL,              -- RUNNING / OK / FAIL / BLOCKED / NOCONV
    "IterCount"  INT           NOT NULL DEFAULT 0,
    "Converged"  NVARCHAR(1)   NOT NULL DEFAULT 'N',
    "Params"     NCLOB,                               -- 本次运行读到的参数快照（JSON）
    "Msg"        NVARCHAR(2000),
    PRIMARY KEY ("RunId")
)
@@
COMMENT ON TABLE "MTC_CA_RUN" IS '成本计算运行日志：一行 = 一次运行，每次运行都保留'
@@
COMMENT ON COLUMN "MTC_CA_RUN"."RunType" IS 'F 正式 / S 模拟'
@@
COMMENT ON COLUMN "MTC_CA_RUN"."Scenario" IS '模拟场景编码（MTC_CA_C_SCENARIO），正式运行为空串'
@@
COMMENT ON COLUMN "MTC_CA_RUN"."Initiator" IS '发起方：USER 用户 / AI 执行台助手'
@@
COMMENT ON COLUMN "MTC_CA_RUN"."Status" IS 'RUNNING 运行中 / OK 成功 / FAIL 失败 / BLOCKED 计算前检查阻断 / NOCONV 未收敛'
@@
COMMENT ON COLUMN "MTC_CA_RUN"."Params" IS '本次运行读到的参数（JSON），便于复现'
@@
CREATE INDEX "MTC_CA_RUN_IX1" ON "MTC_CA_RUN" ("FcCode", "RunType", "Scenario", "Status")
@@
CREATE COLUMN TABLE "MTC_CA_RUN_STEP" (
    "RunId"      BIGINT        NOT NULL,
    "StepNo"     INT           NOT NULL,
    "StepCode"   NVARCHAR(20)  NOT NULL,              -- P00 / P10 / P20 ...
    "StartTime"  TIMESTAMP     NOT NULL,
    "EndTime"    TIMESTAMP,
    "RowCnt"     BIGINT,
    "Status"     NVARCHAR(10)  NOT NULL,              -- RUNNING / OK / WARN / FAIL
    "Msg"        NVARCHAR(2000),
    PRIMARY KEY ("RunId", "StepNo")
)
@@
COMMENT ON TABLE "MTC_CA_RUN_STEP" IS '运行步骤日志：一行 = 一次运行的一个步骤'
@@
CREATE COLUMN TABLE "MTC_CA_RUN_ITER" (
    "RunId"          BIGINT        NOT NULL,
    "Iter"           INT           NOT NULL,
    "MaxPriceDelta"  DECIMAL(19,6),                   -- 本轮物料单价最大变化
    "PoolDelta"      DECIMAL(19,2),                   -- 费用池合计变化
    "CloseDifDelta"  DECIMAL(19,2),                   -- 关单差异合计变化
    "UnconvItems"    INT,                             -- 未达收敛标准的物料数
    "EndTime"        TIMESTAMP,
    PRIMARY KEY ("RunId", "Iter")
)
@@
COMMENT ON TABLE "MTC_CA_RUN_ITER" IS '迭代日志：一行 = 一次运行的一轮迭代（清单 S5.5）'
@@
CREATE COLUMN TABLE "MTC_CA_RUN_KPI" (
    "RunId"    BIGINT        NOT NULL,
    "KpiType"  NVARCHAR(30)  NOT NULL,                -- ITEM_PRICE / ITEM_QM_AMT / ORDER_COST / POOL / WIP ...
    "KeyCode"  NVARCHAR(100) NOT NULL DEFAULT '',     -- 物料、订单键等；合计类为空串
    "Value"    DECIMAL(19,6),
    PRIMARY KEY ("RunId", "KpiType", "KeyCode")
)
@@
COMMENT ON TABLE "MTC_CA_RUN_KPI" IS '指标快照：一行 = 一次运行的一个指标，每次运行都保留，用于比较两次运行'
@@
-- 账期状态（用户 2026-10-19，设计稿 Q36–Q40）：控制“生成凭单后不能再正式计算”。没有行 = OPEN 未计算；B1 锁定（OFPR.PeriodStat='Y'）在视图 MTC_CA_V_PERIOD 中显示为 LOCKED，不存这里。
CREATE COLUMN TABLE "MTC_CA_PERIOD" (
    "FcCode"     NVARCHAR(10)  NOT NULL,              -- 账期（OFPR.Code）
    "Status"     NVARCHAR(10)  NOT NULL,              -- CALC 已计算 / POSTED 已生成凭单
    "CalcRunId"  BIGINT,                              -- 最近一次成功的正式运行
    "PostRunId"  BIGINT,                              -- 生成凭单所用的正式运行（POSTED 时有值；下期期初取它）
    "PostUser"   NVARCHAR(50),                        -- 生成凭单的操作人
    "PostTime"   TIMESTAMP,                           -- 生成凭单的时间
    "UpdUser"    NVARCHAR(50),                        -- 最后一次改状态的操作人
    "UpdTime"    TIMESTAMP,                           -- 最后一次改状态的时间
    PRIMARY KEY ("FcCode")
)
@@
COMMENT ON TABLE "MTC_CA_PERIOD" IS '账期状态：CALC 已计算（可重算）/ POSTED 已生成凭单（不能正式计算和期初承接，撤销凭单后回到 CALC）；没有行 = 未计算'
@@
CREATE COLUMN TABLE "MTC_CA_PERIOD_LOG" (
    "FcCode"     NVARCHAR(10)  NOT NULL,              -- 账期（OFPR.Code）
    "LogTime"    TIMESTAMP     NOT NULL,              -- 改状态的时间
    "FromStatus" NVARCHAR(10)  NOT NULL,              -- 原状态 OPEN / CALC / POSTED
    "ToStatus"   NVARCHAR(10)  NOT NULL,              -- 新状态
    "RunId"      BIGINT,                              -- 相关运行
    "UserCode"   NVARCHAR(50),                        -- 操作人
    "Msg"        NVARCHAR(2000)                       -- 说明
)
@@
COMMENT ON TABLE "MTC_CA_PERIOD_LOG" IS '账期状态变更日志：一行 = 一次状态变化（计算成功、生成凭单、撤销凭单）'
