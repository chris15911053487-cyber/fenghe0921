# 成本执行台 · Mac / Linux 版服务（Python + hdbcli）。Mac 上双击 tools/启动成本执行台.command；Windows 用 tools\启动成本执行台.bat。
# 与 cost_console.ps1 实现同一套接口，读同一个 actions.json。
# 连接：有项目根目录 mtc_ca_conn.json（或 MTC_CA_CONN 指定的文件）时可直接使用，否则逐项输入；密码只在内存中使用。
# 用法：python3 tools/console/dev_server.py [端口，默认 8766]
import sys, os, re, json, time, threading, datetime, decimal, getpass, webbrowser
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from hdbcli import dbapi

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8766
MAX_ROWS = 2000

def ask_conf():
    p = os.environ.get('MTC_CA_CONN', os.path.join(ROOT, 'mtc_ca_conn.json'))
    if os.path.exists(p):
        c = json.load(open(p, encoding='utf-8'))
        a = input('使用连接文件：%s:%s / %s，账号 %s？（回车=是，N=重新输入）' % (c['address'], c['port'], c.get('databaseName', ''), c['user'])).strip()
        if a.upper() != 'N': return c
    c = {'address': input('HANA 服务器地址：').strip(),
         'port': int(input('端口（默认 30015）：').strip() or 30015),
         'databaseName': input('租户数据库名（没有直接回车）：').strip(),
         'user': input('数据库账号：').strip()}
    c['password'] = getpass.getpass('密码：')
    return c

conf = ask_conf()

def connect(schema=None):
    kw = {'databaseName': conf['databaseName']} if conf.get('databaseName') else {}
    if schema or conf.get('schema'): kw['currentSchema'] = schema or conf['schema']
    c = dbapi.connect(address=conf['address'], port=int(conf['port']), user=conf['user'], password=conf['password'], **kw)
    c.setautocommit(False)
    return c

def pick_schema():
    c = connect(); cur = c.cursor()
    cur.execute("SELECT DISTINCT SCHEMA_NAME FROM SYS.PROCEDURES WHERE PROCEDURE_NAME = 'MTC_CA_P_RUN' ORDER BY SCHEMA_NAME")
    cands = [r[0] for r in cur.fetchall()]; c.close()
    if not cands: print('没有找到已部署新框架（MTC_CA_P_RUN）的账套，请先用 部署包 部署。'); sys.exit(1)
    print('以下账套（SCHEMA）已部署新框架：')
    for i, n in enumerate(cands, 1): print('  [%d] %s' % (i, n))
    d = conf.get('schema') if conf.get('schema') in cands else (cands[0] if len(cands) == 1 else '')
    while True:
        v = input('请输入要使用的账套（编号或名称%s）：' % ('，直接回车 = ' + d if d else '')).strip() or d
        if v.isdigit() and 1 <= int(v) <= len(cands): return cands[int(v) - 1]
        hit = [n for n in cands if n.upper() == v.upper()]
        if hit: return hit[0]
        print('账套 %s 中没有新框架，请重新输入。' % v)

conf['schema'] = pick_schema()
conn = connect(); lock = threading.Lock()
SCHEMA = conf['schema']
job = {'state': 'idle'}

def load_actions(): return json.load(open(os.path.join(HERE, 'actions.json'), encoding='utf-8'))

def bind(spec, validators, args):
    vals = []
    for p in spec.get('params', []):
        v = str(args.get(p, '') if args.get(p) is not None else '')
        if not re.match(validators[p], v): raise ValueError('参数 %s 格式不对' % p)
        vals.append(v)
    return vals

def jv(v):
    if isinstance(v, decimal.Decimal): return float(v)
    if isinstance(v, (datetime.datetime, datetime.date)): return v.strftime('%Y-%m-%d %H:%M:%S').replace(' 00:00:00', '')
    if isinstance(v, (bytes, bytearray)): return v.hex()
    if hasattr(v, 'read'): return v.read()  # NCLOB（如过程定义）
    return v

