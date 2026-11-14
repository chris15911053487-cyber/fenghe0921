// 成本执行台 · trace.js — 成本追溯：从物料或订单逐层展开料工费来源
// index.html 按顺序加载 js/ 下的脚本，共用全局作用域；加载时立即执行的代码只能用到本文件和前面文件里的名字。
"use strict";
// ---------------- 成本追溯（用户 2026-10-23）----------------
// 从一个物料（或订单）出发逐层展开料工费的来源：物料 = 期初 + 计入加权单价的入库（完工订单、形态转换、采购等）；
// 订单 = 各材料本期结转（四项随子件带上来）+ 本级分摊的制造费用、人工 + 委外加工费；材料再展开成它自己的来源，一直到采购件。
// 每层只在点开时查询（traceItemSrc / orderHead + traceOrderMat）；“构成占比” = 本行合计 ÷ 同一层各行合计。
// 材料再点开列的是该材料全期的来源（期初 + 全部计价入库），不是这张订单那一份，所以“本行”金额逐层接不上；
// “折算到根”= 本行 × 上层折算系数 × 上层金额 ÷ 同层合计，每层合计都等于根的金额（用户 2026-11-13）。
let TRACE = null; try { TRACE = JSON.parse(localStorage.getItem("cc.trace") || "null"); } catch (e) {}
if (URL0 && URL0.tab === "trace" && URL0.obj) TRACE = URL0.obj;
let TRN = 0;
const TR_MAX = 1500;
function goTrace(spec){
  TRACE = spec; try { localStorage.setItem("cc.trace", JSON.stringify(spec)); } catch (e) {}
  TAB = "trace"; try { localStorage.setItem("cc.tab", TAB); } catch (e) {}
  wtStale("trace"); renderTab();
}
const trSum = a => a[0] + a[1] + a[2] + a[3];
const trAmt = (x, p = "") => [p + "Mat", p + "Mfg", p + "Lab", p + "Sub"].map(k => Number(x[k] || 0));
const trSrcText = v => !v ? "" : PRICESRC[v] ? `${v} ${PRICESRC[v]}` : priceSrcText(v);
// 折算系数：根 = 1；下层 = 上层系数 × 上层金额 ÷ 同层合计。同层合计为 0 时折算不了（null）
function trK(n){
  if (!n.parent) return 1;
  const pk = trK(n.parent), tot = n.parent.kids.reduce((t, c) => t + trSum(c.a || [0, 0, 0, 0]), 0);
  return pk === null || Math.abs(tot) < 0.005 ? null : pk * trSum(n.parent.a || [0, 0, 0, 0]) / tot;
}
// 物料单价不是本期加权（维护价兜底 / 无价）时，期初 + 入库解释不了单价
const trSrcWarn = s => s && s !== "WAVG" && s !== "OPEN" ? `单价来源 ${trSrcText(s)}，不是按下面这些来源加权算出来的` : "";
function trNode(o, parent){
  const n = {id: ++TRN, depth: parent ? parent.depth + 1 : 0, parent, kids: null, open: false, loading: false, err: null,
             path: new Set(parent ? parent.path : []), ...o};
  if (n.code) n.path.add(n.code);
  if (n.ord && n.ord.item) n.path.add(n.ord.item);
  // 返工单“自己加工自己”：材料和上层某个物料相同时不再展开，避免死循环
  if (n.code && parent && parent.path.has(n.code)) { n.cyc = true; n.exp = false; }
  return n;
}
async function trLoad(n, id){
  if (n.kids || n.loading || !n.exp) return;
  n.loading = true;
  try {
    const kids = [];
    if (n.code) {
      for (const x of asObjs(await q("traceItemSrc", {runId:id, itemCode:n.code}))) {
        const base = {qty: x.Qty, a: [Number(x.MatAmt || 0), Number(x.MfgAmt || 0), Number(x.LabAmt || 0), Number(x.SubAmt || 0)]};
        if (x.Kind === "OPEN") kids.push(trNode({...base, kind:"open", label:"期初结存", note:"上期期末结转过来的四项"}, n));
        else if (x.Kind === "ORDER") kids.push(trNode({...base, kind:"order", exp:true,
          label:`订单 ${x.OrderType}-${x.OrderNum || x.OrderEntry}`, sub: WORTYPE[x.WorType] || "",
          note:`完工入库 ${x.Lines} 行`, ord:{type:String(x.OrderType), entry:String(x.OrderEntry), num:x.OrderNum, item:n.code}}, n));
        else if (x.Kind === "TRF") kids.push(trNode({...base, kind:"item", exp:true, code:x.SrcItem,
          label:`形态转换自 ${x.SrcItem}`, sub: x.SrcItemName || "", note:`I05 = 转出物料的金额，${x.Lines} 行；展开是转出物料的来源`}, n));
        else kids.push(trNode({...base, kind:"other",
          label: codeText("TransCode", x.TransCode) || "（无交易类型）", sub: codeText("Cat", x.Cat) || "", note:`${x.Lines} 行`}, n));
      }
    } else if (n.alloc) {
      // 本级分摊 → 各费用池：工时 = 单位工时 × 本期入库数，占池内工时的比例 × 池分摊额（MTC_CA_R_ALLOC，P43）
      let hw = 0;
      for (const x of asObjs(await q("traceAlloc", {runId:id, orderType:n.alloc.type, orderEntry:n.alloc.entry}))) {
        hw += Number(x.Weight || 0);
        kids.push(trNode({kind:"pool", qty:x.RecvQty, a:[0, Number(x.MfgAmt || 0), Number(x.LabAmt || 0), 0],
          label:`费用池 ${x.PoolName || x.PoolCode}`, sub:`单位工时 ${fmtNum(x.Hours)}`,
          note:`工时 = 单位工时 ${fmtNum(x.Hours)} × 本期入库 ${fmtNum(x.RecvQty)} = ${fmtNum(x.Weight)}；池内 ${x.PoolOrders} 张订单共 ${fmtNum(x.PoolWeight)} 工时，占 ${(Number(x.Ratio || 0) * 100).toFixed(4)}%；池分摊制造费用 ${fmtNum(x.PoolMfg)}、人工 ${fmtNum(x.PoolLab)}，× 占比 = 本订单金额（尾差挤在工时最大的订单）`}, n));
      }
      if (kids.length) n.note = `本订单工时 ${fmtNum(hw)}（单位工时 × 本期入库数）；按工时占池内比例分摊`;
    } else if (n.ord) {
      const key = {runId:id, orderType:n.ord.type, orderEntry:n.ord.entry};
      const [hr, mr] = await Promise.all([q("orderHead", key), q("traceOrderMat", key)]);
      const h = asObjs(hr)[0] || {};
      if (!n.depth) Object.assign(n, {qty: h.RecvQty, a: trAmt(h, "Cost"), label:`订单 ${h.OrderType}-${h.OrderNum || h.OrderEntry}`,
        sub:`${h.ItemCode || ""} ${h.ItemName || ""}`.trim(), lv: h.iLevel});
      n.price = h.UnitCost; n.ord.item = h.ItemCode || n.ord.item; if (h.ItemCode) n.path.add(h.ItemCode);
      for (const x of asObjs(mr)) {
        const a = trAmt(x, "Car");
        if (x.ItemCode === "#SUBFEE") { kids.push(trNode({kind:"subfee", a, label:"本级委外", sub:"委外加工费", note:"订单自己的加工费，随入库全部结转"}, n)); continue; }
        const wip = Number(x.OpenWip || 0), nt = [`本期结转（本期领料 ${fmtNum(x.IssQty)}）；单价来源 ${trSrcText(x.PriceSrc) || "-"}`];
        if (Math.abs(wip) > 0.005) nt.push(`期初在产品 ${fmtNum(wip)}（以前账期领料未结转，按当时单价构成），本期结转里有一部分来自它，点开只看本期来源`);
        if (trSrcWarn(x.PriceSrc)) nt.push(trSrcWarn(x.PriceSrc));
        nt.push("点开是该材料全期的来源，看“折算到根”是本订单那一份");
        kids.push(trNode({kind:"item", exp:true, code:x.ItemCode, a, lv:x.iLevel, price:x.Price, psrc:x.PriceSrc,
          label:`材料 ${x.ItemCode}`, sub:x.ItemName || "", note:nt.join("；")}, n));
      }
      const al = [0, Number(h.AllocMfg || 0), Number(h.AllocLab || 0), 0];
      if (al[1] || al[2]) kids.push(trNode({kind:"alloc", exp:true, alloc:{type:n.ord.type, entry:n.ord.entry}, a:al, label:"本级分摊", sub:"制造费用、人工",
        note:"费用池按 单位工时 × 本期入库数 分摊到本订单；点开看各费用池的工时"}, n));
      // 下层合计应等于订单本期完工成本（Cost 四项）；上层一行是按交易类型汇总的入库，订单只有部分入库在这一行时两者可以不同
      const s = [0, 1, 2, 3].map(k => kids.reduce((t, c) => t + c.a[k], 0)), d = trSum(s) - trSum(trAmt(h, "Cost"));
      if (n.depth && Math.abs(trSum(n.a) - trSum(trAmt(h, "Cost"))) > 0.01) n.note += `；订单本期完工成本 ${fmtNum(h.CostAmt)}，这一行只是其中一部分入库`;
      if (h.OrderType && Math.abs(d) > 0.01) kids.push(trNode({kind:"warn", a:[0, 0, 0, 0], label:"⚠ 下层合计与订单完工成本不一致", note:`差 ${fmtNum(d)}，请反馈`}, n));
      if (!h.OrderType) n.err = "本次运行没有这张订单";
    }
    if (n.code && trSrcWarn(n.psrc)) kids.unshift(trNode({kind:"warn", a:[0, 0, 0, 0], label:"⚠ " + trSrcWarn(n.psrc), note:"维护价兜底 / 无价时期初 + 入库的数量不大于 0，下面的金额解释不了单价，折算也不可靠"}, n));
    n.kids = kids; n.open = true;
  } catch (e) { n.err = e.message || String(e); }
  n.loading = false;
}
function trVisible(n, out = []){
  out.push(n);
  if (n.open && n.kids) n.kids.forEach(k => trVisible(k, out));
  return out;
}
function trRows(root){
  return trVisible(root).map(n => {
    const sib = n.parent && n.parent.kids, tot = sib ? sib.reduce((t, c) => t + trSum(c.a || [0, 0, 0, 0]), 0) : 0, amt = trSum(n.a || [0, 0, 0, 0]);
    const unit = n.price !== undefined && n.price !== null ? Number(n.price) : (n.qty ? amt / Number(n.qty) : null);
    // 料工费比例（用户 2026-10-23）：本行自身的构成，料 = 材料 + 委外加工费，三项合计 100%
    const a = n.a || [0, 0, 0, 0], big = Math.abs(amt) > 0.005;
    const mix = big ? [(a[0] + a[3]) / amt * 100, a[2] / amt * 100, a[1] / amt * 100] : [null, null, null];
    const k = trK(n), fa = k === null ? [null, null, null, null] : a.map(v => Number(v) * k);
    return {n, amt, unit, mix, fa, famt: k === null ? null : amt * k, pct: sib && Math.abs(tot) > 0.005 ? amt / tot * 100 : null};
  });
}
// 追溯表用共用表格 table() 的树形模式（2026-10-23）：工具条（复制、导出 Excel、列、全屏、本表筛选）和其他表格一样；
// 展开 / 收起后 tblSetData 原地换数据。NodeId 是隐藏的键列；追溯路径的值带全角空格缩进，复制、导出到 Excel 时保留层次
const TR_COLS = ["NodeId", "层次", "追溯路径", "名称", "物料层级", "数量", "单价", "本行·材料", "本行·制造费用", "本行·人工", "本行·委外加工费", "本行·合计",
  "折算到根·材料", "折算到根·制造费用", "折算到根·人工", "折算到根·委外加工费", "折算到根·合计", "料%", "工%", "费%", "构成占比%", "说明"];
