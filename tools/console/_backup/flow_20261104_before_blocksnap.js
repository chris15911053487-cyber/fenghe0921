// 成本执行台 · flow.js — 计算过程示意图（FLOW 节点、FLINES 连线）
// index.html 按顺序加载 js/ 下的脚本，共用全局作用域；加载时立即执行的代码只能用到本文件和前面文件里的名字。
"use strict";
// 计算过程示意图（用户 2026-10-18 选定 Claude Design 样稿 A 版）：节点是 HTML 按钮，按固定坐标排在 FW × FH 的画布上，
// 连线是垫在下面的一张 SVG；整张图按窗口宽度等比缩小，窄于 720px 时改成单列卡片（不画线）。
// 节点状态取 MTC_CA_RUN_STEP；P41–P47 和 a–e 是 P40 里的小步，状态跟随 P40，运行中按进度说明（MTC_CA_P_LOG_NOTE）标出当前小步。
// 金额只在运行成功时显示（flowAmts、jdtSummary）；“只看流程”不取运行数据。节点和代码的对应以 新框架/sql/10_run_entry.sql、13_p40_iter.sql 为准
const FW = 1200, FH = 1040;
const yuan = v => v === null || v === undefined ? "" : "¥" + fmtNum(Math.round(Number(v) * 100) / 100);
const FLOW = [
  {k:"P00", t:"P00 准备", x:0, y:80, w:200, h:96, codes:["P00"], d:"账期锁定、参数、并发检查",
   long:"检查账期是否锁定、参数是否齐全、同一账期有没有正在运行的计算，写运行头。", proc:["MTC_CA_P_RUN", "MTC_CA_P_RUN_BEGIN"], wr:"MTC_CA_RUN、MTC_CA_RUN_STEP", old:"MTC_COST_PROC_0000（入口）", tab:"steps"},
  {k:"P20", t:"P20 快照", x:248, y:80, w:200, h:96, codes:["P05", "P20*"], main:"P20_LINE", d:"截至期末取单据、订单、费用",
   long:"按截至期末从 B1 取库存变动、订单、费用来源、委外加工费、应付暂估变动、工时和维护价、期初，写入快照表；开头由 P05 把 B1 里维护的费用池和计算参数同步过来。之后的计算只读快照。",
   proc:["MTC_CA_P20_SNAPSHOT", "MTC_CA_P05_CFG_SYNC"], rd:"B1 单据和总账、@MTC_CA_POOL / @MTC_CA_EXPSET、上期结果或期初承接", wr:"MTC_CA_S_*", old:"0201_DOCDETAIL、0301_INVNT、0303_INVNTDETAIL2、0321_OWOR", tab:"b1cfg"},
  {k:"P10", t:"P10 计算前检查", x:496, y:80, w:200, h:96, codes:["P10"], d:"PRE 检查，有阻断项就停止",
   long:"在快照上执行全部计算前检查（只读）。有阻断项就停止本次运行：保留检查结果，删除快照。PRE-23 另外列出需要维护期初成本价的物料（警告，不阻断）；PRE-14 没有工时的产品按物料汇总成“工时维护”清单。",
   proc:["MTC_CA_P10_PRECHECK", "MTC_CA_P10_QCP", "MTC_CA_P10_HOURS"], rd:"MTC_CA_S_*、MTC_CA_C_CHECK、@MTC_COST_TIME", wr:"MTC_CA_R_CHECK、MTC_CA_R_CHECK_DTL、MTC_CA_R_QCP_NEED、MTC_CA_R_HOURS_NEED", old:"MTC_COST_PROC_CAL_1001_CHECK", tab:"checks", stage:"PRE"},
  {k:"STOP", t:"停止", x:496, y:0, w:200, h:52, codes:[], kind:"stop", d:"保留检查结果、删除快照",
   long:"计算前检查有阻断项时运行到这里结束，状态为“检查阻断”。处理完阻断项后重新发起计算。", proc:["MTC_CA_P_RUN_CLEAN"], tab:"checks"},
  {k:"P30", t:"P30 固定价格", x:744, y:80, w:200, h:96, codes:["P30"], d:"采购、发票差额、重估、配对",
   long:"建本次运行的结果行，给不随迭代变化的交易定价：采购入库、发票差额、重估、期初生产入库；配对取消单和形态转换，标记不计价的行。",
   proc:["MTC_CA_P30_INIT"], rd:"MTC_CA_S_*", wr:"MTC_CA_R_LINE、MTC_CA_R_ITEM、MTC_CA_R_ORDER、MTC_CA_R_ORDER_MAT、MTC_CA_R_PAIR", old:"0302_INVNTDETAIL1、0303_INVNTDETAIL2 的固定价格部分", tab:"items", chk:["POST-05"],
   amt: a => `期初 ${yuan(a.OpenAmt)}`},
  {k:"P31", t:"P31 场景假设", x:992, y:80, w:200, h:96, codes:["P31"], d:"只在模拟运行时执行",
   long:"模拟运行时把场景里的假设套到快照和初始结果上；正式运行跳过这一步。", proc:["MTC_CA_P31_SCENARIO"], rd:"MTC_CA_C_SCENARIO*", tab:"scen"},
  {k:"P40", t:"P40 迭代", x:200, y:262, w:760, h:30, codes:["P40"], kind:"hdr",
   long:"每一轮都从快照重算：P41 预定价 → P42 费用池 → P43 分摊 → P45 逐级（L = 0 … 最高层）→ P47 收敛判断，只把上一轮的物料单价和关单差异带进下一轮。收敛条件：所有物料单价变化 ≤ 0.000001，费用池、关单差异变化 ≤ 0.01；到最大轮数仍未收敛时状态为“未收敛”，不写结果。",
   proc:["MTC_CA_P40_ITERATE"], wr:"MTC_CA_RUN_ITER", old:"0401_CAL 六段 + 返工段、旧流程的“算两遍”", tab:"steps"},
  {k:"P41", t:"P41 预定价", x:40, y:316, w:200, h:96, parent:"P40", sub:/P41/, d:"用上一轮物料加权单价；第 1 轮用维护价或上期单价",
   long:"加权价类的行（含公摊材料行）按物料当前单价定价。", proc:["MTC_CA_P41_PRICE"], rd:"MTC_CA_R_ITEM（当前单价）", wr:"MTC_CA_R_LINE", old:"0401 各级的“价格写入领料行”", tab:"items"},
  {k:"P42", t:"P42 费用池", x:288, y:316, w:200, h:96, parent:"P40", sub:/P42/, d:"凭证、公摊材料、关单差异",
   long:"把本期凭证费用、公摊材料（按 P41 的价格）、上一轮的关单差异和重估，归入各费用池的制造费用、人工两项。", proc:["MTC_CA_P42_POOL"],
   rd:"MTC_CA_S_EXP、MTC_CA_R_LINE（公摊材料行）、MTC_CA_R_ORDER（关单差异）、MTC_CA_C_POOL*", wr:"MTC_CA_R_POOL", old:"0311_PRODUCTEXP_ADD", tab:"exp", chk:["POST-03"],
   amt: a => `${yuan(a.PoolAmt)}${Number(a.PoolCloseDif) ? `<br>其中关单差异 ${yuan(a.PoolCloseDif)}` : ""}`},
  {k:"P43", t:"P43 分摊到订单", x:536, y:316, w:200, h:96, parent:"P40", sub:/P43/, d:"按工时直接分摊",
   long:"各费用池按分摊范围和工时直接分摊到订单（制造费用、人工）。没有工时的在计算前检查阻断；未分摊的报出，不转下期。", proc:["MTC_CA_P43_ALLOC"],
   rd:"MTC_CA_R_POOL、MTC_CA_S_HOURS、MTC_CA_C_POOL_TGT", wr:"MTC_CA_R_ALLOC、MTC_CA_R_ORDER（AllocMfg / AllocLab）", old:"0312_PRODUCTEXP_PRC", tab:"pool", chk:["POST-03"],
   amt: a => `${yuan(a.AllocAmt)} · 未分摊 ${yuan(Number(a.PoolAmt) - Number(a.AllocAmt))}`},
  {k:"P45", t:"P45 逐级计算", x:200, y:464, w:760, h:30, parent:"P40", sub:/P45/, kind:"hdr",
   long:"对 L = 0 … 最高层逐层做 a → e：本层订单领料按子件当前单价计价，订单 × 材料结转，算订单完工成本并分到入库行，最后算本层物料的加权单价，供上一层领用。同层和上层（返工单）用上一轮单价，靠迭代收敛。",
   proc:["MTC_CA_P45_LEVEL"], rd:"MTC_CA_R_LINE、MTC_CA_R_ORDER_MAT、MTC_CA_R_ITEM", wr:"MTC_CA_R_LINE、MTC_CA_R_ORDER_MAT、MTC_CA_R_ORDER、MTC_CA_R_ITEM",
   old:"0401_CAL 各级、0402_CAL_OWOR(_30)、0306_WW、CO4001 / CO4011", tab:"orders"},
  {k:"La", t:"a 领料计价", x:64, y:508, w:160, h:80, parent:"P40", sub:/P45/, lv:true, d:"按子件当前单价", tab:"orders", proc:["MTC_CA_P45_LEVEL"]},
  {k:"Lb", t:"b 订单 × 材料结转", x:254, y:508, w:160, h:80, parent:"P40", sub:/P45/, lv:true, d:"在产品、关单差异", tab:"wip", proc:["MTC_CA_P45_LEVEL"], chk:["POST-04", "POST-13", "POST-06"],
   long:"本期有入库时 结转 = 累计领料 × 完工比例 − 以前已结转（加工费比例取 1）；在产品 = 累计领料 − 累计结转；本期关单订单的在产品转关单差异，下一轮进费用池。",
   amt: a => `在产品 ${yuan(a.WipAmt)}`},
  {k:"Lc", t:"c 订单完工成本", x:444, y:508, w:160, h:80, parent:"P40", sub:/P45/, lv:true, d:"材料＋费用＋加工费", tab:"orders", proc:["MTC_CA_P45_LEVEL"], chk:["POST-04"],
   amt: a => `完工 ${yuan(a.CostAmt)}`},
  {k:"Ld", t:"d 完工入库", x:634, y:508, w:160, h:80, parent:"P40", sub:/P45/, lv:true, d:"分到入库行，挤尾差", tab:"ledger", proc:["MTC_CA_P45_LEVEL"]},
  {k:"Le", t:"e 物料加权单价", x:824, y:508, w:160, h:80, parent:"P40", sub:/P45/, lv:true, d:"含形态转换", tab:"items", proc:["MTC_CA_P45_LEVEL"], chk:["POST-07", "POST-14"]},
  {k:"P47", t:"P47 收敛？", x:1016, y:492, w:160, h:112, parent:"P40", sub:/P47|轮完成/, kind:"dia",
   long:"比较本轮和上一轮：物料单价最大变化、费用池合计变化、关单差异合计变化都在收敛条件以内就结束迭代，否则带上本轮单价和关单差异再算一轮。每轮的变化见下面的迭代表。",
   proc:["MTC_CA_P40_ITERATE"], wr:"MTC_CA_RUN_ITER", tab:"steps"},
  {k:"P50", t:"P50 定稿", x:0, y:752, w:270, h:104, codes:["P50"], d:"进销存四项、尾差、料工费占比",
   long:"按最终单价给加权价行定价，汇总物料进销存四项；期末数量为 0 而金额不为 0 的尾差挤进出库行，挤不进且在 TAIL_MAX 以内的转 JZ04；最后写料工费占比，并由 P55 列出“库存重估”清单（只写清单，不写 B1）。",
   proc:["MTC_CA_P50_FINALIZE", "MTC_CA_P55_REVAL"], rd:"MTC_CA_R_LINE、MTC_CA_R_PAIR", wr:"MTC_CA_R_ITEM、MTC_CA_R_LINE、MTC_CA_R_REVAL_NEED", old:"0401 末尾“91 写入”和入库尾差处理", tab:"inv", chk:["POST-01", "POST-02", "POST-07", "POST-14"],
   amt: a => `${Math.abs(Number(a.BalDiff)) < 0.005 ? "期初＋入库−出库＝期末 ✓" : `<b class="bad">四项不平 ${fmtNum(a.BalDiff)}</b>`}<br>期末 ${yuan(a.EndAmt)}`},
  {k:"P60", t:"P60 计算后校验", x:310, y:752, w:270, h:104, codes:["P60"], d:"POST 校验，写指标快照",
   long:"执行计算后校验（不通过即阻断，结果保留供排查，处理前不能过账），并写本次运行的指标快照，供“运行比较”使用。",
   proc:["MTC_CA_P60_POSTCHECK"], chk:["POST-01", "POST-02", "POST-03", "POST-04", "POST-05", "POST-07", "POST-14", "BOOT-01"], wr:"MTC_CA_R_CHECK、MTC_CA_R_CHECK_DTL、MTC_CA_RUN_KPI", old:"CAL_1004_CHECK(_LS)、CO4004、C01–C18", tab:"checks"},
  {k:"P65", t:"P65 新旧比对", x:620, y:752, w:270, h:104, codes:["P65"], d:"与旧框架同一账期比对",
   long:"旧框架同一账期已运行时，逐物料、逐订单比较新旧结果，差额 > 0.01 的写比对表并归因。", proc:["MTC_CA_P65_COMPARE"], wr:"MTC_CA_R_CMP", tab:"cmp"},
  {k:"P71", t:"P71 发出商品", x:930, y:752, w:270, h:104, codes:["P71"], d:"交货成本、未开票交货计提",
   long:"按截至期末算交货 / 退货成本和未开票交货，生成发出商品明细，供 P70 生成 DN、AR03 / AR04 凭证。", proc:["MTC_CA_P71_SALES"],
   wr:"MTC_CA_R_GOODS_OUT、MTC_CA_R_GOODS_OUT_BEG、MTC_CA_R_GOODS_MOVE、MTC_CA_R_DNCOST", old:"0801 的 DN01–DN04、AR03 / AR04", tab:"goods", chk:["POST-10", "POST-12"]},
  {k:"P73", t:"P73 / P74 应付暂估", x:0, y:920, w:270, h:104, codes:["P73", "P74"], main:"P73", d:"暂估计提与冲回 PUR1–PUR5",
   long:"P73 按截至期末算各供应商的应付暂估，P74 生成 PUR1–PUR5 凭证底稿（计提、开票冲回、冲销系统收退货凭证）。", proc:["MTC_CA_P73_AP_ACCR", "MTC_CA_P74_AP_JDT"],
   rd:"MTC_CA_S_AP_MOVE", wr:"MTC_CA_R_AP_ACCR、MTC_CA_R_JDT", old:"6101_1（PUR1–PUR5）、FI5009", tab:"ap", chk:["POST-11", "POST-15"]},
  {k:"P70", t:"P70 凭证", x:310, y:920, w:270, h:104, codes:["P70"], d:"生成 MR、PP、WW、JZ 等凭证底稿",
   long:"按结果生成成本凭证底稿和每条分录的业务来源；实际过账在库外完成。", proc:["MTC_CA_P70_JDT"], rd:"MTC_CA_R_*", wr:"MTC_CA_R_JDT、MTC_CA_R_JDT_SRC", old:"0801_TOOJDT", tab:"jdt", chk:["POST-08"],
   amt: (a, x) => x.jdt ? `${x.jdt.length} 种凭证 · ${x.jdt.some(j => Math.abs(Number(j.Diff || 0)) > 0.001) ? `<b class="bad">借贷不平</b>` : "借贷平衡"}` : ""},
  {k:"P75", t:"P75 凭证与暂估校验", x:620, y:920, w:270, h:104, codes:["P75"], d:"凭证借贷、科目、财务对账",
   long:"检查凭证底稿借贷平衡、科目齐全，并按财务对账口径核对存货、在产品、委外、发出商品、应付暂估（不通过即阻断）。", proc:["MTC_CA_P75_POSTCHECK"],
   rd:"MTC_CA_R_JDT、总账", wr:"MTC_CA_R_CHECK、MTC_CA_R_CHECK_DTL", old:"CAL_1005、C16、C18–C20", tab:"recon", chk:["POST-06", "POST-08", "POST-09", "POST-10", "POST-11", "POST-12", "POST-13"]},
  {k:"P80", t:"P80 收尾", x:930, y:920, w:270, h:104, codes:["P80"], d:"删除同运行键下的旧明细，运行状态 = 成功",
   long:"删除同账期、同运行类型、同场景下旧运行的明细（上一次成功的结果被这次替换），运行状态改为成功。", proc:["MTC_CA_P_RUN_CLEAN", "MTC_CA_P_RUN_END"], tab:"steps"},
];
// 连线：点列（最后一点是箭头尖）；n 主流程、s 阻断分支、l 下一层、b 下一轮
const FLINES = [
  ["n", [200,128, 247,128]], ["n", [448,128, 495,128]], ["n", [696,128, 743,128]], ["n", [944,128, 991,128]],
  ["s", [596,80, 596,53]],
  ["n", [1092,176, 1092,216, 100,216, 100,315]],
  ["n", [240,364, 287,364]], ["n", [488,364, 535,364]],
  ["n", [636,412, 636,434, 144,434, 144,507]],
  ["n", [224,548, 253,548]], ["n", [414,548, 443,548]], ["n", [604,548, 633,548]], ["n", [794,548, 823,548]], ["n", [984,548, 1015,548]],
  ["l", [904,588, 904,614, 144,614, 144,589]],
  ["b", [1096,492, 1096,292, 180,292, 180,315]],
  ["n", [1096,604, 1096,712, 135,712, 135,751]],
  ["n", [270,804, 309,804]], ["n", [580,804, 619,804]], ["n", [890,804, 929,804]],
  ["n", [1065,856, 1065,888, 135,888, 135,919]],
  ["n", [270,972, 309,972]], ["n", [580,972, 619,972]], ["n", [890,972, 929,972]],
];
const FLABELS = [[608,56,"有阻断"], [474,618,"下一层 L + 1", 100], [1108,330,"否：再算一轮", 84], [1108,628,"是"]];
let FLOW_PLAIN = false; try { FLOW_PLAIN = localStorage.getItem("cc.flowPlain") === "Y"; } catch (e) {}
let FLOW_SEL = null, FLOW_CTX = null;