def read_only(sql, vals):
    with lock:
        cur = conn.cursor()
        try:
            try: cur.execute('SET TRANSACTION READ ONLY')
            except Exception: pass
            cur.execute(sql, vals)
            cols = [d[0] for d in cur.description]
            rows = cur.fetchmany(MAX_ROWS + 1)
            return {'columns': cols, 'rows': [[jv(x) for x in r] for r in rows[:MAX_ROWS]], 'truncated': len(rows) > MAX_ROWS}
        finally:
            conn.rollback(); cur.close()

def need_confirm(spec, args):
    c = spec.get('confirm')
    return c == 'always' or (c == 'runTypeF' and args.get('runType') == 'F')

def exec_write(sql, vals):
    # 同步的小写操作（kind=exec，维护模拟场景）：普通事务，成功提交、失败回滚
    with lock:
        cur = conn.cursor()
        try:
            try: cur.execute('SET TRANSACTION READ WRITE')   # 查询时设成了只读，写之前改回来
            except Exception: pass
            cur.execute(sql, vals)
            res = {'columns': [d[0] for d in cur.description], 'rows': [[jv(x) for x in r] for r in cur.fetchall()]} if cur.description else {'columns': [], 'rows': []}
            conn.commit(); return res
        except Exception:
            conn.rollback(); raise
        finally:
            cur.close()

# AI 面板（设计稿 8.3 A 档）：页面把“将要发给大模型的内容”交给本机服务，服务先原样写入本地审计日志再决定是否发出。
# 用户 2026-10-13 决定暂不接大模型：一律不发出，返回“大模型未配置”。以后接入时只在这里加发送，审计日志照写。
AI_CONF = os.path.join(HERE, 'ai_config.json')
AUDIT_DIR = os.path.join(HERE, 'audit')
def ai_status():
    c = json.load(open(AI_CONF, encoding='utf-8')) if os.path.exists(AI_CONF) else {}
    return {'configured': False, 'provider': c.get('provider') or None,
            'reason': '大模型未配置（设计稿 Q30：用户 2026-10-13 决定先不接入）'}
def ai_chat(payload):
    st = ai_status()
    os.makedirs(AUDIT_DIR, exist_ok=True)
    fn = os.path.join(AUDIT_DIR, time.strftime('%Y-%m-%d') + '.jsonl')
    rec = {'time': time.strftime('%Y-%m-%d %H:%M:%S'), 'osUser': getpass.getuser(), 'schema': SCHEMA,
           'status': 'blocked', 'reason': st['reason'], 'payload': payload}
    with open(fn, 'a', encoding='utf-8') as f: f.write(json.dumps(rec, ensure_ascii=False) + '\n')
    return os.path.relpath(fn, ROOT), st['reason']

