// 成本执行台 · core.js — 基础：接口调用 api() / q()、查询缓存、字段中文名 LABEL 和代码字典、表格“SQL”查看、取数 SQL
// index.html 按顺序加载 js/ 下的脚本，共用全局作用域；加载时立即执行的代码只能用到本文件和前面文件里的名字。
"use strict";
const $ = s => document.querySelector(s);
const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const H = {"X-Requested-With":"cost-console"};
// 公司（账套）（用户 2026-10-23）：本机模式每个请求在请求头 X-Schema 里带所选公司（链接里的 co= 优先，其次本机记住的 cc.co）；
// 服务器模式以登录时选的公司为准，服务端不看这个头
let CO = ""; try { CO = localStorage.getItem("cc.co") || ""; } catch (e) {}
{ const m = /[?&]co=([^&]+)/.exec(location.hash); if (m) CO = decodeURIComponent(m[1]); }
async function api(path, body){
  const hd = CO ? {...H, "X-Schema":CO} : H;
  const r = await fetch(path, body ? {method:"POST", headers:{...hd, "Content-Type":"application/json"}, body:JSON.stringify(body)} : {headers:hd});
  let j;
  try { j = await r.json(); }
  catch (e) { throw new Error(r.status === 404 ? `服务端没有接口 ${path}：页面已更新但执行台服务还是旧版本，请关掉服务窗口重新启动` : `服务端返回的不是 JSON（HTTP ${r.status}）`); }
  if (j.auth) { location.replace("/login.html" + (CO ? "?co=" + encodeURIComponent(CO) : "") + location.hash); throw new Error(j.error); }   // 服务器模式：未登录或登录过期
  if (j.badSchema) {   // 记住的公司已经不可用：忘掉它，回首页重新选
    try { localStorage.removeItem("cc.co"); } catch (e) {}
    if (CO) { CO = ""; location.replace(location.pathname); }
    throw new Error(j.error);
  }
  if (!j.ok) throw new Error(j.error || "请求失败");
  return j;
}
// 查询结果缓存：运行结束后结果不再变，同一查询第二次直接用缓存（切页签不重查）；“刷新”和计算进行中会清空。
// 依赖当前总账的财务对账另行处理（见 recon 页的“重新对账”）
const QC = new Map();
const NOCACHE = new Set(["reconSrc", "tb", "tbAcctSum", "tbLedger", "tbVoucher"]);   // 科目余额表按当前总账，每次重查
const qKey = (action, args) => action + "|" + JSON.stringify(args);
const cacheable = (action, args) => args.runId && !NOCACHE.has(action) && RUNS.some(r => String(r.RunId) === String(args.runId) && r.Status !== "RUNNING");
const qCached = (action, args = {}) => QC.get(qKey(action, args));
async function q(action, args = {}, fresh = false){
  const k = qKey(action, args);
  if (!fresh && QC.has(k)) return QC.get(k);
  const r = await api("/api/q", {action, args});
  r.src = [{action, args}];   // 表格工具条“SQL”按钮据此显示语句和参数
  if (cacheable(action, args)) QC.set(k, r);
  return r;
}
const asObjs = r => r.rows.map(x => Object.fromEntries(r.columns.map((c, i) => [c, x[i]])));

