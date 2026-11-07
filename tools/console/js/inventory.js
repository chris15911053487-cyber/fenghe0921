// 成本执行台 · inventory.js — 收发存汇总、科目余额表明细账、物料收发明细、物料明细 itemDetail()
// index.html 按顺序加载 js/ 下的脚本，共用全局作用域；加载时立即执行的代码只能用到本文件和前面文件里的名字。
"use strict";
// 收发存汇总：物料行 + 物料组小计 + 合计。小计和合计另查（invGrp），物料行超过行数上限被截断时也是全量数
async function invSummary(id){
  const box = $("#lst");
  box.innerHTML = `<div class="bar"><h3 style="margin:0">收发存汇总</h3><span class="sp"></span><input type="text" id="sq" placeholder="物料编码开头或物料组" maxlength="50" value="${esc(sqGet("收发存汇总"))}"><button class="btn" id="sgo">查询</button><button class="btn" id="selem"></button><button class="btn" id="scsv">导出 Excel</button></div><div id="sres"></div>`;
  let last = null;
  const K = ["Beg", "In", "Out", "End"], EL = ["Mat", "Mfg", "Lab", "Sub"];
  // 料工费构成（材料 / 制造 / 人工 / 委外）默认收起，展开状态记在本机
  let showEl = false; try { showEl = localStorage.getItem("cc.invElem") === "Y"; } catch (e) {}
  const elCols = K.flatMap(k => EL.map(e => k + e));
  // 展开料工费时最右边加占比（用户 2026-10-18）：期初、入库、出库、期末各自的材料 / 人工 / 制造 / 委外 ÷ 四项合计，显示 2 位小数；四项合计为 0 时为空
  // 物料行取 MTC_CA_R_ITEM.Rt*（P50 写入，invSum 查出，期初列名 Open → Beg）；小计、合计按汇总金额现算，公式与 P50 相同
  const RT = ["Mat", "Lab", "Mfg", "Sub"], rtCols = K.flatMap(k => RT.map(e => "Rt" + k + e));
  const rtOf = o => Object.fromEntries(K.flatMap(k => { const v = RT.map(e => Number(o[k + e]) || 0), t = v.reduce((a, b) => a + b, 0); return RT.map((e, j) => ["Rt" + k + e, Math.abs(t) > 0.005 ? Math.round(v[j] / t * 1000000) / 10000 : null]); }));
  const elBtn = () => { $("#selem").textContent = showEl ? "收起料工费" : "展开料工费"; };
  elBtn();
  const go = async () => {
    const v = $("#sq").value.trim();
    if (!/^[A-Za-z0-9_.\-\/]{0,50}$/.test(v)) { $("#sres").innerHTML = errBox("只能输入字母、数字、下划线、点、横线和斜线"); return; }
    sqSet("收发存汇总", v);
    $("#sres").innerHTML = `<div class="empty">加载中…</div>`;
    try { show(...await Promise.all([q("invSum", {runId:id, q:v}), q("invGrp", {runId:id, q:v})])); } catch (e) { $("#sres").innerHTML = errBox(e); }
  };
  let lastRaw = null;
  const show = (it, g) => {
    lastRaw = [it, g];
    const ci = c => it.columns.indexOf(c);
    const row = (grp, name, code, label, o) => {
      const x = it.columns.map(() => null);
      x[ci("ItmsGrpCod")] = grp; x[ci("GrpName")] = name; x[ci("ItemCode")] = code; x[ci("ItemName")] = label;
      K.forEach(k => { x[ci(k + "Qty")] = o[k + "Qty"]; x[ci(k + "Amt")] = o[k + "Amt"]; x[ci(k + "Price")] = o[k + "Qty"] ? o[k + "Amt"] / o[k + "Qty"] : null; });
      elCols.forEach(c => { if (ci(c) >= 0) x[ci(c)] = o[c] ?? null; });
      const r = rtOf(o); rtCols.forEach(c => { if (ci(c) >= 0) x[ci(c)] = r[c]; });
      return x;
    };
    const rows = [], tot = {}, subs = new Set();
    asObjs(g).forEach(s => {
      it.rows.filter(x => x[ci("ItmsGrpCod")] === s.ItmsGrpCod).forEach(x => rows.push(x));
      const sr = row(s.ItmsGrpCod, s.GrpName, "小计", `${s.ItemCnt} 个物料`, s); subs.add(sr); rows.push(sr);
      K.forEach(k => { tot[k + "Qty"] = (tot[k + "Qty"] || 0) + s[k + "Qty"]; tot[k + "Amt"] = (tot[k + "Amt"] || 0) + s[k + "Amt"]; });
      elCols.forEach(c => { tot[c] = (tot[c] || 0) + (s[c] || 0); });
    });
    const tr = g.rows.length ? row("", "", "合计", `${asObjs(g).reduce((n, s) => n + s.ItemCnt, 0)} 个物料`, tot) : null;
    if (tr) rows.push(tr);
    last = {columns: it.columns, rows, truncated: it.truncated, src: [...(it.src || []), ...(g.src || [])]};
    const kind = x => x === tr ? "tot" : subs.has(x) ? "sub" : "";
    const pctFmt = v => v === null || v === undefined || v === "" ? "" : Number(v).toFixed(2) + "%";
    $("#sres").innerHTML = table(last, {rowCls: kind, noClick: kind, hide: showEl ? [] : [...elCols, ...rtCols], fmt: Object.fromEntries(rtCols.map(c => [c, pctFmt])), onRow: o => invItemLedger(id, o.ItemCode), empty:"没有物料"})
      + (it.truncated ? `<p class="hint">物料行被截断，但小计和合计是全部物料的数。</p>` : "");
    bindRows($("#sres"), last, o => invItemLedger(id, o.ItemCode));
    $("#sres").querySelectorAll("tr.sub, tr.tot").forEach(t => t.onclick = null);
  };
  $("#sgo").onclick = go; $("#sq").onkeydown = e => { if (e.key === "Enter") go(); };
  $("#scsv").onclick = () => last && csv(last, `收发存汇总_${id}`);
  $("#selem").onclick = () => {
    showEl = !showEl; try { localStorage.setItem("cc.invElem", showEl ? "Y" : "N"); } catch (e) {}
    elBtn(); if (lastRaw) show(...lastRaw);
  };
  const a = {runId:id, q:sqGet("收发存汇总")}, c1 = qCached("invSum", a), c2 = qCached("invGrp", a);
  if (c1 && c2) show(c1, c2); else $("#sres").innerHTML = SQ_HINT(false);
}
// 科目余额表 → 明细账：上面按来源 × 凭证代码汇总（点一行只看这个凭证代码），下面逐笔分录和余额；
// 点总账分录看整张凭证，点底稿分录看它由哪些业务明细汇总而来
async function tbLedger(id, a, tc, sub){
  const d = drawer(`${acctText(a.AcctCode)} 明细账${tc ? " · " + tc : ""}`, {replace:!!sub}); d.innerHTML = `<div class="empty">加载中…</div>`;
  try {
    const [sm, lr] = await Promise.all([q("tbAcctSum", {runId:id, acct:a.AcctCode}), q("tbLedger", {runId:id, acct:a.AcctCode, q:tc})]);
    d.innerHTML = `<div class="bar"><h3 style="margin:0">${esc(acctText(a.AcctCode))} 明细账${tc ? ` · 只看 <span class="mono">${esc(tc)}</span>` : ""}</h3><span class="sp"></span>`
      + (tc ? `<button class="btn" id="tbAll">显示全部</button>` : "") + `<button class="btn" id="tbLCsv">导出明细账</button></div>`
      + `<h3>按来源和凭证代码汇总（本期）</h3><div id="tbSum">` + table(sm, {onRow:true, empty:"本期没有分录"}) + `</div>`
      + `<h3>明细账</h3>` + note(`第一行是期初余额，接着是本期已过账分录、“本期合计 / 期末余额”，再是未清凭单和本次底稿、“未过账合计 / 含未过账期末余额”。余额按全部分录逐笔累计（只看某个凭证代码时，余额仍是这一行之后科目的实际余额）。底稿中已过账的凭证代码列出但不计入余额。点击总账分录看整张凭证，点击底稿分录看业务来源。`, "tbLedger")
      + (lr.truncated ? `<div class="msg info">分录超过 ${lr.rows.length} 行，只显示前 ${lr.rows.length} 行；点上面的汇总行按凭证代码查看。</div>` : "")
      + `<div id="tbLed">` + table(lr, {hide:["Kind", "LineId"], wrap:["Memo"], onRow:true, noClick: x => !(x[2] === "GL" || x[2] === "DRAFT"),
          rowCls: x => x[0] === 0 ? "sub" : (x[0] === 2 || x[0] === 5) ? "tot" : "", empty:"没有分录"}) + `</div>`;
    if (tc) $("#tbAll").onclick = () => tbLedger(id, a, "", true);
    $("#tbLCsv").onclick = () => csv(lr, `明细账_${a.AcctCode}_${tc || "全部"}_${id}`);
    bindRows($("#tbSum"), sm, s => { if (s.TransCode) tbLedger(id, a, s.TransCode, true); });
    bindRows($("#tbLed"), lr, async x => {
      const el = drawer(x.Src === "GL" ? `凭证 ${x.DocNo || x.TransId}` : `底稿 ${x.TransCode} 第 ${x.LineId} 行`); el.innerHTML = `<div class="empty">加载中…</div>`;
      try {
        if (x.Src === "GL") {
          const vr = await q("tbVoucher", {transId:String(x.TransId)});
          el.innerHTML = `<h3>凭证 ${esc(x.DocNo || "")}（交易号 TransId ${esc(x.TransId)}）${x.TransCode ? " · " + esc(codeText("TransCode", x.TransCode)) : ""}</h3>`
            + `<p class="hint">日期 ${esc(x.RefDate || "")}${x.ObjType ? " · 来源 " + esc(codeText("ObjType", x.ObjType)) : ""}${x.BaseRef ? " " + esc(x.BaseRef) : ""}</p>` + table(vr, {wrap:["Memo"]});
        } else if (x.Src === "DRAFT") {
          const sr = await q("jdtSrc", {runId:id, transCode:x.TransCode, lineNo:String(x.LineId)});
          el.innerHTML = `<h3>底稿 ${esc(codeText("TransCode", x.TransCode))} 第 ${esc(x.LineId)} 行的业务明细</h3>`
            + (sr.truncated ? `<div class="msg info">来源超过 ${sr.rows.length} 条，只列出前 ${sr.rows.length} 条。</div>` : "") + table(sr, {wrap:["Note"], empty:"没有来源明细"});
        } else el.innerHTML = "";
      } catch (e) { el.innerHTML = errBox(e); }
    });
  } catch (e) { d.innerHTML = errBox(e); }
}
async function invItemLedger(id, itemCode){
  const box = drawer(`收发存明细 ${itemCode}`);
  box.innerHTML = `<div class="bar"><h3 style="margin:0">收发存明细 ${esc(itemCode)}</h3><span class="sp"></span><button class="btn" id="lgCsv">导出 Excel</button></div><div id="odBody"><div class="empty">加载中…</div></div>`;
  try {
    const r = await q("invLedgerItem", {runId:id, itemCode});
    $("#odBody").innerHTML = table(r, {hide:["Seq", "ItemCode", "ItemName"], wrap:["PriceSrc"], rowCls: x => x[2] === 0 ? "sub" : x[2] === 2 ? "tot" : "", empty:"没有期初、收发或期末"});
    $("#lgCsv").onclick = () => csv(r, `收发存明细_${itemCode}_${id}`);
  } catch (e) { $("#odBody").innerHTML = errBox(e); }
}

