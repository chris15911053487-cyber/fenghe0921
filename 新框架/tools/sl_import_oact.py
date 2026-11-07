# 通过 SAP Business One Service Layer 把科目表（OACT）从源账套导入目标账套（默认 GLOBAL_UAT → TEST20261012）。
# 源科目从 HANA 读取（连接同 hana_exec.py：mtc_ca_conn.json 或环境变量 MTC_CA_CONN），写入一律走 Service Layer POST /ChartOfAccounts。
# Service Layer 连接信息放在项目根目录 sl_conn.json（或环境变量 MTC_SL_CONN），含密码，不要发布、打包或贴进对话：
#   {"url":"https://<host>:50000/b1s/v1","company":"TEST20261012","user":"manager","password":"…","verify":false}
# 用法：python3 新框架/tools/sl_import_oact.py [--source GLOBAL_UAT | --file 科目表.txt] [--dry-run]
# 规则：1 级科目（资产、负债…抽屉）是 B1 建账时固定的，不导入；目标已有的科目跳过；按 Levels、父科目、GrpLine 顺序创建，保证父科目先建、排列顺序与源一致。
# 只打印计数和失败科目的代码 + 错误信息。
import sys, json, os, argparse
from hdbcli import dbapi
import requests, urllib3

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
ap = argparse.ArgumentParser()
ap.add_argument('--source', default='GLOBAL_UAT')
ap.add_argument('--file', help='B1 导出的 OACT 文本（分号分隔、首行为字段名、? 表示空），给了就不读 --source')
ap.add_argument('--dry-run', action='store_true')
args = ap.parse_args()

c = json.load(open(os.environ.get('MTC_CA_CONN', os.path.join(ROOT, 'mtc_ca_conn.json')), encoding='utf-8'))
kw = {'databaseName': c['databaseName']} if c.get('databaseName') else {}
conn = dbapi.connect(address=c['address'], port=c['port'], user=c['user'], password=c['password'],
                     currentSchema=c['schema'], **kw)
cur = conn.cursor()

YN = lambda v: 'tYES' if v == 'Y' else 'tNO'
ACT_TYPE = {'I': 'at_Revenues', 'E': 'at_Expenses', 'N': 'at_Other'}
BASE = ['AcctCode', 'AcctName', 'FrgnName', 'ActCurr', 'Postable', 'FatherNum', 'ActType', 'Finanse',
        'LocManTran', 'Budget', 'Details', 'FrozenFor', 'ValidFor', 'Levels', 'GrpLine']

cur.execute("SELECT COLUMN_NAME FROM SYS.TABLE_COLUMNS WHERE TABLE_NAME='OACT' AND SCHEMA_NAME=CURRENT_SCHEMA AND COLUMN_NAME LIKE 'U\\_%' ESCAPE '\\'")
target_udf = {r[0] for r in cur.fetchall()}
cur.execute('SELECT "AcctCode" FROM OACT')
existing = {r[0] for r in cur.fetchall()}

if args.file:
    # 只取科目定义字段；余额等其他列读进来就丢掉，不打印
    lines = [l.rstrip('\r\n') for l in open(args.file, encoding='utf-8-sig') if l.strip()]
    head = lines[0].split(';')
    udf = [h for h in head if h.startswith('U_') and h in target_udf]
    keep = BASE + udf
    rows = []
    for l in lines[1:]:
        v = l.split(';')
        if len(v) != len(head):
            sys.exit(f'第 {len(rows) + 2} 行字段数 {len(v)} ≠ 表头 {len(head)}（科目名称里有分号？）')
        d = dict(zip(head, v))
        rows.append({k: (None if d.get(k) in ('?', '') else d.get(k)) for k in keep})
    for r in rows:
        r['Levels'], r['GrpLine'] = int(r['Levels']), int(r['GrpLine'] or 0)
    src = args.file
else:
    # 源与目标都有的 U_ 字段一起带过去
    cur.execute("SELECT COLUMN_NAME FROM SYS.TABLE_COLUMNS WHERE TABLE_NAME='OACT' AND SCHEMA_NAME=? AND COLUMN_NAME LIKE 'U\\_%' ESCAPE '\\'", (args.source,))
    udf = [r[0] for r in cur.fetchall() if r[0] in target_udf]
    keep = BASE + udf
    cur.execute('SELECT ' + ','.join(f'"{x}"' for x in keep) + f' FROM "{args.source}".OACT')
    rows = [dict(zip(keep, r)) for r in cur.fetchall()]
    src = args.source
conn.close()

total = len(rows)
rows = [r for r in rows if r['Levels'] > 1 and r['AcctCode'] not in existing]
rows.sort(key=lambda r: (r['Levels'], r['FatherNum'] or '', r['GrpLine'], r['AcctCode']))
# 父科目必须是标题科目且在源里或目标里存在
codes = {r['AcctCode'] for r in rows} | existing
orphan = [r['AcctCode'] for r in rows if r['FatherNum'] not in codes]
if orphan:
    sys.exit(f'{len(orphan)} 个科目的父科目不存在：{", ".join(orphan[:20])}')

def payload(r):
    p = {'Code': r['AcctCode'], 'Name': r['AcctName'], 'FatherAccountKey': r['FatherNum'],
         'ActiveAccount': YN(r['Postable']), 'AcctCurrency': r['ActCurr'] or '##',
         'AccountType': ACT_TYPE.get(r['ActType'], 'at_Other'), 'CashAccount': YN(r['Finanse']),
         'LockManualTransaction': YN(r['LocManTran']), 'BudgetAccount': YN(r['Budget']),
         'FrozenFor': YN(r['FrozenFor']), 'ValidFor': YN(r['ValidFor'])}
    if r['FrgnName']: p['ForeignName'] = r['FrgnName']
    if r['Details']: p['Details'] = r['Details']
    for u in udf:
        if r[u] is not None: p[u] = r[u] if isinstance(r[u], (str, int, float)) else str(r[u])
    return p

print(f'源 {src}：共 {total} 个科目，待导入 {len(rows)} 个（已排除 1 级和目标已有），UDF：{", ".join(udf) or "无"}')
if args.dry_run:
    sys.exit(0)

s = json.load(open(os.environ.get('MTC_SL_CONN', os.path.join(ROOT, 'sl_conn.json')), encoding='utf-8'))
verify = s.get('verify', False)
if not verify:
    urllib3.disable_warnings()
base = s['url'].rstrip('/')
sess = requests.Session()
r = sess.post(base + '/Login', json={'CompanyDB': s['company'], 'UserName': s['user'], 'Password': s['password']}, verify=verify)
if r.status_code != 200:
    sys.exit(f'登录失败：{r.status_code} {r.text[:300]}')

ok, failed = 0, []
for row in rows:
    r = sess.post(base + '/ChartOfAccounts', json=payload(row), verify=verify)
    if r.status_code in (200, 201):
        ok += 1
    else:
        try:
            msg = r.json()['error']['message']['value']
        except Exception:
            msg = r.text[:200]
        failed.append((row['AcctCode'], msg))
        print('ERR', row['AcctCode'], '|', msg)
sess.post(base + '/Logout', verify=verify)
print(f'完成：成功 {ok}，失败 {len(failed)}')
sys.exit(1 if failed else 0)