const TR_TIPS = {"追溯路径": "点 ▸ 展开下一层；双击行也可以展开 / 收起", "料%": "本行（材料 + 委外加工费）÷ 本行合计", "工%": "本行人工 ÷ 本行合计", "费%": "本行制造费用 ÷ 本行合计",
  "构成占比%": "本行合计 ÷ 同一层各行合计", "本行·合计": "这一行自己的金额。材料行点开后列的是该材料全期的来源，不是上层订单那一份，所以和上层接不上",
  "折算到根·合计": "本行按比例折算成根那一行里的份额：每层合计都等于根的金额，可以直接看根成本里有多少来自这里"};
const trPct = v => v === null || v === undefined || !isFinite(v) ? null : Math.round(v * 100) / 100;   // 比例两位小数
const trNum = v => v === null || v === undefined || v === "" || !isFinite(Number(v)) ? null : Number(v);
function trData(root, nodes){
  nodes.clear();
  return {columns: TR_COLS, rows: trRows(root).map(({n, amt, unit, mix, fa, famt, pct}) => {
    nodes.set(n.id, n);
    return [n.id, n.depth, "\u3000".repeat(n.depth) + n.label, n.sub || "", trNum(n.lv), trNum(n.qty), trNum(unit), ...(n.a || [0, 0, 0, 0]).map(Number), amt,
      ...fa, famt, ...mix.map(trPct), trPct(pct), n.err || (n.cyc ? "上层已出现这个物料（返工单自己加工自己），不再展开" : n.note || "")];
  })};
}
// ---------------- 构成图（冰柱图，用户 2026-11-01）----------------
// 表格上方一张可收起的图：每层一行，色块宽度 = 金额绝对值 ÷ 同层绝对值合计 × 上层宽度（负数按绝对值画、斜线纹、标“−”；
// 标出的占比仍是“构成占比”口径）。只画表里已经展开的层；单击 = 选中表里这一行并展开下一层，双击 = 以它为根放大，面包屑回上层。
// 配色两种：料工费（色块底部一根四项堆叠条）、来源类型（期初 / 订单 / 材料 / 采购等 / 分摊 / 委外）。设置记在本机 cc.trviz
let TRV = {hide:false, mode:"mix", form:"sankey"}; try { Object.assign(TRV, JSON.parse(localStorage.getItem("cc.trviz") || "{}")); } catch (e) {}
const TV_MIX = [["mat", "材料", 0], ["sub", "委外加工费", 3], ["lab", "人工", 2], ["mfg", "制造费用", 1]];   // a[] 顺序是 材料、制造、人工、委外
const TV_SRC = [["open", "期初"], ["order", "订单"], ["item", "材料 / 形态转换"], ["other", "采购等入库"], ["alloc", "分摊"], ["subfee", "委外加工费"]];
const TV_ROWH = 34;
// ---------------- 桑基图（用户 2026-11-13，默认；冰柱图保留为选项 TRV.form）----------------
// 根在最左，每展开一层往右一列；节点高度 = 金额绝对值按同层比例分上层的高度（= 折算到根，负数按绝对值、斜线纹），
// 连线从上层节点右边分出一段连到下层节点。只画表里已经展开的层。节点、连线上悬停看明细，单击 / 双击同冰柱图
const SK_BAR = 12, SK_H = 300, SK_CW = 230, SK_LAB = 210, SK_LP = 190;
// 按显示宽度截断（中文约 12px、其他约 7px）
const skFit = (t, px) => { let w = 0, i = 0; for (; i < t.length; i++) { w += t.charCodeAt(i) > 255 ? 12 : 7; if (w > px) break; } return i < t.length ? t.slice(0, Math.max(0, i - 1)) + "…" : t; };
function trSankey(z, sel, mix, W){
  const cols = [], all = [];
  const walk = (n, d, w) => {
    const o = {n, d, w, kids:[]}; (cols[d] = cols[d] || []).push(o); all.push(o);
    if (n.open && n.kids) {
      const tot = n.kids.reduce((t, k) => t + trAbs(k), 0);
      if (tot > 0.005) for (const k of n.kids) { const kw = w * trAbs(k) / tot; if (kw > 0) o.kids.push(walk(k, d + 1, kw)); }
    }
    return o;
  };
  const top = walk(z, 0, 1);
  // 列宽固定（不按窗口平分）；最后一列右边留出标签的位置，图比窗口宽时才横向滚动
  const cw = SK_CW, svgW = SK_LP + (cols.length - 1) * cw + SK_BAR + SK_LAB + 8;
  // 下层一组节点（含间隔）以上层节点的中心为中心展开，同一列重叠的往下推；最后整体平移到顶部留白
  const gap = c => Math.max(1, Math.min(10, 200 / c.length));
  top.cy = 0;
  cols.forEach((c, d) => {
    const g = gap(c);
    let bottom = -Infinity;
    for (const o of c) {
      o.h = Math.max(1, o.w * SK_H); o.x = SK_LP + d * cw;
      o.y = Math.max(o.want !== undefined ? o.want : 0, bottom + g); bottom = o.y + o.h;
      const kg = o.kids.length ? gap(cols[d + 1]) : 0, blk = o.kids.reduce((t, k) => t + Math.max(1, k.w * SK_H), 0) + kg * (o.kids.length - 1);
      let cy = o.y + o.h / 2 - blk / 2; for (const k of o.kids) { k.want = cy; cy += Math.max(1, k.w * SK_H) + kg; }
    }
  });
  const y0 = Math.min(...all.map(o => o.y)) - 8; all.forEach(o => { o.y -= y0; });
  const H = Math.max(...all.map(o => o.y + o.h)) + 10;
  const pc = (n) => { const sib = n.parent && n !== z && n.parent.kids, tot = sib ? sib.reduce((t, c) => t + trSum(c.a || [0, 0, 0, 0]), 0) : 0;
    return sib && Math.abs(tot) > 0.005 ? (trSum(n.a || [0, 0, 0, 0]) / tot * 100).toFixed(1) + "%" : ""; };
  let links = "", bars = "", labs = "";
  for (const o of all) {
    const n = o.n, amt = trSum(n.a || [0, 0, 0, 0]), ng = amt < -0.005, k = trK(n), tip = `<title>${esc(trTip(n))}</title>`;
    // 连线：上层右边按下层高度依次切一段
    let sy = o.y;
    for (const c of o.kids) {
      const h = c.w * SK_H, x0 = o.x + SK_BAR, x1 = c.x, xm = (x0 + x1) / 2, cng = trSum(c.n.a || [0, 0, 0, 0]) < -0.005;
      links += `<path class="skl${mix ? "" : " src tv-k-" + c.n.kind}${cng ? " ng" : ""}" data-n="${c.n.id}" d="M${x0},${sy}C${xm},${sy} ${xm},${c.y} ${x1},${c.y}L${x1},${c.y + h}C${xm},${c.y + h} ${xm},${sy + h} ${x0},${sy + h}Z"><title>${esc(trTip(c.n))}</title></path>`;
      sy += h;
    }
    // 节点：按料工费时四项竖向堆叠，按来源类型时一种颜色
    let r = "";
    if (mix) {
      const v = TV_MIX.map(([key, , i]) => [key, Math.abs(Number((n.a || [])[i] || 0))]), t = v.reduce((a, x) => a + x[1], 0);
      let yy = o.y;
      if (t > 0.005) for (const [key, x] of v) { if (!x) continue; const hh = o.h * x / t; r += `<rect class="tv-${key}" x="${o.x}" y="${yy}" width="${SK_BAR}" height="${hh}"/>`; yy += hh; }
      else r = `<rect class="skz" x="${o.x}" y="${o.y}" width="${SK_BAR}" height="${o.h}"/>`;
    } else r = `<rect class="tv-k-${n.kind}" x="${o.x}" y="${o.y}" width="${SK_BAR}" height="${o.h}"/>`;
    bars += `<g class="skn${n.id === sel ? " on" : ""}${ng ? " ng" : ""}" data-n="${n.id}">${tip}${r}<rect class="skf" x="${o.x - 1}" y="${o.y - 1}" width="${SK_BAR + 2}" height="${o.h + 2}"/>`
      + `<rect class="skhit" x="${o.x - 3}" y="${o.y - 3}" width="${cw - 8}" height="${Math.max(o.h, 14) + 6}"/></g>`;
    // 标签：名称 + 折算到根金额（+ 构成占比）；太矮的只在悬停时看
    // 根的标签放在左边（不压连线），其他放在节点右边；高度够时名称、说明、金额分三行
    if (o.h >= 11) {
      const isRoot = o === top, px = isRoot ? SK_LP - 14 : cw - SK_BAR - 16, x = isRoot ? o.x - 6 : o.x + SK_BAR + 5, an = isRoot ? ` text-anchor="end"` : "";
      const t1 = (ng ? "− " : "") + (n.exp && !n.open && !n.cyc ? "▸ " : "") + n.label, lines = [[t1, ""]];
      if (n.sub && o.h >= 42) lines.push([n.sub, " sks"]); else if (n.sub) lines[0][0] += " " + n.sub;
      if (o.h >= 28) lines.push([`${fmtNum(k === null ? amt : amt * k)} ${pc(n)}`.trim(), " skv"]);
      let ty = o.y + o.h / 2 - (lines.length - 1) * 7 + 4;
      for (const [t, c] of lines) { labs += `<text class="skt${c}" x="${x}" y="${ty}"${an}>${esc(skFit(t, px))}</text>`; ty += 14; }
    }
  }
  return `<svg class="sk" width="${svgW}" height="${H}" viewBox="0 0 ${svgW} ${H}"><defs><pattern id="skNg" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">`
    + `<rect width="2" height="6" class="skpat"/></pattern></defs>${links}${bars}${labs}</svg>`;
}
let TV_MARK = null;   // 当前追溯页的“图上跟着高亮”；表格的 ↑ ↓ 换行在 document 上处理，这里也在 document 上跟
document.addEventListener("keyup", e => { if ((e.key === "ArrowUp" || e.key === "ArrowDown") && TV_MARK && $("#trViz")) TV_MARK(); });
// 四项堆叠条（按绝对值比例），图和表里的“合计”列共用
function trMixBar(a, cls){
  const v = TV_MIX.map(([k, , i]) => [k, Math.abs(Number(a[i] || 0))]), t = v.reduce((s, x) => s + x[1], 0);
  if (t < 0.005) return "";
  return `<span class="${cls}">` + v.filter(x => x[1] > 0).map(([k, x]) => `<i class="tv-${k}" style="width:${(x / t * 100).toFixed(3)}%"></i>`).join("") + "</span>";
}
const trAbs = n => Math.abs(trSum(n.a || [0, 0, 0, 0]));
function trLay(n, x, w, d, out){
  out.push({n, x, w, d});
  if (!n.open || !n.kids) return out;
  const tot = n.kids.reduce((t, k) => t + trAbs(k), 0);
  let cx = x;
  if (tot > 0.005) for (const k of n.kids) { const kw = w * trAbs(k) / tot; if (kw > 0) trLay(k, cx, kw, d + 1, out); cx += kw; }
  return out;
}
function trTip(n){
  const amt = trSum(n.a || [0, 0, 0, 0]), sib = n.parent && n.parent.kids, tot = sib ? sib.reduce((t, c) => t + trSum(c.a || [0, 0, 0, 0]), 0) : 0;
  const a = n.a || [0, 0, 0, 0], pc = v => Math.abs(amt) > 0.005 ? (v / amt * 100).toFixed(2) + "%" : "-";
  return [n.label + (n.sub ? "  " + n.sub : ""), `合计 ${fmtNum(amt)}` + (sib && Math.abs(tot) > 0.005 ? `，构成占比 ${(amt / tot * 100).toFixed(2)}%` : ""),
    `材料 ${fmtNum(a[0])}  制造费用 ${fmtNum(a[1])}  人工 ${fmtNum(a[2])}  委外加工费 ${fmtNum(a[3])}`,
    `料 ${pc(a[0] + a[3])} / 工 ${pc(a[2])} / 费 ${pc(a[1])}`,
    ...(n.parent && trK(n) !== null ? [`折算到根 ${fmtNum(amt * trK(n))}`] : []),
    n.exp && !n.open ? "单击展开下一层，双击放大" : "双击以它为根放大"].join("\n");
}
async function renderTrace(pane, id){
  const sp = TRACE || {};
  pane.innerHTML = latestNote() + note(`从一个物料或订单出发，逐层展开料工费从哪里来，四项（材料、制造费用、人工、委外加工费）一直随物料往上传。<br>
    <b>物料</b>一行是“期初 + 计入加权单价的入库”（加权单价的分子），单价是本期加权单价；下一层是期初结存、各完工订单、形态转换、采购等来源（出库和不计入单价的调整不列）。<br>
    <b>订单</b>一行是本期完工成本，单价是单位成本；下一层是各材料的本期结转（四项按子件单价的构成带上来）、本级分摊的制造费用和人工、委外加工费。材料再点开就是这个材料自己的来源，一直到采购件。<br>
    “本级分摊”点开是各费用池：单位工时 × 本期入库数 = 本订单工时，占池内全部订单工时的比例 × 池的制造费用 / 人工 = 分到本订单的金额。<br>
    “料% / 工% / 费%”是本行自己的构成（料含委外加工费，三项合计 100%），可以逐层对比比例怎么变化。“构成占比” = 本行合计 ÷ 同一层各行合计。<br>
    <b>本行</b>是这一行自己的金额：订单下的材料是本订单的结转额，再点开却是该材料<b>全期</b>的来源（也供给别的订单），所以和上层接不上。<b>折算到根</b>按比例折成根那一行里的份额，每一层加起来都等于根的金额（四项明细在“列 ▾”里打开）。
    材料的单价是维护价兜底或无价时，期初 + 入库解释不了单价，会标 ⚠；订单的结转里含期初在产品（以前账期的单价构成）时在说明里标出。本期没有结转的材料不列（领料都留在在产品里）。返工单领用的物料和产出相同，到这里停止展开。“详情”打开原来的物料 / 订单明细。`, "trace")
    + `<div class="bar"><input type="text" id="trCode" placeholder="物料编码" maxlength="50" value="${esc(sp.kind === "item" ? sp.code : "")}">`
    + `<button class="btn primary" id="trGo">追溯</button><span class="hint" id="trRoot"></span><span class="sp"></span>`
    + `<button class="btn" id="trAll" title="逐层点开全部，最多 ${TR_MAX} 行">全部展开</button><button class="btn" id="trFold">收起</button></div>`
    + `<div class="trviz" id="trViz" hidden><div class="tvbar"><b>构成图</b><span class="tvcrumb" id="tvCrumb"></span><span class="sp"></span>`
    + `<span class="tvleg" id="tvLeg"></span><select id="tvForm" title="图形"><option value="sankey">桑基图</option><option value="icicle">冰柱图</option></select><select id="tvMode" title="配色"><option value="mix">按料工费</option><option value="src">按来源类型</option></select>`
    + `<button class="btn" id="tvHide"></button></div><div class="tvcv" id="tvCv"></div></div><div id="trBox"></div>`;
  const box = $("#trBox"), nodes = new Map(), viz = $("#trViz"), cv = $("#tvCv");
  let root = null, tid = null, zoom = null;
  const tvSave = () => { try { localStorage.setItem("cc.trviz", JSON.stringify(TRV)); } catch (e) {} };
  const selNode = () => { const st = tid && LASTSEL && LASTSEL.id === tid && TBL.get(tid), x = st && st.r.rows[LASTSEL.i]; return x ? x[0] : null; };
  // 构成图跟着表格重画：放大的节点被上层收起（不在表里显示）时回到根
  const vizDraw = () => {
    viz.hidden = !root; if (!root) return;
    viz.classList.toggle("off", TRV.hide);
    $("#tvHide").textContent = TRV.hide ? "展开图" : "收起图";
    $("#tvMode").value = TRV.mode; $("#tvForm").value = TRV.form;
    $("#tvLeg").innerHTML = (TRV.mode === "mix" ? TV_MIX : TV_SRC).map(([k, t]) => `<span><i class="tv-${TRV.mode === "mix" ? "" : "k-"}${k}"></i>${t}</span>`).join("");
    for (let p = zoom; p; p = p.parent) if (p !== zoom && !p.open) { zoom = null; break; }
    const z = zoom || root, chain = [];
    for (let p = z; p; p = p.parent) chain.unshift(p);
    $("#tvCrumb").innerHTML = chain.length > 1 ? "：" + chain.map((p, i) => i < chain.length - 1 ? `<a data-z="${p.id}">${esc(p.label)}</a>` : esc(p.label)).join(" › ") : "";
    if (TRV.hide) return;
    const sel = selNode(), mix = TRV.mode === "mix";
    cv.classList.toggle("skcv", TRV.form === "sankey");
    if (TRV.form === "sankey") { cv.style.height = ""; cv.innerHTML = trSankey(z, sel, mix, cv.clientWidth || 900); return; }
    const bl = trLay(z, 0, 100, 0, []);
    cv.style.height = (Math.max(...bl.map(b => b.d)) + 1) * TV_ROWH + 2 + "px";
    cv.innerHTML = bl.filter(b => b.w >= 0.15).map(({n, x, w, d}) => {
      const amt = trSum(n.a || [0, 0, 0, 0]), sib = n !== z && n.parent.kids, tot = sib ? sib.reduce((t, c) => t + trSum(c.a || [0, 0, 0, 0]), 0) : 0;
      const pct = sib && Math.abs(tot) > 0.005 ? ` <span class="tvp">${(amt / tot * 100).toFixed(1)}%</span>` : ` <span class="tvp">${fmtNum(amt)}</span>`;
      const cls = "tvb" + (mix ? "" : " src tv-k-" + n.kind) + (amt < -0.005 ? " ng" : "") + (n.id === sel ? " on" : "");
      return `<div class="${cls}" data-n="${n.id}" title="${esc(trTip(n))}" style="left:${x}%;width:${w}%;top:${d * TV_ROWH}px;height:${TV_ROWH - 2}px">`
        + `<span class="tvl">${amt < -0.005 ? "<b>−</b> " : ""}${n.exp && !n.open && !n.cyc ? "▸ " : ""}${esc(n.label)}${pct}</span>`
        + (mix ? trMixBar(n.a || [], "tvmix") : "") + `</div>`;
    }).join("");
  };
  const vizMark = () => { const s = selNode(); cv.querySelectorAll("[data-n]").forEach(b => b.classList.toggle("on", Number(b.dataset.n) === s)); };
  // 图上单击：选中表里这一行（滚到可见）；还没展开的展开下一层
  const vizPick = n => {
    const st = tid && TBL.get(tid), w = document.getElementById(tid);
    const i = st ? st.r.rows.findIndex(x => x[0] === n.id) : -1, tr = i >= 0 && w.querySelector(`tr[data-i="${i}"]`);
    if (tr) { tblSel(w, tr); tr.scrollIntoView({block:"nearest"}); }
    vizMark();
    if (n.exp && !n.cyc && !n.open && !n.loading) toggle(n);
  };
  cv.onclick = e => { const b = e.target.closest("[data-n]"), n = b && nodes.get(Number(b.dataset.n)); if (n) vizPick(n); };
  cv.ondblclick = e => { const b = e.target.closest("[data-n]"), n = b && nodes.get(Number(b.dataset.n)); if (n) { zoom = n === root ? null : n; vizDraw(); } };
  $("#tvCrumb").onclick = e => { const a = e.target.closest("a[data-z]"); if (!a) return; const n = nodes.get(Number(a.dataset.z)); zoom = !n || n === root ? null : n; vizDraw(); };
  $("#tvForm").onchange = e => { TRV.form = e.target.value; tvSave(); vizDraw(); };
  $("#tvMode").onchange = e => { TRV.mode = e.target.value; tvSave(); vizDraw(); };
  $("#tvHide").onclick = () => { TRV.hide = !TRV.hide; tvSave(); vizDraw(); };
  // 表里点行 / ↑ ↓ 换行后，图上跟着高亮
  box.addEventListener("click", () => setTimeout(vizMark));
  TV_MARK = vizMark;
  const nodeOf = x => nodes.get(x[0]);
  const opt = {hide:["NodeId"], hideDefault:["折算到根·材料", "折算到根·制造费用", "折算到根·人工", "折算到根·委外加工费"], key:"NodeId", sum:false, freeze:3, wrap:["说明"], tips:TR_TIPS, onRow:true, noClick: x => !nodeOf(x).exp,
    trCls: x => { const n = nodeOf(x); return "tr-" + n.kind + (n.depth ? "" : " tot"); },
    fmt: {"追溯路径": (v, x) => { const n = nodeOf(x); return esc(n.label) + (n.ord ? ` <a class="trd">详情</a>` : n.code ? ` <a class="trd">详情</a>` : ""); },
          "说明": (v, x) => { const n = nodeOf(x); return n.err ? `<span class="bad">${esc(v)}</span>` : `<span class="hint">${esc(v)}</span>`; },
          "本行·合计": (v, x) => `<b>${fmtNum(v)}</b>` + trMixBar(nodeOf(x).a || [], "trmix"),
          "折算到根·合计": v => v === null ? `<span class="hint">-</span>` : `<b>${fmtNum(v)}</b>`},
    tree: {col:"追溯路径", depth: x => x[1], can: x => nodeOf(x).exp, toggle: x => toggle(nodeOf(x)),
           mark: x => { const n = nodeOf(x); return n.loading ? "…" : n.exp ? (n.open ? "▾" : "▸") : "·"; }}};
  const draw = () => {
    if (!root) { box.innerHTML = `<div class="empty">输入物料编码后点“追溯”；也可以在物料单价、订单的明细里点“逐层追溯料工费”。</div>`; tid = null; vizDraw(); return; }
    const r = trData(root, nodes);
    if (tid && document.getElementById(tid)) tblSetData(tid, r);
    else {
      box.innerHTML = table(r, opt); tid = box.querySelector(".tbl").id;
      bindRows(box, r, o => toggle(nodes.get(o.NodeId)));   // 点行处理函数拿到的是按列名的对象
    }
    vizDraw();
  };
  const toggle = async n => {
    if (!n || !n.exp || n.loading) return;
    if (n.kids) { n.open = !n.open; draw(); return; }
    n.loading = true; draw(); n.loading = false;
    await trLoad(n, id); draw();
  };
  const start = async s => {
    TRACE = s; try { localStorage.setItem("cc.trace", JSON.stringify(s)); } catch (e) {}
    syncUrl(true);
    tid = null; zoom = null; root = null; vizDraw(); box.innerHTML = `<div class="empty">加载中…</div>`;
    try {
      if (s.kind === "item") {
        const h = asObjs(await q("traceItem", {runId:id, itemCode:s.code}))[0];
        if (!h) { box.innerHTML = `<div class="empty">本次运行没有物料 ${esc(s.code)}</div>`; root = null; return; }
        root = trNode({kind:"item", exp:true, code:h.ItemCode, label:`物料 ${h.ItemCode}`, sub:h.ItemName || "", lv:h.iLevel, qty:h.Qty, price:h.Price,
          a:[Number(h.MatAmt || 0), Number(h.MfgAmt || 0), Number(h.LabAmt || 0), Number(h.SubAmt || 0)],
          note:`单价四项：材料 ${fmtNum(h.PMat)} / 制造 ${fmtNum(h.PMfg)} / 人工 ${fmtNum(h.PLab)} / 委外 ${fmtNum(h.PSub)}；${trSrcText(h.PriceSrc)}`, psrc:h.PriceSrc}, null);
        $("#trRoot").textContent = "";
      } else {
        root = trNode({kind:"order", exp:true, ord:{type:s.type, entry:s.entry}, label:`订单 ${s.type}-${s.entry}`}, null);
        $("#trRoot").textContent = `从订单 ${s.type}-${s.entry} 开始`;
      }
      await trLoad(root, id); draw();
    } catch (e) { box.innerHTML = errBox(e); }
  };
  $("#trGo").onclick = () => { const v = $("#trCode").value.trim(); if (!v) { box.innerHTML = errBox("请先输入物料编码"); return; } start({kind:"item", code:v}); };
  $("#trCode").onkeydown = e => { if (e.key === "Enter") $("#trGo").click(); };
  // “详情”：打开原来的物料 / 订单明细（表格点行规则不管链接）
  box.onclick = e => {
    const d = e.target.closest("a.trd"); if (!d) return;
    const w = d.closest(".tbl"), st = w && TBL.get(w.id), tr = d.closest("tr[data-i]"); if (!st || !tr) return;
    const n = nodeOf(st.r.rows[tr.dataset.i]); if (!n) return;
    if (n.ord) orderDetail(id, {OrderType:n.ord.type, OrderEntry:n.ord.entry, OrderNum:n.ord.num, ItemCode:n.ord.item}); else itemDetail(id, {ItemCode:n.code});
  };
  $("#trAll").onclick = async () => {
    if (!root) return;
    const b = $("#trAll"); b.disabled = true;
    try {
      for (let lvl = 0; lvl < 30; lvl++) {
        const todo = trVisible(root).filter(n => n.exp && !n.cyc && !n.err && (!n.kids || !n.open));
        if (!todo.length || trVisible(root).length > TR_MAX) break;
        b.textContent = `展开中…（${trVisible(root).length} 行）`;
        for (let k = 0; k < todo.length; k += 6) await Promise.all(todo.slice(k, k + 6).map(async n => { if (n.kids) n.open = true; else await trLoad(n, id); }));
        draw();
      }
      if (trVisible(root).length > TR_MAX) toast(`已超过 ${TR_MAX} 行，停止展开；需要更深的层次请逐个点开`);
    } finally { b.disabled = false; b.textContent = "全部展开"; draw(); }
  };
  $("#trFold").onclick = () => { if (!root) return; const f = n => { if (n.depth) n.open = false; (n.kids || []).forEach(f); }; f(root); draw(); };
  draw();
  if (sp.kind) start(sp);
}
