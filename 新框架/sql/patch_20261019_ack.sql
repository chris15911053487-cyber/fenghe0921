-- 2026-10-19 补丁：计算后校验阻断项的人工确认（用户 2026-10-19，设计稿 8.6 Q45）
-- 已部署的库依次执行：本文件（建表），19_jv.sql（P_JV_BEGIN 跳过已确认的项，新增 P_CHECK_ACK / P_CHECK_UNACK），18_meta_comments.sql，再 CALL "MTC_CA_P_META_SYNC"()。
-- 计算后校验阻断项的人工确认（用户 2026-10-19，设计稿 8.6 Q45）：管理权限逐项确认并写理由后，生成凭单不再被这一项阻断；只对这次运行有效
CREATE COLUMN TABLE "MTC_CA_CHECK_ACK" (
    "RunId"      BIGINT        NOT NULL,              -- 运行号（MTC_CA_RUN.RunId）
    "CheckId"    NVARCHAR(20)  NOT NULL,              -- 校验编号（MTC_CA_C_CHECK，Stage = POST、结果 FAIL）
    "UserCode"   NVARCHAR(50)  NOT NULL,              -- 确认人（B1 账号）
    "AckTime"    TIMESTAMP     NOT NULL,              -- 确认时间
    "Reason"     NVARCHAR(500) NOT NULL,              -- 确认理由
    PRIMARY KEY ("RunId", "CheckId")
)
@@
COMMENT ON TABLE "MTC_CA_CHECK_ACK" IS '计算后校验阻断项的人工确认：确认后生成凭单不再被该项阻断；只对这次运行有效，重新计算要重新确认；取消确认会删行（日志见 MTC_CA_PERIOD_LOG）'
