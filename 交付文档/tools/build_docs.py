#!/usr/bin/env python3
# 把 交付文档/src/*.md 生成 Word + PDF（dist/）。Markdown 只用手册需要的子集：标题、段落、列表、表格、引用、图片。
#   ![说明](shot:id)      执行台截图，取 截图/id.png；还没有时放占位框
#   ![说明](diagram:id)   流程示意图，本文件里的 DIAGRAMS 现画，不含业务数据
#   【待提供：xxx】       单独一行，占位框（B1 前台截图由用户提供）
# 用法：python3 交付文档/tools/build_docs.py [--only 00]
import argparse, html, os, re, sys
from docx import Document
from docx.enum.section import WD_ORIENT
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.abspath(os.path.join(HERE, '..'))
SRC, SHOTS, DIST = (os.path.join(BASE, x) for x in ('src', '截图', 'dist'))
COMPANY, VERSION = '【公司名称】', '样稿 V0.1'
FONT, MONO = '微软雅黑', 'Consolas'
BLUE, GREY = RGBColor(0x1F, 0x4E, 0x79), RGBColor(0x66, 0x66, 0x66)

BOX = 'display:inline-block;padding:14px 16px;border:1.5px solid #1F4E79;border-radius:8px;background:#EEF4FA;color:#17365D;font-size:20px;line-height:1.35;text-align:center;min-width:112px'
ARR = '<span style="color:#1F4E79;font-size:26px;padding:0 9px">→</span>'
def _flow(rows):
    return '<div style="display:inline-block;padding:18px;font-family:PingFang SC,sans-serif;background:#fff">' + ''.join(
        '<div style="display:flex;align-items:center;margin:10px 0">' + ARR.join(f'<span style="{BOX}{";background:#FFF4E5;border-color:#C55A11;color:#843C0C" if t.startswith("!") else ""}">{t.lstrip("!")}</span>' for t in r) + '</div>' for r in rows) + '</div>'
DIAGRAMS = {
    'flow': _flow([['B1 准备<br><small>单据、工时、配置</small>', '只做检查<br><small>处理阻断项</small>', '正式计算', '计算后复核'],
                   ['财务对账', '!需要调整时<br><small>重估后重新计算</small>', '生成凭单', 'B1 过账'],
                   ['重新对账', '成本报表归档', 'B1 锁定账期']]),
    'period': _flow([['未计算', '已计算<br><small>可反复重算</small>', '已生成凭单', '已锁定']])
             + '<div style="font:18px PingFang SC,sans-serif;color:#555;padding:0 18px 16px;background:#fff">正式计算：未计算 → 已计算　生成凭单：已计算 → 已生成凭单　撤销凭单：已生成凭单 → 已计算　B1 锁账期：已生成凭单 → 已锁定</div>',
}

def parse(path):
    t = open(path, encoding='utf-8').read()
    meta = {}
    m = re.match(r'---\n(.*?)\n---\n', t, re.S)
    if m:
        meta = dict(x.split(': ', 1) for x in m.group(1).splitlines()); t = t[m.end():]
    L, i, out = t.split('\n'), 0, []
    while i < len(L):
        s = L[i]
        if not s.strip(): i += 1; continue
        if s.startswith('#'):
            n = len(s) - len(s.lstrip('#')); out.append(('h', n, s[n:].strip())); i += 1
        elif re.match(r'!\[', s):
            c, u = re.match(r'!\[(.*?)\]\((.*?)\)', s).groups(); out.append(('img', c, u)); i += 1
        elif s.startswith('【待提供'):
            out.append(('todo', s.strip('【】'))); i += 1
        elif s.startswith('> '):
            out.append(('quote', s[2:])); i += 1
        elif s.startswith('|'):
            rows = []
            while i < len(L) and L[i].startswith('|'):
                rows.append([c.strip() for c in L[i].strip().strip('|').split('|')]); i += 1
            out.append(('table', rows[0], rows[2:]))
        elif re.match(r'(\d+\.|-) ', s):
            ord_ = s[0].isdigit(); items = []
            while i < len(L) and re.match(r'(\d+\.|-) ', L[i]):
                items.append(re.sub(r'^(\d+\.|-) ', '', L[i])); i += 1
            out.append(('ol' if ord_ else 'ul', items))
        else:
            out.append(('p', s)); i += 1
    return meta, out

