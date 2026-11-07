-- 2026-10-17 补丁（Q35）：以前账期已关闭的订单本期仍有加工费退货等挂上来时，按关单转关单差异；POST-06 中加工费留在未关闭订单上的只列示、不阻断；
-- RECON_COSTONLY_AREAS 加 WW_MAT：140801 本期手工调整（凭证代码为空）单独列出、不算差异。B1 @MTC_CA_EXPSET 若维护了该参数，那里也要改成 WIP_PROD,GOODS,WW_MAT（P05 会用 B1 的值覆盖）。
-- 已部署的库依次执行：本文件（检查说明），07_snapshot_procs.sql（P20_EXP 不再读 MRV2），12_p30_init.sql（P30），16_p70_jdt.sql（MR02 不再读 MRV2、P75），18_meta_comments.sql，再重新计算。
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-06', 'POST', 160, '委外对账', '140801 = 委外在产品（材料）；140802 = 订单上未结转加工费。140801 本期的非成本凭证分录（手工调整等）单独列出、不算差异（参数 RECON_COSTONLY_AREAS 含 WW_MAT，用户 2026-10-17）。加工费留在未关闭订单上的（本期没有入库）只在说明里列示、不阻断；截至期末已关闭的订单（含以前账期关闭、本期仍有加工费退货等挂上来的）按关单转关单差异（Q35，用户 2026-10-17）。期初 / 本期 / 期末分开列示业务、财务和差额：业务期初取承接 / 上期结果，财务期初 = 本期以前的总账 + 未清凭单；财务本期 = 本期分录 + 底稿中本期尚未过账的凭证（已过账或已在未清凭单的凭证代码不再加）；按参数 RECON_BLOCK_ON 判断（默认 CUR 本期差额，期初差额只列示；用户 2026-10-15；MTC_CA_F_RECON）', 'Y', 'S4') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('RECON_COSTONLY_AREAS', '0000-00', '9999-99', ',WIP_PROD,GOODS,WW_MAT,', 'LIST', '财务对账中只比较成本凭证（COST_TRANSCODES）的对账项：其他分录（手工凭证、单据自动凭证等）允许存在，单独列出、不算差异；可选 STOCK、WIP_PROD、WW_MAT、WW_FEE、GOODS、AP（用户 2026-10-13；GOODS 发出商品手工调整不算差异，用户 2026-10-17）') WITH PRIMARY KEY
@@
