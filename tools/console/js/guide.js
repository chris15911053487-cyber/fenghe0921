// 成本执行台 · guide.js — 左侧菜单最下面“使用手册”页（用户 2026-11-07：交付文档不再出 Word / PDF，放进执行台）
// 内容在 guidedata.js（交付文档/tools/build_web.py 从 交付文档/src/*.md 生成）；本页只负责目录、查找、跳转、实时清单和月结清单勾选。
// index.html 按顺序加载 js/ 下的脚本，共用全局作用域；加载时立即执行的代码只能用到本文件和前面文件里的名字。
"use strict";
const GD_LS = k => { try { return localStorage.getItem(k); } catch (e) { return null; } };
const GD_SET = (k, v) => { try { localStorage.setItem(k, v); } catch (e) {} };
// 【实时：…】块：打开时从登记表现查，和“说明书”页同一批查询；查不到（没部署、离线）时说明去哪里看
const GD_LIVE = {
  checks: async () => table(await q("metaChecks"), {wrap:["Purpose", "Scene"], fmt:{IsBlock: v => v === "Y" ? "阻断" : "", Stage: v => esc({PRE:"计算前", POST:"计算后", CMP:"新旧比对"}[v] || v)}, sum:false}),
  rules: async () => table(await q("metaRules"), {wrap:["Descr", "Basis"], sum:false}),
  params: async () => { const fc = ($("#fc") && $("#fc").value) || (SEL && SEL.FcCode) || "";
    return `<p class="hint">账期 ${esc(fc)} 适用的取值。</p>` + table(await q("paramOverview", {fc}), {hide:["SortNo"], wrap:["CnName", "Hint", "EffValue"], sum:false}); },
  reports: async () => table({columns:["编号", "报表", "分组", "说明"], rows: RPTDEFS.map(r => ["R" + r.id, r.name, r.grp, r.desc])}, {wrap:["说明"], freeze:2, sum:false}),
};
function renderGuide(pane){
  const docs = GUIDE || [];
  if (!docs.length) { pane.innerHTML = `<div class="empty">还没有手册内容：运行 python3 交付文档/tools/build_web.py 生成 js/guidedata.js。</div>`; return; }
  let cur = GD_LS("cc.guide"); if (!docs.some(d => d.id === cur)) cur = docs[0].id;
  pane.innerHTML = `<div class="gd">
    <aside class="gd-side">
      <div class="gd-q"><input type="search" id="gdQ" placeholder="在全部手册里查找" maxlength="40"></div>
      <div id="gdHits" hidden></div>
      <nav id="gdToc">${docs.map(d => `<div class="gd-d" data-doc="${esc(d.id)}"><button class="gd-dt">${esc(d.menu)}</button>`
        + `<div class="gd-sub">${d.toc.map(t => `<a class="lv${t.lv}" data-sec="${esc(t.id)}">${esc(t.t)}</a>`).join("")}</div></div>`).join("")}</nav>
      <p class="hint gd-tip">截图经过脱敏处理，物料、业务伙伴、人员和金额都不是真实数据。</p>
    </aside>
    <article class="gd-doc" id="gdDoc"></article></div>`;
  const side = pane.querySelector(".gd-side"), art = pane.querySelector("#gdDoc");
  const show = (id, sec) => {
    const d = docs.find(x => x.id === id) || docs[0];
    if (art.dataset.doc !== d.id) {
      art.dataset.doc = d.id; GD_SET("cc.guide", d.id);
      art.innerHTML = `<header class="gd-h"><h1>${esc(d.title)}</h1>${d.subtitle ? `<p class="hint">${esc(d.subtitle)}</p>` : ""}`
        + `<div class="bar"><span class="sp"></span><button class="btn" id="gdPrint" title="只打印这份文档，可在打印窗口选“另存为 PDF”">打印</button></div></header>` + d.html;
      gdFill(art, d.id);
      art.querySelector("#gdPrint").onclick = () => gdPrint(art);
    }
    side.querySelectorAll(".gd-d").forEach(x => x.classList.toggle("on", x.dataset.doc === d.id));
    const el = sec && art.querySelector("#" + CSS.escape(sec));
    if (el) { el.scrollIntoView({block:"start"}); el.classList.remove("gd-flash"); void el.offsetWidth; el.classList.add("gd-flash"); }
    else window.scrollTo(0, 0);
  };
  // 目录、正文里的“第 N 章”、《文档》链接都走这里；页签重画时 pane 不换，所以用 onclick 不叠加监听
  pane.onclick = e => {
    const a = e.target.closest("[data-sec], .gd-dt, .gd-ln[data-doc]"); if (!a || !pane.contains(a)) return;
    e.preventDefault();
    const dEl = a.closest(".gd-d");
    if (a.classList.contains("gd-dt")) return show(dEl.dataset.doc);
    show(a.dataset.doc || (dEl && dEl.dataset.doc) || art.dataset.doc, a.dataset.sec);
  };
  // 查找：按标题分段，列出命中的段落；点结果跳过去
  const idx = gdIndex(docs);
  const qEl = pane.querySelector("#gdQ"), hits = pane.querySelector("#gdHits"), toc = pane.querySelector("#gdToc");
  qEl.oninput = () => {
    const v = qEl.value.trim().toLowerCase();
    hits.hidden = !v; toc.hidden = !!v;
    if (!v) return;
    const m = idx.filter(s => s.text.toLowerCase().includes(v)).slice(0, 60);
    hits.innerHTML = m.length ? m.map(s => { const i = s.text.toLowerCase().indexOf(v), a = Math.max(0, i - 18);
        return `<a class="gd-hit" data-doc="${esc(s.doc)}" data-sec="${esc(s.sec)}"><b>${esc(s.title)}</b><span>${esc(s.docName)}</span>`
          + `<small>${a ? "…" : ""}${esc(s.text.slice(a, i))}<mark>${esc(s.text.slice(i, i + v.length))}</mark>${esc(s.text.slice(i + v.length, i + v.length + 40))}</small></a>`; }).join("")
      : `<div class="empty">没有找到</div>`;
  };
  show(cur);
}
// 每个二级以上标题到下一个标题之间算一段
function gdIndex(docs){
  const out = [], box = document.createElement("div");
  for (const d of docs) {
    box.innerHTML = d.html;
    let sec = {doc:d.id, docName:d.menu, sec:"", title:d.title, text:""};
    out.push(sec);
    for (const el of box.children) {
      if (/^H[23]$/.test(el.tagName) && el.id) { sec = {doc:d.id, docName:d.menu, sec:el.id, title:el.textContent, text:el.textContent + " "}; out.push(sec); }
      else sec.text += el.textContent.replace(/\s+/g, " ") + " ";
    }
  }
  return out.filter(s => s.text.trim());
}
function gdFill(art, did){
  // 截图还没放进 img/ 时显示占位框，不显示破图
  art.querySelectorAll("img[data-shot]").forEach(img => { img.onerror = () => { img.replaceWith(Object.assign(document.createElement("div"), {className:"gd-todo", textContent:"截图待补：" + img.alt})); }; });
  art.querySelectorAll(".gd-live").forEach(async el => {
    const f = GD_LIVE[el.dataset.live];
    if (!f) { el.innerHTML = `<div class="hint">未知的清单 ${esc(el.dataset.live)}</div>`; return; }
    try { el.innerHTML = await f(); }
    catch (e) { el.innerHTML = `<div class="msg info">这份清单从数据库登记表实时读取，现在读不到（${esc(e.message || e)}）。也可以到“说明书”页查看。</div>`; }
  });
  // 月结清单勾选：按文档记在本机，换月时点“清空勾选”
  const cks = [...art.querySelectorAll(".gd-ck")];
  if (cks.length) {
    const key = "cc.guideck." + did;
    let st = []; try { st = JSON.parse(GD_LS(key) || "[]"); } catch (e) {}
    cks.forEach((c, i) => { c.checked = !!st[i]; c.onchange = () => { GD_SET(key, JSON.stringify(cks.map(x => x.checked))); gdCkCount(art, cks); }; });
    const bar = art.querySelector(".gd-h .bar");
    bar.insertAdjacentHTML("afterbegin", `<span class="hint" id="gdCkN"></span>`);
    bar.insertAdjacentHTML("beforeend", `<button class="btn" id="gdCkClr">清空勾选</button>`);
    art.querySelector("#gdCkClr").onclick = () => { cks.forEach(c => c.checked = false); GD_SET(key, "[]"); gdCkCount(art, cks); };
    gdCkCount(art, cks);
  }
}
function gdCkCount(art, cks){ const n = cks.filter(c => c.checked).length; art.querySelector("#gdCkN").textContent = `已完成 ${n} / ${cks.length} 项（勾选只记在本机浏览器）`; }
// 打印当前文档：另开一个只有正文的窗口，样式跟随当前主题的浅色版
function gdPrint(art){
  const w = window.open("", "_blank"); if (!w) { toast("浏览器拦截了弹出窗口"); return; }
  const css = [...document.querySelectorAll('link[rel="stylesheet"]')].map(l => `<link rel="stylesheet" href="${esc(l.href)}">`).join("");
  const body = art.cloneNode(true); body.querySelectorAll(".bar").forEach(x => x.remove());
  w.document.write(`<!doctype html><html data-ui-theme="mono"><head><meta charset="utf-8"><title>${esc(art.querySelector("h1").textContent)}</title>${css}</head><body class="gd-printing"><article class="gd-doc">${body.innerHTML}</article></body></html>`);
  w.document.close(); w.onload = () => w.print();
}