# ---------------- 图片 ----------------
def render_diagrams():
    from playwright.sync_api import sync_playwright
    os.makedirs(SHOTS, exist_ok=True)
    with sync_playwright() as pw:
        b = pw.chromium.launch(); pg = b.new_page(device_scale_factor=2, viewport={'width': 1400, 'height': 500})
        for k, h in DIAGRAMS.items():
            pg.set_content(f'<body style="margin:0;background:#fff"><div id="d" style="display:inline-block">{h}</div></body>')
            pg.locator('#d').screenshot(path=os.path.join(SHOTS, f'diagram_{k}.png'))
        b.close()

def img_path(u):
    k, v = u.split(':', 1)
    p = os.path.join(SHOTS, ('diagram_' + v if k == 'diagram' else v) + '.png')
    return p if os.path.isfile(p) else None

# ---------------- Word ----------------
def set_font(run, name=FONT):
    run.font.name = name
    rf = run._element.get_or_add_rPr().get_or_add_rFonts()
    for a in ('w:eastAsia', 'w:ascii', 'w:hAnsi', 'w:cs'): rf.set(qn(a), name)

def inline(par, text, size=None, color=None):
    for tok in re.split(r'(\*\*.+?\*\*|`[^`]+`)', text):
        if not tok: continue
        if tok.startswith('**'): r = par.add_run(tok[2:-2]); r.bold = True; set_font(r)
        elif tok.startswith('`'): r = par.add_run(tok[1:-1]); set_font(r, MONO)
        else: r = par.add_run(tok); set_font(r)
        if size: r.font.size = Pt(size)
        if color is not None: r.font.color.rgb = color

def shade(cell_or_par_pr, fill):
    e = OxmlElement('w:shd'); e.set(qn('w:val'), 'clear'); e.set(qn('w:color'), 'auto'); e.set(qn('w:fill'), fill)
    cell_or_par_pr.append(e)

def field(par, code):
    for t, x in (('begin', None), (None, code), ('separate', None), ('text', '1'), ('end', None)):
        r = par.add_run(); set_font(r); r.font.size = Pt(9)
        if t == 'text': r.text = x
        elif t is None:
            e = OxmlElement('w:instrText'); e.set(qn('xml:space'), 'preserve'); e.text = x; r._r.append(e)
        else:
            e = OxmlElement('w:fldChar'); e.set(qn('w:fldCharType'), t); r._r.append(e)

def new_num(doc, style):
    """每个编号列表从 1 开始：基于样式的编号定义新建一个带重新起始的 w:num。"""
    np_ = doc.part.numbering_part.element
    aid = None
    base = doc.styles[style].element.pPr.numPr.numId.val
    for n in np_.findall(qn('w:num')):
        if n.numId == base: aid = n.abstractNumId.val
    num = np_.add_num(aid); o = num.add_lvlOverride(ilvl=0); o.add_startOverride(1)
    return num.numId

def col_widths(head, rows, total):
    w = [max(sum(2 if ord(c) > 255 else 1 for c in re.sub(r'[*`]', '', r[i])) for r in [head] + rows) for i in range(len(head))]
    w = [min(max(x, 6), 44) for x in w]
    s = sum(w)
    return [total * x / s for x in w]

def docx_table(doc, head, rows, total):
    t = doc.add_table(rows=1, cols=len(head)); t.style = 'Table Grid'; t.alignment = WD_TABLE_ALIGNMENT.CENTER; t.autofit = False
    ws = col_widths(head, rows, total)
    trPr = t.rows[0]._tr.get_or_add_trPr(); e = OxmlElement('w:tblHeader'); trPr.append(e)
    for i, h in enumerate(head):
        c = t.rows[0].cells[i]; c.width = Cm(ws[i]); shade(c._tc.get_or_add_tcPr(), '1F4E79')
        p = c.paragraphs[0]; r = p.add_run(h); set_font(r); r.bold = True; r.font.size = Pt(9.5); r.font.color.rgb = RGBColor(255, 255, 255)
    for x in rows:
        cs = t.add_row(); tr = cs._tr.get_or_add_trPr(); tr.append(OxmlElement('w:cantSplit'))
        for i, v in enumerate(x):
            c = cs.cells[i]; c.width = Cm(ws[i]); inline(c.paragraphs[0], v, size=9.5)
    for g, w in zip(t._tbl.tblGrid.findall(qn('w:gridCol')), ws): g.set(qn('w:w'), str(int(w * 567)))
    sp = doc.add_paragraph(); sp.paragraph_format.space_after = Pt(2)

