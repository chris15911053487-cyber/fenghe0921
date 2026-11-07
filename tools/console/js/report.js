// 成本执行台 · report.js — 运行比较（指标快照）、计算说明（本地模板）
// index.html 按顺序加载 js/ 下的脚本，共用全局作用域；加载时立即执行的代码只能用到本文件和前面文件里的名字。
"use strict";
// ---------------- 运行比较（指标快照 MTC_CA_RUN_KPI） ----------------
const KPI = {ITEM_PRICE:"物料单价", ITEM_END_AMT:"物料期末金额", ORDER_COST:"订单完工成本", ORDER_WIP:"订单在产品", POOL:"费用池",
  TOTAL_END_AMT:"期末库存合计", TOTAL_WIP:"在产品合计", TOTAL_CLOSEDIF:"关单差异合计"};
const runLabel = r => `#${r.RunId} ${r.FcCode} ${r.RunType === "F" ? "正式" : r.RunType === "H" ? "历史（旧框架回填）" : "模拟 " + (r.Scenario || "")} · ${RUNST[r.Status] || r.Status}`;
async function renderKpi(pane, id){
  const others = RUNS.filter(r => r.RunId !== SEL.RunId && r.Status === "OK");
  if (SEL.Status !== "OK") { pane.innerHTML = latestNote(); return; }
  if (!others.length) { pane.innerHTML = `<div class="empty">没有别的成功运行可以比较</div>`; return; }
  const def = others.find(r => r.FcCode === SEL.FcCode) || others[0];
  pane.innerHTML = `<p class="hint">用每次运行保存的指标快照比较两次运行（同一账期的正式与模拟、重算前后、相邻两期都可以）。差额 = 本次 − 对比运行。</p>
    <div class="bar"><label class="hint">对比运行</label><select id="kpiOther">${others.map(r => `<option value="${r.RunId}" ${r === def ? "selected" : ""}>${esc(runLabel(r))}</option>`).join("")}</select></div>
    <div id="kpiSum"></div>`;
  const load = async () => {
    const id2 = $("#kpiOther").value;
    $("#kpiSum").innerHTML = `<div class="empty">加载中…</div>`; closeDrawer();
    try {
      const r = await q("kpiCmpSummary", {runId:id, runId2:id2});
      $("#kpiSum").innerHTML = table(r, {onRow:true, fmt:{KpiType: v => `${esc(KPI[v] || v)} <span class="hint mono">${esc(v)}</span>`}, empty:"两次运行都没有指标"});
      bindRows($("#kpiSum"), r, c => searchList(drawer(KPI[c.KpiType] || c.KpiType), "kpiCmpList", {runId:id, runId2:id2, kind:c.KpiType}, `${KPI[c.KpiType] || c.KpiType}：有差异的项`, {fmt:ordKeyFmt(c.KpiType)}, "编码开头"));
    } catch (e) { $("#kpiSum").innerHTML = errBox(e); }
  };
  $("#kpiOther").onchange = load; load();
}

