# 新成本框架 SQL

按文件序号部署到与 FH100 结构相同的库（对象不带 schema 前缀，建在当前 schema）。语句之间用单独一行 `@@` 分隔：

```
# 10_run_entry 依赖 12–17，按 01…09、11…19、10 的顺序执行；最后同步数据字典
python3 新框架/tools/hana_exec.py -f 新框架/sql/0[1-9]_*.sql 新框架/sql/1[1-9]_*.sql 新框架/sql/10_run_entry.sql
python3 新框架/tools/hana_exec.py 'CALL "MTC_CA_P_META_SYNC"()'
```

| 文件 | 内容 | 期 |
|---|---|---|
| 01_run_tables | 运行日志、步骤、迭代、指标快照 | 1 |
| 02_config_meta_tables | 参数、规则、科目、层级覆盖、计价仓库例外、校验登记、模拟场景、AI 工具、数据字典 | 1 |
| 03_run_procs | 步骤日志、运行开始 / 结束、按运行键清理、数据字典同步 | 1 |
| 04_seed | 配置初始数据（可重复执行） | 1 |
| 05_config_pool | 费用池配置（设计稿 4.4），含初始值 | 1 |
| 06_snapshot_tables | 计价仓库视图、快照表 S_*、校验结果 R_CHECK(_DTL)、期初承接 BOOT_* | 1 |
| 07_snapshot_procs | P20 快照（物料层级、库存变动、委外加工费、订单、费用来源、工时与维护价、期初） | 1 |
| 08_precheck | P10 计算前检查 PRE-01…27（只读）；发出商品函数 F_GOODS_OPEN / F_GOODS_MOVE | 1 |
| 09_bootstrap | 期初承接 `MTC_CA_P_BOOTSTRAP('2026-08')` 和核对视图 | 1 |
| 10_run_entry | 入口 `MTC_CA_P_RUN`（P00 → P20 → P10 → P30 →（模拟）P31 → P40 → P50 → P60 → P65 → P71 → P73 → P74 → P70 → P75 → P80） | 1–4 |
| 11_result_tables | 结果表 R_LINE / R_ITEM / R_ORDER / R_ORDER_MAT / R_POOL / R_ALLOC / R_PAIR / R_CMP，进销存视图 | 2 |
| 12_p30_init | P30 定价类别、固定价格、退货 / 取消单 / 形态转换配对、物料 / 订单 / 费用池初始化 | 2 |
| 13_p40_iter | P40 迭代：P41 加权价行定价、P42 费用池、P43 分摊、P45 逐级结转、收敛判断 | 2 |
| 14_p50_p60_p65 | P50 定稿与尾差、P60 计算后校验与指标快照、P65 新旧比对 | 2 |
| 15_p70_tables | 凭证 R_JDT / R_JDT_SRC、发出商品 R_GOODS_OUT（期初 R_GOODS_OUT_BEG）、交货成本 R_DNCOST、应付暂估 R_AP_ACCR，凭证配置 | 3 |
| 16_p70_jdt | P71 发出商品与交货成本、P73 应付暂估、P74 应付暂估凭证 PUR1–PUR5、P70 凭证（0801 各段 + JZ01/JZ03）、P75 凭证与暂估校验 | 3 |
| 17_p90_tools | `MTC_CA_P_PRECHECK` 只做计算前检查、P31 模拟场景假设、`MTC_CA_P_SCEN_*` 场景维护、工具登记 | 4 |
| 19_jv | 生成 SAP 日记账凭单：计划 F_JV_PLAN、P_JV_BEGIN / LOG / FINISH / UNDO（凭单由执行台服务器模式经 Service Layer 建，设计稿 8.6） | 5 |
| 19_ww_hist | 历史委外差异转出：P_WW_HIST_LOAD 载入清单、P_WW_HIST_SET 选账期、P_WW_HIST_MARK 标记手工转出（设计稿 8.9） | 5 |
| 18_meta_comments | 字段说明（由 `新框架/tools/build_meta_comments.py` 从建表注释生成，不要手改） | 4 |
| 99_drop_all | 删除全部 `MTC_CA_*` 对象（测试库重新部署用） | — |

已有对象时：表要先删（`99_drop_all`）或手工 ALTER；视图、过程、函数是 `CREATE OR REPLACE`，可直接重跑。

## 第一次在新库上验证

```sql
CALL "MTC_CA_P_META_SYNC"();
CALL "MTC_CA_P_BOOTSTRAP"('2026-08');                 -- 需要旧框架 2026-08 已跑完
SELECT * FROM "MTC_CA_V_BOOT_CHECK";                    -- 只看行数，明细不出本地
CALL "MTC_CA_P_RUN"('2026-09', 'F', '', 'manager', 'USER');
SELECT "Status", "Msg" FROM "MTC_CA_RUN" ORDER BY "RunId" DESC LIMIT 1;
SELECT "StepCode", "Status", "RowCnt", "Msg" FROM "MTC_CA_RUN_STEP" WHERE "RunId" = <RunId> ORDER BY "StepNo";
SELECT "CheckId", "Result", "IssueCnt" FROM "MTC_CA_R_CHECK" WHERE "RunId" = <RunId> ORDER BY "CheckId";
SELECT "Iter", "MaxPriceDelta", "PoolDelta", "CloseDifDelta", "UnconvItems" FROM "MTC_CA_RUN_ITER" WHERE "RunId" = <RunId>;
SELECT "Kind", COUNT(*) FROM "MTC_CA_R_CMP" WHERE "RunId" = <RunId> GROUP BY "Kind";   -- 新旧差异条数
SELECT "TransCode", SUM("Debit"), SUM("Credit") FROM "MTC_CA_R_JDT" WHERE "RunId" = <RunId> GROUP BY "TransCode";  -- 凭证是否平衡（金额只在本地看）
```

按数据边界约定，反馈时只需给出步骤状态、行数和哪些检查未通过；`MTC_CA_R_CHECK_DTL` 的明细在本地看。

## 2026-10-13 补丁：运行进度实时显示

`03` 新增 `MTC_CA_P_LOG_NOTE(RunId, Msg)`：自治事务更新本次运行中正在执行那一步的 `MTC_CA_RUN_STEP.Msg`。`08` 的 `MTC_CA_P_CHECK_PUT` 每做完一项校验写一次（“已完成 N 项校验，刚完成 PRE-07 …：通过 / k 条问题”，P10、P60、P75 都适用）；`13` 的 P40 写当前第几轮、P41/P42/P43、逐级结转第几级，`MTC_CA_RUN_ITER` 改为自治提交（运行中可见，出错回滚后也保留）。已部署的库依次执行 `03_run_procs.sql`、`08_precheck.sql`、`13_p40_iter.sql`。已在 TEST20261012 编译并跑过只做检查和正式计算。