const LABEL = {
  DiffKind:"差异类型", AmtDiff:"金额差", SrcOpenQty:"取数 SQL · 未清数量", SrcOpenAmt:"取数 SQL · 暂估金额", SrcUnitPrice:"取数 SQL · 暂估单价",
  RunOpenQty:"计算结果 · 未清数量", RunOpenAmt:"计算结果 · 暂估金额", RunUnitPrice:"计算结果 · 暂估单价",
  RunId:"运行号", FcCode:"账期", RunType:"类型", Scenario:"场景", Status:"状态", Msg:"说明", StartTime:"开始", EndTime:"结束",
  StepNo:"#", StepCode:"步骤", RowCnt:"数量", Sec:"秒", Iter:"轮", MaxPriceDelta:"最大单价变化", PoolDelta:"费用池变化",
  CloseDifDelta:"关单差异变化", UnconvItems:"未收敛物料", CheckId:"编号", Stage:"阶段", Title:"校验", Result:"结果", IssueCnt:"问题数",
  IsBlock:"阻断", Purpose:"用途", TroublePath:"排查路径", SeqNo:"#", KeyCode:"对象", Info:"说明", Kind:"类别", Cnt:"差异条数",
  AbsDiff:"差异绝对值合计", NoReason:"未归因", NewVal:"新框架", OldVal:"旧框架", Diff:"差额", Reason:"原因", Note:"备注",
  ItemCode:"物料", iLevel:"层级", PriceSrc:"定价来源", Price:"单价", PMat:"材料", PMfg:"制造费用", PLab:"人工", PSub:"委外",
  OpenQty:"期初数量", InQty:"入库数量", OutQty:"出库数量", EndQty:"期末数量", EndAmount:"期末金额", Flags:"标记",
  OrderType:"订单单据", OrderEntry:"订单 Entry", WorType:"订单类型", PlannedQty:"计划数", RecvQty:"本期完工", CostMat:"材料", CostMfg:"制造费用",
  CostLab:"人工", CostSub:"委外", CostAmt:"完工成本", UnitCost:"单位成本", WipAmt:"在产品", CloseDifAmt:"关单差异", ClosedInFc:"按关单处理",
  TransCode:"凭证代码", TransName:"名称", Lines:"行数", Debit:"借方", Credit:"贷方", NoAcct:"缺科目", LineNo:"行", RefDate:"日期",
  AcctCode:"科目", OcrCode:"成本中心", Project:"项目",
  OrderNum:"订单号 Num", ItemName:"名称", PostDate:"下单日期", B1Status:"当前状态", CloseDate:"关闭日期", StatusAtEnd:"期末状态", InScope:"计算范围",
  CardCode:"业务伙伴", PrevRecvQty:"上期累计完工", Ratio:"结转比例", AllocMfg:"分摊制造费用", AllocLab:"分摊人工",
  PlanQty:"计划用量", OpenIssQty:"期初累计领料数", OpenIssAmt:"期初累计领料", OpenCarAmt:"期初累计结转", IssQty:"本期领料数", IssAmt:"本期领料",
  CarAmt:"本期结转", CarMat:"结转材料", CarMfg:"结转制造", CarLab:"结转人工", CarSub:"结转委外", ClsAmt:"关单差异",
  WipMat:"在产品材料", WipMfg:"在产品制造", WipLab:"在产品人工", WipSub:"在产品委外", ClosedCnt:"本期关单数",
  AllocState:"分摊情况", UnitHours:"单位工时", TotHours:"工时", PoolPct:"占池工时%", MfgPerUnit:"每件制造费用", LabPerUnit:"每件人工", HourRate:"每工时费用",
  PoolCode:"费用池", PoolName:"名称", Elem:"要素", Hours:"单位工时", Weight:"权重", Amount:"金额",
  SrcJDT:"凭证", SrcMRV:"重估", SrcPROWW:"委外重估", SrcSHARED:"公摊材料", SrcCLOSEDIF:"关单差异", PoolAmt:"池合计", AllocAmt:"已分摊", Unalloc:"未分摊", OrderCnt:"订单数",
  DocDate:"日期", ObjType:"单据类型", DocNum:"单号 Num", DocEntry:"单号 Entry", LineNum:"行号 LineNum", BusiType:"业务类型", WhsCode:"仓库", Qty:"数量",
  MatAmt:"材料", MfgAmt:"制造费用", LabAmt:"人工", SubAmt:"委外", RuleId:"规则",
  CustType:"客户类型", IsSample:"样品", DocQty:"单据数量", InvQty:"已开票", RetQty:"已退货", CostSrc:"成本来源", AccrType:"暂估类别",
  Seq:"#", Sec:"项目", Note:"说明", ValA:"本次", ValB:"对比运行", DiffCnt:"有差异", KpiType:"指标", Value:"值", TableName:"表", Layer:"层", ColumnName:"字段", DataType:"类型",
  Descr:"说明", Scene:"场景", Basis:"依据", ToolName:"工具", ProcName:"过程", IsWrite:"写数据", NeedConfirm:"需确认", ModelOutput:"给模型的内容",
  ParamCode:"参数", FromFc:"起", ToFc:"止", Usage:"用途", LineNo:"行", OvrType:"假设类型", Stage:"阶段", Val:"值", Key:"键",
  Sel:"生成", LineCnt:"行数", BadAcct:"科目有问题", State:"状态", StateMsg:"说明", BatchNum:"B1 批号", B1State:"B1 里现在", JvId:"#",
  AutoRev:"下月冲销", RevDate:"冲销日期", AckUser:"确认人", AckTime:"确认时间", AckReason:"确认理由", Act:"操作",
  CreateUser:"生成人", CreateTime:"生成时间", DelUser:"撤销人", DelTime:"撤销时间",
  UnitPrice:"暂估单价", OpenAmt:"暂估金额", PurRole:"科目类别", SysAmt:"系统凭证", PurRev:"PUR 冲回", PurBook:"PUR 重记", Mr01:"MR01", InitCnt:"指定单价行", HasSysJe:"有无系统凭证", PurSrc:"来源", Vendors:"供应商数", VendorCode:"供应商",
  Area:"对账项", BegBiz:"期初·业务", BegFin:"期初·财务", BegDiff:"期初·差额", CurBiz:"本期·业务", CurFin:"本期·财务", CurDiff:"本期·差额", EndBiz:"期末·业务", EndFin:"期末·财务", EndDiff:"期末·差额", EndDiffGl:"总账差额（含手工调整）", EndEqBeg:"扣除手工后 = 期初差额", Phase:"期间", BizAmt:"业务端", GlAmt:"总账已过账", VchAmt:"未清凭单", DraftAmt:"底稿", PendAmt:"未过账底稿", FinAmt:"财务端", Diff:"差额", PendCodes:"未过账底稿凭证", DupAmt:"已过账底稿（不再加）", DupCodes:"已过账底稿凭证", Fin1:"①财务端", Diff1:"参考：①全部底稿", Fin2:"②财务端", Diff2:"参考：②不加底稿", OtherAmt:"手工调整（不参与对账）", InRecon:"计入对账", Dup:"已过账（不再加）", Amt:"金额",
  IsDefault:"默认池", IsCloseDif:"关单差异池", SrcCnt:"成本中心行", TgtCnt:"分摊范围行", OcrName:"名称", DimCode:"维度", CalType:"成本计入类型", Active:"有效",
  MatchBy:"匹配方式", MatchVal:"匹配值", MatchName:"匹配到", WorTypes:"订单类型", InFc:"本期适用", Used:"计算时",
  FirstSeen:"出现情况", Action:"操作", Pools:"费用池", CurHours:"本期工时单", RefHours:"参考工时", RefFc:"参考工时账期", NoRef:"无参考工时", ZeroCnt:"录了 0", ItmsGrpNam:"物料组名称", LastFc:"最近出现账期", NeedTrans:"需要单价的交易", NeedDocs:"来源单据", PoolNames:"费用池名称", NeedOrders:"本期有入库的订单", NeedQty:"数量", SuggPrice:"建议价", SuggSrc:"建议价来源", SuggFc:"建议价账期", FirstCnt:"首次出现", NoSugg:"无参考价", ItmsGrpCod:"物料组", SrcTrans:"凭证代码 / 交易类型", SrcObj:"来源单据类型", SrcDoc:"来源单据 Entry", JdtNum:"凭证编号 Number",
  GrpName:"物料组名称", ItemCnt:"物料数", BegQty:"期初数量", BegPrice:"期初单价", BegAmt:"期初金额", RcvQty:"入库数量",
  InPrice:"入库单价", InAmt:"入库金额", OutPrice:"出库单价", OutAmt:"出库金额", EndPrice:"期末单价", EndAmt:"期末金额",
  BalQty:"结存数量", BalPrice:"结存单价", BalAmt:"结存金额",
  BegMat:"期初·材料", BegMfg:"期初·制造", BegLab:"期初·人工", BegSub:"期初·委外", InMat:"入库·材料", InMfg:"入库·制造", InLab:"入库·人工", InSub:"入库·委外",
  OutMat:"出库·材料", OutMfg:"出库·制造", OutLab:"出库·人工", OutSub:"出库·委外", EndMat:"期末·材料", EndMfg:"期末·制造", EndLab:"期末·人工", EndSub:"期末·委外",
  ...Object.fromEntries([["Beg", "期初"], ["In", "入库"], ["Out", "出库"], ["End", "期末"]].flatMap(([k, n]) => [["Mat", "材料"], ["Lab", "人工"], ["Mfg", "制造"], ["Sub", "委外"]].map(([e, m]) => ["Rt" + k + e, `${n}料工费占比·${m}%`]))),
  SrcType:"来源", BizTrans:"交易类型", OrderRefNum:"订单号 Num",
  Src:"来源", SrcKey:"来源键（内部）", RcptNum:"生产收货单 Num", MatchNote:"匹配方式", FeeOpen:"期初未结转", FeeIss:"本期发生", FeeCar:"本期结转", FeeCls:"关单差异", FeeWip:"期末未结转",
  Cat:"分类", AcctName:"科目名称", BegDr:"期初借方", BegCr:"期初贷方", CurDr:"本期借方", CurCr:"本期贷方", EndDr:"期末借方", EndCr:"期末贷方",
  PendDr:"未过账借方", PendCr:"未过账贷方", AllDr:"含未过账期末借方", AllCr:"含未过账期末贷方", DocNo:"凭证编号 Number", TransId:"交易号 TransId", LineId:"行", Line_ID:"行",
  BaseRef:"原始单号 Num", Memo:"摘要", Dir:"方向", Balance:"余额", RevOf:"冲销的凭证", Part:"发出商品构成",
  Category:"分类", CnName:"名称", B1Value:"B1 取值", Locked:"锁定", EffValue:"计算使用值", ParamState:"状态", Hint:"填法", Obj:"表",
};
const ELEM = {MFG:"制造费用", LAB:"人工"};
const RECON = {STOCK:"存货", WIP_PROD:"生产在产品", WW_MAT:"委外材料", WW_FEE:"委外加工费", GOODS:"发出商品", AP:"应付暂估"};
const diffCell = v => Math.abs(Number(v || 0)) > 0.01 ? `<b style="color:var(--crit)">${fmtNum(v)}</b>` : fmtNum(v);
const QCPSRC = {NEW:"新框架期末单价", OLD:"旧框架单价", BOOT:"期初承接", LASTPUR:"最近采购价"};
const JSRC = {LINE:"单据行", ORDER:"订单", DOC:"B1 单据行", GL:"总账分录", OMRV:"重估单", ITEM:"物料尾差"};
const SUBSRC = {PDN:"加工费收货", RPD:"加工费退货", PROWW:"委外重估"};
const WORTYPE = {"10":"生产计划单","20":"包装计划单","30":"返工计划单","40":"生产试打","50":"委外工单"};
const STEP = {P00:"准备",P05:"费用池 / 计算参数从 B1 同步",P20_ITEM:"快照：物料与层级",P20_LINE:"快照：库存变动",P20_AP:"快照：应付暂估变动",P20_SUBFEE:"快照：委外加工费",P20_ORDER:"快照：订单",
  P20_EXP:"快照：费用来源",P20_MISC:"快照：工时、维护价",P20_OPEN:"快照：期初",P10:"计算前检查",P30:"初始化与固定价格",P31:"模拟场景假设",P40:"迭代计算",
  P50:"定稿与尾差",P60:"计算后校验",P65:"新旧比对",P71:"发出商品",P73:"应付暂估",P74:"应付暂估凭证",P70:"凭证",P75:"凭证校验",P80:"收尾"};
