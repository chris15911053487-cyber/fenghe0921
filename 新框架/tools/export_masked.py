# 把成本核算的中间表 / 结果表脱敏后导出成 CSV，用于把排查数据交给 AI（用户 2026-10-13 同意：脱敏后可以给）。
# 在能连到目标库的机器上运行，屏幕上只打印表名和行数，不打印数据。
#
# 脱敏规则（按列名和类型判断，所有表同一套规则）：
#   1. 名称、备注、用户等文本列清空：ItemName、CardName、Comments、Memo、Remark、Creator、UserCode、Project 等。
#   2. 业务伙伴代码换成代号：CardCode/VendorCode → BP0001…；物料代码默认保留（用户 2026-10-13：物料编码不用脱敏），加 --mask-items 才换成 I000001…；
#      Msg、Info、PriceMemo、KeyCode 等其余文本列里出现的这些代码也一起替换。同一个代码在所有表、所有次导出里代号相同。
#   3. 金额默认保留（用户 2026-10-13：金额不用脱敏）。加 --scale 时，金额、单价列（DECIMAL/DOUBLE 且列名不是数量、工时、比例、权重类）
#      统一乘以系数 K（0.3–3 之间的随机数）。同一个 K 作用于所有表，所以加总、勾稽、借贷平衡关系不变，但看不出真实金额。不做舍入，原来 0.01 的尾差会变成 0.01×K。
#   4. 账期、日期、单据 DocEntry/DocNum、仓库、科目、交易类型、订单类型、层级、数量都保留。
# K、代号种子和对照表放在 脱敏密钥/（项目根目录下），只留在本机，不要发出去；用它可以把 AI 给出的代号还原成真实代码。
#
# 新框架的表按运行号取（2026-10-29）：默认 = 本账期最近一次运行（不管成功、未收敛还是失败）+ 每种运行类型 / 场景最近一次成功的运行；
#   --run 12,15 指定运行号，--all-runs 导出本账期全部运行（RUN_KPI 每次运行都保留，全部导出会很大）。
#   MTC_CA_RUN 列出本账期全部运行；有 RunId 列的表只取选中的运行；只有 FcCode 的表按账期取。
#   未收敛的运行要库上已执行 patch_20261029_noconv.sql 才保留快照和中间结果，否则只有迭代日志，脚本会提示。
#
# 用法：python3 新框架/tools/export_masked.py 2026-09 [--set new|old|all] [--run 运行号,…|--all-runs] [--tables 表1,表2] [--mask-items] [--scale] [--conn 连接文件]
#   连接文件格式同 mtc_ca_conn.json；加 "driver":"odbc" 时用 pyodbc + HANA ODBC（Windows），否则用 hdbcli。
#   输出：排查数据/<账期>_<时间>/*.csv + 说明.txt。把这个文件夹拷进项目，告诉 AI 路径即可。
import sys, os, json, re, csv, random, datetime, argparse
from decimal import Decimal

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))

OLD_TABLES = ['MTC_COST_0201_DOCDETAL', 'MTC_COST_0301_INVNT', 'MTC_COST_0302_INVNTDETAIL1', 'MTC_COST_0303_INVNTLIST',
              'MTC_COST_0321_OWOR', 'MTC_COST_0321_OWOR1', 'MTC_COST_0321_OWOR2', 'MTC_COST_0321_OWOR_SUM',
              'MTC_COST_0322_OWOR_ZCP', 'MTC_COST_0322_OWOR_ZCP1', 'MTC_COST_0801_TOOJDT', 'MTC_COST_0802_OJDTBASEDETAIL',
              'U_COILV']

DROP_COL = re.compile(r'(ItemName|CardName|StockName|Comments|Remark|^Memo$|LineMemo|^U_Memo$|Creator|^User$|UserCode|'
                      r'CreateUser|PlanUser|PlanNote|Project|Address|Phone|Mail|ModelOutput)', re.I)
ITEM_COL = re.compile(r'(ItemCode|ProdItem|^Father$|StockCode)$', re.I)
BP_COL = re.compile(r'(CardCode|VendorCode)$', re.I)
# 纯代码列：不做文本替换（避免把与物料代码同形的科目、仓库等误替换）
CODE_COL = re.compile(r'(FcCode|TransCode|WhsCode|Acct|OcrCode|CostCode|BusiType|Type|Status|StepCode|CheckId|'
                      r'^Code$|Cod$|Stat$|^Is|Canceled|Dir|Stage|Result|Scenario|Layer|Elem|Kind|Cat|Unit)', re.I)
