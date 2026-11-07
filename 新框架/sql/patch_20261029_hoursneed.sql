-- 2026-10-29 补丁：需要维护工时的产品清单（PRE-14 按物料汇总，执行台“工时维护”页）
-- 已部署的库依次执行：本文件（建表），12_p30_init.sql（新过程 MTC_CA_P10_HOURS），10_run_entry.sql、17_p90_tools.sql（调用），
--   18_meta_comments.sql，最后 CALL "MTC_CA_P_META_SYNC"()。离线改的，还没编译。
CREATE COLUMN TABLE "MTC_CA_R_HOURS_NEED" (
    "FcCode" NVARCHAR(10) NOT NULL, "RunType" NVARCHAR(1) NOT NULL, "Scenario" NVARCHAR(30) NOT NULL, "RunId" BIGINT NOT NULL,
    "ItemCode"   NVARCHAR(50)   NOT NULL,       -- 产品（订单主件）
    "ItemName"   NVARCHAR(200),
    "ItmsGrpCod" NVARCHAR(20),
    "Pools"      NVARCHAR(500),                 -- 应分摊的费用池（逗号分隔）
    "OrderCnt"   INT,                           -- 本期有入库、应分摊的订单数
    "RecvQty"    DECIMAL(19,6),                 -- 这些订单本期入库数量合计
    "CurHours"   DECIMAL(19,6),                 -- 本期工时单里的单位工时：空 = 没有录，0 = 录了 0
    "RefHours"   DECIMAL(19,6),                 -- 参考工时：以前最近一个账期工时单里不为 0 的单位工时（只供参考，不写 B1）
    "RefFc"      NVARCHAR(30),                  -- 参考工时的账期
    PRIMARY KEY ("RunId", "ItemCode")
)
@@
COMMENT ON TABLE "MTC_CA_R_HOURS_NEED" IS '需要维护工时的产品（PRE-14 按物料汇总）：本期有入库、在费用池分摊范围内的订单，产品在本期工时单里没有单位工时或为 0；只读清单，不写 @MTC_COST_TIME'
