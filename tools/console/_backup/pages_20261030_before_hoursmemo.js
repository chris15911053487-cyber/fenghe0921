// 成本执行台 · pages.js — 页面分发 renderTab()（各结果页）、明细列表 searchList()、订单明细 orderDetail()、校验明细
// index.html 按顺序加载 js/ 下的脚本，共用全局作用域；加载时立即执行的代码只能用到本文件和前面文件里的名字。
"use strict";
// 结果表（物料、订单、比对、凭证）只保留最近一次成功运行的明细
const latestNote = () => SEL.Status === "OK" ? "" : SEL.Status === "CHECKED" ? `<div class="msg info">这次是“只做计算前检查”，没有计算结果；看“校验”页。</div>` : `<div class="msg info">这次运行状态是“${esc(RUNST[SEL.Status] || SEL.Status)}”，没有写结果；物料、订单、在产品、费用、发出商品、暂估、比对和凭证只有成功的运行才有。</div>`;

// quiet：运行中每秒刷新“步骤”页时不先清空成“加载中”，避免闪烁
// 不依赖所选运行的页面；PAGES 是固定在页面里的操作区（发起计算、模拟场景、期初承接）
const NORUN = new Set(["run", "scen", "boot", "b1cfg", "manual", "jv"]);
const PAGES = {run:"#page-run", scen:"#page-scen", boot:"#page-boot"};
async function renderTab(quiet){
  document.querySelectorAll("#tabs button[data-t]").forEach(b => b.classList.toggle("on", b.dataset.t === TAB));
  $("#tabs").classList.remove("open");
  navGrpSync();
  Object.entries(PAGES).forEach(([k, sel]) => { $(sel).hidden = k !== TAB; });
  $("#runCard").hidden = !!PAGES[TAB];
  if (!quiet) closeDrawer("tab");
  syncUrl(true);
  const nb = document.querySelector(`#tabs button[data-t="${TAB}"]`);
  $("#pageTitle").textContent = nb ? nb.textContent : "";
  if (PAGES[TAB]) return;
  const pane = $("#pane");
  if (TAB === "b1cfg") { renderB1(pane); return; }
  if (TAB === "jv") { renderJv(pane); return; }
  if (TAB === "manual") { renderManual(pane); return; }
  if (!SEL) { pane.innerHTML = `<div class="empty">还没有运行记录，或还没选择运行：点顶部的运行按钮选择一次，或先“发起计算”。</div>`; return; }
  const id = String(SEL.RunId);
  if (!quiet) pane.innerHTML = `<div class="empty">加载中…</div>`;
  try {
    if (TAB === "steps") {
      // 执行步骤：选中哪次运行就显示哪次的，带每步开始 / 结束的时分秒；运行中的那次每秒刷新
      const live = SEL.Status === "RUNNING", run = SEL;
      const [prog, s, it] = await Promise.all([progressHtml(runAction(run), run, live), q("steps", {runId:id}, live), q("iters", {runId:id}, live)]);
      if (SEL !== run || TAB !== "steps") return;
      const open = pane.querySelector("details.sd") && pane.querySelector("details.sd").open;
      pane.innerHTML = `<div class="prog">${prog}</div>`
        + `<h3>迭代过程</h3>` + table(it, {empty:"没有迭代记录"})
        + `<details class="sd"${open ? " open" : ""}><summary class="hint" style="cursor:pointer;margin:12px 0 6px">步骤明细（全部小步骤、行数、说明）</summary>`
        + table(s, {fmt:{StepCode: v => `<b>${esc(STEP[v] || v)}</b> <span class="hint mono">${esc(v)}</span>`, Status: chip, StartTime: hms, EndTime: hms}, wrap:["Msg"], empty:"还没有步骤记录"}) + `</details>`;
    } else if (TAB === "flow") {
      await flowChart(SEL, pane, quiet);
    } else if (TAB === "checks") {
      const r = await q("checks", {runId:id});
      const o = asObjs(r), fail = o.filter(x => x.Result === "FAIL");
      pane.innerHTML = `<div class="summary"><span>共 <b>${o.length}</b> 项</span><span>阻断 <b class="bad">${fail.length}</b> 项</span><span>警告 <b>${o.filter(x => x.Result === "WARN").length}</b> 项（计算后校验没有警告，不通过即阻断）</span><span>点击一行查看明细</span></div>`
        + table(r, {hide:["Purpose","TroublePath"], wrap:["Msg"], fmt:{Result: chkChip, IsBlock: v => v === "Y" ? "阻断" : ""}, onRow:true});
      bindRows(pane, r, c => checkDrawer(id, c));
    } else if (TAB === "recon") {
      const st0 = qCached("reconStatus", {runId:id}), r0 = qCached("recon", {runId:id});
      if (!st0 || !r0) {
        pane.innerHTML = latestNote() + `<div class="bar"><button class="btn" id="reconGo">对账（按当前总账计算）</button></div><div class="empty">对账要按当前总账重算，点按钮开始。</div>`;
        $("#reconGo").onclick = async () => { pane.innerHTML = `<div class="empty">对账中…</div>`; try { await Promise.all([q("reconStatus", {runId:id}, true), q("recon", {runId:id}, true)]); renderTab(); } catch (e) { pane.innerHTML = errBox(e); } };
        return;
      }
      const st = st0, r = r0;
      const h = asObjs(st)[0] || {}, o = asObjs(r), d = o.filter(x => Math.abs(Number(x.CurDiff)) > 0.01), d0 = o.filter(x => Math.abs(Number(x.BegDiff)) > 0.01);
      // 应付暂估按供应商分行：先按科目合并成一行（KeyCode 显示供应商数），点开在抽屉里看各供应商，再点供应商看凭证构成（用户 2026-10-17）
      const C = r.columns, ci = c => C.indexOf(c), apKids = new Map(), rm = {columns:C, rows:[]};
      const NUMC = ["BegBiz","BegFin","BegDiff","CurBiz","CurFin","CurDiff","EndBiz","EndFin","EndDiff","OtherAmt","EndDiffGl","PendAmt","DupAmt","GlAmt","VchAmt","Diff1","Diff2"];
      const hasDiff = x => Math.abs(Number(x[ci("CurDiff")] || 0)) > 0.01 || Math.abs(Number(x[ci("EndDiff")] || 0)) > 0.01;
      for (const x of r.rows) {
        if (x[ci("Area")] !== "AP") { rm.rows.push(x); continue; }
        const a = x[ci("AcctCode")];
        if (!apKids.has(a)) { const m = C.map(c => NUMC.includes(c) ? 0 : null); m[ci("Area")] = "AP"; m[ci("AcctCode")] = a; apKids.set(a, {row:m, kids:[]}); rm.rows.push(m); }
        const g = apKids.get(a); g.kids.push(x);
        NUMC.forEach(c => { g.row[ci(c)] = Math.round((g.row[ci(c)] + Number(x[ci(c)] || 0)) * 100) / 100; });
      }
      const uniq = (kids, c) => [...new Set(kids.flatMap(x => String(x[ci(c)] || "").split("、").filter(Boolean)))].sort().join("、") || null;
      for (const [a, g] of apKids) {
        const m = g.row, nd = g.kids.filter(hasDiff).length;
        m[ci("KeyCode")] = `（${g.kids.length} 个供应商${nd ? `，${nd} 个有差异` : ""}）`;
        m[ci("PendCodes")] = uniq(g.kids, "PendCodes"); m[ci("DupCodes")] = uniq(g.kids, "DupCodes");
        m[ci("EndEqBeg")] = Math.abs(m[ci("EndDiff")] - m[ci("BegDiff")]) <= 0.01 ? "Y" : "N";
        g.nd = nd;
      }
      const isAp = x => x[ci("Area")] === "AP" && apKids.has(x[ci("AcctCode")]) && apKids.get(x[ci("AcctCode")]).row === x;
      const ropt = (t, top) => ({
        quick:{label:"只看有差异", test:x => hasDiff(x) || (top && isAp(x) && apKids.get(x[ci("AcctCode")]).nd > 0)},
        groups:{OtherAmt:["手工调整","金额（不参与对账）"], EndDiffGl:["手工调整","总账差额（含手工）"], EndEqBeg:["手工调整","扣除后 = 期初差额"],
          PendAmt:["底稿与过账","未过账底稿"], PendCodes:["底稿与过账","未过账底稿凭证"], DupAmt:["底稿与过账","已过账底稿（不再加）"], DupCodes:["底稿与过账","已过账底稿凭证"],
          GlAmt:["底稿与过账","总账已过账"], VchAmt:["底稿与过账","未清凭单"], Diff1:["参考","①全部底稿"], Diff2:["参考","②不加底稿"]},
        fmt:{BegDiff: v => diffCell(v), CurDiff: v => diffCell(v), EndDiff: v => diffCell(v), EndDiffGl: v => fmtNum(v), EndEqBeg: (v, x) => v === "Y" ? `<span style="color:var(--good)">✓ 相等</span>` : `<b style="color:var(--crit)">✗ 差 ${fmtNum(Number(x[ci("EndDiff")]) - Number(x[ci("BegDiff")]))}</b>`},
        wrap:["PendCodes","DupCodes"]});
      const reconSrc = async x => {
        const el = drawer(`${acctText(x.AcctCode)}${x.KeyCode ? " · " + x.KeyCode : ""} 的构成`); el.innerHTML = `<div class="empty">加载中…</div>`;
        try {
          const s2 = await q("reconSrc", {runId:id, acct:x.AcctCode, keyCode:x.KeyCode || ""});
          el.innerHTML = `<h3>${esc(acctText(x.AcctCode))}${x.KeyCode ? " · " + esc(x.KeyCode) : ""} 的构成</h3>${note(`期间：期初 = 本期以前的分录，本期 = 本期分录和底稿。GL 已过账分录、VCH 未清凭单、DRAFT 本次底稿；“计入对账”为 N 的不参与比较；底稿“已过账（不再加）”为 Y 的凭证代码本期已过账，不计入差额。`, "reconSrc")}`
            + table(s2, {empty:"没有分录"});
        } catch (e) { el.innerHTML = errBox(e); }
      };
      const warn = [];
      if (h.Basis === "PART") warn.push(`底稿的凭证只有一部分已在本期总账过账（${esc(h.PostedCodes || "在未清凭单中")}）：这部分不再加，其余底稿照加。`);
      if (h.VchCodes) warn.push(`未清凭单里有成本模块的凭证代码 ${esc(h.VchCodes)}（例如旧框架生成的 JZ01 / JZ03 草稿）：本期的按“已过账”处理，底稿同样的凭证不再加；以前账期留下的照常计入，确认是否应删除。`);
      pane.innerHTML = latestNote()
        + `<div class="summary"><span>本期凭证 <b>${h.Basis === "POSTED" ? "都已过账" : h.Basis === "PART" ? "部分过账" : "都未过账"}</b></span><span>本期有差异 <b>${d.length}</b> 行</span><span>期初有差异 <b>${d0.length}</b> 行</span><span>底稿凭证 <b>${esc(h.DraftCodes || "无")}</b></span><span>本期已过账 <b>${esc(h.PostedCodes || "无")}</b></span></div>`
        + warn.map(w => `<div class="msg info">${w}</div>`).join("")
        + `<div class="bar"><span class="hint">下面是上次对账的结果；过账或改了总账后点</span><button class="btn" id="reconGo">重新对账</button></div>`
        + note(`每个对账项分期初、本期、期末列示业务端、财务端和差额（期末 = 期初 + 本期）。业务期初取承接 / 上期结果（库存期初、订单累计投入 − 累计结转、截至上期末未开票的发出商品、上期末应付暂估）；财务期初 = 本期以前的总账 + 未清凭单；财务本期 = 本期总账分录 + 本期未清凭单 + 底稿中本期尚未过账的凭证。底稿中某个凭证代码本期已经在总账过账（或已在本期未清凭单里），这个代码就不再加，避免部分过账时重复计入。计算后校验默认按本期差额判断（参数 RECON_BLOCK_ON），期初差额是承接前就有的，只列示。手工调整（参数 RECON_COSTONLY_AREAS 中的对账项，本期凭证代码不在 COST_TRANSCODES 的分录，如发出商品 140601、生产在产品 500101）单独列在“手工调整 · 金额（不参与对账）”，“期末 · 财务”和“期末 · 差额”都不含它；“手工调整 · 总账差额（含手工）”= 两者相加，即按总账余额算的差额；“手工调整 · 扣除后 = 期初差额”核对期末差额扣除手工调整后是否等于期初差额（用户 2026-10-17）。口径①②两列参考默认隐藏，可在表格右上角“列”里打开。默认“只看有差异”（本期或期末差额不为 0），点按钮显示全部。每次打开都按当前总账重算。发出商品 140601 月末由 AR03 / AR04 把未开票部分全部计提、下月初 B1 自动冲销，所以业务端期初、期末都是 0，财务端含全部分录；点这一行按 ① 冲销上月计提 ② 发货 ③ 样品转出 ④ 发票 ⑤ 本月计提 列出构成，合计应为 0；POST-10 另核对 ① = 上期末未开票、⑤ = 本期末未开票。应付暂估按贷 − 借、按供应商，表中先按科目合并成一行，点开看各供应商，再点供应商看凭证构成。生产在产品（500101）本期只比较成本凭证，本期的手工凭证、单据自动凭证等其他分录允许存在，金额列在“手工调整”，不算差异；期初按科目余额全额比较。点击一行看期初、本期的金额由哪些凭证代码组成。`)
        + table(rm, Object.assign({freeze:2, hideDefault:["Diff1","Diff2"], onRow:true, empty:"没有对账结果（需要成功的计算运行）"}, ropt(rm, true)));
      $("#reconGo").onclick = async () => { $("#reconGo").disabled = true; $("#reconGo").textContent = "对账中…"; try { await Promise.all([q("reconStatus", {runId:id}, true), q("recon", {runId:id}, true)]); renderTab(); } catch (e) { pane.innerHTML = errBox(e); } };
      bindRows(pane, rm, x => {
        const g = x.Area === "AP" && apKids.get(x.AcctCode);
        if (!g || g.row[ci("KeyCode")] !== x.KeyCode) return reconSrc(x);
        const el = drawer(`${acctText(x.AcctCode)} 应付暂估 · 按供应商`), t = {columns:C, rows:g.kids};
        el.innerHTML = `<h3>${esc(acctText(x.AcctCode))} 应付暂估 · 按供应商</h3><p class="hint">${g.kids.length} 个供应商，合计等于上一层这一行。点供应商看期初、本期由哪些凭证代码组成。</p>`
          + table(t, Object.assign({freeze:2, hide:["Area"], hideDefault:["Diff1","Diff2"], onRow:true, empty:"没有供应商"}, ropt(t, false)));
        bindRows(el, t, reconSrc);
      });
    } else if (TAB === "tb") {
      const r = await q("tb", {fc:SEL.FcCode, runId:id});
      pane.innerHTML = `<div class="summary"><span>账期 <b>${esc(SEL.FcCode)}</b></span><span><b>${r.rows.length}</b> 个科目</span><span>点击科目看明细账</span><span class="sp"></span><button class="btn" id="tbCsv">导出 Excel</button></div>`
        + note(`成本相关科目：物料组存货科目（OGAR）、成本模块用到的全部科目（MTC_CA_C_ACCT，按前缀匹配，含 5101 制造费用），以及参数 TB_EXTRA_ACCTS 里加的科目或前缀；只列有余额或有发生额的科目。期初、本期、期末取总账已过账分录（OJDT）；“未过账”= 截至期末的未清凭单 + 本次运行的凭证底稿（底稿中本期已经过账或已在未清凭单里的凭证代码不再加，同财务对账）；含未过账期末 = 期末 + 未过账。每次打开都按当前总账重查。`)
        + `<div id="tbMain">` + table(r, {freeze:3, onRow:true, empty:"没有成本相关科目的余额或发生额",
          groups:{BegDr:["期初","借方"], BegCr:["期初","贷方"], CurDr:["本期","借方"], CurCr:["本期","贷方"], EndDr:["期末","借方"], EndCr:["期末","贷方"],
            PendDr:["未过账","借方"], PendCr:["未过账","贷方"], AllDr:["含未过账期末","借方"], AllCr:["含未过账期末","贷方"]}}) + `</div>`;
      $("#tbCsv").onclick = () => csv(r, `科目余额表_${SEL.FcCode}_${id}`);
      bindRows($("#tbMain"), r, a => tbLedger(id, a, ""));
    } else if (TAB === "qcp") {
      const sm = asObjs(await q("qcpNeedSum", {runId:id}))[0] || {};
      pane.innerHTML = `<div class="summary"><span>需要维护 <b>${sm.Cnt || 0}</b> 个物料</span><span>其中首次出现 <b>${sm.FirstCnt || 0}</b></span><span>没有可参考价格 <b>${sm.NoSugg || 0}</b></span>${b1DocBtn()}</div><div id="b1dMsg"></div>`
        + note(`计算前检查 PRE-23：这些物料本期有出库、其他入库、盘点、无原单退货等要按单价计价的变动，计算前却没有任何价格来源（没有期初结存金额、没有采购 / 完工 / 形态转换入库、没有维护价）。建议价取以前最近一个账期不为 0 的单价，都没有时取物料主数据最近采购价，只供参考。请在 B1“期初单价维护”里录入后重新“只做检查”，录好的物料不再出现在这里（已录入的可在“B1 维护数据 → 期初成本价”查看）。只做检查和正式计算都会生成这份清单。`) + `<div id="lst"></div>`;
      b1DocBind("qcp", id);
      searchList("#lst", "qcpNeed", {runId:id}, "期初价维护", {fmt:{FirstSeen: v => v === "Y" ? "<b>首次出现</b>" : "以前出现过"}, wrap:["NeedTrans", "Reason", "NeedDocs"],
        onRow: x => qcpDrawer(id, x),
        b1:{cols:["ItemCode", "ItemName", "SuggPrice"], tip:"复制 物料编码、物料名称、建议价 三列（不带表头），粘到 B1“期初单价维护”或 Excel；建议价只供参考，没有建议价的单价为空，要自己填"}}, "物料编码开头或物料组");
    } else if (TAB === "hrsneed") {
      const sm = asObjs(await q("hoursNeedSum", {runId:id}))[0] || {};
      pane.innerHTML = `<div class="summary"><span>需要维护 <b>${sm.Cnt || 0}</b> 个产品</span><span>本期录了 0 的 <b>${sm.ZeroCnt || 0}</b></span><span>没有参考工时 <b>${sm.NoRef || 0}</b></span>${b1DocBtn()}</div><div id="b1dMsg"></div>`
        + note(`计算前检查 PRE-14（阻断）按产品汇总：这些产品本期有入库、订单在费用池分摊范围内，但本期 B1“生产工时”（@MTC_COST_TIME，表头账期 ${esc(SEL.FcCode)}）里没有单位工时或为 0，不补就分不到制造费用和人工。“本期工时单”为空表示没录，0 表示录了 0。参考工时取以前最近一个账期工时单里不为 0 的单位工时，只供参考。请在 B1 工时单里录入后重新“只做检查”，录好的产品不再出现在这里（已录入的可在“B1 维护数据 → 工时”查看）。只做检查、检查阻断和正式计算都会生成这份清单；PRE-14 的逐张订单明细在“校验”页。`) + `<div id="lst"></div>`;
      b1DocBind("hours", id);
      searchList("#lst", "hoursNeed", {runId:id}, "工时维护", {
        b1:{cols:["ItemCode", "ItemName", "RefHours"], tip:"复制 物料编码、物料名称、参考工时 三列（不带表头），粘到 B1“生产工时”或 Excel；参考工时只供参考，没有参考的为空，要自己填"}}, "物料编码开头或物料组");
    } else if (TAB === "cmp") {
      const r = await q("cmpSummary", {runId:id});
      pane.innerHTML = latestNote() + `<p class="hint">新框架与旧框架同账期结果逐项比较；点击类别查看差异最大的对象。</p>` + table(r, {onRow:true, empty:"没有差异（或没有可比较的旧框架结果）"});
      bindRows(pane, r, c => searchList(drawer(`新旧比对 ${CMPKIND[c.Kind] || c.Kind}`), "cmpList", {runId:id, kind:c.Kind}, `新旧比对 ${c.Kind}`, {wrap:["Note","Reason"], fmt:ordKeyFmt(c.Kind)}));
    } else if (TAB === "items") {
      pane.innerHTML = latestNote() + `<div id="lst"></div>`;
      searchList("#lst", "items", {runId:id}, "物料单价", {onRow: it => itemDetail(id, it)}, "物料编码开头");
    } else if (TAB === "inv") {
      pane.innerHTML = latestNote() + note(`期初 + 入库 − 出库 = 期末，出库按正数显示。按物料组小计，最后是合计；只列有期初、收发或期末的物料。入库金额含数量为 0 的调整（发票差额、重估），所以入库单价 = 入库金额 ÷ 入库数量。“展开料工费”在期初、入库、出库、期末金额后面分列材料、制造费用、人工、委外加工费（四项合计 = 金额），最右边依次是期初、入库、出库、期末的料工费占比（材料 / 人工 / 制造 / 委外 ÷ 该项四项合计；物料行取结果表 MTC_CA_R_ITEM 的 Rt* 列，小计和合计按汇总金额算，四项合计为 0 时为空），再点收起；导出总是包含这些列。点击物料看收发存明细；明细中不列数量、金额都为 0 的发票 / 贷项行（13、14）。`) + `<div id="lst"></div>`;
      invSummary(id);
    } else if (TAB === "ledger") {
      pane.innerHTML = latestNote() + note(`每个物料：期初结存、按日期逐条的单据行（结存 = 期初 + 截至这一行的累计收发），最后是本期合计（结存 = 期末）。出库按正数显示；数量为 0 的调整行按交易类型方向计入入库或出库。只列本期有收发的物料。必须输入物料编码开头或物料组；看单个物料也可以在“收发存汇总”里点物料。`) + `<div id="lst"></div>`;
      searchList("#lst", "invLedger", {runId:id}, "收发存明细", {require:true, hide:["Seq"], wrap:["PriceSrc"], rowCls: x => x[2] === 0 ? "sub" : x[2] === 2 ? "tot" : "", empty:"没有收发"}, "物料编码开头或物料组");
    } else if (TAB === "orders") {
      pane.innerHTML = latestNote() + `<p class="hint">点击一张订单查看成本构成、材料结转、费用分摊、委外加工费来源和单据行。</p><div id="lst"></div>`;
      searchList("#lst", "orders", {runId:id}, "订单成本", {fmt:{WorType: wt}, onRow: o => orderDetail(id, o)}, "物料编码开头或订单号");
    } else if (TAB === "wip") {
      const r = await q("wipSummary", {runId:id});
      pane.innerHTML = latestNote() + `<p class="hint">期末在产品和本期关单差异（四项要素合计 = 订单 × 材料汇总）。点击订单查看明细。</p>`
        + table(r, {fmt:{WorType: wt}, empty:"没有在产品"}) + `<div id="lst"></div>`;
      searchList("#lst", "wipList", {runId:id}, "在产品明细", {fmt:{WorType: wt}, onRow: o => orderDetail(id, o)}, "物料编码开头或订单号");
    } else if (TAB === "exp") {
      const r = await q("expSum", {runId:id});
      const tot = asObjs(r).reduce((n, x) => n + Number(x.Amount || 0), 0);
      pane.innerHTML = latestNote() + note(`进入费用池的全部金额：凭证（按成本中心归池，没有配置的进默认池）、库存重估、委外重估、公摊材料（记 5101 的其他出入库、盘点）、关单差异。按池 × 要素 × 来源 × 凭证代码（公摊材料为交易类型）× 科目汇总，合计等于“费用分摊”页的池合计。点击一行看明细。`)
        + `<div class="summary"><span>归集合计 <b class="mono">${fmtNum(tot)}</b></span><span>${r.rows.length} 行</span><span class="sp"></span><button class="btn" id="expCsv">导出汇总</button></div>`
        + table(r, {onRow:true, empty:"没有费用归集数据"});
      $("#expCsv").onclick = () => csv(r, `费用归集_${id}`);
      bindRows(pane, r, async c => {
        const d = drawer(`${c.PoolCode || ""} ${ELEM[c.Elem] || c.Elem} · ${SRCALL[c.Src] || c.Src}${c.SrcTrans ? " · " + c.SrcTrans : ""}`); d.innerHTML = `<div class="empty">加载中…</div>`;
        try {
          const dr = await q("expDtl", {runId:id, pool0:c.PoolCode || "", elem:c.Elem, kind:c.Src, keyCode:c.SrcTrans || "", text:c.AcctCode || ""});
          d.innerHTML = `<div class="bar"><h3 style="margin:0">${esc(c.PoolCode || "")} ${esc(c.PoolName || "")} · ${esc(ELEM[c.Elem] || c.Elem)} · ${esc(SRCALL[c.Src] || c.Src)} · ${esc(c.SrcTrans || "")} · ${esc(acctText(c.AcctCode))}</h3><span class="sp"></span><button class="btn" id="dtlCsv">导出 Excel</button></div>`
            + `<div id="ed">${table(dr, {wrap:["Note"], onRow: c.Src === "CLOSEDIF", empty:"没有明细"})}</div>`;
          $("#dtlCsv").onclick = () => csv(dr, `费用归集明细_${c.PoolCode}_${c.Src}_${c.SrcTrans || ""}_${id}`);
          if (c.Src === "CLOSEDIF") bindRows($("#ed"), dr, o => orderDetail(id, {OrderType:o.SrcObj, OrderEntry:o.SrcDoc, ItemCode:o.ItemCode}));
        } catch (e) { d.innerHTML = errBox(e); }
      });
    } else if (TAB === "pool") {
      const r = await q("poolSummary", {runId:id});
      pane.innerHTML = latestNote() + `<p class="hint">费用池按来源归集、按“单位工时 × 本期入库数”分摊给订单；未分摊不为 0 的要先查（没有工时或没有可分摊订单）。点击一行查看分摊到的订单。</p>`
        + table(r, {onRow:true, empty:"没有费用池数据"});
      bindRows(pane, r, async c => {
        const d = drawer(`${c.PoolCode} ${c.PoolName || ""} · ${ELEM[c.Elem] || c.Elem}`); d.innerHTML = `<div class="empty">加载中…</div>`;
        try {
          const ar = await q("poolAlloc", {runId:id, poolCode:c.PoolCode, elem:c.Elem});
          d.innerHTML = `<div class="bar"><h3 style="margin:0">${esc(c.PoolCode)} ${esc(c.PoolName || "")} · ${esc(ELEM[c.Elem] || c.Elem)}</h3><span class="sp"></span><button class="btn" id="dtlCsv">导出 Excel</button></div>`
            + `<div id="pa">${table(ar, {fmt:{WorType: wt}, onRow:true, empty:"没有分摊到订单"})}</div>`;
          $("#dtlCsv").onclick = () => csv(ar, `费用分摊_${c.PoolCode}_${c.Elem}_${id}`);
          bindRows($("#pa"), ar, o => orderDetail(id, o));
        } catch (e) { d.innerHTML = errBox(e); }
      });
    } else if (TAB === "hours") {
      // 工时分摊（用户 2026-10-23）：本期有完工的物料 × 费用池，工时 = 单位工时 × 本期入库数，没分到的也列出原因
      const r = await q("hoursByItem", {runId:id});
      const o = asObjs(r), sum = k => o.reduce((t, x) => t + Number(x[k] || 0), 0), bad = o.filter(x => !x.PoolCode).length;
      pane.innerHTML = latestNote() + note(`本期有完工入库的物料，按费用池列出分摊到的工时和金额：<b>工时 = 单位工时 × 本期入库数</b>，费用池的制造费用、人工按各订单工时占池内全部工时的比例分摊（P43），尾差挤在工时最大的订单。
        “分摊情况”不是“已分摊”的行排在最前面：委外工单本来就不分摊；没有单位工时、单位工时为 0、不在费用池范围的要先查（单位工时在 B1 的工时表维护，见“B1 维护数据 → 工时”）。返工单按产品的正常单位工时。点击一行看这个物料的各张订单。`, "hours")
        + `<div class="summary"><span>工时合计 <b class="mono">${fmtNum(sum("TotHours"))}</b></span><span>分摊制造费用 <b class="mono">${fmtNum(sum("AllocMfg"))}</b></span><span>分摊人工 <b class="mono">${fmtNum(sum("AllocLab"))}</b></span>`
        + `<span>${o.length} 行${bad ? `，<b style="color:var(--crit)">${bad} 行未分摊</b>` : ""}</span><span class="sp"></span><button class="btn" id="hrCsv">导出 Excel</button></div>`
        + table(r, {onRow:true, freeze:2, fmt:{AllocState: hrState}, empty:"本期没有完工入库的订单"});
      $("#hrCsv").onclick = () => csv(r, `工时分摊_${id}`);
      bindRows(pane, r, async c => {
        const d = drawer(`工时分摊 · ${c.ItemCode} ${c.ItemName || ""}`); d.innerHTML = `<div class="empty">加载中…</div>`;
        try {
          const ar = await q("hoursItemOrders", {runId:id, itemCode:c.ItemCode});
          d.innerHTML = `<div class="bar"><h3 style="margin:0">${esc(c.ItemCode)} ${esc(c.ItemName || "")} · 各订单工时</h3><span class="sp"></span><button class="btn" id="itTr">逐层追溯料工费 ›</button><button class="btn" id="dtlCsv">导出 Excel</button></div>`
            + `<div id="ha">${table(ar, {fmt:{WorType: wt, AllocState: hrState}, onRow:true, empty:"没有订单"})}</div>`;
          $("#dtlCsv").onclick = () => csv(ar, `工时分摊_${c.ItemCode}_${id}`);
          $("#itTr").onclick = () => goTrace({kind:"item", code:c.ItemCode});
          bindRows($("#ha"), ar, x => orderDetail(id, x));
        } catch (e) { d.innerHTML = errBox(e); }
      });
    } else if (TAB === "goods") {
      const r = await q("goodsOutSum", {runId:id});
      pane.innerHTML = latestNote() + `<p class="hint">截至期末已交货未开票（口径同 CO6103）；成本取新框架结果，“缺成本”不为 0 的行要先查。</p>`
        + table(r, {fmt:{IsSample: v => v === "Y" ? "样品" : ""}, empty:"没有发出商品"}) + `<div id="lst"></div>`;
      searchList("#lst", "goodsOut", {runId:id}, "发出商品明细", {fmt:{IsSample: v => v === "Y" ? "样品" : ""}}, "客户或物料编码开头");
    } else if (TAB === "ap") {
      const r = await q("apAccrSum", {runId:id});
      pane.innerHTML = latestNote() + `<p class="hint">截至期末已收货未开票（口径同 CO6102），按暂估单价计。</p>`
        + table(r, {empty:"没有应付暂估"}) + `<div id="lst"></div>`;
      searchList("#lst", "apAccr", {runId:id}, "应付暂估明细", {}, "供应商或物料编码开头");
    } else if (TAB === "jdt") {
      const r = await q("jdtSummary", {runId:id});
      pane.innerHTML = latestNote() + `<p class="hint">凭证只生成到 MTC_CA_R_JDT，供核对；过账仍在库外完成。借贷差额不为 0 或缺科目的行要先查。</p>`
        + table(r, {onRow:true, empty:"没有凭证行"});
      bindRows(pane, r, async c => {
        const d = drawer(`${c.TransCode} ${c.TransName || ""}`); d.innerHTML = `<div class="empty">加载中…</div>`;
        try {
          const lr = await q("jdtLines", {runId:id, transCode:c.TransCode});
          d.innerHTML = `<div class="bar"><h3 style="margin:0">${esc(c.TransCode)} ${esc(c.TransName || "")}</h3><span class="sp"></span><button class="btn" id="dtlCsv">导出 Excel</button></div>`
            + `<p class="hint">点击一行分录，查看它由哪些业务明细汇总而来。</p>` + table(lr, {onRow:true});
          $("#dtlCsv").onclick = () => csv(lr, `凭证_${c.TransCode}_${id}`);
          bindRows(d, lr, async x => {
            const el = drawer(`第 ${x.LineNo} 行 ${acctText(x.AcctCode)}`); el.innerHTML = `<div class="empty">加载中…</div>`;
            try {
              const [sm, sr] = await Promise.all([q("jdtSrcSum", {runId:id, transCode:c.TransCode, lineNo:String(x.LineNo)}), q("jdtSrc", {runId:id, transCode:c.TransCode, lineNo:String(x.LineNo)})]);
              const so = asObjs(sm), n = so.reduce((a, y) => a + Number(y.Lines || 0), 0),
                    dr = so.reduce((a, y) => a + Number(y.Debit || 0), 0), cr = so.reduce((a, y) => a + Number(y.Credit || 0), 0);
              const ok = Math.abs(dr - Number(x.Debit || 0)) < 0.005 && Math.abs(cr - Number(x.Credit || 0)) < 0.005;
              el.innerHTML = `<div class="bar"><h3 style="margin:0">第 ${esc(x.LineNo)} 行 ${esc(acctText(x.AcctCode))} 的业务明细</h3><span class="sp"></span><button class="btn" id="jsrcCsv">导出明细</button></div>`
                + `<p class="hint">共 ${n} 条来源，借 ${fmtNum(dr)}、贷 ${fmtNum(cr)}，${ok ? "与分录行一致" : "<b>与分录行不一致，请反馈</b>"}。来源：单据行 = 本次计算的库存变动；订单 = 按订单汇总（分摊、关单差异、加工费结转）；B1 单据行 = 交货、发票、收货等；总账分录 = 冲回的系统凭证或 PP04 汇总的科目；重估单 = @MTC_OMRV。</p>`
                + `<h3>按来源和交易类型汇总</h3>` + table(sm, {empty:"没有来源"})
                + `<h3>明细</h3>` + (sr.truncated ? `<div class="msg info">来源超过 ${sr.rows.length} 条，下面只列出前 ${sr.rows.length} 条（导出也只有这些）；上面的汇总是全部来源。</div>` : "")
                + table(sr, {wrap:["Note"], empty:"没有来源明细"});
              $("#jsrcCsv").onclick = () => csv(sr, `凭证来源_${c.TransCode}_${x.LineNo}_${id}`);
            } catch (e) { el.innerHTML = errBox(e); }
          });
        } catch (e) { d.innerHTML = errBox(e); }
      });
    } else if (TAB === "trace") {
      renderTrace(pane, id);
    } else if (TAB === "kpi") {
      renderKpi(pane, id);
    } else if (TAB === "report") {
      renderReport(pane);
    } else if (TAB === "ai") {
      renderAI(pane);
    }
    srcSqlBar(pane, SRCSQL[TAB], SEL.FcCode, id);   // 有取数 SQL 的页面在顶部放按钮
  } catch (e) { pane.innerHTML = errBox(e); }
}
// 明细列表打开时不自动查询：有缓存（这次运行查过同样条件）就直接显示，否则等点“查询”。opt.require = 必须输入条件
const SQ_HINT = req => `<div class="empty">${req ? "输入条件后点“查询”。" : "输入条件后点“查询”；不输入条件直接点“查询”= 查全部，数据多时较慢。"}</div>`;
async function searchList(sel, action, args, title, opt = {}, ph = "编码开头"){
  const box = typeof sel === "string" ? $(sel) : sel, $b = x => box.querySelector(x);
  box.innerHTML = `<div class="bar"><h3 style="margin:0">${esc(title)}</h3><span class="sp"></span><input type="text" class="sq" placeholder="${esc(ph)}" maxlength="50" value="${esc(sqGet(title))}"><button class="btn sgo">查询</button>${opt.b1 ? `<button class="btn sb1" title="${esc(opt.b1.tip)}">复制 B1 录入格式</button>` : ""}<button class="btn scsv">导出 Excel</button></div><div class="sres"></div>`;
  let last = null;
  const go = async () => {
    const v = $b(".sq").value.trim();
    if (!/^[A-Za-z0-9_.\-\/]{0,50}$/.test(v)) { $b(".sres").innerHTML = errBox("只能输入字母、数字、下划线、点、横线和斜线"); return; }
    if (opt.require && !v) { $b(".sres").innerHTML = errBox("请先输入查询条件"); return; }
    sqSet(title, v);
    $b(".sres").innerHTML = `<div class="empty">加载中…</div>`;
    try { show(await q(action, {...args, q:v})); } catch (e) { $b(".sres").innerHTML = errBox(e); }
  };
  const show = r => {
    last = r; $b(".sres").innerHTML = table(last, opt);
    if (opt.onRow) bindRows($b(".sres"), last, opt.onRow);
  };
  $b(".sgo").onclick = go; $b(".sq").onkeydown = e => { if (e.key === "Enter") go(); };
  $b(".scsv").onclick = () => last && csv(last, `${title}_${args.runId}`);
  if (opt.b1) $b(".sb1").onclick = () => last && b1Copy(last, opt.b1);
  const c = qCached(action, {...args, q:sqGet(title)});
  if (c) show(c); else $b(".sres").innerHTML = SQ_HINT(opt.require);
}

