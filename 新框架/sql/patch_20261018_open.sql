-- 2026-10-18 补丁：期初料工费（用户 2026-10-18）
--   1. 期初承接按旧框架最近有完工账期的完工成本比例拆分料工费（新表 MTC_CA_BOOT_RATIO，物料期末在 P_BOOTSTRAP 拆，订单 × 材料在 P20_OPEN 拆）；
--   2. P20_OPEN 实现“上期是新框架账期”：取上期最近一次成功正式运行的 R_ITEM 期末、R_ORDER_MAT 累计数、R_ORDER 累计入库（2026-10 起不再被 PRE-16 阻断）。
-- 已部署的库依次执行：本文件（建表），07_snapshot_procs.sql（P20_OPEN），09_bootstrap.sql（P_BOOTSTRAP），18_meta_comments.sql；
-- 然后重新执行期初承接 CALL "MTC_CA_P_BOOTSTRAP"('2026-08')，再重新计算 2026-09（之后各期按顺序重算）。
CREATE COLUMN TABLE "MTC_CA_BOOT_RATIO" (
    "FcCode"     NVARCHAR(10)   NOT NULL,       -- 承接账期
    "ItemCode"   NVARCHAR(50)   NOT NULL,
    "RatioFc"    NVARCHAR(10)   NOT NULL,       -- 取比例的旧框架账期（截至承接账期最近一个有完工的账期）
    "RMat"       DECIMAL(19,10) NOT NULL DEFAULT 1,
    "RMfg"       DECIMAL(19,10) NOT NULL DEFAULT 0,
    "RLab"       DECIMAL(19,10) NOT NULL DEFAULT 0,
    "RSub"       DECIMAL(19,10) NOT NULL DEFAULT 0,
    "Basis"      NVARCHAR(200),
    "LoadTime"   TIMESTAMP,
    PRIMARY KEY ("FcCode", "ItemCode")
)
@@
COMMENT ON TABLE "MTC_CA_BOOT_RATIO" IS '期初承接：物料料工费比例（旧 0321_OWOR_SUM 最近有完工账期的完工成本四项，材料按领料逐级展开；用户 2026-10-18），拆分 BOOT_ITEM 期末和订单领料'
@@
COMMENT ON TABLE "MTC_CA_BOOT_ITEM" IS '期初承接：旧框架该期物料期末（MTC_COST_0301_INVNT.QM_*），料工费按 MTC_CA_BOOT_RATIO 拆分，没有比例的全部记材料'
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_S_OPEN', 'S', 'P20_OPEN：上期是承接账期时取 MTC_CA_BOOT_ITEM（旧框架 0301 期末，P_BOOTSTRAP 写入，料工费按 BOOT_RATIO 拆分）；否则取上期最近一次成功正式运行的 R_ITEM 期末') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_S_ORDER_OPEN', 'S', 'P20_OPEN：上期是承接账期时取 MTC_CA_BOOT_ORDER_MAT（旧框架 CO4011 / ZCP1，按领用材料的 BOOT_RATIO 拆分料工费）；否则取上期最近一次成功正式运行的 R_ORDER_MAT 累计数（未关闭订单）') WITH PRIMARY KEY
@@
