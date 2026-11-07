-- 2026-10-17 补丁：发出商品 140601 期末差额扣除手工调整后应等于期初差额（用户 2026-10-17）。
-- ① 底稿是否“本期已过账 / 已在未清凭单”改为按凭证代码 × 科目判断，B1 自动冲销不算（2026-09 运行 28：未清凭单有 AR03 / AR04 但没有 140601 分录，
--    底稿 AR03 / AR04 的 140601 计提被当成重复丢掉，POST-10 ⑤ 本月计提为 0）；
-- ② RECON_COSTONLY_AREAS 加 GOODS：140601 本期非成本凭证分录（手工调整）单独列出、不算差异；B1 自动冲销成本凭证（上月 AR03 / AR04）仍参与对账。
-- 已部署的库依次执行：本文件，16_p70_jdt.sql；然后在执行台“财务对账”点“重新对账”或重新计算。
-- 如果 B1 @MTC_CA_EXPSET 里维护了 RECON_COSTONLY_AREAS，那里也要加 GOODS（P05 会用 B1 的值覆盖）。
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-10', 'POST', 200, '发出商品对账', '140601 期末 = 期初 = 0（用户 2026-10-15）：月末 AR03 / AR04 把未开票部分全部计提，下月初 B1 自动冲销，所以业务端期初、期末都是 0，财务端含全部分录。本期构成：① 冲销上月计提（OJDT.StornoToTr 指向 AR03 / AR04）② 发货 DN01 ③ 样品转出 DN02 / DN04 ④ 发票 DN03 ⑤ 本月计提 AR03 / AR04，合计应为 0；另核对 ① = 上期末未开票（R_GOODS_OUT_BEG）、⑤ = 本期末未开票（R_GOODS_OUT），不一致单独列出（如旧框架按当前未清数量计提的上月金额）。差额 = 总账已过账 + 未清凭单 + 底稿中本期尚未过账的凭证 − 0；底稿分录按凭证代码 × 科目判断是否已过账，B1 自动冲销不算（2026-10-17）。手工调整（凭证代码不在 COST_TRANSCODES，参数 RECON_COSTONLY_AREAS 含 GOODS）单独列出、不算差异：期末差额扣除手工调整后应等于期初差额（用户 2026-10-17）', 'Y', 'S12') WITH PRIMARY KEY
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('RECON_COSTONLY_AREAS', '0000-00', '9999-99', ',WIP_PROD,GOODS,', 'LIST', '财务对账中只比较成本凭证（COST_TRANSCODES）的对账项：其他分录（手工凭证、单据自动凭证等）允许存在，单独列出、不算差异；可选 STOCK、WIP_PROD、WW_MAT、WW_FEE、GOODS、AP（用户 2026-10-13；GOODS 发出商品手工调整不算差异，用户 2026-10-17）') WITH PRIMARY KEY