def run_job(spec, vals):
    c = None
    try:
        c = connect(); c.setautocommit(True)
        cur = c.cursor(); cur.execute(spec['sql'], vals)
        res = None
        if cur.description:
            res = {'columns': [d[0] for d in cur.description], 'rows': [[jv(x) for x in r] for r in cur.fetchall()]}
        job.update(state='done', result=res, end=time.time())
    except Exception as e:
        job.update(state='error', error=str(e), end=time.time())
    finally:
        if c: c.close()

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, code, ctype, body):
        self.send_response(code); self.send_header('Content-Type', ctype); self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store'); self.send_header('X-Content-Type-Options', 'nosniff'); self.end_headers(); self.wfile.write(body)
    def js(self, o): self.send(200, 'application/json; charset=utf-8', json.dumps(o, ensure_ascii=False).encode('utf-8'))
    def guard(self):
        if self.headers.get('Host') not in ('127.0.0.1:%d' % PORT, 'localhost:%d' % PORT): self.send(403, 'text/plain', b'forbidden'); return False
        if self.path.startswith('/api/') and self.headers.get('X-Requested-With') != 'cost-console': self.send(403, 'text/plain', b'forbidden'); return False
        return True
    def do_GET(self):
        if not self.guard(): return
        p = self.path.split('?')[0]
        if p in ('/', '/index.html'):
            return self.send(200, 'text/html; charset=utf-8', open(os.path.join(HERE, 'index.html'), 'rb').read())
        if p == '/api/info':
            try:
                r = read_only(load_actions()['actions']['ping']['sql'], [])['rows'][0]
                return self.js({'ok': True, 'conn': '%s:%s / %s' % (conf['address'], conf['port'], conf.get('databaseName', '')),
                                'user': r[0], 'schema': r[1], 'hasNew': bool(r[3]), 'osUser': getpass.getuser()})
            except Exception as e: return self.js({'ok': False, 'error': str(e)})
        if p == '/api/ai/status':
            r = ai_status(); r['ok'] = True; return self.js(r)
        if p == '/api/job':
            j = dict(job); st = j.get('start')
            if st: j['elapsed'] = int((j.get('end') or time.time()) - st)
            j['ok'] = True; return self.js(j)
        self.send(404, 'text/plain', b'not found')
    def do_POST(self):
        if not self.guard(): return
        p = self.path.split('?')[0]
        n = int(self.headers.get('Content-Length') or 0)
        if n > 1048576: return self.send(400, 'text/plain', b'too large')
        try: body = json.loads(self.rfile.read(n) or b'{}')
        except Exception: return self.js({'ok': False, 'error': '请求格式不对'})
        try:
            if p == '/api/q':
                d = load_actions(); spec = d['actions'].get(body.get('action'))
                if not spec or spec['kind'] != 'query': raise ValueError('不允许的查询')
                r = read_only(spec['sql'], bind(spec, d['validators'], body.get('args') or {}))
                r['ok'] = True; return self.js(r)
            if p == '/api/call':
                d = load_actions(); a = body.get('action'); spec = d['actions'].get(a); args = body.get('args') or {}
                if not spec or spec['kind'] != 'call': raise ValueError('不允许的操作')
                if need_confirm(spec, args) and str(args.get('confirm', '')).strip().upper() != SCHEMA.upper():
                    raise ValueError('确认的账套名与当前账套不一致')
                vals = bind(spec, d['validators'], args)
                if job.get('state') == 'running': raise ValueError('已有操作在运行，请等它结束')
                job.clear(); job.update(state='running', action=a, title=spec.get('title', a), start=time.time(), seen=False)
                print('%s  开始 %s %s' % (time.strftime('%H:%M:%S'), spec.get('title', a), vals))
                threading.Thread(target=run_job, args=(spec, vals), daemon=True).start()
                return self.js({'ok': True})
            if p == '/api/exec':
                d = load_actions(); spec = d['actions'].get(body.get('action'))
                if not spec or spec['kind'] != 'exec': raise ValueError('不允许的操作')
                r = exec_write(spec['sql'], bind(spec, d['validators'], body.get('args') or {}))
                print('%s  %s %s' % (time.strftime('%H:%M:%S'), body.get('action'), (r['rows'][0] if r['rows'] else '')))
                r['ok'] = True; return self.js(r)
            if p == '/api/ai/chat':
                payload = body.get('payload')
                if not isinstance(payload, dict): raise ValueError('请求格式不对')
                fn, reason = ai_chat(payload)
                return self.js({'ok': False, 'blocked': True, 'audit': fn, 'error': reason + '；本次内容没有发出，已记入本机审计日志 ' + fn})
            if p == '/api/job/ack':
                job['seen'] = True; return self.js({'ok': True})
        except Exception as e:
            return self.js({'ok': False, 'error': str(e)})
        self.send(404, 'text/plain', b'not found')

srv = None
for _ in range(10):
    try: srv = ThreadingHTTPServer(('127.0.0.1', PORT), H); break
    except OSError: PORT += 1
if srv is None: print('找不到可用端口'); sys.exit(1)
url = 'http://127.0.0.1:%d/' % PORT
print('\n已连接 HANA：%s:%s / %s，账号 %s，账套 %s' % (conf['address'], conf['port'], conf.get('databaseName', ''), conf['user'], SCHEMA))
print('执行台地址：' + url)
print('保持这个窗口打开；计算进行中关闭窗口会中断计算。按 Ctrl+C 停止服务。\n')
threading.Timer(0.5, lambda: webbrowser.open(url)).start()
try: srv.serve_forever()
except KeyboardInterrupt: print('已停止')
