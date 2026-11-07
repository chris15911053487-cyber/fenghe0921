#!/usr/bin/env python3
# 把 交付文档/src/*.md 生成执行台“使用手册”页的数据 tools/console/js/guidedata.js（用户 2026-11-07：手册放进执行台左侧菜单，不再输出 Word / PDF）。
# Markdown 子集同 build_docs.py：标题、段落、列表、表格、引用、图片，另加：
#   ![说明](shot:id)      执行台截图，页面取 img/id.png（服务从 console/img/ 或 交付文档/截图/ 读），没有时显示占位框
#   ![说明](diagram:id)   流程示意图，本文件 DIAGRAMS 现画成 HTML，跟随执行台主题
#   【待提供：xxx】       单独一行，占位框（B1 前台截图由用户提供）
#   【实时：checks】      单独一行，页面打开时从登记表现查：checks 校验、rules 计算规则、params 计算参数、reports 成本报表
#   《文档名》            链到同名文档；“第 N 章”“见 N.N”链到本文档的标题
# 以 _ 开头的文件不进页面（_内部核对表.md）。用法：python3 交付文档/tools/build_web.py
import html, json, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.abspath(os.path.join(HERE, '..'))
SRC = os.path.join(BASE, 'src')
OUT = os.path.abspath(os.path.join(BASE, '..', 'tools', 'console', 'js', 'guidedata.js'))

def _flow(rows, foot=''):
    def box(t):
        warn = t.startswith('!'); t = t.lstrip('!')
        return f'<span class="gd-box{" warn" if warn else ""}">{t}</span>'
    return '<div class="gd-flow">' + ''.join('<div class="gd-frow">' + '<i>→</i>'.join(box(t) for t in r) + '</div>' for r in rows) \
        + (f'<div class="hint">{foot}</div>' if foot else '') + '</div>'