const RUNST = {OK:"完成",RUNNING:"运行中",FAIL:"失败",WARN:"有警告",BLOCKED:"检查阻断",NOCONV:"未收敛",SKIP:"跳过",CHECKED:"检查通过"};
const CHKST = {PASS:"通过",FAIL:"阻断",WARN:"警告",SKIP:"跳过",NA:"不适用"};
const chip = s => `<span class="chip s-${esc(s)}">${esc(RUNST[s] || s)}</span>`;
// 校验明细中显性的问题标红（用户 2026-10-14）：不为 0 的差额 / 尾差 / 影响金额、不等式两边、比对双方的数量、百分比波动、问题类别和“找不到”等说法
const RED = t => `<b class="bad">${t}</b>`;
const NUMRE = "-?\\d[\\d,]*(?:\\.\\d+)?";
const nz = n => Math.abs(Number(String(n).replace(/,/g, ""))) > 0.005;
function hlInfo(v){
  let h = esc(v);
  h = h.replace(new RegExp(`(差额[①②]?|尾差|影响金额约?|未分摊|期末金额|借方|贷方)(\\s*)(${NUMRE})`, "g"), (m, k, sp, n) => nz(n) ? k + sp + RED(n) : m);
  h = h.replace(new RegExp(`(新框架期末|B1)(\\s+)(${NUMRE})`, "g"), (m, k, sp, n) => k + sp + RED(n));
  h = h.replace(new RegExp(`(，金额\\s*)(0(?:\\.0+)?)(?![\\d.])`, "g"), (m, k, n) => k + RED(n));
  h = h.replace(/[（(][+-]?\d+(?:\.\d+)?%[）)]/g, m => RED(m));
  h = h.replace(/≠/g, RED("≠"));
  h = h.replace(/^(负库存|有数量无金额(?:的单据行)?|金额为负|尾差偏大|小尾差|数量 0 金额不为 0|期末单价偏离|价格波动)/, m => RED(m));
  h = h.replace(/(找不到[^，；。、]*|取不到[^，；。、]*|不对应|未结转|没有客户类型)/g, m => RED(m));
  return h;
}
const chkChip = s => `<span class="chip s-${esc(s)}">${esc(CHKST[s] || s)}</span>`;
const fmtNum = v => {
  if (v === null || v === undefined || v === "") return "";
  const n = Number(v); if (!isFinite(n)) return esc(v);
  const s = n.toLocaleString("zh-CN", {maximumFractionDigits: Math.abs(n) < 100 ? 6 : 2});
  return n < 0 ? `<span class="neg">${s}</span>` : s;
};

