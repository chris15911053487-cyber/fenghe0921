// 成本执行台 · trace.js — 成本追溯：从物料或订单逐层展开料工费来源
// index.html 按顺序加载 js/ 下的脚本，共用全局作用域；加载时立即执行的代码只能用到本文件和前面文件里的名字。
"use strict";
// ---------------- 成本追溯（用户 2026-10-23）----------------
// 从一个物料（或订单）出发逐层展开料工费的来源：物料 = 期初 + 计入加权单价的入库（完工订单、形态转换、采购等）；
// 订单 = 各材料本期结转（四项随子件带上来）+ 本级分摊的制造费用、人工 + 委外加工费；材料再展开成它自己的来源，一直到采购件。
// 每层只在点开时查询（traceItemSrc / orderHead + traceOrderMat）；“构成占比” = 本行合计 ÷ 同一层各行合计（= 上层的金额）。
let TRACE = null; try { TRACE = JSON.parse(localStorage.getItem("cc.trace") || "null"); } catch (e) {}
if (URL0 && URL0.tab === "trace" && URL0.obj) TRACE = URL0.obj;
let TRN = 0;
const TR_MAX = 1500;
function goTrace(spec){
  TRACE = spec; try { localStorage.setItem("cc.trace", JSON.stringify(spec)); } catch (e) {}
  TAB = "trace"; try { localStorage.setItem("cc.tab", TAB); } catch (e) {}
  renderTab();
}
const trSum = a => a[0] + a[1] + a[2] + a[3];
const trAmt = (x, p = "") => [p + "Mat", p + "Mfg", p + "Lab", p + "Sub"].map(k => Number(x[k] || 0));
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
        if (x.ItemCode === "#SUBFEE") { kids.push(trNode({kind:"subfee", a, label:"委外加工费", note:"随入库全部结转"}, n)); continue; }
        kids.push(trNode({kind:"item", exp:true, code:x.ItemCode, a, lv:x.iLevel, price:x.Price,
          label:`材料 ${x.ItemCode}`, sub:x.ItemName || "", note:`本期结转（本期领料 ${fmtNum(x.IssQty)}）；单价是该材料的加权单价`}, n));
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
    return {n, amt, unit, mix, pct: sib && Math.abs(tot) > 0.005 ? amt / tot * 100 : null};
  });
}
// 追溯表用共用表格 table() 的树形模式（2026-10-23）：工具条（复制、导出 Excel、列、全屏、本表筛选）和其他表格一样；
// 展开 / 收起后 tblSetData 原地换数据。NodeId 是隐藏的键列；追溯路径的值带全角空格缩进，复制、导出到 Excel 时保留层次
const TR_COLS = ["NodeId", "层次", "追溯路径", "名称", "物料层级", "数量", "单价", "材料", "制造费用", "人工", "委外加工费", "合计", "料%", "工%", "费%", "构成占比%", "说明"];
const TR_TIPS = {"追溯路径": "点 ▸ 展开下一层；双击行也可以展开 / 收起", "料%": "本行（材料 + 委外加工费）÷ 本行合计", "工%": "本行人工 ÷ 本行合计", "费%": "本行制造费用 ÷ 本行合计",
  "构成占比%": "本行合计 ÷ 同一层各行合计（就是上一层那一行的金额）"};