## 2026-10-14 补丁：费用配置改在 B1 维护、数据字典含 B1 表

用户决定费用池和归集参数在 SAP B1 里维护（表结构见 `新框架/B1自定义表_费用配置.md`）。`07` 新增 P05 `MTC_CA_P05_CFG_SYNC`（P20_SNAPSHOT 开头调用，B1 表没建或没数据时沿用 `C_*`），`08` 的 PRE-18 增加：B1 同步出错、成本中心不在 OPRC 或本期多条、匹配的物料组 / 车间类别不在 OITB。`02` 的 `MTC_CA_M_TABLE` 加 `Source`（快照表的 B1 来源），`03` 的 `MTC_CA_P_META_SYNC` 把 OUTB 中全部 B1 自定义表和字段说明（CUFD）收进数据字典（Layer = B1）。已部署的库依次执行 `patch_20261014_b1cfg.sql`、`03_run_procs.sql`、`07_snapshot_procs.sql`、`08_precheck.sql`、`18_meta_comments.sql`，再 `CALL "MTC_CA_P_META_SYNC"()`。另有 `patch_20261014_pre24.sql`（PRE-24 工单类型不能为空）。另有 `patch_20261014_ordtc.sql`：只有工单交易 I03/O03/I07/O07/I08/O08/I09/O09 关联订单（P20_LINE），其他交易（如 210 其他辅助领用 O04）填了订单号也不计入订单成本、不触发 PRE-10；PRE-06 同口径（用户 2026-10-14）。执行本文件后再执行 `07_snapshot_procs.sql`、`08_precheck.sql`，尚未部署（测试库连不上）。另有 `patch_20261014_tailwarn.sql`：POST-14 ② 尾差偏大改用参数 TAIL_WARN（0.1，绝对值 ≥ 才报），执行后再执行 `14_p50_p60_p65.sql`，同样未部署。已在 TEST20261012 部署，用临时建的同结构表验证过同步（含全角逗号、“空”凭证代码）和出错时阻断，验证后已删除临时表、恢复种子值。

## 2026-10-13 补丁：财务对账两个口径

已部署的库依次执行 `16_p70_jdt.sql`（新函数 `MTC_CA_F_RECON_LEDGER` / `MTC_CA_F_RECON` / `MTC_CA_F_RECON_STATUS` 和 P75）、`14_p50_p60_p65.sql`（P60 去掉 POST-06）、`patch_20261013_recon.sql`（检查项说明，新增 POST-13）。离线写的，还没编译。

```sql
SELECT * FROM "MTC_CA_F_RECON_STATUS"(<RunId>);
SELECT "Area", "AcctCode", COUNT(*) FROM "MTC_CA_F_RECON"(<RunId>) WHERE ABS("Diff") > 0.01 GROUP BY "Area", "AcctCode";  -- 金额只在本地看
```

## 2026-10-14 补丁：计算后校验一律阻断

POST 阶段（POST-01…14、BOOT-01）不通过一律阻断，没有警告（用户 2026-10-14）。`08_precheck.sql` 的 `MTC_CA_P_CHECK_PUT` 对 POST 阶段强制 IsBlock='Y'；`10_run_entry.sql` 中 P60 / P75 有未通过项时步骤状态记 BLOCKED，运行状态仍为 OK（结果保留供排查），运行说明写“计算后校验 N 项未通过（阻断）：POST-…，处理前不能过账”。已部署的库依次执行 `08_precheck.sql`、`10_run_entry.sql`、`patch_20261014_postblock.sql`；如同时部署对账补丁，`patch_20261014_recon2.sql` 已同步为 IsBlock='Y'。离线写的，还没编译。

## 2026-10-14 补丁：财务对账按凭证代码合并两个口径

底稿中本期已过账（或已在本期未清凭单）的凭证代码不再加，差额 = 总账 + 未清凭单 + 未过账底稿 − 业务（`MTC_CA_F_RECON.Diff`），校验明细列出凭证代码和中文名。已部署的库依次执行 `16_p70_jdt.sql`、`patch_20261014_recon2.sql`，然后在执行台“财务对账”点“重新对账”（或重新计算，P75 会重写 POST-06/09/10/11/13）。离线写的，还没编译。

## 2026-10-13 补丁：PRE-23 需要维护期初成本价的物料

已部署的库：执行 `patch_20261013_qcp.sql`（建表 `MTC_CA_R_QCP_NEED` + 检查项和参数），再依次执行 `12_p30_init.sql`（新过程 `MTC_CA_P10_QCP`）、`17_p90_tools.sql`、`10_run_entry.sql`，最后 `CALL "MTC_CA_P_META_SYNC"()`。离线写的，还没编译。

## 2026-10-15 补丁：发出商品尾差、PRE-26 / PRE-27

分次开票的尾差在交货 / 退货行全部消耗完时由 DN03 清掉（`MTC_CA_F_GOODS_MOVE`、`MTC_CA_R_GOODS_MOVE`，P71 / P70 改写）；PRE-26 应收发票 / 贷项不基于交货 / 退货、PRE-27 销售单据没有客户类型（都阻断）。`MTC_CA_F_GOODS_OPEN` 从 16 移到 08（PRE-27 要用）。已部署的库依次执行 `patch_20261015_goods.sql`、`08_precheck.sql`、`16_p70_jdt.sql`、`18_meta_comments.sql`，再 `CALL "MTC_CA_P_META_SYNC"()`。离线写的，还没编译。

## 2026-10-15 补丁：科目余额表

执行台“财务 → 科目余额表”：成本相关科目的期初、本期借贷、期末（总账已过账），未过账（截至期末的未清凭单 + 本次底稿，已过账的底稿凭证代码不再加），含未过账期末；点科目看按来源 × 凭证代码的汇总和逐笔明细账（带累计余额），点总账分录看整张凭证，点底稿分录看业务来源。`16` 新增 `MTC_CA_F_TB_ACCT`、`MTC_CA_F_TB_LINE`。已部署的库依次执行 `patch_20261015_tb.sql`、`16_p70_jdt.sql`。离线写的，还没编译（OBTF.Memo、BTF1.Line_ID / LineMemo / ProfitCode 按 OJDT / JDT1 同结构写的，未在库上核对）。

## 2026-10-15 补丁：发出商品 140601 期末 = 期初 = 0