function flowSvg(){
  const mk = (id, cls) => `<marker id="${id}" orient="auto" markerWidth="5" markerHeight="5" refX="2" refY="2" overflow="visible"><path class="${cls}" d="M0 0 L4 2 L0 4 Z"/></marker>`;
  const path = (k, p) => {
    const n = p.length, x1 = p[n - 2], y1 = p[n - 1], x0 = p[n - 4], y0 = p[n - 3];
    const q = p.slice(); q[n - 2] = x1 - Math.sign(x1 - x0) * 4; q[n - 1] = y1 - Math.sign(y1 - y0) * 4;   // 线停在箭头底下
    let d = ""; for (let i = 0; i < n; i += 2) d += (i ? " L " : "M ") + q[i] + " " + q[i + 1];
    return `<path class="fl-${k}" d="${d}" marker-end="url(#fm-${k})"/>`;
  };
  return `<svg class="flines" width="${FW}" height="${FH}" viewBox="0 0 ${FW} ${FH}" aria-hidden="true"><defs>${mk("fm-n", "fh-n")}${mk("fm-s", "fh-s")}${mk("fm-l", "fh-n")}${mk("fm-b", "fh-b")}</defs>${FLINES.map(([k, p]) => path(k, p)).join("")}</svg>`;
}
// 一个节点对应的步骤记录（"P20*" = 以 P20 开头的小步骤）
const flowRows = (n, steps) => steps.filter(s => (n.codes || []).some(c => c.endsWith("*") ? String(s.StepCode).startsWith(c.slice(0, -1)) : s.StepCode === c));
function flowState(n, x){
  if (!x) return "PLAIN";
  if (n.kind === "stop") return x.byCode.P10 && ["FAIL", "BLOCKED"].includes(x.byCode.P10.Status) ? "FAIL" : "NONE";
  if (n.parent) {
    const p = x.byCode.P40; if (!p) return "NONE";
    if (p.Status !== "RUNNING") return p.Status;
    return n.sub && n.sub.test(p.Msg || "") ? "RUNNING" : "OK0";   // 运行中：当前小步标蓝，其他小步不着色
  }
  const rs = flowRows(n, x.steps); if (!rs.length) return "NONE";
  for (const s of ["RUNNING", "FAIL", "NOCONV", "BLOCKED", "WARN"]) if (rs.some(r => r.Status === s)) return s;
  return "OK";
}
const FST = {OK:"完成", RUNNING:"运行中", FAIL:"失败", BLOCKED:"阻断", NOCONV:"未收敛", WARN:"有警告", NONE:"未执行", OK0:""};
function flowMetric(n, x){
  if (!x) return "";
  if (n.kind === "stop") return "";
  if (n.k === "P47") { const it = x.iters.length; return it ? `第 ${it} 轮：${x.byCode.P40 && x.byCode.P40.Status === "OK" ? "是" : x.byCode.P40 && x.byCode.P40.Status === "RUNNING" ? "计算中" : "否"}` : ""; }
  if (n.k === "P40") { const p = x.byCode.P40; if (!p) return ""; return `本次 ${x.iters.length} 轮${p.Status === "OK" ? "，已收敛" : p.Status === "RUNNING" ? `，${esc(p.Msg || "")}` : `，${esc(FST[p.Status] || p.Status)}`}`; }
  const parts = [];
  if (x.amts && n.amt) { const h = n.amt(x.amts, x); if (h) parts.push(h); }
  if (!n.parent && !parts.length) {   // 有金额时不再列行数和耗时（卡片放不下，抽屉里有）
    const rs = flowRows(n, x.steps);
    if (rs.length) {
      const sec = rs.reduce((a, r) => a + Number(r.Sec || 0), 0), main = rs.find(r => r.StepCode === (n.main || n.codes[0])) || rs[rs.length - 1];
      const cnt = main.RowCnt !== null && main.RowCnt !== undefined ? `${String(main.Msg || "行数").replace(/（.*$/, "")} ${fmtNum(main.RowCnt)} · ` : "";
      if (main.Status === "RUNNING") parts.push(`<span class="hint">${esc(main.Msg || "运行中…")}</span>`);
      else parts.push(`${cnt}${sec} 秒`);
    }
  }
  return parts.join("<br>");
}
function flowCard(n, x){
  const st = flowState(n, x), sel = FLOW_SEL === n.k ? " sel" : "";
  const pos = `left:${n.x}px;top:${n.y}px;width:${n.w}px;height:${n.h}px`;
  const m = flowMetric(n, x);
  if (n.kind === "hdr") return `<button type="button" class="fhdr${sel}" data-n="${n.k}" style="${pos}"><b>${esc(n.t)}</b>${m ? ` <span class="hint">· ${m}</span>` : ""}</button>`;
  const pill = st === "PLAIN" || st === "OK0" || n.kind === "dia" || n.lv || (n.kind === "stop" && st !== "FAIL") ? "" : n.kind === "stop" ? ` <span class="chip s-FAIL">本次在此停止</span>` : ` <span class="chip s-${st === "NONE" ? "SKIP" : esc(st)}">${esc(FST[st] || st)}</span>`;
  return `<button type="button" class="fn fs-${esc(st)}${n.kind ? " f-" + n.kind : ""}${n.lv ? " f-lv" : ""}${sel}" data-n="${n.k}" style="${pos}"><span class="ft"><b>${esc(n.t)}</b>${pill}</span>`
    + (n.d && n.kind !== "dia" ? `<span class="fd">${esc(n.d)}</span>` : "") + (m ? `<span class="fm">${m}</span>` : "") + `</button>`;
}
async function flowChart(run, pane, quiet){
  const id = String(run.RunId), live = run.Status === "RUNNING", ok = run.Status === "OK";
  let x = null;
  if (!FLOW_PLAIN) {
    const g = (a, args) => q(a, args, live).catch(() => null);
    const [s, it, ck, am, jd] = await Promise.all([q("steps", {runId:id}, live), g("iters", {runId:id}), g("checks", {runId:id}),
      ok ? g("flowAmts", {runId:id}) : null, ok ? g("jdtSummary", {runId:id}) : null]);
    const steps = asObjs(s), byCode = {};
    steps.forEach(r => { byCode[r.StepCode] = r; });
    x = {run, steps, byCode, iters: it ? asObjs(it) : [], itR: it, checks: ck ? asObjs(ck) : [], ckR: ck,
      amts: am && am.rows.length ? asObjs(am)[0] : null, jdt: jd ? asObjs(jd) : null};
  }
  if (SEL !== run || TAB !== "flow") return;
  FLOW_CTX = x;
  const head = x ? `${esc(run.FcCode)} · ${run.RunType === "S" ? "模拟 " + esc(run.Scenario || "") : "正式"} · ${esc(RUNST[run.Status] || run.Status)}${ok ? "" : "（金额只在运行成功时显示）"}` : "只看流程：不显示运行数据";
  pane.innerHTML = `<div class="bar"><span class="hint">${head}</span><span class="sp"></span>`
    + `<span class="flegend"><span class="chip s-OK">完成</span><span class="chip s-WARN">有警告</span><span class="chip s-FAIL">阻断 / 失败</span><span class="chip s-RUNNING">运行中</span><span class="chip s-SKIP">未执行</span></span>`
    + `<label class="hint" style="display:inline-flex;align-items:center;gap:4px;cursor:pointer"><input type="checkbox" id="flowPlain"${FLOW_PLAIN ? " checked" : ""}>只看流程</label></div>`
    + `<div class="fwrap" id="fwrap"><div class="fhost" id="fhost">`
    + `<div class="fbox" style="left:0;top:256px;width:${FW}px;height:424px"></div><div class="fbox2" style="left:40px;top:456px;width:960px;height:184px"></div>`
    + flowSvg() + FLOW.map(n => flowCard(n, x)).join("")
    + FLABELS.map(([lx, ly, t, w]) => `<span class="flab" style="left:${lx}px;top:${ly}px${w ? `;width:${w}px` : ""}">${esc(t)}</span>`).join("")
    + `</div></div><p class="hint">点任一节点，在右侧看这一步做什么、本次运行情况、相关校验和源代码。虚线：回到下一层、下一轮迭代。</p>`;
  $("#flowPlain").onchange = e => { FLOW_PLAIN = e.target.checked; try { localStorage.setItem("cc.flowPlain", FLOW_PLAIN ? "Y" : "N"); } catch (er) {} renderTab(true); };
  $("#fhost").onclick = e => { const b = e.target.closest("button[data-n]"); if (b) flowDrawer(FLOW.find(n => n.k === b.dataset.n)); };
  flowFit();
}
function flowFit(){
  const w = $("#fwrap"), h = $("#fhost"); if (!w || !h) return;
  const cw = w.clientWidth, narrow = cw < 720, s = narrow ? 1 : Math.min(1, cw / FW);
  w.classList.toggle("narrow", narrow);
  h.style.transform = narrow ? "" : `scale(${s})`;
  w.style.height = narrow ? "" : Math.ceil(FH * s) + "px";
}
window.addEventListener("resize", () => { if (TAB === "flow") flowFit(); });
function flowDrawer(n){
  if (!n) return;
  FLOW_SEL = n.k;
  document.querySelectorAll("#fhost [data-n]").forEach(b => b.classList.toggle("sel", b.dataset.n === n.k));
  const d = drawer(n.t), x = FLOW_CTX, tabBtn = document.querySelector(`#tabs button[data-t="${n.tab}"]`);
  const kv = [["做什么", esc(n.long || n.d || "")], ["过程", (n.proc || []).map(p => `<span class="mono">${esc(p)}</span>`).join("、")], ["读", esc(n.rd || "")], ["写", esc(n.wr || "")], ["替代旧过程", esc(n.old || "")]].filter(r => r[1]);
  let h = `<div class="bar"><span class="sp"></span>${tabBtn ? `<button class="btn" id="flowGo">打开“${esc(tabBtn.textContent)}”页 ›</button>` : ""}</div>`
    + `<h3>说明</h3><div class="fkv">${kv.map(([k, v]) => `<span class="hint">${k}</span><span>${v}</span>`).join("")}</div>`;
  if (x) {
    const codes = n.parent ? ["P40"] : n.codes || [];
    const rs = flowRows({codes}, x.steps);
    h += `<h3>本次运行</h3>` + (rs.length ? table({columns: ["StepCode", "Status", "RowCnt", "Msg", "StartTime", "EndTime"], rows: rs.map(r => ["StepCode", "Status", "RowCnt", "Msg", "StartTime", "EndTime"].map(c => r[c]))},
      {fmt:{StepCode: v => `<b>${esc(STEP[v] || v)}</b> <span class="hint mono">${esc(v)}</span>`, Status: chip, StartTime: hms, EndTime: hms}, wrap:["Msg"]}) : `<div class="empty">这一步本次没有执行</div>`);
    if ((n.parent || n.k === "P40") && x.itR && x.itR.rows.length) h += `<h3>每轮迭代</h3>` + table(x.itR);
    // 相关校验：P10 = 全部 PRE；其余按节点登记的编号（P60 / P75 各自执行哪些 POST 见 14_p50_p60_p65.sql、16_p70_jdt.sql）
    const cks = x.checks.filter(c => (n.chk || []).includes(c.CheckId) || (n.stage && c.Stage === n.stage));
    if (cks.length) h += `<h3>相关校验</h3><div id="flowCk"></div>`;
    d.innerHTML = h + `<h3>源代码</h3><div id="flowSrc"></div>`;
    if (cks.length) {
      const r = {columns: x.ckR.columns, rows: x.ckR.rows.filter(rw => cks.some(c => c.CheckId === rw[x.ckR.columns.indexOf("CheckId")])), src: x.ckR.src};
      $("#flowCk").innerHTML = table(r, {hide:["Purpose","TroublePath","Stage"], wrap:["Msg"], fmt:{Result: chkChip, IsBlock: v => v === "Y" ? "阻断" : ""}, onRow:true});
      bindRows($("#flowCk"), r, c => checkDrawer(String(x.run.RunId), c));
    }
  } else d.innerHTML = h + `<h3>源代码</h3><div id="flowSrc"></div>`;
  if ($("#flowGo")) $("#flowGo").onclick = () => { closeDrawer(); TAB = n.tab; try { localStorage.setItem("cc.tab", TAB); } catch (e) {} renderTab(); };
  flowSource(n, $("#flowSrc"));
}
// 源代码取数据库中已部署的定义（与“校验”页的 SQL 同一个查询，SYS.PROCEDURES），默认收起
async function flowSource(n, box){
  const ps = [...new Set(n.proc || [])]; if (!ps.length) { box.innerHTML = `<div class="empty">没有对应的过程</div>`; return; }
  box.innerHTML = `<div class="empty">加载中…</div>`;
  try {
    const all = asObjs(await q("checkSql")), m = Object.fromEntries(all.map(o => [o.ProcName, o.Def]));
    box.innerHTML = ps.map(p => m[p] ? `<details class="fsrc"><summary><span class="mono">${esc(p)}</span> <span class="hint">${String(m[p]).split("\n").length} 行</span></summary><pre>${esc(m[p])}</pre></details>`
      : `<p class="hint"><span class="mono">${esc(p)}</span>：数据库里没有这个过程（还没部署？）</p>`).join("");
  } catch (e) { box.innerHTML = errBox(e); }
}
