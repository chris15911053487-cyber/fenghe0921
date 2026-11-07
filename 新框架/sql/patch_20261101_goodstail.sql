-- =====================================================================
-- 2026-11-01 发出商品尾差（用户 2026-11-01：财务不允许 140601 留 0.01，处理不了的作期末差异转主营业务成本）
-- ① P70 新增 JZ04 发出商品尾差：140601 本期参与对账的分录（总账 + 未清凭单 + 本次底稿未过账部分，手工调整不算）合计不为 0、
--    在 ±GOODS_TAIL_MAX（默认 1 元）以内的，借 / 贷 TAIL_ADJ（640101），贷 / 借 140601；超过的不处理，POST-10 报出。
-- ② POST-10 140601 差额改为 ≥ 0.005 就报（原来 > 0.01）；F_RECON_LEDGER 的发出商品构成加 TAIL（JZ04）。
-- 已部署的库：执行本文件，再执行 16_p70_jdt.sql（重建 P70、F_RECON_LEDGER、P75），然后重新计算；执行台更新 js/core.js、js/pages.js、actions.json。
-- 未编译。改前备份 _backup/*_20261101_before_goodstail.*
-- =====================================================================
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-10', 'POST', 200, '发出商品对账', '140601 期末 = 期初 = 0（用户 2026-10-15）：月末 AR03 / AR04 把未开票部分全部计提，下月初 B1 自动冲销，所以业务端期初、期末都是 0，财务端含全部分录。本期构成：① 冲销上月计提（OJDT.StornoToTr 指向 AR03 / AR04）② 发货 DN01 ③ 样品转出 DN02 / DN04 ④ 发票 DN03 ⑤ 本月计提 AR03 / AR04，合计应为 0；另核对 ① = 上期末未开票（R_GOODS_OUT_BEG）、⑤ = 本期末未开票（R_GOODS_OUT），不一致单独列出（如旧框架按当前未清数量计提的上月金额）。差额 = 总账已过账 + 未清凭单 + 底稿中本期尚未过账的凭证 − 0；底稿分录按凭证代码 × 科目判断是否已过账，B1 自动冲销不算（2026-10-17）。手工调整（凭证代码不在 COST_TRANSCODES，参数 RECON_COSTONLY_AREAS 含 GOODS）单独列出、不算差异：期末差额扣除手工调整后应等于期初差额（用户 2026-10-17）。140601 差额不允许 0.01（用户 2026-11-01）：本期合计在 ±GOODS_TAIL_MAX（默认 1 元）以内的尾差由 P70 生成 JZ04 转入 TAIL_ADJ（640101 主营业务成本），本校验按差额 ≥ 0.005 报出', 'Y', 'S12') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('GOODS_TAIL_MAX', '0000-00', '9999-99', '1', 'DEC', '发出商品尾差结转上限（元，含）：140601 本期参与对账的分录合计不为 0、在 ±本值以内的，P70 生成 JZ04 转入 TAIL_ADJ（640101），超过的由 POST-10 报出（用户 2026-11-01）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('GOODS_TAIL_MAX', 'PARAM', '尾差与校验', 315, '发出商品尾差结转上限', 'DEC', NULL, '元（含）：140601 本期合计在 ± 本值以内的转 640101（JZ04），如 1；超过的 POST-10 报出') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_RULE" ("RuleId", "Scene", "Title", "Descr", "Basis") VALUES ('TAIL-02', 'S12', '发出商品尾差结转', '140601 本期 = 冲销上月计提 + 发货 + 样品转出 + 发票 + 本月计提，应为 0；四舍五入留下的尾差（±GOODS_TAIL_MAX 以内）生成 JZ04：借 / 贷 TAIL_ADJ（640101），贷 / 借 140601，期末差额 = 期初差额；超过的不处理，POST-10 报出', '用户确认') WITH PRIMARY KEY
