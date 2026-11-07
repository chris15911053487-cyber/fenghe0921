// 成本执行台 · wtabs.js — 多页签（用户 2026-11-06）：点菜单开一个页签，换页签时原来的内容（表格筛选、排序、滚动位置、抽屉钻取、查询结果）都留着。
// 每个菜单页最多一个页签，各有一个内容容器 p.el；不在前面的容器从页面上摘下来（多个页面共用 #lst、#dtlCsv、#mg* 这些 id，不能同时留在页面里）。
// 打开的页签记在 sessionStorage：刷新浏览器还在，单开的窗口各管各的。需要左右对照时用 wtWin 单开窗口。
// index.html 按顺序加载 js/ 下的脚本，共用全局作用域；加载时立即执行的代码只能用到本文件和前面文件里的名字。
"use strict";
const WT = {list:[], cur:null, panes:new Map()};   // list 打开的页面，cur 正在前面的页面，panes：页面 → {el, key, busy, redo, dr, sy, scr, w}
try { WT.list = (JSON.parse(sessionStorage.getItem("cc.wtabs") || "[]") || []).filter(tabOk); } catch (e) {}
function wtSave(){ try { sessionStorage.setItem("cc.wtabs", JSON.stringify(WT.list)); } catch (e) {} }
const wtName = t => { const b = document.querySelector(`#tabs button[data-t="${t}"]`); return b ? b.textContent : t; };
// 内容对应哪次运行、什么状态；不依赖运行的页面恒为空。切回来时不一致就重画
const wtKey = t => NORUN.has(t) || !SEL ? "" : SEL.RunId + ":" + SEL.Status;
const wtPane = t => { let p = WT.panes.get(t); if (!p) { p = {el:PAGES[t] ? null : document.createElement("div"), key:null, busy:0, redo:false, dr:null, sy:0, scr:[], w:0}; WT.panes.set(t, p); } return p; };
// 查询失败或还在加载时离开的页面，切回来要重画
const wtLoading = el => !el.children.length || (el.children.length === 1 && el.firstElementChild.matches(".empty") && /中…$/.test(el.textContent.trim()));
function wtLeave(t){
  const p = WT.panes.get(t); if (!p) return;
  p.dr = drStash(); p.sy = window.scrollY; p.w = window.innerWidth;
  if (!p.el) return;
  p.scr = [...p.el.querySelectorAll(".tw")].map(x => [x, x.scrollLeft, x.scrollTop]);
  if (p.busy) p.redo = true;
  p.el.remove();
}
// 把 TAB 放到前面。返回 {p, keep}：keep = 内容还能用，不用重画
function wtShow(quiet){
  const t = TAB, prev = WT.cur, moved = t !== prev;
  if (!WT.list.includes(t)) { const i = WT.list.indexOf(prev); WT.list.splice(i < 0 ? WT.list.length : i + 1, 0, t); wtSave(); }
  if (moved && prev) wtLeave(prev);
  WT.cur = t;
  const p = wtPane(t), ok = moved && (!!PAGES[t] || (p.key === wtKey(t) && !p.redo && !wtLoading(p.el)));
  if (p.el && $("#pane").firstElementChild !== p.el) $("#pane").replaceChildren(p.el);
  Object.entries(PAGES).forEach(([k, sel]) => { $(sel).hidden = k !== t; });
  $("#runCard").hidden = !!PAGES[t];
  wtBar();
  if (!ok) {
    if (!quiet) closeDrawer("tab");
    p.dr = null;
    if (moved) window.scrollTo(0, 0);
    return {p, keep:false};
  }
  if (MGS[t]) { MG = MGS[t]; if (MG.dirty) { MG.dirty = false; mgShow(); } }
  relayout();
  (p.scr || []).forEach(([x, l, y]) => { x.scrollLeft = l; x.scrollTop = y; });
  window.scrollTo(0, p.sy);
  if (p.dr) { drUnstash(p.dr); p.dr = null; }
  if (p.w && p.w !== window.innerWidth) window.dispatchEvent(new Event("resize"));   // 在后台时窗口大小变了：流程图等按宽度排的内容重排
  return {p, keep:true};
}
function wtBar(){
  const box = $("#wtList");
  box.classList.toggle("one", WT.list.length < 2);
  box.innerHTML = WT.list.map(t => `<div class="wt${t === TAB ? " on" : ""}" role="tab" data-t="${esc(t)}" title="${esc(wtName(t))}"><span>${esc(wtName(t))}</span><i title="关闭页签">×</i></div>`).join("");
  document.querySelectorAll("#tabs button[data-t]").forEach(b => b.classList.toggle("wto", WT.list.includes(b.dataset.t)));
  const on = box.querySelector(".wt.on"); if (on) on.scrollIntoView({block:"nearest", inline:"nearest"});
}
function wtGo(t){ TAB = t; try { localStorage.setItem("cc.tab", TAB); } catch (e) {} renderTab(); }
function wtClose(t){
  if (WT.list.length < 2) return;
  const i = WT.list.indexOf(t); if (i < 0) return;
  WT.list.splice(i, 1); wtSave();
  const p = WT.panes.get(t); if (p && p.el) p.el.remove();
  WT.panes.delete(t);
  if (t !== TAB) { wtBar(); return; }
  closeDrawer("tab"); WT.cur = null;
  wtGo(WT.list[Math.min(i, WT.list.length - 1)]);
}
function wtOthers(){
  WT.list.filter(t => t !== TAB).forEach(t => { const p = WT.panes.get(t); if (p && p.el) p.el.remove(); WT.panes.delete(t); });
  WT.list = [TAB]; wtSave(); wtBar();
}
// 单开窗口：sessionStorage 不带过去（noopener），新窗口只有这一页
function wtWin(t){
  const w = Math.min(1280, screen.availWidth), h = screen.availHeight;
  window.open(location.pathname + location.search + urlNow(t), "_blank", `noopener,popup,width=${w},height=${h}`);
}
// 外部改了这一页要显示的内容（成本追溯换了物料、报表换了编号），切过去时要重画
function wtStale(t){ const p = WT.panes.get(t); if (p) p.redo = true; }
// 表格是否还在某个后台页签或它收起的抽屉里
function wtHas(id){
  const s = "#" + id;
  for (const p of WT.panes.values()) {
    if (p.el && p.el.querySelector(s)) return true;
    if (p.dr && [p.dr, ...p.dr.stack].some(x => x.node && x.node.querySelector(s))) return true;
  }
  return false;
}
// 后台页签的查询回来后生成表格：列设置按页面记（table() 读 TAB），临时换成结果所属的页面
function wtAs(t, fn){ const t0 = TAB; TAB = t; try { fn(); } finally { TAB = t0; } }
$("#wtList").onclick = e => {
  const w = e.target.closest(".wt"); if (!w) return;
  if (e.target.tagName === "I") wtClose(w.dataset.t);
  else if (w.dataset.t !== TAB) wtGo(w.dataset.t);
};
$("#wtList").addEventListener("auxclick", e => { const w = e.target.closest(".wt"); if (w && e.button === 1) { e.preventDefault(); wtClose(w.dataset.t); } });
$("#wtRe").onclick = () => renderTab();
$("#wtWin").onclick = () => wtWin(TAB);
$("#wtOther").onclick = wtOthers;
