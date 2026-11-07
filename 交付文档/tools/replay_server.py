#!/usr/bin/env python3
# 离线回放：不连库，用 排查数据/ 下的脱敏导出驱动成本执行台页面，给 capture.py 截图用。
# CSV 载入内存 SQLite，actions.json 里的 HANA 语句转换后执行；只读，没有任何写接口。
# 缺的表（B1 表、没导出的表）当空表，缺的列当 NULL。只打印统计，不打印数据。
# 导出里物料名称已清空，这里按编码补一个名称，再由 capture.py 换成代号；金额由 capture.py 乘系数。
# 用法：python3 交付文档/tools/replay_server.py [--data 排查数据/目录] [--extra 排查数据/较新目录] [--port 8767] [--stats]
#   启动时写 排查数据/_replay_dict.json（物料对照表，已被 gitignore），capture.py 用 --dict-json 指定它：
#   python3 交付文档/tools/capture.py --base http://127.0.0.1:8767 --dict-json 排查数据/_replay_dict.json
import argparse, csv, glob, inspect, json, os, re, sqlite3, sys, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
CONSOLE = os.path.join(ROOT, 'tools', 'console')
TEXT_COL = re.compile(r'(Code|Acct|Item|Whs|Card|Ocr|Num$|Name|Memo|Msg|Info|Status|Type|Fc$|Scenario|Key|Ref|Docs|Reason|Title|Time|Date|Year|Cat|Kind|Stage|Result)', re.I)
NUM = re.compile(r'^-?\d+(\.\d+)?([eE][-+]?\d+)?$')
UDF_NULL = lambda *a: None
LOCK = threading.Lock()


def conv(col, v):
    if v == '' or v == '*': return None
    if NUM.match(v) and not TEXT_COL.search(col):
        return float(v) if re.search(r'[.eE]', v) else int(v)
    return v


class Agg:
    def __init__(self): self.v, self.s = [], ','
    def step(self, x, s=','):
        if x is not None: self.v.append(str(x)); self.s = s
    def finalize(self): return self.s.join(self.v) if self.v else None


def fix_decimal(db):
    """DECIMAL 列要以浮点数出去（捕获时据此乘系数），导出里写成 12 的整数值统一按列转。"""
    for (t,) in db.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall():
        cols = [r[1] for r in db.execute(f'PRAGMA table_info("{t}")')]
        for c in cols:
            if re.search(r'(Amt|Amount|Price|Debit|Credit|Exp$|Sum$|Total)', c):
                db.execute(f'UPDATE "{t}" SET "{c}" = CAST("{c}" AS REAL) WHERE typeof("{c}") = \'integer\'')