// 复制成 B1 录入用的几列（不带表头、数字不带千分位），按 b1.cols 的顺序；取表格当前筛选后的行，有选中的行时只取选中的行
async function b1Copy(r, b1){
  const st = [...TBL.values()].find(x => x.r === r), all = st ? tblRows(st) : r.rows.map((x, i) => i);
  const sel = st ? all.filter(i => st.pick.has(i)) : [], ix = b1.cols.map(c => r.columns.indexOf(c));
  const rows = (sel.length ? sel : all).map(i => r.rows[i]);
  const tsv = rows.map(x => ix.map(i => i < 0 || x[i] === null || x[i] === undefined ? "" : String(x[i]).replace(/[\t\r\n]+/g, " ")).join("\t")).join("\r\n");
  let ok = false;
  try { if (navigator.clipboard) { await navigator.clipboard.writeText(tsv); ok = true; } } catch (e) {}
  if (!ok) ok = copyFallback(`<pre>${esc(tsv)}</pre>`);
  toast(ok ? `已复制 ${rows.length} 行（${b1.cols.map(c => LABEL[c] || c).join("、")}，不带表头），可以粘贴到 B1 或 Excel` : "复制失败：浏览器不允许访问剪贴板，请用“导出 Excel”");
}

// 生成 B1 维护单据（期初单价 / 生产工时，用户 2026-10-29）：只在服务器模式、操作权限 O 及以上；先预览，再输入 B1 密码执行
const b1DocBtn = () => `<span class="sp"></span>` + (INFO && INFO.login && canDo("O") ? `<button class="btn primary" id="b1dGo">生成 B1 单据</button>`
  : `<span class="hint">${INFO && INFO.login ? "生成 B1 单据需要“操作”权限" : "生成 B1 单据只在服务器模式（用 B1 账号登录）下可用"}</span>`);
