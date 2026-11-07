// 成本执行台 · margin.js — “R23 销售毛利走势”单独一页（用户 2026-11-06）：连续 N 个月的单品毛利对比，取 MTC_CA_RPT_23_MARGINTREND 的长表在页面上汇总。
// index.html 按顺序加载 js/ 下的脚本，共用全局作用域；加载时立即执行的代码只能用到本文件和前面文件里的名字。
// 上面两张对比图 + 下面一行一个物料（N 月合计 4 列 + 选定指标的月份列）；已开票 / 暂估等细分不进主表，单品抽屉里看。条件和报表页共用 cc.rpt.23。
"use strict";
const MG_MAX = 6;   // 对比图最多几个物料（主题图表色 + 形状能区分的数量）
const MG_IND = ["毛利", "毛利率 %", "收入", "成本", "数量", "单位售价", "单位成本"];
const MG_SHAPE = ["circle", "square", "tri", "diamond", "down", "hex"];
const MG_COLOR = [1, 6, 5, 4, 3, 2];   // 取主题 --c-chart-N 的顺序：相邻两色尽量拉开
const MG_NOI = "(未归属产品)";
const MG = {data:null, pick:new Map(), ind:null, chart:["毛利", "毛利率 %"], seq:0};
function mgGet(k, d){ try { const s = localStorage.getItem(k); return s === null ? d : JSON.parse(s); } catch (e) { return d; } }
function mgPut(k, v){ try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) {} }
const mgMonth = (fc, k) => { const [y, m] = fc.split("-").map(Number), t = y * 12 + m - 1 + k; return Math.floor(t / 12) + "-" + String(t % 12 + 1).padStart(2, "0"); };
const mgNow = () => { const d = new Date(); return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0"); };
const mgZero = () => ({rev:0, cost:0, qty:0, revAcc:0, noCost:0, noPrice:0, late:0});
function mgAdd(o, x){ for (const k of Object.keys(o)) o[k] += Number(x[k]) || 0; return o; }
const mgRound = (v, d) => v === null || !isFinite(v) ? null : Number(v.toFixed(d));
function mgVal(o, ind){
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
  const map = new Map(), all = {tot:mgZero(), m:{}};
  for (const x of asObjs(res)) {
    const code = x["物料"], fc = x["账期"];
    if (!map.has(code)) map.set(code, {code, name:x["物料名称"], grp:x["物料组名称"], tot:mgZero(), m:{}});
    const it = map.get(code), d = {rev:x["收入·合计"], cost:x["成本·合计"], qty:x["数量·合计"], revAcc:x["收入·暂估"], noCost:x["缺成本单价行数"], noPrice:x["缺销售单价行数"], late:x["结账后补单行数"]};
    it.m[fc] = mgAdd(it.m[fc] || mgZero(), d); mgAdd(it.tot, d);
    all.m[fc] = mgAdd(all.m[fc] || mgZero(), d); mgAdd(all.tot, d);
  }
  const items = [...map.values()].sort((a, b) => (b.tot.rev - b.tot.cost) - (a.tot.rev - a.tot.cost));
  return {months, items, all, v, n, src:res.src, empty:months.filter(f => !all.m[f])};
}
// 对比的物料：沿用上次勾选里这次还在的；一个都没有时取毛利绝对值最大的 5 个。颜色跟物料走，去掉别的物料不换色
function mgDefaultPick(d){
  const old = [...MG.pick.keys()].filter(c => d.items.some(x => x.code === c));
  const pick = new Map(); old.forEach(c => pick.set(c, MG.pick.get(c)));
  if (!pick.size) d.items.filter(x => x.code !== MG_NOI).slice().sort((a, b) => Math.abs(b.tot.rev - b.tot.cost) - Math.abs(a.tot.rev - a.tot.cost)).slice(0, 5).forEach((x, i) => pick.set(x.code, i));
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
// 折线图（一根 y 轴）：series = [{name, label, vals, slot}]。悬停 / 方向键：竖线吸附到月份，提示框列出每条线；不超过 4 条时线尾直接标名称
function mgChart(box, o){
  box.classList.add("mgchart");
  box._draw = () => {
    const W = Math.max(box.clientWidth, 280), H = o.h || 240, S = o.series, lab = S.length <= 4 && W >= 420, L = 52, R = lab ? 104 : 14, T = 10, B = 24, M = o.months, n = M.length;
    const xs = S.flatMap(s => s.vals.filter(v => v !== null));
    if (!xs.length) { box.innerHTML = `<div class="empty">这个指标没有数据</div>`; return; }
    const isAmt = !/单位|%/.test(o.ind), tk = mgTicks(isAmt ? Math.min(0, ...xs) : Math.min(...xs), isAmt ? Math.max(0, ...xs) : Math.max(...xs)), y0 = tk[0], y1 = tk[tk.length - 1];
    const X = i => L + (n > 1 ? i * (W - L - R) / (n - 1) : (W - L - R) / 2), Y = v => T + (y1 - v) / (y1 - y0) * (H - T - B);
    const every = Math.ceil(n / Math.max(2, Math.floor((W - L - R) / 62)));
    let h = `<svg width="${W}" height="${H}" role="img" tabindex="0" aria-label="${esc(o.ind)}，${esc(M[0])} 到 ${esc(M[n - 1])}，方向键逐月查看">`;
    for (const t of tk) h += `<line class="mg-grid${t === 0 ? " zero" : ""}" x1="${L}" x2="${W - R}" y1="${Y(t)}" y2="${Y(t)}"/><text class="mg-ax" x="${L - 6}" y="${Y(t) + 4}" text-anchor="end">${esc(mgAxis(t, o.ind))}</text>`;
    M.forEach((f, i) => { if ((n - 1 - i) % every === 0) h += `<text class="mg-ax" x="${X(i)}" y="${H - 7}" text-anchor="${i === n - 1 && !lab ? "end" : "middle"}">${esc(n > 12 ? f.slice(2) : f)}</text>`; });
    for (const s of S) {
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
      S.map(s => ({s, v:s.vals[i]})).sort((a, b) => (b.v ?? -Infinity) - (a.v ?? -Infinity)).forEach(({s, v}) => {
        const row = document.createElement("div"); row.className = "mg-tipr";
        row.insertAdjacentHTML("beforeend", mgKey(MG_SHAPE[s.slot], mgColor(s.slot)));
        const b = document.createElement("b"); b.textContent = mgFmt(v, o.ind);
        const t = document.createElement("span"); t.textContent = mgShort(s.name, 22);
        row.append(b, t); tip.appendChild(row);
      });
      const tw = tip.offsetWidth; tip.style.left = (x + 12 + tw > W ? Math.max(0, x - tw - 12) : x + 12) + "px"; tip.style.top = T + "px";
    };
    const hide = () => { cur = -1; cross.setAttribute("visibility", "hidden"); tip.hidden = true; };
    const near = e => { const r = svg.getBoundingClientRect(), k = n > 1 ? Math.round((e.clientX - r.left - L) / ((W - L - R) / (n - 1))) : 0; return Math.max(0, Math.min(n - 1, k)); };
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
    || `<span class="hint">在下面的表格里勾选物料，加入对比。</span>`;
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
    if (s < 0) { toast(`对比图最多放 ${MG_MAX} 个物料，先去掉一个`); document.querySelectorAll("#mgTbl input[data-mg]").forEach(i => { if (i.dataset.mg === code) i.checked = false; }); return; }
    MG.pick.set(code, s);
  } else {
    MG.pick.delete(code);
    document.querySelectorAll("#mgTbl input[data-mg]").forEach(i => { if (i.dataset.mg === code) i.checked = false; });
  }
  mgPut("cc.mg.pick", [...MG.pick.entries()]);
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
  const tip = vals.map((v, i) => `${months[i]}：${mgFmt(v, ind)}`).join("\n");
  return `<svg class="mg-spark" width="${W}" height="${H}" role="img" aria-label="${esc(ind)}走势"><title>${esc(tip)}</title><path d="${d}"/>${h}<circle class="se" cx="${X(last).toFixed(1)}" cy="${Y(vals[last]).toFixed(1)}" r="3"/></svg>`;
}
// 主表：物料 + 走势 + N 月合计 4 列 + 选定指标的月份列 + 末月较首月。一个月只占一列，切指标换这几列，其余细分在单品抽屉里
function mgTable(d){
  const ind = MG.ind, nm = `近${d.n}月`, chg = /%/.test(ind) ? "末月较首月（百分点）" : "末月较首月";
  const cols = ["物料", "物料名称", "走势", "物料组名称", `${nm}·收入`, `${nm}·成本`, `${nm}·毛利`, `${nm}·毛利率 %`, ...d.months.map(f => `${ind}·${f}`), `${ind}·${chg}`, "提示"];
  const rows = d.items.map(it => {
    const vals = d.months.map(f => mgVal(it.m[f], ind)), got = vals.filter(v => v !== null), warn = [];
    if (it.tot.noCost) warn.push(`缺成本 ${it.tot.noCost} 行`);
    if (it.tot.noPrice) warn.push(`缺售价 ${it.tot.noPrice} 行`);
    if (it.tot.late) warn.push(`结账后补单 ${it.tot.late} 行`);
    return [it.code, it.name, "", it.grp, mgVal(it.tot, "收入"), mgVal(it.tot, "成本"), mgVal(it.tot, "毛利"), mgVal(it.tot, "毛利率 %"), ...vals,
      got.length > 1 ? mgRound(got[got.length - 1] - got[0], 4) : null, warn.join("；")];
  });
  const r = {columns:cols, rows, src:d.src}, mi = cols.indexOf(`${ind}·${d.months[0]}`);
  const box = $("#mgTbl");
  box.innerHTML = table(r, {freeze:3, onRow:true, hideDefault:["物料组名称"], wrap:["提示"], noExport:["走势"], tips:{"走势":`${ind}，近 ${d.n} 个月；每行用自己的刻度，只看形状`}, empty:"没有符合条件的数据",
    fmt:{"物料":v => `<input type="checkbox" class="mgck" data-mg="${esc(v)}"${MG.pick.has(v) ? " checked" : ""} title="加入 / 去掉对比图" aria-label="对比 ${esc(v)}"> ${esc(v)}`,
      "走势":(v, x) => mgSpark(x.slice(mi, mi + d.n), d.months, ind)}});
  bindRows(box, r, row => mgDetail(row["物料"]));
}
// 单品抽屉：行 = 指标、列 = 月份（含暂估），图是收入对成本、毛利率
function mgDetail(code){
  const d = MG.data, it = d.items.find(x => x.code === code), r = rptDef("23"); if (!it) return;
  const el = drawer(`${code} ${it.name || ""}`), inds = ["数量", "收入", "其中暂估收入", "成本", "毛利", "毛利率 %", "单位售价", "单位成本"];
  const cell = (o, k) => k === "其中暂估收入" ? (o ? mgRound(o.revAcc, 2) : null) : mgVal(o, k);
  const m = {columns:["指标", ...d.months, "合计"], rows:inds.map(k => [k, ...d.months.map(f => cell(it.m[f], k)), cell(it.tot, k)]), src:d.src};
  el.innerHTML = `<div class="bar"><button class="btn" id="mgDocs">看单据行</button><button class="btn" id="mgAddC"></button></div>
    <h3>收入和成本</h3><div id="mgDA"></div><h3>毛利率</h3><div id="mgDB"></div><h3>逐月明细</h3>` + table(m, {freeze:1, sort:false, sum:false});
  const rv = el.querySelector("#mgAddC"), lab = () => { rv.textContent = MG.pick.has(code) ? "从对比图去掉" : "加入对比图"; };
  lab();
  rv.onclick = () => { const on = !MG.pick.has(code); mgToggle(code, on); if (MG.pick.has(code)) document.querySelectorAll("#mgTbl input[data-mg]").forEach(i => { if (i.dataset.mg === code) i.checked = true; }); lab(); };
  el.querySelector("#mgDocs").onclick = () => { DRILL_IN = true; try { rptDrill(r, Object.assign({}, d.v, {STYPE:"0"}), {"物料":code}); } finally { DRILL_IN = false; } };
  mgChart(el.querySelector("#mgDA"), {months:d.months, ind:"金额", h:190, series:[
    {name:"收入", label:"收入", slot:0, vals:d.months.map(f => mgVal(it.m[f], "收入"))},
    {name:"成本", label:"成本", slot:1, vals:d.months.map(f => mgVal(it.m[f], "成本"))}]});
  mgChart(el.querySelector("#mgDB"), {months:d.months, ind:"毛利率 %", h:170, series:[{name:"毛利率", label:"毛利率", slot:0, vals:d.months.map(f => mgVal(it.m[f], "毛利率 %"))}]});
}
function mgShow(){
  const d = MG.data, out = $("#mgOut"); if (!d || !out) return;
  if (!d.items.length) { out.innerHTML = `<div class="empty">这段时间没有符合条件的销售。</div>`; return; }
  const a = d.all.tot, tile = (k, v) => `<div class="tile"><span>${esc(k)}</span><b>${v}</b></div>`;
  const warn = d.items.filter(x => x.tot.noCost).length, noi = d.items.some(x => x.code === MG_NOI);
  const ind = o => o.map(x => `<option>${esc(x)}</option>`).join("");
  out.innerHTML = `<div class="tiles">${tile(`近${d.n}月收入`, fmtNum(mgVal(a, "收入")))}${tile("成本", fmtNum(mgVal(a, "成本")))}${tile("毛利", fmtNum(mgVal(a, "毛利")))}${tile("毛利率", mgFmt(mgVal(a, "毛利率 %"), "%"))}${tile("物料数", d.items.length - (noi ? 1 : 0))}</div>`
    + (warn ? `<div class="msg warn">${warn} 个物料有缺成本单价的行，这些物料的成本偏低、毛利偏高，见表格“提示”列。</div>` : "")
    + (d.empty.length ? `<p class="hint">${esc(d.empty.join("、"))} 没有数据${d.v.Basis === "1" ? "（月结固定只列已结账账期）" : ""}。</p>` : "")
    + `<div class="mg-leg" id="mgLegend"></div>
       <div class="mg-charts" id="mgCharts">${[0, 1].map(k => `<section class="mg-card"><select id="mgS${k}" aria-label="图${k + 1}的指标">${ind(MG_IND)}</select><div id="mgC${k}"></div></section>`).join("")}</div>
       <div class="bar"><label>月份列显示 <select id="mgInd">${ind(MG_IND)}</select></label><span class="hint">勾选物料放进上面的对比图（最多 ${MG_MAX} 个），${CLICK === "one" ? "点" : "双击"}一行看这个物料的逐月明细。</span></div>
       <div id="mgTbl"></div>`;
  $("#mgInd").value = MG.ind;
  $("#mgInd").onchange = () => { MG.ind = $("#mgInd").value; mgPut("cc.mg.ind", MG.ind); mgTable(d); };
  [0, 1].forEach(k => { $(`#mgS${k}`).onchange = () => { MG.chart[k] = $(`#mgS${k}`).value; mgPut("cc.mg.chart", MG.chart); mgCharts(); }; });
  $("#mgTbl").addEventListener("change", e => { const c = e.target.closest && e.target.closest("input[data-mg]"); if (c) mgToggle(c.dataset.mg, c.checked); });
  mgCharts(); mgTable(d);
}
async function renderMargin(pane){
  const r = rptDef("23"), keep = ["FcTo", "Basis", "Item", "ItemGrp", "Cust", "CustType", "SalType", "InclSample"];
  const v = Object.assign(rptDefaults(r), rptSaved("23") || {});
  if (!v.FcTo) v.FcTo = $("#fc").value || mgNow();
  if (!MG.ind) { MG.ind = mgGet("cc.mg.ind", "毛利"); MG.chart = mgGet("cc.mg.chart", MG.chart); MG.pick = new Map(mgGet("cc.mg.pick", [])); }
  let n = Number(mgGet("cc.mg.n", 6)) || 6;
  pane.innerHTML = `<div class="bar"><span class="sp"></span><button class="btn" id="mgB1" title="复制这张报表的 B1 查询管理器语句">在 SAP 中打开</button></div>`
    + note(esc(r.desc) + `<br>本页由 ${esc(r.proc)} 按月取数后在页面上汇总，和“成本报表”里的 R23 是同一个过程。“近 N 月”从截止账期往前连续数，没有销售的月份留空。`, "rpt")
    + `<div class="rptform" id="mgForm"><div class="empty">加载中…</div></div>
       <div class="bar"><button class="btn primary" id="mgGo">查询</button><button class="btn" id="mgReset">恢复默认条件</button></div>
       <div id="mgOut"></div>`;
  $("#mgB1").onclick = () => rptB1(r);
  const seq = ++MG.seq, L = await rptLists();
  if (seq !== MG.seq || TAB !== "margin") return;
  const form = $("#mgForm"), ps = keep.map(k => r.params.find(p => p.name === k));
  form.innerHTML = rptField(ps[0], v, L) + `<label><span>连续月数</span><input type="text" id="mgN" inputmode="numeric" maxlength="2" value="${n}" style="min-width:0;width:5em" title="从截止账期往前连续几个月，2–36"></label>` + ps.slice(1).map(p => rptField(p, v, L)).join("");
  const go = async () => {
    const nv = Object.assign({}, v, rptRead({params:ps}, form)); n = Math.max(2, Math.min(36, Math.round(Number($("#mgN").value)) || 6));
    $("#mgN").value = n; mgPut("cc.mg.n", n);
    try { localStorage.setItem("cc.rpt.23", JSON.stringify(nv)); } catch (e) {}
    const end = nv.FcTo || mgNow(), months = Array.from({length:n}, (_, i) => mgMonth(end, i - n + 1));
    const args = rptArgs(r, Object.assign({}, nv, {FcFrom:months[0], FcTo:end, STYPE:"0"})), out = $("#mgOut"), my = ++MG.seq;
    out.style.opacity = MG.data ? ".5" : ""; if (!MG.data) out.innerHTML = `<div class="empty">查询中…</div>`;
    try {
      const res = await api("/api/q", {action:"rpt23", args, all:true});   // 物料 × 月份容易超过页面 2000 行，这里要全部行才能汇总
      if (my !== MG.seq || TAB !== "margin") return;
      res.src = [{action:"rpt23", args}];
      MG.data = mgBuild(res, months, Object.assign({}, nv, {FcFrom:months[0], FcTo:end}), n);
      mgDefaultPick(MG.data); mgShow();
    } catch (e) { out.innerHTML = errBox(e) + `<div class="hint">数据库还没有部署 新框架/sql/21_reports.sql 时会出现这个错误。</div>`; }
    out.style.opacity = "";
  };
  $("#mgGo").onclick = go;
  $("#mgReset").onclick = () => { try { localStorage.removeItem("cc.rpt.23"); localStorage.removeItem("cc.mg.n"); } catch (e) {} MG.data = null; renderMargin(pane); };
  form.addEventListener("keydown", e => { if (e.key === "Enter" && e.target.tagName === "INPUT") { e.preventDefault(); go(); } });
  // 打开页面不自动查询（用户 2026-11-01）；这次打开过的结果切回来时还在
  if (MG.data) mgShow(); else $("#mgOut").innerHTML = `<div class="empty">设好条件后点“查询”。</div>`;
}