def load(data, extra=None):
    db = sqlite3.connect(':memory:', check_same_thread=False)
    for f in glob.glob(os.path.join(data, '*.csv')):
        t = os.path.basename(f)[:-4]
        r = csv.reader(open(f, encoding='utf-8-sig')); h = next(r)
        db.execute(f'CREATE TABLE "{t}" (' + ','.join(f'"{c}"' for c in h) + ')')
        db.executemany(f'INSERT INTO "{t}" VALUES (' + ','.join('?' * len(h)) + ')',
                       ([conv(c, v) for c, v in zip(h, x)] for x in r if len(x) == len(h)))
    for f in glob.glob(os.path.join(extra or '', '*.csv')) if extra else []:   # 主目录没有的配置表，从较新的导出补
        t = os.path.basename(f)[:-4]
        if t != 'MTC_CA_C_PARAM_DEF' or db.execute("SELECT 1 FROM sqlite_master WHERE name=?", (t,)).fetchone(): continue
        r = csv.reader(open(f, encoding='utf-8-sig')); h = next(r)
        db.execute(f'CREATE TABLE "{t}" (' + ','.join(f'"{c}"' for c in h) + ')')
        db.executemany(f'INSERT INTO "{t}" VALUES (' + ','.join('?' * len(h)) + ')', ([conv(c, v) for c, v in zip(h, x)] for x in r if len(x) == len(h)))
    fix_decimal(db)
    items = set()
    for (t,) in db.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall():
        cols = [r[1] for r in db.execute(f'PRAGMA table_info("{t}")')]
        for c in cols:
            if c in ('ItemCode', 'ProdItem', 'MatItem', 'Father', 'SrcItem'):
                items |= {r[0] for r in db.execute(f'SELECT DISTINCT "{c}" FROM "{t}" WHERE "{c}" IS NOT NULL')}
    db.execute('CREATE TABLE "OITM" ("ItemCode","ItemName","ItmsGrpCod","InvntItem")')
    db.executemany('INSERT INTO "OITM" VALUES (?,?,101,?)', [(i, f'物料 {i}', 'Y') for i in items])
    db.execute('CREATE TABLE "OITB" ("ItmsGrpCod","ItmsGrpNam")'); db.execute("INSERT INTO \"OITB\" VALUES (101,'示例物料组')")
    rid = db.execute('SELECT MAX("RunId") FROM "MTC_CA_RUN" WHERE "RunType"=\'F\' AND "Status"=\'OK\'').fetchone()[0]
    db.execute('''CREATE TABLE "MTC_CA_F_JV_PLAN" AS SELECT "RunId","TransCode",MAX("TransName") AS "TransName",MAX("RefDate") AS "RefDate",COUNT(*) AS "LineCnt",
        SUM("Debit") AS "Debit",SUM("Credit") AS "Credit",0 AS "BadAcct",'READY' AS "State",NULL AS "BatchNum",
        CASE WHEN "TransCode" IN ('AR03','AR04') THEN 'Y' ELSE 'N' END AS "AutoRev",CASE WHEN "TransCode" IN ('AR03','AR04') THEN '2026-10-01' END AS "RevDate"
        FROM "MTC_CA_R_JDT" WHERE "RunId"=? GROUP BY "RunId","TransCode"''', (rid,))
    db.execute('CREATE TABLE "MTC_CA_V_PERIOD" ("FcCode","PeriodStat","Status","CostStatus","CalcRunId","PostRunId","PostUser","PostTime","LastOkRunId")')
    db.execute('INSERT INTO "MTC_CA_V_PERIOD" VALUES (?,?,?,?,?,?,?,?,?)', ('2026-09', 'N', 'CALC', 'CALC', rid, None, None, None, rid))
    db.execute('CREATE TABLE DUMMY (x)'); db.execute('INSERT INTO DUMMY VALUES (1)')
    db.execute('CREATE TABLE "OFPR" ("Code","PeriodStat","F_RefDate","T_RefDate")')
    db.executemany('INSERT INTO "OFPR" VALUES (?,?,?,?)', [('2026-09', 'N', '2026-09-01', '2026-09-30'), ('2026-10', 'N', '2026-10-01', '2026-10-31')])
    fs = {'TO_NVARCHAR': lambda x, f=None: None if x is None else str(x), 'TO_VARCHAR': lambda x, f=None: None if x is None else str(x),
          'TO_DECIMAL': lambda x, a=None, b=None: None if x is None else float(x), 'TO_DOUBLE': lambda x: None if x is None else float(x),
          'TO_INTEGER': lambda x: None if x is None else int(float(x)), 'TO_BIGINT': lambda x: None if x is None else int(float(x)),
          'NDIV0': lambda a, b: None if not b else a / b, 'SECONDS_BETWEEN': lambda a, b: 0, 'CURRENT_DATE': lambda: '2026-10-16',
          'TO_DATE': lambda x, f=None: x, 'TO_TIMESTAMP': lambda x, f=None: x, 'ADD_DAYS': lambda x, n: x, 'ADD_MONTHS': lambda x, n: x, 'LPAD': lambda x, n, c=' ': str(x).rjust(n, c),
          'RPAD': lambda x, n, c=' ': str(x).ljust(n, c), 'LOCATE': lambda a, b: (str(a).find(str(b)) + 1), 'CURRENT_SCHEMA': lambda: 'DEMO',
          'GREATEST': lambda *a: max(x for x in a if x is not None), 'LEAST': lambda *a: min(x for x in a if x is not None), 'CURRENT_USER': lambda: 'demo'}
    for k, f in fs.items():
        try:
            ps = inspect.signature(f).parameters.values(); hi = None if any(p.kind == p.VAR_POSITIONAL for p in ps) else len(ps)
            lo = sum(1 for p in ps if p.default is p.empty and p.kind != p.VAR_POSITIONAL)
            if hi is None: db.create_function(k, -1, f)
            else:
                for n in range(lo, hi + 1): db.create_function(k, n, f)
        except ValueError: pass
    db.create_aggregate('STRING_AGG', 1, Agg); db.create_aggregate('STRING_AGG', 2, Agg)
    return db, items


