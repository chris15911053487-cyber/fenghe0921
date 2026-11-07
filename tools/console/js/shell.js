// 成本执行台 · shell.js — 状态与启动：地址栏链接 / 浏览器后退（#页面?run=&item=&order=）、init()、账期、账期状态、运行列表、运行抬头
// index.html 按顺序加载 js/ 下的脚本，共用全局作用域；加载时立即执行的代码只能用到本文件和前面文件里的名字。
"use strict";
// ---------------- 状态 ----------------
let INFO = null, RUNS = [], SEL = null, TAB = "steps", runType = "F", pollTimer = null;
try { TAB = localStorage.getItem("cc.tab") || "steps"; } catch (e) {}
// 地址栏（用户 2026-10-23）：#页面?run=运行号&item=物料 或 &order=单据类型-Entry，复制给别人可以直接打开同一个内容；
// 切换页面、切换运行、打开物料 / 订单明细都记入浏览器历史，“后退 / 前进”可用。LINK = 抽屉里当前的物料 / 订单（成本追溯页用 TRACE）
function parseUrl(h = location.hash){
  const m = /^#([a-z0-9]+)(?:\?(.*))?$/i.exec(h || ""); if (!m) return null;
  const p = new URLSearchParams(m[2] || ""), u = {tab:m[1], run:p.get("run") || "", co:p.get("co") || "", r:p.get("r") || "", obj:null};
  if (p.get("item")) u.obj = {kind:"item", code:p.get("item")};
  else if (p.get("order")) { const v = p.get("order"), k = v.lastIndexOf("-"); if (k > 0) u.obj = {kind:"order", type:v.slice(0, k), entry:v.slice(k + 1)}; }
  return u;
}
const tabOk = t => !!document.querySelector(`#tabs button[data-t="${t}"]`);
const URL0 = parseUrl();
if (URL0 && tabOk(URL0.tab)) TAB = URL0.tab;
let LINK = null, URL_APPLY = false, URL_READY = false;
let RPT_CUR = URL0 && URL0.r ? URL0.r : null;   // 成本报表页当前报表编号（rpt.js，用户 2026-10-30）
function urlNow(t = TAB){
  const p = new URLSearchParams(), o = t !== TAB ? null : t === "trace" ? TRACE : LINK;
  if (INFO && (INFO.companies || []).length > 1) p.set("co", INFO.schema);   // 多个公司时链接带上公司
  if (SEL && !NORUN.has(t)) p.set("run", SEL.RunId);
  if (t === "rpt" && RPT_CUR) p.set("r", RPT_CUR);
  if (o && o.kind === "item") p.set("item", o.code);
  else if (o && o.kind === "order") p.set("order", o.type + "-" + o.entry);
  const s = p.toString();
  return "#" + t + (s ? "?" + s : "");
}
// push：新增一条历史（初始化完成前一律替换，避免打开页面就多出一条）
function syncUrl(push){
  if (URL_APPLY) return;
  const h = urlNow(); if (h === location.hash) return;
  try { history[push && URL_READY ? "pushState" : "replaceState"]({cc:1, dr:!!LINK && TAB !== "trace"}, "", h); } catch (e) {}
}
const sameObj = (a, b) => !!a && !!b && a.kind === b.kind && (a.kind === "item" ? a.code === b.code : a.type === b.type && String(a.entry) === String(b.entry));
function openObj(o){
  if (!SEL || !o) return;
  const id = String(SEL.RunId);
  if (o.kind === "item") itemDetail(id, {ItemCode:o.code}); else orderDetail(id, {OrderType:o.type, OrderEntry:o.entry});
}
// 抽屉打开的是物料 / 订单时写进地址；fresh = 抽屉原来是关着的（新增历史），否则替换
function drLink(o, fresh){ LINK = o; drLinkBtn(); syncUrl(fresh); }
function drLinkBtn(){ $("#drLink").hidden = !LINK; }
function copyLink(){
  const u = location.href;
  const done = ok => toast(ok ? "已复制链接" + (INFO && INFO.login ? "：对方用自己的 B1 账号登录后打开同一个内容" : "（本机模式的地址只能在本机打开）") : "复制失败，请从浏览器地址栏复制");
  if (navigator.clipboard && window.isSecureContext) navigator.clipboard.writeText(u).then(() => done(true), () => done(copyFallback(esc(u))));
  else done(copyFallback(esc(u)));
}
window.addEventListener("popstate", () => {
  const u = parseUrl(); if (!u || !tabOk(u.tab)) return;
  if (u.co && INFO && u.co !== INFO.schema) { location.reload(); return; }   // 后退到另一个公司的页面：按链接的公司重新打开
  URL_APPLY = true;
  try {
    let re = u.tab !== TAB;
    TAB = u.tab;
    if (u.run && (!SEL || String(SEL.RunId) !== u.run)) {
      const r = RUNS.find(x => String(x.RunId) === u.run);
      if (r) { SEL = r; re = true; $("#runs").querySelectorAll("div.r").forEach(d => d.classList.toggle("sel", d.dataset.id === String(r.RunId))); renderHead(); }
    }
    if (TAB === "trace" && u.obj && !sameObj(u.obj, TRACE)) { TRACE = u.obj; re = true; wtStale("trace"); }
    if (TAB === "rpt" && u.r && u.r !== RPT_CUR) { RPT_CUR = u.r; re = true; wtStale("rpt"); }
    if (re) renderTab();
    else if (!u.obj && LINK) closeDrawer();
    if (TAB !== "trace" && u.obj && !sameObj(u.obj, LINK)) openObj(u.obj);
  } finally { URL_APPLY = false; }
});

