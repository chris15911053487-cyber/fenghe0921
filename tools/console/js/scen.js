// 成本执行台 · scen.js — 模拟场景维护
// index.html 按顺序加载 js/ 下的脚本，共用全局作用域；加载时立即执行的代码只能用到本文件和前面文件里的名字。
"use strict";
// ---------------- 模拟场景维护（只写 MTC_CA_C_SCENARIO*） ----------------
const OVR = {ITEM_PRICE_PCT:"采购价 %（键 = 物料，空 = 全部）", POOL_PCT:"费用池金额 %（键 = 费用池，空 = 全部）", HOURS_PCT:"单位工时 %（键 = 产品，空 = 全部）"};
const ex = (action, args) => api("/api/exec", {action, args});
const exMsg = r => { const o = asObjs(r)[0] || {}; if (Number(o.Code) !== 0) throw new Error(o.Msg || "保存失败"); return o.Msg; };
async function loadScenSel(pick){
  try {
    const r = asObjs(await q("scenarios"));
    $("#scSel").innerHTML = r.length ? r.map(s => `<option value="${esc(s.Scenario)}">${esc(s.Scenario)} ${esc(s.Title || "")}</option>`).join("") : `<option value="">（还没有场景）</option>`;
    if (pick) $("#scSel").value = pick;
    $("#scen").innerHTML = $("#scSel").innerHTML;
  } catch (e) { $("#scBox").innerHTML = errBox(e); }
}
function scenForm(s){
  const isNew = !s;
  $("#scBox").innerHTML = `<div class="detail">
    <div class="row"><label>编码</label><input type="text" id="scCode" maxlength="30" value="${esc(s ? s.Scenario : "")}" ${isNew ? "" : "disabled"}></div>
    <div class="row"><label>标题</label><input type="text" id="scTitle" maxlength="100" value="${esc(s ? s.Title : "")}"></div>
    <div class="row"><label>说明</label><input type="text" id="scDescr" maxlength="500" value="${esc(s ? s.Descr || "" : "")}" style="width:100%"></div>
    <div class="row"><button class="btn primary" id="scSave">保存</button>${isNew ? "" : `<button class="btn" id="scDel">删除场景</button>`}<button class="btn" id="scClose">收起</button></div>
    <div id="scMsg"></div><div id="scOvr"></div></div>`;
  const msg = (t, ok) => { $("#scMsg").innerHTML = `<div class="msg ${ok ? "ok" : "err"}">${esc(t)}</div>`; };
  $("#scClose").onclick = () => { $("#scBox").innerHTML = ""; };
  $("#scSave").onclick = async () => {
    const code = $("#scCode").value.trim(), title = $("#scTitle").value.trim();
    if (!/^[A-Za-z0-9_\-]{1,30}$/.test(code)) return msg("编码只能用字母、数字、下划线、横线", false);
    try { msg(exMsg(await ex("scenSave", {scenCode:code, title, descr:$("#scDescr").value.trim(), user:$("#user").value.trim() || "user"})), true);
          await loadScenSel(code); if (isNew) scenForm({Scenario:code, Title:title, Descr:$("#scDescr").value.trim()}); }
    catch (e) { msg(e.message, false); }
  };
  if (isNew) return;
  $("#scDel").onclick = async () => {
    if (!confirm(`删除场景 ${s.Scenario} 和它的全部假设？已有的模拟运行记录保留。`)) return;
    try { exMsg(await ex("scenDel", {scenCode:s.Scenario})); $("#scBox").innerHTML = ""; await loadScenSel(); } catch (e) { msg(e.message, false); }
  };
  loadOvr(s.Scenario, msg);
}
async function loadOvr(code, msg){
  const box = $("#scOvr");
  try {
    const r = await q("scenOvr", {scenCode:code}), o = asObjs(r);
    box.innerHTML = `<h3>假设</h3>` + (o.length ? `<div class="tw"><table><thead><tr><th>#</th><th>类型</th><th>键</th><th>%</th><th>说明</th><th></th></tr></thead><tbody>`
      + o.map(x => `<tr><td>${x.LineNo}</td><td>${esc(x.OvrType)}</td><td>${esc(x.KeyCode || "全部")}</td><td class="n">${fmtNum(x.Value)}</td><td>${esc(x.Descr || "")}</td><td><button class="btn" data-del="${x.LineNo}">删除</button></td></tr>`).join("")
      + `</tbody></table></div>` : `<p class="hint">还没有假设；没有假设的模拟计算结果与正式计算相同。</p>`)
      + `<div class="row" style="margin-top:8px"><select id="ovT">${Object.entries(OVR).map(([k, v]) => `<option value="${k}">${esc(v)}</option>`).join("")}</select></div>
         <div class="row"><input type="text" id="ovK" placeholder="键（空 = 全部）" maxlength="100" style="width:130px"><input type="text" id="ovV" placeholder="%，如 10 或 -5" maxlength="12" style="width:110px"></div>
         <div class="row"><input type="text" id="ovD" placeholder="说明" maxlength="500" style="flex:1"><button class="btn" id="ovAdd">添加</button></div>`;
    box.querySelectorAll("button[data-del]").forEach(b => b.onclick = async () => {
      try { exMsg(await ex("scenOvrDel", {scenCode:code, lineNo:b.dataset.del})); loadOvr(code, msg); } catch (e) { msg(e.message, false); }
    });
    $("#ovAdd").onclick = async () => {
      const v = $("#ovV").value.trim();
      if (!/^-?\d{1,5}(\.\d{1,6})?$/.test(v)) return msg("百分比格式不对", false);
      try { msg(exMsg(await ex("scenOvrSave", {scenCode:code, lineNo:"0", ovrType:$("#ovT").value, keyCode:$("#ovK").value.trim(), pct:v, descr:$("#ovD").value.trim()})), true); loadOvr(code, msg); }
      catch (e) { msg(e.message, false); }
    };
  } catch (e) { box.innerHTML = errBox(e); }
}
