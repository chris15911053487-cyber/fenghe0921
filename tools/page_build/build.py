"""生成《FH100成本核算关系图.html》。

用法（在任意目录运行，需要 Python 3）：
    python tools/page_build/build.py                 生成项目根目录下的本地网页
    python tools/page_build/build.py --fragment X    另外输出一个不带 <html> 外壳的版本到 X（用于发布到 claude.ai）

数据来源：
    template.html                    页面模板（含关系图、字段影响等数据）
    changelog.json                   版本记录（第一条为当前版本；每次改网页先在最前面加一条）
    checks/MTC_COST_CHECKS.sql       校验与追溯查询（解析每段头部的 @check 注释）
    0921-存储过程/.../create.sql     导出包中的存储过程
    0921-表/.../create.sql           导出包中的表结构
    0921-补充对象/*                  对话中补充的视图、函数、过程、配置数据
    0921-数据库同步/*                从数据库同步的最新定义（优先使用，原版本保留用于对比）
"""
import glob
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
TEMPLATE = os.path.join(HERE, 'template.html')
CHECKS = os.path.join(ROOT, 'checks', 'MTC_COST_CHECKS.sql')
OUTPUT = os.path.join(ROOT, 'FH100成本核算关系图.html')
CHANGELOG = os.path.join(HERE, 'changelog.json')


def parse_checks(path):
    checks, cur, mode, last = [], None, None, None
    for ln in open(path, encoding='utf-8').read().split('\n'):
        m = re.match(r'^-- @check (\S+) \| (.+)$', ln)
        if m:
            cur = {'id': m.group(1), 'title': m.group(2).strip(), 'step': '', 'ok': '', 'bad': '',
                   'nodes': [], 'fields': [], 'sql': []}
            checks.append(cur)
            mode = 'head'
            continue
        if cur is None:
            continue
        if mode == 'head':
            m = re.match(r'^-- @(\w+)\s+(.*)$', ln)
            if m:
                k, v = m.group(1), m.group(2).strip()
                cur[k] = [x.strip() for x in v.split(',') if x.strip()] if k in ('nodes', 'fields') else v
                last = k
                continue
            if ln.startswith('--      ') and last == 'bad':
                cur['bad'] += '\n' + ln[2:].strip()
                continue
            mode = 'body'
        cur['sql'].append(ln)
    for c in checks:
        c['sql'] = re.sub(r'/\*.*?\*/', '', '\n'.join(c['sql']), flags=re.S).strip()
    return checks


def pretty_table(t):
    """把导出时写成一整行的 CREATE TABLE 拆成一个字段一行。"""
    t = t.strip()
    if '\n' in t:
        return t
    out, depth = [], 0
    for ch in t:
        if ch == '(':
            depth += 1
            out.append(ch)
            if depth == 1:
                out.append('\n    ')
        elif ch == ')':
            if depth == 1:
                out.append('\n')
            depth -= 1
            out.append(ch)
        elif ch == ',' and depth == 1:
            out.append(',\n    ')
        elif ch == ' ' and depth == 1 and out and out[-1].endswith('\n    '):
            continue
        else:
            out.append(ch)
    return ''.join(out)


def collect_sources():
    src = {}
    for f in sorted(glob.glob(os.path.join(ROOT, '0921-存储过程', 'export', 'FH100', 'MT', '*', 'create.sql'))):
        name = os.path.basename(os.path.dirname(f))
        src[name] = {'kind': 'proc', 'origin': '导出包', 'path': os.path.relpath(f, ROOT),
                     'text': open(f, encoding='utf-8').read().rstrip()}
    for f in sorted(glob.glob(os.path.join(ROOT, '0921-表', 'index', 'FH100', 'MT', '*', 'create.sql'))):
        name = os.path.basename(os.path.dirname(f))
        src[name] = {'kind': 'table', 'origin': '导出包', 'path': os.path.relpath(f, ROOT),
                     'text': pretty_table(open(f, encoding='utf-8').read())}
    for f in sorted(glob.glob(os.path.join(ROOT, '0921-补充对象', '*'))):
        name, ext = os.path.splitext(os.path.basename(f))
        text = open(f, encoding='utf-8').read().rstrip()
        if ext == '.tsv':
            kind = 'data'
        elif re.search(r'CREATE\s+VIEW', text, re.I):
            kind = 'view'
        elif re.search(r'CREATE\s+FUNCTION', text, re.I):
            kind = 'func'
        elif re.search(r'CREATE\s+(COLUMN\s+)?TABLE', text, re.I):
            kind = 'table'
        else:
            kind = 'proc'
        src[name] = {'kind': kind, 'origin': '对话补充', 'path': os.path.relpath(f, ROOT), 'text': text}
    # 新报表草稿（reports/，未部署）；部署并同步后，以数据库版本为准，草稿保留为 alt
    for f in sorted(glob.glob(os.path.join(ROOT, 'reports', '*.sql'))):
        name = os.path.splitext(os.path.basename(f))[0]
        src[name] = {'kind': 'proc', 'origin': '报表草稿', 'path': os.path.relpath(f, ROOT),
                     'text': open(f, encoding='utf-8').read().rstrip()}
    # 数据库同步结果（tools/cost_server.ps1 写入）优先，原版本保留为 alt，供页面对比
    sync_dirs = {'存储过程': 'proc', '表函数': 'func', '视图': 'view', '表结构': 'table', '配置数据': 'data'}
    for sub, kind in sync_dirs.items():
        for f in sorted(glob.glob(os.path.join(ROOT, '0921-数据库同步', sub, '*'))):
            name = os.path.splitext(os.path.basename(f))[0]
            text = open(f, encoding='utf-8').read().rstrip()
            item = {'kind': kind, 'origin': '数据库', 'path': os.path.relpath(f, ROOT), 'text': text, 'db': True}
            if name in src:
                old = src[name]
                item.update({'alt': old['text'], 'altOrigin': old['origin'], 'altPath': old['path']})
            else:
                item['isNew'] = True
            src[name] = item
    return src


def main():
    html = open(TEMPLATE, encoding='utf-8').read()
    checks, sources = parse_checks(CHECKS), collect_sources()
    changelog = json.load(open(CHANGELOG, encoding='utf-8'))
    import datetime
    built = datetime.datetime.now().strftime('%Y-%m-%d %H:%M')
    for ph, val in (('/*CHECKS*/[]', checks), ('/*SOURCES*/{}', sources), ('/*CHANGELOG*/[]', changelog), ('/*BUILT*/""', built)):
        if ph not in html:
            sys.exit('模板中缺少占位符 ' + ph)
        html = html.replace(ph, json.dumps(val, ensure_ascii=False).replace('</', '<\\/'))

    if '--fragment' in sys.argv:
        frag = sys.argv[sys.argv.index('--fragment') + 1]
        open(frag, 'w', encoding='utf-8').write(html)

    i = html.index('<div class="wrap">')
    page = ('<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n'
            '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n'
            '<style>html{color-scheme:light}body{margin:0;font-size:14px}img{max-width:100%}'
            '[hidden]{display:none!important}</style>\n'
            + html[:i] + '</head>\n<body>\n' + html[i:] + '\n</body>\n</html>\n')
    open(OUTPUT, 'w', encoding='utf-8').write(page)
    print('已生成 %s（版本 v%s，%s）：%d 个校验，%d 个源码对象' % (os.path.relpath(OUTPUT, ROOT), changelog[0]['version'], changelog[0]['date'], len(checks), len(sources)))


if __name__ == '__main__':
    main()