const trPct = v => v === null || v === undefined || !isFinite(v) ? null : Math.round(v * 100) / 100;   // 比例两位小数
const trNum = v => v === null || v === undefined || v === "" || !isFinite(Number(v)) ? null : Number(v);
function trData(root, nodes){
  nodes.clear();
  return {columns: TR_COLS, rows: trRows(root).map(({n, amt, unit, mix, pct}) => {
    nodes.set(n.id, n);
    return [n.id, n.depth, "\u3000".repeat(n.depth) + n.label, n.sub || "", trNum(n.lv), trNum(n.qty), trNum(unit), ...(n.a || [0, 0, 0, 0]).map(Number), amt,
      ...mix.map(trPct), trPct(pct), n.err || (n.cyc ? "上层已出现这个物料（返工单自己加工自己），不再展开" : n.note || "")];
  })};
}
async function renderTrace(pane, id){
  const sp = TRACE || {};
  pane.innerHTML = latestNote() + note(`从一个物料或订单出发，逐层展开料工费从哪里来，四项（材料、制造费用、人工、委外加工费）一直随物料往上传。<br>
    <b>物料</b>一行是“期初 + 计入加权单价的入库”（加权单价的分子），单价是本期加权单价；下一层是期初结存、各完工订单、形态转换、采购等来源（出库和不计入单价的调整不列）。<br>
    <b>订单</b>一行是本期完工成本，单价是单位成本；下一层是各材料的本期结转（四项按子件单价的构成带上来）、本级分摊的制造费用和人工、委外加工费。材料再点开就是这个材料自己的来源，一直到采购件。<br>
    “本级分摊”点开是各费用池：单位工时 × 本期入库数 = 本订单工时，占池内全部订单工时的比例 × 池的制造费用 / 人工 = 分到本订单的金额。<br>
    “料% / 工% / 费%”是本行自己的构成（料含委外加工费，三项合计 100%），可以逐层对比比例怎么变化。“构成占比” = 本行合计 ÷ 同一层各行合计（就是上一层那一行的金额）。本期没有结转的材料不列（领料都留在在产品里）。返工单领用的物料和产出相同，到这里停止展开。“详情”打开原来的物料 / 订单明细。`, "trace")
    + `<div class="bar"><input type="text" id="trCode" placeholder="物料编码" maxlength="50" value="${esc(sp.kind === "item" ? sp.code : "")}">`
    + `<button class="btn primary" id="trGo">追溯</button><span class="hint" id="trRoot"></span><span class="sp"></span>`
    + `<button class="btn" id="trAll" title="逐层点开全部，最多 ${TR_MAX} 行">全部展开</button><button class="btn" id="trFold">收起</button></div><div id="trBox"></div>`;
  const box = $("#trBox"), nodes = new Map();
  let root = null, tid = null;
  const nodeOf = x => nodes.get(x[0]);
  const opt = {hide:["NodeId"], key:"NodeId", sum:false, freeze:3, wrap:["说明"], tips:TR_TIPS, onRow:true, noClick: x => !nodeOf(x).exp,
    trCls: x => { const n = nodeOf(x); return "tr-" + n.kind + (n.depth ? "" : " tot"); },
    fmt: {"追溯路径": (v, x) => { const n = nodeOf(x); return esc(n.label) + (n.ord ? ` <a class="trd">详情</a>` : n.code ? ` <a class="trd">详情</a>` : ""); },
          "说明": (v, x) => { const n = nodeOf(x); return n.err ? `<span class="bad">${esc(v)}</span>` : `<span class="hint">${esc(v)}</span>`; },
          "合计": v => `<b>${fmtNum(v)}</b>`},
    tree: {col:"追溯路径", depth: x => x[1], can: x => nodeOf(x).exp, toggle: x => toggle(nodeOf(x)),
           mark: x => { const n = nodeOf(x); return n.loading ? "…" : n.exp ? (n.open ? "▾" : "▸") : "·"; }}};
  const draw = () => {
    if (!root) { box.innerHTML = `<div class="empty">输入物料编码后点“追溯”；也可以在物料单价、订单的明细里点“逐层追溯料工费”。</div>`; tid = null; return; }
    const r = trData(root, nodes);
    if (tid && document.getElementById(tid)) { tblSetData(tid, r); return; }
    box.innerHTML = table(r, opt); tid = box.querySelector(".tbl").id;
    bindRows(box, r, o => toggle(nodes.get(o.NodeId)));   // 点行处理函数拿到的是按列名的对象
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
    tid = null; box.innerHTML = `<div class="empty">加载中…</div>`;
    try {
      if (s.kind === "item") {
        const h = asObjs(await q("traceItem", {runId:id, itemCode:s.code}))[0];
        if (!h) { box.innerHTML = `<div class="empty">本次运行没有物料 ${esc(s.code)}</div>`; root = null; return; }
        root = trNode({kind:"item", exp:true, code:h.ItemCode, label:`物料 ${h.ItemCode}`, sub:h.ItemName || "", lv:h.iLevel, qty:h.Qty, price:h.Price,
          a:[Number(h.MatAmt || 0), Number(h.MfgAmt || 0), Number(h.LabAmt || 0), Number(h.SubAmt || 0)],
          note:`单价四项：材料 ${fmtNum(h.PMat)} / 制造 ${fmtNum(h.PMfg)} / 人工 ${fmtNum(h.PLab)} / 委外 ${fmtNum(h.PSub)}；${priceSrcText(h.PriceSrc || "")}`}, null);
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