def build_docx(meta, blocks, out, landscape=False):
    d = Document(); s = d.sections[0]
    s.page_width, s.page_height = (Cm(29.7), Cm(21)) if landscape else (Cm(21), Cm(29.7))
    if landscape: s.orientation = WD_ORIENT.LANDSCAPE
    m = 1.5 if landscape else 2.2
    s.left_margin = s.right_margin = Cm(m); s.top_margin = Cm(1.6 if landscape else 2.4); s.bottom_margin = Cm(1.4 if landscape else 2.0)
    W = (29.7 if landscape else 21) - 2 * m
    st = d.styles['Normal']; st.font.name = FONT; st.font.size = Pt(10.5)
    st.element.get_or_add_rPr().get_or_add_rFonts().set(qn('w:eastAsia'), FONT)
    st.paragraph_format.line_spacing = 1.3; st.paragraph_format.space_after = Pt(6)
    for name, sz, bf, af in (('Heading 1', 18, 0, 12), ('Heading 2', 13.5, 14, 6), ('Heading 3', 11.5, 10, 4)):
        h = d.styles[name]; h.font.name = FONT; h.font.size = Pt(sz); h.font.bold = True; h.font.color.rgb = BLUE
        rf = h.element.get_or_add_rPr().get_or_add_rFonts()
        for a in ('w:eastAsia', 'w:ascii', 'w:hAnsi'): rf.set(qn(a), FONT)
        for a in ('w:asciiTheme', 'w:eastAsiaTheme', 'w:hAnsiTheme', 'w:cstheme'):
            if rf.get(qn(a)) is not None: del rf.attrib[qn(a)]
        h.paragraph_format.space_before = Pt(bf); h.paragraph_format.space_after = Pt(af); h.paragraph_format.keep_with_next = True
    d.styles['Heading 1'].paragraph_format.page_break_before = not landscape
    d.core_properties.title = meta.get('title', ''); d.core_properties.author = COMPANY; d.core_properties.comments = ''
    fp = s.footer.paragraphs[0]; fp.alignment = WD_ALIGN_PARAGRAPH.CENTER; field(fp, 'PAGE')
    hp = s.header.paragraphs[0]; hp.alignment = WD_ALIGN_PARAGRAPH.RIGHT; inline(hp, f"{meta.get('title', '')}　{VERSION}", size=8.5, color=GREY)
    if landscape:
        p = d.add_paragraph(); inline(p, '**' + meta['title'] + '**', size=18, color=BLUE); p.paragraph_format.space_after = Pt(0)
        p = d.add_paragraph(); inline(p, meta.get('subtitle', ''), size=9.5, color=GREY)
    else:
        s.different_first_page_header_footer = True
        for _ in range(8): d.add_paragraph()
        p = d.add_paragraph(); p.alignment = WD_ALIGN_PARAGRAPH.CENTER; inline(p, '**' + meta['title'] + '**', size=30, color=BLUE)
        p = d.add_paragraph(); p.alignment = WD_ALIGN_PARAGRAPH.CENTER; inline(p, meta.get('subtitle', ''), size=13, color=GREY)
        for _ in range(12): d.add_paragraph()
        for x in (COMPANY, '版本：' + VERSION):
            p = d.add_paragraph(); p.alignment = WD_ALIGN_PARAGRAPH.CENTER; inline(p, x, size=11)
        p = d.add_paragraph(); p.add_run().add_break(WD_BREAK.PAGE)
        p = d.add_paragraph(); inline(p, '**目录**', size=18, color=BLUE)
        p = d.add_paragraph(); r = p.add_run()
        for t, x in (('begin', None), (None, 'TOC \\o "1-2" \\h \\z \\u'), ('separate', None), ('t', '在 Word 中右键此处“更新域”生成目录'), ('end', None)):
            if t == 't': r2 = p.add_run(x); set_font(r2); continue
            r2 = p.add_run()
            if t is None:
                e = OxmlElement('w:instrText'); e.set(qn('xml:space'), 'preserve'); e.text = x
            else:
                e = OxmlElement('w:fldChar'); e.set(qn('w:fldCharType'), t)
            r2._r.append(e)
        u = OxmlElement('w:updateFields'); u.set(qn('w:val'), 'true'); d.settings.element.append(u)
    fig = 0
    def box(text):
        p = d.add_paragraph(); p.alignment = WD_ALIGN_PARAGRAPH.CENTER; shade(p._p.get_or_add_pPr(), 'FFF2CC'); inline(p, text, size=10, color=RGBColor(0x7F, 0x60, 0))
    for b in blocks:
        k = b[0]
        if k == 'h': d.add_heading(b[2], level=min(b[1], 3))
        elif k == 'p': inline(d.add_paragraph(), b[1])
        elif k == 'quote':
            p = d.add_paragraph(); shade(p._p.get_or_add_pPr(), 'EEF4FA'); p.paragraph_format.left_indent = Cm(0.2); inline(p, b[1], size=10)
        elif k in ('ol', 'ul'):
            sty = 'List Number' if k == 'ol' else 'List Bullet'; nid = new_num(d, sty) if k == 'ol' else None
            for x in b[1]:
                p = d.add_paragraph(style=sty); inline(p, x); p.paragraph_format.space_after = Pt(3)
                if nid:
                    pr = p._p.get_or_add_pPr().get_or_add_numPr(); pr.get_or_add_numId().val = nid; pr.get_or_add_ilvl().val = 0
        elif k == 'table': docx_table(d, b[1], b[2], W)
        elif k == 'todo': box('【' + b[1] + '】')
        elif k == 'img':
            fig += 1; p0 = img_path(b[2])
            if p0:
                p = d.add_paragraph(); p.alignment = WD_ALIGN_PARAGRAPH.CENTER; p.paragraph_format.keep_with_next = True
                p.add_run().add_picture(p0, width=Cm(W if 'shot:' in b[2] else min(W, 15)))
            else: box(f'【待实机截图：{b[1]}】')
            p = d.add_paragraph(); p.alignment = WD_ALIGN_PARAGRAPH.CENTER; inline(p, f'图 {fig}　{b[1]}', size=9, color=GREY)
    d.save(out)