def balanced(s, i):
    """s[i] 是 '('，返回匹配的 ')' 位置。"""
    d = 0; q = False
    for j in range(i, len(s)):
        c = s[j]
        if c == "'": q = not q
        elif not q:
            if c == '(': d += 1
            elif c == ')':
                d -= 1
                if d == 0: return j
    return -1


def translate(sql, vals, db):
    s = re.sub(r'--[^\n]*', '', sql); vals = list(vals)
    s = re.sub(r'"?SYS"?\.', '', s)
    m = re.match(r'\s*SELECT\s+TOP\s+(\d+)\b', s, re.I)
    if m: s = 'SELECT ' + s[m.end():].rstrip().rstrip(';') + f' LIMIT {m.group(1)}'
    s = re.sub(r'\bSELECT\s+TOP\s+\d+\b', 'SELECT', s, flags=re.I)
    s = re.sub(r'\bLEFT\s*\(', 'SUBSTR_L(', s); s = re.sub(r'\bRIGHT\s*\(', 'SUBSTR_R(', s)
    s = re.sub(r'\bSUBSTRING\s*\(', 'SUBSTR(', s)
    s = re.sub(r"\bCURRENT_(DATE|TIMESTAMP|UTCTIMESTAMP)\b(?!\s*\()", "'2026-10-16'", s)
    s = re.sub(r'\bCURRENT_SCHEMA\b(?!\s*\()', "'DEMO'", s); s = re.sub(r'\bCURRENT_USER\b(?!\s*\()', "'demo'", s)
    s = re.sub(r'\bLIKE_REGEXPR\b', 'REGEXP', s)
    # 表函数当成同名空表；参数从绑定列表里去掉
    while True:
        m = re.search(r'(FROM|JOIN|,)\s+"(MTC_[A-Za-z0-9_]+)"\s*\(', s)
        if not m: break
        o = s.index('(', m.start(2)); c = balanced(s, o)
        pos = s[:o].count('?'); cnt = s[o:c].count('?')
        del vals[pos:pos + cnt]
        s = s[:o] + s[c + 1:]
    for f in set(re.findall(r'"(MTC_[A-Za-z0-9_]+)"\s*\(', s)):
        db.create_function(f, -1, UDF_NULL)
    return s, vals


