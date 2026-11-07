// 历史委外差异转出（用户 2026-11-04，设计稿 8.9）：承接前已关闭、在产品留在 140801 的委外订单，按整张订单选账期转出。
// 选好后重新计算：金额进费用池，P70 生成 JZ05（借 510109 / P016，贷 140801）。
const WWSTATE = {TODO:"待转", PLAN:"本期转出", DONE:"已转出", OTHER:"其他账期计划", MANUAL:"已手工转出"};
const whR = v => Math.round(Number(v || 0) * 100) / 100;
async function wwHistPage(pane, id){
  const fc = SEL.FcCode, can = canDo("A");
  const r = await q("wwHistList", {fc, runId:id}, true), pl = asObjs(await q("wwHistPool", {fc, runId:id}, true))[0] || {};
  // 差异预览：只有成功的运行才有业务端结果可比；财务对账函数较慢，失败时页面照常用
  let gap = null;
  if (SEL.Status === "OK") { try { gap = asObjs(await q("wwHistGap", {runId:id}, true))[0] || null; } catch (e) {} }
  const c0 = r.columns.slice(), ix = c => r.columns.indexOf(c);
  r.columns = ["Pick", ...c0];
  r.rows = r.rows.map(x => ["", ...x]);
  const iP = ix("Pick"), iS = ix("State"), iA = ix("Amount"), iT = ix("OrderType"), iE = ix("OrderEntry"), iR = ix("InRun");
  const key = x => x[iT] + "-" + x[iE], byKey = new Map(r.rows.map(x => [key(x), x]));
  const of = s => r.rows.filter(x => x[iS] === s), sum = a => whR(a.reduce((s, x) => s + Number(x[iA] || 0), 0));
  const todo = of("TODO"), plan = of("PLAN"), done = of("DONE"), manual = of("MANUAL");
  const stale = r.rows.filter(x => (x[iS] === "PLAN") !== (x[iR] === "Y") && x[iS] !== "DONE");
  pane.innerHTML = `<div class="summary"><span>待转 <b>${todo.length}</b> 张，净额 <b>${fmtNum(sum(todo))}</b></span><span>${esc(fc)} 转出 <b>${plan.length}</b> 张，净额 <b>${fmtNum(sum(plan))}</b></span>`
    + `<span>已转出 <b>${done.length}</b> 张，净额 <b>${fmtNum(sum(done))}</b></span><span>已手工转出 <b>${manual.length}</b> 张，净额 <b>${fmtNum(sum(manual))}</b></span><span>已选 <b id="whCnt">0</b> 张，净额 <b id="whSum">0.00</b></span><span class="sp"></span>`
    + (can ? `<button class="btn" id="whLoad">刷新清单</button><button class="btn primary" id="whAdd">转入 ${esc(fc)}</button><button class="btn" id="whDel">取消转出</button><input id="whManFc" style="width:80px;min-width:0" value="${esc(fc)}" title="手工分录的账期"><button class="btn" id="whMan">标记手工转出</button><button class="btn" id="whUnman">取消标记</button>`
           : `<span class="hint">转出需要“管理”权限</span>`) + `</div><div id="whMsg"></div><div id="whPrev"></div>`
    + (stale.length ? `<div class="msg err">转出计划和当前运行 #${id} 不一致（${stale.length} 张订单），重新计算后才能生成凭单。</div>` : "")
    + note(`这里列出承接前已关闭、在产品还留在 140801 的委外订单。旧框架关单日期在 2026-08 以前的委外订单没有转关单差异，承接时又只取未关闭订单，所以业务端是 0、总账还有余额。勾选后点“转入”，按整张订单转出，负数订单也要转。之后重新计算：金额进 ${esc(pl.PoolName || pl.PoolCode || "制造费用")} 费用池分摊给当月完工产品，并生成凭证 JZ05（借 510109 / P016，贷 140801）。转出金额本期不算 140801 差额，在“财务对账”单独列示；下期起进期初，期初差额随之减少。已生成凭单的账期不能改，要先撤销凭单。`, "wwhist")
    + `<div id="whMain">` + table(r, {freeze:4, wrap:["PlanNote"], empty:"清单是空的，点“刷新清单”从旧在产品表载入",
        fmt:{Pick:(v, x) => x[iS] === "TODO" || x[iS] === "PLAN" || x[iS] === "MANUAL" ? `<input type="checkbox" data-wh="${esc(key(x))}"${x[iP] ? " checked" : ""}>` : "",
             State:v => esc(WWSTATE[v] || v), InRun:v => v === "Y" ? "是" : ""}}) + `</div>`;
  const main = $("#whMain"), box = $("#whMsg"), picked = st => r.rows.filter(x => x[iP] && x[iS] === st);
  // 140801 现有差异 = 对账期末差额 + 本运行的手工调整和 JZ05；计划改过、还没重新计算的部分按计划扣减
  const pending = sum(r.rows.filter(x => x[iS] === "PLAN" && x[iR] !== "Y")) - sum(r.rows.filter(x => x[iS] === "TODO" && x[iR] === "Y"));
  const gapNow = gap ? whR(Number(gap.EndDiffGl) - pending) : null;
  const gapAfter = () => whR(gapNow - sum(picked("TODO")) + sum(picked("PLAN")));
  const gapHtml = () => { if (gapNow === null) return `<p class="hint">这次运行没有成功的计算结果，算不出 140801 差异预览。</p>`;
    const v = gapAfter(); return `<div class="msg ${v < 0 ? "err" : "info"}">140801 财务 − 业务差异：现在 ${fmtNum(gapNow)}，按当前选择转完后 ${fmtNum(v)}`
      + (v < 0 ? `。<b>超过差异 ${fmtNum(-v)}，财务会低于业务，请少选一些。</b>` : "") + `</div>`; };
  const stat = () => { const a = r.rows.filter(x => x[iP]); $("#whCnt").textContent = a.length; $("#whSum").textContent = fmtNum(sum(a));
    const add = sum(picked("TODO")), del = sum(picked("PLAN")), pool = Number(pl.PoolAmt || 0), next = whR(pool + add - del);
    $("#whPrev").innerHTML = gapHtml() + (pl.PoolAmt === null || pl.PoolAmt === undefined ? "" : `<p class="hint">当前运行 ${esc(pl.PoolName || pl.PoolCode)} 制造费用池 ${fmtNum(pool)}（含转出 ${fmtNum(pl.HistAmt)}）；按当前选择变为 ${fmtNum(next)}`
      + (pool ? `，变化 ${fmtNum(whR((next - pool) / pool * 100))}%，每工时费用同比例变化` : "") + `。这是按金额估算，单价以重新计算或模拟为准。</p>`); };
  for (const ev of ["click", "dblclick", "keydown", "mousedown"]) main.addEventListener(ev, e => { if (e.target.closest("input[data-wh]")) e.stopPropagation(); });
  main.addEventListener("change", e => { const t = e.target.closest("input[data-wh]"); if (!t) return; byKey.get(t.dataset.wh)[iP] = t.checked ? "Y" : ""; stat(); });
  stat();
  if (!can) return;
  const user = () => $("#user").value.trim() || "user";
  const reload = async msg => { await wwHistPage(pane, id); $("#whMsg").innerHTML = msg; };
  $("#whLoad").onclick = async () => {
    box.innerHTML = `<div class="msg info">正在载入…</div>`;
    try { await reload(`<div class="msg ok">${esc(exMsg(await ex("wwHistLoad", {fc, user:user()})))}</div>`); } catch (e) { box.innerHTML = errBox(e); }
  };
  const apply = async (rows, onoff, descr, action = "wwHistSet", tofc = fc) => {
    let n = 0; const errs = [];
    for (const x of rows) {   // 一张订单一次调用，失败的列出来，已成功的不回退
      try { exMsg(await ex(action, {fc:tofc, orderType:String(x[iT]), orderEntry:String(x[iE]), onoff, descr, user:user()})); n++; }
      catch (e) { errs.push(`${key(x)}：${e.message}`); }
    }
    await reload(`<div class="msg ${errs.length ? "err" : "ok"}">成功 ${n} 张${action === "wwHistSet" ? "，请重新计算" : ""}${errs.length ? "；失败：" + esc(errs.join("；")) : ""}</div>`);
  };
  $("#whAdd").onclick = async () => {
    const a = picked("TODO");
    if (!a.length) { box.innerHTML = `<div class="msg err">请先勾选待转的订单。</div>`; return; }
    const ok = await confirmDlg(`确认转入 ${fc}`, [["账套", INFO.schema], ["账期", fc], ["订单", `${a.length} 张`], ["净额", fmtNum(sum(a))], ["分录", "借 510109 / P016，贷 140801（JZ05）"], ...(gapNow === null ? [] : [["转完后 140801 差异", fmtNum(gapAfter()) + (gapAfter() < 0 ? "（财务低于业务）" : "")]]), ["说明", "金额进费用池分摊给当月完工产品，改完要重新计算"]], false, false, true);
    if (ok === null) return;
    await apply(a, "Y", DLG_REASON);
  };
  $("#whDel").onclick = async () => {
    const a = picked("PLAN");
    if (!a.length) { box.innerHTML = `<div class="msg err">请先勾选本期转出的订单。</div>`; return; }
    const ok = await confirmDlg("确认取消转出", [["账期", fc], ["订单", `${a.length} 张`], ["净额", fmtNum(sum(a))], ["说明", "取消后回到待转，要重新计算"]], false, false, false);
    if (ok === null) return;
    await apply(a, "N", "");
  };
  $("#whMan").onclick = async () => {
    const a = picked("TODO"), mf = $("#whManFc").value.trim();
    if (!a.length) { box.innerHTML = `<div class="msg err">请先勾选待转的订单。</div>`; return; }
    if (!/^\d{4}-\d{2}$/.test(mf)) { box.innerHTML = `<div class="msg err">手工分录账期要写成 2026-09 这样。</div>`; return; }
    const ok = await confirmDlg("确认标记手工转出", [["手工分录账期", mf], ["订单", `${a.length} 张`], ["净额", fmtNum(sum(a))], ["说明", "只标记这些订单不能再选，不生成凭证、不影响计算"]], false, false, true);
    if (ok === null) return;
    await apply(a, "Y", DLG_REASON, "wwHistMark", mf);
  };
  $("#whUnman").onclick = async () => {
    const a = picked("MANUAL");
    if (!a.length) { box.innerHTML = `<div class="msg err">请先勾选已手工转出的订单。</div>`; return; }
    const ok = await confirmDlg("确认取消标记", [["订单", `${a.length} 张`], ["净额", fmtNum(sum(a))], ["说明", "取消后回到待转"]], false, false, false);
    if (ok === null) return;
    await apply(a, "N", "", "wwHistMark");
  };
}