# ---------------- PDF ----------------
CSS = '''@page{size:A4;margin:22mm 20mm 18mm}
body{font:10.5pt/1.6 "PingFang SC","Microsoft YaHei",sans-serif;color:#222;margin:0}
h1{font-size:18pt;color:#1F4E79;break-before:page;margin:0 0 10pt}h2{font-size:13.5pt;color:#1F4E79;margin:14pt 0 6pt;break-after:avoid}
table{border-collapse:collapse;width:100%;margin:6pt 0 10pt;font-size:9.5pt}th{background:#1F4E79;color:#fff;text-align:left}th,td{border:1px solid #BFC9D4;padding:3pt 5pt;vertical-align:top}tr{break-inside:avoid}thead{display:table-header-group}
code{font:9.5pt Menlo,Consolas,monospace}blockquote{margin:8pt 0;padding:6pt 9pt;background:#EEF4FA;border-left:3px solid #1F4E79;font-size:10pt}
figure{margin:8pt 0;text-align:center;break-inside:avoid}figure img{max-width:100%}figcaption{font-size:9pt;color:#666}.todo{background:#FFF2CC;color:#7F6000;text-align:center;padding:14pt;font-size:10pt;margin:6pt 0}
.cover{height:240mm;display:flex;flex-direction:column;justify-content:center;text-align:center}.cover h2{font-size:30pt;margin:0 0 8pt}.cover p{color:#666;font-size:13pt}.cover .m{margin-top:90mm;color:#222;font-size:11pt}
.toc{break-before:page}.toc div{margin:3pt 0}.toc .l2{padding-left:16pt;color:#555;font-size:9.5pt}.toc a{color:inherit;text-decoration:none}
.land h1{break-before:auto}'''
def inline_h(s):
    s = html.escape(s, quote=False)
    s = re.sub(r'\*\*(.+?)\*\*', r'<b>\1</b>', s)
    return re.sub(r'`([^`]+)`', r'<code>\1</code>', s)