def run(db, sql, vals):
    sql, vals = translate(sql, vals, db)
    for _ in range(80):
        try:
            cur = db.execute(sql, vals)
            return [d[0] for d in cur.description], [list(r) for r in cur.fetchall()]
        except sqlite3.OperationalError as e:
            m = str(e)
            t = re.search(r'no such table: (?:main\.)?(.+)', m)
            if t: db.execute(f'CREATE TEMP TABLE IF NOT EXISTS "{t.group(1).split(".")[-1]}" (_d)'); continue
            c = re.search(r'no such column: (?:(\w+)\.)?"?([^"\s]+)"?', m)
            if c:
                new, k = re.subn(r'(?<![Aa][Ss] )((?:\b\w+|"[^"]+")\.)?"%s"(?!\s*\()' % re.escape(c.group(2)), 'NULL', sql)
                if k: sql = new; continue
            raise


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', default=os.path.join(ROOT, '排查数据', '2026-09_20261016_2327'))
    ap.add_argument('--extra', default=os.path.join(ROOT, '排查数据', '2026-10_20261030_1143'))
    ap.add_argument('--port', type=int, default=8767)
    ap.add_argument('--stats', action='store_true', help='跑一遍全部查询，只打印能否执行')
    a = ap.parse_args()
    db, items = load(a.data, a.extra)
    json.dump({'items': {i: '' for i in items}, 'bps': {}, 'users': {}, 'companies': ['FH100_COST', 'FH100_COST_TEST', 'FH100']},
              open(os.path.join(ROOT, '排查数据', '_replay_dict.json'), 'w', encoding='utf-8'))
    db.create_function('SUBSTR_L', 2, lambda x, n: None if x is None else str(x)[:n])
    db.create_function('REGEXP', 2, lambda p, x: x is not None and re.search(p, str(x)) is not None)
    db.create_function('SUBSTR_R', 2, lambda x, n: None if x is None else str(x)[-n:])
    db.create_function('SUBSTR_BEFORE', 2, lambda x, c: None if x is None else str(x).split(c)[0] if c in str(x) else '')
    db.create_function('SUBSTR_AFTER', 2, lambda x, c: None if x is None else str(x).split(c, 1)[1] if c in str(x) else '')
    acts = json.load(open(os.path.join(CONSOLE, 'actions.json'), encoding='utf-8'))['actions']
    bad = {}
    if a.stats:
        ok = 0
        for k, v in acts.items():
            if v.get('kind') != 'query' or not v.get('sql'): continue
            try: run(db, v['sql'], ['1'] * v['sql'].count('?')); ok += 1
            except Exception as e: bad[k] = re.sub(r'"[^"]*"', '"…"', str(e))[:70]
        print('可执行', ok, '失败', len(bad))
        for k, m in bad.items(): print(' ', k, m)
        return

    class H(BaseHTTPRequestHandler):
        def log_message(s, *x): pass
        def out(s, o, ct='application/json; charset=utf-8', code=200):
            b = o if isinstance(o, bytes) else json.dumps(o, ensure_ascii=False).encode('utf-8')
            s.send_response(code); s.send_header('Content-Type', ct); s.send_header('Content-Length', str(len(b))); s.end_headers(); s.wfile.write(b)
        def do_GET(s):
            p = s.path.split('?')[0]
            if p == '/': return s.out(open(os.path.join(CONSOLE, 'index.html'), 'rb').read(), 'text/html; charset=utf-8')
            m = re.match(r'^/(css|js)/([a-z0-9_]+)\.(css|js)$', p)
            if m: return s.out(open(os.path.join(CONSOLE, m.group(1), f'{m.group(2)}.{m.group(3)}'), 'rb').read(), 'text/css' if m.group(1) == 'css' else 'text/javascript; charset=utf-8')
            m = re.match(r'^/img/([a-z0-9_]+)\.png$', p)   # 使用手册的截图
            if m and os.path.isfile(os.path.join(ROOT, '交付文档', '截图', m.group(1) + '.png')): return s.out(open(os.path.join(ROOT, '交付文档', '截图', m.group(1) + '.png'), 'rb').read(), 'image/png')
            co = [{'schema': 'DEMO', 'name': '示例公司'}]
            if p == '/api/info': return s.out({'ok': True, 'conn': 'replay', 'user': 'demo', 'schema': 'DEMO', 'hasNew': True, 'osUser': 'demo', 'companies': co})
            if p == '/api/companies': return s.out({'ok': True, 'companies': co, 'default': 'DEMO'})
            if p == '/api/job': return s.out({'ok': True, 'state': 'idle'})
            if p == '/api/ai/status': return s.out({'ok': True})
            s.out(b'not found', 'text/plain', 404)
        def do_POST(s):
            n = int(s.headers.get('Content-Length') or 0); b = json.loads(s.rfile.read(n) or b'{}')
            if s.path != '/api/q': return s.out({'ok': False, 'error': '离线回放不支持这个操作'})
            spec = acts.get(b.get('action')) or {}
            args = b.get('args') or {}
            vals = [args.get(p, '') for p in spec.get('params', [])]
            try:
                with LOCK: c, r = run(db, spec['sql'], vals)
                s.out({'ok': True, 'columns': c, 'rows': r, 'truncated': False})
            except Exception:
                bad[b.get('action')] = 1
                print('查询失败', b.get('action'), flush=True)
                s.out({'ok': False, 'error': '离线回放没有这项数据'})
    print(f'回放服务 http://127.0.0.1:{a.port}/', flush=True)
    ThreadingHTTPServer(('127.0.0.1', a.port), H).serve_forever()


if __name__ == '__main__':
    main()
