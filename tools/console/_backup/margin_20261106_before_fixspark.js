// 成本执行台 · margin.js — 走势页公用部分（折线 / 堆叠柱、迷你图、物料 × 月份主表、对比勾选）+ “R23 销售毛利走势”（用户 2026-11-06）。R22 的页面在 costtrend.js。
// 每页一个配置 c（mgPage 登记）：报表编号、指标、合计列、取值 val、概览图、单品抽屉；MG = 当前页状态。过程返回长表，都在页面上汇总。
// index.html 按顺序加载 js/ 下的脚本，共用全局作用域；加载时立即执行的代码只能用到本文件和前面文件里的名字。
// 上面两张对比图 + 下面一行一个物料（N 月合计 4 列 + 选定指标的月份列）；已开票 / 暂估等细分不进主表，单品抽屉里看。条件和报表页共用 cc.rpt.23。
"use strict";
const MG_MAX = 6;   // 对比图最多几个物料（主题图表色 + 形状能区分的数量）
const MG_SHAPE = ["circle", "square", "tri", "diamond", "down", "hex"];
const MG_COLOR = [1, 6, 5, 4, 3, 2];   // 取主题 --c-chart-N 的顺序：相邻两色尽量拉开
const MG_NOI = "(未归属产品)";
const MGS = {};
let MG = null;
function mgPage(tab, c){ MGS[tab] = {tab, c, data:null, pick:new Map(), ind:null, chart:c.chart.slice(), seq:0}; }
const mgSK = k => "cc.mg." + (MG.c.sk ? MG.c.sk + "." : "") + k;
function mgGet(k, d){ try { const s = localStorage.getItem(k); return s === null ? d : JSON.parse(s); } catch (e) { return d; } }
function mgPut(k, v){ try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) {} }
const mgMonth = (fc, k) => { const [y, m] = fc.split("-").map(Number), t = y * 12 + m - 1 + k; return Math.floor(t / 12) + "-" + String(t % 12 + 1).padStart(2, "0"); };
const mgNow = () => { const d = new Date(); return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0"); };
function mgAdd(o, x){ for (const k of Object.keys(o)) o[k] += Number(x[k]) || 0; return o; }
const mgRound = (v, d) => v === null || !isFinite(v) ? null : Number(v.toFixed(d));
const mgVal = (o, ind) => MG.c.val(o, ind);
function mgValSale(o, ind){
  if (!o) return null;
  switch (ind) {
    case "毛利": return mgRound(o.rev - o.cost, 2);
    case "毛利率 %": return o.rev ? mgRound((o.rev - o.cost) * 100 / o.rev, 2) : null;
    case "收入": return mgRound(o.rev, 2);
    case "成本": return mgRound(o.cost, 2);
    case "数量": return mgRound(o.qty, 6);
    case "单位售价": return o.qty ? mgRound(o.rev / o.qty, 4) : null;
    case "单位成本": return o.qty ? mgRound(o.cost / o.qty, 4) : null;
  }
  return null;
}
// 长表 → 物料 × 月份。月份按截止账期往前连续排，没有发生的月份也占一列
function mgBuild(res, months, v, n){
  const c = MG.c, map = new Map(), all = {tot:c.zero(), m:{}};
  for (const x of asObjs(res)) {
    const code = x[c.code], fc = x["账期"], o = c.row(x);
    if (!map.has(code)) map.set(code, {code, name:x[c.nameCol], grp:x["物料组名称"], tot:c.zero(), m:{}});
    const it = map.get(code);
    it.m[fc] = mgAdd(it.m[fc] || c.zero(), o); mgAdd(it.tot, o);
    all.m[fc] = mgAdd(all.m[fc] || c.zero(), o); mgAdd(all.tot, o);
  }
  const items = [...map.values()].sort((a, b) => c.rank(b.tot) - c.rank(a.tot));
  return {months, items, all, v, n, src:res.src, empty:months.filter(f => !all.m[f])};
}
// 对比的物料：沿用上次勾选里这次还在的；一个都没有时取毛利绝对值最大的 5 个。颜色跟物料走，去掉别的物料不换色
function mgDefaultPick(d){
  const old = [...MG.pick.keys()].filter(c => d.items.some(x => x.code === c));
  const pick = new Map(); old.forEach(c => pick.set(c, MG.pick.get(c)));
  if (!pick.size) d.items.filter(x => x.code !== MG_NOI).slice().sort((a, b) => Math.abs(MG.c.rank(b.tot)) - Math.abs(MG.c.rank(a.tot))).slice(0, 5).forEach((x, i) => pick.set(x.code, i));
  MG.pick = pick;
}
const mgSlot = () => { const used = new Set(MG.pick.values()); for (let i = 0; i < MG_MAX; i++) if (!used.has(i)) return i; return -1; };
const mgColor = s => `rgb(var(--c-chart-${MG_COLOR[s]}))`;
const mgShort = (t, n) => { t = String(t ?? ""); return t.length > n ? t.slice(0, n - 1) + "…" : t; };
function mgMark(shape, x, y, r, color){
  const a = `fill="${color}" stroke="var(--surface)" stroke-width="2"`, poly = p => `<polygon points="${p.map(([u, w]) => (x + u * r).toFixed(1) + "," + (y + w * r).toFixed(1)).join(" ")}" ${a}/>`;
  switch (shape) {
    case "square": return `<rect x="${x - r * .9}" y="${y - r * .9}" width="${r * 1.8}" height="${r * 1.8}" rx="1" ${a}/>`;
    case "tri": return poly([[0, -1.2], [1.1, .8], [-1.1, .8]]);
    case "down": return poly([[0, 1.2], [1.1, -.8], [-1.1, -.8]]);
    case "diamond": return poly([[0, -1.3], [1.3, 0], [0, 1.3], [-1.3, 0]]);
    case "hex": return poly([[0, -1.2], [1.05, -.6], [1.05, .6], [0, 1.2], [-1.05, .6], [-1.05, -.6]]);
  }
  return `<circle cx="${x}" cy="${y}" r="${r}" ${a}/>`;
}
const mgKey = (shape, color) => `<svg class="mgkey" width="22" height="12" aria-hidden="true"><line x1="0" x2="22" y1="6" y2="6" stroke="${color}" stroke-width="2"/>${mgMark(shape, 11, 6, 4, color)}</svg>`;
function mgTicks(lo, hi){
  if (lo === hi) { lo -= Math.abs(lo) * .1 || 1; hi += Math.abs(hi) * .1 || 1; }
  const raw = (hi - lo) / 4, p = Math.pow(10, Math.floor(Math.log10(raw))), f = raw / p, step = (f <= 1 ? 1 : f <= 2 ? 2 : f <= 2.5 ? 2.5 : f <= 5 ? 5 : 10) * p;
  const a = Math.floor(lo / step) * step, b = Math.ceil(hi / step) * step, t = [];
  for (let v = a; v <= b + step / 2; v += step) t.push(Number(v.toFixed(6)));
  return t;
}
const mgFmt = (v, ind) => v === null || v === undefined ? "—" : /%/.test(ind) ? v.toFixed(2) + "%" : fmtNum(v);
function mgAxis(v, ind){
  if (/%/.test(ind)) return v + "%";
  const a = Math.abs(v);
  return a >= 1e8 ? +(v / 1e8).toFixed(2) + "亿" : a >= 1e4 ? +(v / 1e4).toFixed(2) + "万" : String(v);
}
// 折线图（一根 y 轴）：series = [{name, label, vals, slot}]。悬停 / 方向键：竖线吸附到月份，提示框列出每条线；不超过 4 条时线尾直接标名称。o.stack = 堆叠柱（图例由调用方放在标题里）
function mgChart(box, o){
  box.classList.add("mgchart");
  box._draw = () => {
    const W = Math.max(box.clientWidth, 280), H = o.h || 240, S = o.series, stack = !!o.stack, lab = !stack && S.length <= 4 && W >= 420, L = 52, R = lab ? 104 : 14, T = 10, B = 24, M = o.months, n = M.length;
    const pos = M.map((_, i) => S.reduce((a, s) => a + Math.max(s.vals[i] || 0, 0), 0)), neg = M.map((_, i) => S.reduce((a, s) => a + Math.min(s.vals[i] || 0, 0), 0));
    const xs = stack ? [...pos, ...neg] : S.flatMap(s => s.vals.filter(v => v !== null));
    if (!S.some(s => s.vals.some(v => v !== null))) { box.innerHTML = `<div class="empty">这个指标没有数据</div>`; return; }
    const isAmt = stack || !/单位|%/.test(o.ind), tk = mgTicks(isAmt ? Math.min(0, ...xs) : Math.min(...xs), isAmt ? Math.max(0, ...xs) : Math.max(...xs)), y0 = tk[0], y1 = tk[tk.length - 1];
    const bw = (W - L - R) / n, X = i => stack ? L + (i + .5) * bw : L + (n > 1 ? i * (W - L - R) / (n - 1) : (W - L - R) / 2), Y = v => T + (y1 - v) / (y1 - y0) * (H - T - B);
    const every = Math.ceil(n / Math.max(2, Math.floor((W - L - R) / 62)));
    let h = `<svg width="${W}" height="${H}" role="img" tabindex="0" aria-label="${esc(o.ind)}，${esc(M[0])} 到 ${esc(M[n - 1])}，方向键逐月查看">`;
    for (const t of tk) h += `<line class="mg-grid${t === 0 ? " zero" : ""}" x1="${L}" x2="${W - R}" y1="${Y(t)}" y2="${Y(t)}"/><text class="mg-ax" x="${L - 6}" y="${Y(t) + 4}" text-anchor="end">${esc(mgAxis(t, o.ind))}</text>`;
    M.forEach((f, i) => { if ((n - 1 - i) % every === 0) h += `<text class="mg-ax" x="${X(i)}" y="${H - 7}" text-anchor="${i === n - 1 && !lab && !stack ? "end" : "middle"}">${esc(n > 12 ? f.slice(2) : f)}</text>`; });
    if (stack) {
      const w = Math.min(24, bw * .6);
      M.forEach((f, i) => {
        let up = 0, dn = 0;
        for (const s of S) {
          const v = s.vals[i]; if (!v) continue;
          const a = v > 0 ? up : dn, b = a + v, top = Math.min(Y(a), Y(b)), ht = Math.abs(Y(a) - Y(b));
          if (v > 0) up = b; else dn = b;
          h += `<rect x="${(X(i) - w / 2).toFixed(1)}" y="${(top + (ht > 3 ? 1 : 0)).toFixed(1)}" width="${w.toFixed(1)}" height="${Math.max(ht - (ht > 3 ? 2 : 0), 1).toFixed(1)}" rx="1.5" fill="${mgColor(s.slot)}"/>`;
        }
      });
    } else for (const s of S) {
      const col = mgColor(s.slot), seg = []; let cur = "";
      s.vals.forEach((v, i) => { if (v === null) { if (cur) seg.push(cur); cur = ""; } else cur += `${cur ? "L" : "M"}${X(i).toFixed(1)} ${Y(v).toFixed(1)}`; });
      if (cur) seg.push(cur);
      h += seg.map(p => `<path d="${p}" fill="none" stroke="${col}" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>`).join("");
      s.vals.forEach((v, i) => { if (v !== null) h += mgMark(MG_SHAPE[s.slot], X(i), Y(v), 4, col); });
    }
    if (lab) {
      const ends = S.map(s => { let i = n - 1; while (i >= 0 && s.vals[i] === null) i--; return {s, y:i < 0 ? 0 : Y(s.vals[i])}; }).sort((a, b) => a.y - b.y);
      ends.forEach((e, k) => { if (k && e.y - ends[k - 1].y < 14) e.y = ends[k - 1].y + 14; });
      ends.forEach(e => { e.y = Math.min(e.y, H - B); h += `<text class="mg-end" x="${W - R + 9}" y="${e.y + 4}">${esc(mgShort(e.s.label, 8))}</text>`; });
    }
    h += `<line class="mg-cross" y1="${T}" y2="${H - B}" visibility="hidden"/></svg><div class="mg-tip" hidden></div>`;
    box.innerHTML = h;
    const svg = box.querySelector("svg"), cross = svg.querySelector(".mg-cross"), tip = box.querySelector(".mg-tip");
    let cur = -1;
    const show = i => {
      cur = i; const x = X(i);
      cross.setAttribute("x1", x); cross.setAttribute("x2", x); cross.setAttribute("visibility", "visible");
      tip.innerHTML = ""; tip.hidden = false;
      const head = document.createElement("div"); head.className = "mg-tiph"; head.textContent = `${M[i]} · ${o.ind}`; tip.appendChild(head);
      const list = S.map(s => ({s, v:s.vals[i]}));
      (stack ? list.reverse() : list.sort((a, b) => (b.v ?? -Infinity) - (a.v ?? -Infinity))).forEach(({s, v}) => {
        const row = document.createElement("div"); row.className = "mg-tipr";
        row.insertAdjacentHTML("beforeend", mgKey(MG_SHAPE[s.slot], mgColor(s.slot)));
        const b = document.createElement("b"); b.textContent = mgFmt(v, o.ind);
        const t = document.createElement("span"); t.textContent = mgShort(s.name, 22);
        row.append(b, t); tip.appendChild(row);
      });
      if (stack) { const row = document.createElement("div"), b = document.createElement("b"), t = document.createElement("span"); row.className = "mg-tipr"; b.textContent = mgFmt(pos[i] + neg[i], o.ind); t.textContent = "合计"; row.append(b, t); tip.appendChild(row); }
      const tw = tip.offsetWidth; tip.style.left = (x + 12 + tw > W ? Math.max(0, x - tw - 12) : x + 12) + "px"; tip.style.top = T + "px";
    };
    const hide = () => { cur = -1; cross.setAttribute("visibility", "hidden"); tip.hidden = true; };
    const near = e => { const r = svg.getBoundingClientRect(), px = e.clientX - r.left - L, k = stack ? Math.floor(px / bw) : n > 1 ? Math.round(px / ((W - L - R) / (n - 1))) : 0; return Math.max(0, Math.min(n - 1, k)); };
    svg.addEventListener("pointermove", e => show(near(e)));
    svg.addEventListener("pointerleave", hide);
    svg.addEventListener("blur", hide);
    svg.addEventListener("keydown", e => {
      if (e.key !== "ArrowLeft" && e.key !== "ArrowRight") return;
      e.preventDefault(); show(Math.max(0, Math.min(n - 1, (cur < 0 ? n - 1 : cur + (e.key === "ArrowLeft" ? -1 : 1)))));
    });
  };
  box._draw();
}
window.addEventListener("resize", () => document.querySelectorAll(".mgchart").forEach(b => b._draw && b.isConnected && b._draw()));
function mgLegend(el, d){
  const items = [...MG.pick.entries()].map(([code, slot]) => ({it:d.items.find(x => x.code === code), slot})).filter(x => x.it);
  el.innerHTML = items.map(({it, slot}) => `<span class="mg-chip">${mgKey(MG_SHAPE[slot], mgColor(slot))}<span title="${esc(it.code)} ${esc(it.name || "")}">${esc(mgShort(it.name || it.code, 14))}</span><button data-x="${esc(it.code)}" title="从对比图去掉" aria-label="去掉 ${esc(it.code)}">×</button></span>`).join("")
    || `<span class="hint">在下面的表格里勾选${esc(MG.c.noun)}，加入对比。</span>`;
  el.querySelectorAll("button[data-x]").forEach(b => { b.onclick = () => mgToggle(b.dataset.x, false); });
}
function mgCharts(){
  const d = MG.data, host = $("#mgCharts"); if (!d || !host) return;
  mgLegend($("#mgLegend"), d);
  [0, 1].forEach(k => {
    const ind = MG.chart[k], box = host.querySelector(`#mgC${k}`);
    host.querySelector(`#mgS${k}`).value = ind;
    const series = [...MG.pick.entries()].map(([code, slot]) => { const it = d.items.find(x => x.code === code); return it && {name:`${it.code} ${it.name || ""}`, label:it.name || it.code, slot, vals:d.months.map(f => mgVal(it.m[f], ind))}; }).filter(Boolean);
    if (!series.length) { box.classList.remove("mgchart"); box.innerHTML = `<div class="empty">还没有勾选物料</div>`; return; }
    mgChart(box, {series, months:d.months, ind});
  });
}
function mgToggle(code, on){
  if (on) {
    const s = mgSlot();
    if (s < 0) { toast(`对比图最多放 ${MG_MAX} 个${MG.c.noun}，先去掉一个`); document.querySelectorAll("#mgTbl input[data-mg]").forEach(i => { if (i.dataset.mg === code) i.checked = false; }); return; }
    MG.pick.set(code, s);
  } else {
    MG.pick.delete(code);
    document.querySelectorAll("#mgTbl input[data-mg]").forEach(i => { if (i.dataset.mg === code) i.checked = false; });
  }
  mgPut(mgSK("pick"), [...MG.pick.entries()]);
  mgCharts();
}
// 行内迷你折线（用户 2026-11-06）：跟“月份列显示”的指标走，每行用自己的刻度只看形状；末月标点，没销售的月份断开
function mgSpark(vals, months, ind){
  const W = 92, H = 20, P = 4, n = vals.length, got = vals.filter(v => v !== null);
  if (!got.length) return "";
  const lo = Math.min(...got), hi = Math.max(...got), X = i => P + i * (W - P * 2) / (n - 1), Y = v => hi === lo ? H / 2 : H - P - (v - lo) / (hi - lo) * (H - P * 2);
  let d = "", h = "", last = -1;
  vals.forEach((v, i) => {
    if (v === null) return;
    const lone = vals[i - 1] == null && vals[i + 1] == null;
    d += `${vals[i - 1] == null ? "M" : "L"}${X(i).toFixed(1)} ${Y(v).toFixed(1)}`;
    if (lone) h += `<circle class="sl" cx="${X(i).toFixed(1)}" cy="${Y(v).toFixed(1)}" r="1.5"/>`;
    last = i;
  });
  const txt = vals.map((v, i) => `${months[i]}：${v === null ? "—" : fmtNum(v)}`).join("；");
  return `<svg class="mg-spark" width="${W}" height="${H}" role="img" aria-label="${esc(ind)}走势：${esc(txt)}" data-v="${esc(JSON.stringify(vals))}"><path d="${d}"/>${h}<circle class="se" cx="${X(last).toFixed(1)}" cy="${Y(vals[last]).toFixed(1)}" r="3"/></svg>`;
}
// 迷你图的悬停提示：浏览器不显示最外层 <svg> 的 <title>，只会冒出行上的“双击查看明细”，所以自己画。数字格式同月份列，高亮鼠标所在的月份
const MGT = {el:null, hold:[]};
function mgTipHide(){
  if (MGT.el) MGT.el.hidden = true;
  MGT.hold.forEach(([n, t]) => n.setAttribute("title", t)); MGT.hold = [];
}
function mgTipMove(e, d){
  const sp = e.target.closest && e.target.closest("svg.mg-spark");
  if (!sp) { mgTipHide(); return; }
  if (!MGT.hold.length) [sp.closest("td"), sp.closest("tr")].forEach(n => { const t = n && n.getAttribute("title"); if (t) { MGT.hold.push([n, t]); n.removeAttribute("title"); } });
  if (!MGT.el) { MGT.el = document.createElement("div"); MGT.el.className = "mg-tip mg-sptip"; document.body.appendChild(MGT.el); }
  const vals = JSON.parse(sp.dataset.v), n = vals.length, r = sp.getBoundingClientRect(), k = Math.max(0, Math.min(n - 1, Math.round((e.clientX - r.left - 4) / (r.width - 8) * (n - 1)))), tip = MGT.el;
  tip.innerHTML = ""; tip.hidden = false;
  const head = document.createElement("div"); head.className = "mg-tiph"; head.textContent = MG.ind; tip.appendChild(head);
  vals.forEach((v, i) => {
    const row = document.createElement("div"); row.className = "mg-tipr" + (i === k ? " on" : "");
    const t = document.createElement("span"); t.textContent = d.months[i];
    const b = document.createElement("b"); b.textContent = v === null ? "—" : fmtNum(v);
    row.append(t, b); tip.appendChild(row);
  });
  tip.style.left = Math.max(4, Math.min(innerWidth - tip.offsetWidth - 4, e.clientX + 14)) + "px";
  tip.style.top = Math.max(4, Math.min(innerHeight - tip.offsetHeight - 4, e.clientY + 14)) + "px";
}
// 主表：物料 + 走势 + N 月合计 4 列 + 选定指标的月份列 + 末月较首月。一个月只占一列，切指标换这几列，其余细分在单品抽屉里
function mgTable(d){
  const c = MG.c, ind = MG.ind, nm = `近${d.n}月`, chg = /%/.test(ind) ? "末月较首月（百分点）" : "末月较首月", spk = `走势·${ind}`, pct = c.pct && !/%/.test(ind);
  const cols = [c.code, c.nameCol, spk, "物料组名称", ...c.sums.map(([t]) => `${nm}·${t}`), ...d.months.map(f => `${ind}·${f}`), `${ind}·${chg}`, ...(pct ? [`${ind}·变动 %`] : []), "提示"];
  const rows = d.items.map(it => {
    const vals = d.months.map(f => mgVal(it.m[f], ind)), got = vals.filter(v => v !== null), a = got[0], b = got[got.length - 1];
    return [it.code, it.name, "", it.grp, ...c.sums.map(([, k]) => mgVal(it.tot, k)), ...vals, got.length > 1 ? mgRound(b - a, 4) : null,
      ...(pct ? [got.length > 1 && a ? mgRound((b - a) * 100 / Math.abs(a), 2) : null] : []), c.warn(it)];
  });
  const r = {columns:cols, rows, src:d.src}, mi = cols.indexOf(`${ind}·${d.months[0]}`);
  const box = $("#mgTbl");
  mgTipHide();
  box.innerHTML = table(r, {freeze:3, onRow:true, hideDefault:["物料组名称"], wrap:["提示"], noExport:[spk], tips:{[spk]:`${ind}，近 ${d.n} 个月；每行用自己的刻度，只看形状`}, empty:"没有符合条件的数据",
    fmt:{[c.code]:v => `<input type="checkbox" class="mgck" data-mg="${esc(v)}"${MG.pick.has(v) ? " checked" : ""} title="加入 / 去掉对比图" aria-label="对比 ${esc(v)}"> ${esc(v)}`,
      [spk]:(v, x) => mgSpark(x.slice(mi, mi + d.n), d.months, ind)}});
  bindRows(box, r, row => mgDetail(row[c.code]));
}
// 单品抽屉：行 = 指标、列 = 月份（mgMatrix）；各页的图和按钮在 c.detail
function mgDetail(code){
  const d = MG.data, it = d.items.find(x => x.code === code); if (!it) return;
  MG.c.detail(drawer(`${code} ${it.name || ""}`), it, d);
}
function mgMatrix(it, d, inds, cell){
  return table({columns:["指标", ...d.months, "合计"], rows:inds.map(k => [k, ...d.months.map(f => cell(it.m[f], k)), cell(it.tot, k)]), src:d.src}, {freeze:1, sort:false, sum:false});
}
function mgPickBtn(btn, code){
  const lab = () => { btn.textContent = MG.pick.has(code) ? "从对比图去掉" : "加入对比图"; };
  lab();
  btn.onclick = () => { mgToggle(code, !MG.pick.has(code)); if (MG.pick.has(code)) document.querySelectorAll("#mgTbl input[data-mg]").forEach(i => { if (i.dataset.mg === code) i.checked = true; }); lab(); };
}
function saleDetail(el, it, d){
  const code = it.code, r = rptDef("23"), inds = ["数量", "收入", "其中暂估收入", "成本", "毛利", "毛利率 %", "单位售价", "单位成本"];
  const cell = (o, k) => k === "其中暂估收入" ? (o ? mgRound(o.revAcc, 2) : null) : mgVal(o, k);
  el.innerHTML = `<div class="bar"><button class="btn" id="mgDocs">看单据行</button><button class="btn" id="mgAddC"></button></div>
    <h3>收入和成本</h3><div id="mgDA"></div><h3>毛利率</h3><div id="mgDB"></div><h3>逐月明细</h3>` + mgMatrix(it, d, inds, cell);
  mgPickBtn(el.querySelector("#mgAddC"), code);
  el.querySelector("#mgDocs").onclick = () => { DRILL_IN = true; try { rptDrill(r, Object.assign({}, d.v, {STYPE:"0"}), {"物料":code}); } finally { DRILL_IN = false; } };
  mgChart(el.querySelector("#mgDA"), {months:d.months, ind:"金额", h:190, series:[
    {name:"收入", label:"收入", slot:0, vals:d.months.map(f => mgVal(it.m[f], "收入"))},
    {name:"成本", label:"成本", slot:1, vals:d.months.map(f => mgVal(it.m[f], "成本"))}]});
  mgChart(el.querySelector("#mgDB"), {months:d.months, ind:"毛利率 %", h:170, series:[{name:"毛利率", label:"毛利率", slot:0, vals:d.months.map(f => mgVal(it.m[f], "毛利率 %"))}]});
}
const mgTiles = ts => `<div class="tiles">${ts.map(([k, v]) => `<div class="tile"><span>${esc(k)}</span><b>${esc(String(v))}</b></div>`).join("")}</div>`;
function mgShow(){
  const d = MG.data, c = MG.c, out = $("#mgOut"); if (!d || !out) return;
  if (!d.items.length) { out.innerHTML = `<div class="empty">${esc(c.none)}</div>`; return; }
  const ind = o => o.map(x => `<option>${esc(x)}</option>`).join("");
  out.innerHTML = mgTiles(c.tiles(d)) + c.banner(d)
    + (d.empty.length ? `<p class="hint">${esc(d.empty.join("、"))} ${esc(c.emptyNote(d))}。</p>` : "")
    + c.overHtml(d)
    + `<div class="mg-sec">单品对比</div>
       <div class="mg-leg" id="mgLegend"></div>
       <div class="mg-charts" id="mgCharts">${[0, 1].map(k => `<section class="mg-card"><select id="mgS${k}" aria-label="图${k + 1}的指标">${ind(c.inds)}</select><div id="mgC${k}"></div></section>`).join("")}</div>
       <div class="bar"><label>月份列显示 <select id="mgInd">${ind(c.inds)}</select></label><span class="hint">勾选${esc(c.noun)}放进上面的对比图（最多 ${MG_MAX} 个），${CLICK === "one" ? "点" : "双击"}一行看这个${esc(c.noun)}的逐月明细。</span></div>
       <div id="mgTbl"></div>`;
  $("#mgInd").value = MG.ind;
  $("#mgInd").onchange = () => { MG.ind = $("#mgInd").value; mgPut(mgSK("ind"), MG.ind); mgTable(d); };
  [0, 1].forEach(k => { $(`#mgS${k}`).onchange = () => { MG.chart[k] = $(`#mgS${k}`).value; mgPut(mgSK("chart"), MG.chart); mgCharts(); }; });
  $("#mgTbl").addEventListener("change", e => { const x = e.target.closest && e.target.closest("input[data-mg]"); if (x) mgToggle(x.dataset.mg, x.checked); });
  $("#mgTbl").addEventListener("pointermove", e => mgTipMove(e, MG.data));
  $("#mgTbl").addEventListener("pointerleave", mgTipHide);
  c.overDraw(d);
  mgCharts(); mgTable(d);
}
async function renderMargin(pane){
  const page = MG = MGS[TAB], c = MG.c, tab = TAB, r = rptDef(c.rid), keepK = "cc.rpt." + c.rid;
  const v = Object.assign(rptDefaults(r), rptSaved(c.rid) || {});
  if (!v.FcTo) v.FcTo = $("#fc").value || mgNow();
  if (!MG.ind) { MG.ind = mgGet(mgSK("ind"), c.ind); if (!c.inds.includes(MG.ind)) MG.ind = c.ind; MG.chart = mgGet(mgSK("chart"), MG.chart).map((x, i) => c.inds.includes(x) ? x : c.chart[i]); MG.pick = new Map(mgGet(mgSK("pick"), [])); }
  let n = Number(mgGet(mgSK("n"), 6)) || 6;
  pane.innerHTML = `<div class="bar"><span class="sp"></span><button class="btn" id="mgB1" title="复制这张报表的 B1 查询管理器语句">在 SAP 中打开</button></div>`
    + note(esc(r.desc) + `<br>本页由 ${esc(r.proc)} 按月取数后在页面上汇总，和“成本报表”里的 R${esc(c.rid)} 是同一个过程。“近 N 月”从截止账期往前连续数，${esc(c.gapNote)}`, "rpt")
    + `<div class="rptform" id="mgForm"><div class="empty">加载中…</div></div>
       <div class="bar"><button class="btn primary" id="mgGo">查询</button><button class="btn" id="mgReset">恢复默认条件</button></div>
       <div id="mgOut"></div>`;
  $("#mgB1").onclick = () => rptB1(r);
  const seq = ++page.seq, L = await rptLists();
  if (seq !== page.seq || TAB !== tab) return;
  const form = $("#mgForm"), ps = c.params.map(k => r.params.find(p => p.name === k));
  form.innerHTML = rptField(ps[0], v, L) + `<label><span>连续月数</span><input type="text" id="mgN" inputmode="numeric" maxlength="2" value="${n}" style="min-width:0;width:5em" title="从截止账期往前连续几个月，2–36"></label>` + ps.slice(1).map(p => rptField(p, v, L)).join("");
  const go = async () => {
    const nv = Object.assign({}, v, rptRead({params:ps}, form)); n = Math.max(2, Math.min(36, Math.round(Number($("#mgN").value)) || 6));
    $("#mgN").value = n; mgPut(mgSK("n"), n);
    try { localStorage.setItem(keepK, JSON.stringify(nv)); } catch (e) {}
    const end = nv.FcTo || mgNow(), months = Array.from({length:n}, (_, i) => mgMonth(end, i - n + 1));
    const args = rptArgs(r, Object.assign({}, nv, {FcFrom:months[0], FcTo:end, STYPE:"0"})), out = $("#mgOut"), my = ++page.seq;
    out.style.opacity = page.data ? ".5" : ""; if (!page.data) out.innerHTML = `<div class="empty">查询中…</div>`;
    try {
      const res = await api("/api/q", {action:"rpt" + c.rid, args, all:true});   // 物料 × 月份容易超过页面 2000 行，这里要全部行才能汇总
      if (my !== page.seq) return;
      res.src = [{action:"rpt" + c.rid, args}];
      // 查询中切到别的页签时先算好，切回来再画（wtShow）；MG 是全局的当前页，这里临时换成本页
      const m0 = MG; MG = page;
      page.data = mgBuild(res, months, Object.assign({}, nv, {FcFrom:months[0], FcTo:end}), n);
      mgDefaultPick(page.data); MG = m0;
      if (TAB === tab) mgShow(); else page.dirty = true;
    } catch (e) { out.innerHTML = errBox(e) + `<div class="hint">数据库还没有部署 新框架/sql/21_reports.sql 时会出现这个错误。</div>`; }
    out.style.opacity = "";
  };
  $("#mgGo").onclick = go;
  $("#mgReset").onclick = () => { try { localStorage.removeItem(keepK); localStorage.removeItem(mgSK("n")); } catch (e) {} page.data = null; renderMargin(pane); };
  form.addEventListener("keydown", e => { if (e.key === "Enter" && e.target.tagName === "INPUT") { e.preventDefault(); go(); } });
  // 打开页面不自动查询（用户 2026-11-01）；这次打开过的结果切回来时还在
  if (page.data) mgShow(); else $("#mgOut").innerHTML = `<div class="empty">设好条件后点“查询”。</div>`;
}
// R23 销售毛利走势
mgPage("margin", {rid:"23", sk:"", code:"物料", nameCol:"物料名称", noun:"物料", none:"这段时间没有符合条件的销售。",
  params:["FcTo", "Basis", "Item", "ItemGrp", "Cust", "CustType", "SalType", "InclSample"], gapNote:"没有销售的月份留空。",
  inds:["毛利", "毛利率 %", "收入", "成本", "数量", "单位售价", "单位成本"], ind:"毛利", chart:["毛利", "毛利率 %"],
  sums:[["收入", "收入"], ["成本", "成本"], ["毛利", "毛利"], ["毛利率 %", "毛利率 %"]],
  zero:() => ({rev:0, cost:0, qty:0, revAcc:0, noCost:0, noPrice:0, late:0}),
  row:x => ({rev:x["收入·合计"], cost:x["成本·合计"], qty:x["数量·合计"], revAcc:x["收入·暂估"], noCost:x["缺成本单价行数"], noPrice:x["缺销售单价行数"], late:x["结账后补单行数"]}),
  rank:o => o.rev - o.cost, val:mgValSale, detail:saleDetail,
  warn:it => { const w = [], t = it.tot; if (t.noCost) w.push(`缺成本 ${t.noCost} 行`); if (t.noPrice) w.push(`缺售价 ${t.noPrice} 行`); if (t.late) w.push(`结账后补单 ${t.late} 行`); return w.join("；"); },
  tiles:d => { const a = d.all.tot, noi = d.items.some(x => x.code === MG_NOI); return [[`近${d.n}月收入`, fmtNum(mgVal(a, "收入"))], ["成本", fmtNum(mgVal(a, "成本"))], ["毛利", fmtNum(mgVal(a, "毛利"))], ["毛利率", mgFmt(mgVal(a, "毛利率 %"), "%")], ["物料数", d.items.length - (noi ? 1 : 0)]]; },
  banner:d => { const w = d.items.filter(x => x.tot.noCost).length; return w ? `<div class="msg warn">${w} 个物料有缺成本单价的行，这些物料的成本偏低、毛利偏高，见表格“提示”列。</div>` : ""; },
  emptyNote:d => "没有数据" + (d.v.Basis === "1" ? "（月结固定只列已结账账期）" : ""),
  overHtml:d => { const noi = d.items.some(x => x.code === MG_NOI); return `<div class="mg-sec">全部物料汇总<span class="hint">与上面的合计同一范围${noi ? "，含未归属产品" : ""}</span></div>
       <div class="mg-charts all"><section class="mg-card"><div class="mg-ttl">收入、成本、毛利<span class="mg-keys">${["收入", "成本", "毛利"].map((k, i) => `<span>${mgKey(MG_SHAPE[i], mgColor(i))}${k}</span>`).join("")}</span></div><div id="mgA0"></div></section>
         <section class="mg-card"><div class="mg-ttl">毛利率</div><div id="mgA1"></div></section></div>`; },
  overDraw:d => {
    const allV = ind => d.months.map(f => mgVal(d.all.m[f], ind));
    mgChart($("#mgA0"), {months:d.months, ind:"金额", h:220, series:["收入", "成本", "毛利"].map((k, i) => ({name:k, label:k, slot:i, vals:allV(k)}))});
    mgChart($("#mgA1"), {months:d.months, ind:"毛利率 %", h:220, series:[{name:"毛利率", label:"毛利率", slot:0, vals:allV("毛利率 %")}]});
  }});