def build_html(meta, blocks, landscape=False):
    o, toc, fig, hid = [], [], 0, 0
    for b in blocks:
        k = b[0]
        if k == 'h':
            hid += 1; o.append(f'<h{b[1]} id="h{hid}">{inline_h(b[2])}</h{b[1]}>')
            if b[1] <= 2: toc.append(f'<div class="l{b[1]}"><a href="#h{hid}">{inline_h(b[2])}</a></div>')
        elif k == 'p': o.append(f'<p>{inline_h(b[1])}</p>')
        elif k == 'quote': o.append(f'<blockquote>{inline_h(b[1])}</blockquote>')
        elif k in ('ol', 'ul'): o.append(f'<{k}>' + ''.join(f'<li>{inline_h(x)}</li>' for x in b[1]) + f'</{k}>')
        elif k == 'table':
            o.append('<table><thead><tr>' + ''.join(f'<th>{inline_h(x)}</th>' for x in b[1]) + '</tr></thead><tbody>'
                     + ''.join('<tr>' + ''.join(f'<td>{inline_h(c)}</td>' for c in r) + '</tr>' for r in b[2]) + '</tbody></table>')
        elif k == 'todo': o.append(f'<div class="todo">【{inline_h(b[1])}】</div>')
        elif k == 'img':
            fig += 1; p = img_path(b[2])
            o.append('<figure>' + (f'<img src="file://{p}">' if p else f'<div class="todo">【待实机截图：{inline_h(b[1])}】</div>') + f'<figcaption>图 {fig}　{inline_h(b[1])}</figcaption></figure>')
    t = html.escape(meta.get('title', ''))
    if landscape:
        head = f'<h1 style="margin:0">{t}</h1><p style="color:#666;margin:0 0 4pt;font-size:9.5pt">{html.escape(meta.get("subtitle", ""))}</p>'
        css = CSS.replace('size:A4;margin:22mm 20mm 18mm', 'size:A4 landscape;margin:11mm 14mm 10mm') + 'body{font-size:9.5pt;line-height:1.35}table{font-size:8.5pt}th,td{padding:1.5pt 4pt}'
    else:
        head = f'<div class="cover"><h2>{t}</h2><p>{html.escape(meta.get("subtitle", ""))}</p><div class="m">{COMPANY}<br>版本：{VERSION}</div></div><div class="toc"><h2>目录</h2>{"".join(toc)}</div>'
        css = CSS
    return f'<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>{t}</title><style>{css}</style></head><body class="{"land" if landscape else ""}">{head}{"".join(o)}</body></html>'

def build_pdf(items):
    from playwright.sync_api import sync_playwright
    with sync_playwright() as pw:
        b = pw.chromium.launch(); pg = b.new_page()
        for h, out, land, title in items:
            f = out[:-4] + '.tmp.html'; open(f, 'w', encoding='utf-8').write(h)
            pg.goto('file://' + f); pg.wait_for_load_state('networkidle')
            foot = '<div style="font-size:8px;width:100%;text-align:center;color:#888"><span class="pageNumber"></span></div>'
            pg.pdf(path=out, prefer_css_page_size=True, print_background=True, display_header_footer=not land, header_template='<span></span>', footer_template=foot)
            os.remove(f)
        b.close()

def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--only', default=''); a = ap.parse_args()
    os.makedirs(DIST, exist_ok=True); render_diagrams()
    todo = []
    for f in sorted(os.listdir(SRC)):
        if not f.endswith('.md') or f.startswith('_') or (a.only and not f.startswith(a.only)): continue
        meta, blocks = parse(os.path.join(SRC, f))
        land = f.startswith('00')
        out = os.path.join(DIST, meta['title'])
        build_docx(meta, blocks, out + '.docx', land)
        todo.append((build_html(meta, blocks, land), out + '.pdf', land, meta['title']))
        miss = sum(1 for b in blocks if b[0] == 'img' and not img_path(b[2]))
        print(f"{meta['title']}：图 {sum(1 for b in blocks if b[0] == 'img')}，缺 {miss}，B1 占位 {sum(1 for b in blocks if b[0] == 'todo')}")
    build_pdf(todo)

if __name__ == '__main__':
    main()
