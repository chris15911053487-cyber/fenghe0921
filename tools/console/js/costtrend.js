// 成本执行台 · costtrend.js — “R22 生产成本走势”单独一页（用户 2026-11-06）：连续 N 个月的单位成本和料工费构成，取 MTC_CA_RPT_22_COSTTREND 的长表在页面上汇总，图表和主表用 margin.js。
// index.html 按顺序加载 js/ 下的脚本，共用全局作用域；加载时立即执行的代码只能用到本文件和前面文件里的名字。
// 不同产品的单位成本不能相加，所以汇总图看完工成本和构成，单位成本只按产品比。
// 过程只给单位料工费，金额 = 单位值 × 完工数量；完工数量为 0 的月份只有完工成本，没有构成，合计数不受影响。
"use strict";
const CT_PART = [["材料", "mat", 0], ["人工", "lab", 4], ["制造", "mfg", 3], ["委外", "sub", 5]];   // [名称, 字段, 槽位]：颜色和成本追溯的料工费一致
function ctVal(o, ind){
  if (!o) return null;
  const u = v => o.qty ? mgRound(v / o.qty, 4) : null, parts = o.mat + o.lab + o.mfg + o.sub;
  switch (ind) {
    case "单位成本": return u(o.amt);
    case "材料单位成本": return u(o.mat);
    case "人工单位成本": return u(o.lab);
    case "制造单位成本": return u(o.mfg);
    case "委外单位成本": return u(o.sub);
    case "完工数量": return mgRound(o.qty, 6);
    case "完工成本": return mgRound(o.amt, 2);
    case "材料占比 %": return parts ? mgRound(o.mat * 100 / parts, 2) : null;
    case "人工占比 %": return parts ? mgRound(o.lab * 100 / parts, 2) : null;
    case "制造占比 %": return parts ? mgRound(o.mfg * 100 / parts, 2) : null;
    case "委外占比 %": return parts ? mgRound(o.sub * 100 / parts, 2) : null;
  }
  return null;
}
const ctBasis = d => d.v.Basis === "1" ? "成本还原：半成品里含的料工费分回各要素，同 R02" : "本级：人工、制造 = 本期分摊，委外 = 订单自己的加工费，半成品全额算材料";
const ctKeys = () => CT_PART.map(([k, , s]) => `<span><svg class="mgkey" width="12" height="12" aria-hidden="true"><rect width="12" height="12" rx="2" fill="${mgColor(s)}"/></svg>${k}</span>`).join("");
const ctLines = () => CT_PART.map(([k, , s]) => `<span>${mgKey(MG_SHAPE[s], mgColor(s))}${k}</span>`).join("");
function ctDetail(el, it, d){
  const code = it.code, inds = ["完工数量", "完工成本", "单位成本", "材料单位成本", "人工单位成本", "制造单位成本", "委外单位成本", "单位成本环比 %"], M = d.months;
  const ucs = M.map(f => ctVal(it.m[f], "单位成本"));
  const cell = (o, k) => {
    if (k !== "单位成本环比 %") return ctVal(o, k);
    const i = M.findIndex(f => it.m[f] === o); if (i <= 0 || ucs[i] === null) return null;   // 合计列没有环比；和前一个有完工的月份比
    let j = i - 1; while (j >= 0 && ucs[j] === null) j--;
    return j >= 0 && ucs[j] ? mgRound((ucs[i] - ucs[j]) * 100 / Math.abs(ucs[j]), 2) : null;
  };
  el.innerHTML = `<div class="bar"><button class="btn" id="mgDocs">看完工订单</button><button class="btn" id="mgAddC"></button></div>
    <div class="mg-ttl">单位成本构成<span class="mg-keys">${ctKeys()}</span></div><div id="mgDA"></div><h3>完工数量</h3><div id="mgDB"></div><h3>逐月明细</h3>` + mgMatrix(it, d, inds, cell);
  mgPickBtn(el.querySelector("#mgAddC"), code);
  el.querySelector("#mgDocs").onclick = () => {
    const r = {drill:{"0":{to:"02", stype:"1", set:{Item:"=产品", WorType:"@WorType"}}}};
    DRILL_IN = true; try { rptDrill(r, Object.assign({}, d.v, {STYPE:"0"}), {"产品":code}); } finally { DRILL_IN = false; }
  };
  mgChart(el.querySelector("#mgDA"), {months:M, ind:"单位成本", h:200, stack:true, series:CT_PART.map(([k, , s]) => ({name:k, label:k, slot:s, vals:M.map(f => ctVal(it.m[f], k + "单位成本"))}))});
  mgChart(el.querySelector("#mgDB"), {months:M, ind:"完工数量", h:160, series:[{name:"完工数量", label:"完工数量", slot:0, vals:M.map(f => ctVal(it.m[f], "完工数量"))}]});
}
mgPage("costtrend", {rid:"22", sk:"r22", code:"产品", nameCol:"名称", noun:"产品", none:"这段时间没有符合条件的完工。", pct:true, sparks:["单位成本", "完工成本"],
  params:["FcTo", "Basis", "WorType", "Item", "ItemGrp"], gapNote:"没有完工的月份留空。",
  inds:["单位成本", "材料单位成本", "人工单位成本", "制造单位成本", "委外单位成本", "完工数量", "完工成本", "材料占比 %", "人工占比 %", "制造占比 %", "委外占比 %"], ind:"单位成本", chart:["单位成本", "完工数量"],
  sums:[["完工数量", "完工数量"], ["完工成本", "完工成本"], ["单位成本", "单位成本"], ["材料占比 %", "材料占比 %"]],
  zero:() => ({qty:0, amt:0, mat:0, lab:0, mfg:0, sub:0, noQty:0}),
  row:x => { const q = Number(x["完工数量"]) || 0, u = k => q * (Number(x["单位成本·" + k]) || 0); return {qty:q, amt:x["完工成本"], mat:u("材料"), lab:u("人工"), mfg:u("制造"), sub:u("委外"), noQty:q ? 0 : 1}; },
  rank:o => o.amt, val:ctVal, detail:ctDetail,
  warn:it => { const t = it.tot, w = []; if (t.noQty) w.push(`${t.noQty} 个月有成本没有完工数量`); if (t.amt < 0) w.push("完工成本为负"); return w.join("；"); },
  tiles:d => { const a = d.all.tot, sum = a.mat + a.lab + a.mfg + a.sub, pc = v => sum ? `（${(v * 100 / sum).toFixed(1)}%）` : "";
    return [[`近${d.n}月完工成本`, fmtNum(mgVal(a, "完工成本"))], ...CT_PART.map(([k, f]) => [k + pc(a[f]), fmtNum(mgRound(a[f], 2))]), ["产品数", d.items.length]]; },
  banner:() => "",
  emptyNote:() => "没有完工",
  overHtml:d => `<div class="mg-sec">全部产品汇总<span class="hint">不同产品的单位成本不能相加，这里看完工成本和构成。${ctBasis(d)}</span></div>
       <div class="mg-charts all"><section class="mg-card"><div class="mg-ttl">完工成本构成<span class="mg-keys">${ctKeys()}</span></div><div id="mgA0"></div></section>
         <section class="mg-card"><div class="mg-ttl">料工费占比<span class="mg-keys">${ctLines()}</span></div><div id="mgA1"></div></section></div>`,
  overDraw:d => {
    const M = d.months, amt = f => M.map(m => { const o = d.all.m[m]; return o ? mgRound(o[f], 2) : null; });
    mgChart($("#mgA0"), {months:M, ind:"金额", h:220, stack:true, series:CT_PART.map(([k, f, s]) => ({name:k, label:k, slot:s, vals:amt(f)}))});
    mgChart($("#mgA1"), {months:M, ind:"占比 %", h:220, series:CT_PART.map(([k, , s]) => ({name:k, label:k, slot:s, vals:M.map(m => ctVal(d.all.m[m], k + "占比 %"))}))});
  }});