// 校验的执行语句：从数据库中已部署的过程定义（SYS.PROCEDURES）截出该项，反映实际运行的版本；
// 再列出语句读到的 MTC_CA_S_ / R_ 表由哪些过程写入（INSERT / UPDATE），以及 MTC_CA_V_ 视图的定义
const CHECK_PROCS = ["MTC_CA_P10_PRECHECK", "MTC_CA_P60_POSTCHECK", "MTC_CA_P75_POSTCHECK"];
let CHECK_DEFS = null;
function cutCheckSql(def, checkId){
  const call = `"MTC_CA_P_CHECK_PUT"(:RunId, '${checkId}'`;
  const i = def.indexOf(call);
  if (i < 0) return null;
  const end = def.indexOf(";", i) + 1;
  const prev = def.lastIndexOf('"MTC_CA_P_CHECK_PUT"(:RunId,', i - 1);
  let start = def.lastIndexOf(`-- ${checkId} `, i);
  if (start < 0 || start < prev) start = prev >= 0 ? def.indexOf(";", prev) + 1 : 0;
  return def.slice(start, end).replace(/^\s*\n/, "").replace(/\s+$/, "");
}
function stmtAt(def, idx){
  const ls = def.lastIndexOf("\n", idx) + 1, end = def.indexOf(";", idx);
  return def.slice(ls, end < 0 ? def.length : end + 1);
}
function tableWriters(table){
  const out = [];
  const direct = new RegExp(`(INSERT\\s+INTO|UPSERT|UPDATE)\\s+"${table}"`, "g");
  const alias = new RegExp(`UPDATE\\s+(\\w+)\\s+SET[^;]*?FROM\\s+"${table}"\\s+\\1\\b`, "g");
  for (const d of CHECK_DEFS) {
    if (d.Kind !== "P") continue;
    const def = String(d.Def || ""), stmts = [];
    for (const re of [direct, alias]) { re.lastIndex = 0; let m; while ((m = re.exec(def))) stmts.push([m.index, stmtAt(def, m.index)]); }
    if (stmts.length) out.push({proc: d.ProcName, def, stmts: stmts.sort((a, b) => a[0] - b[0]).map(x => x[1])});
  }
  return out;
}
const preBox = t => `<pre class="mono" style="white-space:pre;font-size:12px;background:var(--soft);padding:10px;border-radius:6px;max-height:50vh;overflow:auto">${esc(t)}</pre>`;
function sourceHtml(sql){
  const names = [...new Set([...sql.matchAll(/"(MTC_CA_[SRV]_[A-Z0-9_]+)"/g)].map(m => m[1]))];
  if (!names.length) return "";
  return `<h3>相关表的来源</h3><p class="hint">语句读到的快照表 / 结果表由哪些过程写入（只列 INSERT / UPDATE 语句；语句里的 :xxx 是同一过程中前面定义的表变量，展开“整个过程”可看到）。视图直接显示定义。</p>`
    + names.map(t => {
      if (t.startsWith("MTC_CA_V_")) {
        const v = CHECK_DEFS.find(d => d.Kind === "V" && d.ProcName === t);
        return `<details><summary class="mono">${esc(t)}（视图）</summary>${v ? preBox(String(v.Def || "")) : `<p class="hint">数据库中没有这个视图。</p>`}</details>`;
      }
      const w = tableWriters(t);
      if (!w.length) return `<details><summary class="mono">${esc(t)}</summary><p class="hint">没有找到写入这张表的过程。</p></details>`;
      return `<details><summary class="mono">${esc(t)} ← ${w.map(x => esc(x.proc)).join("、")}</summary>`
        + w.map(x => `<p class="mono" style="margin:8px 0 4px"><b>${esc(x.proc)}</b>（${x.stmts.length} 处写入）</p>` + preBox(x.stmts.join("\n\n"))
          + `<details><summary>整个过程 ${esc(x.proc)}</summary>${preBox(x.def)}</details>`).join("")
        + `</details>`;
    }).join("");
}
async function showCheckSql(checkId, box){
  if (box.innerHTML) { box.innerHTML = ""; return; }
  box.innerHTML = `<div class="empty">加载中…</div>`;
  try {
    if (!CHECK_DEFS) CHECK_DEFS = asObjs(await q("checkSql", {}));
    let sql = null, proc = "";
    for (const d of CHECK_DEFS) {
      if (d.Kind !== "P" || !CHECK_PROCS.includes(d.ProcName)) continue;
      sql = cutCheckSql(String(d.Def || ""), checkId); if (sql) { proc = d.ProcName; break; }
    }
    if (!sql) { box.innerHTML = `<p class="hint">在数据库已部署的检查过程中没有找到 ${esc(checkId)}。</p>`; return; }
    box.innerHTML = `<p class="hint">来自数据库中已部署的过程 <span class="mono">${esc(proc)}</span>。<span class="mono">:RunId</span>、<span class="mono">:fc</span>、<span class="mono">:d0</span> / <span class="mono">:d1</span>（账期起止日）等是过程变量，单独执行时替换为运行号、账期和日期；<span class="mono">t..</span> 表变量即问题明细，最后的 CALL 把它写入校验结果。</p>`
      + `<div class="bar"><span class="sp"></span><button class="btn" id="dtlSqlCopy">复制</button></div>`
      + preBox(sql) + sourceHtml(sql);
    $("#dtlSqlCopy").onclick = () => navigator.clipboard && navigator.clipboard.writeText(sql);
  } catch (e) { box.innerHTML = errBox(e); }
}
// 表格工具条“SQL”：显示产生这张表的白名单查询（actions.json）、参数值、代入参数后可直接执行的语句，以及读到的 MTC_CA_ 表由哪些过程写入。
// 语句由服务端 /api/sql 返回（只限 kind=query），页面不执行它。用户 2026-10-18
const SQLDEF = new Map();
const sqlLit = v => v === null || v === undefined ? "NULL" : "'" + String(v).replace(/'/g, "''") + "'";
// 代入参数：按顺序替换字符串常量和引号标识符之外的 ?
function sqlBind(sql, vals){
  let i = 0;
  return sql.replace(/'(?:[^']|'')*'|"(?:[^"]|"")*"|\?/g, m => m === "?" ? (i < vals.length ? sqlLit(vals[i++]) : m) : m);
}
// 简单换行：主要子句前断行，便于阅读（不改语义）
const sqlPretty = sql => sql.includes("\n") ? sql : sql.replace(/'(?:[^']|'')*'|"(?:[^"]|"")*"|\s+(FROM|LEFT JOIN|INNER JOIN|JOIN|WHERE|GROUP BY|HAVING|ORDER BY|UNION ALL|UNION)\s+/g,
  (m, k) => k ? "\n" + k + " " : m);
