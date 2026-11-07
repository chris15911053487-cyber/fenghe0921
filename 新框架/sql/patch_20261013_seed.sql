-- 2026-10-13 补丁：PRE-04 改警告、PRE-05 忽略数量和金额为 0 的行、SRT-01 描述、新增 SRT-03、PRE-12 改警告（与 04_seed.sql 同步；只更新这 5 行，不重跑整个种子）
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-04', 'PRE', 40, '无原单销售退货', '没有原交货行的销售退货允许发生，只警告：有期初维护价按维护价，没有按本期加权价（原交货取 RDN1 标准来源，不是交货时取 U_BaseType / U_BaseEntry / U_BaseLine）', 'N', 'S10') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-05', 'PRE', 50, '交易类型可识别', '计价仓库的每条库存变动都能识别 TransCode（旧流程会静默丢弃，#13）；数量和金额都为 0 的行（如基于交货的应收发票 13）不报；应收贷项凭证退货入库也在此拦截', 'Y', 'S10') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_RULE" ("RuleId", "Scene", "Title", "Descr", "Basis") VALUES ('SRT-01', 'S10', '销售退货按原交货成本', '有原单的按原交货行成本冲回；无原单的以维护价为最终价，没有维护价按本期加权价（SRT-03）；应收贷项凭证退货入库不存在，不计', '用户确认') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_RULE" ("RuleId", "Scene", "Title", "Descr", "Basis") VALUES ('SRT-03', 'S10', '无原单退货没有维护价', '没有原交货、也没有期初维护价的销售退货按本期加权价，PRE-04 警告', '用户确认') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-12', 'PRE', 120, '委外加工费找不到订单', '加工费收货 / 退货关联不到订单，这笔金额不会进入任何订单（只警告，不阻断；用户 2026-10-13）', 'N', 'S4') WITH PRIMARY KEY
