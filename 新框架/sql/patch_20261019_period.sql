-- 2026-10-19 补丁：账期状态控制（用户 2026-10-19，设计稿 Q36–Q40）
--   OPEN 未计算 → CALC 已计算（可重算）→ POSTED 已生成凭单（OBTF 待过账）；POSTED 时不能正式计算、不能重做期初承接，模拟照常。
--   上期未生成凭单、B1 账期状态为期末结算等只警告（写在 P00 步骤）。下期期初优先取上期生成凭单所用的运行。
-- 已部署的库依次执行：本文件（建表），03_run_procs.sql（视图 MTC_CA_V_PERIOD、P_PERIOD_GUARD、P_PERIOD_SET），
--   07_snapshot_procs.sql（P20_OPEN），09_bootstrap.sql（P_BOOTSTRAP），10_run_entry.sql（P_RUN），18_meta_comments.sql，
--   再 CALL "MTC_CA_P_META_SYNC"()。
-- 已有的成功正式运行：最后一段把每个账期最近一次成功的正式运行补记为 CALC（不生成凭单状态，凭单功能上线后再说）。
CREATE COLUMN TABLE "MTC_CA_PERIOD" (
    "FcCode"     NVARCHAR(10)  NOT NULL,
    "Status"     NVARCHAR(10)  NOT NULL,
    "CalcRunId"  BIGINT,
    "PostRunId"  BIGINT,
    "PostUser"   NVARCHAR(50),
    "PostTime"   TIMESTAMP,
    "UpdUser"    NVARCHAR(50),
    "UpdTime"    TIMESTAMP,
    PRIMARY KEY ("FcCode")
)
@@
COMMENT ON TABLE "MTC_CA_PERIOD" IS '账期状态：CALC 已计算（可重算）/ POSTED 已生成凭单（不能正式计算和期初承接，撤销凭单后回到 CALC）；没有行 = 未计算'
@@
CREATE COLUMN TABLE "MTC_CA_PERIOD_LOG" (
    "FcCode"     NVARCHAR(10)  NOT NULL,
    "LogTime"    TIMESTAMP     NOT NULL,
    "FromStatus" NVARCHAR(10)  NOT NULL,
    "ToStatus"   NVARCHAR(10)  NOT NULL,
    "RunId"      BIGINT,
    "UserCode"   NVARCHAR(50),
    "Msg"        NVARCHAR(2000)
)
@@
COMMENT ON TABLE "MTC_CA_PERIOD_LOG" IS '账期状态变更日志：一行 = 一次状态变化（计算成功、生成凭单、撤销凭单）'
@@
INSERT INTO "MTC_CA_PERIOD" ("FcCode", "Status", "CalcRunId", "UpdUser", "UpdTime")
SELECT "FcCode", 'CALC', MAX("RunId"), 'patch_20261019', CURRENT_TIMESTAMP
  FROM "MTC_CA_RUN" WHERE "RunType" = 'F' AND "Scenario" = '' AND "Status" = 'OK'
 GROUP BY "FcCode"
@@
INSERT INTO "MTC_CA_PERIOD_LOG" ("FcCode", "LogTime", "FromStatus", "ToStatus", "RunId", "UserCode", "Msg")
SELECT "FcCode", CURRENT_TIMESTAMP, 'OPEN', 'CALC', "CalcRunId", 'patch_20261019', '补丁补记：已有的最近一次成功正式运行'
  FROM "MTC_CA_PERIOD"