NOSCALE_COL = re.compile(r'(Qty|Quantity|数量|Hours|Ratio|Weight|Level|Cnt|Count|Iter|Items|SortNo|Rate|Pct|Percent)', re.I)
NUM_TYPES = {'DECIMAL', 'DOUBLE', 'REAL', 'SMALLDECIMAL', 'FLOAT'}
TOKEN = re.compile(r'[A-Za-z0-9_]+(?:[-./][A-Za-z0-9_]+)*')   # 代码可含 - . /，前后的中文和标点不算


def connect(c):
    if c.get('driver') == 'odbc':
        import pyodbc
        cs = c.get('odbc') or (f"DRIVER={{HDBODBC}};SERVERNODE={c['address']}:{c['port']};UID={c['user']};PWD={c['password']};"
                               + (f"DATABASENAME={c['databaseName']};" if c.get('databaseName') else ''))
        conn = pyodbc.connect(cs, autocommit=False)
        conn.cursor().execute(f'SET SCHEMA "{c["schema"]}"')
        return conn
    from hdbcli import dbapi
    kw = {'databaseName': c['databaseName']} if c.get('databaseName') else {}
    return dbapi.connect(address=c['address'], port=c['port'], user=c['user'], password=c['password'],
                         currentSchema=c['schema'], **kw)