// 物料明细：按交易类型的进销存 + 单据行
async function itemDetail(id, it){
  const fresh = $("#drawer").hidden, box = drawer(`物料 ${it.ItemCode}`);
  drLink({kind:"item", code:String(it.ItemCode)}, fresh);
  box.innerHTML = `<div id="odBody"><div class="empty">加载中…</div></div>`;
  try {
    const [x, f, l] = await Promise.all([q("explainItem", {runId:id, itemCode:it.ItemCode}), q("itemFlow", {runId:id, itemCode:it.ItemCode}), q("itemLines", {runId:id, itemCode:it.ItemCode})]);
    $("#odBody").innerHTML = `<div class="bar"><h3 style="margin:0">单价构成</h3><span class="sp"></span><button class="btn" id="itTrace">逐层追溯料工费 ›</button></div><p class="hint">加权单价只由期初和“计入加权单价的入库”决定；出库、其他调整按这个单价计价。四项要素分别算。</p>`
      + table(x, {hide:["Seq"], wrap:["Sec"], fmt:{Sec: (v, r) => r[0] === 3 || r[0] === 6 ? `<b>${esc(v)}</b>` : esc(v), Note: v => codeHtml("Cat", v) ?? codeHtml("PriceSrc", v) ?? esc(v)}, empty:"本次运行没有这个物料"})
      + `<h3>按交易类型汇总</h3>` + table(f, {empty:"没有收发"})
      + `<div class="bar" style="margin-top:12px"><h3 style="margin:0">单据行</h3><span class="sp"></span><button class="btn" id="ilCsv">导出 Excel</button></div><div id="il">${table(l, {wrap:["PriceSrc"], empty:"没有单据行"})}</div>`;
    $("#ilCsv").onclick = () => csv(l, `物料单据行_${it.ItemCode}_${id}`);
    $("#itTrace").onclick = () => goTrace({kind:"item", code:it.ItemCode});
  } catch (e) { $("#odBody").innerHTML = errBox(e); }
}