财务对账 140601 业务端期初、期末都是 0，财务端含 AR03 / AR04 和 B1 自动冲销（不再剔除）；`F_RECON_LEDGER` 加 `Part`，POST-10 列出 ① 冲销上月计提 ② 发货 ③ 样品转出 ④ 发票 ⑤ 本月计提，核对 ① = 上期末未开票、⑤ = 本期末未开票；`F_TB_LINE` 加 `RevOf`。已部署的库依次执行 `patch_20261015_goods2.sql`、`16_p70_jdt.sql`。冲销靠 OJDT.StornoToTr 识别，离线写的，还没编译。

## 尚未验证

2026-10-12 在测试库 TEST20261012（与 FH100 结构相同，已部署旧成本模块和配置数据，**没有业务数据**）上：01–16 全部编译通过，对象全部有效；编译时改了两处——12 的费用池 `GROUP BY IFNULL(…, :变量)`（HANA 不接受，改成子查询），13 的 `FOR lv IN 0 .. :maxLv`（报 identifier must be declared，改成 WHILE）。空库上 `META_SYNC`、`BOOTSTRAP('2026-08')`、`P_RUN('2026-09','F')` 都能跑完：P00…P80 全部 OK，只有 PRE-16（没有期初）按设计阻断，临时把它设为不阻断后整条流水线走完、迭代 1 轮（测完已改回阻断）。

所以下面这些只验证了语法和空数据下的流程，计算逻辑还没有被数据验证过。重点关注：
- `UPDATE … FROM … JOIN` 写法（沿用旧过程的习惯）、`FOR … IN 0 .. :n` 循环、表变量参数。
- 第 2 期的计算逻辑需要用 2026-09 的新旧比对逐项归因后才能确认。
- `MTC_VIEW_Document` 的列名（导出的 DDL 里第一段 UNION 没有别名，代码按旧 0303 使用的列名 BaseType / BaseEntry / BaseRef / BaseLine 引用）。
- 表类型参数 `MTC_CA_P_CHECK_PUT(… IN dtl TABLE(…))` 与各检查结果的列类型兼容。
- `WOR1."ItemType"`、`OWOR."CardCode"` 等标准字段在该 B1 版本中存在。

### 2026-10-13 POST-05 明细写单据

POST-05 的明细原来只有运行内行号（LineId），看不出是什么单。改为 KeyCode = `ObjType-DocNum-LineNum`（与 PRE 检查一致），说明开头写单据类型中文名（销售交货 / 销售退货等）、取消单 / 已被取消、物料、交易类型。已部署的库执行 `14_p50_p60_p65.sql`（只改了 P60），重新计算后生效。已在 TEST20261012 编译通过。

财务对账 140601 期末差额扣除手工调整后应等于期初差额（用户 2026-10-17）：底稿是否“本期已过账 / 已在未清凭单”改为按凭证代码 × 科目判断，B1 自动冲销不算（2026-09 未清凭单有 AR03 / AR04 但没有 140601 分录，底稿的 140601 计提被当成重复丢掉，POST-10 ⑤ 为 0）；`RECON_COSTONLY_AREAS` 默认加 GOODS，140601 本期非成本凭证分录（手工调整）单独列出、不算差异，B1 自动冲销成本凭证仍参与对账；POST-10 说明里列出手工调整金额。已部署的库依次执行 `patch_20261017_goods3.sql`、`16_p70_jdt.sql`，B1 `@MTC_CA_EXPSET` 若维护了该参数也要加 GOODS。离线写的，还没编译。

POST-09 存货科目差额（2026-09 RunId 28：140301 0.05、140501 −752.32、140901 −467.03，期初都平）= 底稿 MR02 中 @MTC_OMRV 188（MRV2，旧 0501 写的“期末 0 数量有金额差异”）的存货分录：P70 的 MR02 和 P20_EXP 费用池都读 MRV1 + MRV2（照搬旧 0801 / 0311），P20_LINE 业务端只收 MRV1。MRV2 由新框架 TAIL-01 / JZ04 替代，改为 MR02、P20_EXP 都只读 MRV1（2026-10-17）；费用池少了这张单的 510197，分摊结果会变。已部署的库执行 `07_snapshot_procs.sql`、`16_p70_jdt.sql`，再重新计算。离线改的，还没编译。

委外加工费退货挂到已关闭订单（Q35，用户 2026-10-17）：2026-09 有 11 张以前账期就已关闭的委外订单本期有加工费采购退货（合计 −2,462.31），负的加工费一直留在订单上，POST-06 每期报。改为：P30 把截至期末已关闭的订单（不只是本期关闭的）`R_ORDER.ClosedInFc` 记为 Y，期末在产品全部转关单差异，进 CLOSE_DIF_POOL 分摊、生成 JZ03（加工费部分借 / 贷 140802）；POST-06 只按 140801 / 140802 的差额阻断，加工费留在未关闭订单上的只在说明里列示。已部署的库依次执行 `patch_20261017_ww_closed.sql`、`07_snapshot_procs.sql`、`12_p30_init.sql`、`16_p70_jdt.sql`、`18_meta_comments.sql`（含上面 MRV2 的修改），再重新计算。离线改的，还没编译。

140801 本期手工调整（用户 2026-10-17）：2026-09 POST-06 本期差额 −253,269.53 全部是凭证代码为空的总账分录，用户确认是手工调整。`RECON_COSTONLY_AREAS` 默认改为 `WIP_PROD,GOODS,WW_MAT`，140801 本期非成本凭证分录单独列出（“不参与对账的分录”）、不算差异；期初仍按科目余额全额比较（期初差额 1,608,654.36 只列示）。随 `patch_20261017_ww_closed.sql` 一起执行；B1 `@MTC_CA_EXPSET` 若维护了该参数也要加 WW_MAT。

### 2026-10-18 物料料工费占比落表

用户要求收发存汇总的料工费占比保存到静态表：`MTC_CA_R_ITEM` 加 16 列 `Rt<Open|In|Out|End><Mat|Lab|Mfg|Sub>`（期初、入库、出库、期末各自的材料 / 人工 / 制造 / 委外 ÷ 该项四项合计 × 100，保留 4 位，四项合计为 0 时为空），P50 定稿最后写入。物料组小计、合计的占比不落表，执行台按汇总金额现算（公式相同）。已部署的库依次执行 `patch_20261018_ratio.sql`（加列并回填已有运行）、`14_p50_p60_p65.sql`、`18_meta_comments.sql`，再 `CALL "MTC_CA_P_META_SYNC"()`；之后才能换新版执行台（`invSum` 读这些列）。离线写的，还没编译。

