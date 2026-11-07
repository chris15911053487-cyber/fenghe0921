# 在 HANA 上执行 SQL 文件或单条语句（新框架部署 / 测试用）。
# 连接信息从 JSON 文件读取，默认项目根目录的 mtc_ca_conn.json（用户 2026-10-12 要求放在项目内），也可用环境变量 MTC_CA_CONN 指定。
# 该文件含密码，不要发布、打包或贴进对话。
#   {"address":"…","port":30015,"user":"…","password":"…","databaseName":"NDB","schema":"TEST20261012"}
# 用法：python3 hana_exec.py -f 新框架/sql/01_run_tables.sql [更多文件…]
#       python3 hana_exec.py "SELECT …"
# SQL 文件中语句之间用单独一行 @@ 分隔。查询结果最多打印 200 行；按数据边界约定，只查状态、行数和校验结果。
import sys, json, os
from hdbcli import dbapi

c = json.load(open(os.environ.get('MTC_CA_CONN', os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'mtc_ca_conn.json')), encoding='utf-8'))
kw = {'databaseName': c['databaseName']} if c.get('databaseName') else {}
conn = dbapi.connect(address=c['address'], port=c['port'], user=c['user'], password=c['password'],
                     currentSchema=c['schema'], **kw)

if sys.argv[1] == '-f':
    stmts = []
    for p in sys.argv[2:]:
        stmts += [s.strip() for s in open(p, encoding='utf-8').read().split('\n@@\n') if s.strip()]
else:
    stmts = [sys.argv[1]]

cur, failed = conn.cursor(), 0
for st in stmts:
    head = st.split('\n')[0][:80]
    try:
        cur.execute(st)
        if cur.description:
            print('\t'.join(d[0] for d in cur.description))
            for r in cur.fetchmany(200):
                print('\t'.join('' if v is None else str(v) for v in r))
        else:
            print('OK ', head, '| rows:', cur.rowcount)
    except Exception as e:
        failed += 1
        print('ERR', head, '|', e)
conn.commit()
conn.close()
sys.exit(1 if failed else 0)
