# 成本执行台 · Python 版服务（hdbcli，没有时用本机 HANA ODBC 驱动，见 hana_odbc.py）。两种用法：
#   本机模式（默认）：Mac 上双击 tools/启动成本执行台.command；只监听 127.0.0.1，交互输入连接，不登录。
#   服务器模式（--server，2026-10-18）：部署在 Windows 服务器上给多人用。读 tools/console/server.json（或 MTC_CA_SERVER 指定的文件，
#     样例见 server.example.json），不交互；用 B1 账号登录（Service Layer /Login 验证密码，验证后立即登出），
#     权限取 OUSR 自定义字段（默认 U_MTC_CARole：R 查看 / O 操作 / A 管理），访问日志写 tools/console/logs/。
# 与 cost_console.ps1 实现同一套接口，读同一个 actions.json。
# 本机模式连接：有项目根目录 mtc_ca_conn.json（或 MTC_CA_CONN 指定的文件）时可直接使用，否则逐项输入；密码只在内存中使用。
# 用法：python3 tools/console/dev_server.py [端口，默认 8766]
#       python  tools\console\dev_server.py --server
import sys, os, re, json, time, threading, datetime, decimal, getpass, webbrowser, queue, secrets, ssl, ipaddress, contextlib
import urllib.request, urllib.error
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from hdbcli import dbapi
except ImportError:   # 2026-10-19：服务器上不装 hdbcli 时，直接用已装的 HANA Client ODBC 驱动（只需 Windows + HDBODBC）
    dbapi = None
    if os.name != 'nt':
        print('没有安装 hdbcli（pip3 install hdbcli）；只有 Windows 能改用 HANA ODBC 驱动。'); sys.exit(1)
import hana_odbc

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
SERVER = '--server' in sys.argv
ARGV = [a for a in sys.argv[1:] if not a.startswith('--')]
MAX_ROWS = 2000
EXPORT_MAX = 200000   # 表格“导出全部”时的上限（用户 2026-10-23）
LOG_DIR = os.path.join(HERE, 'logs')

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

def die(msg):
    print(msg); sys.exit(1)

if SERVER:
    CFG_PATH = os.environ.get('MTC_CA_SERVER', os.path.join(HERE, 'server.json'))
    if not os.path.exists(CFG_PATH): die('找不到服务器配置 %s，请复制 server.example.json 改好后再启动。' % CFG_PATH)
    CFG = json.load(open(CFG_PATH, encoding='utf-8'))
    if '--set-password' in sys.argv:
        # 加密 server.json 里的 HANA 密码（Windows DPAPI，2026-10-19）：交互输入两次，写回 "password": "dpapi:..."，不留明文备份
        if os.name != 'nt': die('只有 Windows 能加密密码（DPAPI）。')
        import dpapi
        p1 = getpass.getpass('HANA 数据库账号 %s 的密码：' % CFG['hana'].get('user', ''))
        if not p1 or p1 != getpass.getpass('再输入一次：'): die('两次输入不一致或为空，没有修改。')
        user_scope = '--user-scope' in sys.argv
        CFG['hana']['password'] = dpapi.protect(p1, machine=not user_scope)
        # 原地改写（不用临时文件替换），保留 server.json 上已设好的访问权限
        with open(CFG_PATH, 'w', encoding='utf-8') as f: json.dump(CFG, f, ensure_ascii=False, indent=2)
        print('已加密写入 %s（%s）。服务会在下次重启时使用。' % (CFG_PATH, '只有当前 Windows 账号 %s 能解开' % getpass.getuser() if user_scope else '只有这台服务器能解开'))
        sys.exit(0)
    conf = dict(CFG['hana']); conf['schema'] = CFG['schema']
    if str(conf.get('password', '')).startswith('dpapi:'):
        import dpapi
        try: conf['password'] = dpapi.unprotect(conf['password'])
        except Exception as e: die(str(e))
    PORT = int(CFG.get('port', 8766))
else:
    CFG = {}
    conf = ask_conf()
    PORT = int(ARGV[0]) if ARGV else 8766

def use_odbc():
    return dbapi is None or conf.get('via') == 'odbc'

def connect(schema=None):
    if use_odbc():
        c = hana_odbc.connect(hana_odbc.conn_str(conf, schema or conf.get('schema')))
        c.setautocommit(False)
        return c
    kw = {}
    if schema or conf.get('schema'): kw['currentSchema'] = schema or conf['schema']
    if conf.get('key'):   # hdbuserstore 键（服务器模式推荐，密码不落在配置文件里）
        c = dbapi.connect(key=conf['key'], **kw)
    else:
        if conf.get('databaseName'): kw['databaseName'] = conf['databaseName']
        c = dbapi.connect(address=conf['address'], port=int(conf['port']), user=conf['user'], password=conf['password'], **kw)
    c.setautocommit(False)
    return c

