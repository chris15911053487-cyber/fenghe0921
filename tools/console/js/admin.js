// 成本执行台 · admin.js — 说明书、B1 维护数据（只读）、生成 SAP 凭单
// index.html 按顺序加载 js/ 下的脚本，共用全局作用域；加载时立即执行的代码只能用到本文件和前面文件里的名字。
"use strict";
// ---------------- 说明书（meta.describe / doc.manual，只用元数据和登记表） ----------------
const LAYER = {RUN:"运行日志", C:"配置", M:"元数据", S:"快照（输入）", R:"结果", BOOT:"期初承接", B1:"B1 自定义表"};
// ---------------- B1 维护数据（只读）：费用池、成本中心归属、计算参数、期初成本价、工时 ----------------
// 这些都在 SAP B1 里维护（用户 2026-10-14），执行台只看不改。费用池和计算参数（2026-10-28 起 @MTC_CA_PARAM）每次计算 / 只做检查时由 P05 同步到 MTC_CA_C_*；
// 期初成本价、工时在 P20_MISC 取快照（同一物料多行取最大值，已取消的不取，期初价为 0 的不取）。
const B1SUB = {pool:"费用池", ocr:"成本中心归属", exp:"计算参数", qcp:"期初成本价", time:"工时"};
const MATCHBY = {GRPTYPE:"车间类别", GRP:"物料组"};
const b1Err = (e, tbl) => `<div class="msg err">${esc(e.message || e)}</div><p class="hint">如果提示表或字段不存在：B1 里还没建 ${esc(tbl)}，或字段名与 新框架/B1自定义表_费用配置.md 不一致。</p>`;
const ynMark = v => v === "Y" ? "<b>是</b>" : "";
const listVal = v => esc(String(v ?? "").replace(/^,|,$/g, ""));
// 检查 B1 配置（用户 2026-10-28）：只读查询校验视图 MTC_CA_V_B1CFG_ISSUES，与 B1 保存校验、P05 同一口径
const B1OBJ = {MTC_CA_PARAM:"计算参数", MTC_CA_POOL:"费用池"};
const b1ChkBar = () => `<div class="bar"><button class="btn" id="b1Pull"${canDo("O") ? "" : " disabled title=\"需要“操作”权限\""}>从 B1 拉取</button><button class="btn" id="b1Chk">检查 B1 配置</button><span class="hint">“从 B1 拉取”把 B1 的费用池和计算参数抽取到新框架（开始计算、只做检查、期初承接时也会自动拉取），不计算；“检查 B1 配置”只读，查 B1 里填的有没有错</span></div><div id="b1ChkRes"></div>`;
// onPulled：拉取成功后重画当前页签（用户 2026-10-29）
function b1ChkBind(onPulled){
  const pull = $("#b1Pull");
  if (pull) pull.onclick = async () => {
    pull.disabled = true; $("#b1ChkRes").innerHTML = `<div class="empty">正在从 B1 拉取…</div>`;
    try {
      const r = asObjs(await api("/api/exec", {action:"cfgPull", args:{}}))[0] || {};
      const msg = `<div class="msg ${Number(r.Code) === 0 ? "info" : "err"}">${esc(r.Msg || "已拉取")}</div>`;
      loadBoot();
      if (onPulled) { await onPulled(); const el = $("#b1ChkRes"); if (el) el.innerHTML = msg; }
      else $("#b1ChkRes").innerHTML = msg;
    } catch (e) { $("#b1ChkRes").innerHTML = errBox(e); }
    finally { const b = $("#b1Pull"); if (b) b.disabled = !canDo("O"); }
  };
  const btn = $("#b1Chk"); if (!btn) return;
  btn.onclick = async () => {
    const res = $("#b1ChkRes"); res.innerHTML = `<div class="empty">检查中…</div>`;
    try {
      const r = await q("cfgIssues");
      res.innerHTML = r.rows.length
        ? `<div class="msg err">B1 配置有 ${r.rows.length} 个问题，不改的话下次计算会在 P05 / PRE-18 被阻断：</div>` + table(r, {fmt:{Obj: v => esc(B1OBJ[v] || v)}, wrap:["Msg"], sum:false})
        : `<div class="msg info">B1 配置检查通过（计算参数、费用池）</div>`;
    } catch (e) {
      res.innerHTML = `<div class="msg err">${esc(e.message || e)}</div><p class="hint">这个账套还没装校验视图 MTC_CA_V_B1CFG_ISSUES（它直接读 B1 自定义表，不在部署包里）：在 B1 建好 @MTC_CA_PARAM、@MTC_CA_POOL / 1 / 2 和 OPRC.U_CalType 字段后，执行 新框架/sql/20_b1cfg_check.sql。没装时不影响计算，P05 会用内置的检查。</p>`;
    }
  };
}
// 比较 B1 填法和库里的值：去空格、全角逗号，列表去掉首尾逗号，单独的“空”当作空项
const paramNorm = v => String(v ?? "").replace(/\s/g, "").replace(/，/g, ",").split(",").map(x => x === "空" ? "" : x).join(",").replace(/^,+|,+$/g, "").toUpperCase();
const usedCell = v => /^使用|使用这一行/.test(v || "") ? esc(v) : `<b style="color:var(--warn)">${esc(v)}</b>`;
// 生成 SAP 凭单（用户 2026-10-19，设计稿 8.6；Q36 OBTF、Q41 本人 B1 账号、Q42 一种凭证代码一张、Q43 校验不通过不能生成、Q44 B1 已有的代码排除）
// 只在服务器模式（B1 账号登录）可用；数据库端 MTC_CA_P_JV_BEGIN / UNDO 同样检查
const JVST = {READY:["可以生成","OK"], CREATED:["已生成","RUNNING"], B1:["B1 已有","SKIP"], UNBAL:["借贷不平","FAIL"], BADACCT:["科目有问题","FAIL"],
  FAIL:["失败","FAIL"], DELETED:["已撤销","SKIP"]};
