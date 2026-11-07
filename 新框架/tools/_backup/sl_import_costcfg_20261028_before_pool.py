# 通过 SAP Business One Service Layer 写入费用池 / 费用归集参数的初始数据（B1 UDO MTC_CA_POOL、MTC_CA_EXPSET，结构见 新框架/B1自定义表_费用配置.md）。
# 数据与新框架种子值一致（旧 0312 / 0311 口径，04_seed.sql、05_config_pool.sql），写入后 P05 同步出来的 C_POOL* / C_ACCT / C_PARAM 与现在相同。
# Service Layer 连接信息：项目根目录 sl_conn.json（或环境变量 MTC_SL_CONN），含密码，不要发布、打包或贴进对话。
# 另外把 MTC_CA_C_PARAM 中其余参数（除 CLOSE_DIF_POOL，它在费用池 U_IsCloseDif 维护）按库中当前值写入 @MTC_CA_EXPSET（用户 2026-10-14），
# 各起止账期行都带上；列表型参数（,A,B,）写成 A,B，空代码写成“空”。读参数要连 HANA（mtc_ca_conn.json，同 hana_exec.py）。
# 用法：python3 新框架/tools/sl_import_costcfg.py [--dry-run] [--no-params]
# 目标库已有的代码跳过，不覆盖（要改请在 B1 里改）。
# --param（用户 2026-10-28）：只写计算参数平铺表 @MTC_CA_PARAM（UDO MTC_CA_PARAM，一行 = 一个参数的一段账期），
#   参数清单取参数目录 MTC_CA_C_PARAM_DEF（中文名、分类、类型、填法一起写入）；取值：旧 B1 @MTC_CA_EXPSET1 里有的取 B1 的，
#   没有的取 MTC_CA_C_PARAM / C_ACCT 当前值。第一段 Code = 参数代码，第二段起 Code = 参数代码@起始账期。
#   --update-meta：已有的行只刷新 Name / U_Category / U_DataType / U_Hint，不动取值和账期。
import sys, json, os, argparse
import requests, urllib3

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
ap = argparse.ArgumentParser()
ap.add_argument('--dry-run', action='store_true')
ap.add_argument('--no-params', action='store_true', help='只写费用池和三个归集参数，不写 MTC_CA_C_PARAM 的其余参数')
ap.add_argument('--param', action='store_true', help='只写计算参数平铺表 @MTC_CA_PARAM（2026-10-28）')
ap.add_argument('--update-meta', action='store_true', help='与 --param 一起用：已有的行刷新中文名、分类、类型、填法')
args = ap.parse_args()

POOL = [
    {'Code': 'MFG', 'Name': '制造车间', 'U_IsDefault': 'Y', 'U_IsCloseDif': 'Y',
     'U_Descr': '旧 0312：成本中心不是 P017 的费用；关单差异也进这个池（Q10）',
     'MTC_CA_POOL1Collection': [],
     'MTC_CA_POOL2Collection': [
         {'U_MatchBy': 'GRPTYPE', 'U_MatchVal': 'B', 'U_WorTypes': '10,20,30,40', 'U_Descr': '车间类别 B（旧 0312 物料组 102）'},
         {'U_MatchBy': 'GRPTYPE', 'U_MatchVal': 'C', 'U_WorTypes': '10,20,30,40', 'U_Descr': '车间类别 C（旧 0312 物料组 103）'}]},
    {'Code': 'PKG', 'Name': '包装车间', 'U_IsDefault': 'N', 'U_IsCloseDif': 'N',
     'U_Descr': '旧 0312：成本中心 P017 的费用',
     'MTC_CA_POOL1Collection': [
         {'U_OcrCode': 'P017', 'U_Descr': 'OPRC.U_CalType = P017 的成本中心都进包装车间（也可以直接填成本中心代码）'}],
     'MTC_CA_POOL2Collection': [
         {'U_MatchBy': 'GRPTYPE', 'U_MatchVal': 'A', 'U_WorTypes': '10,20,30,40', 'U_Descr': '车间类别 A 包装（旧 0312 物料组 101）'}]},
]
EXPSET = [
    {'Code': 'MFG_EXP_PREFIX', 'Name': '制造费用科目前缀（凭证里以它开头的科目计入制造费用）',
     'MTC_CA_EXPSET1Collection': [{'U_Value': '5101'}]},
    {'Code': 'LAB_EXP', 'Name': '人工费用科目',
     'MTC_CA_EXPSET1Collection': [{'U_Value': '500102'}]},
    {'Code': 'EXP_JDT_TRANSCODES', 'Name': '计入费用池的凭证代码（逗号分隔，“空”= 没有凭证代码的手工凭证）',
     'MTC_CA_EXPSET1Collection': [{'U_Value': '空,PP03,MR03,MR11,MR12'}]},
]

