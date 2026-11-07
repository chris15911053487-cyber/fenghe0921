// 成本执行台 · rpt.js — “成本报表”页（用户 2026-10-30）：19 张 B1 端只读报表 MTC_CA_RPT_*，定义在 rptdefs.js（gen_rpt.py 生成）
// index.html 按顺序加载 js/ 下的脚本，共用全局作用域；加载时立即执行的代码只能用到本文件和前面文件里的名字。
// 报表调的是 B1 查询管理器里用的同一批过程，取数运行由过程决定（账期已生成凭单取 PostRunId，否则取 CalcRunId），不跟顶栏所选的运行走。
// 筛选值记在本机 cc.rpt.<编号>，当前报表 cc.rpt.cur；地址栏 #rpt?r=03。汇总行双击按 rptdefs 的 drill 在抽屉里打开明细（同一过程换显示方式、加行条件）。
"use strict";
const RPT_GRPS = ["核算结果", "核对", "管理分析"];
const rptDef = id => RPTDEFS.find(r => r.id === id);
let RPT_LISTS = null;
function rptSaved(id){ try { return JSON.parse(localStorage.getItem("cc.rpt." + id) || "null"); } catch (e) { return null; } }
function rptSave(id, v){ try { localStorage.setItem("cc.rpt." + id, JSON.stringify(v)); localStorage.setItem("cc.rpt.cur", id); } catch (e) {} }
const rptDefaults = r => Object.fromEntries(r.params.map(p => [p.name, p.def ?? ""]));
const rptArgs = (r, v) => Object.fromEntries(r.params.map(p => ["rp_" + p.name, String(v[p.name] ?? "")]));
// 下拉选项（物料组、费用池、客户类型、销售订单类型）：取一次，失败时当作没有选项（仍可手填）
async function rptLists(){
  if (RPT_LISTS) return RPT_LISTS;
  const get = a => q(a).then(asObjs).catch(() => []);
  const [grp, pool, custType, salType] = await Promise.all(["rptGrpList", "rptPoolList", "rptCustType", "rptSalType"].map(get));
  return RPT_LISTS = {grp, pool, custType, salType};
}
function rptField(p, v, L){
  const val = v[p.name] ?? "", id = "rpf_" + p.name, tip = p.hint ? ` title="${esc(p.hint)}"` : "";
  let inp;
  if (p.type === "fc") {
    const ops = [...$("#fc").options].map(o => `<option value="${esc(o.value)}"${o.value === val ? " selected" : ""}>${esc(o.value)}</option>`).join("");
    inp = `<select id="${id}"${tip}><option value="">${esc(p.hint && p.hint.startsWith("空 = ") ? p.hint.slice(4) : "（空）")}</option>${ops}</select>`;
  } else if (p.type === "sel" || p.type === "stype") {
    inp = `<select id="${id}"${tip}>${p.opts.map(([k, t]) => `<option value="${esc(k)}"${k === val ? " selected" : ""}>${esc(t)}</option>`).join("")}</select>`;
  } else if (p.type === "yn") {
    inp = `<input type="checkbox" id="${id}"${val === "Y" ? " checked" : ""}>`;
  } else {
    const list = L[p.type] || null;
    inp = `<input type="text" id="${id}" value="${esc(val)}" maxlength="500" placeholder="${esc(p.type === "num" ? (p.def || "") : "全部")}"${tip}${list ? ` list="${id}_l"` : ""}${p.type === "num" ? ' inputmode="decimal" style="width:7em"' : ""}>`
      + (list ? `<datalist id="${id}_l">${list.map(o => `<option value="${esc(o.Code)}">${esc(o.Name || "")}</option>`).join("")}</datalist>` : "");
  }
  return `<label class="${p.type === "yn" ? "yn" : ""}"><span>${esc(p.label)}</span>${inp}</label>`;
}
const rptRead = (r, box) => Object.fromEntries(r.params.map(p => {
  const el = box.querySelector("#rpf_" + p.name);
  return [p.name, !el ? "" : p.type === "yn" ? (el.checked ? "Y" : "N") : el.value.trim()];
}));
// 条件摘要（抽屉标题下、导出文件名用）
const rptCond = (r, v) => r.params.filter(p => v[p.name] && !(p.type === "yn" && v[p.name] === "N")).map(p => {
  const o = (p.opts || []).find(x => x[0] === v[p.name]);
  return `${p.label}：${o ? o[1] : p.type === "yn" ? "是" : v[p.name]}`;
}).join("；");
// 结果上方一行：这次取的是哪个账期的哪次运行（R00 的同一规则）
async function rptRunLine(r, v){
  const f0 = v.FcFrom ?? v.Fc ?? "", f1 = v.FcTo ?? v.Fc ?? "";
  if (r.id === "00") return "";
  try {
    const o = asObjs(await q("rpt00", {rp_FcFrom: f0, rp_FcTo: f0 ? (f1 || f0) : ""}));
    const xs = f0 ? o : o.filter(x => x["运行号"] != null).slice(0, 1);
    if (!xs.length) return `<div class="msg info">这个账期还没有成功的正式计算，报表没有数据。</div>`;
    return `<div class="hint rptrun">取数：` + xs.slice().reverse().map(x => x["运行号"] == null ? `${esc(x["账期"])} <b class="bad">未计算</b>`
      : `${esc(x["账期"])} 运行 <b>#${esc(x["运行号"])}</b>（${esc(x["取数来源"])}${x["账期状态"] ? "，" + esc(x["账期状态"]) : ""}）`).join("　") + `</div>`;
  } catch (e) { return ""; }
}
const RPT_WRAP = ["说明", "备注", "定价来源", "物料描述", "凭单批号", "未过账底稿·凭证代码", "分摊状态"];
function rptTable(r, v, res, el){
  if (res.columns.length === 1 && res.columns[0] === "说明") return `<div class="msg info">${esc(res.rows[0] ? res.rows[0][0] : "")}</div>`;
  const st = v.STYPE ?? "", dd = r.drill && r.drill[st || "0"];
  const html = table(res, {wrap: RPT_WRAP.filter(c => res.columns.includes(c)), freeze: Math.min(3, res.columns.filter(c => /账期|代码|物料|产品|客户|供应商|订单号|费用池|对账项|类别|凭证代码/.test(c)).length || 1),
    onRow: !!dd, empty: "没有符合条件的数据"});
  if (dd) setTimeout(() => bindRows(el, res, row => rptDrill(r, v, row)), 0);
  return html + (dd ? `<p class="hint">双击一行看明细（${esc(rptDef(dd.to || r.id).name)}）。</p>` : "");
}
async function rptQuery(r, v){
  const res = await q("rpt" + r.id, rptArgs(r, v), true);
  res.src = [{action: "rpt" + r.id, args: rptArgs(r, v)}];
  return res;
}
// 双击汇总行：drill.set 的值 = 行的列名（= 开头精确匹配，@ 开头沿用当前参数），在抽屉里逐层打开
async function rptDrill(r, v, row){
  const dd = r.drill && r.drill[(v.STYPE ?? "") || "0"]; if (!dd) return;
  const to = rptDef(dd.to || r.id), nv = dd.to ? rptDefaults(to) : Object.assign({}, v);
  if (dd.to) to.params.forEach(p => { if (p.name in v && !(p.name in dd.set) && p.type === "fc") nv[p.name] = v[p.name]; });
  if (dd.stype !== undefined) nv.STYPE = dd.stype;
  for (const [k, c] of Object.entries(dd.set)) {
    if (c.startsWith("@")) nv[k] = v[c.slice(1)] ?? "";
    else { const ex = c.startsWith("="), x = row[ex ? c.slice(1) : c]; nv[k] = x === null || x === undefined || x === "" ? "" : (ex ? "=" : "") + String(x); }
  }
  const el = drawer(`R${to.id} ${to.name}`);
  el.innerHTML = `<p class="hint">${esc(rptCond(to, nv))}</p><div class="empty">加载中…</div>`;
  try {
    const [res, line] = await Promise.all([rptQuery(to, nv), rptRunLine(to, nv)]);
    el.innerHTML = `<p class="hint">${esc(rptCond(to, nv))}</p>` + line + rptTable(to, nv, res, el);
  } catch (e) { el.innerHTML = errBox(e); }
}
function rptB1(r){
  const el = drawer(`R${r.id} ${r.name} · 在 SAP 中打开`);
  el.innerHTML = `<p class="hint">B1 → 工具 → 查询 → 查询管理器 → 新建，整段粘贴后保存到分类“成本报表（新）”（也可以由管理员运行 <span class="mono">python3 新框架/tools/sl_import_queries.py</span> 一次登记 19 条）。执行时依次弹出参数框，留空 = 全部；参数顺序：</p>`
    + `<ol class="hint">${r.params.map((p, i) => `<li>[%${i}] ${esc(p.label)}${p.opts ? "：" + esc(p.opts.map(([k, t]) => (k || "空") + " = " + t).join("；")) : p.type === "yn" ? "：Y / N（空 = N）" : p.hint ? "：" + esc(p.hint) : ""}</li>`).join("")}</ol>`
    + preBox(r.b1) + `<div class="bar"><button class="btn primary" id="rptCopyB1">复制语句</button></div>`;
  el.querySelector("#rptCopyB1").onclick = () => {
    const ok = () => toast("已复制，粘贴到 B1 查询管理器");
    if (navigator.clipboard && window.isSecureContext) navigator.clipboard.writeText(r.b1).then(ok, () => { copyFallback(esc(r.b1)); ok(); });
    else { copyFallback(esc(r.b1)); ok(); }
  };
}
async function renderRpt(pane){
  let cur = RPT_CUR; if (!cur || !rptDef(cur)) { try { cur = localStorage.getItem("cc.rpt.cur"); } catch (e) {} }
  if (!cur || !rptDef(cur)) cur = "03";
  RPT_CUR = cur; syncUrl(false);
  const r = rptDef(cur), v = Object.assign(rptDefaults(r), rptSaved(cur) || {});
  const opts = RPT_GRPS.map(g => `<optgroup label="${esc(g)}">${RPTDEFS.filter(x => x.grp === g).map(x => `<option value="${x.id}"${x.id === cur ? " selected" : ""}>R${x.id} ${esc(x.name)}</option>`).join("")}</optgroup>`).join("");
  pane.innerHTML = `<div class="bar"><select id="rptSel" style="max-width:100%">${opts}</select><span class="sp"></span>
      <button class="btn" id="rptB1" title="复制这张报表的 B1 查询管理器语句">在 SAP 中打开</button></div>`
    + note(esc(r.desc) + `<br>这些报表是 B1 端存储过程（${esc(r.proc)}），B1 查询管理器和这里调的是同一个过程，口径只有一套；取数运行：账期已生成凭单取凭单所用运行，否则取最近一次成功正式运行（与顶栏所选的运行无关，见 R00）。代码类条件按开头匹配，多个用逗号，前面加 = 精确匹配。`, "rpt")
    + `<div class="rptform" id="rptForm"><div class="empty">加载中…</div></div>
       <div class="bar"><button class="btn primary" id="rptGo">查询</button><button class="btn" id="rptReset">恢复默认条件</button></div>
       <div id="rptOut"></div>`;
  $("#rptSel").onchange = () => { RPT_CUR = $("#rptSel").value; try { localStorage.setItem("cc.rpt.cur", RPT_CUR); } catch (e) {} syncUrl(true); renderRpt(pane); };
  $("#rptB1").onclick = () => rptB1(r);
  const L = await rptLists();
  if (RPT_CUR !== cur || TAB !== "rpt") return;
  const form = $("#rptForm");
  form.innerHTML = r.params.map(p => rptField(p, v, L)).join("");
  const go = async () => {
    const nv = rptRead(r, form); rptSave(r.id, nv);
    const out = $("#rptOut");
    if (r.need && !r.need.some(k => nv[k])) { out.innerHTML = `<div class="msg info">这张报表行数多，请至少填一项：${esc(r.params.filter(p => r.need.includes(p.name)).map(p => p.label).join("、"))}。</div>`; return; }
    out.innerHTML = `<div class="empty">查询中…</div>`;
    try {
      const [res, line] = await Promise.all([rptQuery(r, nv), rptRunLine(r, nv)]);
      if (RPT_CUR !== r.id || TAB !== "rpt") return;
      out.innerHTML = line + rptTable(r, nv, res, out);
    } catch (e) { out.innerHTML = errBox(e) + `<div class="hint">数据库还没有部署 新框架/sql/21_reports.sql 时会出现这个错误。</div>`; }
  };
  $("#rptGo").onclick = go;
  $("#rptReset").onclick = () => { rptSave(r.id, rptDefaults(r)); renderRpt(pane); };
  form.addEventListener("keydown", e => { if (e.key === "Enter" && e.target.tagName === "INPUT") { e.preventDefault(); go(); } });
  form.addEventListener("change", e => { if (e.target.tagName === "SELECT" || e.target.type === "checkbox") go(); });
  if (!r.need || r.need.some(k => v[k])) go();
}
