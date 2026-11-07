-- 2026-10-30 补丁（用户确认）：
--   1. 退料：收货单上用领料类业务类型（B03，如 302、308、309）、数量为正的行按退料 RTN304 计价（本单该材料平均领料单价，计入加权价），
--      原来按负数领料、物料当前单价定价；返工单退回自身产品时迭代每轮放大 −1.48 倍不收敛（FH100_COST_TEST #16，MTC_OWOR 512 / 511）。
--   2. 结转比例按净领料数量：MTC_CA_R_ORDER_MAT 新列 Ratio = max(订单比例, 累计入库 × 计划用量 ÷ 订单计划数 ÷ 净领料)，最高 1，P30 计算、P45 使用。
-- 已部署的库：执行部署包（会自动补 Ratio 列）；或依次执行本文件，12_p30_init.sql，13_p40_iter.sql，18_meta_comments.sql，04_seed.sql 中 RTN-01 / RETURN_BUSITYPES 两行，
--   再 CALL "MTC_CA_P_META_SYNC"()。离线改的，还没编译。
ALTER TABLE "MTC_CA_R_ORDER_MAT" ADD ("Ratio" DECIMAL(19,10))
@@
