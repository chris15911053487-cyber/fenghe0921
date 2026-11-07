# 通过 Service Layer 导入物料（OITM）到 sl_conn.json 指定的账套。
# 输入：新框架/基础数据/导出/05_物料_脱敏.txt（分号分隔，首行字段名；不含物料名称和规格）
# 物料名称按 U_RawOrWrap 分类生成：原料001、包材001、生产成品001…（按物料代码排序编号），规格统一为 '-'，即脱敏。
# 缺少的默认仓库先建（名称 = 仓库<代码>，U_IsCost='Y'）。目标已有的物料跳过。
# 用法：python3 新框架/tools/sl_import_items.py [文件] [--dry-run]
import sys, json, os, requests, urllib3

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
args = [a for a in sys.argv[1:] if not a.startswith('--')]
path = args[0] if args else os.path.join(ROOT, '新框架', '基础数据', '导出', '05_物料_脱敏.txt')
dry = '--dry-run' in sys.argv

lines = [l.rstrip('\r\n') for l in open(path, encoding='utf-8-sig') if l.strip()]
head = lines[0].split(';')
rows = []
for i, l in enumerate(lines[1:], 2):
    v = l.split(';')
    if len(v) != len(head):
        sys.exit(f'第 {i} 行字段数 {len(v)} ≠ 表头 {len(head)}')
    rows.append(dict(zip(head, v)))
rows.sort(key=lambda r: r['ItemCode'])

seq = {}
for r in rows:
    k = r['U_RawOrWrap'] or '物料'
    seq[k] = seq.get(k, 0) + 1
    r['ItemName'] = f'{k}{seq[k]:03d}'

YN = lambda v: 'tYES' if v == 'Y' else 'tNO'

def payload(r):
    p = {'ItemCode': r['ItemCode'], 'ItemName': r['ItemName'], 'ItemsGroupCode': int(r['ItmsGrpCod']),
         'InventoryItem': 'tYES', 'SalesItem': YN(r['SellItem']), 'PurchaseItem': YN(r['PrchseItem']),
         'InventoryUOM': r['Uom'], 'PurchaseUnit': r['Uom'], 'SalesUnit': r['Uom'],
         'CostAccountingMethod': 'bis_Standard', 'GLMethod': 'glm_ItemClass',
         'ManageBatchNumbers': YN(r['ManBtchNum']), 'ManageSerialNumbers': YN(r['ManSerNum']),
         'DefaultWarehouse': r['DfltWH'], 'ProcurementMethod': 'bom_Make' if r['PrcrmntMtd'] == 'M' else 'bom_Buy',
         'Valid': 'tYES', 'Frozen': 'tNO', 'U_Specs': '-',
         'ItemWarehouseInfoCollection': [{'WarehouseCode': r['DfltWH']}]}
    for u in ('U_ItemProp', 'U_FinType', 'U_RawOrWrap', 'U_Ver', 'U_KeyItem'):
        if r[u]:
            p[u] = r[u]
    return p

whs = sorted({r['DfltWH'] for r in rows})
print(f'{path}：{len(rows)} 个物料，分类 {seq}，默认仓库 {whs}')
if dry:
    sys.exit(0)

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
for row in rows:
    if sess.get(f"{base}/Items('{row['ItemCode']}')?$select=ItemCode", verify=verify).status_code == 200:
        skip += 1
        continue
    r = sess.post(base + '/Items', json=payload(row), verify=verify)
    if r.status_code in (200, 201):
        ok += 1
    else:
        failed += 1
        print('ERR', row['ItemCode'], '|', err(r))
sess.post(base + '/Logout', verify=verify)
print(f'完成：成功 {ok}，已存在跳过 {skip}，失败 {failed}')
sys.exit(1 if failed else 0)
