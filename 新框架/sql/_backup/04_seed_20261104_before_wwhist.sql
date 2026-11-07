-- =====================================================================
-- 新成本框架 第 1 期：配置初始数据（可重复执行，UPSERT 按主键覆盖）
-- 只含规则和代码层面的配置，不含业务数据。
-- =====================================================================
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('CONV_PRICE', '0000-00', '9999-99', '0.000001', 'DEC', '收敛标准：物料四项单价两轮之差的上限') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('CONV_AMT', '0000-00', '9999-99', '0.01', 'DEC', '收敛标准：费用池、关单差异两轮之差的上限（元）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('TAIL_MAX', '0000-00', '9999-99', '0.02', 'DEC', '零库存尾差结转上限（元，含）：期末数量 0、金额在 ±本值以内且没有出库行可挤的，结转到 TAIL_ADJ 科目（JZ04，TAIL-01；Q32 用户 2026-10-14）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('TAIL_WARN', '0000-00', '9999-99', '0.1', 'DEC', 'POST-14 尾差偏大的报警下限（元，含）：挤进出库行的尾差（行金额 − 数量 × 加权单价）绝对值达到本值才报；它吸收其他出库行的四舍五入累积差，几分钱属正常（用户 2026-10-14）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('PRICE_JUMP_PCT', '0000-00', '9999-99', '30', 'DEC', 'POST-14 价格波动 / 期末单价偏离的比例上限（%）：本期加权单价与期初单价、期末单价与本期加权单价相差超过它才报（用户 2026-10-14）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('PRICE_JUMP_AMT', '0000-00', '9999-99', '100', 'DEC', 'POST-14 价格波动 / 期末单价偏离的影响金额下限（元）：同时超过比例和本金额才报，避免小金额物料刷屏（用户确认 2026-10-14）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('MAX_ITER', '0000-00', '9999-99', '50', 'INT', '最大迭代轮数，超过仍未收敛则运行状态为 NOCONV、不写结果') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('ITER_TRACE_TOP', '0000-00', '9999-99', '30', 'INT', '迭代明细：每轮记录单价变化最大的前 N 个物料到 MTC_CA_RUN_ITER_ITEM，0 = 不记（2026-10-29）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('KEEP_NOCONV', '0000-00', '9999-99', 'Y', 'STR', '未收敛或迭代及以后出错时保留本次快照和最后一轮中间结果供排查（Y），N = 删除（2026-10-29；出错 2026-10-30）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('LEVEL_GUARD', '0000-00', '9999-99', '30', 'INT', '物料层级计算的保护上限（防止循环引用死循环），不是业务层数限制') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('START_FC', '0000-00', '9999-99', '2026-10', 'STR', '新框架起始账期（清单 R3；用户 2026-11-02 改为 2026-10）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('BOOTSTRAP_FC', '0000-00', '9999-99', '2026-09', 'STR', '期初承接账期：从旧框架该期结果取期初（设计稿第 7 节；用户 2026-11-02 改为 2026-09）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_ACCT" ("Usage", "FromFc", "ToFc", "AcctCode", "Descr") VALUES ('WIP_PROD', '0000-00', '9999-99', '500101', '生产订单领料 / JZ01 贷方（0801、COJZ_01，读代码）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_ACCT" ("Usage", "FromFc", "ToFc", "AcctCode", "Descr") VALUES ('MFG_SHARED', '0000-00', '9999-99', '500103', '公摊费用（0311 库存重估-委外工单差异，读代码）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_ACCT" ("Usage", "FromFc", "ToFc", "AcctCode", "Descr") VALUES ('CLOSE_DIF_PROD', '0000-00', '9999-99', '510199', '制造费用-关闭工单差异：生产订单（JZ01 借方）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_ACCT" ("Usage", "FromFc", "ToFc", "AcctCode", "Descr") VALUES ('CLOSE_DIF_WW', '0000-00', '9999-99', '510198', '关单差异：委外订单（JZ03 借方）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_ACCT" ("Usage", "FromFc", "ToFc", "AcctCode", "Descr") VALUES ('WW_MAT', '0000-00', '9999-99', '140801', '委外加工物资-材料（用户确认）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_ACCT" ("Usage", "FromFc", "ToFc", "AcctCode", "Descr") VALUES ('WW_FEE', '0000-00', '9999-99', '140802', '委外加工物资-加工费（用户确认）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_ACCT" ("Usage", "FromFc", "ToFc", "AcctCode", "Descr") VALUES ('GOODS_ISSUED', '0000-00', '9999-99', '140601', '发出商品（DN01–DN04、AR03/AR04）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_ACCT" ("Usage", "FromFc", "ToFc", "AcctCode", "Descr") VALUES ('AP_ACCRUAL', '0000-00', '9999-99', '220202', '应付暂估（6101_1 PUR1–PUR5）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_ACCT" ("Usage", "FromFc", "ToFc", "AcctCode", "Descr") VALUES ('COGS_DOM', '0000-00', '9999-99', '640101', '主营业务成本-国内客户（@MTC_SALORDTYPE.U_CustType=国内客户）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_ACCT" ("Usage", "FromFc", "ToFc", "AcctCode", "Descr") VALUES ('TAIL_ADJ', '0000-00', '9999-99', '640101', '零库存尾差结转对方科目（JZ04，TAIL-01；Q31 用户 2026-10-14：进主营业务成本）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_ACCT" ("Usage", "FromFc", "ToFc", "AcctCode", "Descr") VALUES ('COGS_EXP', '0000-00', '9999-99', '640103', '主营业务成本-国外客户（U_CustType=国外客户）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_ACCT" ("Usage", "FromFc", "ToFc", "AcctCode", "Descr") VALUES ('SAMPLE', '0000-00', '9999-99', '660106', '样品成本（0801 样品段，读代码，待确认）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_RULE" ("RuleId", "Scene", "Title", "Descr", "Basis") VALUES ('LVL-01', 'S0', '物料层级', '按本期 BOM 计算层级：无 BOM 为 0 级，其余 = 子件最高级 + 1；子件缺失或循环引用为 -1，阻断计算；手工覆盖见 MTC_CA_C_LEVEL_OVR；不限层数', '读代码') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_RULE" ("RuleId", "Scene", "Title", "Descr", "Basis") VALUES ('QCP-01', 'S1', '期初维护价只做初值和兜底', '第 1 轮迭代用维护价（无则上期期末单价），之后用上一轮本期加权价；物料本期确实算不出价格时以维护价为最终价并标注兜底', '用户确认') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_RULE" ("RuleId", "Scene", "Title", "Descr", "Basis") VALUES ('RWK-01', 'S2', '返工单同层求解', '返工单领用的 A 与产出的 A 同层，领料按上一轮 A 的单价，迭代收敛后一致', '用户确认') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_RULE" ("RuleId", "Scene", "Title", "Descr", "Basis") VALUES ('TRF-01', 'S3', '形态转换 A 入 = B 出', 'I05 金额 = 配对 O05 金额；O05 用 B 本期最终加权价；只允许同月一对一', '用户确认') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_RULE" ("RuleId", "Scene", "Title", "Descr", "Basis") VALUES ('WW-01', 'S4', '委外加工费按订单归集', '加工费按订单归集（含 MTC_OWOR 订单）；订单本期有入库时累计未结转加工费全部结转，无入库时留在订单上，关单时转关单差异', '用户确认') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_RULE" ("RuleId", "Scene", "Title", "Descr", "Basis") VALUES ('WIP-01', 'S5', '订单 × 材料按比例结转', '本期结转 = 累计领料 × min(累计入库数 ÷ 计划数, 1) − 以前已结转；在产品 = 累计领料 − 累计结转', '用户确认') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_RULE" ("RuleId", "Scene", "Title", "Descr", "Basis") VALUES ('CLS-01', 'S5.5', '关单差异迭代求解', '本期关单 = 截至期末状态为关闭且关单日期在本期；剩余在产品转关单差异，进入下一轮费用池，直到收敛', '用户确认') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_RULE" ("RuleId", "Scene", "Title", "Descr", "Basis") VALUES ('EXP-01', 'S6', '费用分摊', '费用来源按成本中心归入费用池（C_POOL_SRC，没配的和没有成本中心的进默认池）；关单差异全部进 CLOSE_DIF_POOL；各池按单位工时 × 本期入库数一步分到池范围内（C_POOL_TGT）本期有入库的订单，不进在产品；池没有可分摊入库的金额留在池里报未分摊，不自动转下期（设计稿 4.4，Q9–Q13）', '用户确认') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_RULE" ("RuleId", "Scene", "Title", "Descr", "Basis") VALUES ('TRY-01', 'S7', '生产试打计入制造费用', '试打领用（O04 → 5101）作为公摊材料费用进入费用池', '用户确认') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_RULE" ("RuleId", "Scene", "Title", "Descr", "Basis") VALUES ('RTN-01', 'S8', '生产退料', '业务类型 304（参数 RETURN_BUSITYPES），以及收货单上用领料类业务类型（B03，如 302、308、309）的行——就是退料（用户确认 2026-10-30）：按该订单该材料截至本期的平均领料单价，取不到用物料加权价', '建议') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_RULE" ("RuleId", "Scene", "Title", "Descr", "Basis") VALUES ('SRT-01', 'S10', '销售退货按原交货成本', '有原单的按原交货行成本冲回；无原单的以维护价为最终价，没有维护价按本期加权价（SRT-03）；应收贷项凭证退货入库不存在，不计', '用户确认') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_RULE" ("RuleId", "Scene", "Title", "Descr", "Basis") VALUES ('WHS-01', 'S14', '计价仓库范围', '只计 OWHS.U_IsCost=''Y'' 的仓库（例外见 MTC_CA_C_WHS）；跨计价范围的库存转储不允许，计算前阻断', '用户确认') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_RULE" ("RuleId", "Scene", "Title", "Descr", "Basis") VALUES ('RND-01', 'S16', '尾差', '计算用 DECIMAL(19,6)，金额最后取 2 位，尾差挤进同组金额最大的一行', '读代码') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_RULE" ("RuleId", "Scene", "Title", "Descr", "Basis") VALUES ('TAIL-01', 'S16', '零库存尾差结转', '期末数量为 0、金额不为 0 且没有出库行可挤尾差时，总额和四项都在 ±TAIL_MAX（0.02）以内的，计入出库、期末清零，生成 JZ04：借 / 贷 TAIL_ADJ（640101），贷 / 借存货；超过的留在期末，POST-07 报出', '用户确认') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-01', 'PRE', 10, '账期未锁定', '正式运行不能算已锁定账期（P00 已执行）', 'Y', 'R1') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-02', 'PRE', 20, '物料层级完整', '本期有变动的物料都有层级，且没有 -1（子件缺失、循环引用）', 'Y', 'S0') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-03', 'PRE', 30, '形态转换同月一对一', '同旧检查第 15 项：配对键完整、同月、一对一', 'Y', 'S3') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-04', 'PRE', 40, '无原单销售退货', '没有原交货行的销售退货允许发生，只警告：有期初维护价按维护价，没有按本期加权价；物料也没有其他价格来源（期初、计价入库）时加权价为 0，说明写“将按 0 成本入库”（2026-10-29）（原交货取 RDN1 标准来源，不是交货时取 U_BaseType / U_BaseEntry / U_BaseLine）', 'N', 'S10') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-05', 'PRE', 50, '交易类型可识别', '计价仓库的每条库存变动都能识别 TransCode（旧流程会静默丢弃，#13）；数量和金额都为 0 的行（如基于交货的应收发票 13）不报；应收贷项凭证退货入库也在此拦截', 'Y', 'S10') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-06', 'PRE', 60, '订单存在', '工单交易（I03/O03/I07/O07/I08/O08/I09/O09）行指向的订单（DocType + DocEntry）存在于订单快照；其他交易不关联订单（用户 2026-10-14）', 'Y', 'S5') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-07', 'PRE', 70, '跨计价范围转储', '库存转储一端是计价仓库、另一端不是：不允许（设计稿 Q7）', 'Y', 'S14') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-08', 'PRE', 80, '非计价仓库中的生产和采购', 'U_IsCost 不是 Y 的仓库中有订单领料、完工或采购入库，提示核对仓库设置；参数 PRE08_EXCL_WHS 列出的仓库不报（用户 2026-10-29）', 'N', 'S14') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-09', 'PRE', 90, '试打订单领料类型', '试打订单（WorType 40）只能用 307 试打领用、305 生产报废（旧检查第 4 项）', 'N', 'S7') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-01', 'POST', 110, '期末数量 = B1', '逐物料期末数量 = OIVL 截至期末数量（计价仓库）', 'Y', 'S14') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-02', 'POST', 120, '进销存四项平衡', '期初 + 入 − 出 = 期末，四项分别成立', 'Y', 'R1') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-03', 'POST', 130, '费用守恒', '费用池 = 已分摊 + 未分摊；未分摊须为 0 或说明原因', 'Y', 'S6') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-04', 'POST', 140, '订单结转勾稽', '累计领料 = 累计结转 + 在产品；关单订单在产品 = 0', 'Y', 'S5') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-05', 'POST', 150, '配对金额', 'I05 金额 = 配对 O05 金额；退货成本 = 原交货成本', 'Y', 'S3') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-06', 'POST', 160, '委外对账', '140801 = 委外在产品（材料）；140802 = 订单上未结转加工费。140801 本期的非成本凭证分录（手工调整等）单独列出、不算差异（参数 RECON_COSTONLY_AREAS 含 WW_MAT，用户 2026-10-17）。加工费留在未关闭订单上的（本期没有入库）只在说明里列示、不阻断；截至期末已关闭的订单（含以前账期关闭、本期仍有加工费退货等挂上来的）按关单转关单差异（Q35，用户 2026-10-17）。期初 / 本期 / 期末分开列示业务、财务和差额：业务期初取承接 / 上期结果，财务期初 = 本期以前的总账 + 未清凭单；财务本期 = 本期分录 + 底稿中本期尚未过账的凭证（已过账或已在未清凭单的凭证代码不再加）；按参数 RECON_BLOCK_ON 判断（默认 CUR 本期差额，期初差额只列示；用户 2026-10-15；MTC_CA_F_RECON）', 'Y', 'S4') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('BOOT-01', 'POST', 200, '期初承接：ZCP1 与 ZCP 一致', '承接后逐订单比较 ZCP1 合计与 0322_OWOR_ZCP，不一致的列出，不自动调整（设计稿 Q8）', 'Y', 'S5.6') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_TOOL" ("ToolName", "Title", "Descr", "ProcName", "IsWrite", "NeedConfirm", "ModelOutput", "Phase") VALUES ('cost.precheck', '计算前检查', '执行登记的 PRE 校验', NULL, 'N', 'N', '各检查项是否通过、问题行数', 4) WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_TOOL" ("ToolName", "Title", "Descr", "ProcName", "IsWrite", "NeedConfirm", "ModelOutput", "Phase") VALUES ('cost.run', '成本计算', '正式 / 模拟计算，只写 MTC_CA_*', 'MTC_CA_P_RUN', 'Y', 'N', 'Code、Msg、RunId、运行状态', 4) WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_TOOL" ("ToolName", "Title", "Descr", "ProcName", "IsWrite", "NeedConfirm", "ModelOutput", "Phase") VALUES ('cost.status', '运行状态', '运行头、步骤、迭代日志', NULL, 'N', 'N', '状态、步骤、行数、迭代次数', 4) WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_TOOL" ("ToolName", "Title", "Descr", "ProcName", "IsWrite", "NeedConfirm", "ModelOutput", "Phase") VALUES ('cost.checks', '校验结果', 'POST 校验结果', NULL, 'N', 'N', '各校验是否通过、问题行数', 4) WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_TOOL" ("ToolName", "Title", "Descr", "ProcName", "IsWrite", "NeedConfirm", "ModelOutput", "Phase") VALUES ('cost.explain_item', '解释物料单价', '按成本构成表展开物料单价', NULL, 'N', 'N', '仅状态；明细只在本地页面显示', 4) WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_TOOL" ("ToolName", "Title", "Descr", "ProcName", "IsWrite", "NeedConfirm", "ModelOutput", "Phase") VALUES ('cost.explain_order', '解释订单成本', '按成本构成表展开订单成本', NULL, 'N', 'N', '仅状态；明细只在本地页面显示', 4) WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_TOOL" ("ToolName", "Title", "Descr", "ProcName", "IsWrite", "NeedConfirm", "ModelOutput", "Phase") VALUES ('cost.compare_runs', '比较两次运行', '用指标快照比较', NULL, 'N', 'N', '有差异的指标数', 4) WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_TOOL" ("ToolName", "Title", "Descr", "ProcName", "IsWrite", "NeedConfirm", "ModelOutput", "Phase") VALUES ('cost.compare_old', '新旧比对', '与旧框架结果比对，差异按原因归类', NULL, 'N', 'N', '各类差异的行数', 4) WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_TOOL" ("ToolName", "Title", "Descr", "ProcName", "IsWrite", "NeedConfirm", "ModelOutput", "Phase") VALUES ('cost.report', '本期计算说明', '本地模板生成', NULL, 'N', 'N', '是否生成成功', 4) WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_TOOL" ("ToolName", "Title", "Descr", "ProcName", "IsWrite", "NeedConfirm", "ModelOutput", "Phase") VALUES ('meta.describe', '查说明', '查表、字段、规则、校验、工具的说明', NULL, 'N', 'N', '说明文本（不含业务数据）', 4) WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_TOOL" ("ToolName", "Title", "Descr", "ProcName", "IsWrite", "NeedConfirm", "ModelOutput", "Phase") VALUES ('doc.manual', '系统说明书', '由元数据和登记表生成', NULL, 'N', 'N', '是否生成成功', 4) WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_TOOL" ("ToolName", "Title", "Descr", "ProcName", "IsWrite", "NeedConfirm", "ModelOutput", "Phase") VALUES ('jdt.generate', '生成凭证', '第 3 期', NULL, 'Y', 'Y', '是否生成成功、凭证数', 3) WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-10', 'PRE', 100, '已关闭订单仍有出入库', '期初前已关闭或已取消的订单本期仍有工单交易（I03/O03/I07/O07/I08/O08/I09/O09）或加工费（旧检查第 13、14 项）；其他交易填了订单号不报、也不计入订单成本（用户 2026-10-14）', 'N', 'S5') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-11', 'PRE', 110, '关闭订单缺关单日期', '状态为关闭但没有关单日期，无法判断在哪一期结转关单差异（Q4）', 'Y', 'S5.5') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-12', 'PRE', 120, '委外加工费找不到订单', '加工费收货 / 退货关联不到订单，这笔金额不会进入任何订单（只警告，不阻断；用户 2026-10-13）', 'N', 'S4') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-13', 'PRE', 130, '同一产品多个工时', '同一账期同一产品在工时单中有不同的单位工时：工时决定分摊比例，先改工时单（Q21 用户确认阻断）', 'Y', 'S6') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-14', 'PRE', 140, '应分摊订单的产品没有工时', '本期有入库、在费用池分摊范围内的订单，产品没有工时：先补工时（旧代码静默不分；Q11 用户确认阻断）', 'Y', 'S6') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-15', 'PRE', 150, '制造费用可能重复计入', '制造费用凭证来自其他出入库 / 盘点单，而该单据行又作为公摊材料计入费用池', 'N', 'S6') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-16', 'PRE', 160, '有期初', '上期是承接账期时需先运行 MTC_CA_P_BOOTSTRAP；否则需有上期新框架正式结果', 'Y', 'R3') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-17', 'PRE', 170, '产品不在费用池范围', '本期有入库的生产订单，产品（按物料组或 U_ItemGrpType）不在 MTC_CA_C_POOL_TGT 范围内，分不到制造费用和人工', 'N', 'S6') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('CHECK_DTL_MAX', '0000-00', '9999-99', '200', 'INT', '每项校验最多保留的问题明细行数') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('EXP_JDT_TRANSCODES', '0000-00', '9999-99', ',,PP03,MR03,MR11,MR12,', 'LIST', '计入费用池的凭证代码（OJDT.TransCode），逗号分隔、前后带逗号，“,,” 表示空代码；旧 0311 还含 YF01、MR02，新框架从源单据取，去掉以免重复（Q14）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_ACCT" ("Usage", "FromFc", "ToFc", "AcctCode", "Descr") VALUES ('LAB_EXP', '0000-00', '9999-99', '500102', '人工费用科目（0311）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_ACCT" ("Usage", "FromFc", "ToFc", "AcctCode", "Descr") VALUES ('MFG_EXP_PREFIX', '0000-00', '9999-99', '5101', '制造费用科目前缀（0311：LEFT(科目,4)=5101）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_LEVEL_OVR" ("ItemCode", "FromFc", "ToFc", "iLevel", "Reason") VALUES ('102000058', '0000-00', '9999-99', 2, '旧 MTC_CO_001GetItemLevel 写死') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_LEVEL_OVR" ("ItemCode", "FromFc", "ToFc", "iLevel", "Reason") VALUES ('102000762', '0000-00', '9999-99', 2, '旧 MTC_CO_001GetItemLevel 写死') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_LEVEL_OVR" ("ItemCode", "FromFc", "ToFc", "iLevel", "Reason") VALUES ('FH1401101', '0000-00', '9999-99', 3, '旧 MTC_CO_001GetItemLevel 写死') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_LEVEL_OVR" ("ItemCode", "FromFc", "ToFc", "iLevel", "Reason") VALUES ('FH1403501', '0000-00', '9999-99', 3, '旧 MTC_CO_001GetItemLevel 写死') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('CLOSE_DIF_POOL', '0000-00', '9999-99', 'MFG', 'STR', '关单差异全部进这个费用池（Q10 用户确认：固定一个车间）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-18', 'PRE', 180, '费用池配置有效', '正好一个默认池；CLOSE_DIF_POOL 和 C_POOL_SRC / C_POOL_TGT 引用的池都存在；同一产品只属于一个池（Q22）；MatchBy 只能是 GRP / GRPTYPE（Q17）；B1 @MTC_CA_POOL / @MTC_CA_PARAM（没有时旧 @MTC_CA_EXPSET）同步没有出错（2026-10-28 起含保存校验视图 MTC_CA_V_B1CFG_ISSUES 的全部问题：账期格式、起止顺序、账期段重叠、取值类型等），成本中心在 OPRC 中存在且本期只有一条，匹配的物料组 / 车间类别在 OITB 中存在（2026-10-14）', 'Y', 'S6') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-19', 'PRE', 190, '订单本期净入库为负', '完工退回多于入库的生产订单不分摊制造费用和人工（Q20）', 'N', 'S6') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-20', 'PRE', 200, '发票不基于收货', '本期库存物料 / 委外加工费的应付发票、贷项行不基于收货或退货：PUR2/PUR3 会冲回其系统分录却没有暂估可冲（Q24，正常不会出现）', 'N', 'S12') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-21', 'PRE', 210, '委外发票差异找不到产品', '委外加工费发票的“发票 − 暂估”差额，发票行 U_ItemCode 为空或无效，差额进不了产品成本（旧 6101_1 静默丢掉）', 'N', 'S4') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-22', 'PRE', 220, '暂估变动没有库存记录', '本期材料收货、退货、发票差额在计价仓库没有 OIVL 记录：PUR1/PUR2 记了存货科目，物料成本却不含（Q29）', 'N', 'S11') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-23', 'PRE', 230, '需要维护期初成本价的物料', '本期有要按单价计价的变动（出库、其他入库、盘点、无原单退货等），计算前却没有任何价格来源（无期初结存金额、无采购 / 完工 / 形态转换入库、无维护价）；区分首次出现和以前出现过，给出建议价（以前最近一期单价，或最近采购价）。只列清单，不写 @MTC_COST_QCPRICE，在 B1 维护后重新检查（用户 2026-10-13）', 'N', 'S1') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-24', 'PRE', 240, '工单类型不能为空', '本期涉及的生产 / 委外 / 返工订单 U_OrdType 为空：分不到制造费用和人工，在产品对账（POST-06 / POST-13）也归不到对应科目（用户 2026-10-14）', 'Y', 'S6') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-25', 'PRE', 250, '其他收发货科目与库存交易事务配置不一致', '其他收货 / 发货行上的科目与库存交易事务配置（@U_CITRN1：业务类型 + 部门 + 物料组 → 科目）不一致，或配置中没有这个组合。例：210 其他辅助领用应记 5101 制造费用，记成 500101 时 YF01 借生产成本却没有订单承接，生产在产品对账对不上（POST-13）。范围见参数 ACCT_CHECK_BUSITYPES（用户 2026-10-15）', 'Y', 'S7') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('ACCT_CHECK_BUSITYPES', '0000-00', '9999-99', ',210,', 'LIST', 'PRE-25：要核对单据科目与库存交易事务配置（@U_CITRN1）的业务类型（@U_CIOTRN.Code），默认只查 210 其他辅助领用（用户 2026-10-15）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('PRE08_EXCL_WHS', '0000-00', '9999-99', ',', 'LIST', 'PRE-08：不计价仓库中这些仓库（OWHS.WhsCode，逗号分隔）的采购、订单领料和完工不报；只影响警告，不影响计算（用户 2026-10-29）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-26', 'PRE', 260, '应收发票 / 贷项不基于交货 / 退货', '本期应收发票的库存物料行不基于交货（直接开票出库、预留发票），或应收贷项的库存物料行不基于退货：发出商品和 DN03 只认基于交货 / 退货的开票，这类行的销售成本结转不了（用户 2026-10-15：不会出现，出现就阻断）', 'Y', 'S10') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-27', 'PRE', 270, '销售单据没有客户类型', '本期交货 / 退货 / 应收发票 / 贷项，以及截至期末仍未开票的交货 / 独立退货，销售订单类型（U_SalOrdType）在 @MTC_SALORDTYPE 中没有或客户类型不是国内客户 / 国外客户：DN03 取不到 6401 科目，AR03/AR04 不计提，样品 DN02/DN04 不生成（用户 2026-10-15 阻断）', 'Y', 'S12') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-28', 'PRE', 280, 'B1 计算参数缺项', '参数目录 MTC_CA_C_PARAM_DEF 中的参数，B1 @MTC_CA_PARAM 没有适用于本账期的行：不阻断时会静默沿用新框架种子值。按 B1 原样快照 MTC_CA_C_PARAM_B1（P05 同步时刷新）判断，只看有没有行，取值格式由 PRE-18 管（用户 2026-11-01 阻断，为保证准确）', 'Y', 'S6') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-29', 'PRE', 290, '已生成凭单账期有未进结果的重估单', '日期在已生成凭单账期内、未取消的 MRV1 重估单，不在生成凭单所用运行的快照里（生成凭单之后才建的单）：那个账期不能再正式计算，后面账期按日期也不会读它，金额会被漏掉。只警告，不阻断（用户 2026-11-04）', 'N', 'S13') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('TB_EXTRA_ACCTS', '0000-00', '9999-99', ',', 'LIST', '执行台“科目余额表”：在默认范围（物料组存货科目、MTC_CA_C_ACCT 中的全部科目、5101 制造费用）之外再列出的科目或科目前缀，如 ,6602,1122,（用户 2026-10-15）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('QCP_PRICED_IN', '0000-00', '9999-99', ',I01,I03,I05,I07,I08,I09,I90,', 'LIST', 'PRE-23：数量为正时算作价格来源的入库交易类型（采购、生产 / 返工 / 委外完工、形态转换入库、期初生产入库）；这些行本身也不需要维护价') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('WW_WORTYPES', '0000-00', '9999-99', ',50,', 'LIST', '委外工单的订单类型（U_OrdType）：在产品记 WW_MAT（140801），完工 WW03、关单 JZ03，不分摊制造费用和人工（PRE-17/19 不查）；改了要同步改费用池分摊范围的订单类型（2026-10-27 由代码固定值改为参数）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('REWORK_WORTYPES', '0000-00', '9999-99', ',30,', 'LIST', '返工单的订单类型：期初承接取旧框架料工费比例时跳过（领料和产出是同一物料）（2026-10-27 由代码固定值改为参数）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('TRIAL_WORTYPES', '0000-00', '9999-99', ',40,', 'LIST', 'PRE-09：试打订单的订单类型（2026-10-27 由代码固定值改为参数）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('TRIAL_ISSUE_BUSITYPES', '0000-00', '9999-99', ',307,305,', 'LIST', 'PRE-09：试打订单允许的领料业务类型（@U_CIOTRN.Code，默认 307 试打领用、305 生产报废）（2026-10-27 由代码固定值改为参数）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('CONV_IN_BUSITYPE', '0000-00', '9999-99', '204', 'STR', '形态转换转入的业务类型（@U_CIOTRN.Code，I05）：P20_LINE 按行上 U_BaseType / U_BaseEntry / U_BaseLineGrpNum 配对，不关联订单；PRE-03 查一对一（2026-10-27 由代码固定值改为参数）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('CONV_OUT_BUSITYPE', '0000-00', '9999-99', '205', 'STR', '形态转换转出的业务类型（@U_CIOTRN.Code，O05），用法同 CONV_IN_BUSITYPE（2026-10-27 由代码固定值改为参数）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('RETURN_BUSITYPES', '0000-00', '9999-99', ',304,', 'LIST', '生产退料的业务类型：带订单的退料按该订单该材料的平均领料单价（RTN304 / RTN-01）（2026-10-27 由代码固定值改为参数）；收货单上用领料类业务类型（302、308、309 等）的行不用列在这里，自动按退料处理（用户确认 2026-10-30）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('SAMPLE_SALTYPES', '0000-00', '9999-99', ',样品销售,', 'LIST', '样品销售：@MTC_SALORDTYPE.U_BusiType 为这些值的交货 / 退货走 DN02 / DN04（不结转 DN03、不计提 AR03 / AR04）（2026-10-27 由代码固定值改为参数）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('CUST_DOM', '0000-00', '9999-99', '国内客户', 'STR', '国内客户的客户类型（@MTC_SALORDTYPE.U_CustType）：DN03 / AR03 记 COGS_DOM，样品 DN02；PRE-27、POST-12 只认 CUST_DOM / CUST_EXP（2026-10-27 由代码固定值改为参数）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('CUST_EXP', '0000-00', '9999-99', '国外客户', 'STR', '国外客户的客户类型（@MTC_SALORDTYPE.U_CustType）：DN03 / AR04 记 COGS_EXP，样品 DN04（销项税按成本 × SAMPLE_EXPORT_FACTOR）（2026-10-27 由代码固定值改为参数）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_RULE" ("RuleId", "Scene", "Title", "Descr", "Basis") VALUES ('FIX-01', 'S11', '固定来源金额', '采购收货 / 退货（U_InitPrice 优先）、应付发票 / 贷项差额（没有基于收货的取发票行金额，#14）、库存重估 I11：按来源金额', '读代码') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_RULE" ("RuleId", "Scene", "Title", "Descr", "Basis") VALUES ('WAVG-01', 'S1', '全月一次加权', '物料单价 =（期初 + 计价入库）÷（期初数量 + 计价入库数量），四项分别算；领料、销售出库、其他出入库、盘点、形态转换出库按此价', '读代码') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_RULE" ("RuleId", "Scene", "Title", "Descr", "Basis") VALUES ('RVL-01', 'S13', '重估只调整结存', 'U_CalType=InvntCost 的重估计入期末金额，不参与当期加权单价', '读代码') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_RULE" ("RuleId", "Scene", "Title", "Descr", "Basis") VALUES ('CNL-01', 'S10', '取消单', '交货 / 退货的取消单：原单在本期且为固定价的按原单单位成本反向；否则按本期加权价（原单在本期按加权价时与原单同价相抵）', '建议') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_RULE" ("RuleId", "Scene", "Title", "Descr", "Basis") VALUES ('B1-01', 'S17', '没有订单的期初生产入库', 'I90 没有关联订单时取 B1 金额', '建议') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_RULE" ("RuleId", "Scene", "Title", "Descr", "Basis") VALUES ('SRT-02', 'S10', '退货找不到原交货成本', '原交货不在新框架结果和旧 0302 中时按本期加权价，并在 POST-05 报出', '建议') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_RULE" ("RuleId", "Scene", "Title", "Descr", "Basis") VALUES ('SRT-03', 'S10', '无原单退货没有维护价', '没有原交货、也没有期初维护价的销售退货按本期加权价，PRE-04 警告', '用户确认') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-07', 'POST', 170, '物料异常标记', '负库存、用了维护价或期初单价兜底、无价、没有任何价格来源时按 0 成本入库（2026-10-29）、期末数量为 0 但金额不为 0 且超过尾差结转上限 TAIL_MAX（以内的由 TAIL-01 结转）', 'Y', 'S1') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-14', 'POST', 175, '物料成本异常', '计算后逐物料检查单价、数量、金额：① 小尾差已结转（TAIL-01）② 挤进出库行的尾差绝对值 ≥ TAIL_WARN ③ 期末数量 0 金额不为 0 ④ 负库存、有数量无金额、金额为负 ⑤ 期末单价偏离本期加权单价 ⑥ 本期加权单价比期初单价波动超过 PRICE_JUMP_PCT 且影响金额超过 PRICE_JUMP_AMT ⑦ 有数量无金额的单据行（用户 2026-10-14）', 'Y', 'S16') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-05', 'POST', 150, '配对金额', 'I05 = −O05；退货、取消单按原单成本；找不到原单按加权价兜底的行', 'Y', 'S3') WITH PRIMARY KEY
@@
-- 数据字典：快照表（S 层）和配置表的数据来源（用户 2026-10-14，执行台“说明书 → 表与字段”显示、可搜索）
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_S_ITEM', 'S', 'P20_ITEM：OITM 物料、OITB 物料组（U_ItemGrpType 车间类别）、OITT / ITT1 当前 BOM（算层级），MTC_CA_C_LEVEL_OVR 层级覆盖') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_S_LINE', 'S', 'P20_LINE：OIVL 库存记录（计价仓库 OWHS.U_IsCost=Y），交易类型取 MTC_VIEW_Document + @U_CIOTRN（59/60 的 U_TrsName）+ @MTC_COST_IOTYPE；采购收货 / 退货 / 发票 OPDN·PDN1、ORPD·RPD1、OPCH·PCH1、ORPC·RPC1；销售退货 RDN1；库存重估 @MTC_OMRV / @MTC_OMRV1；P20_AP 用 S_AP_MOVE 覆盖材料暂估金额') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_S_ORDER', 'S', 'P20_ORDER：OWOR 生产 / 委外订单（U_OrdType 工单类型）、@MTC_OWOR 返工单（U_OrdType、U_ItemCode、U_PlannedQty）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_S_ORDER_LINE', 'S', 'P20_ORDER：WOR1 生产订单行、@MTC_WOR1 返工单行（计划用料）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_S_EXP', 'S', 'P20_EXP：OJDT / JDT1 已过账凭证（人工科目 LAB_EXP、制造费用科目 MFG_EXP_PREFIX 开头，凭证代码在 EXP_JDT_TRANSCODES；取值见 B1 @MTC_CA_PARAM），@MTC_OMRV / @MTC_OMRV1 库存重估，OWOR / @MTC_OWOR 找订单') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_S_SUBFEE', 'S', 'P20_SUBFEE：委外加工费收货 OPDN / PDN1（U_BaseType / U_BaseEntry 指向生产收货 IGN1，U_OWORNum 找 OWOR）、退货 ORPD / RPD1，@MTC_OMRV / @MTC_OMRV1 中 U_BaseType=ProWW 的重估行，@MTC_OWOR 返工单') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_S_AP_MOVE', 'S', 'P20_AP：采购收货 OPDN / PDN1、采购退货 ORPD / RPD1、应付发票 OPCH / PCH1、应付贷项 ORPC / RPC1（暂估价 U_InitPrice / U_IsPrice / Price），OITM 判断库存物料，@MTC_COST_IOTYPE') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_S_HOURS', 'S', 'P20_MISC：B1 生产工时 @MTC_COST_TIME（表头 U_FcCode 账期、Canceled）+ @MTC_COST_TIME1（行 U_ItemCode 物料、U_Time 单位工时）；同一物料多行取最大值（PRE-13 报出）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_S_QCPRICE', 'S', 'P20_MISC：B1 期初单价维护 @MTC_COST_QCPRICE（表头 U_FcCode）+ @MTC_COST_QCPRICE1（行 U_ItemCode、U_Price）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_S_OPEN', 'S', 'P20_OPEN：上期是承接账期时取 MTC_CA_BOOT_ITEM（旧框架 0301 期末，P_BOOTSTRAP 写入，料工费按 BOOT_RATIO 拆分）；否则取上期最近一次成功正式运行的 R_ITEM 期末') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_S_ORDER_OPEN', 'S', 'P20_OPEN：上期是承接账期时取 MTC_CA_BOOT_ORDER_MAT（旧框架 CO4011 / ZCP1，按领用材料的 BOOT_RATIO 拆分料工费）；否则取上期最近一次成功正式运行的 R_ORDER_MAT 累计数（未关闭订单）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_C_POOL', 'C', 'P05：B1 @MTC_CA_POOL（Code、Name、U_IsDefault、U_Descr）有数据时每次运行前整表覆盖；没有时用种子值') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_C_POOL_SRC', 'C', 'P05：B1 @MTC_CA_POOL1（U_OcrCode、U_FromFc、U_ToFc）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_C_POOL_TGT', 'C', 'P05：B1 @MTC_CA_POOL2（U_MatchBy、U_MatchVal、U_WorTypes、U_FromFc、U_ToFc）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_C_ACCT', 'C', 'MFG_EXP_PREFIX / LAB_EXP 两行由 P05 从 B1 @MTC_CA_PARAM（没有时读旧 @MTC_CA_EXPSET1）同步（有数据时）；其余科目用种子值') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_C_PARAM', 'C', 'MTC_CA_C_PARAM_DEF 登记的参数由 P05 从 B1 @MTC_CA_PARAM（没有时读旧 @MTC_CA_EXPSET1）同步，B1 里出现的以 B1 为准；CLOSE_DIF_POOL 取 @MTC_CA_POOL.U_IsCloseDif=Y 的池（有数据时）；其余参数用种子值') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('JV_REV_TRANSCODES', '0000-00', '9999-99', ',AR03,AR04,', 'LIST', '生成 SAP 凭单时下月初自动冲销的凭证代码：凭单勾选冲销（OBTF.AutoStorno），冲销日期 = 下一账期第一天；同旧 COJZ_01/03 的 U_IsRev（用户 2026-10-19）') WITH PRIMARY KEY
@@
-- 参数目录（用户 2026-10-28：参数改在 B1 @MTC_CA_PARAM 平铺表格维护）。新增可在 B1 维护的参数时在这里加一行
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('MFG_EXP_PREFIX', 'ACCT', '费用归集', 110, '制造费用科目前缀', 'STR', NULL, '凭证里以它开头的科目计入制造费用，如 5101') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('LAB_EXP', 'ACCT', '费用归集', 120, '人工费用科目', 'STR', NULL, '科目代码，如 500102') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('EXP_JDT_TRANSCODES', 'PARAM', '费用归集', 130, '计入费用池的凭证代码', 'LIST', NULL, 'OJDT.TransCode，逗号分隔；“空”= 没有凭证代码的手工凭证。如 空,PP03,MR03,MR11,MR12') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('SUBFEE_ITEM', 'PARAM', '费用归集', 140, '委外加工费物料', 'STR', NULL, '物料代码，如 X0510001') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('START_FC', 'PARAM', '计算控制', 210, '新框架起始账期', 'FC', NULL, 'YYYY-MM。上线后不要改，会打乱期初承接') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('BOOTSTRAP_FC', 'PARAM', '计算控制', 220, '期初承接账期', 'FC', NULL, 'YYYY-MM，从旧框架该期结果取期初。上线后不要改') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('CONV_PRICE', 'PARAM', '计算控制', 230, '收敛标准：单价', 'DEC', NULL, '物料单价两轮之差的上限，如 0.000001；不清楚不要改') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('CONV_AMT', 'PARAM', '计算控制', 240, '收敛标准：金额', 'DEC', NULL, '费用池、关单差异两轮之差的上限（元），如 0.01；不清楚不要改') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('MAX_ITER', 'PARAM', '计算控制', 250, '最大迭代轮数', 'INT', NULL, '整数，超过仍不收敛则不写结果，如 50') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('ITER_TRACE_TOP', 'PARAM', '计算控制', 252, '迭代明细记录物料数', 'INT', NULL, '整数，每轮记录单价变化最大的前 N 个物料，排查不收敛用，如 30；0 = 不记') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('KEEP_NOCONV', 'PARAM', '计算控制', 254, '未收敛 / 出错时保留中间结果', 'STR', 'Y,N', 'Y = 未收敛或迭代及以后出错时，保留本次快照和最后一轮中间结果（可在执行台查看、导出排查），下次成功运行时自动删除；N = 删除') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('LEVEL_GUARD', 'PARAM', '计算控制', 260, '层级计算保护上限', 'INT', NULL, '整数，防循环引用，不是业务层数，如 30') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('QCP_PRICED_IN', 'PARAM', '计算控制', 270, 'PRE-23 价格来源入库类型', 'LIST', NULL, '交易类型逗号分隔，如 I01,I03,I05,I07,I08,I09,I90') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('LEGACY_INITPRICE_DATE', 'PARAM', '计算控制', 280, '按 U_InitPrice 取成本的截止日', 'DATE', NULL, 'YYYY-MM-DD，该日及以前的交货 / 退货按行上 U_InitPrice 取成本') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('TAIL_MAX', 'PARAM', '尾差与校验', 310, '零库存尾差结转上限', 'DEC', NULL, '元（含）：期末数量 0、金额在 ± 本值以内的结转 640101（JZ04），如 0.02') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('TAIL_WARN', 'PARAM', '尾差与校验', 320, '尾差报警下限', 'DEC', NULL, '元（含）：POST-14 挤进出库行的尾差绝对值达到本值才报，如 0.1') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('PRICE_JUMP_PCT', 'PARAM', '尾差与校验', 330, '价格波动报警比例', 'DEC', NULL, '%：POST-14 价格波动 / 期末单价偏离，如 30') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('PRICE_JUMP_AMT', 'PARAM', '尾差与校验', 340, '价格波动报警金额', 'DEC', NULL, '元：POST-14 价格波动的影响金额下限，如 100') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('CHECK_DTL_MAX', 'PARAM', '尾差与校验', 350, '每项校验保留明细行数', 'INT', NULL, '整数，如 200') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('ACCT_CHECK_BUSITYPES', 'PARAM', '尾差与校验', 360, 'PRE-25 核对科目的业务类型', 'LIST', NULL, '@U_CIOTRN.Code 逗号分隔，如 210') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('PRE08_EXCL_WHS', 'PARAM', '尾差与校验', 370, 'PRE-08 不报的不计价仓库', 'LIST', NULL, '仓库代码逗号分隔，可以为空，如 S300,WX01') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('COST_TRANSCODES', 'PARAM', '凭证与对账', 410, '成本模块生成的凭证代码', 'LIST', NULL, '凭证代码逗号分隔；要和代码实际生成的一致，不要随意增删') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('JV_REV_TRANSCODES', 'PARAM', '凭证与对账', 420, '凭单下月初自动冲销的凭证代码', 'LIST', NULL, '凭证代码逗号分隔，如 AR03,AR04') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('RECON_BLOCK_ON', 'PARAM', '凭证与对账', 430, '财务对账按哪列差额阻断', 'STR', 'CUR,END', 'CUR 本期差额（期初差额只列示）/ END 期末差额') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('RECON_COSTONLY_AREAS', 'PARAM', '凭证与对账', 440, '只比较成本凭证的对账项', 'LIST', NULL, '可选 STOCK、WIP_PROD、WW_MAT、WW_FEE、GOODS、AP，逗号分隔') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('PUR2_REV_ACCTS', 'PARAM', '凭证与对账', 450, 'PUR2 冲回发票凭证的科目', 'LIST', NULL, '科目或前 4 位，逗号分隔，如 1403,1405,1409,220202') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('PUR3_REV_ACCTS', 'PARAM', '凭证与对账', 460, 'PUR3 冲回发票凭证的科目', 'LIST', NULL, '科目或前 4 位，逗号分隔，如 140802') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('PUR_STDVAR_ACCTS', 'PARAM', '凭证与对账', 465, 'PUR 勾稽：标准成本差异科目（补充）', 'LIST', NULL, '除物料组的价格差异科目、差异科目外，B1 标准成本凭证还会用到的差异科目；POST-15 要求这些科目在采购单据上净额为 0。逗号分隔，可空') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('INITPRICE_NEW_FROM', 'PARAM', '凭证与对账', 466, '指定单价 U_InitPrice 报出起始日', 'DATE', NULL, 'YYYY-MM-DD；这天及以后的收货 / 退货用了 U_InitPrice 时 POST-15 报出，如 2026-01-01') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('POST_WARN_IDS', 'PARAM', '计算控制', 285, '只警告的计算后校验', 'LIST', NULL, '校验编号，逗号分隔，如 POST-15；不在这里的计算后校验一律阻断') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('TB_EXTRA_ACCTS', 'PARAM', '凭证与对账', 470, '科目余额表额外列出的科目', 'LIST', NULL, '科目或科目前缀，逗号分隔，可以为空，如 6602,1122') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('SAMPLE_VAT_RATE', 'PARAM', '凭证与对账', 480, '样品视同销售税率', 'DEC', NULL, '小数，如 0.13') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('SAMPLE_VAT_DIV', 'PARAM', '凭证与对账', 490, '国内样品销项税除数', 'DEC', NULL, '销项税 = 数量 × 平台价 ÷ 本值 × 税率，如 1.13') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('SAMPLE_EXPORT_FACTOR', 'PARAM', '凭证与对账', 500, '国外样品销项税成本倍数', 'DEC', NULL, '销项税 = 成本 × 本值 × 税率，如 1.5') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('WW_WORTYPES', 'PARAM', '业务口径', 510, '委外工单的订单类型', 'LIST', NULL, 'U_OrdType 逗号分隔，如 50；改了要同步改费用池分摊范围的订单类型') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('REWORK_WORTYPES', 'PARAM', '业务口径', 520, '返工单的订单类型', 'LIST', NULL, 'U_OrdType 逗号分隔，如 30') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('TRIAL_WORTYPES', 'PARAM', '业务口径', 530, '试打订单的订单类型', 'LIST', NULL, 'U_OrdType 逗号分隔，如 40') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('TRIAL_ISSUE_BUSITYPES', 'PARAM', '业务口径', 540, '试打允许的领料业务类型', 'LIST', NULL, '@U_CIOTRN.Code 逗号分隔，如 307,305') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('CONV_IN_BUSITYPE', 'PARAM', '业务口径', 550, '形态转换转入业务类型', 'STR', NULL, '@U_CIOTRN.Code，如 204（I05）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('CONV_OUT_BUSITYPE', 'PARAM', '业务口径', 560, '形态转换转出业务类型', 'STR', NULL, '@U_CIOTRN.Code，如 205（O05）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('RETURN_BUSITYPES', 'PARAM', '业务口径', 570, '生产退料业务类型', 'LIST', NULL, '@U_CIOTRN.Code 逗号分隔，如 304；收货单上用领料类业务类型（302、308、309 等）的行自动按退料处理，不用填') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('SAMPLE_SALTYPES', 'PARAM', '业务口径', 580, '样品销售的业务类型', 'LIST', NULL, '@MTC_SALORDTYPE.U_BusiType 逗号分隔，如 样品销售') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('CUST_DOM', 'PARAM', '业务口径', 590, '国内客户的客户类型', 'STR', NULL, '@MTC_SALORDTYPE.U_CustType，如 国内客户') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('CUST_EXP', 'PARAM', '业务口径', 600, '国外客户的客户类型', 'STR', NULL, '@MTC_SALORDTYPE.U_CustType，如 国外客户') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_C_PARAM_DEF', 'C', '种子数据（04_seed.sql）；B1 @MTC_CA_PARAM 的 Name / U_Category / U_DataType / U_Hint 由 sl_import_costcfg.py --param 按它写入') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_C_PARAM_B1', 'C', 'B1 @MTC_CA_PARAM 的原样快照：P05 调 MTC_CA_P_PARAM_B1_SNAP 整表刷新，B1 保存时 MTC_CA_P_B1CFG_TN 逐行刷新；用来判断锁定（U_Locked = Y）的参数有没有被改，计算不读') WITH PRIMARY KEY