### 2026-10-19 账期状态控制

用户要求生成 SAP 凭单后不能再正式计算（Q36–Q40，设计稿 8.5）。新表 `MTC_CA_PERIOD` / `MTC_CA_PERIOD_LOG`，视图 `MTC_CA_V_PERIOD`，过程 `MTC_CA_P_PERIOD_GUARD`（正式计算、期初承接前检查）、`MTC_CA_P_PERIOD_SET`（改状态并记日志）；`P_RUN` 正式计算成功记 CALC，`P20_OPEN` 上期已生成凭单时取凭单所用的运行，`P_BOOTSTRAP` 起始账期已生成凭单时拒绝。已部署的库依次执行 `patch_20261019_period.sql`（建表，并把已有的最近一次成功正式运行补记为 CALC）、`03_run_procs.sql`、`07_snapshot_procs.sql`、`09_bootstrap.sql`、`10_run_entry.sql`、`18_meta_comments.sql`，再 `CALL "MTC_CA_P_META_SYNC"()`。执行台 `periodStatus` 读视图，没打补丁的库不显示状态。离线写的，还没编译。

### 2026-10-19 生成 SAP 凭单

执行台“生成凭单”页（服务器模式、管理权限）按凭证代码经 Service Layer 建 OBTF，结果记 `MTC_CA_JV`，全部成功后账期状态 POSTED（设计稿 8.6）。已部署的库依次执行 `patch_20261019_jv.sql`（建表）、`03_run_procs.sql`、`19_jv.sql`、`18_meta_comments.sql`，再 `CALL "MTC_CA_P_META_SYNC"()`。B1 前台要先加日记账分录表头字段 `MTC_CARunId`（数字 11）。离线写的，还没编译。

### 2026-10-19 计算后校验阻断项的人工确认

生成凭单时计算后校验有阻断项，管理权限可以在“生成凭单”页逐项确认并写理由，确认过的项不再阻断（Q45，设计稿 8.6）。新表 `MTC_CA_CHECK_ACK`，过程 `MTC_CA_P_CHECK_ACK` / `_UNACK`，`P_JV_BEGIN` 跳过已确认的项。已部署的库依次执行 `patch_20261019_ack.sql`、`19_jv.sql`、`18_meta_comments.sql`，再 `CALL "MTC_CA_P_META_SYNC"()`。离线写的，还没编译。

### 2026-10-27 业务口径参数化

代码里写死的业务口径改成 `MTC_CA_C_PARAM` 参数（也可在 B1 `@MTC_CA_EXPSET` 维护，见 `B1自定义表_费用配置.md`“业务口径”）：`WW_WORTYPES`（委外 50）、`REWORK_WORTYPES`（返工 30）、`TRIAL_WORTYPES`（试打 40）、`TRIAL_ISSUE_BUSITYPES`（307,305）、`CONV_IN_BUSITYPE` / `CONV_OUT_BUSITYPE`（形态转换 204 / 205）、`RETURN_BUSITYPES`（生产退料 304）、`SAMPLE_SALTYPES`（样品销售）、`CUST_DOM` / `CUST_EXP`（国内客户 / 国外客户）。默认值等于原来的固定值，参数缺失时过程内也按原值兜底，结果不变。涉及 P20_LINE、P10（PRE-03/09/17/19/27）、`F_GOODS_OPEN`、P_BOOTSTRAP、P30、P70、P71、`F_RECON`、P75。已部署的库依次执行 `patch_20261027_param.sql`、`07_snapshot_procs.sql`、`08_precheck.sql`、`09_bootstrap.sql`、`12_p30_init.sql`、`16_p70_jdt.sql`。执行台“取数 SQL”（`tools/console/srcsql/`）只读 B1 表，仍写着默认值，改参数后要手工同步。改前备份 `sql/_backup/*_20261027_before_param.sql`。离线改的，还没编译。

### 2026-10-28 计算参数改成 B1 平铺表格、保存时校验

用户决定计算参数在 B1 用平铺表格维护（`@MTC_CA_PARAM`，一行 = 一个参数的一段账期，见 `B1自定义表_费用配置.md` 第 2 节），保存时校验，执行台改成参数总览 + “检查 B1 配置”。`02` 新增参数目录 `MTC_CA_C_PARAM_DEF`（`04` 种子 38 个参数：分类、中文名、类型、可选值、填法）；`07` 的 P05 优先读 `@MTC_CA_PARAM`（没有时仍读旧 `@MTC_CA_EXPSET`），装了校验视图时按视图校验，费用池补账期格式和起止顺序检查，列表参数“空”只替换单独一项，运行记录 `Params` 的 JSON 转义反斜杠。已部署的库依次执行 `patch_20261028_param_ui.sql`、`07_snapshot_procs.sql`、`18_meta_comments.sql`，再 `CALL "MTC_CA_P_META_SYNC"()`。

### 2026-10-29 PRE-08 可排除仓库

用户反馈 PRE-08（不计价仓库中的生产和采购）警告太多。新参数 `PRE08_EXCL_WHS`（列表，仓库代码，默认空 = 不排除），在 B1 `@MTC_CA_PARAM` 加一行（取值如 `S300,WX01`），列出的仓库不再报。只影响警告明细，不影响计算。已部署的库依次执行 `patch_20261029_pre08whs.sql`、`08_precheck.sql`，再 `CALL "MTC_CA_P_META_SYNC"()`。改前备份 `sql/_backup/*_20261029_before_pre08whs.sql`。离线改的，还没编译。

同日：PRE-12（委外加工费找不到订单）明细的单号改成 DocNum：`20 采购收货-DocNum …-LineNum …`、`21 采购退货-DocNum …`、`MTC_OMRV 重估单-DocNum …-LineId …`（原来显示 DocEntry；查不到单号时仍显示 DocEntry）。只改 `08_precheck.sql`，已部署的库重新执行它即可；执行台 `js/core.js` 给 MTC_OMRV 加了中文名。改前备份 `sql/_backup/08_precheck_20261029_before_pre12docnum.sql`、`tools/console/_backup/core_20261029_before_pre12docnum.js`。