async function showQuerySql(src){
  const box = drawer("查询语句");
  box.innerHTML = `<div class="empty">加载中…</div>`;
  try {
    const defs = await Promise.all(src.map(async x => {
      if (!SQLDEF.has(x.action)) SQLDEF.set(x.action, await api("/api/sql", {action:x.action}));
      return SQLDEF.get(x.action);
    }));
    if (!CHECK_DEFS) { try { CHECK_DEFS = asObjs(await q("checkSql", {})); } catch (e) {} }
    box.innerHTML = `<p class="hint">这张表由下面${src.length > 1 ? " " + src.length + " 个" : "的"}只读查询产生（登记在 tools/console/actions.json）。“代入参数”的语句可以直接在 HANA Studio / DBeaver 里执行；单价、小计、合计、占比等是页面在查询结果上算的，不在语句里。</p>`
      + src.map((x, k) => {
        const d = defs[k], vals = (d.params || []).map(p => x.args[p] ?? "");
        const bound = sqlPretty(sqlBind(d.sql, vals));
        return `<h3>${esc(d.title || x.action)} <span class="hint mono">${esc(x.action)}</span></h3>`
          + (d.params && d.params.length ? `<p class="hint">参数（按 ? 的顺序）：${d.params.map((p, i) => `<span class="mono">${esc(p)} = ${esc(sqlLit(vals[i]))}</span>`).join("，")}</p>` : `<p class="hint">没有参数。</p>`)
          + `<div class="bar"><span class="sp"></span><button class="btn" data-sc="${k}" data-m="b">复制（代入参数）</button><button class="btn" data-sc="${k}" data-m="r">复制原语句</button></div>`
          + preBox(bound);
      }).join("")
      + (CHECK_DEFS ? sourceHtml(defs.map(d => d.sql).join("\n")) : "");
    box.querySelectorAll("[data-sc]").forEach(b => b.onclick = () => {
      const k = Number(b.dataset.sc), d = defs[k], vals = (d.params || []).map(p => src[k].args[p] ?? "");
      const t = b.dataset.m === "b" ? sqlPretty(sqlBind(d.sql, vals)) : d.sql;
      if (navigator.clipboard) navigator.clipboard.writeText(t).then(() => { b.textContent = "已复制"; setTimeout(() => b.textContent = b.dataset.m === "b" ? "复制（代入参数）" : "复制原语句", 1200); });
    });
  } catch (e) { box.innerHTML = errBox(e); }
}
// 取数 SQL：直接从 B1 单据算出某个结果的独立语句，放在 srcsql/*.sql（分段写、带中文注释），actions.json 用 sqlFile 登记。
// 页面上显示语句、可复制到 HANA Studio、可在只读事务中执行，并与本次计算结果逐行比对（resultSql 替换文件中 -- @result 之后的输出）。用户 2026-10-19
// list：[{title, action, diff}]，一页可以有几条（如订单 + 委外加工费）
const SRCSQL = {
  ap:     [{title:"应付暂估", action:"srcApAccr", diff:"srcApAccrDiff"}],
  goods:  [{title:"发出商品", action:"srcGoodsOut", diff:"srcGoodsOutDiff"}],
  inv:    [{title:"收发存", action:"srcInvLine", diff:"srcInvLineDiff"}],
  ledger: [{title:"收发存", action:"srcInvLine", diff:"srcInvLineDiff"}],
  orders: [{title:"订单", action:"srcOrder", diff:"srcOrderDiff"}, {title:"委外加工费", action:"srcSubfee", diff:"srcSubfeeDiff"}],
  wip:    [{title:"订单", action:"srcOrder", diff:"srcOrderDiff"}, {title:"委外加工费", action:"srcSubfee", diff:"srcSubfeeDiff"}],
  exp:    [{title:"费用归集", action:"srcExp", diff:"srcExpDiff"}],
};
function srcSqlBar(pane, list, fc, runId){
  pane.querySelectorAll(":scope > .srcbar").forEach(x => x.remove());
  if (!list || !fc) return;
  const bar = document.createElement("div"); bar.className = "bar srcbar";
  bar.innerHTML = `<span class="hint">想看这些数从 B1 哪些单据、按什么规则取出来：</span>`
    + list.map((o, k) => `<button class="btn" data-k="${k}">${esc(o.title)} · 取数 SQL</button>`).join("");
  pane.prepend(bar);
  bar.querySelectorAll("button").forEach(b => b.onclick = () => showSrcSql({...list[Number(b.dataset.k)], fc, runId}));
}
async function showSrcSql(o){
  const box = drawer(`${o.title} · 取数 SQL`);
  box.innerHTML = `<div class="empty">加载中…</div>`;
  try {
    if (!SQLDEF.has(o.action)) SQLDEF.set(o.action, await api("/api/sql", {action:o.action}));
    const d = SQLDEF.get(o.action), bound = sqlBind(d.sql, [o.fc]);
    box.innerHTML = `<p class="hint">这条语句只读 B1 单据（文件 <span class="mono">tools/console/srcsql/</span>），按 ①②③… 分段写，每段开头的注释说明这一步取什么、按什么规则算。`
      + `复制到 HANA Studio 可以直接执行；排查时把最后一句 <span class="mono">SELECT</span> 换成 <span class="mono">SELECT * FROM 某一段的名字</span>（如 ②、③ 段开头的名字），看那一步的中间结果。文件开头写明了哪些数不在这条语句里（由计算产生）。`
      + `它与新框架的计算过程是同一口径，“与计算结果比对”逐行核对两边是否一致。</p>`
      + `<p class="hint">账期 <span class="mono">${esc(o.fc)}</span></p>`
      + `<div class="bar"><button class="btn" data-m="run">执行取数</button>${o.diff ? `<button class="btn" data-m="diff">与计算结果比对</button>` : ""}<span class="sp"></span>`
      + `<button class="btn" data-m="cb">复制（代入账期）</button><button class="btn" data-m="cr">复制原语句</button></div>`
      + `<div class="sres"></div>` + preBox(bound);
    const res = box.querySelector(".sres");
    box.querySelectorAll("[data-m]").forEach(b => b.onclick = async () => {
      const m = b.dataset.m;
      if (m === "cb" || m === "cr") {
        if (navigator.clipboard) navigator.clipboard.writeText(m === "cb" ? bound : d.sql).then(() => { const t = b.textContent; b.textContent = "已复制"; setTimeout(() => b.textContent = t, 1200); });
        return;
      }
      res.innerHTML = `<div class="empty">执行中…</div>`;
      try {
        if (m === "run") {
          const r = await q(o.action, {fc:o.fc}, true);
          res.innerHTML = `<h3>取数结果</h3>` + table(r, {empty:"没有数据"});
        } else {
          const r = await q(o.diff, {fc:o.fc, runId:o.runId}, true);
          res.innerHTML = `<h3>与计算结果比对（运行 ${esc(o.runId)}）</h3><p class="hint">只列有差异的行，0 行表示两边一致。“只在取数 SQL / 只在计算结果”是一边有、一边没有的暂估行。`
            + `计算之后 B1 里又新增、修改或取消了单据，或改了费用池 / 参数配置，也会出现差异，这时先重新计算再比。</p>` + table(r, {empty:"两边一致"});
        }
      } catch (e) { res.innerHTML = errBox(e); }
    });
  } catch (e) { box.innerHTML = errBox(e); }
}
// 代码列：显示“代码 + 中文名”（导出 Excel 同样带中文名）。交易类型、凭证代码、业务类型、规则、校验、费用池、科目（OACT）的名称从数据库读取，其余是固定代码。
const DICT = {TRANS:{}, BUSI:{}, RULE:{}, CHECK:{}, POOL:{}, ACCT:{}};
const PRICESRC = {WAVG:"本期加权单价", QCPRICE:"期初维护价兜底", OPEN:"期初单价（本期无计价入库）", ZERO:"无价"};
const CAT = {FIX:"固定金额", NOCOST:"不参与单价", SRT:"按原交货成本", SRTQ:"无原单退货按维护价", CNL:"取消单按原单", TRF_IN:"形态转换入库", RCPT:"订单完工入库", ISSUE:"订单领料", RTN304:"生产退料", B1:"取 B1 金额", WAVG:"本期加权单价"};
const OBJ = {"13":"应收发票", "14":"应收贷项", "15":"销售交货", "16":"销售退货", "18":"应付发票", "19":"应付贷项", "20":"采购收货", "21":"采购退货", "59":"收货单", "60":"发货单", "67":"库存转储", "162":"库存重估", "202":"生产订单", "MTC_OWOR":"返工单", "MTC_OMRV":"重估单", INV:"应收发票", RIN:"应收贷项", OMRV:"重估单", "24":"收款", "30":"日记账", "46":"付款", "-2":"期初余额"};
const LEVELSRC = {NOBOM:"无 BOM", BOM:"按 BOM", OVR:"手工指定"};
const ACCR = {MAT:"材料", SUBFEE:"委外加工费"};
const SRCALL = {JDT:"凭证", MRV:"库存重估", SHARED:"公摊材料", CLOSEDIF:"关单差异", PDN:"加工费收货", RPD:"加工费退货", PROWW:"委外重估", GL:"总账已过账", VCH:"未清凭单", DRAFT:"底稿", BEG:"期初", BOOT:"期初承接", PREV:"上期新框架", OIVL:"库存记录", OMRV:"重估单", APDIF:"委外发票差异"};
const STAGE = {PRE:"计算前", POST:"计算后"};
const GOODSPART = {REV:"① 冲销上月计提", DN01:"② 发货", SAMPLE:"③ 样品转出", DN03:"④ 发票", ACCR:"⑤ 本月计提", OTHER:"其他凭证"};
const CMPKIND = {ITEM_END:"物料期末", ITEM_PRICE:"物料单价", ORDER_COST:"订单成本", WIP:"在产品"};
const CODECOL = {TransCode:() => DICT.TRANS, BizTrans:() => DICT.TRANS, NeedTrans:() => DICT.TRANS, Cat:() => CAT, RuleId:() => DICT.RULE,
  CheckId:() => DICT.CHECK, PoolCode:() => DICT.POOL, BusiType:() => DICT.BUSI, ObjType:() => OBJ, OrderType:() => OBJ, LevelSrc:() => LEVELSRC,
  AccrType:() => ACCR, SuggSrc:() => QCPSRC, SrcType:() => JSRC, Src:() => SRCALL, Area:() => RECON, Elem:() => ELEM, Stage:() => STAGE, Kind:() => CMPKIND,
  WorType:() => WORTYPE, PriceSrc:() => PRICESRC, AcctCode:() => DICT.ACCT, Part:() => GOODSPART, RevOf:() => DICT.TRANS};