function b1DocBind(kind, id){
  const b = $("#b1dGo"); if (!b) return;
  b.onclick = async () => {
    const box = $("#b1dMsg"); box.innerHTML = `<div class="msg info">正在按 B1 当前数据计算要写哪些行…</div>`;
    let pv;
    try { pv = await api("/api/b1doc", {kind, runId:String(id), preview:true}); } catch (e) { box.innerHTML = errBox(e); return; }
    box.innerHTML = b1DocSkips(pv);
    if (!pv.addCnt && !pv.updCnt) { box.innerHTML = `<div class="msg ok">没有要写进 B1 的行：清单里的物料本期都已经维护过，重新“只做检查”即可。</div>` + b1DocSkips(pv); return; }
    const ok = await confirmDlg(`确认生成 B1“${pv.title}”`, [["账套", INFO.schema], ["账期", pv.fc], ["运行", "#" + id],
      ["写到哪张单据", pv.target ? `追加到本期单据 ${pv.target}` : "本期还没有单据，新建一张"],
      ["新增行", `${pv.addCnt} 行${pv.addZero ? `（其中 ${pv.addZero} 行没有参考值，填 0，要在 B1 里补）` : ""}`],
      ["改原来为 0 的行", pv.updCnt ? `${pv.updCnt} 行（单据 ${pv.updDocs.join("、")}）` : "无"],
      ["跳过", `${pv.skips.length} 个物料（见页面上的清单）`],
      ["说明", "用你的 B1 账号经 Service Layer 写入；值只是参考，请在 B1 里核对后再重新“只做检查”"]], false, true);
    if (ok === null) return;
    const pwd = DLG_PWD; DLG_PWD = "";
    box.innerHTML = `<div class="msg info">正在写入 B1…</div>`;
    try {
      const r = await api("/api/b1doc", {kind, runId:String(id), password:pwd});
      const bad = (r.done || []).filter(d => !d.ok);
      box.innerHTML = `<div class="msg ${bad.length ? "err" : "ok"}">${bad.length ? "有单据没写成功：" + esc(bad.map(d => d.msg).join("；")) : `已写入 B1“${esc(r.title)}”。请在 B1 里核对数值，然后重新“只做检查”。`}</div>`
        + ((r.done || []).length ? table({columns:["Action", "DocNum", "DocEntry", "Lines", "ok", "msg"], rows:r.done.map(d => [d.Action, d.DocNum ?? "", d.DocEntry ?? "", d.Lines, d.ok ? "成功" : "失败", d.msg || ""])},
            {wrap:["msg"], sum:false}) : "") + b1DocSkips(r);
    } catch (e) { box.innerHTML = errBox(e); }
  };
}
const b1DocSkips = r => (r.skips || []).length ? `<h3>跳过的物料（${r.skips.length}）</h3>` + table({columns:["ItemCode", "Reason"], rows:r.skips.map(x => [x.ItemCode, x.Reason])}, {wrap:["Reason"], sum:false}) : "";

