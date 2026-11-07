-- 2026-10-14 补丁：POST-14 ② 尾差偏大改用新参数 TAIL_WARN（默认 0.1，绝对值 ≥ 才报）。已部署的库执行本文件，再执行 14_p50_p60_p65.sql
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('TAIL_WARN', '0000-00', '9999-99', '0.1', 'DEC', 'POST-14 尾差偏大的报警下限（元，含）：挤进出库行的尾差（行金额 − 数量 × 加权单价）绝对值达到本值才报；它吸收其他出库行的四舍五入累积差，几分钱属正常（用户 2026-10-14）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-14', 'POST', 175, '物料成本异常', '计算后逐物料检查单价、数量、金额：① 小尾差已结转（TAIL-01）② 挤进出库行的尾差绝对值 ≥ TAIL_WARN ③ 期末数量 0 金额不为 0 ④ 负库存、有数量无金额、金额为负 ⑤ 期末单价偏离本期加权单价 ⑥ 本期加权单价比期初单价波动超过 PRICE_JUMP_PCT 且影响金额超过 PRICE_JUMP_AMT ⑦ 有数量无金额的单据行（用户 2026-10-14）', 'N', 'S16') WITH PRIMARY KEY