def conn_desc():
    if use_odbc() and conf.get('odbc'): return 'ODBC 连接串'
    if use_odbc() and conf.get('dsn'): return 'ODBC DSN ' + conf['dsn']
    return ('ODBC ' if use_odbc() else '') + ('hdbuserstore ' + conf['key'] if conf.get('key') else '%s:%s / %s' % (conf['address'], conf['port'], conf.get('databaseName', '')))

def deployed_schemas():
    c = connect(); cur = c.cursor()
    cur.execute("SELECT DISTINCT SCHEMA_NAME FROM SYS.PROCEDURES WHERE PROCEDURE_NAME = 'MTC_CA_P_RUN' ORDER BY SCHEMA_NAME")
    cands = [r[0] for r in cur.fetchall()]; c.close()
    return cands

def pick_schema():
    cands = deployed_schemas()
    if not cands: die('没有找到已部署新框架（MTC_CA_P_RUN）的账套，请先用 部署包 部署。')
    print('以下账套（SCHEMA）已部署新框架：')
    for i, n in enumerate(cands, 1): print('  [%d] %s' % (i, n))
    d = conf.get('schema') if conf.get('schema') in cands else (cands[0] if len(cands) == 1 else '')
    while True:
        v = input('请输入要使用的账套（编号或名称%s）：' % ('，直接回车 = ' + d if d else '')).strip() or d
        if v.isdigit() and 1 <= int(v) <= len(cands): return cands[int(v) - 1]
        hit = [n for n in cands if n.upper() == v.upper()]
        if hit: return hit[0]
        print('账套 %s 中没有新框架，请重新输入。' % v)

if SERVER:
    _c = deployed_schemas()
    if conf['schema'] not in _c:
        die('账套 %s 中没有新框架（MTC_CA_P_RUN），请先部署或检查 server.json 的 schema。当前数据库账号 %s 能看到已部署新框架的账套：%s'
            '（看不到某个已部署的账套时，是这个账号没有该账套的权限）。' % (conf['schema'], conf.get('user') or conf.get('key') or '', '、'.join(_c) or '无'))
else:
    conf['schema'] = pick_schema()
SCHEMA = conf['schema']
job = {'state': 'idle'}

# 连接池：多人同时查询时不再排队等一个连接（本机模式也用，默认 4 个）。连接断开（如 HANA 重启）时丢掉重建。
class Pool:
    def __init__(self, n):
        self.idle = queue.LifoQueue(); self.sem = threading.BoundedSemaphore(n)
    @contextlib.contextmanager
    def get(self):
        self.sem.acquire()
        c = None
        try:
            try: c = self.idle.get_nowait()
            except queue.Empty: c = connect()
            yield c
        finally:
            alive = False
            if c is not None:
                try: alive = c.isconnected()
                except Exception: pass
            if alive: self.idle.put(c)
            elif c is not None:
                try: c.close()
                except Exception: pass
            self.sem.release()
pool = Pool(int(CFG.get('poolSize', 4)))

def load_actions():
    d = json.load(open(os.path.join(HERE, 'actions.json'), encoding='utf-8'))
    # sqlFile：语句放在单独的 .sql 文件里（取数 SQL，带分段注释，用户 2026-10-19）；resultSql 替换文件中“-- @result”之后的输出段
    for spec in d['actions'].values():
        if spec.get('sqlFile'):
            t = open(os.path.join(HERE, spec['sqlFile']), encoding='utf-8-sig').read()
            if spec.get('resultSql'): t = t[:t.index('-- @result')] + spec['resultSql']
            spec['sql'] = t.strip()
    return d

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

def read_only(sql, vals, limit=MAX_ROWS):
    with pool.get() as conn:
        cur = conn.cursor()
        try:
            try: cur.execute('SET TRANSACTION READ ONLY')
            except Exception: pass
            cur.execute(sql, vals)
            cols = [d[0] for d in cur.description]
            rows = cur.fetchmany(limit + 1)
            return {'columns': cols, 'rows': [[jv(x) for x in r] for r in rows[:limit]], 'truncated': len(rows) > limit}
        finally:
            try: conn.rollback()
            except Exception: pass
            cur.close()

def need_confirm(spec, args):
    c = spec.get('confirm')
    return c == 'always' or (c == 'runTypeF' and args.get('runType') == 'F')

def exec_write(sql, vals):
    # 同步的小写操作（kind=exec，维护模拟场景）：普通事务，成功提交、失败回滚
    with pool.get() as conn:
        cur = conn.cursor()
        try:
            try: cur.execute('SET TRANSACTION READ WRITE')   # 查询时设成了只读，写之前改回来
            except Exception: pass
            cur.execute(sql, vals)
            res = {'columns': [d[0] for d in cur.description], 'rows': [[jv(x) for x in r] for r in cur.fetchall()]} if cur.description else {'columns': [], 'rows': []}
            conn.commit(); return res
        except Exception:
            try: conn.rollback()
            except Exception: pass
            raise
        finally:
            cur.close()