DIAGRAMS = {
    'flow': _flow([['B1 准备<small>单据、工时、配置</small>', '只做检查<small>处理阻断项</small>', '正式计算', '计算后复核'],
                   ['财务对账', '!需要调整时<small>重估后重新计算</small>', '生成凭单', 'B1 过账'],
                   ['重新对账', '成本报表归档', 'B1 锁定账期']]),
    'period': _flow([['未计算', '已计算<small>可反复重算</small>', '已生成凭单', '已锁定']],
                    '正式计算：未计算 → 已计算　生成凭单：已计算 → 已生成凭单　撤销凭单：已生成凭单 → 已计算　B1 锁账期：已生成凭单 → 已锁定'),
    'calc': _flow([['取快照<small>截至期末的单据</small>', '计算前检查<small>有阻断就停止</small>', '固定价格<small>采购、发票差额、重估</small>'],
                   ['!迭代计算<small>费用池 → 分摊 → 逐级定价</small>', '收敛判断<small>单价不再变化</small>', '写结果'],
                   ['计算后校验', '生成凭证底稿', '财务对账']]),
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
        elif s.startswith('【实时：'):
            out.append(('live', s.strip('【】').split('：', 1)[1].strip())); i += 1
        elif s.startswith('> '):
            out.append(('quote', s[2:])); i += 1
        elif s.startswith('|'):
            rows = []
            while i < len(L) and L[i].startswith('|'):
                rows.append([c.strip() for c in L[i].strip().strip('|').split('|')]); i += 1
            out.append(('table', rows[0], rows[2:]))
        elif s.startswith('```'):
            j = i + 1
            while j < len(L) and not L[j].startswith('```'): j += 1
            out.append(('pre', '\n'.join(L[i + 1:j]))); i = j + 1
        elif re.match(r'(\d+\.|-) ', s):
            ord_ = s[0].isdigit(); items = []
            while i < len(L) and re.match(r'(\d+\.|-) ', L[i]):
                items.append(re.sub(r'^(\d+\.|-) ', '', L[i])); i += 1
            out.append(('ol' if ord_ else 'ul', items))
        else:
            out.append(('p', s)); i += 1
    return meta, out

CKBOX = '<input type="checkbox" class="gd-ck">'

def build():
    files = sorted(f for f in os.listdir(SRC) if f.endswith('.md') and not f.startswith('_'))
    docs = [(f.split('_', 1)[0], *parse(os.path.join(SRC, f))) for f in files]
    titles = {m.get('title', ''): d for d, m, _ in docs}
    def doc_of(name):   # 《月结操作手册》→ 标题含这几个字的文档
        for t, d in titles.items():
            if name in t or t in name: return d
        return None
    TOC, ANC = {}, {}
    for did, meta, blocks in docs:   # 先给全部文档的标题编号，正文里的“第 N 章”“见 N.N”才能链过去
        toc, anc, n = [], {}, 0
        for b in blocks:
            if b[0] == 'h' and b[1] <= 2:
                n += 1; hid = f'g{did}-{n}'; toc.append({'id': hid, 't': b[2], 'lv': b[1]})
                m = re.match(r'第 (\d+) 章|(\d+\.\d+) ', b[2] + ' ')
                if m: anc[m.group(1) or m.group(2)] = hid
        TOC[did], ANC[did] = toc, anc
    res = []
    for did, meta, blocks in docs:
        toc = TOC[did]
        # 本文档没有章节编号时（月结清单），“第 N 章”链到 refdoc 指定的文档
        ref = meta.get('refdoc') if not ANC[did] else None
        anchors = ANC.get(ref, {}) if ref else ANC[did]
        dattr = f' data-doc="{ref}"' if ref else ''
        def inline(s, links=True):
            s = html.escape(s, quote=False)
            s = re.sub(r'\*\*(.+?)\*\*', r'<b>\1</b>', s)
            s = re.sub(r'`([^`]+)`', r'<code>\1</code>', s)
            if not links: return s
            # 《某手册》第 N 章：整段链到那份手册的那一章
            def xref(m):
                d = doc_of(m.group(1)); a = ANC.get(d, {}).get(m.group(2)) if d else None
                return f'<a class="gd-ln" data-doc="{d}" data-sec="{a}">《{m.group(1)}》第 {m.group(2)} 章</a>' if a else m.group(0)
            s = re.sub(r'《(.+?)》第 (\d+) 章', xref, s)
            s = re.sub(r'(<a class="gd-ln"[^>]*>.*?</a>)|《(.+?)》', lambda m: m.group(1) or (f'<a class="gd-ln" data-doc="{doc_of(m.group(2))}">《{m.group(2)}》</a>' if doc_of(m.group(2)) else m.group(0)), s)
            # 已经是链接的部分不再处理“第 N 章”
            parts = re.split(r'(<a class="gd-ln".*?</a>)', s)
            for i in range(0, len(parts), 2): parts[i] = local(parts[i])
            return ''.join(parts)
        def local(s):
            s = re.sub(r'第 (\d+)(、(\d+))? 章', lambda m: ''.join([f'<a class="gd-ln"{dattr} data-sec="{anchors[m.group(1)]}">第 {m.group(1)}</a>' if m.group(1) in anchors else f'第 {m.group(1)}',
                       (f'、<a class="gd-ln"{dattr} data-sec="{anchors[m.group(3)]}">{m.group(3)}</a>' if m.group(3) in anchors else (m.group(2) or '')), ' 章']), s)
            s = re.sub(r'见 (\d+\.\d+)(?![\d.])', lambda m: f'见 <a class="gd-ln"{dattr} data-sec="{anchors[m.group(1)]}">{m.group(1)}</a>' if m.group(1) in anchors else m.group(0), s)
            return s
        h, n = [], 0
        for b in blocks:
            k = b[0]
            if k == 'h':
                if b[1] <= 2: n += 1; h.append(f'<h{b[1] + 1} id="g{did}-{n}">{inline(b[2], False)}</h{b[1] + 1}>')
                else: h.append(f'<h4>{inline(b[2], False)}</h4>')
            elif k == 'p': h.append(f'<p>{inline(b[1])}</p>')
            elif k == 'quote': h.append(f'<blockquote>{inline(b[1])}</blockquote>')
            elif k == 'pre': h.append(f'<pre class="gd-pre">{html.escape(b[1])}</pre>')
            elif k in ('ul', 'ol'): h.append(f'<{k}>' + ''.join(f'<li>{inline(x)}</li>' for x in b[1]) + f'</{k}>')
            elif k == 'todo': h.append(f'<div class="gd-todo">{html.escape(b[1])}</div>')
            elif k == 'live': h.append(f'<div class="gd-live" data-live="{html.escape(b[1])}"><div class="empty">加载中…</div></div>')
            elif k == 'img':
                c, u = b[1], b[2]; kind, v = u.split(':', 1)
                if kind == 'diagram': h.append(f'<figure class="gd-fig">{DIAGRAMS[v]}<figcaption>{html.escape(c)}</figcaption></figure>')
                else: h.append(f'<figure class="gd-fig"><img src="img/{v}.png" alt="{html.escape(c)}" loading="lazy" data-shot="{v}"><figcaption>{html.escape(c)}</figcaption></figure>')
            elif k == 'table':
                ck = b[1] and b[1][0] == '完成'   # 月结清单：勾选框，页面记在本机
                th = ''.join(f'<th>{inline(x)}</th>' for x in b[1])
                rows = ''.join('<tr>' + ''.join(
                    f'<td>{CKBOX if ck and j == 0 and x == "☐" else inline(x)}</td>' for j, x in enumerate(r)) + '</tr>' for r in b[2])
                h.append(f'<div class="gd-tw"><table class="gd-t"><thead><tr>{th}</tr></thead><tbody>{rows}</tbody></table></div>')
        res.append({'id': did, 'title': meta.get('title', did), 'subtitle': meta.get('subtitle', ''), 'menu': meta.get('menu', meta.get('title', did)),
                    'toc': toc, 'html': '\n'.join(h)})
    with open(OUT, 'w', encoding='utf-8') as f:
        f.write('// 成本执行台 · guidedata.js — “使用手册”页的内容。由 交付文档/tools/build_web.py 从 交付文档/src/*.md 生成，不要手改\n"use strict";\nconst GUIDE = ')
        f.write(json.dumps(res, ensure_ascii=False, indent=0))
        f.write(';\n')
    print('已生成 %s：%d 份文档' % (os.path.relpath(OUT, os.path.join(BASE, '..')), len(res)))
    for d in res: print('  %s %s（%d 节）' % (d['id'], d['title'], len(d['toc'])))

if __name__ == '__main__':
    build()
