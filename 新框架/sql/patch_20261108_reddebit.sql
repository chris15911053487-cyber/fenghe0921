-- =====================================================================
-- 2026-11-08 YF01 / IO01 费用固定借方红字（用户 2026-11-08）
-- 起因：辅助领用退回（59 收货，业务类型 203 → O04）使 510109 / 部门 净额为负，新框架按正负把它记到贷方，财务按借方找不到。
--   旧 0801 的 YF01 / IO01 费用科目固定 Debit、存货科目固定 Credit，反向时是负数（红字）。
-- ① 新参数 JDT_RED_DEBIT_TRANSCODES（默认 YF01,IO01）：P70 写 R_JDT 时，列出的凭证代码费用科目（不是物料组存货科目的）固定借方、
--    存货科目固定贷方，负数红字；其他凭证代码照旧按正负分借贷，JZ05 照旧两行借方。
-- ①b PUR1 / PUR4 同旧 6101_1：存货 / 140802 固定借方、220202 固定贷方，退货多于收货时记负数，不再换方向（用户 2026-11-08，只改 P70，不加参数）。
-- ② 凭证行的部门、项目、供应商空串当 NULL：同科目、同部门的分录不再按 NULL / 空串分成两行。
-- ③ dev_server.py 生成凭单时贷方负数留在贷方（原来只保留借方负数）。B1 公司设置要允许负数金额，否则 Service Layer 会拒绝。
-- 已部署的库：执行本文件，再执行 16_p70_jdt.sql（重建 P70），在 B1 @MTC_CA_PARAM 加 JDT_RED_DEBIT_TRANSCODES = YF01,IO01
--   （否则 PRE-28 阻断；sl_import_costcfg.py --param 只补缺的），然后重新计算；服务器模式更新 dev_server.py 并重启。
-- 未编译。改前备份 _backup/*_20261108_before_reddebit.*
-- =====================================================================
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('JDT_RED_DEBIT_TRANSCODES', '0000-00', '9999-99', ',YF01,IO01,', 'LIST', '费用固定记借方的凭证代码：费用科目（行上科目）固定借方、存货科目固定贷方，退回 / 盘盈使净额反向时用红字（负数），不换到另一方；同旧 0801（用户 2026-11-08）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('JDT_RED_DEBIT_TRANSCODES', 'PARAM', '凭证与对账', 425, '费用固定借方（红字）的凭证代码', 'LIST', NULL, '凭证代码逗号分隔，如 YF01,IO01；列出的凭证费用科目固定借方、存货科目固定贷方，反向用负数') WITH PRIMARY KEY
@@
