-- 2026-10-29 补丁：迭代不收敛排查（用户反馈迭代到 49 轮单价越来越大）
--   1. 新表 MTC_CA_RUN_ITER_ITEM：每轮单价变化最大的前 ITER_TRACE_TOP 个物料（P40 写）。
--   2. 未收敛时（参数 KEEP_NOCONV = Y，默认）保留本次快照和最后一轮中间结果（P_RUN_CLEAN 新模式 NCV），可在执行台查看、用导出脚本导出；
--      下次同类运行成功时按原来的规则删掉，再次未收敛时删掉以前未收敛运行的。
-- 已部署的库依次执行：本文件，03_run_procs.sql（P_RUN_CLEAN），13_p40_iter.sql（P40），10_run_entry.sql（P_RUN），18_meta_comments.sql，
--   再 CALL "MTC_CA_P_META_SYNC"()。离线改的，还没编译。
-- 迭代明细（2026-10-29，用户反馈迭代到 49 轮单价越来越大）：每轮单价变化最大的前 N 个物料（参数 ITER_TRACE_TOP，默认 30），
-- 用来看哪些物料在发散、每轮放大多少倍。不在 P_RUN_CLEAN 的清理范围内，未收敛、成功都保留。
CREATE COLUMN TABLE "MTC_CA_RUN_ITER_ITEM" (
    "RunId"      BIGINT        NOT NULL,
    "Iter"       INT           NOT NULL,
    "Rk"         INT           NOT NULL,              -- 本轮按单价变化从大到小的名次
    "ItemCode"   NVARCHAR(50)  NOT NULL,
    "iLevel"     INT,
    "PriceDelta" DECIMAL(19,6),                       -- 四项单价两轮之差的最大值
    "Price"      DECIMAL(19,6),                       -- 本轮四项单价合计
    "LastPrice"  DECIMAL(19,6),                       -- 上一轮四项单价合计
    "PMat" DECIMAL(19,6), "PMfg" DECIMAL(19,6), "PLab" DECIMAL(19,6), "PSub" DECIMAL(19,6),
    "OpenQty"    DECIMAL(19,6),
    "OpenAmt"    DECIMAL(19,6),
    "InQty"      DECIMAL(19,6),                       -- 本轮计价入库数量（InVal = Y）
    "InAmt"      DECIMAL(19,6),
    "PriceSrc"   NVARCHAR(20),
    PRIMARY KEY ("RunId", "Iter", "Rk")
)
@@
COMMENT ON TABLE "MTC_CA_RUN_ITER_ITEM" IS '迭代明细：一行 = 一次运行一轮中单价变化最大的一个物料（前 ITER_TRACE_TOP 个），排查不收敛用'
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('ITER_TRACE_TOP', '0000-00', '9999-99', '30', 'INT', '迭代明细：每轮记录单价变化最大的前 N 个物料到 MTC_CA_RUN_ITER_ITEM，0 = 不记（2026-10-29）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('KEEP_NOCONV', '0000-00', '9999-99', 'Y', 'STR', '未收敛时保留本次快照和最后一轮中间结果供排查（Y），N = 删除（2026-10-29）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('ITER_TRACE_TOP', 'PARAM', '计算控制', 252, '迭代明细记录物料数', 'INT', NULL, '整数，每轮记录单价变化最大的前 N 个物料，排查不收敛用，如 30；0 = 不记') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('KEEP_NOCONV', 'PARAM', '计算控制', 254, '未收敛时保留中间结果', 'STR', 'Y,N', 'Y = 保留本次快照和最后一轮中间结果（可在执行台查看、导出排查），下次成功运行时自动删除；N = 删除') WITH PRIMARY KEY
@@
