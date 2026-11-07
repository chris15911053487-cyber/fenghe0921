#!/usr/bin/env python3
# 交付手册的执行台截图：Playwright 打开本机运行的成本执行台，在接口响应到达页面之前脱敏，再截图。
#
# 业务数据不出本地（CLAUDE.md 数据边界）：
#   - 物料、业务伙伴、用户、公司名：启动时从库里读全量对照表，只放内存；所有接口返回的文字都按它替换。
#   - 金额：小数列和文字里的金额统一乘随机系数 K，勾稽关系不变。K 和对照表不落盘、不打印，不用 脱敏密钥/。
#   - 备注类列清空。脱敏规则沿用 新框架/tools/export_masked.py。
#   - 写接口一律拦截，只放行静态文件和只读查询。
#   - 每张图保存前扫描页面文字，命中对照表的真实名称或代码就不保存。屏幕上只打印图名和条数，不打印数据。
#
# 用法：先启动执行台（tools/启动成本执行台.command），再运行
#   python3 交付文档/tools/capture.py [--only id1,id2] [--base http://127.0.0.1:8766] [--conn 连接文件]
#   --dict-json 只用于自测：用文件里的假对照表，不连库。
import argparse, json, os, random, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, os.path.join(ROOT, '新框架', 'tools'))
from export_masked import DROP_COL, NOSCALE_COL, TOKEN

CN_DROP = re.compile(r'(备注|摘要|用户|创建人|领用人|申请人|操作人|制单|项目|地址|电话|联系人)')
CN_NOSCALE = re.compile(r'(数量|工时|比例|占比|率|%|％|行数|层级|^Rt[A-Z]|Sec$|Hour)')
TEXT_NUM = re.compile(r'(?<![\d.\-/:A-Za-z])-?\d{1,3}(?:,\d{3})+(?:\.\d+)?(?![\d%％])|(?<![\d.\-/:A-Za-z])-?\d+\.\d+(?![\d%％.])')
OK_POST = {'/api/q', '/api/sql'}
OK_GET = {'/api/info', '/api/companies', '/api/job', '/api/ai/status'}


class Masker:
    def __init__(self, items, bps, users, companies, K=None):
        """items/bps/users：{代码: 名称}；companies：要隐藏的公司名和账套名。"""
        self.K = K if K is not None else random.uniform(0.3, 3)
        self.code, self.name = {}, {}
        for src, cp, cw, np in ((items, 'I', 6, '示例物料 '), (bps, 'BP', 4, '示例伙伴 '), (users, 'U', 3, '示例用户 ')):
            codes = sorted(c for c in src if c); random.shuffle(codes)
            for i, c in enumerate(codes, 1):
                self.code[str(c)] = f'{cp}{i:0{cw}d}'
                nm = src[c]
                if nm and len(str(nm)) >= 2: self.name.setdefault(str(nm), f'{np}{i:03d}')
        for c in companies:
            if c: self.name[str(c)] = 'DEMO'
        self.lens = sorted({len(n) for n in self.name}, reverse=True)
        self.cache = {}

    def scale(self, v): return round(v * self.K, 6)

    def _names(self, s):
        out, i, n = [], 0, len(s)
        while i < n:
            for L in self.lens:
                if i + L <= n and s[i:i + L] in self.name:
                    out.append(self.name[s[i:i + L]]); i += L; break
            else:
                out.append(s[i]); i += 1
        return ''.join(out)

    def _nums(self, s):
        def f(m):
            t = m.group(0); d = len(t.split('.')[1]) if '.' in t else 2
            return f'{float(t.replace(",", "")) * self.K:,.{d}f}'
        return TEXT_NUM.sub(f, s)

    def text(self, s):
        r = self.cache.get(s)
        if r is None:
            r = self.code.get(s)
            if r is None:
                r = self._nums(self._names(TOKEN.sub(lambda m: self.code.get(m.group(0), m.group(0)), s)))
            self.cache[s] = r
        return r

    def cell(self, col, v):
        if isinstance(v, str):
            if (DROP_COL.search(col) and not re.search(r'ItemName|CardName|StockName', col, re.I)) or CN_DROP.search(col):
                return ''
            return self.text(v)
        if isinstance(v, float) and not (NOSCALE_COL.search(col) or CN_NOSCALE.search(col)):
            return self.scale(v)
        return v

    def rows(self, o):
        cols = o.get('columns') or []
        o['columns'] = cols
        o['rows'] = [[self.cell(c, x) for c, x in zip(cols, r)] for r in o.get('rows') or []]
        return o

    def walk(self, o):
        if isinstance(o, str): return self.text(o)
        if isinstance(o, list): return [self.walk(x) for x in o]
        if isinstance(o, dict): return {k: self.walk(v) for k, v in o.items()}
        return o

    def payload(self, o):
        """接口响应：columns/rows 按列脱敏，其余字段（报错、提示等）按文字脱敏。"""
        if isinstance(o, dict) and 'columns' in o and 'rows' in o:
            r = {k: self.walk(v) for k, v in o.items() if k not in ('columns', 'rows')}
            r.update(self.rows({'columns': o['columns'], 'rows': o['rows']}))
            return r
        return self.walk(o)

    def info(self, o):
        o = self.walk(o)
        o.update(conn='DEMO-SERVER', user='demo', schema='DEMO', osUser='demo',
                 companies=[{'schema': 'DEMO', 'name': 'DEMO 示例公司'}],
                 login={'user': 'demo', 'name': '示例用户', 'role': 'A', 'roleName': '管理'})
        return o

    def leaks(self, text):
        """页面文字里还剩多少真实名称和代码。太短的不扫，避免和界面文字、科目号撞车。"""
        n = sum(text.count(x) for x in self.name if len(x) >= 3)
        toks = set(TOKEN.findall(text))
        return n + sum(1 for c in self.code if len(c) >= 5 and c in toks)


