-- 2026-10-15 补丁：执行台“科目余额表”（用户 2026-10-15）。新函数 MTC_CA_F_TB_ACCT（成本相关科目范围）、MTC_CA_F_TB_LINE（期初 / 本期总账 / 未清凭单 / 底稿分录），
-- 新参数 TB_EXTRA_ACCTS。已部署的库依次执行：本文件（参数种子），16_p70_jdt.sql（建函数）；执行台更新 actions.json / index.html
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('TB_EXTRA_ACCTS', '0000-00', '9999-99', ',', 'LIST', '执行台“科目余额表”：在默认范围（物料组存货科目、MTC_CA_C_ACCT 中的全部科目、5101 制造费用）之外再列出的科目或科目前缀，如 ,6602,1122,（用户 2026-10-15）') WITH PRIMARY KEY
