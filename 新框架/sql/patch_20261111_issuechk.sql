-- 2026-11-11 补丁：计算后校验新增 POST-18 领料完整性、POST-19 完工没有材料、POST-20 单耗偏离（用户：生产入库的材料、收发存明细里的领料要有可比对的校验）
--   三项固定只警告（08_precheck.sql 的 P_CHECK_PUT 写死），不改 POST_WARN_IDS。
-- 已部署的库依次执行：本文件，08_precheck.sql（P_CHECK_PUT），14_p50_p60_p65.sql（P60），再 CALL "MTC_CA_P_META_SYNC"()。
-- 新参数 ISSUE_DEV_PCT、ISSUE_DEV_AMT 进了参数目录，部署后先执行 python3 新框架/tools/sl_import_costcfg.py --param 补到 B1，否则 PRE-28 阻断。
-- 离线写的，还没编译。
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('ISSUE_DEV_PCT', '0000-00', '9999-99', '10', 'DEC', 'POST-20 单耗偏离的比例上限（%）：订单 × 材料累计领料数量与按计划应领相差超过它才报（用户 2026-11-11）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('ISSUE_DEV_AMT', '0000-00', '9999-99', '500', 'DEC', 'POST-20 单耗偏离的影响金额下限（元，含）：偏离数量 × 物料本期单价达到本值才报（用户 2026-11-11）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('ISSUE_DEV_PCT', 'PARAM', '尾差与校验', 347, '单耗偏离报警比例', 'DEC', NULL, '%：POST-20 订单累计领料与按计划应领相差超过它才报，如 10') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('ISSUE_DEV_AMT', 'PARAM', '尾差与校验', 348, '单耗偏离报警金额', 'DEC', NULL, '元（含）：POST-20 偏离数量 × 单价达到本值才报，如 500') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-18', 'POST', 141, '领料完整性', '① 按订单核对：收发存明细里挂订单的领料 / 退料行合计 = 订单本期领料（不含加工费）；订单不在本期订单清单时这些行的金额进不了在产品 ② 生产领料（B03）、完工入库（B01）类业务没挂订单的行，按普通出入库计价，不进任何订单。固定只警告（用户 2026-11-11）', 'N', 'S5') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-19', 'POST', 142, '完工没有材料', '本期有完工入库，但本级材料（完工成本 − 本级分摊制造、人工 − 加工费结转，同 R02 本级分摊·材料）≤ 0：没领料就入库、领料挂错订单，或退料多于领料。固定只警告（用户 2026-11-11）', 'N', 'S5') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-20', 'POST', 143, '单耗偏离', '订单 × 材料：累计净领料数量与按计划应领（订单用料计划数 ÷ 订单计划数 × 累计完工数）比较。少领：本期有完工或关单的订单都比；超领、计划外领料（替代料）只比已完工的订单（本期关单或累计完工 ≥ 计划数）。偏离比例 > ISSUE_DEV_PCT 且影响金额（偏离数量 × 本期单价）≥ ISSUE_DEV_AMT 才报；不含加工费和联产品。固定只警告（用户 2026-11-11）', 'N', 'S5') WITH PRIMARY KEY
@@