同日：其他校验明细的单号也改成 DocNum。`08` 新增函数 `MTC_CA_F_DOCKEY(单据类型, DocEntry)`，返回“类型-DocNum 单号”，支持 13–21、59、60、67、202、MTC_OWOR、MTC_OMRV；查不到单号时返回“类型-DocEntry n”。用到它的有 PRE-15、PRE-21、PRE-22，POST-04、BOOT-01（`14`），POST-12（`16`）。已部署的库依次执行 `08_precheck.sql`、`14_p50_p60_p65.sql`、`16_p70_jdt.sql`。改前备份 `sql/_backup/*_20261029_before_docnum.sql`。离线改的，还没编译。

同日：需要维护工时的产品清单。PRE-14（阻断）按订单报，阻断时快照会删掉，现在由新过程 `MTC_CA_P10_HOURS`（`12`）在 P10 之后按产品汇总写进 `MTC_CA_R_HOURS_NEED`（`11`）：费用池、订单数、本期入库数、本期工时单里的值（空 = 没录，0 = 录了 0）、参考工时（以前最近一个账期不为 0 的单位工时）。`MTC_CA_P_RUN`（`10`）、`MTC_CA_P_PRECHECK`（`17`）调用；PRE-14 的说明写“N 个产品，见工时维护页”。执行台新增“工时维护”页，“期初价维护”页加了物料组名称；两页都有“复制 B1 录入格式”（物料编码、名称、建议价 / 参考工时，不带表头）。已部署的库依次执行 `patch_20261029_hoursneed.sql`、`12_p30_init.sql`、`10_run_entry.sql`、`17_p90_tools.sql`、`18_meta_comments.sql`，再 `CALL "MTC_CA_P_META_SYNC"()`。改前备份 `sql/_backup/*_20261029_before_hoursneed.sql`、`tools/console/_backup/*_20261029_before_hoursneed.*`。离线改的，还没编译。

`20_b1cfg_check.sql`（校验视图 `MTC_CA_V_B1CFG_ISSUES`、TN 校验过程 `MTC_CA_P_B1CFG_TN`）直接引用 B1 自定义表，**不在部署包里**：B1 建好 `@MTC_CA_PARAM`（和 `@MTC_CA_POOL` / 1 / 2）后单独执行；`20_b1cfg_tn_snippet.sql` 是要合进 B1 `SBO_SP_TransactionNotification` 的一段，不能单独执行。建了 `@MTC_CA_PARAM` 却没装视图时 P05 记 FAIL。离线写的，都还没编译。

**TN 不会被部署覆盖**：`全部部署.sql`、`deploy.py`、`build_deploy.py`、`20_b1cfg_check.sql` 都不碰 `SBO_SP_TransactionNotification`，片段只能人工合入、人工删除。合入后 TN 依赖 `MTC_CA_P_B1CFG_TN` 和 `MTC_CA_V_B1CFG_ISSUES`：执行 `99_drop_all.sql`，或重建库后没执行 `20_b1cfg_check.sql`，B1 里保存计算参数（`MTC_CA_PARAM`）和费用池（`MTC_CA_POOL`）会报找不到过程而存不进去（其他单据不受影响）；重新执行 `20_b1cfg_check.sql`，或先把 TN 里那一段注释掉。

### 2026-10-30 POST-15 PUR1–PUR5 逐单据勾稽

用户要求 PUR1–PUR5 的数据和业务端逻辑匹配。新只读函数 `MTC_CA_F_PUR_DOC(RunId)`（`16`）按 采购单据 × 科目 列出：系统凭证（OJDT.TransType + CreatedBy）+ PUR 冲回 + PUR 重记 + MR01 = 业务端（220202 = 暂估变动；存货 = 计入物料成本的 R_LINE；140802 = 加工费暂估；140803、价格差异科目（OGAR.PriceDifAc / VarianceAc + 参数 `PUR_STDVAR_ACCTS`）、收货单其他科目 = 0；业务伙伴行、税额行、发票上其他科目不比较）。P75（`16`）新增 POST-15，另报没有系统凭证的单据、全部开票后暂估没清零、PUR4 与订单加工费不一致、非库存收货行、本期新用指定单价 `U_InitPrice` 的行（参数 `INITPRICE_NEW_FROM`，默认 2026-01-01）、已过账 PUR 与底稿不一致；说明里写截至期末仍按指定单价暂估的行数和金额。`P_CHECK_PUT`（`08`）：参数 `POST_WARN_IDS`（默认 `,POST-15,`）中的计算后校验按 IsBlock 只警告，其余仍一律阻断。执行台“应付暂估”页加“凭证勾稽”表（默认只看有差额，点行看系统凭证和 PUR 底稿逐行）。同日用户定（方案 B）：委外加工费计入订单的金额改按暂估口径（指定单价 U_InitPrice → 已确认价 Price × 数量 → LineTotal），与 PUR4 借 140802 一致：`07` P20_SUBFEE 收货 / 退货金额取 `S_AP_MOVE`（原来 LineTotal），取数 SQL `subfee.sql` 同步；旧视图的对应修改见 `fixes/MTC_VIEW_ProductDetail.sql`（用户自己改库）。执行台左侧菜单新增“暂估凭证 PUR”页：PUR 的目的、各凭证汇总（本次底稿 vs B1 本期已过账）、220202 本期变动（按暂估口径：指定单价 / 已确认价 / LineTotal / 委外加工费，点行看供应商）、截至期末仍按指定单价暂估的行、POST-15 结果和逐单据勾稽（原放在“应付暂估”页）。已部署的库执行 `patch_20261030_purchk.sql`（含 P_CHECK_PUT、P20_AP、P20_SUBFEE、F_PUR_DOC、P75 和种子），再执行 `18_meta_comments.sql`、`CALL "MTC_CA_P_META_SYNC"()`，重新计算后看 POST-15。改前备份 `sql/_backup/*_20261030_before_purchk.sql`、`tools/console/_backup/*_20261030_before_purchk.*`。离线写的，还没编译；`OGAR.PriceDifAc / VarianceAc`、`JDT1.VatLine` 两处 B1 字段是按标准结构写的，编译报错时告诉我。

### 2026-10-30 期初价维护写明原因和来源单据

用户要求期初价维护清单和生成到 B1 的期初单价维护单行备注里看得出这个物料为什么要维护。`11` 的 `MTC_CA_R_QCP_NEED` 加 `Reason`（原因：首次出现 / 以前出现过、本期哪些交易类型要按单价计价、计算前没有价格来源）和 `NeedDocs`（按交易类型列单号 Num，每类最多 10 张）；新表 `MTC_CA_R_QCP_LINE` 存逐行来源单据（结果层，阻断时也保留）。`12` 的 P10_QCP 写入这些，PRE-23 明细改用 Reason + 建议价 + 单据。执行台“期初价维护”页显示两列，点行看来源单据；服务器模式“生成 B1 单据”把原因、建议价来源和单号写进 `U_LineMemo`（超过 254 字截断；改已有 0 值行时只在原备注为空时写）。已部署的库依次执行 `patch_20261030_qcpreason.sql`、`12_p30_init.sql`、`18_meta_comments.sql`，再 `CALL "MTC_CA_P_META_SYNC"()`，然后重新“只做检查”。改前备份 `sql/_backup/*_20261030_before_qcpreason.sql`、`tools/console/_backup/*_20261030_before_qcpreason.*`。离线改的，还没编译。

