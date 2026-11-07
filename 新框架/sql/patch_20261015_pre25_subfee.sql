-- 2026-10-15 补丁：新增 PRE-25 其他收发货科目与库存交易事务配置不一致（阻断）；委外加工费退货没有关联采购收货时按退货行上的订单号找订单。
-- 已部署的库依次执行：本文件（种子），07_snapshot_procs.sql（重建 MTC_CA_P20_SUBFEE），08_precheck.sql（重建 MTC_CA_P10_PRECHECK）
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-25', 'PRE', 250, '其他收发货科目与库存交易事务配置不一致', '其他收货 / 发货行上的科目与库存交易事务配置（@U_CITRN1：业务类型 + 部门 + 物料组 → 科目）不一致，或配置中没有这个组合。例：210 其他辅助领用应记 5101 制造费用，记成 500101 时 YF01 借生产成本却没有订单承接，生产在产品对账对不上（POST-13）。范围见参数 ACCT_CHECK_BUSITYPES（用户 2026-10-15）', 'Y', 'S7') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('ACCT_CHECK_BUSITYPES', '0000-00', '9999-99', ',210,', 'LIST', 'PRE-25：要核对单据科目与库存交易事务配置（@U_CITRN1）的业务类型（@U_CIOTRN.Code），默认只查 210 其他辅助领用（用户 2026-10-15）') WITH PRIMARY KEY
