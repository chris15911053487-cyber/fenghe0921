-- 2026-10-13 补丁：财务端与业务端对账改为两个口径（MTC_CA_F_RECON），新增 POST-13。已部署的库依次执行：
--   16_p70_jdt.sql（新函数 + P75）、14_p50_p60_p65.sql（P60 去掉 POST-06）、本文件（检查项说明，与 04_seed / 15_p70_tables 同步）
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-06', 'POST', 160, '委外对账', '140801 = 委外在产品（材料）；140802 = 订单上未结转加工费（正常为 0）；另列加工费留在订单上的订单。口径①（过账前）总账 + 未清凭单 + 底稿 = 业务；口径②（过账后）总账 + 未清凭单 = 业务；本期成本凭证已过账时按②，否则按①（MTC_CA_F_RECON）', 'N', 'S4') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-09', 'POST', 190, '库存科目总账 = 业务', '按存货科目比较与新框架期末金额（替代 JZ04 尾差凭证，Q15）。口径①（过账前）总账 + 未清凭单 + 底稿 = 业务；口径②（过账后）总账 + 未清凭单 = 业务；本期成本凭证已过账时按②，否则按①（MTC_CA_F_RECON）', 'N', 'S16') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-10', 'POST', 200, '发出商品对账', '140601（三个来源都不含 AR03/AR04）= 发出商品（非样品）合计（同 C20）。口径①（过账前）总账 + 未清凭单 + 底稿 = 业务；口径②（过账后）总账 + 未清凭单 = 业务；本期成本凭证已过账时按②，否则按①（MTC_CA_F_RECON）', 'N', 'S12') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-11', 'POST', 210, '应付暂估对账', '220202（贷 − 借）按 U_VendorCode = 应付暂估（按供应商，同 C19）。口径①（过账前）总账 + 未清凭单 + 底稿 = 业务；口径②（过账后）总账 + 未清凭单 = 业务；本期成本凭证已过账时按②，否则按①（MTC_CA_F_RECON）', 'N', 'S12') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-13', 'POST', 225, '生产在产品对账', '500101 的成本凭证 = 生产 / 包装 / 返工订单（WorType ≠ 50）在产品，不含加工费；非成本凭证分录（手工凭证、单据自动凭证等）允许存在，单独列出、不算差异（参数 RECON_COSTONLY_AREAS）。口径①（过账前）总账 + 未清凭单 + 底稿 = 业务；口径②（过账后）总账 + 未清凭单 = 业务；本期成本凭证已过账时按②，否则按①（MTC_CA_F_RECON）', 'N', 'S5') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('RECON_COSTONLY_AREAS', '0000-00', '9999-99', ',WIP_PROD,', 'LIST', '财务对账中只比较成本凭证（COST_TRANSCODES）的对账项：其他分录（手工凭证、单据自动凭证等）允许存在，单独列出、不算差异；可选 STOCK、WIP_PROD、WW_MAT、WW_FEE、GOODS、AP（用户 2026-10-13）') WITH PRIMARY KEY