def load_key(keydir):
    os.makedirs(keydir, exist_ok=True)
    p = os.path.join(keydir, '脱敏密钥.json')
    if os.path.exists(p):
        return json.load(open(p, encoding='utf-8')), p
    k = {'K': f'{random.uniform(0.3, 3):.6f}', 'seed': random.randrange(1 << 30),
         'created': datetime.datetime.now().isoformat(timespec='seconds')}
    json.dump(k, open(p, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    return k, p


def build_map(cur, sql, prefix, width, seed, old):
    """代码 → 代号。已有对照表里的代号保持不变，新代码按随机顺序续号。"""
    cur.execute(sql)
    codes = sorted({r[0] for r in cur.fetchall() if r[0]})
    m = {c: v for c, v in old.items() if v.startswith(prefix)}
    new = [c for c in codes if c not in m]
    random.Random(seed).shuffle(new)
    n = len(m)
    for c in new:
        n += 1
        m[c] = f'{prefix}{n:0{width}d}'
    return m


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('fc')
    ap.add_argument('--set', default='all', choices=['new', 'old', 'all'])
    ap.add_argument('--tables', default='')
    ap.add_argument('--run', default='', help='运行号，逗号分隔；默认最近一次运行 + 各类最近一次成功')
    ap.add_argument('--all-runs', action='store_true')
    ap.add_argument('--mask-items', action='store_true')
    ap.add_argument('--scale', action='store_true')
    ap.add_argument('--conn', default=os.environ.get('MTC_CA_CONN', os.path.join(ROOT, 'mtc_ca_conn.json')))
    a = ap.parse_args()

    c = json.load(open(a.conn, encoding='utf-8'))
    conn = connect(c)
    cur = conn.cursor()
    schema = c['schema']

    keydir = os.path.join(ROOT, '脱敏密钥')
    key, keypath = load_key(keydir)
    K = Decimal(key['K']) if a.scale else Decimal('1')
    mapfile = os.path.join(keydir, '代码对照.csv')
    old = {}
    if os.path.exists(mapfile):
        old = {r[0]: r[1] for r in csv.reader(open(mapfile, encoding='utf-8-sig')) if len(r) == 2}
    imap = build_map(cur, 'SELECT "ItemCode" FROM "OITM"', 'I', 6, key['seed'], old) if a.mask_items else {}
    bmap = build_map(cur, 'SELECT "CardCode" FROM "OCRD"', 'BP', 4, key['seed'] + 1, old)
    allmap = {**bmap, **imap}
    with open(mapfile, 'w', encoding='utf-8-sig', newline='') as f:
        csv.writer(f).writerows(sorted(allmap.items(), key=lambda x: x[1]))

    def sub_text(s):
        return TOKEN.sub(lambda m: allmap.get(m.group(0), m.group(0)), s)

    # 要导出的表
    if a.tables:
        tables = [t.strip() for t in a.tables.split(',') if t.strip()]
    else:
        tables = []
        if a.set in ('new', 'all'):
            cur.execute('SELECT "TABLE_NAME" FROM "SYS"."TABLES" WHERE "SCHEMA_NAME"=? AND "TABLE_NAME" LIKE ? ESCAPE \'\\\' ORDER BY 1',
                        (schema, 'MTC\\_CA\\_%'))
            tables += [r[0] for r in cur.fetchall() if not re.search(r'_(BACKUP|TEST|\d{6,})', r[0], re.I)]
        if a.set in ('old', 'all'):
            tables += OLD_TABLES

    # 选运行
    runs, run_ids, run_cols = [], [], []
    if any(t.startswith('MTC_CA_') for t in tables):
        cur.execute('SELECT * FROM "MTC_CA_RUN" WHERE "FcCode"=? ORDER BY "RunId"', (a.fc,))
        run_cols = [d[0] for d in cur.description]
        runs = [dict(zip(run_cols, r)) for r in cur.fetchall()]
        if a.run:
            run_ids = [int(x) for x in a.run.split(',') if x.strip()]
        elif a.all_runs:
            run_ids = [r['RunId'] for r in runs]
        elif runs:
            pick = {runs[-1]['RunId']}
            last_ok = {}
            for r in runs:
                if r['Status'] == 'OK':
                    last_ok[(r['RunType'], r.get('Scenario') or '')] = r['RunId']
            run_ids = sorted(pick | set(last_ok.values()))
        print('选中的运行：' + (', '.join(f"#{r['RunId']} {r['RunType']} {r['Status']}"
                                          + (f" 迭代 {r.get('IterCount')} 轮" if r.get('IterCount') else '')
                                          for r in runs if r['RunId'] in run_ids) or '（本账期没有运行）'))
    run_in = ','.join(str(int(i)) for i in run_ids) or 'NULL'

    outdir = os.path.join(ROOT, '排查数据', f'{a.fc}_{datetime.datetime.now():%Y%m%d_%H%M}')
    os.makedirs(outdir, exist_ok=True)
    summary = []
    for t in tables:
        cur.execute('SELECT "COLUMN_NAME","DATA_TYPE_NAME" FROM "SYS"."TABLE_COLUMNS" WHERE "SCHEMA_NAME"=? AND "TABLE_NAME"=? '
                    'ORDER BY "POSITION"', (schema, t))
        cols = cur.fetchall()
        if not cols:
            print(f'跳过 {t}：不存在')
            summary.append((t, '不存在'))
            continue
        names = [r[0] for r in cols]
        if t.startswith('MTC_CA_') and t != 'MTC_CA_RUN' and 'RunId' in names:
            where, args = f' WHERE "RunId" IN ({run_in})', ()
        elif 'FcCode' in names:
            where, args = ' WHERE "FcCode"=?', (a.fc,)
        elif '期间' in names:   # 0322_OWOR_ZCP 的账期列
            where, args = ' WHERE "期间"=?', (a.fc,)
        else:
            where, args = '', ()
        rules = []
        for n, typ in cols:
            if DROP_COL.search(n) and not ITEM_COL.search(n) and not BP_COL.search(n):
                rules.append('drop')
            elif BP_COL.search(n) or (a.mask_items and ITEM_COL.search(n)):
                rules.append('map')
            elif ITEM_COL.search(n):
                rules.append('keep')
            elif typ in NUM_TYPES:
                rules.append('scale' if a.scale and not NOSCALE_COL.search(n) else 'keep')
            elif typ in ('NVARCHAR', 'VARCHAR', 'NCLOB', 'CLOB', 'ALPHANUM', 'SHORTTEXT'):
                rules.append('keep' if CODE_COL.search(n) else 'text')
            else:
                rules.append('keep')
        try:
            cur.execute(f'SELECT * FROM "{t}"' + where, args)
        except Exception as e:
            print(f'跳过 {t}：{e}')
            summary.append((t, f'查询失败 {e}'))
            continue
        cnt = 0
        with open(os.path.join(outdir, f'{t}.csv'), 'w', encoding='utf-8-sig', newline='') as f:
            w = csv.writer(f)
            w.writerow(names)
            while True:
                rows = cur.fetchmany(5000)
                if not rows:
                    break
                for r in rows:
                    out = []
                    for v, rule in zip(r, rules):
                        if v is None:
                            out.append('')
                            continue
                        if hasattr(v, 'read'):
                            v = v.read()
                        if rule == 'drop':
                            out.append('*')
                        elif rule == 'map':
                            out.append(allmap.get(v, sub_text(str(v))))
                        elif rule == 'scale':
                            out.append(str((Decimal(str(v)) * K).quantize(Decimal('0.000001')).normalize()))
                        elif rule == 'text':
                            out.append(sub_text(str(v)))
                        else:
                            out.append(str(v))
                    w.writerow(out)
                    cnt += 1
        print(f'{t}\t{cnt}')
        summary.append((t, cnt, {n: r for n, r in zip(names, rules) if r != 'keep'}))
    # 未收敛 / 失败的运行有没有留下中间结果（失败 2026-10-30）
    warns = []
    noconv = [(r['RunId'], r['Status']) for r in runs if r['RunId'] in run_ids and r['Status'] in ('NOCONV', 'FAIL')]
    if noconv and 'MTC_CA_R_ITEM' in tables:
        for i, st in noconv:
            cur.execute('SELECT COUNT(*) FROM "MTC_CA_R_ITEM" WHERE "RunId"=?', (i,))
            if cur.fetchone()[0] != 0:
                continue
            if st == 'FAIL':
                warns.append(f'运行 #{i} 失败，快照和中间结果已被删除（出错在迭代 P40 之前的不保留；在迭代中或之后出错的，'
                             f'要库上已执行 patch_20261030_failkeep.sql 且 KEEP_NOCONV = Y），只导出了运行和步骤日志。')
            else:
                warns.append(f'运行 #{i} 未收敛，但快照和中间结果已被删除（库上还没执行 patch_20261029_noconv.sql，或参数 KEEP_NOCONV = N），'
                             f'只导出了迭代日志。部署补丁后重新计算一次再导出。')
    for w_ in warns:
        print('⚠ ' + w_)
    # 财务对账的总账 / 未清凭单分录（2026-10-17）：表里没有，从只读函数取。本账期每种运行类型最近一次成功的运行；
    # F_RECON_LEDGER = 对账科目按来源 × 凭证代码汇总，F_TB_LINE = 成本相关科目逐笔分录（Memo 清空、VendorCode 换代号）
    if 'MTC_CA_RUN' in tables:
        ids = [r['RunId'] for r in runs if r['RunId'] in run_ids and r['Status'] == 'OK']   # 只对成功的运行（未收敛的没有定稿和凭证）
        for name, fn in (('F_RECON_LEDGER', '"MTC_CA_F_RECON_LEDGER"({})'), ('F_TB_LINE', '"MTC_CA_F_TB_LINE"({}, \'\')')):
            if not ids:
                break
            sql = ' UNION ALL '.join(f'SELECT {i} AS "RunId", L.* FROM {fn.format(i)} L' for i in ids)
            try:
                cur.execute(sql)
            except Exception as e:
                print(f'跳过 {name}：{e}')
                summary.append((name, f'查询失败 {e}'))
                continue
            names = [d[0] for d in cur.description]
            rules = []
            for n in names:
                if DROP_COL.search(n) and not ITEM_COL.search(n) and not BP_COL.search(n):
                    rules.append('drop')
                elif BP_COL.search(n) or (a.mask_items and ITEM_COL.search(n)):
                    rules.append('map')
                elif ITEM_COL.search(n) or CODE_COL.search(n):
                    rules.append('keep')
                else:
                    rules.append('auto')   # 按值的类型：文本做代码替换，金额按 --scale
            cnt = 0
            with open(os.path.join(outdir, f'{name}.csv'), 'w', encoding='utf-8-sig', newline='') as f:
                w = csv.writer(f)
                w.writerow(names)
                for r in cur.fetchall():
                    out = []
                    for n, v, rule in zip(names, r, rules):
                        if v is None:
                            out.append('')
                        elif rule == 'drop':
                            out.append('*')
                        elif rule == 'map':
                            out.append(allmap.get(v, sub_text(str(v))))
                        elif rule == 'auto' and isinstance(v, str):
                            out.append(sub_text(v))
                        elif rule == 'auto' and isinstance(v, (Decimal, float)) and a.scale and not NOSCALE_COL.search(n):
                            out.append(str((Decimal(str(v)) * K).quantize(Decimal('0.000001')).normalize()))
                        else:
                            out.append(str(v))
                    w.writerow(out)
                    cnt += 1
            print(f'{name}\t{cnt}')
            summary.append((name, cnt, {n: r for n, r in zip(names, rules) if r != 'keep'}))
    conn.rollback()
    conn.close()

    with open(os.path.join(outdir, '说明.txt'), 'w', encoding='utf-8') as f:
        f.write(f'账期 {a.fc}，导出时间 {datetime.datetime.now():%Y-%m-%d %H:%M}，金额{"已乘以系数 K（不在此文件中）" if a.scale else "原值"}，物料代码{"已换成代号" if a.mask_items else "原值"}。\n')
        f.write('列处理：drop=清空为 *，map=代码换成代号，scale=金额乘以 K，text=文本中的代码换成代号；未列出的列原样保留。\n')
        if runs:
            f.write('新框架的表只含这些运行（MTC_CA_RUN 列出本账期全部运行）：\n')
            for r in runs:
                if r['RunId'] in run_ids:
                    f.write(f"  #{r['RunId']} {r['RunType']} {r.get('Scenario') or ''} {r['Status']} 迭代 {r.get('IterCount')} 轮 收敛 {r.get('Converged')}\n")
        for w_ in warns:
            f.write('⚠ ' + w_ + '\n')
        f.write('\n')
        for s in summary:
            f.write(f'{s[0]}\t{s[1]}\n')
            if len(s) > 2 and s[2]:
                f.write('\t' + ', '.join(f'{k}:{v}' for k, v in s[2].items()) + '\n')
    print(f'\n已导出到 {outdir}')
    print(f'密钥和代码对照在 {keydir}（只留在本机，不要发出去）')


if __name__ == '__main__':
    main()