同日（用户）：工时维护单的行备注保留“参考哪个账期的工时单”，再加费用池和本期有入库的订单。`11` 的 `MTC_CA_R_HOURS_NEED` 加 `PoolNames`（费用池代码 + 名称）、`NeedOrders`（类型 + 单号 Num + 入库数量，最多 15 张，多的写“等 N 张”），`12` 的 P10_HOURS 写入；执行台“工时维护”页显示这两列；“生成 B1 单据”写进 `@MTC_COST_TIME1.U_Memo`：`执行台运行 #N PRE-14：参考 YYYY-MM 工时单；费用池 …；本期有入库的订单 N 张（入库 X）：…`，超过 254 字截断。补丁同在 `patch_20261030_qcpreason.sql`。改前备份 `*_20261030_before_hoursmemo.*`。离线改的，还没编译。

### 2026-10-29 迭代不收敛排查

用户反馈迭代到 49 轮单价越来越大。原来未收敛（NOCONV）时快照和结果全删，只剩 `MTC_CA_RUN_ITER` 每轮一行合计，看不出是哪些物料在发散。新表 `MTC_CA_RUN_ITER_ITEM`（`01`）：P40（`13`）每轮记单价变化最大的前 `ITER_TRACE_TOP`（默认 30）个物料的四项单价、上一轮单价、期初、计价入库数量和金额；`MTC_CA_P_RUN`（`10`）未收敛时按参数 `KEEP_NOCONV`（默认 Y）调 `MTC_CA_P_RUN_CLEAN` 新模式 `NCV`（`03`）：保留本次快照和最后一轮中间结果，只删同运行键下以前未收敛运行的；下次同类运行成功时按原规则删掉。导出脚本（`tools/export_masked.ps1`、`新框架/tools/export_masked.py`）改成按运行号取数，默认最近一次运行 + 各类最近一次成功。已部署的库依次执行 `patch_20261029_noconv.sql`、`03_run_procs.sql`、`13_p40_iter.sql`、`10_run_entry.sql`、`18_meta_comments.sql`，再 `CALL "MTC_CA_P_META_SYNC"()`。改前备份 `sql/_backup/*_20261029_before_noconv.sql`。离线改的，还没编译。

### 2026-10-31 收货 / 发货行 → 订单统一

用户要求：返工单的委外加工费不改旧视图，新框架内统一规则。`07` 新增表函数 `MTC_CA_F_GI_ORDER(账期, 起, 止)`（起止为空 = 不限日期）：59 / 60 行取视图 `MTC_VIEW_Document` 改写后的订单，视图没给出订单的按行上 `U_OWORType` 补（原 P20_LINE 的兜底，2026-10-29）。P20_LINE 和 P20_SUBFEE 都用它；P20_SUBFEE 原来 202 取视图、返工单另读 IGN1，IGN1.BaseType 不是 -1 的 202 生产收货上的加工费挂不上订单，现在与收发存同一规则。取数 SQL `subfee.sql` ③ 同步（只读 B1，规则写在语句里）。`patch_20261030_purchk.sql` 里的 P20_SUBFEE / P20_LINE 已过期，不要再单独执行。已部署的库执行部署包，或执行 `07_snapshot_procs.sql`。改前备份 `sql/_backup/*_20261031_before_giorder.*`。离线改的，还没编译。

### 2026-11-01 发出商品 140601 尾差结转

用户要求 140601 差额 0.01 也算差异（财务不允许）。新参数 `GOODS_TAIL_MAX`（数字，默认 `1` 元，含）：140601 本期参与对账的分录合计不为 0、在 ± 本值以内的，P70（`16`）生成 JZ04，借 / 贷 `TAIL_ADJ`（640101），贷 / 借 140601；超过的不处理，POST-10 按差额 ≥ 0.005 报出。规则 `TAIL-02`。参数、参数目录、POST-10 说明在 `15_p70_tables.sql`，已部署的库执行 `patch_20261101_goodstail.sql`。未编译。

部署后在 B1 `@MTC_CA_PARAM` 加一行（`sl_import_costcfg.py --param` 会自动补上，已有的跳过）。B1 里要维护的参数完整清单见 `新框架/B1维护数据_成本参数.md` 第二节（2026-11-01 补齐到 46 个：`ITER_TRACE_TOP`、`KEEP_NOCONV`、`POST_WARN_IDS`、`PUR_STDVAR_ACCTS`、`INITPRICE_NEW_FROM`、`RPT_GRP_CLASS`、`GOODS_TAIL_MAX` 原来没写进文档）。

### 2026-11-01 PRE-28 B1 计算参数缺项（阻断）

用户要求：参数目录 `MTC_CA_C_PARAM_DEF` 里登记的参数，B1 `@MTC_CA_PARAM` 没有适用于本账期的行时，计算前先阻断（原来 P05 静默沿用新框架种子值，新加的参数 B1 没补也照算）。P10 按 B1 原样快照 `MTC_CA_C_PARAM_B1`（P05 每次同步时刷新）核对：Code 中 `@` 前 = 参数代码，起止账期为空 = 不限；只看有没有行，列表型参数可以填空值，取值格式仍由 PRE-18 管；B1 没建 `@MTC_CA_PARAM` 时报一行。旧表 `@MTC_CA_EXPSET` 不算维护。补参数最快的办法是 `python3 新框架/tools/sl_import_costcfg.py --param`（只补缺的，已有的跳过）。以后新加参数时，部署后先在 B1 补上再算。已部署的库依次执行 `patch_20261101_paramreq.sql`、`08_precheck.sql`，再 `CALL "MTC_CA_P_META_SYNC"()`。离线写的，还没编译。

### 2026-11-02 新旧报表合并：旧框架历史回填

