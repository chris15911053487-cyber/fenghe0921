-- 2026-11-06 补丁：POST-16 制造 / 人工费用波动（用户：制造费用按产量每月应在 100 万左右，单据做错成 10 万这种要警告）
--   本期费用（全部、各费用池）与本期之前最近 FEE_BASE_MONTHS 个账期的中位数比较，金额偏离且按产量折算也偏离才报；固定只警告，不改 POST_WARN_IDS。
-- 已部署的库依次执行：本文件，08_precheck.sql（P_CHECK_PUT），14_p50_p60_p65.sql（P60），再 CALL "MTC_CA_P_META_SYNC"()。
-- 新参数 FEE_DEV_PCT、FEE_DEV_AMT、FEE_BASE_MONTHS 进了参数目录，部署后先执行 python3 新框架/tools/sl_import_costcfg.py --param 补到 B1，否则 PRE-28 阻断。
-- 离线写的，还没编译。
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('FEE_DEV_PCT', '0000-00', '9999-99', '30', 'DEC', 'POST-16 费用波动的比例上限（%）：制造 / 人工费用与基准金额、与按产量折算的金额都相差超过它才报（用户 2026-11-06）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('FEE_DEV_AMT', '0000-00', '9999-99', '50000', 'DEC', 'POST-16 费用波动的金额下限（元，含）：差额达到本值才报，避免小费用池刷屏（用户 2026-11-06）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('FEE_BASE_MONTHS', '0000-00', '9999-99', '6', 'INT', 'POST-16 费用波动的基准月数：取本期之前最近几个已计算账期的中位数，不足 3 个月不比较（用户 2026-11-06）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('FEE_DEV_PCT', 'PARAM', '尾差与校验', 344, '费用波动报警比例', 'DEC', NULL, '%：POST-16 制造 / 人工费用与基准相差超过它才报，如 30') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('FEE_DEV_AMT', 'PARAM', '尾差与校验', 345, '费用波动报警金额', 'DEC', NULL, '元（含）：POST-16 差额达到本值才报，如 50000') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('FEE_BASE_MONTHS', 'PARAM', '尾差与校验', 346, '费用波动基准月数', 'INT', NULL, 'POST-16 取本期之前最近几个账期的中位数，如 6；不足 3 个月不比较') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-16', 'POST', 178, '制造 / 人工费用波动', '制造费用、人工费用（全部、各费用池）与本期之前最近 FEE_BASE_MONTHS 个账期的中位数比较，不含关单差异和历史委外转出：金额偏离基准，且也偏离“基准单位费用 × 本期产量”（产量能解释的不报）时报出，偏离 = 差额 ≥ FEE_DEV_AMT 且比例 > FEE_DEV_PCT；本期完全没有费用也报。用来发现单据做错、费用漏记或多记。固定只警告（用户 2026-11-06）', 'N', 'S6') WITH PRIMARY KEY
@@
