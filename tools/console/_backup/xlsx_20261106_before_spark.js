// 成本执行台 · xlsx.js — 导出 Excel（.xlsx）：页面里手写的生成器 saveXlsx()，不用第三方库；csv() 也走这里；列表查询条件记忆
// index.html 按顺序加载 js/ 下的脚本，共用全局作用域；加载时立即执行的代码只能用到本文件和前面文件里的名字。
"use strict";
// ---------------- 导出 Excel（.xlsx）：本页生成，不用第三方库、不经过服务器（用户 2026-10-23，替代原来的 CSV） ----------------
// 工作表：冻结表头（和页面一样冻结左侧列）、自动筛选、列宽按内容估算、分组表头合并单元格；
// 金额列为数字并带千分位两位小数（负数红色），其他数字列（单价、数量、编号）为常规数字，文字列设成文本格式（编码前导 0 不丢）。
// 页面表格导出时末尾加一行 SUBTOTAL 合计公式（在 Excel 里筛选后自动跟着变）；有小计 / 合计行的表不加，原来的小计行加粗。
const CRC_T = (() => { const t = new Uint32Array(256); for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; } return t; })();
const crc32 = b => { let c = 0xFFFFFFFF; for (let i = 0; i < b.length; i++) c = CRC_T[(c ^ b[i]) & 255] ^ (c >>> 8); return (c ^ 0xFFFFFFFF) >>> 0; };
async function deflateRaw(b){
  if (typeof CompressionStream === "undefined") return null;   // 老浏览器不压缩，文件大一些但照样能打开
  try { return new Uint8Array(await new Response(new Blob([b]).stream().pipeThrough(new CompressionStream("deflate-raw"))).arrayBuffer()); } catch (e) { return null; }
}
async function zipBlob(files, type){
  const enc = new TextEncoder(), parts = [], cd = []; let off = 0;
  for (const f of files) {
    const nm = enc.encode(f.name), data = typeof f.data === "string" ? enc.encode(f.data) : f.data, crc = crc32(data), z = await deflateRaw(data), body = z || data, meth = z ? 8 : 0;
    const h = new DataView(new ArrayBuffer(30));
    h.setUint32(0, 0x04034b50, true); h.setUint16(4, 20, true); h.setUint16(6, 0x0800, true); h.setUint16(8, meth, true); h.setUint16(12, 0x21, true);
    h.setUint32(14, crc, true); h.setUint32(18, body.length, true); h.setUint32(22, data.length, true); h.setUint16(26, nm.length, true);
    const c = new DataView(new ArrayBuffer(46));
    c.setUint32(0, 0x02014b50, true); c.setUint16(4, 20, true); c.setUint16(6, 20, true); c.setUint16(8, 0x0800, true); c.setUint16(10, meth, true); c.setUint16(14, 0x21, true);
    c.setUint32(16, crc, true); c.setUint32(20, body.length, true); c.setUint32(24, data.length, true); c.setUint16(28, nm.length, true); c.setUint32(42, off, true);
    parts.push(new Uint8Array(h.buffer), nm, body); cd.push(new Uint8Array(c.buffer), nm);
    off += 30 + nm.length + body.length;
  }
  const cdLen = cd.reduce((a, x) => a + x.length, 0), e = new DataView(new ArrayBuffer(22));
  e.setUint32(0, 0x06054b50, true); e.setUint16(8, files.length, true); e.setUint16(10, files.length, true); e.setUint32(12, cdLen, true); e.setUint32(16, off, true);
  return new Blob([...parts, ...cd, new Uint8Array(e.buffer)], {type});
}
const xEsc = s => String(s).replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f￾￿]/g, "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const xCol = n => { let s = ""; for (n++; n; n = Math.floor((n - 1) / 26)) s = String.fromCharCode(65 + (n - 1) % 26) + s; return s; };
const xWid = s => { let n = 0; for (const ch of String(s)) n += ch.charCodeAt(0) > 255 ? 2 : 1; return n; };
// 样式序号：1 表头、2 金额、3 文本、4 合计行金额、5 加粗文本、6 加粗常规数字
const XSTYLES = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="1"><numFmt numFmtId="164" formatCode="#,##0.00;[Red]\\-#,##0.00"/></numFmts>
<fonts count="2"><font><sz val="11"/><name val="等线"/><family val="2"/><charset val="134"/></font><font><b/><sz val="11"/><name val="等线"/><family val="2"/><charset val="134"/></font></fonts>
<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFEDEDED"/><bgColor indexed="64"/></patternFill></fill></fills>
<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left style="thin"><color rgb="FFC8C8C8"/></left><right style="thin"><color rgb="FFC8C8C8"/></right><top style="thin"><color rgb="FFC8C8C8"/></top><bottom style="thin"><color rgb="FFC8C8C8"/></bottom><diagonal/></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="7"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
<xf numFmtId="49" fontId="1" fillId="2" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>
<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
<xf numFmtId="49" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
<xf numFmtId="164" fontId="1" fillId="2" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1"/>
<xf numFmtId="49" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/>
<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>
<cellStyles count="1"><cellStyle name="常规" xfId="0" builtinId="0"/></cellStyles></styleSheet>`;
// sh：{name, head:[[分组|null, 列名]], kind:["n" 金额 | "g" 常规数字 | "t" 文本], rows:[[值]], bold:Set(行序号), freeze, total}
function xSheet(sh){
  const nc = sh.head.length, grouped = sh.head.some(h => h[0]), hr = grouped ? 2 : 1, L = sh.head.map((h, k) => xCol(k));
  const merges = [], out = [];
  const tc = (ref, s, v) => `<c r="${ref}" s="${s}" t="inlineStr"><is><t xml:space="preserve">${xEsc(v)}</t></is></c>`;
  if (grouped) {
    let r1 = "", r2 = "";
    for (let k = 0; k < nc; k++) {
      const g = sh.head[k][0];
      if (!g) { r1 += tc(L[k] + 1, 1, sh.head[k][1]); r2 += `<c r="${L[k]}2" s="1"/>`; merges.push(`${L[k]}1:${L[k]}2`); continue; }
      let n = 1; while (k + n < nc && sh.head[k + n][0] === g) n++;
      for (let j = k; j < k + n; j++) { r1 += j === k ? tc(L[j] + 1, 1, g) : `<c r="${L[j]}1" s="1"/>`; r2 += tc(L[j] + 2, 1, sh.head[j][1]); }
      if (n > 1) merges.push(`${L[k]}1:${L[k + n - 1]}1`);
      k += n - 1;
    }
    out.push(`<row r="1">${r1}</row>`, `<row r="2">${r2}</row>`);
  } else out.push(`<row r="1">${sh.head.map((h, k) => tc(L[k] + 1, 1, h[1])).join("")}</row>`);
  const wid = sh.head.map(h => xWid(h[1]) + 2);
  sh.rows.forEach((x, ri) => {
    const rn = ri + hr + 1, b = sh.bold && sh.bold.has(ri); let s = "";
    for (let k = 0; k < nc; k++) {
      const v = x[k]; if (blank(v)) continue;
      if (typeof v === "number" && isFinite(v)) {
        s += `<c r="${L[k]}${rn}" s="${sh.kind[k] === "n" ? (b ? 4 : 2) : (b ? 6 : 0)}"><v>${v}</v></c>`;
        if (ri < 500) wid[k] = Math.max(wid[k], String(Math.round(Math.abs(v))).length * 1.35 + 5);
      } else {
        s += tc(L[k] + rn, b ? 5 : 3, v);
        if (ri < 500) wid[k] = Math.max(wid[k], xWid(v) + 1);
      }
    }
    out.push(`<row r="${rn}">${s}</row>`);
  });
  const last = hr + sh.rows.length;
  if (sh.total && sh.rows.length > 1 && sh.kind.includes("n")) {
    const rn = last + 1, lab = sh.kind.findIndex(k => k !== "n");
    out.push(`<row r="${rn}">` + sh.head.map((h, k) => sh.kind[k] === "n" ? `<c r="${L[k]}${rn}" s="4"><f>SUBTOTAL(9,${L[k]}${hr + 1}:${L[k]}${last})</f></c>` : k === lab ? tc(L[k] + rn, 5, "合计") : `<c r="${L[k]}${rn}" s="4"/>`).join("") + `</row>`);
  }
  const fz = Math.min(sh.freeze || 0, nc - 1), tl = xCol(fz) + (hr + 1);
  const pane = fz ? `<pane xSplit="${fz}" ySplit="${hr}" topLeftCell="${tl}" activePane="bottomRight" state="frozen"/><selection pane="bottomRight" activeCell="${tl}" sqref="${tl}"/>`
    : `<pane ySplit="${hr}" topLeftCell="${tl}" activePane="bottomLeft" state="frozen"/><selection pane="bottomLeft" activeCell="${tl}" sqref="${tl}"/>`;
  const flt = `${L[0]}${hr}:${L[nc - 1]}${Math.max(last, hr)}`;
  return {flt, xml: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">`
    + `<sheetViews><sheetView workbookViewId="0">${pane}</sheetView></sheetViews><sheetFormatPr defaultRowHeight="15"/>`
    + `<cols>${wid.map((w, k) => `<col min="${k + 1}" max="${k + 1}" width="${Math.min(60, Math.max(6, Math.round(w)))}" customWidth="1"/>`).join("")}</cols>`
    + `<sheetData>${out.join("")}</sheetData><autoFilter ref="${flt}"/>`
    + (merges.length ? `<mergeCells count="${merges.length}">${merges.map(m => `<mergeCell ref="${m}"/>`).join("")}</mergeCells>` : "")
    + `</worksheet>`};
}
async function saveXlsx(sheets, name){
  const used = new Set();
  const nm = sheets.map((s, i) => { let n = String(s.name || "Sheet" + (i + 1)).replace(/[\[\]:*?\/\\]/g, "_").slice(0, 31) || "Sheet" + (i + 1); while (used.has(n)) n = n.slice(0, 28) + "_" + i; used.add(n); return n; });
  const xs = sheets.map(xSheet);
  const files = [
    {name:"[Content_Types].xml", data:`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>${xs.map((x, i) => `<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>`).join("")}</Types>`},
    {name:"_rels/.rels", data:`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>`},
    {name:"xl/workbook.xml", data:`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><bookViews><workbookView/></bookViews><sheets>${nm.map((n, i) => `<sheet name="${xEsc(n)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>`).join("")}</sheets><definedNames>${xs.map((x, i) => `<definedName name="_xlnm._FilterDatabase" localSheetId="${i}" hidden="1">'${xEsc(nm[i].replace(/'/g, "''"))}'!${x.flt.replace(/([A-Z]+)(\d+)/g, "$$$1$$$2")}</definedName>`).join("")}</definedNames></workbook>`},
    {name:"xl/_rels/workbook.xml.rels", data:`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${xs.map((x, i) => `<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>`).join("")}<Relationship Id="rId${xs.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>`},
    {name:"xl/styles.xml", data:XSTYLES},
    ...xs.map((x, i) => ({name:`xl/worksheets/sheet${i + 1}.xml`, data:x.xml}))];
  const blob = await zipBlob(files, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
  const a = document.createElement("a"); a.href = URL.createObjectURL(blob); a.download = String(name).replace(/[\\/:*?"<>|]+/g, "_") + ".xlsx"; a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 2000);
}
// 金额列（千分位两位小数）：可合计的数字列，数量类除外
const xAmt = c => !noFmt(c) && !NOSUM.test(c) && !/Qty|数量|单价|占比|比例|层级|层次|Depth|%$/i.test(c);
// 查询结果（{columns, rows}）→ 工作表：列名取中文（含“·”时拆成两行表头），代码列带中文名
function xFromResult(r, name){
  const num = r.columns.map((c, i) => r.rows.every(x => blank(x[i]) || typeof x[i] === "number"));
  return {name, head: r.columns.map(c => { const l = LABEL[c] || c, k = l.indexOf("·"); return k > 0 ? [l.slice(0, k), l.slice(k + 1)] : [null, l]; }),
    kind: r.columns.map((c, i) => num[i] ? (xAmt(c) ? "n" : "g") : "t"),
    rows: r.rows.map(x => x.map((v, i) => blank(v) ? null : num[i] ? v : String(codeText(r.columns[i], v) ?? ""))), freeze: 1};
}
// 页面表格 → 工作表：当前显示的列和行（有选中的行时只取选中的行）、页面的列名和冻结列
function xFromTable(st, name){
  const r = st.r, cols = tblCols(st), all = tblRows(st), sel = all.filter(i => st.pick.has(i)), rows = sel.length ? sel : all, rc = st.opt.rowCls;
  const bold = new Set(); rows.forEach((ri, k) => { if (rc && rc(r.rows[ri])) bold.add(k); });
  return {name, picked: !!sel.length, head: cols.map(i => colHead(st, r.columns[i])),
    kind: cols.map(i => st.num[i] ? (sumCol(st, i) && xAmt(r.columns[i]) ? "n" : "g") : "t"),
    rows: rows.map(ri => cols.map(i => { const v = r.rows[ri][i]; return blank(v) ? null : st.num[i] ? v : cellText(st, r.rows[ri], i); })),
    bold, total: !rc && st.opt.sum !== false, freeze: Math.min(st.opt.freeze ?? 1, 3, Math.max(cols.length - 1, 0))};
}
function csv(r, name){   // 名字沿用：各页“导出”按钮都调用它，现在导出 Excel
  saveXlsx([xFromResult(r, String(name).slice(0, 31))], name).catch(e => toast("导出失败：" + (e.message || e)));
}
// 各列表的查询条件（按列表标题记），切换页签、换运行、刷新页面后带回来
let SQ = {}; try { SQ = JSON.parse(localStorage.getItem("cc.sq") || "{}") || {}; } catch (e) {}
const sqGet = k => SQ[k] || "";
const sqSet = (k, v) => { if (v) SQ[k] = v; else delete SQ[k]; try { localStorage.setItem("cc.sq", JSON.stringify(SQ)); } catch (e) {} };
const errBox = e => `<div class="msg err">${esc(e.message || e)}</div>`;