def load_dict(conn_path, schema):
    from export_masked import connect
    c = json.load(open(conn_path, encoding='utf-8'))
    c['schema'] = schema or c['schema']
    db = connect(c); cur = db.cursor()
    def pairs(sql):
        cur.execute(sql); return {r[0]: r[1] for r in cur.fetchall()}
    items = pairs('SELECT "ItemCode", "ItemName" FROM "OITM"')
    bps = pairs('SELECT "CardCode", "CardName" FROM "OCRD"')
    users = pairs('SELECT "USER_CODE", "U_NAME" FROM "OUSR"')
    cur.execute('SELECT MAX("CompnyName") FROM "OADM"'); co = cur.fetchone()[0]
    db.close()
    return items, bps, users, [co, c['schema']]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--only', default='')
    ap.add_argument('--base', default='http://127.0.0.1:8766')
    ap.add_argument('--conn', default=os.path.join(ROOT, 'mtc_ca_conn.json'))
    ap.add_argument('--dict-json', default='')
    ap.add_argument('--shots', default=os.path.join(HERE, 'shots.json'))
    ap.add_argument('--out', default=os.path.join(ROOT, '交付文档', '截图'))
    a = ap.parse_args()
    import urllib.parse, urllib.request
    from playwright.sync_api import sync_playwright
    req = urllib.request.Request(a.base + '/api/info', headers={'X-Requested-With': 'cost-console'})
    real = json.load(urllib.request.urlopen(req))
    if not real.get('ok'): sys.exit('执行台没有连上库，先启动并确认连接')
    schema = real['schema']
    if a.dict_json:
        d = json.load(open(a.dict_json, encoding='utf-8')); args = (d['items'], d['bps'], d['users'], d['companies'])
    else:
        args = load_dict(a.conn, schema)
    m = Masker(*args)
    print(f'对照表已载入：物料 {len(args[0])}，业务伙伴 {len(args[1])}，用户 {len(args[2])}')
    spec = json.load(open(a.shots, encoding='utf-8'))['shots']
    only = set(filter(None, a.only.split(',')))
    os.makedirs(a.out, exist_ok=True)
    blocked, saved, skipped = [], [], []

    def api(route):
        rq = route.request
        from urllib.parse import urlparse
        p = urlparse(rq.url).path
        if p == '/login.html':
            return route.fulfill(path=os.path.join(ROOT, 'tools', 'console', 'login.html'), content_type='text/html; charset=utf-8')
        if not p.startswith('/api/'): return route.continue_()
        if not ((rq.method == 'GET' and p in OK_GET) or (rq.method == 'POST' and p in OK_POST)):
            blocked.append(p); return route.abort()
        resp = route.fetch(headers={**rq.headers, 'x-schema': schema})
        body = resp.json()
        out = m.info(body) if p == '/api/info' else m.payload(body)
        route.fulfill(status=resp.status, content_type='application/json; charset=utf-8', body=json.dumps(out, ensure_ascii=False))

    with sync_playwright() as pw:
        b = pw.chromium.launch()
        ctx = b.new_context(viewport={'width': 1440, 'height': 900}, device_scale_factor=2, locale='zh-CN')
        ctx.add_init_script('try{localStorage.setItem("cc.theme","ent");localStorage.setItem("cc.user","示例用户")}catch(e){}')
        ctx.route('**/*', api)
        runs = None
        def pick(kind):
            nonlocal runs
            if runs is None:
                pg = ctx.new_page(); pg.goto(a.base + '/#run'); pg.wait_for_load_state('networkidle')
                runs = pg.evaluate('RUNS.map(r => ({RunId:r.RunId, RunType:r.RunType, Scenario:r.Scenario, Status:r.Status}))'); pg.close()
            st = ('OK',) if kind == 'ok' else ('CHECKED', 'BLOCKED')
            for r in runs:   # 运行列表最近的在前
                if r['RunType'] == 'F' and not r['Scenario'] and r['Status'] in st: return r['RunId']
        for s in spec:
            if only and s['id'] not in only: continue
            pg = ctx.new_page()
            try:
                if s.get('login'):
                    pg.goto(a.base + '/login.html')
                else:
                    rid = pick(s.get('run', 'ok')) if s.get('run') != 'none' else None
                    if s.get('run') != 'none' and rid is None:
                        skipped.append((s['id'], '没有符合条件的运行')); continue
                    item = ''
                    if s.get('traceTop'):   # 成本追溯：取层级最高、期末金额最大的物料当起点
                        rq2 = urllib.request.Request(a.base + '/api/q', data=json.dumps({'action': 'items', 'args': {'runId': str(rid), 'q': ''}}).encode(),
                                                     headers={'X-Requested-With': 'cost-console', 'Content-Type': 'application/json'})
                        r2 = json.load(urllib.request.urlopen(rq2)); c2 = r2['columns']
                        o2 = max(r2['rows'], key=lambda x: (x[c2.index('iLevel')] or 0, x[c2.index('EndAmount')] or 0))
                        item = '&item=' + urllib.parse.quote(str(o2[c2.index('ItemCode')]))
                    pg.goto(f"{a.base}/#{s['tab']}" + (f'?run={rid}' if rid else '') + item)
                pg.wait_for_load_state('networkidle'); pg.wait_for_timeout(800)
                pg.evaluate('f => document.querySelectorAll("input").forEach(e => { if (e.type === "text" && e.value) e.value = f[e.value] || e.value; })', m.code)   # 链接带进输入框的代码
                for st in s.get('steps', []):
                    if 'click' in st: pg.click(st['click'], timeout=8000)
                    if 'clickIf' in st and pg.locator(st['clickIf']).count(): pg.locator(st['clickIf']).first.click(timeout=8000)
                    if 'wait' in st: pg.wait_for_selector(st['wait'], timeout=8000)
                    if 'sleep' in st: pg.wait_for_timeout(st['sleep'])
                    if 'hide' in st: pg.evaluate('x => document.querySelectorAll(x).forEach(e => e.style.display = "none")', st['hide'])
                    if 'scrollText' in st: pg.evaluate('x => { const t = [...document.querySelectorAll("td")].find(e => e.textContent.startsWith(x)); if (t) t.scrollIntoView({block:"start"}); }', st['scrollText'])
                    pg.wait_for_load_state('networkidle')
                for k in s.get('marks', []):
                    pg.evaluate('''k => { const e = document.querySelector(k.sel); if (!e) return; const r = e.getBoundingClientRect();
                      const d = document.createElement("div"); d.textContent = "①②③④⑤⑥⑦⑧⑨"[k.n - 1];
                      d.style.cssText = `position:fixed;z-index:99999;left:${Math.max(2, r.left - 12)}px;top:${Math.max(2, (k.at === "top" ? r.top + 4 : r.top + r.height / 2 - 12))}px;width:24px;height:24px;line-height:23px;text-align:center;font-size:20px;color:#fff;background:#d4380d;border-radius:50%;box-shadow:0 1px 3px #0006`;
                      document.body.appendChild(d); }''', k)
                txt = pg.evaluate('document.body.innerText + " " + [...document.querySelectorAll("input,textarea,select")].map(e => e.value).join(" ") + " " + [...document.querySelectorAll("[title]")].map(e => e.title).join(" ")')
                hits = m.leaks(txt)
                if hits:
                    skipped.append((s['id'], f'脱敏扫描命中 {hits} 处，未保存')); continue
                pg.screenshot(path=os.path.join(a.out, s['id'] + '.png'))
                saved.append(s['id'])
            except Exception as e:
                skipped.append((s['id'], type(e).__name__))   # 不打印异常内容，里面可能带页面文字
            finally:
                pg.close()
        b.close()
    print(f'已保存 {len(saved)} 张：' + '、'.join(saved))
    for i, w in skipped: print(f'未保存 {i}：{w}')
    print(f'拦截写接口 {len(blocked)} 次' + (('：' + '、'.join(sorted(set(blocked)))) if blocked else ''))
    print('请先抽查图片，确认没有真实数据后再交给 AI 处理。')


if __name__ == '__main__':
    main()