# ---------------- 服务器模式：登录、权限、访问日志 ----------------
ROLE_NAME = {'R': '查看', 'O': '操作', 'A': '管理'}
ROLE_RANK = {'R': 1, 'O': 2, 'A': 3}
ROLE_FIELD = CFG.get('roleField', 'U_MTC_CARole')
if SERVER and not re.match(r'^U_[A-Za-z0-9_]{1,50}$', ROLE_FIELD): die('server.json 的 roleField 格式不对：%s' % ROLE_FIELD)
SESS = {}; SESS_LOCK = threading.Lock()
IDLE_SEC = int(CFG.get('idleMinutes', 480)) * 60
FAILS = {}   # 客户端地址 -> [失败时间]，5 分钟内失败 5 次就暂停登录
NETS = [ipaddress.ip_network(n, strict=False) for n in CFG.get('allowNets', [])]
TLS = bool(CFG.get('tls'))

def access_log(rec):
    if not SERVER: return
    os.makedirs(LOG_DIR, exist_ok=True)
    rec = dict({'time': time.strftime('%Y-%m-%d %H:%M:%S')}, **rec)
    with open(os.path.join(LOG_DIR, 'access-' + time.strftime('%Y-%m') + '.jsonl'), 'a', encoding='utf-8') as f:
        f.write(json.dumps(rec, ensure_ascii=False) + '\n')

def sl_err(e):
    try: return json.loads(e.read().decode('utf-8'))['error']['message']['value']
    except Exception: return 'HTTP %s' % e.code

class SL:
    # B1 Service Layer 会话（用登录人自己的 B1 账号）。登录验证用完即登出；生成凭单时在一次请求里登录、建单、登出（2026-10-19）。
    def __init__(self, user, pwd):
        sl = CFG['sl']; self.base = sl['url'].rstrip('/'); self.cookie = None
        self.ctx = ssl.create_default_context()
        if not sl.get('verify', False): self.ctx.check_hostname = False; self.ctx.verify_mode = ssl.CERT_NONE
        self.login = {'CompanyDB': sl.get('company', SCHEMA), 'UserName': user, 'Password': pwd}
    def open(self):
        req = urllib.request.Request(self.base + '/Login', data=json.dumps(self.login).encode('utf-8'), headers={'Content-Type': 'application/json'}, method='POST')
        try:
            r = urllib.request.urlopen(req, context=self.ctx, timeout=30)
        except urllib.error.HTTPError as e:
            return False, sl_err(e)
        except Exception as e:
            raise RuntimeError('连不上 Service Layer（%s）：%s' % (self.base, e))
        self.cookie = '; '.join(h.split(';')[0] for h in r.headers.get_all('Set-Cookie') or [])
        return True, ''
    def post(self, path, obj):
        req = urllib.request.Request(self.base + path, data=json.dumps(obj, ensure_ascii=False).encode('utf-8'),
                                     headers={'Content-Type': 'application/json', 'Cookie': self.cookie}, method='POST')
        try:
            r = urllib.request.urlopen(req, context=self.ctx, timeout=120)
            t = r.read().decode('utf-8', 'replace')
            return True, (json.loads(t) if t.strip() else {})
        except urllib.error.HTTPError as e:
            return False, sl_err(e)
    def close(self):
        if not self.cookie: return
        try: urllib.request.urlopen(urllib.request.Request(self.base + '/Logout', data=b'', headers={'Cookie': self.cookie}, method='POST'), context=self.ctx, timeout=10)
        except Exception: pass
        self.cookie = None

def sl_login(user, pwd):
    # 用 B1 Service Layer 验证账号密码（OUSR 里的密码是加密的，不能读表比对）；成功后立即登出，不占用会话。
    s = SL(user, pwd); ok, msg = s.open(); s.close()
    return ok, msg

def user_role(user):
    r = read_only('SELECT "USER_CODE", "U_NAME", "%s" FROM "OUSR" WHERE "USER_CODE" = ?' % ROLE_FIELD, [user])
    if not r['rows']: return None
    code, name, role = r['rows'][0]
    return {'user': code, 'name': name or code, 'role': (role or '').strip().upper()}

def check_role_field():
    r = read_only('SELECT COUNT(*) FROM "CUFD" WHERE "TableID" = \'OUSR\' AND "AliasID" = ?', [ROLE_FIELD[2:]])
    if not r['rows'][0][0]:
        die('B1 用户表 OUSR 还没有自定义字段 %s。请在 B1 前台“工具 → 定制工具 → 用户定义字段 - 管理 → 设置 → 常规 → 用户”添加（见 README“服务器部署”第 5 步）。' % ROLE_FIELD)

def new_session(info):
    sid = secrets.token_urlsafe(32)
    with SESS_LOCK:
        now = time.time()
        for k in [k for k, v in SESS.items() if v['exp'] < now]: SESS.pop(k, None)
        SESS[sid] = dict(info, exp=now + IDLE_SEC)
    return sid

def need_rank(spec, args):
    if spec['kind'] == 'query': return 'R'
    return 'A' if need_confirm(spec, args) else spec.get('role', 'O')

