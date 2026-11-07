-- 2026-10-29 补丁：无原单销售退货在物料没有任何价格来源时的提示（用户 2026-10-29）
--   计价口径不变：无原单退货有维护价按维护价，没有按本期加权价（SRT-03）。物料没有期初金额、没有计价入库、也没有维护价时，
--   加权价为 0，退货按 0 成本入库。PRE-04 说明区分这种情况；P50 给这类物料加“按 0 成本入库”标记，POST-07 报出（没有出库也报）；
--   PRE-23 判断“有原交货”改为与 P30 一致（BaseType = 15 且 BaseEntry 不为空）。
-- 已部署的库依次执行：本文件，08_precheck.sql（P10），12_p30_init.sql（P10_QCP / P30），14_p50_p60_p65.sql（P50），再 CALL "MTC_CA_P_META_SYNC"()。离线改的，还没编译。
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-04', 'PRE', 40, '无原单销售退货', '没有原交货行的销售退货允许发生，只警告：有期初维护价按维护价，没有按本期加权价；物料也没有其他价格来源（期初、计价入库）时加权价为 0，说明写“将按 0 成本入库”（2026-10-29）（原交货取 RDN1 标准来源，不是交货时取 U_BaseType / U_BaseEntry / U_BaseLine）', 'N', 'S10') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-07', 'POST', 170, '物料异常标记', '负库存、用了维护价或期初单价兜底、无价、没有任何价格来源时按 0 成本入库（2026-10-29）、期末数量为 0 但金额不为 0 且超过尾差结转上限 TAIL_MAX（以内的由 TAIL-01 结转）', 'Y', 'S1') WITH PRIMARY KEY