用户要求：成本报表从上线 2024-12 起连续可查（方案和实施说明见 `新框架/报表合并方案.md`）。旧框架 2024-12 … `BOOTSTRAP_FC` 各期结果回填成历史运行（RunType H），报表的取数规则 `MTC_CA_F_RPT_RUN` 在承接账期及以前取它们。已部署的库依次执行 `09_bootstrap.sql`（比例算法抽成 `MTC_CA_P_LEGACY_RATIO`，期初承接改为调它，口径不变）、`21_reports.sql`、`22_legacy_load.sql`，再 `CALL "MTC_CA_P_META_SYNC"()`。然后 `CALL "MTC_CA_P_LEGACY_LOAD"('2024-12', '2026-08', 'manager')`（或执行台“期初承接”页“历史回填”），完成后执行 `22_legacy_verify.sql`，只反馈不通过数不为 0 的编号。建议先回填最后两期核对，再回填全部。离线写的，还没编译。

## 2026-11-04：委外加工费物料按参数判断（PRE-12）

用户确认 X 开头的物料不都是委外加工费。`07` 的 `MTC_CA_P20_SUBFEE`：不基于采购收货的退货原来按 `ItemCode LIKE 'X%'` 取，改为等于参数 `SUBFEE_ITEM`，其他 X 开头物料不再进 `S_SUBFEE`，也不再被 PRE-12 报出。`08` 的 PRE-12 新增一段：`S_AP_MOVE` 里本期按加工费计提、却不在 `S_SUBFEE` 的收货 / 退货行（行上没填 `U_BaseType = '59'`）也报出，只警告，金额不变。取数 SQL `subfee.sql` 同步（写默认值 X0510001，改参数后要手工同步）。已部署的库执行 `07_snapshot_procs.sql`、`08_precheck.sql`，再重新计算。改前备份 `sql/_backup/*_20261104_before_pre12.*`、`tools/console/_backup/subfee_20261104_before_pre12.sql`。离线改的，还没编译。

## 2026-11-04：库存重估清单（设计稿 8.8）

新表 `MTC_CA_R_REVAL_NEED`、新过程 `MTC_CA_P55_REVAL`（`MTC_CA_P_RUN` 在 P50 之后调用）、新参数 `REVAL_DEV_PCT`。执行台新页“库存重估”，服务器模式新接口 `/api/reval`。已部署的库依次执行 `patch_20261104_reval.sql`、`14_p50_p60_p65.sql`、`10_run_entry.sql`、`18_meta_comments.sql`，再 `CALL "MTC_CA_P_META_SYNC"()`；B1 `@MTC_CA_PARAM` 要先补 `REVAL_DEV_PCT`（`sl_import_costcfg.py --param`），否则 PRE-28 阻断。改前备份 `sql/_backup/*_20261104_before_reval.*`、`tools/console/_backup/*_20261104_before_reval.*`。SQL 离线写的，还没编译；服务端逻辑和页面只用模拟数据测过，没有真实写过 B1。

## 2026-11-04：阻断时看当月库存交易

用户要求计算前检查阻断时也能看当月交易明细（选快照，不是 B1 当前数据）。`03` 的 `MTC_CA_P_RUN_CLEAN` 模式 `BLK` 改为保留本次快照和校验结果，只删同运行键下以前 `BLOCKED` / `CHECKED` 运行的快照；下次同类运行成功时按 `OK` 删掉。`MTC_CA_P_RUN`（阻断）和 `MTC_CA_P_PRECHECK`（只做检查）都走这条路，所以“只做检查”也保留快照，`17` 的 P80 步骤说明同步。已部署的库执行 `03_run_procs.sql`、`17_p90_tools.sql`，不用改表；`10`、`12` 只改了注释。执行台：“收发存明细”页对 BLOCKED / CHECKED 运行改查快照（`snapLines`，可按物料开头、物料组、单号、订单号、交易类型、业务类型查），校验页 PRE 明细点行看对应物料、单据或订单的交易（PRE-07、PRE-08 的单据不在快照里，不能点）。快照没有计算成本。改前备份 `sql/_backup/*_20261104_before_blocksnap.*`、`tools/console/_backup/*_20261104_before_blocksnap.*`。SQL 离线改的，还没编译；`snapLines` 只在 SQLite 模拟数据上测过筛选和结存数量，页面没有在浏览器里跑过。

### 2026-11-04 手工重估单的两处防漏（用户）

PRE-29 已生成凭单账期有未进结果的重估单（只警告）：日期在 POSTED 账期内、未取消的 MRV1 行不在 PostRunId 的快照里。已部署的库依次执行 `patch_20261104_revalcheck.sql`、`08_precheck.sql`、`CALL "MTC_CA_P_META_SYNC"()`。执行台服务端同时改了：运行之后新增的同物料 MRV1 单，生成重估单时跳过。未编译。

### 2026-11-05 POST-15 取消非库存收货行（用户）

检查 ⑤ 报的 X0710002 这类是虚拟物料，不进成本、不暂估，开票时入费用，用户确认不需要警告，只有委外加工费需要处理。`16` 的 P75 去掉 ⑤（⑥ ⑦ 编号不变），`15` 和执行台 PUR 页的说明同步。原说明“PUR5 冲掉了系统分录”也不对：核实一张单据，收货没有系统凭证，发票直接借费用科目。已部署的库依次执行 `16_p70_jdt.sql`、`patch_20261105_nonstockchk.sql`。未编译。

### 2026-11-05 POST-15 ② 跳过发票和收货都是 0 的单据（用户）

发票是 0 且收货金额也是 0 的单据，B1 不生成凭证，也没有可冲回的分录，用户确认不需要关注。`16` 的 P75 ② 按单据合计，发票金额（DocAmt）和冲回的收货暂估（AccrAmt）都是 0 的不报；只有发票是 0、收货有金额的照常报。已部署的库重新执行 `16_p70_jdt.sql`。未编译。

### 2026-11-05 POST-15 ② 不报加工费收货 / 退货（用户）

加工费物料 X0510001 是非库存物料，收货 / 退货 B1 不生成凭证，由 PUR4 按暂估记账（核实：一张纯加工费收货 TransId 为空），② 原来把这类单据全部误报。`16` 的 P75 ② 对收货 / 退货只看 `AccrType = 'MAT'` 的变动，发票 / 贷项不变；加工费金额继续由 ④ 核对。已部署的库重新执行 `16_p70_jdt.sql`。未编译。

### 2026-11-05 POST-15 ② 不报不基于收货的退货（用户）

2026-10 全部 41 张采购退货都没有系统凭证，也没有挂在别处的类型 21 凭证，B1 对这类退货不生成凭证，由 PUR1 / PUR4 记账。`16` 的 P75 ② 不再报 `ObjType = BaseObj = '21'` 的变动；基于收货的退货（BaseObj = 20）照常报。已部署的库重新执行 `16_p70_jdt.sql`。未编译。

