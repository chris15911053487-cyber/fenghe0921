// 成本执行台 · table.js — 通用表格 table()：工具条、排序、按列筛选、合计行、多选、调列宽、全屏、复制到 Excel、导出
// index.html 按顺序加载 js/ 下的脚本，共用全局作用域；加载时立即执行的代码只能用到本文件和前面文件里的名字。
"use strict";
// ---------------- 通用表格 ----------------
// 点行方式（用户 2026-10-23）：dbl = 单击只选中，双击或选中后按 Enter 打开明细（默认）；one = 单击打开。顶栏下拉框切换，记在本机 cc.click
let CLICK = "dbl"; try { CLICK = localStorage.getItem("cc.click") === "one" ? "one" : "dbl"; } catch (e) {}
let LASTSEL = null, CLICK_HINT = false;
// table() 返回表格 HTML，并把数据登记在 TBL（按表格 id）。工具条（行数、筛选、快速筛选、复制到 Excel、列显示）、点表头排序、
// 分组表头（列名中的“·”或 opt.groups）、冻结左侧列都在本页处理，不重查数据库。点行用 bindRows 登记处理函数，
// 事件统一在 document 上分发，所以排序、筛选重画后仍然有效（用户 2026-10-17）。
// opt：hide 不显示的列；hideDefault 默认隐藏、可在“列”里打开；quick {label, test(行, 取列序号), def} 快速筛选；
//      groups {列: [分组, 列名]}；freeze 冻结左侧列数（默认 1，最多 3）；sort:false 不排序（有 rowCls 小计 / 合计行的表自动不排序）；
//      tips {列: 表头提示}；trCls(行) 只加样式的行 class（不算小计）；key 行的唯一键列（tblSetData 换数据后保留选中行）；
//      tree 树形（2026-10-23，成本追溯）：{col 显示缩进和 ▸ 的列, depth(行), mark(行) 显示的符号, can(行) 能否展开, toggle(行)}，
//        点 ▸ 调 toggle，树形表不排序；展开后调用方用 tblSetData(表格 id, 新数据) 原地换数据，全屏、列宽、筛选都保留
const TBL = new Map(); let TBLN = 0;
let COLS = {}; try { COLS = JSON.parse(localStorage.getItem("cc.cols") || "{}") || {}; } catch (e) {}
const saveCols = () => { try { localStorage.setItem("cc.cols", JSON.stringify(COLS)); } catch (e) {} };
let COLW = {}; try { COLW = JSON.parse(localStorage.getItem("cc.colw") || "{}") || {}; } catch (e) {}
const saveColw = () => { try { localStorage.setItem("cc.colw", JSON.stringify(COLW)); } catch (e) {} };
// 合计行不加的数字列：单价、比例、层级、耗时等加起来没有意义
const NOSUM = /Price|Ratio|^Rt|Unit|Pct|Rate|Level|^Sec$|Iter|Delta|Cnt$|^Lines$|Days?$|单价|比例|占比|%|层级|天数|月数|单耗|费率|每件|每工时|单位成本|单位工时|因素|行号|账期数|运行号|批号|本期值|上期值/;
const NOFMT = ["StepNo","SeqNo","Iter","RunId","iLevel","LineNo","OrderEntry","OrderNum","DocEntry","DocNum","LineNum","ObjType","TransId","LineId","Line_ID","SrcDoc","RcptNum","JdtNum","DocNo","BaseRef"];
// 编号类列（不加千分位、不合计）：英文列名按 NOFMT，成本报表的中文列名按“单号 Num / 订单 Entry / 行号 / 运行号 / 层级”等（用户 2026-10-30）
const noFmt = c => NOFMT.includes(c) || /Num$|Entry$|行号|运行号|批号|^层级$|^账期数$/.test(c);
function table(r, opt = {}){
  if (!r.rows.length) return `<div class="empty">${esc(opt.empty || "没有数据")}</div>`;
  const id = "t" + (++TBLN), key = TAB + "|" + r.columns.join(",");
  const st = {id, r, opt, key, sort:null, filter:"", fn:null, txt:null,
    quick: !!opt.quick && opt.quick.def !== false,
    hidden: new Set(COLS[key] || opt.hideDefault || []),
    num: r.columns.map((c, i) => r.rows.every(x => x[i] === null || typeof x[i] === "number")),
    skipCode: new Set(r.columns.filter(c => NAMECOL[c] && r.columns.includes(NAMECOL[c]))),
    pick: new Set(), anchor: null, cf: {}, w: Object.assign({}, COLW[key] || {})};
  st.canSort = opt.sort !== false && !opt.rowCls && !opt.tree;
  tblPrune(); TBL.set(id, st);
  const inner = tblInner(st), nv = r.columns.filter(c => !(opt.hide || []).includes(c)).length;
  requestAnimationFrame(() => tblLayout(id));
  return `<div class="tbl" id="${id}"><div class="tbar"><span class="cnt">${tblCnt(st)}</span>`
    + (opt.quick ? `<button data-a="quick" class="${st.quick ? "on" : ""}">${esc(opt.quick.label)}</button>` : "")
    + (r.rows.length > 8 ? `<input type="text" class="tf" placeholder="在本表中筛选…" maxlength="50">` : "")
    + `<span class="sp"></span>` + (r.src && r.src.length ? `<button data-a="sql" title="查看这张表的查询语句和参数">SQL</button>` : "")
    + `<span class="tx"></span>`
    + `<button data-a="copy" title="复制当前显示的行和列（有选中的行时只复制选中的行），可直接粘贴到 Excel">复制</button>`
    + `<button data-a="xlsx" title="${r.truncated && r.src && r.src.length === 1 ? "从数据库重新取全部行，导出成 Excel（不受页面 2000 行限制，页面上的筛选不带过去）" : "把当前显示的行和列导出成 Excel（有选中的行时只导出选中的行）"}">${r.truncated && r.src && r.src.length === 1 ? "导出全部 Excel" : "导出 Excel"}</button>`
    + (nv > 4 ? `<button data-a="cols" title="选择显示哪些列">列 ▾</button>` : "")
    + `<button data-a="full" title="表格全屏（Esc 退出）">⛶ 全屏</button></div>`
    + `<div class="tw">${inner}</div>`
    + (r.truncated ? `<p class="hint">只显示前 ${r.rows.length} 行（复制的也只有这些行）${r.src && r.src.length === 1 ? "，要全部行请点“导出全部 Excel”" : "，导出的也只有这些行"}；也可以用搜索缩小范围。</p>` : "") + `</div>`;
}
const tblCnt = st => st.shown === st.r.rows.length ? `${st.shown} 行` : `${st.shown} / ${st.r.rows.length} 行`;
// 工具条上的状态：列筛选个数、选中行数（点 ✕ 清除）
const tblTx = st => {
  const n = Object.keys(st.cf).length;
  return (n ? `<button data-a="cfclr" class="on" title="清除全部列筛选">列筛选 ${n} ✕</button>` : "")
    + (st.pick.size ? `<button data-a="pkclr" class="on" title="清除选中（Ctrl / ⌘ 点行多选，Shift 点行连选）">已选 ${st.pick.size} 行 ✕</button>` : "");
};
// 可以合计的列：数字列，去掉编号类（NOFMT）和单价 / 比例类（NOSUM）
const sumCol = (st, i) => st.num[i] && !noFmt(st.r.columns[i]) && !NOSUM.test(st.r.columns[i]);
// 列筛选：{列名: {t:"set", vals:Set}} 或 {t:"num", op, v}
function cfTest(f, v){
  if (f.t === "set") return f.vals.has(blank(v) ? "" : String(v));
  const x = blank(v) ? null : Number(v), y = Number(f.v);
  switch (f.op) {
    case "ne0": return x !== null && Math.abs(x) > 1e-9;
    case "gt0": return x !== null && x > 1e-9;
    case "lt0": return x !== null && x < -1e-9;
    case "blank": return x === null;
    case "ge": return x !== null && x >= y;
    case "le": return x !== null && x <= y;
    case "eq": return x !== null && Math.abs(x - y) < 1e-9;
    case "absge": return x !== null && Math.abs(x) >= y;
  }
  return true;
}
// 列标题 [分组, 列名]：opt.groups 优先，否则按中文列名里的“·”拆
function colHead(st, c){
  const g = st.opt.groups && st.opt.groups[c];
  if (g) return g;
  const l = LABEL[c] || c, k = l.indexOf("·");
  return k > 0 ? [l.slice(0, k), l.slice(k + 1)] : [null, l];
}
const tblCols = st => st.r.columns.map((c, i) => i).filter(i => !(st.opt.hide || []).includes(st.r.columns[i]) && !st.hidden.has(st.r.columns[i]));
const blank = v => v === null || v === undefined || v === "";
// 当前显示的行（原始行号）：快速筛选 → 文字筛选（小计 / 合计行保留）→ 排序
function tblRows(st){
  const r = st.r, cols = r.columns, cls = st.opt.rowCls;
  let ix = r.rows.map((x, i) => i);
  if (st.quick && st.opt.quick) { const col = c => cols.indexOf(c); ix = ix.filter(i => st.opt.quick.test(r.rows[i], col)); }
  const cfs = Object.entries(st.cf).map(([c, f]) => [cols.indexOf(c), f]).filter(([i]) => i >= 0);
  if (cfs.length) ix = ix.filter(i => (cls && cls(r.rows[i])) || cfs.every(([k, f]) => cfTest(f, r.rows[i][k])));
  if (st.filter) {
    if (!st.txt) st.txt = r.rows.map(x => x.map((v, i) => blank(v) ? "" : String(codeText(cols[i], v))).join("\u0001").toLowerCase());
    const f = st.filter.toLowerCase();
    ix = ix.filter(i => st.txt[i].includes(f) || (cls && cls(r.rows[i])));
  }
  if (st.sort) {
    const c = st.sort.i, dir = st.sort.dir, num = st.num[c];
    ix.sort((a, b) => {
      const x = r.rows[a][c], y = r.rows[b][c];
      if (blank(x)) return blank(y) ? 0 : 1;
      if (blank(y)) return -1;
      return (num ? x - y : String(x).localeCompare(String(y), "zh-CN", {numeric:true})) * dir;
    });
  }
  return ix;
}
function tblInner(st){
  const r = st.r, opt = st.opt, fmt = opt.fmt || {}, wrapCols = new Set(opt.wrap || []), tree = opt.tree;
  const cols = tblCols(st), rows = tblRows(st); st.shown = rows.length;
  const nfz = Math.min(opt.freeze ?? 1, 3, Math.max(cols.length - 1, 0));
  const heads = cols.map(i => colHead(st, r.columns[i])), grouped = heads.some(h => h[0]);
  // 分组的起点画左边框；冻结列 fz0…fz2，最后一个冻结列右侧画线
  const gs = cols.map((i, k) => k > 0 && !!(heads[k][0] || heads[k - 1][0]) && heads[k][0] !== heads[k - 1][0]);
  const fzc = k => k < nfz ? ` fz fz${k}${k === nfz - 1 ? " fzl" : ""}` : "";
  const cls = k => (gs[k] ? " gs" : "") + fzc(k);
  const mark = i => st.sort && st.sort.i === i ? `<span class="ar">${st.sort.dir > 0 ? "▲" : "▼"}</span>` : "";
  const cw = k => { const w = st.w[r.columns[cols[k]]]; return w ? `min-width:${w}px;max-width:${w}px;width:${w}px` : ""; };
  const leaf = (k, extra = "") => { const c = r.columns[cols[k]], wd = cw(k);
    const tip = opt.tips && opt.tips[c] ? opt.tips[c] + (st.canSort ? "；点击排序" : "") : st.canSort ? "点击排序" : "";
    return `<th class="${st.canSort ? "s" : ""}${cls(k)}" data-c="${cols[k]}"${extra}${wd ? ` style="${wd}"` : ""}${tip ? ` title="${esc(tip)}"` : ""}>${esc(heads[k][1])}${mark(cols[k])}`
      + `<span class="cf${st.cf[c] ? " on" : ""}" title="按本列筛选">▾</span><span class="rz" title="拖动调整列宽，双击恢复"></span></th>`; };
  let h = `<table><thead>`;
  if (grouped) {
    let r1 = "", r2 = "";
    for (let k = 0; k < cols.length; k++) {
      const g = heads[k][0];
      if (!g) { r1 += leaf(k, ` rowspan="2"`); continue; }
      let n = 1; while (k + n < cols.length && heads[k + n][0] === g) n++;
      r1 += `<th class="g${gs[k] ? " gs" : ""}" colspan="${n}">${esc(g)}</th>`;
      for (let j = k; j < k + n; j++) r2 += leaf(j);
      k += n - 1;
    }
    h += `<tr>${r1}</tr><tr class="h2">${r2}</tr>`;
  } else h += `<tr>${cols.map((i, k) => leaf(k)).join("")}</tr>`;
  h += `</thead><tbody>`;
  for (const ri of rows) {
    const x = r.rows[ri];
    const ck = opt.onRow && !(opt.noClick && opt.noClick(x));
    h += `<tr data-i="${ri}" class="${ck ? "click" : ""} ${opt.rowCls ? opt.rowCls(x) : ""}${opt.trCls ? " " + opt.trCls(x) : ""}${st.pick.has(ri) ? " pick" : ""}"${ck ? ` title="${CLICK === "one" ? "点击查看明细" : "双击（或选中后按 Enter）查看明细"}"` : ""}>`;
    cols.forEach((i, k) => {
      const c = r.columns[i], v = x[i], wd = cw(k), cc = cls(k) + (wd ? ` cw" style="${wd}" title="${esc(cellText(st, x, i))}` : ""), w = wrapCols.has(c) ? " wrap" : "";
      let td, inner;
      if (fmt[c]) { td = w + (st.num[i] && !noFmt(c) ? " n" : ""); inner = fmt[c](v, x); }
      else {
        const ch = st.skipCode.has(c) ? null : codeHtml(c, v);
        if (ch !== null) { td = w; inner = ch; }
        else if (st.num[i] && !noFmt(c)) { td = "n"; inner = fmtNum(v); }
        else { td = w; inner = esc(v); }
      }
      if (tree && c === tree.col) { const can = tree.can(x);
        inner = `<span class="tind" style="width:${tree.depth(x) * 16}px"></span><span class="tg${can ? " on" : ""}"${can ? ` data-tg="1" title="展开 / 收起"` : ""}>${tree.mark(x)}</span>` + inner; }
      h += `<td class="${td}${cc}">${inner}</td>`;
    });
    h += "</tr>";
  }
  if (!rows.length) h += `<tr><td colspan="${cols.length}" class="empty">${st.quick && !st.filter ? `没有“${esc(opt.quick.label)}”的行，点上面的按钮显示全部` : "没有匹配的行"}</td></tr>`;
  return h + "</tbody>" + tblFoot(st, cols, rows, cls) + "</table>";
}
// 底部固定的合计行：当前筛选后的明细行（小计 / 合计行不计）；有选中的行时上面再加一行“已选”的合计
function tblFoot(st, cols = tblCols(st), rows = tblRows(st), cls){
  if (st.opt.sum === false) return "";
  const r = st.r, plainRow = i => !(st.opt.rowCls && st.opt.rowCls(r.rows[i]));
  const sc = cols.map(i => sumCol(st, i));
  if (!sc.some(Boolean) || r.rows.length < 2) return "";
  if (!cls) { const nfz = Math.min(st.opt.freeze ?? 1, 3, Math.max(cols.length - 1, 0)); cls = k => k < nfz ? ` fz fz${k}${k === nfz - 1 ? " fzl" : ""}` : ""; }
  const lab = sc.indexOf(false);
  const line = (ix, label, trc) => {
    const sums = cols.map((i, k) => { if (!sc[k]) return null; let t = 0, any = false; for (const j of ix) { const v = r.rows[j][i]; if (!blank(v)) { t += v; any = true; } } return any ? Math.round(t * 100) / 100 : null; });
    return `<tr class="${trc}">` + cols.map((i, k) => `<td class="${sc[k] ? "n" : ""}${cls(k)}">${sc[k] ? fmtNum(sums[k]) : k === lab ? esc(label) : ""}</td>`).join("") + "</tr>";
  };
  const base = rows.filter(plainRow), pk = base.filter(i => st.pick.has(i));
  return "<tfoot>" + (pk.length ? line(pk, `已选 ${pk.length} 行`, "pk") : "") + line(base, `合计（${base.length} 行）`, "sm") + "</tfoot>";
}
// 画完后量第一行表头的高度（第二行表头的吸顶位置）和冻结列的宽度（后面冻结列的左边距）
function tblLayout(id){
  const w = document.getElementById(id); if (!w) return;
  const t = w.querySelector("thead tr"); if (t) w.style.setProperty("--h1", t.offsetHeight + "px");
  const f = w.querySelector("tfoot tr.sm"); if (f) w.style.setProperty("--f1", f.offsetHeight + "px");
  let left = 0;
  for (let k = 0; k < 3; k++) {
    const th = w.querySelector(`thead th.fz${k}`); if (!th) break;
    if (k) w.style.setProperty("--fz" + k, left + "px");
    left += th.offsetWidth;
  }
}
// 原地换数据（树形展开 / 收起后用）：表格外框、工具条、全屏、列宽、筛选条件都保留；有 opt.key 时按键保留选中行
function tblSetData(id, r){
  const st = TBL.get(id); if (!st) return;
  const k = st.opt.key ? st.r.columns.indexOf(st.opt.key) : -1;
  const old = LASTSEL && LASTSEL.id === id && k >= 0 && st.r.rows[LASTSEL.i] ? st.r.rows[LASTSEL.i][k] : undefined;
  st.r = r; st.txt = null; st.pick.clear(); st.anchor = null;
  st.num = r.columns.map((c, i) => r.rows.every(x => x[i] === null || typeof x[i] === "number"));
  tblRender(id);
  if (old === undefined) return;
  const ni = r.rows.findIndex(x => x[k] === old), tr = ni >= 0 && document.querySelector(`#${id} tr[data-i="${ni}"]`);
  if (tr) { tr.classList.add("sel"); LASTSEL.i = String(ni); }
}
function tblRender(id){
  const w = document.getElementById(id), st = TBL.get(id); if (!w || !st) return;
  w.querySelector(".tw").innerHTML = tblInner(st);
  w.querySelector(".cnt").textContent = tblCnt(st);
  w.querySelector(".tx").innerHTML = tblTx(st);
  tblLayout(id);
}
// 登记表太多时清掉已经不在页面上（也不在抽屉返回栈里）的旧表；刚生成还没插入页面的不清
function tblPrune(){
  if (TBL.size < 300) return;
  for (const id of [...TBL.keys()]) {
    if (Number(id.slice(1)) > TBLN - 50 || document.getElementById(id)) continue;
    if (DR.stack.some(s => s.node.querySelector("#" + id))) continue;
    TBL.delete(id);
  }
}
function bindRows(el, r, fn){ el.querySelectorAll(".tbl").forEach(w => { const st = TBL.get(w.id); if (st && st.r === r) st.fn = fn; }); }
// 抽屉里的表格点行时为 true：drawer() 据此把当前一层压栈（钻取），而不是从第一层重新开始
let DRILL_IN = false;
document.addEventListener("click", e => {
  const t = e.target;
  if (!t.closest(".colmenu") && !t.closest('[data-a="cols"]')) document.querySelectorAll(".colmenu").forEach(m => m.remove());
  const w = t.closest(".tbl"), st = w && TBL.get(w.id); if (!st) return;
  const a = t.closest(".tbar [data-a]");
  if (a) {
    if (a.dataset.a === "copy") tblCopy(st);
    else if (a.dataset.a === "cols") colMenu(w, st);
    else if (a.dataset.a === "sql") { DRILL_IN = !!w.closest("#drawer"); try { showQuerySql(st.r.src); } finally { DRILL_IN = false; } }
    else if (a.dataset.a === "quick") { st.quick = !st.quick; a.classList.toggle("on", st.quick); tblRender(st.id); }
    else if (a.dataset.a === "xlsx") tblXlsx(w, st);
    else if (a.dataset.a === "full") tblFull(w, !w.classList.contains("full"));
    else if (a.dataset.a === "cfclr") { st.cf = {}; cfClose(); tblRender(st.id); }
    else if (a.dataset.a === "pkclr") { st.pick.clear(); st.anchor = null; tblRender(st.id); }
    return;
  }
  const cf = t.closest("th .cf");
  if (cf) { cfMenu(w, st, Number(cf.parentElement.dataset.c), cf); return; }
  if (t.closest("th .rz") || RZ_DONE) return;
  const th = t.closest("th.s");
  if (th) {
    // 数字列第一次点按从大到小，文字列从小到大；第三次取消排序
    const i = Number(th.dataset.c), d0 = st.num[i] ? -1 : 1;
    st.sort = !st.sort || st.sort.i !== i ? {i, dir:d0} : st.sort.dir === d0 ? {i, dir:-d0} : null;
    tblRender(st.id); return;
  }
  const tg = st.opt.tree && t.closest("[data-tg]");
  if (tg) { const tr = tg.closest("tr[data-i]"); tblSel(w, tr); st.opt.tree.toggle(st.r.rows[tr.dataset.i]); return; }
  const tr = t.closest("tr[data-i]");
  // Ctrl / ⌘ 点行多选，Shift 点行连选（按当前显示顺序），只做选中求和，不打开明细
  if (tr && (e.ctrlKey || e.metaKey || e.shiftKey) && !t.closest("a, button, input, select, summary")) {
    const i = Number(tr.dataset.i);
    if (e.shiftKey && st.anchor !== null) {
      const ix = tblRows(st), a0 = ix.indexOf(st.anchor), a1 = ix.indexOf(i);
      if (a0 >= 0 && a1 >= 0) for (const j of ix.slice(Math.min(a0, a1), Math.max(a0, a1) + 1)) st.pick.add(j);
    } else { if (st.pick.has(i)) st.pick.delete(i); else st.pick.add(i); st.anchor = i; }
    tblPick(w, st); return;
  }
  if (!tr || !tr.classList.contains("click") || !st.fn || t.closest("a, button, input, select, summary")) return;
  // 单击打开；双击方式下抽屉开着且是从这张表打开的，单击别的行直接换成这一行（跟随）
  if (CLICK === "one" || tblFollow(w)) tblOpen(w, st, tr);
  else {
    tblSel(w, tr);
    if (!CLICK_HINT) { CLICK_HINT = true; toast("双击（或按 Enter）打开明细；顶栏“双击开明细”可以改成单击打开"); }
  }
});
// 选中一行（高亮），↑ ↓ / Enter 以它为准
function tblSel(w, tr){
  w.querySelectorAll("tr.sel").forEach(x => x.classList.remove("sel")); tr.classList.add("sel");
  LASTSEL = {id:w.id, i:tr.dataset.i};
}
// 抽屉开着、且是从这张主页面表格打开的
const tblFollow = w => !w.closest("#drawer") && !$("#drawer").hidden && DR.src === w.id;
// 打开这一行的明细（调用 bindRows 登记的函数）；在抽屉里的表格上是往下钻取；同一行已经在抽屉里时不重复打开
function tblOpen(w, st, tr){
  const inDr = !!w.closest("#drawer"), i = tr.dataset.i;
  tblSel(w, tr);
  if (tblFollow(w) && DR.row === i) return;
  DRILL_IN = inDr;
  try { st.fn(asObjs(st.r)[i]); } finally { DRILL_IN = false; }
  if (!inDr && !st.opt.tree && !$("#drawer").hidden) { DR.src = w.id; DR.row = i; }
}
document.addEventListener("dblclick", e => {
  if (CLICK !== "dbl" || e.ctrlKey || e.metaKey || e.shiftKey) return;
  const t = e.target; if (t.closest("a, button, input, select, summary, th")) return;
  const tr = t.closest(".tbl tbody tr.click[data-i]"), w = tr && tr.closest(".tbl"), st = w && TBL.get(w.id);
  if (st && st.fn) tblOpen(w, st, tr);
});
// 双击时不选中文字
document.addEventListener("mousedown", e => { if (e.detail > 1 && CLICK === "dbl" && e.target.closest(".tbl tbody tr.click")) e.preventDefault(); });
// ↑ ↓ 在最后选中的表格里换行（抽屉跟随），Enter 打开；在输入框里、对话框或列菜单打开时不处理
document.addEventListener("keydown", e => {
  if (!LASTSEL || e.ctrlKey || e.metaKey || e.altKey || !["ArrowUp", "ArrowDown", "Enter"].includes(e.key)) return;
  if (e.target.closest && e.target.closest("input, textarea, select, button, [contenteditable]")) return;
  if ($("#dlg").open || document.querySelector(".colmenu, .cfmenu")) return;
  const w = document.getElementById(LASTSEL.id), st = w && TBL.get(w.id);
  if (!st || !st.fn || !w.offsetParent) return;
  const rows = [...w.querySelectorAll("tbody tr.click[data-i]")], k = rows.findIndex(x => x.dataset.i === LASTSEL.i);
  if (k < 0) return;
  e.preventDefault();
  if (e.key === "Enter") { tblOpen(w, st, rows[k]); return; }
  const tr = rows[k + (e.key === "ArrowDown" ? 1 : -1)]; if (!tr) return;
  tr.scrollIntoView({block:"nearest"});
  if (tblFollow(w)) tblOpen(w, st, tr); else tblSel(w, tr);
});
function setClick(v){
  CLICK = v === "one" ? "one" : "dbl"; try { localStorage.setItem("cc.click", CLICK); } catch (e) {}
  document.querySelectorAll(".tbl").forEach(w => { if (TBL.has(w.id)) tblRender(w.id); });
}
// 选中行变化时只改行的样式、合计行和工具条，不重画整张表
function tblPick(w, st){
  w.querySelectorAll("tbody tr[data-i]").forEach(x => x.classList.toggle("pick", st.pick.has(Number(x.dataset.i))));
  const tb = w.querySelector(".tw table"), old = tb && tb.querySelector("tfoot");
  if (old) old.remove();
  if (tb) tb.insertAdjacentHTML("beforeend", tblFoot(st));
  w.querySelector(".tx").innerHTML = tblTx(st); tblLayout(w.id);
}
document.addEventListener("mousedown", e => { if (e.shiftKey && e.target.closest(".tbl tbody tr[data-i]")) e.preventDefault(); });   // Shift 连选时不选中文字
// 表格全屏：铺满浏览器窗口，Esc 或再点一次退出
function tblFull(w, on){
  w.classList.toggle("full", on);
  const b = w.querySelector('[data-a="full"]'); if (b) b.textContent = on ? "退出全屏" : "⛶ 全屏";
  cfClose(); tblLayout(w.id);
}
// 拖表头右边缘调整列宽（松开后生效），双击恢复；按表记在本机 cc.colw
let RZ_DONE = false;
document.addEventListener("mousedown", e => {
  const rz = e.target.closest(".tbl th .rz"); if (!rz || e.button !== 0) return;
  e.preventDefault(); e.stopPropagation();
  const th = rz.parentElement, w = th.closest(".tbl"), st = TBL.get(w.id); if (!st) return;
  const x0 = e.clientX, w0 = th.getBoundingClientRect().width, line = document.createElement("div");
  line.className = "rzline"; line.style.left = e.clientX + "px"; document.body.appendChild(line);
  const mv = ev => { line.style.left = Math.max(th.getBoundingClientRect().left + 40, ev.clientX) + "px"; };
  const up = ev => {
    document.removeEventListener("mousemove", mv); document.removeEventListener("mouseup", up); line.remove();
    RZ_DONE = true; setTimeout(() => { RZ_DONE = false; }, 0);
    if (Math.abs(ev.clientX - x0) < 3) return;
    st.w[st.r.columns[Number(th.dataset.c)]] = Math.round(Math.max(40, w0 + ev.clientX - x0));
    COLW[st.key] = st.w; saveColw(); tblRender(st.id);
  };
  document.addEventListener("mousemove", mv); document.addEventListener("mouseup", up);
}, true);
document.addEventListener("dblclick", e => {
  const rz = e.target.closest(".tbl th .rz"); if (!rz) return;
  const th = rz.parentElement, w = th.closest(".tbl"), st = TBL.get(w.id); if (!st) return;
  delete st.w[st.r.columns[Number(th.dataset.c)]];
  if (Object.keys(st.w).length) COLW[st.key] = st.w; else delete COLW[st.key];
  saveColw(); tblRender(st.id);
});
// 按列筛选（类似 Excel 自动筛选）：文字列勾选值，数字列按条件；改了马上生效
const cfClose = () => document.querySelectorAll(".cfmenu").forEach(m => m.remove());
function cfMenu(w, st, i, anchor){
  const c = st.r.columns[i], old = document.querySelector(".cfmenu");
  cfClose(); if (old && old.dataset.k === w.id + "|" + i) return;
  const m = document.createElement("div"); m.className = "cfmenu"; m.dataset.k = w.id + "|" + i;
  const f = st.cf[c], h = colHead(st, c), apply = () => { tblRender(st.id); };
  let html = `<b>${esc(h[0] ? h[0] + " · " + h[1] : h[1])}</b>`;
  if (st.num[i]) {
    const ops = [["", "全部"], ["ne0", "≠ 0"], ["gt0", "> 0"], ["lt0", "< 0"], ["blank", "空白"], ["ge", "≥"], ["le", "≤"], ["eq", "="], ["absge", "绝对值 ≥"]];
    html += `<div class="row"><select class="op">${ops.map(([v, l]) => `<option value="${v}"${f && f.op === v ? " selected" : ""}>${l}</option>`).join("")}</select>`
      + `<input type="number" step="any" class="nv" value="${f && f.v !== undefined ? esc(f.v) : ""}" placeholder="数值"></div>`;
    m.innerHTML = html + `<div class="bar"><button data-m="clr">清除本列筛选</button></div>`;
    const op = m.querySelector(".op"), nv = m.querySelector(".nv");
    const set = () => {
      const o = op.value, need = ["ge", "le", "eq", "absge"].includes(o);
      nv.disabled = !need;
      if (!o || (need && nv.value === "")) delete st.cf[c]; else st.cf[c] = {t:"num", op:o, v:nv.value};
      apply();
    };
    op.onchange = set; nv.oninput = set; nv.disabled = !(f && ["ge", "le", "eq", "absge"].includes(f.op));
  } else {
    const cnt = new Map();
    for (const x of st.r.rows) { const k = blank(x[i]) ? "" : String(x[i]); cnt.set(k, (cnt.get(k) || 0) + 1); }
    const keys = [...cnt.keys()].sort((a, b) => a === "" ? 1 : b === "" ? -1 : a.localeCompare(b, "zh-CN", {numeric:true}));
    const cap = 1000, shown = keys.slice(0, cap), sel = f ? f.vals : null;
    html += `<input type="text" class="cs" placeholder="搜索值…">`
      + `<div class="vals">${shown.map(k => `<label><input type="checkbox" data-v="${esc(k)}"${!sel || sel.has(k) ? " checked" : ""}>${k === "" ? "（空白）" : esc(codeText(c, k))} <span class="hint">${cnt.get(k)}</span></label>`).join("")}</div>`
      + (keys.length > cap ? `<p class="hint" style="margin:0">不同的值超过 ${cap} 个，只列出前 ${cap} 个，可用搜索</p>` : "")
      + `<div class="bar"><button data-m="all">全选</button><button data-m="none">清空</button><button data-m="clr">清除本列筛选</button></div>`;
    m.innerHTML = html;
    const boxes = () => [...m.querySelectorAll(".vals input")];
    const set = () => {
      const on = new Set(boxes().filter(b => b.checked).map(b => b.dataset.v));
      if (on.size === keys.length || (keys.length > cap && on.size === shown.length)) delete st.cf[c]; else st.cf[c] = {t:"set", vals:on};
      apply();
    };
    m.querySelector(".vals").onchange = set;
    m.querySelector(".cs").oninput = e => { const q = e.target.value.trim().toLowerCase(); boxes().forEach(b => { b.parentElement.style.display = !q || b.parentElement.textContent.toLowerCase().includes(q) ? "" : "none"; }); };
    m.onclick = e => {
      const b = e.target.closest("[data-m]"); if (!b || b.dataset.m === "clr") return;
      boxes().forEach(x => { if (x.parentElement.style.display !== "none") x.checked = b.dataset.m === "all"; }); set();
    };
  }
  m.addEventListener("click", e => { if (e.target.closest('[data-m="clr"]')) { delete st.cf[c]; cfClose(); apply(); } });
  document.body.appendChild(m);
  const rc = anchor.getBoundingClientRect(), mw = m.offsetWidth, mh = m.offsetHeight;
  m.style.left = Math.max(4, Math.min(rc.left - 8, window.innerWidth - mw - 8)) + "px";
  m.style.top = (rc.bottom + mh + 8 > window.innerHeight ? Math.max(4, rc.top - mh - 4) : rc.bottom + 4) + "px";
  const inp = m.querySelector(".cs, .op"); if (inp) inp.focus();
}
document.addEventListener("mousedown", e => { if (!e.target.closest(".cfmenu") && !e.target.closest("th .cf")) cfClose(); });
let TF_T = null;
document.addEventListener("input", e => {
  const t = e.target; if (!t.classList || !t.classList.contains("tf")) return;
  const w = t.closest(".tbl"), st = w && TBL.get(w.id); if (!st) return;
  clearTimeout(TF_T); TF_T = setTimeout(() => { st.filter = t.value.trim(); tblRender(st.id); }, 180);
});
function colMenu(w, st){
  const old = w.querySelector(".colmenu"); if (old) { old.remove(); return; }
  const cols = st.r.columns.filter(c => !(st.opt.hide || []).includes(c));
  const m = document.createElement("div"); m.className = "colmenu";
  m.innerHTML = cols.map(c => { const h = colHead(st, c); return `<label><input type="checkbox" data-c="${esc(c)}"${st.hidden.has(c) ? "" : " checked"}>${esc(h[0] ? h[0] + " · " + h[1] : h[1])}</label>`; }).join("")
    + `<div class="bar"><button data-m="all">全部显示</button><button data-m="def">恢复默认</button></div>`;
  w.querySelector(".tbar").appendChild(m);
  const sync = () => m.querySelectorAll("input[data-c]").forEach(x => { x.checked = !st.hidden.has(x.dataset.c); });
  m.onchange = e => {
    const c = e.target.dataset.c; if (!c) return;
    if (e.target.checked) st.hidden.delete(c); else st.hidden.add(c);
    if (!tblCols(st).length) { st.hidden.delete(c); e.target.checked = true; return; }   // 至少留一列
    COLS[st.key] = [...st.hidden]; saveCols(); tblRender(st.id);
  };
  m.onclick = e => {
    const b = e.target.closest("[data-m]"); if (!b) return;
    if (b.dataset.m === "all") { st.hidden = new Set(); COLS[st.key] = []; }
    else { st.hidden = new Set(st.opt.hideDefault || []); delete COLS[st.key]; }
    saveCols(); sync(); tblRender(st.id);
  };
}
// 复制到 Excel：同时写 HTML 表格和制表符分隔文本。数字原值（不带千分位），Excel 识别为数字；
// 其余列标成文本格式（mso-number-format），编码的前导 0 不丢。代码列和导出 Excel 一样带中文名（codeText）
const INERT = document.implementation.createHTMLDocument("");
const plain = h => { INERT.body.innerHTML = h; return INERT.body.textContent.trim(); };
function cellText(st, x, i){
  const c = st.r.columns[i], v = x[i], f = (st.opt.fmt || {})[c];
  if (blank(v)) return "";
  if (st.num[i]) return String(v);
  if (f) return plain(f(v, x));
  return String(codeText(c, v) ?? "");
}
async function tblCopy(st){
  const {r, cols, head, data, picked} = tblView(st);
  const tsv = [head, ...data].map(a => a.map(s => s.replace(/[\t\r\n]+/g, " ")).join("\t")).join("\r\n");
  const tx = `style='mso-number-format:"\\@"'`;
  const html = `<table><thead><tr>${head.map(h => `<th ${tx}>${esc(h)}</th>`).join("")}</tr></thead><tbody>`
    + data.map(a => `<tr>${a.map((s, k) => st.num[cols[k]] ? `<td>${esc(s)}</td>` : `<td ${tx}>${esc(s)}</td>`).join("")}</tr>`).join("") + `</tbody></table>`;
  let ok = false;
  try {
    if (navigator.clipboard && window.ClipboardItem) {
      await navigator.clipboard.write([new ClipboardItem({"text/html": new Blob([html], {type:"text/html"}), "text/plain": new Blob([tsv], {type:"text/plain"})})]);
      ok = true;
    }
  } catch (e) {}
  if (!ok) ok = copyFallback(html);
  toast(ok ? `已复制${picked ? "选中的 " : " "}${data.length} 行 × ${cols.length} 列${r.truncated && !picked ? `（只有已加载的 ${r.rows.length} 行）` : ""}，可以直接粘贴到 Excel` : "复制失败：浏览器不允许访问剪贴板，请用“导出”");
}
// 当前显示的列和行（有选中的行时只取选中的行），复制和导出共用
function tblView(st){
  const r = st.r, cols = tblCols(st), all = tblRows(st), sel = all.filter(i => st.pick.has(i)), rows = sel.length ? sel : all;
  const head = cols.map(i => { const h = colHead(st, r.columns[i]); return h[0] ? h[0] + "·" + h[1] : h[1]; });
  return {r, cols, head, picked: !!sel.length, data: rows.map(ri => cols.map(i => cellText(st, r.rows[ri], i)))};
}
const tblName = w => (w.closest("#drawer") ? DR.title : (document.querySelector(`#tabs button[data-t="${TAB}"]`) || {}).textContent || TAB).replace(/[\\/:*?"<>|\s]+/g, "_").slice(0, 60);
// 导出 Excel：没截断时导出当前显示的行和列；被截断（2000 行）时按同一查询从数据库取全部行（服务端上限 20 万行）
async function tblXlsx(w, st){
  const name = tblName(w) + "_" + new Date().toISOString().slice(0, 10), sheet = tblName(w).slice(0, 31);
  try {
    if (st.r.truncated && st.r.src && st.r.src.length === 1) {
      toast("正在从数据库取全部行…");
      const s = st.r.src[0], all = await api("/api/q", {action:s.action, args:s.args, all:true});
      toast(`正在生成 Excel（${all.rows.length} 行）…`);
      await saveXlsx([xFromResult(all, sheet)], name);
      toast(`已导出 ${all.rows.length} 行${all.truncated ? "（超过 20 万行，只导出了前 20 万行）" : ""}；页面上的筛选、隐藏列没有带过去`);
      return;
    }
    const sh = xFromTable(st, sheet);
    await saveXlsx([sh], name); toast(`已导出${sh.picked ? "选中的 " : " "}${sh.rows.length} 行到 Excel`);
  } catch (e) { toast("导出失败：" + (e.message || e)); }
}
function copyFallback(html){
  const d = document.createElement("div");
  d.contentEditable = "true"; d.style.cssText = "position:fixed;left:-99999px;top:0";
  d.innerHTML = html; document.body.appendChild(d);
  const s = getSelection(), rg = document.createRange(); rg.selectNodeContents(d); s.removeAllRanges(); s.addRange(rg);
  let ok = false; try { ok = document.execCommand("copy"); } catch (e) {}
  s.removeAllRanges(); d.remove(); return ok;
}
let TOAST_T = null;
function toast(t){
  let el = $("#toast");
  if (!el) { el = document.createElement("div"); el.id = "toast"; el.className = "toast"; document.body.appendChild(el); }
  el.textContent = t; el.hidden = false;
  clearTimeout(TOAST_T); TOAST_T = setTimeout(() => { el.hidden = true; }, 2800);
}
