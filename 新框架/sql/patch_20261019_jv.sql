-- 2026-10-19 补丁：生成 SAP 日记账凭单（用户 2026-10-19，设计稿 8.6，Q36 / Q41–Q44）
-- 已部署的库依次执行：patch_20261019_period.sql（如还没执行），本文件（建表），03_run_procs.sql（P_PERIOD_GUARD 加“部分生成”检查），
--   19_jv.sql，18_meta_comments.sql，再 CALL "MTC_CA_P_META_SYNC"()。
-- B1 前台另需手工添加 日记账分录 表头字段 MTC_CARunId（数字 11），见设计稿 8.6。
-- 生成的 SAP 日记账凭单（用户 2026-10-19，设计稿 8.6，Q36 / Q41–Q44）：执行台服务器模式经 Service Layer 建 OBTF 后记一行
CREATE SEQUENCE "MTC_CA_SEQ_JV" START WITH 1 INCREMENT BY 1 NO CYCLE
@@
CREATE COLUMN TABLE "MTC_CA_JV" (
    "JvId"       BIGINT        NOT NULL,              -- 记录号
    "FcCode"     NVARCHAR(10)  NOT NULL,              -- 账期（OFPR.Code）
    "RunId"      BIGINT        NOT NULL,              -- 生成凭单所用的正式运行
    "TransCode"  NVARCHAR(10)  NOT NULL,              -- 凭证代码（OTRC，一种代码一张凭单）
    "BatchNum"   INT,                                 -- B1 日记账凭单批号（OBTF.BatchNum），失败时为空
    "Status"     NVARCHAR(10)  NOT NULL,              -- CREATED 已生成 / FAIL 失败 / DELETED 已撤销
    "Debit"      DECIMAL(19,2),                       -- 借方合计
    "Credit"     DECIMAL(19,2),                       -- 贷方合计
    "LineCnt"    INT,                                 -- 分录行数
    "CreateUser" NVARCHAR(50),                        -- 生成人（B1 账号，凭单在 B1 里的创建人）
    "CreateTime" TIMESTAMP     NOT NULL,              -- 生成时间
    "DelUser"    NVARCHAR(50),                        -- 撤销人
    "DelTime"    TIMESTAMP,                           -- 撤销时间
    "Msg"        NVARCHAR(2000),                      -- 说明或 Service Layer 报错
    PRIMARY KEY ("JvId")
)
@@
COMMENT ON TABLE "MTC_CA_JV" IS '生成的 SAP 日记账凭单（OBTF）：一行 = 一种凭证代码的一次生成；撤销后 Status = DELETED'
@@
CREATE INDEX "MTC_CA_JV_IX1" ON "MTC_CA_JV" ("FcCode", "Status")