const hrState = v => v === "已分摊" ? esc(v) : `<b style="color:var(--crit)">${esc(v)}</b>`;
const wt = v => esc(v) + (WORTYPE[v] ? ` <span class="hint">${WORTYPE[v]}</span>` : "");
const kv = (o, keys, numKeys = []) => `<div class="kv">${keys.filter(k => o[k] !== null && o[k] !== undefined && o[k] !== "").map(k =>
  `<div><span>${esc(LABEL[k] || k)}</span><b class="${numKeys.includes(k) ? "mono" : ""}">${numKeys.includes(k) ? fmtNum(o[k]) : esc(o[k])}</b></div>`).join("")}</div>`;

// 订单明细：成本构成 / 概览 / 材料结转 / 费用分摊 / 委外加工费 / 单据行
async function orderDetail(id, o){
  const fresh = $("#drawer").hidden, box = drawer(`订单 ${o.OrderType}-${o.OrderNum || o.OrderEntry}${o.ItemCode ? " · " + o.ItemCode : ""}`);
  drLink({kind:"order", type:String(o.OrderType), entry:String(o.OrderEntry)}, fresh);
  const key = {runId:id, orderType:String(o.OrderType), orderEntry:String(o.OrderEntry)};
  const name = `${o.OrderType}-${o.OrderEntry}`;
  box.innerHTML = `<div><div class="bar"><h3 style="margin:0">订单 ${esc(o.OrderType)} · ${esc(o.OrderNum || o.OrderEntry)} · ${esc(o.ItemCode || "")}</h3><span class="sp"></span><button class="btn" id="odTrace">逐层追溯料工费 ›</button><button class="btn" id="odCsv">导出当前页</button></div>
    <nav class="subtabs" id="odTabs"><button data-t="explain" class="on">成本构成</button><button data-t="head">概览</button><button data-t="mat">材料结转</button><button data-t="alloc">费用分摊</button><button data-t="subfee">委外加工费</button><button data-t="lines">单据行</button></nav><div id="odBody"></div></div>`;
  let cur = null;
  const show = async t => {
    document.querySelectorAll("#odTabs button").forEach(b => b.classList.toggle("on", b.dataset.t === t));
    const b = $("#odBody"); b.innerHTML = `<div class="empty">加载中…</div>`; cur = null;
    try {
      if (t === "explain") {
        const r = await q("orderExplain", key); cur = r;
        b.innerHTML = `<p class="hint">期初在产品 + 本期领料 − 本期结转 − 关单差异 = 期末在产品；本期完工成本 = 本期结转 + 分摊的制造费用、人工（委外加工费随入库全部结转）。</p>`
          + table(r, {hide:["Seq"], wrap:["Sec"], fmt:{Sec: (v, x) => x[0] === 6 || x[0] === 9 ? `<b>${esc(v)}</b>` : esc(v)}, empty:"没有这张订单的结果"});
      } else if (t === "head") {
        const r = await q("orderHead", key); cur = r;
        const h = asObjs(r)[0];
        if (!h) { b.innerHTML = `<div class="empty">没有这张订单的结果</div>`; return; }
        h.WorType = h.WorType + (WORTYPE[h.WorType] ? " " + WORTYPE[h.WorType] : "");
        h.Ratio = h.Ratio === null ? null : (Number(h.Ratio) * 100).toFixed(2) + "%";
        b.innerHTML = `<h3>订单</h3>` + kv(h, ["OrderType","OrderEntry","OrderNum","WorType","ItemCode","ItemName","iLevel","PostDate","B1Status","CloseDate","StatusAtEnd","ClosedInFc","InScope","CardCode"])
          + `<h3>数量</h3>` + kv(h, ["PlannedQty","PrevRecvQty","RecvQty","Ratio"], ["PlannedQty","PrevRecvQty","RecvQty"])
          + `<h3>本期完工成本</h3>` + kv(h, ["CostMat","CostMfg","CostLab","CostSub","CostAmt","UnitCost"], ["CostMat","CostMfg","CostLab","CostSub","CostAmt","UnitCost"])
          + `<h3>费用、在产品与关单</h3>` + kv(h, ["AllocMfg","AllocLab","WipAmt","CloseDifAmt"], ["AllocMfg","AllocLab","WipAmt","CloseDifAmt"]);
      } else if (t === "mat") {
        const r = await q("orderMat", key); cur = r;
        b.innerHTML = `<p class="hint">每种材料：期初累计 + 本期领料 − 本期结转 − 关单差异 = 期末在产品；#SUBFEE 是委外加工费。</p>` + table(r, {empty:"没有领料"});
      } else if (t === "alloc") {
        const r = await q("orderAlloc", key); cur = r;
        b.innerHTML = table(r, {empty:"没有分摊费用（委外工单不分摊制造费用和人工）"});
      } else if (t === "subfee") {
        const [s, r] = await Promise.all([q("orderSubFeeSum", key), q("orderSubFee", key)]); cur = r;
        const h = asObjs(s)[0], src = asObjs(r).reduce((a, x) => a + Number(x.Amount || 0), 0);
        const gap = h ? Number(h.FeeIss || 0) - src : 0;
        b.innerHTML = `<h3>构成（规则 WW-01）</h3><p class="hint">期初未结转 + 本期发生 − 本期结转 − 关单差异 = 期末未结转。本期有完工入库时累计未结转的加工费全部结转，没有入库时留在订单上，关单时转关单差异。</p>`
          + (h ? kv(h, ["FeeOpen","FeeIss","FeeCar","FeeCls","FeeWip"], ["FeeOpen","FeeIss","FeeCar","FeeCls","FeeWip"]) : `<div class="empty">这张订单没有委外加工费</div>`)
          + `<h3>本期来源</h3><p class="hint">加工费采购收货（PDN）、加工费退货（RPD，金额为负）通过生产收货找到订单；ProWW 是库存重估单上指定了订单的行。加工费发票与暂估的差额不进订单，计入产品的 I11；找不到订单的加工费见计算前检查 PRE-12。</p>`
          + (Math.abs(gap) > 0.005 ? errBox(`来源合计 ${fmtNum(src)} 与本期发生 ${fmtNum(h.FeeIss)} 差 ${fmtNum(gap)}（可能是模拟场景覆盖）`) : "")
          + table(r, {wrap:["MatchNote"], empty:"本期没有加工费来源"});
      } else {
        const r = await q("orderLines", key); cur = r;
        b.innerHTML = `<p class="hint">本期这张订单的领料、退料和完工入库行，含价格来源和规则。</p>` + table(r, {wrap:["PriceSrc"], empty:"本期没有单据行"});
      }
    } catch (e) { b.innerHTML = errBox(e); }
  };
  document.querySelectorAll("#odTabs button").forEach(b => b.onclick = () => show(b.dataset.t));
  $("#odCsv").onclick = () => cur && csv(cur, `订单_${name}_${$("#odTabs button.on").textContent}_${id}`);
  $("#odTrace").onclick = () => goTrace({kind:"order", type:String(o.OrderType), entry:String(o.OrderEntry)});
  show("explain");
}

