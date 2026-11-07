// 成本执行台 · drawer.js — 右侧明细抽屉 drawer()：逐层钻取、面包屑、拖动 / 浮动、分段折叠；口径说明 note()
// index.html 按顺序加载 js/ 下的脚本，共用全局作用域；加载时立即执行的代码只能用到本文件和前面文件里的名字。
"use strict";
// ---------------- 明细抽屉 ----------------
// drawer(title) 打开右侧抽屉，返回一个空的内容容器。在抽屉里的表格上点行（DRILL_IN）时把当前一层整块压栈（保留事件），
// 面包屑和“返回”回到上一层；从页面主体点行时从第一层重新开始。opt.replace：替换当前一层（同一层换条件）
const DR = {stack:[], title:"", src:null, row:null};   // src / row：从哪张主页面表格的哪一行打开（双击方式下单击别的行跟随）
function drawer(title, opt = {}){
  const dw = $("#drawer"), body = $("#drBody"), cur = body.firstElementChild;
  if (!dw.hidden && cur && (DRILL_IN || opt.replace)) {
    body.removeChild(cur);
    if (!opt.replace) DR.stack.push({node:cur, title:DR.title, top:body.scrollTop, link:LINK});
  } else { DR.stack = []; body.innerHTML = ""; DR.src = DR.row = null; if (LINK) { LINK = null; syncUrl(false); } }
  drLinkBtn();
  DR.title = title;
  const el = document.createElement("div"); body.appendChild(el);
  dw.hidden = false; body.scrollTop = 0; drCrumb();
  return el;
}
function drCrumb(){
  const all = [...DR.stack.map(s => s.title), DR.title];
  $("#drCrumb").innerHTML = all.map((t, k) => k < all.length - 1 ? `<a data-k="${k}">${esc(t)}</a>` : `<b>${esc(t)}</b>`).join(" › ");
  $("#drCrumb").title = all.join(" › ");
  $("#drBack").hidden = !DR.stack.length;
}
function drBackTo(k){
  const s = DR.stack[k]; if (!s) return;
  DR.stack = DR.stack.slice(0, k);
  const body = $("#drBody"); body.innerHTML = ""; body.appendChild(s.node);
  DR.title = s.title; drCrumb(); body.scrollTop = s.top;
  if (!sameObj(s.link, LINK)) { LINK = s.link || null; drLinkBtn(); syncUrl(false); }
}
// how：true = 用户点 ✕ / Esc（这一条历史是打开明细时加的就“后退”回去）；"tab" = 换页面（由 renderTab 写地址）
function closeDrawer(how){
  if ($("#drawer").hidden) return;
  $("#drawer").hidden = true; $("#drBody").innerHTML = ""; DR.stack = []; DR.src = DR.row = null;
  document.querySelectorAll("main tr.sel").forEach(x => x.classList.remove("sel"));
  if (!LINK) return;
  LINK = null;
  if (how === true && !URL_APPLY && history.state && history.state.dr) history.back();
  else if (how !== "tab") syncUrl(false);
}
$("#drClose").onclick = () => closeDrawer(true);
$("#drLink").onclick = () => copyLink();
$("#drBack").onclick = () => drBackTo(DR.stack.length - 1);
$("#drCrumb").onclick = e => { const a = e.target.closest("a[data-k]"); if (a) drBackTo(Number(a.dataset.k)); };
$("#drWide").onclick = () => { const w = $("#drawer").classList.toggle("wide"); $("#drWide").textContent = w ? "还原" : "全屏"; };
// 拖动抽屉左边缘调整宽度，记在本机
let DRW = 0; try { DRW = Number(localStorage.getItem("cc.drw")) || 0; } catch (e) {}
const setDrw = px => $("#drawer").style.setProperty("--drw", px + "px");
if (DRW) setDrw(DRW);
$("#drGrip").onmousedown = e => {
  e.preventDefault();
  const mv = ev => { DRW = Math.round(Math.max(420, Math.min(window.innerWidth - 80, window.innerWidth - ev.clientX))); setDrw(DRW); };
  const up = () => { document.removeEventListener("mousemove", mv); document.removeEventListener("mouseup", up); try { localStorage.setItem("cc.drw", String(DRW)); } catch (e) {} };
  document.addEventListener("mousemove", mv); document.addEventListener("mouseup", up);
};
// 抽屉里一层有两段以上（多个 h3）时，点标题收起 / 展开这一段（到下一个标题为止）；按标题文字记在本机 cc.drfold
let DRFOLD = {}; try { DRFOLD = JSON.parse(localStorage.getItem("cc.drfold") || "{}") || {}; } catch (e) {}
const foldKey = h => h.textContent.replace(/\s+/g, " ").trim().slice(0, 60);
const foldHead = h => h.parentElement && h.parentElement.classList.contains("bar") && h.parentElement.parentElement && h.parentElement.parentElement.closest("#drBody") ? h.parentElement : h;
function foldApply(h){
  const on = h.classList.contains("folded");
  for (let x = foldHead(h).nextElementSibling; x; x = x.nextElementSibling) {
    if (x.matches("h3") || x.querySelector("h3")) break;
    x.classList.toggle("fx", on);
  }
}
let FOLD_T = 0;
new MutationObserver(() => { cancelAnimationFrame(FOLD_T); FOLD_T = requestAnimationFrame(() => {
  const layer = $("#drBody").firstElementChild; if (!layer) return;
  const hs = [...layer.querySelectorAll("h3")]; if (hs.length < 2) return;
  for (const h of hs) {
    if (!h.dataset.fh) { h.dataset.fh = 1; h.classList.add("fh"); h.title = "点击收起 / 展开这一段"; if (DRFOLD[foldKey(h)]) h.classList.add("folded"); }
    if (h.classList.contains("folded")) foldApply(h);
  }
}); }).observe($("#drBody"), {childList:true, subtree:true});
$("#drBody").addEventListener("click", e => {
  const h = e.target.closest("h3.fh"); if (!h || e.target.closest("a, button, input, select")) return;
  const on = h.classList.toggle("folded"), k = foldKey(h);
  if (on) DRFOLD[k] = 1; else delete DRFOLD[k];
  const ks = Object.keys(DRFOLD); if (ks.length > 300) delete DRFOLD[ks[0]];
  try { localStorage.setItem("cc.drfold", JSON.stringify(DRFOLD)); } catch (e) {}
  foldApply(h);
});
// 拖标题栏移动：第一次拖动时从右侧停靠变成浮动窗口；位置、大小和是否浮动记在本机 cc.drf。窄屏（≤900）不浮动
let DRF = null; try { DRF = JSON.parse(localStorage.getItem("cc.drf") || "null"); } catch (e) {}
const saveDrf = () => { try { localStorage.setItem("cc.drf", JSON.stringify(DRF)); } catch (e) {} };
function drFloatApply(){
  const dw = $("#drawer"), on = !!(DRF && DRF.on) && window.innerWidth > 900;
  dw.classList.toggle("float", on); $("#drDock").hidden = !on;
  if (!on) return;
  // 窗口变小后把它拉回可见范围
  const hdr = parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--hdr")) || 0;
  DRF.w = Math.min(DRF.w, window.innerWidth); DRF.h = Math.min(DRF.h, window.innerHeight - hdr);
  DRF.x = Math.max(0, Math.min(DRF.x, window.innerWidth - 120)); DRF.y = Math.max(hdr, Math.min(DRF.y, window.innerHeight - 40));
  for (const [k, v] of [["--fx", DRF.x], ["--fy", DRF.y], ["--fw", DRF.w], ["--fh", DRF.h]]) dw.style.setProperty(k, v + "px");
}
function drDock(){ if (DRF) { DRF.on = false; saveDrf(); } drFloatApply(); }
$("#drDock").onclick = drDock;
$("#drawer .dh").ondblclick = e => { if (e.target.closest("a, button")) return; if (DRF && DRF.on) drDock(); };
$("#drawer .dh").onpointerdown = e => {
  const dw = $("#drawer");
  if (e.button !== 0 || e.target.closest("a, button") || dw.classList.contains("wide") || window.innerWidth <= 900) return;
  const r0 = dw.getBoundingClientRect(), dx = e.clientX - r0.left, dy = e.clientY - r0.top, x0 = e.clientX, y0 = e.clientY;
  let started = false;
  const mv = ev => {
    if (!started) {
      if (Math.abs(ev.clientX - x0) + Math.abs(ev.clientY - y0) < 5) return;   // 小于 5px 当作点击
      started = true; dw.classList.add("moving");
      if (!(DRF && DRF.on)) DRF = {on:true, x:r0.left, y:r0.top, w:r0.width, h:Math.min(r0.height, Math.round(window.innerHeight * .75))};
    }
    DRF.x = Math.round(ev.clientX - dx); DRF.y = Math.round(ev.clientY - dy); drFloatApply();
  };
  const up = () => {
    document.removeEventListener("pointermove", mv); document.removeEventListener("pointerup", up);
    dw.classList.remove("moving"); if (started) saveDrf();
  };
  document.addEventListener("pointermove", mv); document.addEventListener("pointerup", up);
  e.preventDefault();
};
// 浮动时右下角改大小（CSS resize）后记下尺寸
new ResizeObserver(() => {
  const dw = $("#drawer");
  if (!dw.classList.contains("float") || dw.classList.contains("wide") || dw.hidden || !DRF) return;
  DRF.w = dw.offsetWidth; DRF.h = dw.offsetHeight; saveDrf();
}).observe($("#drawer"));
window.addEventListener("resize", drFloatApply);
drFloatApply();

// 口径说明默认收起，展开状态按页记在本机
let NOTES = {}; try { NOTES = JSON.parse(localStorage.getItem("cc.notes") || "{}") || {}; } catch (e) {}
const note = (html, key = TAB) => `<details class="note" data-k="${esc(key)}"${NOTES[key] ? " open" : ""}><summary>ⓘ 口径说明</summary><p class="hint">${html}</p></details>`;
document.addEventListener("toggle", e => {
  const d = e.target; if (!d.matches || !d.matches("details.note[data-k]")) return;
  if (d.open) NOTES[d.dataset.k] = 1; else delete NOTES[d.dataset.k];
  try { localStorage.setItem("cc.notes", JSON.stringify(NOTES)); } catch (e) {}
}, true);
