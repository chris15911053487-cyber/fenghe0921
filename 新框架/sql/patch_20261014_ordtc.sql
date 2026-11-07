-- 2026-10-14 补丁：只有工单交易 I03/O03/I07/O07/I08/O08/I09/O09 关联订单（PRE-06 / PRE-10 口径同步）。已部署的库执行本文件，再执行 07_snapshot_procs.sql、08_precheck.sql
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-06', 'PRE', 60, '订单存在', '工单交易（I03/O03/I07/O07/I08/O08/I09/O09）行指向的订单（DocType + DocEntry）存在于订单快照；其他交易不关联订单（用户 2026-10-14）', 'Y', 'S5') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-10', 'PRE', 100, '已关闭订单仍有出入库', '期初前已关闭或已取消的订单本期仍有工单交易（I03/O03/I07/O07/I08/O08/I09/O09）或加工费（旧检查第 13、14 项）；其他交易填了订单号不报、也不计入订单成本（用户 2026-10-14）', 'N', 'S5') WITH PRIMARY KEY
