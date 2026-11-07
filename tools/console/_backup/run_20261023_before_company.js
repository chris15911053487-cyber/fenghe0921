// 成本执行台 · run.js — 发起计算 / 只做检查 / 期初承接、确认对话框、运行进度轮询；顶栏、菜单折叠、行距、界面风格
// index.html 按顺序加载 js/ 下的脚本，共用全局作用域；加载时立即执行的代码只能用到本文件和前面文件里的名字。
"use strict";
// ---------------- 发起计算 / 承接 ----------------
document.querySelectorAll("#rtSeg button").forEach(b => b.onclick = () => {
  runType = b.dataset.v;
  document.querySelectorAll("#rtSeg button").forEach(x => x.classList.toggle("on", x === b));
  $("#scenRow").hidden = runType !== "S";
  applyGate();
});
// needPwd：生成凭单时还要输入本人 B1 密码，读到 DLG_PWD 后立即清空输入框（用户 2026-10-19，Q41）
// needReason：确认阻断项时要写理由，读到 DLG_REASON（Q45）
let DLG_PWD = "", DLG_REASON = "";
function confirmDlg(title, rows, needType, needPwd, needReason){
  return new Promise(res => {
    const d = $("#dlg");
    $("#dlgTitle").textContent = title;
    $("#dlgTable").innerHTML = rows.map(([k, v]) => `<tr><td class="hint">${esc(k)}</td><td><b>${esc(v)}</b></td></tr>`).join("");
    $("#dlgSchema").textContent = INFO.schema;
    $("#dlgTypeWrap").hidden = !needType;
    $("#dlgPwdWrap").hidden = !needPwd; $("#dlgPwd").value = ""; DLG_PWD = "";
    $("#dlgReasonWrap").hidden = !needReason; $("#dlgReason").value = ""; DLG_REASON = "";
    $("#dlgPwdUser").textContent = INFO.login ? INFO.login.user : "";
    $("#dlgInput").value = "";
    const okState = () => { $("#dlgOk").disabled = (needType && $("#dlgInput").value.trim().toUpperCase() !== INFO.schema.toUpperCase()) || (needPwd && !$("#dlgPwd").value)
      || (needReason && $("#dlgReason").value.trim().length < 4); };
    okState();
    $("#dlgInput").oninput = okState; $("#dlgPwd").oninput = okState; $("#dlgReason").oninput = okState;
    $("#dlgOk").onclick = () => { DLG_PWD = $("#dlgPwd").value; $("#dlgPwd").value = ""; DLG_REASON = $("#dlgReason").value.trim(); d.close(); res($("#dlgInput").value.trim()); };
    $("#dlgCancel").onclick = () => { $("#dlgPwd").value = ""; d.close(); res(null); };
    d.oncancel = () => { $("#dlgPwd").value = ""; res(null); };
    d.showModal(); if (needType) $("#dlgInput").focus(); else if (needReason) $("#dlgReason").focus();
  });
}
$("#btnRun").onclick = async () => {
  const fc = $("#fc").value, user = $("#user").value.trim(), scen = runType === "S" ? $("#scen").value : "";
  if (!/^[^\x00-\x1f]{1,50}$/.test(user)) { $("#job").innerHTML = errBox("请填写操作人（不超过 50 个字）"); return; }
  if (runType === "S" && !scen) { $("#job").innerHTML = errBox("模拟计算需要选择场景（MTC_CA_C_SCENARIO）"); return; }
  try { localStorage.setItem("cc.user", user); } catch (e) {}
  const ok = await confirmDlg(runType === "F" ? "确认正式计算" : "确认模拟计算",
    [["账套", INFO.schema], ["账期", fc], ["类型", runType === "F" ? "正式（覆盖该账期上一次正式结果）" : "模拟：" + scen], ["操作人", user]], runType === "F");
  if (ok === null) return;
  startJob("doRun", {fc, runType, scenario:scen, user, confirm:ok});
};
$("#btnPre").onclick = async () => {
  const fc = $("#fc").value, user = $("#user").value.trim(), scen = runType === "S" ? $("#scen").value : "";
  if (!/^[^\x00-\x1f]{1,50}$/.test(user)) { $("#job").innerHTML = errBox("请填写操作人（不超过 50 个字）"); return; }
  if (runType === "S" && !scen) { $("#job").innerHTML = errBox("模拟需要选择场景"); return; }
  startJob("doPrecheck", {fc, runType, scenario:scen, user});
};
$("#btnBoot").onclick = async () => {
  const fc = $("#btnBoot").dataset.fc;
  const ok = await confirmDlg("确认期初承接", [["账套", INFO.schema], ["承接账期", fc], ["说明", "重新读取旧框架该期结果，覆盖已有承接数据"]], true);
  if (ok === null) return;
  startJob("doBoot", {fc, confirm:ok});
};
async function startJob(action, args){
  // 记下启动前最大的 RunId：之后出现的 RUNNING 运行才是这次的（避免拿到以前中断后没收尾的运行）
  JOB_BASE = RUNS.reduce((m, r) => Math.max(m, Number(r.RunId)), 0); JOB_RUN = null; JOB_ACTION = action; JOB_AUTOSEL = false;
  try { await api("/api/call", {action, args}); pollJob(); }
  catch (e) { $("#job").innerHTML = errBox(e); }
}
// 运行进度：按入口过程（10_run_entry / 17 MTC_CA_P_PRECHECK）的步骤顺序列出已完成、正在执行、未开始的步骤；
// 正在执行那一步的说明来自 MTC_CA_P_LOG_NOTE（校验做到第几项、迭代第几轮第几级），过程自治提交，所以运行中就能查到
const SNAP = ["P20_ITEM","P20_LINE","P20_AP","P20_SUBFEE","P20_ORDER","P20_EXP","P20_MISC","P20_OPEN"];
const PIPE = {doRun: ["P00","P20","P10","P30","P31","P40","P50","P60","P65","P71","P73","P74","P70","P75","P80"], doPrecheck: ["P00","P20","P10","P80"]};
let JOB_BASE = null, JOB_RUN = null, JOB_ACTION = null, JOB_AUTOSEL = false;
// 时间只显示时分秒（日期在运行抬头里）；服务端把正好 0 点的时间截成只有日期
const hms = v => !v ? "" : String(v).length <= 10 ? "00:00:00" : esc(String(v).slice(11, 19));
// 一次运行按哪个入口的步骤顺序展示：正在看着跑的用实际入口；历史运行状态是 CHECKED 的是“只做计算前检查”
const runAction = r => r.RunId === JOB_RUN && JOB_ACTION ? JOB_ACTION : r.Status === "CHECKED" ? "doPrecheck" : "doRun";
function jobRun(){
  if (JOB_RUN) return RUNS.find(r => r.RunId === JOB_RUN) || null;
  const r = RUNS.find(r => r.Status === "RUNNING" && (JOB_BASE === null || Number(r.RunId) > JOB_BASE));
  if (r) JOB_RUN = r.RunId;
  return r || null;
}
async function progressHtml(action, run, live){
  let steps = [];
  try { steps = asObjs(await q("steps", {runId:String(run.RunId)}, true)); } catch (e) { return errBox(e); }
  const by = Object.fromEntries(steps.map(s => [s.StepCode, s]));
  // 快照的 8 个小步骤合成一行，说明里写正在取哪一块
  const snap = SNAP.map(c => by[c]).filter(Boolean);
  if (snap.length) {
    const cur = snap.find(s => s.Status === "RUNNING");
    const bad = snap.find(s => s.Status === "FAIL") || snap.find(s => s.Status === "WARN");
    by.P20 = {Status: cur ? "RUNNING" : snap.length === SNAP.length ? (bad ? bad.Status : "OK") : (bad && bad.Status === "FAIL" ? "FAIL" : "RUNNING"),
      Sec: snap.reduce((a, s) => a + Number(s.Sec || 0), 0),
      StartTime: snap.map(s => s.StartTime).filter(Boolean).sort()[0], EndTime: cur || snap.length < SNAP.length ? null : snap.map(s => s.EndTime).filter(Boolean).sort().pop(),
      Msg: cur ? `${snap.length}/${SNAP.length}：${(STEP[cur.StepCode] || "").replace("快照：", "")}` : snap.length < SNAP.length ? `${snap.length}/${SNAP.length}`
        : bad ? `${(STEP[bad.StepCode] || bad.StepCode).replace("快照：", "")}：${bad.Msg || ""}` : ""};
  }
  const pipe = PIPE[action].filter(c => c !== "P31" || run.RunType === "S" || by.P31);
  // 日志里有、但不在预期顺序里的步骤（以后新增的）也列出来
  steps.forEach(s => { if (!SNAP.includes(s.StepCode) && !pipe.includes(s.StepCode)) pipe.push(s.StepCode); });
  const stopped = !live || ["FAIL","BLOCKED","NOCONV"].includes(run.Status);
  const done = pipe.filter(c => by[c] && by[c].Status !== "RUNNING").length;
  const curCode = pipe.find(c => by[c] && by[c].Status === "RUNNING");
  // 右侧时间：开始–结束 · 用时；运行中的只有开始时间
  const tm = s => `${s.StartTime ? hms(s.StartTime) + (s.EndTime ? "–" + hms(s.EndTime) : " 起") + " · " : ""}${esc(s.Sec ?? 0)} 秒`;
  const li = c => {
    const s = by[c], nm = c === "P20" ? "取快照" : (STEP[c] || c);
    if (!s) return `<li class="todo"><span class="ic">○</span><span>${esc(nm)}</span><span class="t">${stopped ? "未执行" : ""}</span></li>`;
    if (s.Status === "RUNNING") return `<li class="cur"><span class="ic"><span class="spin"></span></span><span>${esc(nm)} <span class="hint mono">${esc(c)}</span></span><span class="t">${tm(s)}</span>${s.Msg ? `<div class="note">${esc(s.Msg)}</div>` : ""}</li>`;
    const k = s.Status === "FAIL" ? "fail" : s.Status === "WARN" ? "warn" : "ok";
    const txt = s.Msg ? s.Msg + (s.RowCnt !== null && s.RowCnt !== undefined ? "：" + s.RowCnt : "") : "";
    const note = k !== "ok" && txt ? `<div class="note">${esc(txt)}</div>` : "";
    return `<li class="${k}" title="${esc(txt)}"><span class="ic">${k === "ok" ? "✓" : k === "warn" ? "!" : "✕"}</span><span>${esc(nm)}</span><span class="t">${tm(s)}</span>${note}</li>`;
  };
  const pct = Math.round(100 * done / pipe.length);
  return `<div class="pbar"><i style="width:${live || !["OK","CHECKED"].includes(run.Status) ? pct : 100}%"></i></div>`
    + `<div class="ph hint" style="margin:0 0 4px"><span>第 ${Math.min(done + (curCode ? 1 : 0), pipe.length)} / ${pipe.length} 步${curCode ? "：" + esc(curCode === "P20" ? "取快照" : STEP[curCode] || curCode) : ""}</span><span class="sp"></span><span>#${esc(run.RunId)}</span></div>`
    + `<ol class="psteps">${pipe.map(li).join("")}</ol>`;
}
async function pollJob(){
  clearTimeout(pollTimer);
  let j;
  try { j = await api("/api/job"); } catch (e) { $("#job").innerHTML = errBox(e); return; }
  const busy = j.state === "running"; JOB_BUSY = busy;
  $("#btnRun").disabled = busy || !INFO.hasNew || !canDo("O") || !!fcBlock(); $("#btnPre").disabled = busy || !INFO.hasNew || !canDo("O"); $("#btnBoot").disabled = busy || !$("#btnBoot").dataset.fc || !canDo("A");
  const pill = $("#jobPill");
  if (j.state === "idle") { $("#job").innerHTML = ""; pill.hidden = true; return; }
  if (busy) {
    await loadRuns(false);
    JOB_ACTION = j.action;
    const running = PIPE[j.action] ? jobRun() : null;
    const head = `<div class="ph"><b>${esc(j.title)}</b><span>运行中 · 已 ${esc(j.elapsed)} 秒${j.by && INFO.login ? " · " + esc(j.by) + " 发起" : ""}</span>${running ? `<span class="sp"></span><a href="#steps" id="jobSee">#${esc(running.RunId)} 执行步骤 →</a>` : ""}</div>`;
    const body = running ? "" : `<div class="hint">${PIPE[j.action] ? "正在启动…" : "后台执行中，这一步没有分步记录。"}</div>`;
    $("#job").innerHTML = `<div class="prog">${head}${body}<p class="hint">执行步骤在“步骤”页（顶部的进度标签也能点过去）。可以关闭网页，计算在服务端继续；重新打开会接着显示进度。</p></div>`;
    if ($("#jobSee")) $("#jobSee").onclick = e => { e.preventDefault(); TAB = "steps"; selectRun(running); };
    pill.hidden = false; pill.className = "jobpill";
    pill.innerHTML = `<span class="spin" style="margin:0"></span>${esc(j.title)} · ${esc(j.elapsed)} 秒`;
    pill.onclick = e => { e.preventDefault(); if (running) { TAB = "steps"; selectRun(running); } else { TAB = "run"; renderTab(); } };
    // 运行刚出现时自动选中一次；之后用户点别的运行就看别的，不再拉回来
    if (running && !JOB_AUTOSEL) { JOB_AUTOSEL = true; if (!SEL || SEL.RunId !== running.RunId) { TAB = "steps"; selectRun(running); } }
    else if (SEL && SEL.Status === "RUNNING" && (TAB === "steps" || TAB === "flow")) renderTab(true);
    pollTimer = setTimeout(pollJob, 1000);
    return;
  }
  // done / error
  let html;
  if (j.state === "error") html = `<div class="msg err">${esc(j.title)} 出错：${esc(j.error)}</div>`;
  else {
    const o = (j.result && j.result.rows && j.result.rows.length) ? Object.fromEntries(j.result.columns.map((c, i) => [c, j.result.rows[0][i]])) : {};
    const good = Number(o.Code) === 0;
    html = `<div class="msg ${good ? "ok" : "err"}">${esc(j.title)}${good ? "完成" : "未完成"}：${esc(o.Msg ?? "")}（${j.elapsed} 秒）</div>`;
  }
  $("#job").innerHTML = html;
  const first = !j.seen;
  if (first && (j.state === "done" || j.state === "error")) {
    const good = j.state !== "error" && /完成：/.test(html) && !/未完成/.test(html);
    pill.hidden = false; pill.className = "jobpill " + (good ? "ok" : "err");
    pill.textContent = (good ? "✓ " : "✕ ") + j.title + (good ? "完成" : "未完成");
    pill.onclick = e => { e.preventDefault(); TAB = "run"; renderTab(); };
  } else pill.hidden = true;
  if (first) {
    await api("/api/job/ack", {});
    await Promise.all([loadRuns(false), loadBoot()]);
    await loadPStat();
  }
  // 步骤清单在“步骤”页（顶部运行按钮切换看哪一次）
  const run = PIPE[j.action] && JOB_RUN ? RUNS.find(r => r.RunId === JOB_RUN) : null;
  if (first && RUNS.length && (j.action === "doRun" || j.action === "doPrecheck")) { if (j.action === "doPrecheck") TAB = "checks"; selectRun(run || RUNS[0]); }
}
$("#btnRefresh").onclick = () => { loadRuns(false); loadBoot(); loadPStat(); if (SEL) renderTab(); };
function runPop(show){ $("#runPop").hidden = !show; }
$("#runBtn").onclick = e => { e.stopPropagation(); runPop($("#runPop").hidden); };
$("#runPop").onclick = e => e.stopPropagation();
document.addEventListener("click", () => { runPop(false); $("#tabs").classList.remove("open"); });
document.addEventListener("keydown", e => {
  if (e.key !== "Escape" || $("#dlg").open) return;
  const m = document.querySelector(".colmenu, .cfmenu"), fu = document.querySelector(".tbl.full");
  if (m) m.remove(); else if (fu) tblFull(fu, false); else if (!$("#runPop").hidden) runPop(false); else closeDrawer(true);
});
$("#linkBtn").onclick = copyLink;
$("#goRun").onclick = () => { TAB = "run"; try { localStorage.setItem("cc.tab", TAB); } catch (e) {} renderTab(); };
$("#navBtn").onclick = e => { e.stopPropagation(); $("#tabs").classList.toggle("open"); };
$("#tabs").addEventListener("click", e => e.stopPropagation());
// 行距、菜单收起（记在本机）；没设置过时屏宽 ≤1366（笔记本）默认收起菜单，点顶栏“☰ 菜单”浮出
let DEN = "", NAVC = null; try { DEN = localStorage.getItem("cc.den") || ""; NAVC = localStorage.getItem("cc.navc"); } catch (e) {}
const relayout = () => document.querySelectorAll(".tbl").forEach(w => tblLayout(w.id));
function applyDen(){ document.body.classList.toggle("std", DEN === "std"); $("#denBtn").textContent = DEN === "std" ? "紧凑行距" : "标准行距"; }
function applyNav(){
  const c = NAVC === null ? window.innerWidth <= 1366 : NAVC === "Y";
  document.body.classList.toggle("navc", c);
  $("#navCol").textContent = c ? "📌 固定在左侧" : "« 收起菜单";
}
$("#clickSel").value = CLICK;
$("#clickSel").onchange = () => { setClick($("#clickSel").value); toast(CLICK === "one" ? "已改成单击打开明细" : "已改成双击打开明细：单击只选中，抽屉开着时单击别的行直接切换"); };
$("#denBtn").onclick = () => { DEN = DEN === "std" ? "" : "std"; try { localStorage.setItem("cc.den", DEN); } catch (e) {} applyDen(); relayout(); };
$("#navCol").onclick = () => {
  NAVC = document.body.classList.contains("navc") ? "N" : "Y"; try { localStorage.setItem("cc.navc", NAVC); } catch (e) {}
  $("#tabs").classList.remove("open"); applyNav(); relayout();
};
// 左侧菜单分组折叠：点分组名折叠 / 展开，“⇕ 分组”一键全部折叠或展开；当前页所在分组始终展开；折叠状态记在本机 cc.navg
let NAVG = {}; try { NAVG = JSON.parse(localStorage.getItem("cc.navg") || "{}") || {}; } catch (e) {}
document.querySelectorAll("#tabs .grp").forEach(g => {
  const box = document.createElement("div"); box.className = "grpb";
  while (g.nextElementSibling && g.nextElementSibling.matches("button[data-t]")) box.appendChild(g.nextElementSibling);
  g.after(box);
  const name = g.textContent.trim(); g.dataset.g = name;
  g.innerHTML = `<span>${esc(name)}</span><span class="gn">${box.children.length}</span>`;
  g.title = "点击折叠 / 展开";
  g.onclick = () => { NAVG[name] = !g.classList.contains("fold"); saveNavg(); navGrpSync(); };
});
function saveNavg(){ try { localStorage.setItem("cc.navg", JSON.stringify(NAVG)); } catch (e) {} }
function navGrpSync(){
  document.querySelectorAll("#tabs .grp").forEach(g => {
    const box = g.nextElementSibling, cur = !!box.querySelector(`button[data-t="${TAB}"]`);
    const f = !!NAVG[g.dataset.g] && !cur;
    g.classList.toggle("fold", f); box.classList.toggle("fold", f);
    g.querySelector(".gn").hidden = !f;
  });
}
$("#navFold").onclick = () => {
  const gs = [...document.querySelectorAll("#tabs .grp")], any = gs.some(g => !g.classList.contains("fold") && !g.nextElementSibling.querySelector(`button[data-t="${TAB}"]`));
  gs.forEach(g => { NAVG[g.dataset.g] = any; }); saveNavg(); navGrpSync();
};
navGrpSync();
applyDen(); applyNav();
// 界面风格：<head> 里已按 cc.theme 设好 data-ui-theme；这里同步下拉框、处理切换和“跟随系统”。切换后字体宽度可能变，重新量冻结列
const THEME_IDS = ["warm","ent","tech","ind","mono","dark"], DEFAULT_THEME = "warm";
const darkMq = window.matchMedia ? window.matchMedia("(prefers-color-scheme: dark)") : null;
let THEME_PREF = "";
try { THEME_PREF = localStorage.getItem("cc.theme") || ""; } catch (e) {}
function applyTheme(){
  const t = THEME_PREF === "system" ? (darkMq && darkMq.matches ? "dark" : DEFAULT_THEME) : THEME_IDS.includes(THEME_PREF) ? THEME_PREF : DEFAULT_THEME;
  document.documentElement.setAttribute("data-ui-theme", t);
  $("#themeSel").value = THEME_PREF === "system" ? "system" : t;
  relayout();
}
$("#themeSel").onchange = () => { THEME_PREF = $("#themeSel").value; try { localStorage.setItem("cc.theme", THEME_PREF); } catch (e) {} applyTheme(); };
if (darkMq && darkMq.addEventListener) darkMq.addEventListener("change", () => { if (THEME_PREF === "system") applyTheme(); });
applyTheme();
