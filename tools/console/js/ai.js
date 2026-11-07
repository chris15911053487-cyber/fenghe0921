// 成本执行台 · ai.js — AI 助手（大模型暂不接入）
// index.html 按顺序加载 js/ 下的脚本，共用全局作用域；加载时立即执行的代码只能用到本文件和前面文件里的名字。
"use strict";
// ---------------- AI 助手（设计稿 8.3 A 档；大模型暂不接入，调用时由本机服务报错） ----------------
// 出网内容只有：替换成代号的问题、工具清单、执行状态（状态、步骤、行数、未通过的校验编号），不含金额、单价、数量和明细。
// 代号对照只保存在本页内存中；本机服务先把将要发出的内容写入审计日志，再决定是否发出（现在一律不发）。
const AI = {map:{}, rev:{}, n:{}, log:[]};
const AI_KIND = {ITEM:"物料", BP:"伙伴", ORDER:"订单", POOL:"费用池", NUM:"数值"};
const AI_SYSTEM = "你是 FH100 实际成本核算系统的调度助手。只能通过提供的工具查询状态、发起计算或在本机页面展示明细；"
  + "你看到的物料、伙伴、订单编码和数值都是代号（如 物料#1），调用工具时原样使用代号，由本机服务换回。"
  + "工具结果只告诉你状态和行数，金额、单价、数量和明细只在用户本机页面显示，不要猜测或编造这些数字。回答用中文，简洁。";