// 校验明细抽屉（“校验”页和“计算过程”页共用）
// 期初价维护：一个物料为什么要维护、哪些单据行要按单价计价（MTC_CA_R_QCP_LINE，用户 2026-10-30）
async function qcpDrawer(id, x){
  const d = drawer(`${x.ItemCode} ${x.ItemName || ""}`); d.innerHTML = `<div class="empty">加载中…</div>`;
  try {
    const r = await q("qcpLines", {runId:id, itemCode:x.ItemCode});
    const sg = x.SuggPrice === null || x.SuggPrice === undefined ? "没有可参考的价格，要自己填"
      : `${fmtNum(x.SuggPrice)}（${esc((x.SuggFc ? x.SuggFc + " " : "") + (QCPSRC[x.SuggSrc] || x.SuggSrc || ""))}）`;
    d.innerHTML = `<h3>为什么要维护</h3><p>${esc(x.Reason || "（这次运行在补丁之前，没有记录原因；重新“只做检查”一次）")}</p><p class="hint">建议价：${sg}</p>`
      + `<h3>来源单据（这些行要按单价计价）</h3>` + table(r, {empty:"没有记录（补丁之前的运行没有来源单据，重新“只做检查”一次）"});
  } catch (e) { d.innerHTML = errBox(e); }
}
async function checkDrawer(id, c){
  const d = drawer(`${c.CheckId} ${c.Title}`); d.innerHTML = `<div class="empty">加载中…</div>`;
  try {
    const dr = await q("checkDtl", {runId:id, checkId:c.CheckId});
    d.innerHTML = `<h3>${esc(c.CheckId)} ${esc(c.Title)}</h3><p class="hint">${esc(c.Purpose)}${c.TroublePath ? "<br>排查：" + esc(c.TroublePath) : ""}</p>`
      + `<div class="bar"><span class="sp"></span><button class="btn" id="dtlSql">查看 SQL</button><button class="btn" id="dtlCsv">导出 Excel</button></div>`
      + `<div id="dtlSqlBox"></div>` + table(dr, {wrap:["Info"], fmt:{KeyCode: v => esc(keyText(v)), Info: v => hlInfo(v)}, empty:"没有明细"});
    d.querySelector("#dtlCsv").onclick = () => csv(dr, `校验明细_${c.CheckId}_${id}`);
    d.querySelector("#dtlSql").onclick = () => showCheckSql(c.CheckId, d.querySelector("#dtlSqlBox"));
  } catch (e) { d.innerHTML = errBox(e); }
}
