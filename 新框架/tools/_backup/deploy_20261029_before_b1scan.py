# FH100 成本核算部署包执行程序（Python 版，需要 pip install hdbcli）
# 用法：python3 deploy.py                      逐项输入服务器、租户、账号、密码、schema
#       python3 deploy.py --conn 连接.json      {"address":…,"port":…,"user":…,"password":…,"databaseName":…,"schema":…}
#       加 --yes 跳过确认（无人值守）
# 执行 同目录 全部部署.sql：已有的表 / 索引 / 序列 / 旧模块视图和过程跳过，不覆盖；视图和过程因依赖顺序失败的会自动重试。
# 日志写到同目录 部署日志_<时间>.txt，只记录语句状态，不含业务数据。
import sys, os, re, json, getpass, datetime
from hdbcli import dbapi

HERE = os.path.dirname(os.path.abspath(__file__))
args = sys.argv[1:]
conf = {}
if '--conn' in args:
    conf = json.load(open(args[args.index('--conn') + 1], encoding='utf-8'))
else:
    conf['address'] = input('HANA 服务器地址：').strip()
    conf['port'] = int(input('端口（默认 30015）：').strip() or 30015)
    conf['databaseName'] = input('租户数据库名（没有直接回车）：').strip()
    conf['user'] = input('账号：').strip()
    conf['password'] = getpass.getpass('密码：')
    conf['schema'] = input('目标 schema：').strip()
kw = {'databaseName': conf['databaseName']} if conf.get('databaseName') else {}
conn = dbapi.connect(address=conf['address'], port=int(conf['port']), user=conf['user'], password=conf['password'],
                     currentSchema=conf['schema'], **kw)
conn.setautocommit(True)
cur = conn.cursor()
def q(sql, *a):
    cur.execute(sql, a); return cur.fetchall()

text = open(os.path.join(HERE, '全部部署.sql'), encoding='utf-8').read().replace('\r\n', '\n')
parts = text.split('\n@@\n')
header, body = parts[0], parts[1:]
stmts = []
for p in body:
    first, _, sql = p.partition('\n')
    stmts.append((first.replace('-- @stmt ', '').strip(), sql.strip()))

log_lines = []
def out(*a):
    s = '\t'.join(str(x) for x in a); print(s); log_lines.append(s)

# 1. 确认目标
u, sch, db = q('SELECT CURRENT_USER, CURRENT_SCHEMA, (SELECT DATABASE_NAME FROM SYS.M_DATABASE) FROM DUMMY')[0]
n_old = q("SELECT COUNT(*) FROM SYS.PROCEDURES WHERE SCHEMA_NAME = CURRENT_SCHEMA AND PROCEDURE_NAME LIKE 'MTC_COST_PROC%'")[0][0]
n_new = q("SELECT COUNT(*) FROM SYS.OBJECTS WHERE SCHEMA_NAME = CURRENT_SCHEMA AND OBJECT_NAME LIKE 'MTC\\_CA\\_%' ESCAPE '\\'")[0][0]
out('目标', '账号 %s，租户 %s，schema %s；已有旧模块过程 %d 个、新框架对象 %d 个' % (u, db, sch, n_old, n_new))
if sch.upper() != conf['schema'].upper():
    out('错误', 'schema %s 不存在或无权限' % conf['schema']); sys.exit(1)

# 2. 检查 B1 自定义表和字段
miss = []
for t, cs in re.findall(r'^-- @require ([^:]+): (.*)$', header, re.M):
    have = {r[0] for r in q('SELECT COLUMN_NAME FROM SYS.TABLE_COLUMNS WHERE SCHEMA_NAME = CURRENT_SCHEMA AND TABLE_NAME = ?', t)}
    if not have: miss.append('%s（整张表）' % t); continue
    m = [c for c in cs.split(',') if c not in have]
    if m: miss.append('%s.%s' % (t, ','.join(m)))
if miss:
    out('缺少', '以下 B1 自定义表 / 字段不存在，相关对象会编译失败：')
    for m in miss: out('', m)
if '--yes' not in args:
    # 要求完整输入账套名，防止连错账套
    if input('确认部署到 %s？请完整输入账套名继续：' % sch).strip().upper() != sch.upper():
        print('输入与目标账套不一致，已取消'); sys.exit(1)

# 3. 逐条执行
CREATE = re.compile(r'^CREATE\s+(?:(?:COLUMN|ROW|UNIQUE)\s+)?(TABLE|INDEX|SEQUENCE|VIEW|PROCEDURE|FUNCTION)\s+(?:"([^"]+)"|([A-Za-z_][\w$#]*))', re.I)
CODE = re.compile(r'^CREATE\s+(?:OR\s+REPLACE\s+)?(VIEW|PROCEDURE|FUNCTION)\b', re.I)
def strip_comments(s): return re.sub(r'^(\s*--[^\n]*\n)*\s*', '', s)
def exists(n): return q('SELECT COUNT(*) FROM SYS.OBJECTS WHERE SCHEMA_NAME = CURRENT_SCHEMA AND OBJECT_NAME = ?', n)[0][0] > 0

stat = {'成功': 0, '跳过': 0, '失败': 0}
retry = []
for i, (label, sql) in enumerate(stmts, 1):
    m = CREATE.match(strip_comments(sql))
    if m and exists(m.group(2) or m.group(3).upper()):   # 不带引号的名称按大写存储
        stat['跳过'] += 1; log_lines.append('跳过\t%s\t已存在' % label); continue
    try:
        cur.execute(sql); stat['成功'] += 1; log_lines.append('成功\t' + label)
    except Exception as e:
        if CODE.match(strip_comments(sql)): retry.append((label, sql, str(e)))
        else: stat['失败'] += 1; out('失败', label, str(e)[:300])
    if i % 50 == 0: print('  已执行 %d / %d' % (i, len(stmts)))

while retry:
    nxt = []
    for label, sql, _ in retry:
        try: cur.execute(sql); stat['成功'] += 1; log_lines.append('成功（重试）\t' + label)
        except Exception as e: nxt.append((label, sql, str(e)))
    if len(nxt) == len(retry):
        for label, _, e in nxt: stat['失败'] += 1; out('失败', label, e[:300])
        break
    retry = nxt

# 4. 结果
inv = q("""SELECT 'PROCEDURE', PROCEDURE_NAME FROM SYS.PROCEDURES WHERE SCHEMA_NAME = CURRENT_SCHEMA AND IS_VALID <> 'TRUE' AND (PROCEDURE_NAME LIKE 'MTC%')
           UNION ALL SELECT 'FUNCTION', FUNCTION_NAME FROM SYS.FUNCTIONS WHERE SCHEMA_NAME = CURRENT_SCHEMA AND IS_VALID <> 'TRUE' AND FUNCTION_NAME LIKE 'MTC%'
           UNION ALL SELECT 'VIEW', VIEW_NAME FROM SYS.VIEWS WHERE SCHEMA_NAME = CURRENT_SCHEMA AND IS_VALID <> 'TRUE' AND VIEW_NAME LIKE 'MTC%'""")
for k, n in inv: out('无效对象', k, n)
out('完成', '成功 %(成功)d，跳过 %(跳过)d，失败 %(失败)d' % stat + ('，无效对象 %d' % len(inv) if inv else ''))
logf = os.path.join(HERE, '部署日志_%s.txt' % datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
open(logf, 'w', encoding='utf-8').write('\n'.join(log_lines) + '\n')
print('日志：' + logf)
conn.close()
sys.exit(1 if stat['失败'] or inv else 0)
