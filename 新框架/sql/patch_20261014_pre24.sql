-- 2026-10-14 补丁：新增 PRE-24 工单类型不能为空（阻断）。已部署的库执行本文件，再执行 08_precheck.sql（重建 MTC_CA_P10_PRECHECK）
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-24', 'PRE', 240, '工单类型不能为空', '本期涉及的生产 / 委外 / 返工订单 U_OrdType 为空：分不到制造费用和人工，在产品对账（POST-06 / POST-13）也归不到对应科目（用户 2026-10-14）', 'Y', 'S6') WITH PRIMARY KEY
