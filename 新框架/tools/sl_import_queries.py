# 经 SAP Business One Service Layer 把 24 张成本报表登记成 B1 查询（用户 2026-10-30）：
#   建查询分类“成本报表（新）”（QueryCategories），每张报表一条用户查询（UserQueries，语句同 新框架/reports/B1查询语句.md）。
#   已有同名查询的跳过，不覆盖（--update 时改成新语句）。也可以不用本脚本，在查询管理器里手工粘贴。
# Service Layer 连接信息：项目根目录 sl_conn.json（或环境变量 MTC_SL_CONN），含密码，不要发布、打包或贴进对话。
# 用法：python3 新框架/tools/sl_import_queries.py [--dry-run] [--update] [--category 分类名]
import sys, json, os, argparse
import requests, urllib3

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
ap = argparse.ArgumentParser()
ap.add_argument('--dry-run', action='store_true')
ap.add_argument('--update', action='store_true', help='已有同名查询时改成新语句')
ap.add_argument('--category', default='成本报表（新）')
args = ap.parse_args()

from gen_rpt import defs, b1_sql   # 同一份定义、同一条语句（导入时会顺带重新生成 md / js / actions.json）

rows = [('R%s %s' % (r['id'], r['name']), b1_sql(r)) for r in defs]
if args.dry_run:
    for n, q in rows: print('--', n, '\n' + q + '\n')
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
print(f'已登录 {s["company"]}')

def err(r):
    try: return r.json()['error']['message']['value']
    except Exception: return r.text[:300]

def q(s): return s.replace("'", "''")

try:
    g = sess.get(f"{base}/QueryCategories?$filter=Name eq '{q(args.category)}'", verify=verify)
    cats = g.json().get('value', []) if g.status_code == 200 else []
    if cats:
        cat = cats[0]['Code']; print(f'分类已有：{args.category}（{cat}）')
    else:
        p = sess.post(f'{base}/QueryCategories', json={'Name': args.category}, verify=verify)
        if p.status_code not in (200, 201): sys.exit(f'建分类失败：{err(p)}')
        cat = p.json()['Code']; print(f'已建分类：{args.category}（{cat}）')
    ok = skip = fail = 0
    for name, sql in rows:
        g = sess.get(f"{base}/UserQueries?$filter=QueryCategory eq {cat} and QueryDescription eq '{q(name)}'", verify=verify)
        have = g.json().get('value', []) if g.status_code == 200 else []
        if have and not args.update:
            skip += 1; print(f'  跳过（已有）{name}'); continue
        if have:
            k = have[0]
            p = sess.patch(f"{base}/UserQueries(QueryCategory={cat},InternalKey={k['InternalKey']})", json={'Query': sql}, verify=verify)
        else:
            p = sess.post(f'{base}/UserQueries', json={'QueryCategory': cat, 'QueryDescription': name, 'Query': sql}, verify=verify)
        if p.status_code in (200, 201, 204):
            ok += 1; print(f'  {"已更新" if have else "已登记"} {name}')
        else:
            fail += 1; print(f'  ✗ {name}：{err(p)}')
    print(f'完成：登记 / 更新 {ok}，跳过 {skip}，失败 {fail}')
finally:
    sess.post(base + '/Logout', verify=verify)