# AI 面板（设计稿 8.3 A 档）：页面把“将要发给大模型的内容”交给本机服务，服务先原样写入本地审计日志再决定是否发出。
# 用户 2026-10-13 决定暂不接大模型：一律不发出，返回“大模型未配置”。以后接入时只在这里加发送，审计日志照写。
AI_CONF = os.path.join(HERE, 'ai_config.json')
AUDIT_DIR = os.path.join(HERE, 'audit')
def ai_status():
    c = json.load(open(AI_CONF, encoding='utf-8')) if os.path.exists(AI_CONF) else {}
    return {'configured': False, 'provider': c.get('provider') or None,
            'reason': '大模型未配置（设计稿 Q30：用户 2026-10-13 决定先不接入）'}
def ai_chat(payload, who):
    st = ai_status()
    os.makedirs(AUDIT_DIR, exist_ok=True)
    fn = os.path.join(AUDIT_DIR, time.strftime('%Y-%m-%d') + '.jsonl')
    rec = {'time': time.strftime('%Y-%m-%d %H:%M:%S'), 'osUser': who, 'schema': SCHEMA,
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
        access_log({'event': 'job-end', 'action': job.get('action'), 'user': job.get('by'), 'state': job.get('state'), 'error': job.get('error')})

JOB_LOCK = threading.Lock()

# ---------------- 生成 SAP 日记账凭单（用户 2026-10-19，设计稿 8.6，Q36 / Q41–Q44）----------------
# 只在服务器模式：用操作人自己的 B1 账号经 Service Layer JournalVouchersService_Add 建 OBTF（一种凭证代码一张），
# 表头 Ref1 = 'MTC_CA#运行号'，建完按 Ref1 + 凭证代码找回批号（同用户插件，2026-10-19），再回写 OBTD.Remarks，
# 下月冲销的代码（参数 JV_REV_TRANSCODES，AR03 / AR04）回写 OBTF.AutoStorno / StornoDate；有 UDF U_MTC_CARunId 时顺带写运行号。
# 结果记 MTC_CA_JV，全部成功后账期状态 POSTED（MTC_CA_P_JV_FINISH）。
JV_LOCK = threading.Lock()
JV_UDF = 'MTC_CARunId'
SQL_JV_LINES = (
    'SELECT J."LineNo", IFNULL(A1."AcctCode", A2."AcctCode") AS "Acct", J."Debit", J."Credit", J."OcrCode", J."Project", J."VendorCode", '
    'J."TransName", J."RefDate" FROM "MTC_CA_R_JDT" J '
    'LEFT JOIN "OACT" A1 ON A1."AcctCode" = J."AcctCode" '
    'LEFT JOIN (SELECT "FormatCode", MAX("AcctCode") AS "AcctCode" FROM "OACT" WHERE IFNULL("FormatCode", \'\') <> \'\' GROUP BY "FormatCode") A2 '
    'ON A1."AcctCode" IS NULL AND A2."FormatCode" = J."AcctCode" '
    'WHERE J."RunId" = ? AND J."TransCode" = ? AND (J."Debit" <> 0 OR J."Credit" <> 0) ORDER BY J."LineNo"')
SQL_JV_FIND = 'SELECT MAX("BatchNum") FROM "OBTF" WHERE "Ref1" = ? AND "TransCode" = ? AND "BtfStatus" = \'O\''

def first_row(r):
    return dict(zip(r['columns'], r['rows'][0])) if r['rows'] else {}

def udf_exists(table, alias):
    return bool(read_only('SELECT COUNT(*) FROM "CUFD" WHERE "TableID" = ? AND "AliasID" = ?', [table, alias])['rows'][0][0])

def jv_ref(rid): return 'MTC_CA#%s' % rid

def jv_find(rid, code):
    v = read_only(SQL_JV_FIND, [jv_ref(rid), code])['rows'][0][0]
    return int(v) if v is not None else None

def jv_after(bn, memo, rev_date):
    # 同用户插件：建好后回写凭单批备注；需要下月冲销的勾选冲销并写冲销日期（DI / Service Layer 建日记账凭单时设不了这两项）
    exec_write('UPDATE "OBTD" SET "Remarks" = ? WHERE "BatchNum" = ?', [memo, str(bn)])
    if rev_date:
        exec_write('UPDATE "OBTF" SET "AutoStorno" = \'Y\', "StornoDate" = ? WHERE "BatchNum" = ?', [rev_date, str(bn)])

def jv_body(rid, fc, code, rows, vendor_udf, run_udf=False, rev_date=None):
    lines = []; dr = cr = decimal.Decimal(0); ref = name = None
    for x in rows:
        o = dict(zip(['LineNo', 'Acct', 'Debit', 'Credit', 'OcrCode', 'Project', 'VendorCode', 'TransName', 'RefDate'], x))
        ref = ref or str(o['RefDate'])[:10]; name = name or (o['TransName'] or '')
        if not o['Acct']: raise ValueError('%s 第 %s 行科目在 OACT 中不存在' % (code, o['LineNo']))
        amt = (decimal.Decimal(str(o['Debit'] or 0)) - decimal.Decimal(str(o['Credit'] or 0))).quantize(decimal.Decimal('0.01'))
        if amt == 0: continue
        ln = {'AccountCode': o['Acct'], 'Debit': float(amt) if amt > 0 else 0.0, 'Credit': float(-amt) if amt < 0 else 0.0}
        if amt > 0: dr += amt
        else: cr -= amt
        if o['OcrCode']: ln['CostingCode'] = o['OcrCode']
        if o['Project']: ln['ProjectCode'] = o['Project']
        if name: ln['LineMemo'] = name[:50]
        if vendor_udf and o['VendorCode']: ln['U_VendorCode'] = o['VendorCode']
        lines.append(ln)
    if not lines: raise ValueError('%s 没有非零分录' % code)
    if dr != cr: raise ValueError('%s 借贷不平：借 %s，贷 %s' % (code, dr, cr))
    je = {'ReferenceDate': ref, 'TaxDate': ref, 'DueDate': ref, 'TransactionCode': code,
          'Memo': ('成本 %s %s %s' % (fc, code, name))[:50], 'Reference': jv_ref(rid), 'JournalEntryLines': lines}
    if run_udf: je['U_' + JV_UDF] = int(rid)
    if rev_date: je['Reference2'] = '冲销 ' + rev_date
    return {'JournalVoucher': {'JournalEntry': je}}, dr, cr, len(lines)

def jv_log(fc, rid, code, bn, status, dr, cr, n, user, msg):
    exec_write('CALL "MTC_CA_P_JV_LOG"(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
               [fc, str(rid), code, '' if bn is None else str(bn), status, '' if dr is None else str(dr), '' if cr is None else str(cr),
                '' if n is None else str(n), user, (msg or '')[:2000]])

def jv_create(fc, codes, pwd, user):
    r = first_row(exec_write('CALL "MTC_CA_P_JV_BEGIN"(?, ?)', [fc, user]))
    if int(r.get('Code', -1)) != 0: raise ValueError(r.get('Msg') or '不能生成凭单')
    rid = int(r['RunId'])
    plan = {x['TransCode']: x for x in (dict(zip(pr['columns'], row)) for pr in [read_only('SELECT * FROM "MTC_CA_F_JV_PLAN"(?)', [fc])] for row in pr['rows'])}
    bad = [c for c in codes if c not in plan or plan[c]['State'] != 'READY']
    if bad: raise ValueError('这些凭证代码现在不能生成：' + '、'.join('%s（%s）' % (c, plan[c]['StateMsg'] if c in plan else '底稿里没有') for c in bad))
    done = []
    if codes:
        run_udf = udf_exists('OJDT', JV_UDF)   # 可选：有就写运行号
        vendor_udf = udf_exists('JDT1', 'VendorCode')
        bodies = {}; revs = {}
        for c in codes:
            revs[c] = str(plan[c]['RevDate'])[:10] if plan[c].get('AutoRev') == 'Y' and plan[c].get('RevDate') else None
            if plan[c].get('AutoRev') == 'Y' and not revs[c]: raise ValueError('%s 要下月冲销，但 OFPR 里没有下一个账期，取不到冲销日期' % c)
            bodies[c] = jv_body(rid, fc, c, read_only(SQL_JV_LINES, [str(rid), c])['rows'], vendor_udf, run_udf, revs[c])
        sl = SL(user, pwd); ok, msg = sl.open()
        if not ok: raise ValueError('B1 登录失败：' + msg)
        try:
            for c in codes:
                body, dr, cr, n = bodies[c]
                bn = jv_find(rid, c)   # 上次提交成功但没记上（如超时）：不重复建
                if bn is None:
                    # 日记账凭单在 Service Layer 里是服务（JournalVouchersService_Add）；/JournalVouchers 报“Unrecognized resource path”（2026-10-19 实测），
                    # 个别版本若不认服务路径再退回实体路径
                    ok, res = sl.post('/JournalVouchersService_Add', body)
                    if not ok and 'resource path' in str(res).lower():
                        ok, res = sl.post('/JournalVouchers', body)
                    if not ok:
                        jv_log(fc, rid, c, None, 'FAIL', dr, cr, n, user, res)
                        done.append({'TransCode': c, 'ok': False, 'msg': res}); break
                    bn = jv_find(rid, c)
                    if bn is None:
                        m = 'Service Layer 返回成功，但按参考号 Ref1 = %s、凭证代码 %s 在未清凭单里找不到这张凭单，请在 B1 里核对' % (jv_ref(rid), c)
                        jv_log(fc, rid, c, None, 'FAIL', dr, cr, n, user, m)
                        done.append({'TransCode': c, 'ok': False, 'msg': m}); break
                memo = body['JournalVoucher']['JournalEntry']['Memo']
                try: jv_after(bn, memo, revs[c])
                except Exception as e:
                    m = '凭单已建（批号 %s），但回写备注 / 冲销标记失败：%s；请在 B1 里手工补上%s' % (bn, e, '冲销勾选和冲销日期 ' + revs[c] if revs[c] else '备注')
                    jv_log(fc, rid, c, bn, 'CREATED', dr, cr, n, user, m)
                    done.append({'TransCode': c, 'ok': True, 'BatchNum': bn, 'Debit': float(dr), 'Credit': float(cr), 'LineCnt': n, 'msg': m}); continue
                jv_log(fc, rid, c, bn, 'CREATED', dr, cr, n, user, ('下月冲销 ' + revs[c]) if revs[c] else '')
                done.append({'TransCode': c, 'ok': True, 'BatchNum': bn, 'Debit': float(dr), 'Credit': float(cr), 'LineCnt': n, 'msg': ('下月冲销 ' + revs[c]) if revs[c] else ''})
        finally:
            sl.close()
    failed = [d for d in done if not d['ok']]
    fin = {}
    if not failed: fin = first_row(exec_write('CALL "MTC_CA_P_JV_FINISH"(?, ?, ?)', [fc, str(rid), user]))
    return {'runId': rid, 'done': done, 'failed': bool(failed), 'finish': fin}

class H(BaseHTTPRequestHandler):
    timeout = 120
    login = None
    def log_message(self, *a): pass
    def send(self, code, ctype, body, extra=()):
        self.send_response(code); self.send_header('Content-Type', ctype); self.send_header('Content-Length', str(len(body)))
        for k, v in extra: self.send_header(k, v)
        self.send_header('Cache-Control', 'no-store'); self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('X-Frame-Options', 'DENY'); self.send_header('Referrer-Policy', 'no-referrer')
        self.end_headers(); self.wfile.write(body)
    def js(self, o, extra=()): self.send(200, 'application/json; charset=utf-8', json.dumps(o, ensure_ascii=False).encode('utf-8'), extra)
    def ip(self): return self.client_address[0]
    def who(self): return self.login['user'] if self.login else getpass.getuser()
    def cookie_sid(self):
        m = re.search(r'(?:^|;\s*)cc_sid=([A-Za-z0-9_\-]+)', self.headers.get('Cookie') or '')
        return m.group(1) if m else None
    def guard(self):
        p = self.path.split('?')[0]
        if not SERVER:
            if self.headers.get('Host') not in ('127.0.0.1:%d' % PORT, 'localhost:%d' % PORT): self.send(403, 'text/plain', b'forbidden'); return False
        elif NETS:
            try: a = ipaddress.ip_address(self.ip())
            except ValueError: a = None
            if a is None or not any(a in n for n in NETS): self.send(403, 'text/plain', b'forbidden'); return False
        if p.startswith('/api/') and self.headers.get('X-Requested-With') != 'cost-console': self.send(403, 'text/plain', b'forbidden'); return False
        if SERVER and p not in ('/api/login', '/login.html'):
            sid = self.cookie_sid()
            with SESS_LOCK:
                s = SESS.get(sid) if sid else None
                if s and s['exp'] < time.time(): SESS.pop(sid, None); s = None
                if s: s['exp'] = time.time() + IDLE_SEC
            if not s:
                if p.startswith('/api/'): self.js({'ok': False, 'auth': True, 'error': '请先登录（或登录已过期）'})
                else: self.send(302, 'text/plain', b'', (('Location', '/login.html'),))
                return False
            self.login = s
        return True
    def do_GET(self):
        if not self.guard(): return
        p = self.path.split('?')[0]
        if p in ('/', '/index.html'):
            return self.send(200, 'text/html; charset=utf-8', open(os.path.join(HERE, 'index.html'), 'rb').read())
        # 页面的样式和脚本（2026-10-23 拆分）：只认 css/*.css、js/*.js，文件名只能是小写字母、数字、下划线；服务器模式同样要先登录
        m = re.match(r'^/(css|js)/([a-z0-9_]+)\.(css|js)$', p)
        if m and m.group(1) == m.group(3):
            f = os.path.join(HERE, m.group(1), m.group(2) + '.' + m.group(3))
            if os.path.isfile(f):
                return self.send(200, ('text/css' if m.group(3) == 'css' else 'text/javascript') + '; charset=utf-8', open(f, 'rb').read())
        if p == '/login.html' and SERVER:
            return self.send(200, 'text/html; charset=utf-8', open(os.path.join(HERE, 'login.html'), 'rb').read())
        if p == '/api/info':
            try:
                r = read_only(load_actions()['actions']['ping']['sql'], [])['rows'][0]
                o = {'ok': True, 'conn': conn_desc(), 'user': r[0], 'schema': r[1], 'hasNew': bool(r[3]), 'osUser': self.who()}
                if self.login: o['login'] = {k: self.login[k] for k in ('user', 'name', 'role')}; o['login']['roleName'] = ROLE_NAME.get(self.login['role'], '')
                return self.js(o)
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
            if p == '/api/login' and SERVER: return self.do_login(body)
            if p == '/api/logout' and SERVER:
                with SESS_LOCK: SESS.pop(self.cookie_sid(), None)
                access_log({'event': 'logout', 'user': self.who(), 'ip': self.ip()})
                return self.js({'ok': True}, (('Set-Cookie', 'cc_sid=; Path=/; Max-Age=0; HttpOnly; SameSite=Strict'),))
            if p == '/api/sql':
                # 页面“SQL”按钮：返回只读查询（kind=query）登记的语句和参数名，不执行（用户 2026-10-18）
                spec = load_actions()['actions'].get(body.get('action'))
                if not spec or spec['kind'] != 'query': raise ValueError('不允许的查询')
                return self.js({'ok': True, 'action': body.get('action'), 'title': spec.get('title', ''), 'sql': spec['sql'], 'params': spec.get('params', [])})
            if p == '/api/q':
                d = load_actions(); spec = d['actions'].get(body.get('action'))
                if not spec or spec['kind'] != 'query': raise ValueError('不允许的查询')
                # all：表格“导出全部”，不受页面 2000 行限制
                r = read_only(spec['sql'], bind(spec, d['validators'], body.get('args') or {}), EXPORT_MAX if body.get('all') is True else MAX_ROWS)
                r['ok'] = True; return self.js(r)
            if p in ('/api/call', '/api/exec'):
                d = load_actions(); a = body.get('action'); spec = d['actions'].get(a); args = dict(body.get('args') or {})
                if not spec or spec['kind'] != p[5:]: raise ValueError('不允许的操作')
                if self.login:
                    need = need_rank(spec, args)
                    if ROLE_RANK.get(self.login['role'], 0) < ROLE_RANK[need]:
                        access_log({'event': 'denied', 'action': a, 'user': self.who(), 'ip': self.ip(), 'need': need})
                        raise ValueError('没有权限：%s 需要“%s”权限，你的权限是“%s”。请找管理员在 B1 用户主数据的 %s 字段调整。'
                                         % (spec.get('title', a), ROLE_NAME[need], ROLE_NAME.get(self.login['role'], '无'), ROLE_FIELD))
                    if 'user' in spec.get('params', []): args['user'] = self.login['user']   # 操作人以登录账号为准
                if need_confirm(spec, args) and str(args.get('confirm', '')).strip().upper() != SCHEMA.upper():
                    raise ValueError('确认的账套名与当前账套不一致')
                vals = bind(spec, d['validators'], args)
                if spec['kind'] == 'exec':
                    r = exec_write(spec['sql'], vals)
                    print('%s  %s %s %s' % (time.strftime('%H:%M:%S'), self.who(), a, (r['rows'][0] if r['rows'] else '')))
                    access_log({'event': 'exec', 'action': a, 'user': self.who(), 'ip': self.ip(), 'args': vals})
                    r['ok'] = True; return self.js(r)
                if JV_LOCK.locked(): raise ValueError('正在生成凭单，请等它结束')
                with JOB_LOCK:
                    if job.get('state') == 'running': raise ValueError('已有操作在运行（%s 发起的 %s），请等它结束' % (job.get('by', ''), job.get('title', '')))
                    job.clear(); job.update(state='running', action=a, title=spec.get('title', a), start=time.time(), seen=False, by=self.who())
                print('%s  %s 开始 %s %s' % (time.strftime('%H:%M:%S'), self.who(), spec.get('title', a), vals))
                access_log({'event': 'call', 'action': a, 'user': self.who(), 'ip': self.ip(), 'args': vals})
                threading.Thread(target=run_job, args=(spec, vals), daemon=True).start()
                return self.js({'ok': True})
            if p in ('/api/jv/create', '/api/jv/undo'):
                if not SERVER: raise ValueError('生成凭单只在服务器模式下可用（要用 B1 账号登录、经 Service Layer 建单）')
                if ROLE_RANK.get(self.login['role'], 0) < ROLE_RANK['A']:
                    access_log({'event': 'denied', 'action': p, 'user': self.who(), 'ip': self.ip(), 'need': 'A'})
                    raise ValueError('没有权限：生成 / 撤销凭单需要“管理”权限')
                fc = str(body.get('fc') or '')
                if not re.match(r'^\d{4}-\d{2}$', fc): raise ValueError('账期格式不对')
                if str(body.get('confirm', '')).strip().upper() != SCHEMA.upper(): raise ValueError('确认的账套名与当前账套不一致')
                if not JV_LOCK.acquire(blocking=False): raise ValueError('有人正在生成或撤销凭单，请稍后')
                try:
                    if job.get('state') == 'running': raise ValueError('有计算正在运行（%s 发起），等它结束再操作凭单' % job.get('by', ''))
                    if p == '/api/jv/undo':
                        r = first_row(exec_write('CALL "MTC_CA_P_JV_UNDO"(?, ?)', [fc, self.who()]))
                        access_log({'event': 'jv-undo', 'user': self.who(), 'ip': self.ip(), 'fc': fc, 'code': r.get('Code'), 'msg': r.get('Msg')})
                        if int(r.get('Code', -1)) != 0: raise ValueError(r.get('Msg') or '撤销失败')
                        return self.js({'ok': True, 'msg': r.get('Msg')})
                    codes = body.get('codes') or []
                    if not isinstance(codes, list) or len(codes) > 100 or not all(isinstance(c, str) and re.match(r'^[A-Za-z0-9]{2,10}$', c) for c in codes):
                        raise ValueError('凭证代码格式不对')
                    pwd = str(body.get('password') or '')
                    if codes and not pwd: raise ValueError('请输入你的 B1 密码（用你的账号在 B1 建凭单）')
                    print('%s  %s 生成凭单 %s %s' % (time.strftime('%H:%M:%S'), self.who(), fc, codes))
                    res = jv_create(fc, codes, pwd, self.who())
                    access_log({'event': 'jv-create', 'user': self.who(), 'ip': self.ip(), 'fc': fc, 'runId': res['runId'],
                                'done': [(d['TransCode'], d.get('BatchNum'), d['ok']) for d in res['done']], 'finish': res['finish'].get('Msg')})
                    res['ok'] = True; return self.js(res)
                finally:
                    JV_LOCK.release()
            if p == '/api/ai/chat':
                payload = body.get('payload')
                if not isinstance(payload, dict): raise ValueError('请求格式不对')
                fn, reason = ai_chat(payload, self.who())
                return self.js({'ok': False, 'blocked': True, 'audit': fn, 'error': reason + '；本次内容没有发出，已记入服务器审计日志 ' + fn})
            if p == '/api/job/ack':
                job['seen'] = True; return self.js({'ok': True})
        except Exception as e:
            return self.js({'ok': False, 'error': str(e)})
        self.send(404, 'text/plain', b'not found')
    def do_login(self, body):
        ip = self.ip(); now = time.time()
        fl = [t for t in FAILS.get(ip, []) if t > now - 300]; FAILS[ip] = fl
        if len(fl) >= 5: return self.js({'ok': False, 'error': '登录失败次数过多，请 5 分钟后再试'})
        user = str(body.get('user') or '').strip(); pwd = str(body.get('password') or '')
        if not user or not pwd or len(user) > 50: return self.js({'ok': False, 'error': '请输入 B1 账号和密码'})
        ok, msg = sl_login(user, pwd)
        if not ok:
            fl.append(now); access_log({'event': 'login-fail', 'user': user, 'ip': ip, 'msg': msg})
            return self.js({'ok': False, 'error': 'B1 登录失败：' + msg})
        info = user_role(user)
        if not info or info['role'] not in ROLE_RANK:
            access_log({'event': 'login-norole', 'user': user, 'ip': ip})
            return self.js({'ok': False, 'error': '账号 %s 没有成本执行台权限（B1 用户主数据 %s 为空），请找管理员开通。' % (user, ROLE_FIELD)})
        FAILS.pop(ip, None)
        sid = new_session(info)
        access_log({'event': 'login', 'user': info['user'], 'role': info['role'], 'ip': ip})
        print('%s  登录 %s（%s）%s' % (time.strftime('%H:%M:%S'), info['user'], ROLE_NAME[info['role']], ip))
        ck = 'cc_sid=%s; Path=/; HttpOnly; SameSite=Strict%s' % (sid, '; Secure' if TLS else '')
        return self.js({'ok': True}, (('Set-Cookie', ck),))

if SERVER:
    check_role_field()
    srv = ThreadingHTTPServer((CFG.get('listen', '0.0.0.0'), PORT), H)
    if TLS:
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(os.path.join(HERE, CFG['tls']['cert']), os.path.join(HERE, CFG['tls']['key']))
        srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
    url = '%s://<服务器名>:%d/' % ('https' if TLS else 'http', PORT)
    print('\n%s 成本执行台服务器模式：HANA %s，账套 %s，监听 %s:%d' % (time.strftime('%Y-%m-%d %H:%M:%S'), conn_desc(), SCHEMA, CFG.get('listen', '0.0.0.0'), PORT))
    print('访问地址：' + url + '（用 B1 账号登录）')
    try: srv.serve_forever()
    except KeyboardInterrupt: print('已停止')
    sys.exit(0)

srv = None
for _ in range(10):
    try: srv = ThreadingHTTPServer(('127.0.0.1', PORT), H); break
    except OSError: PORT += 1
if srv is None: print('找不到可用端口'); sys.exit(1)
url = 'http://127.0.0.1:%d/' % PORT
print('\n已连接 HANA：%s，账号 %s，账套 %s' % (conn_desc(), conf.get('user', ''), SCHEMA))
print('执行台地址：' + url)
print('保持这个窗口打开；计算进行中关闭窗口会中断计算。按 Ctrl+C 停止服务。\n')
threading.Timer(0.5, lambda: webbrowser.open(url)).start()
try: srv.serve_forever()
except KeyboardInterrupt: print('已停止')
