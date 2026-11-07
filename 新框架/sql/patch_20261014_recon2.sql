-- 2026-10-14 补丁：财务对账按凭证代码合并两个口径（2026-09 运行中 PUR1/PUR2/PUR5、MR02 已过账、其他成本凭证未过账，
-- 口径① 把已过账部分重复计入，140301 差额 −2321.81 即 PUR 合计 + MR02）。已部署的库依次执行：
--   16_p70_jdt.sql（MTC_CA_F_RECON_LEDGER 加 Dup，MTC_CA_F_RECON 加 DupAmt / Diff / PendCodes / DupCodes，状态加 PART，P75 改说明）、
--   本文件（检查项说明，与 04_seed / 15_p70_tables 同步），然后在执行台“财务对账”页点“重新对账”，或重跑 P75
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-06', 'POST', 160, '委外对账', '140801 = 委外在产品（材料）；140802 = 订单上未结转加工费（正常为 0）；另列加工费留在订单上的订单。差额 = 总账已过账 + 未清凭单 + 底稿中本期尚未过账的凭证 − 业务；底稿中本期已过账或已在未清凭单的凭证代码不再加，部分过账时也不重复计入（全部未过账时同口径①，全部过账后同口径②；MTC_CA_F_RECON）', 'Y', 'S4') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-09', 'POST', 190, '库存科目总账 = 业务', '按存货科目比较与新框架期末金额（替代 JZ04 尾差凭证，Q15）。差额 = 总账已过账 + 未清凭单 + 底稿中本期尚未过账的凭证 − 业务；底稿中本期已过账或已在未清凭单的凭证代码不再加，部分过账时也不重复计入（全部未过账时同口径①，全部过账后同口径②；MTC_CA_F_RECON）', 'Y', 'S16') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-10', 'POST', 200, '发出商品对账', '140601（三个来源都不含 AR03/AR04）= 发出商品（非样品）合计（同 C20）。差额 = 总账已过账 + 未清凭单 + 底稿中本期尚未过账的凭证 − 业务；底稿中本期已过账或已在未清凭单的凭证代码不再加，部分过账时也不重复计入（全部未过账时同口径①，全部过账后同口径②；MTC_CA_F_RECON）', 'Y', 'S12') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-11', 'POST', 210, '应付暂估对账', '220202（贷 − 借）按 U_VendorCode = 应付暂估（按供应商，同 C19）。差额 = 总账已过账 + 未清凭单 + 底稿中本期尚未过账的凭证 − 业务；底稿中本期已过账或已在未清凭单的凭证代码不再加，部分过账时也不重复计入（全部未过账时同口径①，全部过账后同口径②；MTC_CA_F_RECON）', 'Y', 'S12') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-13', 'POST', 225, '生产在产品对账', '500101 的成本凭证 = 生产 / 包装 / 返工订单（WorType ≠ 50）在产品，不含加工费；非成本凭证分录（手工凭证、单据自动凭证等）允许存在，单独列出、不算差异（参数 RECON_COSTONLY_AREAS）。差额 = 总账已过账 + 未清凭单 + 底稿中本期尚未过账的凭证 − 业务；底稿中本期已过账或已在未清凭单的凭证代码不再加，部分过账时也不重复计入（全部未过账时同口径①，全部过账后同口径②；MTC_CA_F_RECON）', 'Y', 'S5') WITH PRIMARY KEY