### 2026-11-05 已过账凭单冲销后重算（用户）

凭单都过账后要重做：在 B1 冲销（日期选同一账期）→ 执行台撤销凭单 → 重新计算 → 重新生成。原来原凭证冲销后仍算“已过账”，底稿分录被当成重复（Dup）不计入，总账净额是 0，财务对账和 POST 校验的差额等于全部业务金额。`16` 的 P70 JZ04、`F_RECON_LEDGER`、`F_RECON_STATUS`、`F_TB_LINE`、P75 ⑦ 改为：本期内已被冲销的原凭证不算已过账。冲销日期在下期的不排除（本期总账确实还含旧金额）。冲销凭证没带凭证代码时，PP04（`16`）和 P20_EXP（`07`）按原凭证的代码算，成本凭证的冲销不进制造费用结转和费用池；取数 SQL `exp.sql` 同步。只读排查 `diag_jv_reversal.sql` 列出这批凭单的过账、冲销日期和处理建议，不含金额。已部署的库依次执行 `07_snapshot_procs.sql`、`16_p70_jdt.sql`，都是 CREATE OR REPLACE，不用改表。**没解决**：`P_JV_UNDO` 只看有没有冲销、不看冲销日期，冲销落在下期（如 AR03 / AR04 自动冲销已执行）时仍能撤销，重新生成后总账重复。改前备份 `sql/_backup/*_20261105_before_jvrev.*`、`tools/console/_backup/exp_20261105_before_jvrev.sql`。离线改的，还没编译。

### 2026-11-05 R21 成本结转分录清单（用户）

把 `diag_jv_list.sql` 做成报表 `MTC_CA_RPT_21_JVLIST`（`21`），进成本报表“核对”分组和 B1 查询管理器：分录清单、逐行明细、其他成本凭证。按 `MTC_CA_JV` 的批号取，不走 `F_RPT_RUN`，撤销后选“含已撤销”仍可查。已部署的库执行 `21_reports.sql`；执行台要更新 `actions.json`、`js/rptdefs.js`（服务器模式用新打的包），B1 查询管理器要补登记（`sl_import_queries.py`）。改前备份 `*_20261105_before_jvlist.*`。离线写的，还没编译。

### 2026-11-05 POST-10 本期计提冲销后重算误报（用户）

本期 AR03 / AR04 过账后在 B1 冲销、再重算时，`F_RECON_LEDGER` 把冲销分录（`RevOf` = AR03 / AR04）一律归到 ① 冲销上月计提，原分录归 ⑤ 本月计提。合计仍是 0，但 ① 和 ⑤ 各多出被冲销的金额，POST-10 报 ① ≠ 上期末未开票、⑤ ≠ 本期末未开票（2026-10：两边都多 2,581,027.22）。改为：被冲销的原凭证 RefDate 早于本期才是 REV，否则归 ACCR，与原分录在 ⑤ 里抵消（`led` 加 `RevPrior`）。执行台“财务对账”的构成同一来源，一起变。已部署的库重新执行 `16_p70_jdt.sql`（CREATE OR REPLACE，不改表），重新打部署包 `python3 新框架/tools/build_deploy.py`。改前备份 `sql/_backup/*_20261105_before_goodsrev.*`。离线改的，还没编译。

### 2026-11-05 R22 产品生产成本走势、R23 产品销售毛利走势（用户）

新增 `MTC_CA_RPT_22_COSTTREND`、`MTC_CA_RPT_23_MARGINTREND`，函数 `MTC_CA_F_SALE_TREND`，`MTC_RPT_F_SALE_COST` 搬进 `21_reports.sql`。已部署的库执行 `21_reports.sql`，再跑 `21_reports_verify.sql` 看 V15–V17；执行台要更新 `actions.json`、`js/rptdefs.js`、`js/rpt.js`，服务器模式重新 `pack_server.py`，B1 里用 `sl_import_queries.py` 补登记。未编译，改前备份 `*_20261105_before_trend.*`。

### 2026-11-06 POST-16 制造 / 人工费用波动（用户）

用户要求：制造费用按产量每月应在 100 万左右，单据做错成 10 万这类要警告。P60 新增 POST-16，按“全部”和各费用池比较制造、人工：基准 = 本期之前最近 `FEE_BASE_MONTHS`（默认 6）个账期的中位数（`MTC_CA_PERIOD` 的 PostRunId / CalcRunId，承接账期及以前取历史运行 H），不含关单差异和历史委外转出（H 运行的费用含关单差异，分不开）。金额偏离基准，且也偏离“基准单位费用 × 本期产量”才报，产量能解释的不报；偏离 = 差额 ≥ `FEE_DEV_AMT`（默认 5 万）且比例 > `FEE_DEV_PCT`（默认 30%）。本期完全没有费用也报。产量用入库数不用工时，因为历史运行没有工时。基准不足 3 个月的不比较；历史运行只有虚拟池 LEGACY，所以各池要等新框架积够 3 个月。

固定只警告：`P_CHECK_PUT` 把 POST-16 并入 `POST_WARN_IDS`，B1 里的这个参数不用改。已部署的库依次执行 `patch_20261106_feedev.sql`、`08_precheck.sql`、`14_p50_p60_p65.sql`，再 `CALL "MTC_CA_P_META_SYNC"()`；3 个新参数在参数目录里，先执行 `sl_import_costcfg.py --param` 补到 B1，否则 PRE-28 阻断。改前备份 `sql/_backup/*_20261106_before_feedev.*`。离线改的，还没编译。

### 2026-11-06 PRE-31 委外加工费与入库不同期（用户）

业务要求本月入库本月暂估。P10 新增 PRE-31（只警告，不改计算）：本期未取消的加工费收货行，对应的生产收货不在本期时列出订单、两张单据、日期、金额和这笔的去向。已部署的库依次执行 `patch_20261106_subfeefc.sql`、`08_precheck.sql`，再 `CALL "MTC_CA_P_META_SYNC"()`。

### 2026-11-06 R24 其他领用明细表（用户）

与生产订单无关的其他出入库和盘点（I04 / O04 / I10 / O10）逐单据行明细，替代旧的其他领用查询。已部署过的库执行 `patch_20261106_r24otheruse.sql`，再把 `新框架/reports/B1查询语句.md` 的 R24 语句登记到 B1 查询管理器（`新框架/tools/sl_import_queries.py`）。勾稽 V18。离线写的，未编译。