// 服务器模式的权限（本机模式没有 INFO.login，全部放行）；服务端另有同样的判断
const canDo = need => !INFO || !INFO.login || ({R:1, O:2, A:3}[INFO.login.role] || 0) >= ({R:1, O:2, A:3}[need]);
async function init(){
  try {
    INFO = await api("/api/info");
    const cos = INFO.companies || [];
    // 本机模式有多个公司、还没选过时，首页先选公司（用户 2026-10-23）
    if (!INFO.login && cos.length > 1 && !CO) { companyPick(cos); return; }
    if (!INFO.login) { CO = INFO.schema; try { localStorage.setItem("cc.co", CO); } catch (e) {} }
    // 服务器模式：链接里的公司和登录的公司不同 → 用那个公司重新登录
    if (INFO.login && URL0 && URL0.co && URL0.co !== INFO.schema && cos.some(c => c.schema === URL0.co)) {
      if (confirm(`这个链接是公司（账套）${URL0.co} 的，你现在登录的是 ${INFO.schema}。\n要切换到 ${URL0.co} 吗？（需要用该公司的 B1 账号重新登录）`)) { switchCompany(URL0.co); return; }
    }
    const co = cos.find(c => c.schema === INFO.schema), coName = co && co.name ? co.name : "";
    $("#conn").innerHTML = `<span title="服务器 ${esc(INFO.conn)}，账号 ${esc(INFO.user)}${coName ? "，" + esc(coName) : ""}">${cos.length > 1
      ? `<select id="coSel" title="切换公司（账套）${INFO.login ? "：需要用该公司的 B1 账号重新登录" : ""}">${cos.map(c => `<option value="${esc(c.schema)}"${c.schema === INFO.schema ? " selected" : ""}>${esc(c.schema)}${c.name ? " · " + esc(c.name) : ""}</option>`).join("")}</select>`
      : `账套 <span class="schema">${esc(INFO.schema)}</span>${coName ? " " + esc(coName) : ""}`}</span>`;
    if ($("#coSel")) $("#coSel").onchange = () => { const v = $("#coSel").value; $("#coSel").value = INFO.schema; switchCompany(v); };
    document.title = "成本执行台 · " + INFO.schema + (coName ? " " + coName : "");
    if (INFO.login) {
      // 服务器模式（2026-10-18）：操作人就是登录的 B1 账号，权限取 OUSR 自定义字段（R 查看 / O 操作 / A 管理）
      const L = INFO.login;
      $("#user").value = L.user; $("#user").readOnly = true; $("#user").title = "操作人以登录账号为准";
      $("#conn").insertAdjacentHTML("beforeend", ` <span class="hint" title="权限 ${esc(L.role)}">· ${esc(L.name)}（${esc(L.roleName)}）</span> <a href="#" id="logout">退出</a>`);
      $("#logout").onclick = async e => { e.preventDefault(); try { await api("/api/logout", {}); } catch (x) {} location.replace("/login.html"); };
    } else {
      let u = ""; try { u = localStorage.getItem("cc.user") || ""; } catch (e) {}
      $("#user").value = u || INFO.osUser || "";
    }
    if (!INFO.hasNew) $("#job").innerHTML = `<div class="msg err">当前账套里没有新框架（MTC_CA_P_RUN），请先用 部署包 部署。</div>`;
  } catch (e) { $("#conn").innerHTML = errBox(e); return; }
  await loadDict();
  await Promise.all([loadPeriods(), loadScen(), loadBoot(), loadRuns(true)]);
  await loadPStat();
  $("#fc").addEventListener("change", applyGate);
  if (!SEL || NORUN.has(TAB)) renderTab();
  URL_READY = true;
  if (URL0 && URL0.run && SEL && String(SEL.RunId) !== URL0.run) toast(`链接里的运行 #${URL0.run} 不在运行记录里，已打开最近一次运行`);
  if (URL0 && URL0.obj && TAB !== "trace" && !NORUN.has(TAB)) openObj(URL0.obj);
  pollJob();
}
// 首页选公司（本机模式、有多个公司、还没选过时）：选好后记在本机，以后直接进；顶栏下拉框随时切换
function companyPick(cos){
  const d = document.createElement("div"); d.className = "copick";
  d.innerHTML = `<div class="cobox"><h2>选择公司（账套）</h2><p class="hint">下面是已经部署了新框架、当前数据库账号能访问的账套。选好后记在本机，以后可以在顶栏切换。</p>`
    + cos.map(c => `<button class="coitem" data-s="${esc(c.schema)}"><b>${esc(c.schema)}</b><span>${esc(c.name || "")}</span></button>`).join("") + `</div>`;
  document.body.appendChild(d);
  d.querySelectorAll(".coitem").forEach(b => b.onclick = () => switchCompany(b.dataset.s));
}
// 切换公司：本机模式记住后重新打开（运行号各公司不同，只保留当前页面）；服务器模式退出后用该公司重新登录
async function switchCompany(s){
  if (INFO && INFO.login) {
    if (!confirm(`切换到公司（账套）${s} 需要用该公司的 B1 账号重新登录。现在切换吗？`)) return;
    try { await api("/api/logout", {}); } catch (e) {}
    location.replace("/login.html?co=" + encodeURIComponent(s) + "#" + TAB + "?co=" + encodeURIComponent(s));
    return;
  }
  try { localStorage.setItem("cc.co", s); } catch (e) {}
  location.hash = "#" + TAB + "?co=" + encodeURIComponent(s);
  location.reload();
}
async function loadPeriods(){
  try {
    const r = asObjs(await q("periods"));
    $("#fc").innerHTML = r.map(p => `<option value="${esc(p.Code)}">${esc(p.Code)}${p.PeriodStat === "Y" ? "（已锁定）" : ""}</option>`).join("");
    // 默认：上个月（月结一般算上月），没有就取最近一个未锁定的账期
    const d = new Date(); d.setDate(1); d.setMonth(d.getMonth() - 1);
    const prev = d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0");
    const pick = r.find(p => p.Code === prev) || r.find(p => p.PeriodStat !== "Y");
    if (pick) $("#fc").value = pick.Code;
  } catch (e) { $("#fc").outerHTML = errBox(e); }
}
// 账期状态（MTC_CA_V_PERIOD，用户 2026-10-19）：已生成凭单 / B1 已锁定的账期不能正式计算，模拟照常；数据库里 P_PERIOD_GUARD 同样拦截
const PST_NAME = {OPEN:"未计算", CALC:"已计算", POSTED:"已生成凭单", LOCKED:"B1 已锁定"};
const PST_CLS = {OPEN:"SKIP", CALC:"OK", POSTED:"RUNNING", LOCKED:"BLOCKED"};
let PSTAT = {}, JOB_BUSY = false;
const pChip = fc => { const p = PSTAT[fc]; return p ? `<span class="chip s-${PST_CLS[p.Status] || "SKIP"}" title="账期状态">${esc(PST_NAME[p.Status] || p.Status)}</span>` : ""; };
async function loadPStat(){
  try { PSTAT = Object.fromEntries(asObjs(await q("periodStatus", {}, true)).map(p => [p.FcCode, p])); }
  catch (e) { PSTAT = {}; }   // 还没打 patch_20261019_period 的库：不显示状态，由过程拦截
  [...$("#fc").options].forEach(o => { const p = PSTAT[o.value]; if (p && p.Status !== "OPEN" && p.Status !== "LOCKED") o.textContent = o.value + "（" + PST_NAME[p.Status] + "）"; });
  applyGate(); renderHead();
}
// 正式计算不允许的原因（空 = 允许）
function fcBlock(){
  const p = PSTAT[$("#fc").value];
  if (runType !== "F" || !p) return "";
  if (p.Status === "LOCKED") return "账期已在 B1 锁定，不能正式计算（可以做模拟）。";
  if (p.Status === "POSTED") return `已生成凭单（运行 #${p.PostRunId ?? ""}${p.PostUser ? "，" + p.PostUser : ""}${p.PostTime ? " " + String(p.PostTime).slice(0, 16) : ""}），不能正式计算；需要重算时先撤销凭单（凭单全部未过账才能撤销）。模拟计算不受影响。`;
  return "";
}
function applyGate(){
  const fc = $("#fc") && $("#fc").value; if (!fc) return;
  const p = PSTAT[fc];
  $("#fcStat").innerHTML = p ? " " + pChip(fc) + (p.CalcRunId ? ` <span class="hint">最近成功正式运行 #${esc(p.LastOkRunId ?? p.CalcRunId)}</span>` : "") : "";
  // 正式计算服务端要“管理”权限，模拟“操作”权限即可；按钮跟服务端一致，不让操作权限的人点了才报错（2026-11-07）
  const need = runType === "F" ? "A" : "O";
  const why = fcBlock() || (canDo(need) ? "" : `正式计算需要“管理”权限，你的权限是“${INFO.login.roleName || INFO.login.role}”；可以“只做计算前检查”或改做模拟。`);
  $("#fcGate").innerHTML = why ? `<div class="msg err">${esc(why)}</div>` : "";
  $("#btnRun").disabled = JOB_BUSY || !(INFO && INFO.hasNew) || !canDo(need) || !!why;
}
async function loadScen(){ await loadScenSel(); }
async function loadBoot(){
  try {
    const b = asObjs(await q("boot"))[0] || {};
    $("#bootInfo").innerHTML = b.BootFc ? `承接账期 <b>${esc(b.BootFc)}</b>：` + (b.Items || b.Orders ? `已承接物料 ${b.Items} 个、订单 ${b.Orders} 张（${esc(b.LoadTime || "")}）` : "还没有承接") : "没有配置承接账期（MTC_CA_C_PARAM.BOOTSTRAP_FC）";
    $("#btnBoot").dataset.fc = b.BootFc || "";
    $("#btnBoot").disabled = !b.BootFc || !canDo("A");
  } catch (e) { $("#bootInfo").innerHTML = errBox(e); }
  loadLegacy();
}
// 历史回填（新旧报表合并，用户 2026-11-02）：旧框架有结果的账期（承接账期及以前）和每期最近一次回填
async function loadLegacy(){
  try {
    const r = await q("legacyRuns", {}, true);
    const fcs = asObjs(r).map(o => o.FcCode).sort();
    const opt = v => fcs.map(f => `<option${f === v ? " selected" : ""}>${esc(f)}</option>`).join("");
    const done = asObjs(r).filter(o => o.Status === "OK").map(o => o.FcCode).sort();
    // 默认：从第一个没回填的账期（都回填过就从头）到承接账期
    const from = fcs.find(f => !done.includes(f)) || fcs[0];
    $("#lgFrom").innerHTML = opt(from); $("#lgTo").innerHTML = opt(fcs[fcs.length - 1]);
    $("#btnLegacy").disabled = !fcs.length || JOB_BUSY || !canDo("A");
    $("#lgList").innerHTML = table(r, {fmt:{Status: v => v ? chip(v) : `<span class="hint">未回填</span>`}, wrap:["Msg"], sum:false, empty:"旧框架没有结果（MTC_COST_0301_INVNT 为空），或没有配置承接账期"});
  } catch (e) { $("#lgList").innerHTML = errBox(e); $("#btnLegacy").disabled = true; }
}
async function loadRuns(selectFirst){
  QC.clear();
  try {
    RUNS = asObjs(await q("runs"));
    const typ = r => r.RunType === "F" ? "正式" : r.RunType === "H" ? "历史（旧框架回填）" : "模拟 " + (r.Scenario || "");
    $("#runs").innerHTML = RUNS.length ? RUNS.map(r => `<div class="r ${SEL && SEL.RunId === r.RunId ? "sel" : ""}" data-id="${r.RunId}">
      <span class="id">#${r.RunId}</span><span><b>${esc(r.FcCode)}</b> ${esc(typ(r))}</span>${chip(r.Status)}
      <span class="m" title="${esc(r.Msg || "")}">${esc((r.StartTime || "").slice(5, 16))} · ${esc(r.UserCode || "")} · ${esc(r.Msg || "")}</span></div>`).join("") : `<div class="empty">还没有运行记录</div>`;
    $("#runs").querySelectorAll("div.r").forEach(d => d.onclick = () => { runPop(false); if (NORUN.has(TAB)) TAB = "steps"; selectRun(RUNS.find(r => String(r.RunId) === d.dataset.id)); });
    if (selectFirst && RUNS.length && !SEL) selectRun((URL0 && URL0.run && RUNS.find(r => String(r.RunId) === URL0.run)) || RUNS[0]);
    else if (SEL) { const s = RUNS.find(r => r.RunId === SEL.RunId); if (s) { SEL = s; renderHead(); } }
  } catch (e) { $("#runs").innerHTML = errBox(e); }
}
// 运行概况：顶栏按钮显示当前运行，主区上方一排数字卡片
const secBetween = (a, b) => { const t = v => v ? new Date(String(v).replace(" ", "T")).getTime() : NaN; const d = ((b ? t(b) : Date.now()) - t(a)) / 1000; return isFinite(d) && d >= 0 ? d : null; };
const durText = s => s === null ? "-" : s < 60 ? `${Math.round(s)} 秒` : s < 3600 ? `${Math.floor(s / 60)} 分 ${Math.round(s % 60)} 秒` : `${Math.floor(s / 3600)} 小时 ${Math.round(s % 3600 / 60)} 分`;
function renderHead(){
  const r = SEL; if (!r) return;
  const typ = r.RunType === "F" ? "正式" : r.RunType === "H" ? "历史（旧框架回填）" : "模拟 " + (r.Scenario || "");
  const pp = PSTAT[r.FcCode], used = pp && pp.Status === "POSTED" && String(pp.PostRunId) === String(r.RunId);
  $("#runBtnTxt").innerHTML = `<b>#${esc(r.RunId)}</b> · ${esc(r.FcCode)} ${pChip(r.FcCode)} · ${esc(typ)} ${chip(r.Status)}${used ? ' <span class="chip s-RUNNING">凭单所用</span>' : ""}`;
  // 运行概况压成顶栏一行（原来主区上方的一排卡片，用户 2026-10-17）
  const m = [`迭代 ${r.IterCount ?? "-"} 轮`, `用时 ${durText(secBetween(r.StartTime, r.EndTime))}${r.EndTime ? "" : "…"}`,
    `开始 ${(r.StartTime || "").slice(5, 16)}`, r.UserCode || "", r.Msg || ""].filter(Boolean);
  $("#runMeta").textContent = m.join(" · "); $("#runMeta").title = m.join("\n");
}
function selectRun(r){
  if (!r) return; SEL = r;
  $("#runs").querySelectorAll("div.r").forEach(d => d.classList.toggle("sel", d.dataset.id === String(r.RunId)));
  renderHead(); renderTab();
}
// 点菜单 = 打开或切到这个页签，点当前页不重查（用“⟳ 刷新”）；Ctrl / ⌘ / Shift 点 = 单开窗口（用户 2026-11-06）
document.querySelectorAll("#tabs button[data-t]").forEach(b => b.onclick = e => {
  if (e.ctrlKey || e.metaKey || e.shiftKey) { wtWin(b.dataset.t); return; }
  $("#tabs").classList.remove("open");
  if (b.dataset.t !== TAB) wtGo(b.dataset.t);
});