def hana():
    from hdbcli import dbapi
    c = json.load(open(os.environ.get('MTC_CA_CONN', os.path.join(ROOT, 'mtc_ca_conn.json')), encoding='utf-8'))
    kw = {'databaseName': c['databaseName']} if c.get('databaseName') else {}
    return dbapi.connect(address=c['address'], port=c['port'], user=c['user'], password=c['password'], currentSchema=c['schema'], **kw)

def b1_list(v):
    # 库里的列表 ,A,B,（空代码是两个逗号之间为空）→ B1 填法 A,B（空代码写“空”）；空列表“,”→ 空串
    v = v or ''
    if v.strip(',') == '': return ''
    return ','.join('空' if x == '' else x for x in v[1:-1].split(','))

FIXED = {r['Code'] for r in EXPSET}
PARAM = []
TYPE_CN = {'DEC': '数字', 'INT': '整数', 'STR': '文字', 'LIST': '列表', 'FC': '账期', 'DATE': '日期'}
if args.param:
    conn = hana(); cur = conn.cursor()
    cur.execute('SELECT "ParamCode", "Target", "Category", "CnName", "DataType", "Choices", "Hint" FROM "MTC_CA_C_PARAM_DEF" ORDER BY "SortNo", "ParamCode"')
    defs = cur.fetchall()
    segs = {}   # 参数代码 → [(FromFc, ToFc, B1 填法的取值)]
    cur.execute('SELECT COUNT(*) FROM "TABLES" WHERE "SCHEMA_NAME" = CURRENT_SCHEMA AND "TABLE_NAME" = \'@MTC_CA_EXPSET1\'')
    if cur.fetchone()[0]:
        cur.execute('SELECT TRIM("Code"), IFNULL(NULLIF(TRIM("U_FromFc"), \'\'), \'0000-00\'), IFNULL(NULLIF(TRIM("U_ToFc"), \'\'), \'9999-99\'), IFNULL(TRIM("U_Value"), \'\') FROM "@MTC_CA_EXPSET1"')
        for code, f, t, v in cur.fetchall():
            segs.setdefault(code, []).append((f, t, v))
        print(f'旧 @MTC_CA_EXPSET 里有 {len(segs)} 个参数，取 B1 的值')
    cur.execute('SELECT "ParamCode", "FromFc", "ToFc", "Value", "DataType" FROM "MTC_CA_C_PARAM" WHERE LEFT("FromFc", 1) <> \'#\' '
                'UNION ALL SELECT "Usage", "FromFc", "ToFc", "AcctCode", \'STR\' FROM "MTC_CA_C_ACCT" WHERE "Usage" IN (\'MFG_EXP_PREFIX\', \'LAB_EXP\')')
    cur_vals = {}
    for code, f, t, v, dt in cur.fetchall():
        cur_vals.setdefault(code, []).append((f, t, b1_list(v) if dt == 'LIST' or (v or '').startswith(',') else (v or '')))
    conn.close()
    for code, tgt, cat, name, dt, ch, hint in defs:
        rows = sorted(segs.get(code) or cur_vals.get(code) or [('0000-00', '9999-99', '')])
        for i, (f, t, v) in enumerate(rows):
            row = {'Code': code if i == 0 else f'{code}@{f}', 'Name': name, 'U_Category': cat,
                   'U_DataType': TYPE_CN.get(dt, dt), 'U_Hint': (hint or '')[:254], 'U_Value': v}
            if f != '0000-00': row['U_FromFc'] = f
            if t != '9999-99': row['U_ToFc'] = t
            PARAM.append(row)
    print(f'参数目录 {len(defs)} 个参数，共 {len(PARAM)} 行')