const jvChip = s => `<span class="chip s-${(JVST[s] || [s, "SKIP"])[1]}">${esc((JVST[s] || [s])[0])}</span>`;
async function renderJv(pane, msgHtml){
  const fc0 = pane.dataset.jvfc || (SEL && SEL.FcCode) || $("#fc").value;
  pane.innerHTML = note(`按本期<b>最近一次成功的正式计算</b>的凭证底稿（“凭证”页），每种凭证代码在 B1 建一张<b>日记账凭单</b>（待过账），由财务在 B1 审核过账。`
      + `计算后校验有不通过项时不能生成，管理权限可以逐项确认（写明理由）后仍生成；本期 B1 里已有同一凭证代码的凭证或未清凭单（如手工录过的）自动排除。生成后账期状态变为“已生成凭单”，不能再正式计算；`
      + `需要重算时：先在 B1“财务 → 日记账凭单”里删除这些凭单（已过账的先冲销），再点“撤销凭单”。`)
    + `<div class="bar"><label class="hint">账期 <select id="jvFc">${$("#fc").innerHTML}</select></label><span id="jvStat"></span><span class="sp"></span>
       <button class="btn" id="jvUndo" hidden>撤销凭单</button><button class="btn" id="jvFinish" hidden>不再生成其余代码，标记为已生成凭单</button>
       <button class="btn primary" id="jvGo" disabled>生成凭单</button></div>
       <div id="jvMsg">${msgHtml || ""}</div><div id="jvBody"><div class="empty">加载中…</div></div>`;
  if ([...$("#jvFc").options].some(o => o.value === fc0)) $("#jvFc").value = fc0;
  const fc = $("#jvFc").value; pane.dataset.jvfc = fc;
  $("#jvFc").onchange = () => { pane.dataset.jvfc = $("#jvFc").value; renderJv(pane); };
  await loadPStat();
  const ps = PSTAT[fc];
  $("#jvStat").innerHTML = ps ? " " + pChip(fc) : "";
  let plan, list, chk;
  try { [plan, list, chk] = await Promise.all([q("jvPlan", {fc}, true), q("jvList", {fc}, true), q("jvChecks", {fc}, true)]); }
  catch (e) { $("#jvBody").innerHTML = errBox(e) + `<div class="hint">数据库还没有部署 19_jv.sql 时会出现这个错误。</div>`; return; }
  const po = asObjs(plan), lo = asObjs(list);
  const ready = po.filter(x => x.State === "READY"), created = lo.filter(x => x.Status === "CREATED");
  const server = !!(INFO && INFO.login), canA = canDo("A"), locked = ps && ps.Status === "LOCKED";
  // 计算后校验阻断项（Q45）：逐项确认后不再阻断；已生成凭单后不能再改确认
  const co = asObjs(chk), unack = co.filter(x => !x.AckUser), frozen = created.length > 0 || (ps && ps.Status === "POSTED");
  const why = !server ? "生成凭单只在服务器模式（用 B1 账号登录）下可用，本机模式只能查看。" : !canA ? "生成 / 撤销凭单需要“管理”权限。"
    : locked ? "账期已在 B1 锁定。" : !po.length ? "本期还没有成功的正式计算，或底稿没有分录。"
    : unack.length ? `计算后校验有 ${unack.length} 项未通过且未确认（${unack.map(x => x.CheckId).join("、")}）：处理后重新计算，或在下面逐项确认后再生成。` : "";
  const chk2 = {columns: [...chk.columns, "Act"], rows: chk.rows.map((x, i) => [...x, co[i].CheckId]), src: chk.src};
  const actBtn = (v, x) => { const acked = !!co.find(c => c.CheckId === v && c.AckUser);
    return !server || !canA || frozen ? "" : `<button class="btn jvack" data-id="${esc(v)}" data-ack="${acked ? 1 : 0}">${acked ? "取消确认" : "确认后仍生成"}</button>`; };
  const plan2 = {columns: ["Sel", ...plan.columns], rows: plan.rows.map((x, i) => [po[i].State === "READY" ? po[i].TransCode : "", ...x]), src: plan.src};
  $("#jvBody").innerHTML = (why ? `<div class="msg info">${esc(why)}</div>` : "")
    + (co.length ? `<h3>计算后校验未通过项（运行 #${esc(co[0].RunId)}）</h3>`
        + table(chk2, {hide:["RunId"], fmt:{Act: actBtn}, wrap:["Msg", "AckReason"]}) : "")
    + `<h3>本期凭证底稿${po.length ? `（运行 #${esc(po[0].RunId)}）` : ""}</h3>`
    + table(plan2, {hide:["RunId"], fmt:{Sel: v => v ? `<input type="checkbox" class="jvck" value="${esc(v)}" checked${why ? " disabled" : ""}>` : "", State: jvChip}, wrap:["StateMsg"], empty:"没有凭证底稿"})
    + `<h3>已生成的凭单</h3>` + table(list, {hide:["RunId"], fmt:{Status: jvChip}, wrap:["Msg"], empty:"本期还没有生成过凭单"});
  pane.querySelectorAll(".jvack").forEach(b => b.onclick = async e => {
    e.stopPropagation();
    const c = co.find(x => x.CheckId === b.dataset.id), runId = String(c.RunId);
    try {
      if (b.dataset.ack === "1") {
        const ok = await confirmDlg("取消确认", [["校验", c.CheckId + " " + (c.Title || "")], ["说明", "取消后生成凭单会重新被这一项阻断"]]);
        if (ok === null) return;
        const r = await api("/api/exec", {action:"checkUnack", args:{runId, checkId:c.CheckId, user:$("#user").value.trim() || "console"}});
        renderJv(pane, `<div class="msg ok">${esc((r.rows[0] || [])[1] || "已取消")}</div>`);
      } else {
        const ok = await confirmDlg("确认阻断项后仍生成凭单", [["账期", fc], ["运行", "#" + runId], ["校验", c.CheckId + " " + (c.Title || "")], ["结果", c.Msg || ""],
          ["说明", "只对这次运行有效；重新计算后要重新确认"]], false, false, true);
        if (ok === null) return;
        const reason = DLG_REASON.replace(/\s+/g, " "); DLG_REASON = "";   // 校验规则不允许换行
        const r = await api("/api/exec", {action:"checkAck", args:{runId, checkId:c.CheckId, user:$("#user").value.trim() || "console", descr:reason}});
        const row = r.rows[0] || [];
        renderJv(pane, `<div class="msg ${Number(row[0]) === 0 ? "ok" : "err"}">${esc(row[1] || "")}</div>`);
      }
    } catch (err) { $("#jvMsg").innerHTML = errBox(err); }
  });
  const sel = () => [...pane.querySelectorAll(".jvck:checked")].map(x => x.value);
  const upd = () => { $("#jvGo").disabled = !!why || !sel().length; $("#jvGo").textContent = `生成凭单（${sel().length} 张）`; };
  pane.querySelectorAll(".jvck").forEach(x => x.onchange = upd); upd();
  $("#jvUndo").hidden = !created.length || !server || !canA;
  $("#jvFinish").hidden = !created.length || !server || !canA || (ps && ps.Status === "POSTED");
  const post = async (path, args, okText) => {
    $("#jvMsg").innerHTML = `<div class="msg info">处理中…</div>`;
    try {
      const r = await api(path, args);
      let h;
      if (path.endsWith("undo")) h = `<div class="msg ok">${esc(r.msg || okText)}</div>`;
      else {
        const bad = (r.done || []).filter(d => !d.ok);
        h = `<div class="msg ${r.failed ? "err" : "ok"}">${r.failed ? "部分凭单没有生成：" + esc(bad.map(d => d.TransCode + " " + d.msg).join("；")) + "。已生成的保留，可以重试剩下的，或撤销。" : esc((r.finish && r.finish.Msg) || okText)}</div>`
          + ((r.done || []).length ? table({columns:["TransCode","ok","BatchNum","Debit","Credit","LineCnt","msg"], rows:r.done.map(d => [d.TransCode, d.ok ? "成功" : "失败", d.BatchNum ?? "", d.Debit ?? "", d.Credit ?? "", d.LineCnt ?? "", d.msg || ""])}, {wrap:["msg"]}) : "");
      }
      renderJv(pane, h);
    } catch (e) { $("#jvMsg").innerHTML = errBox(e); }
  };
  $("#jvGo").onclick = async () => {
    const codes = sel(), tot = po.filter(x => codes.includes(x.TransCode)).reduce((a, x) => a + Number(x.Debit || 0), 0);
    const ok = await confirmDlg("确认生成 SAP 日记账凭单", [["账套", INFO.schema], ["账期", fc], ["运行", "#" + po[0].RunId], ["凭证代码", codes.join("、")],
      ["借方合计", tot.toLocaleString("zh-CN", {minimumFractionDigits:2, maximumFractionDigits:2})], ["说明", "在 B1 建待过账的日记账凭单，生成后不能再正式计算"]], true, true);
    if (ok === null) return;
    const pwd = DLG_PWD; DLG_PWD = "";
    post("/api/jv/create", {fc, codes, password:pwd, confirm:ok}, "已生成");
  };
  $("#jvFinish").onclick = async () => {
    const ok = await confirmDlg("标记为已生成凭单", [["账期", fc], ["说明", "其余没勾选的凭证代码不再生成；账期状态改为“已生成凭单”，不能再正式计算"]], true);
    if (ok === null) return;
    post("/api/jv/create", {fc, codes:[], confirm:ok}, "已标记");
  };
  $("#jvUndo").onclick = async () => {
    const ok = await confirmDlg("撤销凭单", [["账期", fc], ["凭单", created.map(x => x.TransCode + " 批号 " + x.BatchNum).join("、")],
      ["说明", "先在 B1 删除这些凭单（已过账的先冲销）；这里核对 B1 后记为已撤销，账期回到“已计算”"]], true);
    if (ok === null) return;
    post("/api/jv/undo", {fc, confirm:ok}, "已撤销");
  };
}
async function renderB1(pane){
  let sub = "pool"; try { sub = localStorage.getItem("cc.b1") || "pool"; } catch (e) {}
  if (!B1SUB[sub]) sub = "pool";
  const fc0 = (SEL && SEL.FcCode) || $("#fc").value;
  pane.innerHTML = note(`这里显示在 SAP B1 里维护的成本配置，只读；要修改请到 B1 里改。费用池和计算参数在每次“开始计算”或“只做计算前检查”时同步到新框架，期初成本价和工时在取快照时读取。`) + `
    <div class="bar"><nav class="subtabs" id="b1Tabs" style="margin:0">${Object.entries(B1SUB).map(([k, v]) => `<button data-t="${k}">${v}</button>`).join("")}</nav>
      <span class="sp"></span><label class="hint" id="b1FcWrap">账期 <select id="b1Fc">${$("#fc").innerHTML}</select></label></div>
    <div id="b1Body"></div>`;
  if ([...$("#b1Fc").options].some(o => o.value === fc0)) $("#b1Fc").value = fc0;
  const body = $("#b1Body");
  const show = async t => {
    sub = t; try { localStorage.setItem("cc.b1", t); } catch (e) {}
    document.querySelectorAll("#b1Tabs button").forEach(b => b.classList.toggle("on", b.dataset.t === t));
    $("#b1FcWrap").hidden = t === "pool";
    const fc = $("#b1Fc").value;
    body.innerHTML = `<div class="empty">加载中…</div>`;
    if (t === "pool") {
      const [p, s1, s2, sy] = await Promise.allSettled([q("b1Pool"), q("b1PoolSrc"), q("b1PoolTgt"), q("cfgSync")]);
      if (sub !== t) return;
      const syn = sy.status === "fulfilled" ? asObjs(sy.value)[0] : null;
      body.innerHTML = (syn ? `<div class="msg ${syn.Status === "FAIL" ? "err" : "info"}">最近一次同步（运行 #${esc(syn.RunId)}，${esc(String(syn.EndTime || "").slice(0, 16))}）：${esc(syn.Msg || "")}</div>` : "")
        + b1ChkBar()
        + `<h3>费用池 <span class="hint mono">@MTC_CA_POOL</span></h3>`
        + (p.status === "fulfilled" ? table(p.value, {fmt:{IsDefault: ynMark, IsCloseDif: ynMark}, wrap:["Descr"], empty:"B1 里没有费用池数据，计算沿用新框架种子值（见“说明书 → 费用池”）"}) : b1Err(p.reason, "@MTC_CA_POOL"))
        + `<p class="hint">默认池：没有配置的成本中心、没有成本中心的重估进这个池；关单差异池：订单关单差异全部进这个池。两者都必须正好一个。</p>`
        + `<h3>成本中心 → 费用池 <span class="hint mono">@MTC_CA_POOL1</span></h3>`
        + (s1.status === "fulfilled" ? table(s1.value, {wrap:["Descr", "OcrName"], empty:"没有单独配置的成本中心（全部按成本计入类型或进默认池）"}) : b1Err(s1.reason, "@MTC_CA_POOL1"))
        + `<p class="hint">成本中心一栏可以填成本中心代码，也可以填成本中心主数据上“成本计入类型”（OPRC.U_CalType）的取值，如 P017，所有该类型的成本中心都进这个池。每个成本中心实际进哪个池看“成本中心归属”。</p>`
        + `<h3>分摊范围 <span class="hint mono">@MTC_CA_POOL2</span></h3>`
        + (s2.status === "fulfilled" ? table(s2.value, {fmt:{MatchBy: v => esc(MATCHBY[v] || v)}, wrap:["Descr"], empty:"没有分摊范围"}) : b1Err(s2.reason, "@MTC_CA_POOL2"))
        + `<p class="hint">池里的费用按“单位工时 × 本期入库数”分给匹配到的产品的订单；车间类别是物料组上的 U_ItemGrpType。订单类型为空 = 10,20,30,40（委外 50 不分摊）。同一产品只能匹配一个池。</p>`;
      b1ChkBind(() => show(t));
    } else if (t === "ocr") {
      try {
        const r = await q("ocrPool", {fc}); if (sub !== t) return;
        const o = asObjs(r), cnt = {}; o.forEach(x => { const k = (x.PoolCode || "") + " " + (x.PoolName || ""); cnt[k] = (cnt[k] || 0) + 1; });
        body.innerHTML = `<p class="hint">${esc(fc)} 每个部门（成本中心维度 1，费用归集按这个维度）的费用进哪个池：先看 @MTC_CA_POOL1 里单独配置的成本中心，再看成本中心主数据的成本计入类型（U_CalType），都没有的进默认池。按上一次同步到新框架的配置计算；在 B1 改了配置后，点“只做计算前检查”同步一次再来看。</p>`
          + `<div class="summary">${Object.entries(cnt).map(([k, n]) => `<span>${esc(k)} <b>${n}</b> 个</span>`).join("")}<span class="sp"></span><button class="btn" id="b1Csv">导出 Excel</button></div>`
          + table(r, {fmt:{Basis: v => /没有配置/.test(v || "") ? `<b style="color:var(--warn)">${esc(v)}</b>` : esc(v)}, empty:"OPRC 里没有部门（维度 1）"});
        $("#b1Csv").onclick = () => csv(r, `成本中心归属_${fc}`);
      } catch (e) { body.innerHTML = b1Err(e, "OPRC.U_CalType"); }
    } else if (t === "exp") {
      // 计算参数总览（用户 2026-10-28）：以参数目录 MTC_CA_C_PARAM_DEF 为主，对上 B1 @MTC_CA_PARAM（没有时旧 @MTC_CA_EXPSET）本期适用的值
      // 和上一次同步后计算实际使用的值；B1 表本身折叠在下面
      const [o, b, old, sy, lk] = await Promise.allSettled([q("paramOverview", {fc}), q("b1Param", {fc}), q("b1ExpSet", {fc}), q("cfgSync"), q("paramLocks")]);
      if (sub !== t) return;
      if (o.status !== "fulfilled") { body.innerHTML = errBox(o.reason) + `<p class="hint">没有参数目录 MTC_CA_C_PARAM_DEF：先执行 新框架/sql/patch_20261028_param_ui.sql。</p>`; return; }
      const useNew = b.status === "fulfilled" && b.value.rows.length > 0;
      const b1 = useNew ? b.value : old.status === "fulfilled" ? old.value : null, b1Tbl = useNew ? "@MTC_CA_PARAM" : "@MTC_CA_EXPSET";
      const bv = {}, bn = {};
      if (b1) asObjs(b1).forEach(x => { bn[x.ParamCode] = (bn[x.ParamCode] || 0) + 1; if (x.InFc === "Y") bv[x.ParamCode] = x.Value ?? ""; });
      // B1 U_Locked = Y 的参数（取自快照 MTC_CA_C_PARAM_B1：B1 保存或同步时刷新；用户 2026-10-29）
      const locked = new Set(lk.status === "fulfilled" ? asObjs(lk.value).map(x => x.ParamCode) : []);
      const r = {columns:["Category", "ParamCode", "CnName", "Locked", "B1Value", "EffValue", "Src", "ParamState", "Hint"], rows: asObjs(o.value).map(x => {
        const n = bn[x.ParamCode] || 0, has = Object.prototype.hasOwnProperty.call(bv, x.ParamCode);
        // B1 里没有或本期没有适用的行：计算前 PRE-28 阻断（用户 2026-11-01）；读的是旧 @MTC_CA_EXPSET 时也算没有维护
        const st = x.Category === "不在参数表维护" ? "" : !useNew || !n ? "B1 里没有（PRE-28 会阻断）"
          : !has ? "B1 里本期没有适用的行（PRE-28 会阻断）" : paramNorm(bv[x.ParamCode]) === paramNorm(x.EffValue) ? "一致" : "B1 已改，还没同步";
        return [x.Category, x.ParamCode, x.CnName, locked.has(x.ParamCode) ? "🔒 锁定" : "", has ? bv[x.ParamCode] : "", x.EffValue, x.Src, st, x.Hint];
      })};
      const syn = sy.status === "fulfilled" ? asObjs(sy.value)[0] : null;
      const miss = r.rows.filter(x => /PRE-28/.test(x[7])).length;
      body.innerHTML = (miss ? `<div class="msg err">${esc(fc)} 有 ${miss} 个参数在 B1 @MTC_CA_PARAM 里没有维护（见“状态”列），计算前检查 PRE-28 会阻断。在 B1 补行，或在能连库的机器上运行 python3 新框架/tools/sl_import_costcfg.py --param 补上缺的参数（已有的不动）。</div>` : "")
        + (syn ? `<div class="msg ${syn.Status === "FAIL" ? "err" : "info"}">最近一次同步（运行 #${esc(syn.RunId)}，${esc(String(syn.EndTime || "").slice(0, 16))}）：${esc(syn.Msg || "")}</div>` : "")
        + b1ChkBar()
        + `<h3>${esc(fc)} 计算参数总览 <span class="hint mono">B1 ${esc(b1Tbl)}</span></h3>`
        + table(r, {fmt:{EffValue: listVal, ParamState: v => v === "一致" || !v ? esc(v) : `<b style="color:var(--warn)">${esc(v)}</b>`},
            wrap:["CnName", "B1Value", "EffValue", "Hint"], sum:false, empty:"参数目录是空的"})
        + `<p class="hint">“B1 取值”是 B1 ${esc(b1Tbl)} 里 ${esc(fc)} 适用的那一行；“计算使用值”是上一次同步（开始计算或只做计算前检查）后新框架实际用的值。`
        + `“B1 已改，还没同步”：开始计算、只做计算前检查、期初承接时都会先同步。“锁定”= B1 里该参数的锁定（U_Locked）是 Y，B1 保存时不允许改值或删除，要改先把锁定改成 N。在 B1 里一行 = 一个参数的一段账期，同一参数第二段起 Code 写 参数代码@起始账期（如 TAIL_MAX@2026-11）。`
        + `列表填 A,B,C；凭证代码里单独的“空”表示没有凭证代码的手工凭证。</p>`
        + `<details><summary>B1 原样（${esc(b1Tbl)}）</summary>`
        + (b1 ? table(b1, {fmt:{InFc: v => v === "Y" ? `<b>${esc(fc)} 适用</b>` : ""}, wrap:["Value", "Descr", "CnName"], sum:false, empty:"B1 里没有数据，全部沿用新框架现有值"})
              : b1Err(b.status === "rejected" ? b.reason : old.reason, "@MTC_CA_PARAM"))
        + `</details>`;
      b1ChkBind(() => show(t));
    } else {
      const isQ = t === "qcp", title = isQ ? "期初成本价" : "工时", act = isQ ? "b1Qcp" : "b1Time";
      body.innerHTML = `<p class="hint">${isQ
          ? `B1“期初单价维护”（@MTC_COST_QCPRICE）中 ${esc(fc)} 的单据。计算前没有任何价格来源的物料用这里的价格兜底；同一物料有多行时取最大值，已取消的单据和单价为 0 的行不使用。哪些物料还需要维护见“期初价维护”页。`
          : `B1“工时维护”（@MTC_COST_TIME）中 ${esc(fc)} 的单据。费用池按“单位工时 × 本期入库数”分摊给订单；同一产品有多行时取最大值，已取消的单据不使用；有完工却没有工时的产品计算前检查会阻断。`}</p>
        <div class="bar"><input type="text" id="b1q" placeholder="${isQ ? "物料编码开头或物料组" : "物料编码开头"}" maxlength="50" value="${esc(sqGet(title))}"><button class="btn" id="b1go">查询</button><span class="sp"></span><span class="hint" id="b1Sum"></span><button class="btn" id="b1Csv">导出 Excel</button></div><div id="b1Res"></div>`;
      let last = null;
      const go = async () => {
        const v = $("#b1q").value.trim();
        if (!/^[A-Za-z0-9_.\-\/]{0,50}$/.test(v)) { $("#b1Res").innerHTML = errBox("只能输入字母、数字、下划线、点、横线和斜线"); return; }
        sqSet(title, v); $("#b1Res").innerHTML = `<div class="empty">加载中…</div>`;
        try {
          last = await q(act, {fc, q:v}); if (sub !== t) return;
          const o = asObjs(last), items = new Set(o.filter(x => /^使用|使用这一行/.test(x.Used)).map(x => x.ItemCode));
          const docs = new Set(o.map(x => x.DocNum)), warn = o.filter(x => !/^使用$/.test(x.Used)).length;
          $("#b1Sum").innerHTML = `${docs.size} 张单据 · ${o.length} 行 · 生效物料 <b>${items.size}</b>${warn ? ` · 需留意 <b style="color:var(--warn)">${warn}</b> 行` : ""}`;
          $("#b1Res").innerHTML = table(last, {fmt:{Used: usedCell}, wrap:["Note"], empty:`B1 里没有 ${fc} 的${title}`});
        } catch (e) { $("#b1Res").innerHTML = b1Err(e, isQ ? "@MTC_COST_QCPRICE" : "@MTC_COST_TIME"); }
      };
      $("#b1go").onclick = go; $("#b1q").onkeydown = e => { if (e.key === "Enter") go(); };
      $("#b1Csv").onclick = () => last && csv(last, `${title}_${fc}`);
      go();
    }
  };
  document.querySelectorAll("#b1Tabs button").forEach(b => b.onclick = () => show(b.dataset.t));
  $("#b1Fc").onchange = () => show(sub);
  show(sub);
}
async function renderManual(pane){
  pane.innerHTML = `<div class="bar"><input type="text" id="mq" placeholder="表名、说明、来源或字段说明里的词" maxlength="50" style="width:220px" value="${esc(sqGet("说明书"))}"><button class="btn" id="mgo">查找</button><span class="sp"></span><button class="btn" id="mdl">下载系统说明书</button></div>
    <nav class="subtabs" id="mTabs"><button data-t="tables" class="on">表与字段</button><button data-t="rules">计算规则</button><button data-t="checks">校验</button><button data-t="tools">AI 工具</button><button data-t="params">参数与科目</button><button data-t="pools">费用池</button><button data-t="rpts">成本报表</button></nav>
    <div id="mBody"></div>`;
  const body = $("#mBody");
  const show = async t => {
    document.querySelectorAll("#mTabs button").forEach(b => b.classList.toggle("on", b.dataset.t === t));
    body.innerHTML = `<div class="empty">加载中…</div>`; closeDrawer();
    try {
      if (t === "tables") {
        const v = $("#mq").value.trim(); sqSet("说明书", v);
        const r = await q("metaTables", {text:v});
        body.innerHTML = table(r, {onRow:true, wrap:["Descr", "Source"], fmt:{Layer: v => esc(LAYER[v] || v)}, empty:"没有匹配的表"});
        bindRows(body, r, async x => {
          const d = drawer(x.TableName); d.innerHTML = `<div class="empty">加载中…</div>`;
          try { const c = await q("metaColumns", {tableName:x.TableName}); d.innerHTML = `<h3>${esc(x.TableName)}</h3><p class="hint">${esc(x.Descr || "")}</p>` + (x.Source ? `<p class="hint">来源：${esc(x.Source)}</p>` : "") + table(c, {wrap:["Descr"]}); }
          catch (e) { d.innerHTML = errBox(e); }
        });
      } else if (t === "rules") body.innerHTML = table(await q("metaRules"), {wrap:["Descr"]});
      else if (t === "checks") body.innerHTML = table(await q("metaChecks"), {wrap:["Purpose"], fmt:{IsBlock: v => v === "Y" ? "阻断" : ""}});
      else if (t === "tools") body.innerHTML = `<p class="hint">AI 助手只能调用这里登记的工具；给模型的只有“给模型的内容”一列（A 档：状态和行数，不含金额、单价、数量和明细）。</p>` + table(await q("metaTools"), {wrap:["Descr","ModelOutput"]});
      else if (t === "params") body.innerHTML = `<h3>参数</h3>` + table(await q("metaParams"), {wrap:["Descr","Value"]}) + `<h3>科目</h3>` + table(await q("metaAccts"), {wrap:["Descr"]});
      else if (t === "rpts") body.innerHTML = `<p class="hint">左侧菜单“成本报表”和 B1 查询管理器调用同一批过程（新框架/sql/21_reports.sql）；B1 语句见 新框架/reports/B1查询语句.md 或报表页的“在 SAP 中打开”。参数留空 = 全部，代码类按开头匹配，前面加 = 精确匹配；账期已生成凭单取凭单所用运行，否则取最近一次成功正式运行。</p>`
        + table({columns:["编号", "报表", "分组", "过程", "说明", "参数"], rows: RPTDEFS.map(r => ["R" + r.id, r.name, r.grp, r.proc, r.desc,
            r.params.map((p, i) => `[%${i}] ${p.label}` + (p.opts ? "（" + p.opts.map(([k, t]) => (k || "空") + " " + t).join(" / ") + "）" : "")).join("；")])}, {wrap:["说明", "参数"], freeze:2});
      else body.innerHTML = table(await q("metaPools"), {wrap:["Descr"]});
    } catch (e) { body.innerHTML = errBox(e); }
  };
  document.querySelectorAll("#mTabs button").forEach(b => b.onclick = () => show(b.dataset.t));
  $("#mgo").onclick = () => show("tables"); $("#mq").onkeydown = e => { if (e.key === "Enter") show("tables"); };
  $("#mdl").onclick = async () => {
    $("#mdl").disabled = true;
    try { download(`成本系统说明书_${INFO.schema}`, await buildManual(), "成本系统说明书"); }
    catch (e) { toast("下载失败：" + (e.message || e)); }
    finally { $("#mdl").disabled = false; }
  };
  show("tables");
}
async function buildManual(){
  const [tabs, cols, rules, checks, tools, params, accts, pools] = await Promise.all(
    ["metaTables","metaAllColumns","metaRules","metaChecks","metaTools","metaParams","metaAccts","metaPools"].map(a => q(a, a === "metaTables" ? {text:""} : {})));
  const tabO = asObjs(tabs).filter(t => t.Layer !== "B1"), colO = asObjs(cols).filter(c => !String(c.TableName).startsWith("@"));   // B1 自定义表只在页面上查，不进说明书
  let h = `<h1>成本系统说明书</h1><p>账套 ${esc(INFO.schema)}。由成本执行台根据数据字典（MTC_CA_M_TABLE / M_COLUMN）和登记表（规则、校验、工具、参数、科目、费用池）生成，${new Date().toLocaleString("zh-CN")}。只含结构与配置，不含业务数据。</p>
<h2>一、计算流程</h2><p>入口 MTC_CA_P_RUN（账期, F 正式 / S 模拟, 场景, 操作人, USER / AI）。只做检查用 MTC_CA_P_PRECHECK。步骤：</p><ol>`
    + Object.entries(STEP).map(([k, v]) => `<li><b>${esc(k)}</b> ${esc(v)}</li>`).join("") + `</ol>
<p>每次运行先取快照（S_ 表），在快照上做计算前检查（PRE），有阻断项就停止；迭代计算物料单价、订单结转、费用分摊直到收敛，再定稿写结果（R_ 表）、执行计算后校验（POST）、新旧比对、生成凭证。同一账期 / 类型 / 场景只保留最后一次成功运行的明细；运行日志和指标快照每次都保留。</p>
<h2>二、计算规则</h2>` + htmlTable(rules, ["RuleId","Scene","Title","Descr","Basis"])
    + `<h2>三、校验</h2>` + htmlTable(checks, ["CheckId","Stage","Title","Purpose","IsBlock","Scene"], {IsBlock: v => v === "Y" ? "阻断" : ""})
    + `<h2>四、配置</h2><h3>参数</h3>` + htmlTable(params, ["ParamCode","FromFc","ToFc","Value","Descr"])
    + `<h3>科目</h3>` + htmlTable(accts, ["Usage","FromFc","ToFc","AcctCode","Descr"], {AcctCode: v => esc(acctText(v))})
    + `<h3>费用池</h3>` + htmlTable(pools, ["Kind","PoolCode","Key","Val","Descr"])
    + `<h2>五、AI 工具</h2><p>模型只能调用登记的工具，本机服务校验参数后执行；A 档只把状态和行数发给模型，金额、单价、数量和明细只在本机页面显示，出网内容写本地审计日志。</p>`
    + htmlTable(tools, ["ToolName","Title","Descr","ProcName","IsWrite","NeedConfirm","ModelOutput"])
    + `<h2>六、表与字段</h2>`;
  for (const L of ["RUN","C","M","S","R","BOOT"]) {
    const ts = tabO.filter(t => (t.Layer || "") === L); if (!ts.length) continue;
    h += `<h3>${esc(LAYER[L] || L)}</h3>`;
    for (const t of ts) {
      const cs = colO.filter(c => c.TableName === t.TableName);
      h += `<h4>${esc(t.TableName)}</h4><p>${esc(t.Descr || "")}</p><table><thead><tr><th>字段</th><th>类型</th><th>说明</th></tr></thead><tbody>`
        + cs.map(c => `<tr><td>${esc(c.ColumnName)}</td><td>${esc(c.DataType)}</td><td>${esc(c.Descr || "")}</td></tr>`).join("") + `</tbody></table>`;
    }
  }
  const other = tabO.filter(t => !["RUN","C","M","S","R","BOOT"].includes(t.Layer || ""));
  if (other.length) h += `<h3>其他</h3>` + other.map(t => `<p><b>${esc(t.TableName)}</b> ${esc(t.Descr || "")}</p>`).join("");
  return h;
}