const AI_SCHEMA = {
  "cost.precheck": {fc:"账期 YYYY-MM", runType:"F 正式 / S 模拟", scenario:"模拟场景编码，正式为空"},
  "cost.run": {fc:"账期 YYYY-MM", runType:"F 正式 / S 模拟", scenario:"模拟场景编码，正式为空"},
  "cost.status": {runId:"运行号，空 = 当前选中的运行"},
  "cost.checks": {runId:"运行号"},
  "cost.explain_item": {runId:"运行号", item:"物料代号"},
  "cost.explain_order": {runId:"运行号", order:"订单代号"},
  "cost.compare_runs": {runId:"运行号", runId2:"对比的运行号"},
  "cost.compare_old": {runId:"运行号"},
  "cost.report": {runId:"运行号"},
  "meta.describe": {text:"要查的表、字段、规则、校验的关键词"},
  "doc.manual": {},
  "jdt.generate": {runId:"运行号"}
};
function aiToken(kind, raw){
  if (AI.map[raw]) return AI.map[raw];
  AI.n[kind] = (AI.n[kind] || 0) + 1;
  const t = `${AI_KIND[kind]}#${AI.n[kind]}`;
  AI.map[raw] = t; AI.rev[t] = raw; return t;
}
async function aiMask(text){
  const runIds = new Set(RUNS.map(r => String(r.RunId)));
  const cands = [...new Set((text.match(/[A-Za-z0-9][A-Za-z0-9_\-\.\/]*/g) || []))];
  const repl = {};
  for (const c of cands) {
    if (/^\d{4}-\d{2}$/.test(c)) continue;                           // 账期不算业务数据
    if (/^MTC_CA_/.test(c)) continue;                                 // 表名；其余先查库，是物料 / 伙伴 / 订单 / 池编码就替换
    let kind = null;
    if (c.length >= 2) {
      try { const r = asObjs(await q("codeKind", {itemCode:c})); if (r.length) kind = r[0].Kind; } catch (e) {}
    }
    if (!kind && /^\d+(\.\d+)?$/.test(c)) {
      if (runIds.has(c) && new RegExp("(#|运行|run)\\s*" + c, "i").test(text)) continue;   // 运行号保留
      if (c.length >= 3 || c.includes(".")) kind = "NUM";
    }
    if (kind) repl[c] = aiToken(kind, c);
  }
  return text.replace(/[A-Za-z0-9][A-Za-z0-9_\-\.\/]*/g, m => repl[m] || m);
}
async function aiStatus(){
  if (!SEL) return {selectedRun:null};
  const id = String(SEL.RunId);
  const [st, ck] = await Promise.all([q("steps", {runId:id}).catch(() => null), q("checks", {runId:id}).catch(() => null)]);
  return {
    selectedRun: {runId:SEL.RunId, fc:SEL.FcCode, runType:SEL.RunType, scenario:SEL.Scenario || "", status:SEL.Status, iterCount:SEL.IterCount, converged:SEL.Converged},
    steps: st ? asObjs(st).map(s => ({step:s.StepCode, status:s.Status, rows:s.RowCnt})) : [],
    checksNotPassed: ck ? asObjs(ck).filter(c => c.Result !== "PASS").map(c => ({id:c.CheckId, title:c.Title, result:c.Result, issues:c.IssueCnt, block:c.IsBlock})) : []
  };
}
async function aiPayload(question){
  const tools = asObjs(await q("metaTools")).map(t => ({
    name: t.ToolName.replace(/\./g, "_"),
    description: `${t.Title}：${t.Descr || ""}（返回给你的只有：${t.ModelOutput || "状态"}）`,
    input_schema: {type:"object", properties:Object.fromEntries(Object.entries(AI_SCHEMA[t.ToolName] || {}).map(([k, v]) => [k, {type:"string", description:v}])), additionalProperties:false}
  }));
  const masked = await aiMask(question);
  return {masked, payload:{tier:"A", system:AI_SYSTEM, tools, messages:[{role:"user", content: masked + "\n\n[本机执行状态]\n" + JSON.stringify(await aiStatus())}]}};
}
function aiRender(){
  const box = $("#aiLog"); if (!box) return;
  box.innerHTML = AI.log.length ? AI.log.map(m => m.role === "user"
      ? `<div class="ai-u"><div class="hint">你（${esc(m.time)}）</div><div>${esc(m.text)}</div>${m.masked !== m.text ? `<div class="hint">发出时替换为：${esc(m.masked)}</div>` : ""}</div>`
      : `<div class="msg ${m.ok ? "ok" : "err"}">${esc(m.text)}</div>`).join("")
    : `<div class="empty">还没有对话。</div>`;
  const keys = Object.keys(AI.rev);
  $("#aiMap").innerHTML = keys.length ? `<table><thead><tr><th>代号</th><th>本机真实值</th></tr></thead><tbody>${keys.map(k => `<tr><td>${esc(k)}</td><td class="mono">${esc(AI.rev[k])}</td></tr>`).join("")}</tbody></table>` : `<p class="hint">还没有替换。</p>`;
}
async function renderAI(pane){
  let st = {};
  try { st = await api("/api/ai/status"); } catch (e) {}
  pane.innerHTML = `<div class="msg info">AI 助手（A 档“仅调度”）：问题中的物料、伙伴、订单编码和数值先在本机替换成代号；发给大模型的只有问题、工具清单和执行状态，不含金额、单价、数量和明细。每次要发出的内容都先写入本机审计日志（tools/console/audit/）。<br><b>当前状态：${esc(st.reason || "大模型未配置")}</b>，所以发送会报错、内容不会发出；可以用“预览出网内容”检查将来会发出什么。</div>
    <textarea id="aiQ" rows="3" maxlength="2000" placeholder="例如：2026-09 的计算为什么被阻断？物料 A001 的单价是怎么来的？" style="width:100%;margin:6px 0;padding:8px;border:1px solid var(--line);border-radius:6px;background:var(--surface);color:var(--ink);font:inherit"></textarea>
    <div class="bar"><button class="btn primary" id="aiSend">发送</button><button class="btn" id="aiPrev">预览出网内容</button><button class="btn" id="aiClear">清空对话和代号</button></div>
    <div id="aiLog"></div><div id="aiPreview"></div>
    <h3>代号对照（只在本页内存中，刷新即清空）</h3><div id="aiMap"></div>`;
  aiRender();
  const prep = async () => {
    const qtext = $("#aiQ").value.trim();
    if (!qtext) throw new Error("请输入问题");
    return Object.assign({qtext}, await aiPayload(qtext));
  };
  $("#aiPrev").onclick = async () => {
    try { const p = await prep(); $("#aiPreview").innerHTML = `<h3>将发给大模型的内容</h3><pre class="mono" style="white-space:pre-wrap;font-size:12px;background:var(--soft);padding:10px;border-radius:6px;max-height:50vh;overflow:auto">${esc(JSON.stringify(p.payload, null, 2))}</pre>`; aiRender(); }
    catch (e) { $("#aiPreview").innerHTML = errBox(e); }
  };
  $("#aiSend").onclick = async () => {
    $("#aiSend").disabled = true;
    try {
      const p = await prep();
      AI.log.push({role:"user", text:p.qtext, masked:p.masked, time:new Date().toLocaleTimeString("zh-CN")});
      try { const r = await api("/api/ai/chat", {payload:p.payload}); AI.log.push({role:"ai", ok:true, text:JSON.stringify(r)}); }
      catch (e) { AI.log.push({role:"ai", ok:false, text:"调用大模型失败：" + e.message}); }
      $("#aiQ").value = ""; aiRender();
    } catch (e) { $("#aiPreview").innerHTML = errBox(e); }
    finally { $("#aiSend").disabled = false; }
  };
  $("#aiClear").onclick = () => { AI.map = {}; AI.rev = {}; AI.n = {}; AI.log = []; $("#aiPreview").innerHTML = ""; aiRender(); };
}
$("#scNew").onclick = () => scenForm(null);
$("#scEdit").onclick = async () => {
  const code = $("#scSel").value; if (!code) return scenForm(null);
  try { const s = asObjs(await q("scenarios")).find(x => x.Scenario === code); scenForm(s || null); } catch (e) { $("#scBox").innerHTML = errBox(e); }
};
