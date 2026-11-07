# 通过 Service Layer 导入 BOM（OITT/ITT1 → ProductTrees）到 sl_conn.json 指定的账套。
# 输入：新框架/基础数据/导出/06_BOM表头.txt（分号分隔、首行字段名、? 为空）
#       新框架/基础数据/导出/07_BOM明细.txt（'#父件' 分组，子件;数量;仓库[;U_BaseQty;U_UnitQty;U_ItemLossRate]）
# 缺少的仓库先建（名称 = 仓库<代码>，U_IsCost='Y'）。没有明细的表头跳过；目标已有的 BOM 跳过。
# 用法：python3 新框架/tools/sl_import_bom.py [--dry-run]
import sys, json, os, requests, urllib3

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
DIR = os.path.join(ROOT, '新框架', '基础数据', '导出')
dry = '--dry-run' in sys.argv

lines = [l.rstrip('\r\n') for l in open(os.path.join(DIR, '06_BOM表头.txt'), encoding='utf-8-sig') if l.strip()]
head = lines[0].split(';')
heads = {}
for l in lines[1:]:
    d = dict(zip(head, l.split(';')))
    heads[d['Code']] = {k: (None if v in ('?', '') else v) for k, v in d.items()}

tree, cur = {}, None
for l in open(os.path.join(DIR, '07_BOM明细.txt'), encoding='utf-8-sig'):
    l = l.strip()
    if not l or l.startswith('# '):
        continue
    if l.startswith('#'):
        cur = l[1:]
        tree[cur] = []
        continue
    v = l.split(';')
    qty = v[2 - 1]
    tree[cur].append({'Code': v[0], 'Quantity': qty, 'Warehouse': v[2],
                      'U_BaseQty': v[3] if len(v) > 3 else '1', 'U_UnitQty': v[4] if len(v) > 4 else qty,
                      'U_ItemLossRate': (v[5] if len(v) > 5 else '0')})

missing_head = sorted(set(tree) - set(heads))
if missing_head:
    sys.exit(f'明细里有表头不存在的父件：{missing_head}')
no_lines = sorted(set(heads) - set(tree))
whs = sorted({h['ToWH'] for h in heads.values()} | {c['Warehouse'] for t in tree.values() for c in t})
print(f'表头 {len(heads)}，有明细 {len(tree)}，明细 {sum(map(len, tree.values()))} 行，仓库 {whs}')
print('无明细跳过：', no_lines)
for f, t in tree.items():
    print(f'  {f}: {len(t)}', end='')
print()
if dry:
    sys.exit(0)

def num(x):
    return float(x)

def payload(code):
    h = heads[code]
    p = {'TreeCode': code, 'TreeType': 'iProductionTree', 'Quantity': num(h['Qauntity']), 'Warehouse': h['ToWH'],
         'ProductTreeLines': []}
    for k in ('U_VerNo', 'U_Status'):
        if h.get(k):
            p[k] = h[k]
    if h.get('U_ProdLossRate'):
        p['U_ProdLossRate'] = num(h['U_ProdLossRate'])
    for c in tree[code]:
        ln = {'ItemCode': c['Code'], 'ItemType': 'pit_Item', 'Quantity': num(c['Quantity']), 'Warehouse': c['Warehouse'],
              'IssueMethod': 'im_Manual', 'U_BaseQty': num(c['U_BaseQty']), 'U_UnitQty': num(c['U_UnitQty']), 'U_IsComSub': 'N'}
        if c['U_ItemLossRate'] not in ('?', ''):
            ln['U_ItemLossRate'] = num(c['U_ItemLossRate'])
        p['ProductTreeLines'].append(ln)
    return p

s = json.load(open(os.environ.get('MTC_SL_CONN', os.path.join(ROOT, 'sl_conn.json')), encoding='utf-8'))
verify = s.get('verify', False)
if not verify:
    urllib3.disable_warnings()
base = s['url'].rstrip('/')
sess = requests.Session()
r = sess.post(base + '/Login', json={'CompanyDB': s['company'], 'UserName': s['user'], 'Password': s['password']}, verify=verify)
if r.status_code != 200:
    sys.exit(f'登录失败：{r.status_code}')

def err(r):
    try:
        return r.json()['error']['message']['value']
    except Exception:
        return r.text[:200]

for w in whs:
    if sess.get(f"{base}/Warehouses('{w}')", verify=verify).status_code == 200:
        continue
    r = sess.post(base + '/Warehouses', json={'WarehouseCode': w, 'WarehouseName': f'仓库{w}', 'U_IsCost': 'Y'}, verify=verify)
    print('仓库', w, 'OK' if r.status_code in (200, 201) else 'ERR ' + err(r))

ok, skip, failed = 0, 0, 0
for code in sorted(tree):
    if sess.get(f"{base}/ProductTrees('{code}')?$select=TreeCode", verify=verify).status_code == 200:
        skip += 1
        continue
    r = sess.post(base + '/ProductTrees', json=payload(code), verify=verify)
    if r.status_code in (200, 201):
        ok += 1
    else:
        failed += 1
        print('ERR', code, '|', err(r))
sess.post(base + '/Logout', verify=verify)
print(f'完成：成功 {ok}，已存在跳过 {skip}，失败 {failed}')
sys.exit(1 if failed else 0)