elif not args.no_params:
    conn = hana(); cur = conn.cursor()
    cur.execute('SELECT "ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr" FROM "MTC_CA_C_PARAM" ORDER BY "ParamCode", "FromFc"')
    rows = cur.fetchall(); conn.close()
    params = {}
    for code, f, t, v, dt, d in rows:
        if code in FIXED or code == 'CLOSE_DIF_POOL' or f.startswith('#'):
            continue
        v = v or ''
        if dt == 'LIST' or v.startswith(','):
            v = b1_list(v)
        d = (d or code).replace('B1 @MTC_CA_EXPSET：', '')
        e = params.setdefault(code, {'Code': code, 'Name': d[:100], 'MTC_CA_EXPSET1Collection': []})
        line = {'U_Value': v}
        if f != '0000-00': line['U_FromFc'] = f
        if t != '9999-99': line['U_ToFc'] = t
        e['MTC_CA_EXPSET1Collection'].append(line)
    EXPSET += list(params.values())
    print(f'从 MTC_CA_C_PARAM 读到 {len(params)} 个参数')

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

def exists(udo, code):
    # 只有 404 才算不存在；其他状态或连接错误重试 3 次，仍失败就停止，避免把已有的代码重复提交
    import time
    for i in range(3):
        try:
            g = sess.get(f"{base}/{udo}('{code}')", verify=verify)
            if g.status_code == 200: return True
            if g.status_code == 404: return False
            last = f'{g.status_code} {err(g)}'
        except requests.RequestException as e:
            last = str(e)[:200]
        time.sleep(2)
    sys.exit(f'查询 {udo} {code} 是否存在失败：{last}')

ok, skip, failed = 0, 0, 0
META = ('Name', 'U_Category', 'U_DataType', 'U_Hint')
for udo, rows in ((('MTC_CA_PARAM', PARAM),) if args.param else (('MTC_CA_POOL', POOL), ('MTC_CA_EXPSET', EXPSET))):
    for row in rows:
        if exists(udo, row['Code']):
            if args.param and args.update_meta:
                if args.dry_run:
                    print(f'待刷新说明 {udo} {row["Code"]}'); continue
                p = sess.patch(f"{base}/{udo}('{row['Code']}')", json={k: row[k] for k in META}, verify=verify)
                if p.status_code in (200, 204):
                    print(f'刷新说明 {udo} {row["Code"]}'); ok += 1
                else:
                    print(f'失败 {udo} {row["Code"]}：{p.status_code} {err(p)}'); failed += 1
                continue
            print(f'跳过 {udo} {row["Code"]}：已存在'); skip += 1; continue
        if args.dry_run:
            print(f'待写入 {udo} {row["Code"]}'); continue
        p = sess.post(f'{base}/{udo}', json=row, verify=verify)
        if p.status_code in (200, 201):
            print(f'写入 {udo} {row["Code"]}'); ok += 1
        else:
            print(f'失败 {udo} {row["Code"]}：{p.status_code} {err(p)}'); failed += 1
sess.post(base + '/Logout', verify=verify)
print(f'完成：写入 {ok}，跳过 {skip}，失败 {failed}')
sys.exit(1 if failed else 0)