const LISTCOL = new Set(["NeedTrans"]);
// 表里已经有名称列时，代码列不再重复显示名称
const NAMECOL = {AcctCode:"AcctName", TransCode:"TransName", PoolCode:"PoolName", CheckId:"Title", ItemCode:"ItemName"};
// 返回 [代码, 名称] 的列表；不是代码列或认不出时返回 null
function codeParts(c, v){
  if (v === null || v === undefined || v === "" || !CODECOL[c]) return null;
  const d = CODECOL[c](), s = String(v);
  if (c === "PriceSrc" && !d[s]) return null;   // 单据行的定价说明是中文句子，里面的代码另行替换
  const codes = LISTCOL.has(c) ? s.split(",").filter(Boolean) : [s];
  if (!codes.some(x => d[x])) return null;
  return codes.map(x => [x, d[x] || ""]);
}
// 校验明细的 KeyCode 以“单据类型-DocNum …”开头时，类型代码后面带中文名（如 16 销售退货-DocNum 123-LineNum 0）
// 新旧比对 / 运行比较中订单类的 KeyCode 是“订单单据-DocEntry”，显示时标出 Entry，旁边另有订单号 Num 列
const ordKeyFmt = kind => /^ORDER/.test(kind) ? {KeyCode: v => esc(String(v ?? "").replace(/^(202|MTC_OWOR)-(\d+)$/, "$1-Entry $2"))} : {};
const keyText = v => String(v ?? "").replace(/^(\d+|MTC_OWOR|MTC_OMRV)(?=-DocNum )/, k => OBJ[k] ? `${k} ${OBJ[k]}` : k);
// 标题等非表格位置：科目编码 + 名称
const acctText = v => !v ? "" : DICT.ACCT[String(v)] ? `${v} ${DICT.ACCT[String(v)]}` : String(v);
const priceSrcText = s => String(s).replace(/（(WAVG|QCPRICE|OPEN|ZERO)）/g, (m, k) => `（${k} ${PRICESRC[k]}）`);
function codeHtml(c, v){
  const p = codeParts(c, v);
  if (p) return p.map(([k, n]) => `<span class="mono">${esc(k)}</span>${n ? ` <span class="hint">${esc(n)}</span>` : ""}`).join("、");
  if (c === "PriceSrc" && v) return esc(priceSrcText(v));
  return null;
}
function codeText(c, v){
  const p = codeParts(c, v);
  if (p) return p.map(([k, n]) => n ? `${k} ${n}` : k).join("、");
  if (c === "PriceSrc" && v) return priceSrcText(v);
  return v;
}
async function loadDict(){
  try { for (const x of asObjs(await q("codeDict"))) if (DICT[x.Dict] && x.Code !== null) DICT[x.Dict][String(x.Code)] = x.Name || ""; } catch (e) {}
}