// ---------------- 计算说明（本地模板，cost.report） ----------------
const n2 = v => v === null || v === undefined ? "" : Number(v).toLocaleString("zh-CN", {minimumFractionDigits:2, maximumFractionDigits:2});
function htmlTable(r, cols, fmt = {}){
  if (!r || !r.rows.length) return "<p>（无）</p>";
  const idx = cols.map(c => r.columns.indexOf(c));
  return "<table><thead><tr>" + cols.map(c => `<th>${esc(LABEL[c] || c)}</th>`).join("") + "</tr></thead><tbody>"
    + r.rows.map(x => "<tr>" + idx.map((i, k) => { const v = x[i]; const f = fmt[cols[k]];
        return `<td${typeof v === "number" ? ' class="n"' : ""}>${f ? f(v, x) : typeof v === "number" && !["StepNo","RowCnt","IssueCnt","Lines","Cnt","NoReason","Iter"].includes(cols[k]) ? n2(v) : esc(v)}</td>`; }).join("") + "</tr>").join("")
    + "</tbody></table>";
}
async function buildReport(run){
  const id = String(run.RunId), ok = run.Status === "OK";
  const g = (a, args) => q(a, args).catch(() => null);
  const [steps, iters, checks, kpis, pools, cmps, jdts, goods, aps] = await Promise.all([
    g("steps", {runId:id}), g("iters", {runId:id}), g("checks", {runId:id}), ok ? g("kpiTotals", {runId:id}) : null,
    ok ? g("poolSummary", {runId:id, runId2:id}) : null, ok ? g("cmpSummary", {runId:id}) : null, ok ? g("jdtSummary", {runId:id}) : null,
    ok ? g("goodsOutSum", {runId:id}) : null, ok ? g("apAccrSum", {runId:id}) : null]);
  const co = checks ? asObjs(checks) : [];
  const bad = co.filter(c => c.Result === "FAIL" || c.Result === "WARN");
  const kv = kpis ? Object.fromEntries(asObjs(kpis).map(k => [k.KpiType, k.Value])) : {};
  const poolO = pools ? asObjs(pools) : [];
  const unalloc = poolO.reduce((a, p) => a + Number(p.Unalloc || 0), 0);
  const jdtO = jdts ? asObjs(jdts) : [];
  const unbal = jdtO.filter(j => Math.abs(Number(j.Diff || 0)) > 0.001 || Number(j.NoAcct || 0) > 0);
  let h = `<h1>成本计算说明 · ${esc(run.FcCode)}</h1>
<p>账套 ${esc(INFO.schema)}；运行 #${run.RunId}（${run.RunType === "F" ? "正式" : run.RunType === "H" ? "历史（旧框架回填）" : "模拟，场景 " + esc(run.Scenario)}）；状态：${esc(RUNST[run.Status] || run.Status)}；
${esc(run.StartTime || "")} 至 ${esc(run.EndTime || "")}；操作人 ${esc(run.UserCode || "")}；迭代 ${run.IterCount ?? "-"} 轮${run.Converged === "Y" ? "，已收敛" : ""}。</p>
<p>${esc(run.Msg || "")}</p>
<h2>一、结论</h2><ul>
<li>计算前 / 后校验：共 ${co.length} 项，未通过 ${co.filter(c => c.Result === "FAIL").length} 项，警告 ${co.filter(c => c.Result === "WARN").length} 项。</li>`;
  if (ok) h += `<li>期末库存合计 ${n2(kv.TOTAL_END_AMT)}；在产品合计 ${n2(kv.TOTAL_WIP)}；本期关单差异 ${n2(kv.TOTAL_CLOSEDIF)}。</li>
<li>费用池未分摊合计 ${n2(unalloc)}${Math.abs(unalloc) > 0.005 ? "（不为 0，见第四节，按 Q13 由财务决定处理）" : "（已全部分摊）"}。</li>
<li>凭证：${jdtO.length} 种凭证代码${unbal.length ? `，其中 ${unbal.map(j => esc(j.TransCode)).join("、")} 借贷不平或缺科目，需先查` : "，借贷平衡、科目齐全"}。凭证只生成到 MTC_CA_R_JDT，过账在库外完成。</li>`;
  h += `</ul><h2>二、步骤</h2>` + htmlTable(steps, ["StepNo","StepCode","Status","RowCnt","Sec","Msg"], {StepCode: v => esc((STEP[v] || v) + " " + v), Status: v => esc(RUNST[v] || v)})
    + (iters && iters.rows.length ? `<h3>迭代</h3>` + htmlTable(iters, ["Iter","MaxPriceDelta","PoolDelta","CloseDifDelta","UnconvItems"]) : "")
    + `<h2>三、未通过和有警告的校验</h2>` + (bad.length ? htmlTable({columns:checks.columns, rows:checks.rows.filter(x => ["FAIL","WARN"].includes(x[checks.columns.indexOf("Result")]))},
        ["CheckId","Title","Result","IssueCnt","IsBlock","TroublePath"], {Result: v => esc(CHKST[v] || v), IsBlock: v => v === "Y" ? "阻断" : ""}) : "<p>全部通过。</p>");
  if (ok) h += `<h2>四、费用归集与分摊</h2>` + htmlTable(pools, ["PoolCode","PoolName","Elem","SrcJDT","SrcMRV","SrcPROWW","SrcSHARED","SrcCLOSEDIF","SrcWWHIST","PoolAmt","AllocAmt","Unalloc","OrderCnt"], {Elem: v => esc(ELEM[v] || v)})
    + `<h2>五、新旧比对</h2>` + htmlTable(cmps, ["Kind","Cnt","AbsDiff","NoReason"])
    + `<h2>六、凭证</h2>` + htmlTable(jdts, ["TransCode","TransName","Lines","Debit","Credit","Diff","NoAcct"])
    + `<h2>七、发出商品与应付暂估</h2>` + htmlTable(goods, ["CustType","IsSample","Lines","OpenQty","CostAmt","NoCost"], {IsSample: v => v === "Y" ? "样品" : ""})
    + htmlTable(aps, ["AccrType","Lines","Vendors","OpenAmt"], {AccrType: v => esc({MAT:"材料", SUBFEE:"委外费用"}[v] || v)});
  h += `<p class="foot">由成本执行台按本地模板生成（${new Date().toLocaleString("zh-CN")}），数据取自 MTC_CA_* 结果表，未经任何外部服务。</p>`;
  return h;
}
const docCss = `body{font:14px/1.6 "PingFang SC","Microsoft YaHei",sans-serif;max-width:1100px;margin:24px auto;padding:0 16px;color:#16222B}
table{border-collapse:collapse;width:100%;margin:8px 0 16px;font-size:13px}th,td{border:1px solid #CCD5D3;padding:4px 8px;text-align:left;vertical-align:top}
th{background:#E6ECEA}td.n{text-align:right;font-variant-numeric:tabular-nums}h1{font-size:22px}h2{font-size:18px;margin-top:28px}h3{font-size:15px}.foot{color:#5B6970;font-size:12px;margin-top:32px}`;
function download(name, bodyHtml, title){
  const html = `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${esc(title)}</title><style>${docCss}</style></head><body>${bodyHtml}</body></html>`;
  const a = document.createElement("a"); a.href = URL.createObjectURL(new Blob([html], {type:"text/html"})); a.download = name + ".html"; a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}
async function renderReport(pane){
  const run = SEL;
  pane.innerHTML = `<div class="bar"><p class="hint" style="margin:0">本期计算说明：按本地模板汇总这次运行的步骤、校验、费用、比对和凭证，可下载保存或打印。</p><span class="sp"></span><button class="btn" id="repDl" disabled>下载 HTML</button></div><div id="rep" class="report"><div class="empty">生成中…</div></div>`;
  try {
    const h = await buildReport(run);
    if (SEL !== run) return;
    $("#rep").innerHTML = h;
    $("#repDl").disabled = false;
    $("#repDl").onclick = () => download(`成本计算说明_${INFO.schema}_${run.FcCode}_${run.RunId}`, h, `成本计算说明 ${run.FcCode}`);
  } catch (e) { $("#rep").innerHTML = errBox(e); }
}
