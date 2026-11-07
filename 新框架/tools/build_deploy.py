# 生成一次性部署包：部署包/全部部署.sql（旧成本模块 + 配置数据 + 新框架 01–16），供 部署包/ 里的执行程序使用。
# 用法：python3 新框架/tools/build_deploy.py
# 来源：旧模块取 0921-数据库同步/（跳过备份/测试对象和坏对象），新框架取 新框架/sql/01–19（10 放在最后），再加 20_b1cfg_check.sql、21_reports.sql、22_legacy_load.sql（带 -- @needs，B1 / 旧模块表齐了才执行）。
# 生成时顺带修正同步定义的两处缺陷（视图缺列名清单、字符型 DEFAULT 无引号），对象一律不带 schema 前缀。
import os, re, glob, datetime, collections

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SYNC = os.path.join(ROOT, '0921-数据库同步')
OUT = os.path.join(ROOT, '部署包', '全部部署.sql')

SKIP = re.compile(r'BACKUP|_TEST|_2024\d\d|_2025\d\d', re.I)
BROKEN = {'MTC_COST_ROLLUP_CALC': '源码写的 RootItem 等列在 MTC_COST_ROLLUP_DETAIL 中不存在，FH100 上也无法编译，没有过程调用它'}
# 目标库里已有、但无效的坏对象：部署末尾删除（只删 IS_VALID 不是 TRUE 的，没有对象引用它们；用户 2026-10-29）
DROP_INVALID = [('VIEW', 'MTC_COST_ROLLUP_V'), ('PROCEDURE', 'MTC_COST_ROLLUP_CALC')]
# 同步定义缺列名清单的视图：MTC_VIEW_Document 取 0921-补充对象/ 的列名；MTC_DocType 第 1 列原名未知，代码只用 DocName、ObjType
VIEW_COLS = {'MTC_DocType': ['TableName', 'DocName', 'ObjType']}
# 计算需要、但由 B1 维护的 UDF（不在 @ 表里）
UDF = {'OWHS': ['U_IsCost'], 'OITM': ['U_ItemProp'], 'OIGN': ['U_TrsName'],
       'IGN1': ['U_BaseType', 'U_BaseEntry', 'U_BaseLineGrpNum', 'U_OWORNum', 'U_MTCOWORNum'],
       'IGE1': ['U_BaseType', 'U_BaseEntry', 'U_BaseLineGrpNum', 'U_OWORNum', 'U_MTCOWORNum'],
       'PDN1': ['U_BaseType', 'U_BaseEntry', 'U_OWORType', 'U_OWORNum', 'U_MTCOWORNum']}

def rd(p): return open(p, encoding='utf-8').read().replace('\r\n', '\n')
def unq(s): return re.sub(r'"FH100"\.', '', s)
def name(p): return os.path.basename(p)[:-4]

def doc_cols():
    s = rd(os.path.join(ROOT, '0921-补充对象', 'MTC_VIEW_Document.sql'))
    return re.findall(r'"([^"]+)"', re.search(r'MTC_VIEW_Document"\s*\((.*?)\)\s*AS', s, re.S).group(1))
VIEW_COLS['MTC_VIEW_Document'] = doc_cols()

def fix_table(s):
    # DEFAULT O → DEFAULT 'O'（只处理字符型列、未加引号的标识符值）
    return re.sub(r'((?:N?VAR)?CHAR\(\d+\)|ALPHANUM\(\d+\)) DEFAULT ([A-Za-z_]\w*)(?=[,\s])',
                  lambda m: m.group(0) if m.group(2).upper() in ('NULL', 'CURRENT_TIMESTAMP', 'CURRENT_DATE', 'CURRENT_TIME', 'CURRENT_USER')
                  else "%s DEFAULT '%s'" % (m.group(1), m.group(2)), s)

def fix_view(n, s):
    if n in VIEW_COLS and re.match(r'CREATE VIEW "[^"]+" AS', s):
        s = s.replace('CREATE VIEW "%s" AS' % n, 'CREATE VIEW "%s" (%s) AS' % (n, ', '.join('"%s"' % c for c in VIEW_COLS[n])), 1)
    return s

def sql_lit(v):
    if v == '': return 'NULL'
    v = re.sub(r'^(\d\d)/(\d\d)/(\d{4})', r'\3-\1-\2', v)   # 导出的日期是 月/日/年
    return "'" + v.replace("'", "''") + "'"

# ---------- 旧模块 ----------
objs = collections.OrderedDict()   # name -> (kind, sql)
skipped = []
for sub, kind in (('表结构', 'TABLE'), ('视图', 'VIEW'), ('表函数', 'FUNCTION'), ('存储过程', 'PROCEDURE')):
    for p in sorted(glob.glob(os.path.join(SYNC, sub, '*.sql'))):
        n = name(p)
        if kind == 'TABLE' and n.startswith('@'): continue          # B1 自定义表由 B1 建，只做存在性检查
        if SKIP.search(n): skipped.append((n, '备份/测试对象')); continue
        if n in BROKEN: skipped.append((n, BROKEN[n])); continue
        s = unq(rd(p)).strip()
        s = fix_table(s) if kind == 'TABLE' else fix_view(n, s) if kind == 'VIEW' else s
        objs[n] = (kind, s)

# 按 依赖关系.tsv 拓扑排序（表最前；同层按类型、名称）
deps = collections.defaultdict(set)
for l in rd(os.path.join(SYNC, '依赖关系.tsv')).split('\n')[1:]:
    f = l.split('\t')
    if len(f) >= 2 and f[0] in objs and f[1] in objs and f[0] != f[1]: deps[f[0]].add(f[1])
rank = {'TABLE': 0, 'VIEW': 1, 'FUNCTION': 2, 'PROCEDURE': 3}
order, done = [], set()
def visit(n, stack=()):
    if n in done or n in stack: return
    for d in sorted(deps[n], key=lambda x: (rank[objs[x][0]], x)): visit(d, stack + (n,))
    done.add(n); order.append(n)
for n in sorted(objs, key=lambda x: (rank[objs[x][0]], x)): visit(n)

# @ 表和 UDF 的列：执行程序部署前检查
require = {}
for p in sorted(glob.glob(os.path.join(SYNC, '表结构', '@*.sql'))):
    require[name(p)] = re.findall(r'^\s+"([^"]+)"\s', rd(p), re.M)
require.update(UDF)

# 配置数据：只插入目标库中还没有的代码
data_stmts = []
for p in sorted(glob.glob(os.path.join(SYNC, '配置数据', '*.tsv'))):
    t = os.path.basename(p)[len('配置数据_'):-4]
    lines = [l for l in rd(p).rstrip('\n').split('\n')]
    cols = lines[0].split('\t')
    if t in require: cols_ok = [i for i, c in enumerate(cols) if c in require[t]]
    else: cols_ok = list(range(len(cols)))
    for l in lines[1:]:
        if not l.strip(): continue
        v = l.split('\t'); v += [''] * (len(cols) - len(v))
        data_stmts.append((t, v[0], 'INSERT INTO "%s" (%s) SELECT %s FROM DUMMY WHERE NOT EXISTS (SELECT 1 FROM "%s" WHERE "%s" = %s)' % (
            t, ', '.join('"%s"' % cols[i] for i in cols_ok), ', '.join(sql_lit(v[i]) for i in cols_ok), t, cols[0], sql_lit(v[0]))))

# ---------- 新框架 ----------
nf = sorted(glob.glob(os.path.join(ROOT, '新框架', 'sql', '[01][0-9]_*.sql')))
nf = [f for f in nf if not os.path.basename(f).startswith('10_')] + [f for f in nf if os.path.basename(f).startswith('10_')]

# ---------- B1 字段核对（用户 2026-10-29：要在 B1 前台新建的字段曾漏登记，如 OPRC.U_CalType） ----------
# 扫描新框架 SQL、取数 SQL、执行台查询引用的 B1 表 / 字段，三种情况报“未登记”：
#   1. 表.字段：同一条语句的旧模块代码里没出现过（旧模块在用 = FH100 已有），也不在 新框架/B1对象登记.tsv；
#   2. @MTC_CA_* 上的字段：B1自定义表_费用配置.md 的字段表里没有；
#   3. 对不上表的 U_ 字段名（动态 SQL 拼出来的）：旧模块、文档、登记表里都没出现过。
# 登记为“新建”的写进部署包 -- @b1new，deploy.py / deploy.ps1 部署时检查目标库，缺了提示到 B1 前台新建。
B1REG = os.path.join(ROOT, '新框架', 'B1对象登记.tsv')
B1DOC = os.path.join(ROOT, '新框架', 'B1自定义表_费用配置.md')
_SKIPW = {'ON', 'WHERE', 'LEFT', 'INNER', 'JOIN', 'GROUP', 'ORDER', 'UNION', 'AND', 'CROSS', 'RIGHT', 'SET', 'AS', 'OR',
          'WITH', 'USING', 'LIMIT', 'FULL', 'OUTER'}
def _stmts(p): return re.split(r';|\n@@\n|"sql":|\bEXEC\b', rd(p).replace('\\"', '"'))
def _b1tab(t): return t.startswith('@') or re.fullmatch(r'[A-Z]{3,4}\d?', t) is not None
def b1_refs(files):
    d = {}
    for p in files:
        for st in _stmts(p):
            al = {}
            for m in re.finditer(r'(?:FROM|JOIN|UPDATE|INTO)\s+"([A-Za-z0-9@_]+)"(?:\s+(?:AS\s+)?([A-Za-z]\w*))?', st):
                if m.group(2) and m.group(2).upper() not in _SKIPW: al[m.group(2)] = m.group(1)
                al[m.group(1)] = m.group(1)
            for m in re.finditer(r'(?:\b([A-Za-z]\w*)|"([A-Za-z0-9@_]+)")\."(U_\w+)"', st):
                t = al.get(m.group(1) or m.group(2))
                if t and _b1tab(t): d.setdefault('%s.%s' % (t, m.group(3)), set()).add(os.path.relpath(p, ROOT))
            ts = set(al.values())
            if len(ts) == 1 and _b1tab(next(iter(ts))):
                for m in re.finditer(r'(?<![\.\w"])"(U_\w+)"', st):
                    d.setdefault('%s.%s' % (next(iter(ts)), m.group(1)), set()).add(os.path.relpath(p, ROOT))
            for m in re.finditer(r'"@([A-Z0-9_]+)"', st): d.setdefault('@' + m.group(1), set()).add(os.path.relpath(p, ROOT))
    return d
b1reg = {}
for l in rd(B1REG).split('\n')[1:]:
    f = l.split('\t')
    if len(f) >= 4 and f[0].strip(): b1reg[f[0].strip()] = (f[1].strip(), f[2].strip(), f[3].strip())
scan = [p for p in glob.glob(os.path.join(ROOT, '新框架', 'sql', '*.sql')) if not re.search(r'99_drop', p)] \
     + glob.glob(os.path.join(ROOT, 'tools', 'console', 'srcsql', '*.sql')) + [os.path.join(ROOT, 'tools', 'console', 'actions.json')]
old_files = glob.glob(os.path.join(SYNC, '**', '*.sql'), recursive=True)
old_st = [s for p in old_files for s in _stmts(p)]
old_txt = '\n'.join(old_st)
doc = rd(B1DOC)
doc_fields = set(re.findall(r'^\|\s*`([A-Za-z]\w*)`\s*\|', doc, re.M))
unreg = []
for k, fs in sorted(b1_refs(scan).items()):
    if k in b1reg: continue
    if '.' not in k:                                            # 整张 @ 表
        if k.startswith('@MTC_CA_') or k not in old_txt: unreg.append((k, fs))
        continue
    t, c = k.split('.', 1)
    if t.startswith('@MTC_CA_'):
        if c[2:] not in doc_fields: unreg.append((k, fs))
    elif not any(t in s and c in s for s in old_st): unreg.append((k, fs))
reg_names = {k.split('.')[-1] for k in b1reg}
for p in scan:
    for c in sorted(set(re.findall(r'\bU_[A-Za-z]\w*', rd(p)))):
        if c not in old_txt and c[2:] not in doc_fields and c not in reg_names and c not in doc:
            unreg.append(('?.%s（对不上表）' % c, {os.path.relpath(p, ROOT)}))
b1new = [(k, v) for k, v in b1reg.items() if v[0] == '新建']

# ---------- 输出 ----------
stmts = []
for n in order:
    k, s = objs[n]; stmts.append(('旧模块 %s %s' % (k, n), s))
for t, code, s in data_stmts:
    stmts.append(('配置数据 %s %s' % (t, code), s))
# 已有的表会跳过：紧跟一段 DO，把表结构里有、库里没有的列补上（NOT NULL 去掉，DEFAULT 保留），老库升级不用单独打补丁
def add_missing_cols(s):
    m = re.match(r'CREATE (?:COLUMN |ROW )?TABLE "([^"]+)"\s*\((.*)\)\s*$', s, re.S)
    if not m: return None
    t, body = m.groups(); adds = []
    for l in body.split('\n'):
        c = re.match(r'\s*"([^"]+)"\s+(.*?)\s*,?\s*(?:--.*)?$', l)
        if not c: continue
        d = re.sub(r'\s+NOT NULL', '', c.group(2)).rstrip(',').strip()
        adds.append("    SELECT COUNT(*) INTO n FROM SYS.TABLE_COLUMNS WHERE SCHEMA_NAME = CURRENT_SCHEMA AND TABLE_NAME = '%s' AND COLUMN_NAME = '%s';\n"
                    "    IF :n = 0 THEN EXEC 'ALTER TABLE \"%s\" ADD (\"%s\" %s)'; END IF;" % (t, c.group(1), t, c.group(1), d.replace("'", "''")))
    return t, 'DO BEGIN\n    DECLARE n INT;\n%s\nEND' % '\n'.join(adds)

for f in nf:
    for i, s in enumerate([x.strip() for x in rd(f).split('\n@@\n') if x.strip()], 1):
        stmts.append(('新框架 %s #%d' % (os.path.basename(f), i), s))
        a = add_missing_cols(s)
        if a: stmts.append(('新框架 %s #%d 补齐 %s 缺少的列' % (os.path.basename(f), i, a[0]), a[1]))
stmts.append(('新框架 同步数据字典', 'CALL "MTC_CA_P_META_SYNC"()'))
# B1 配置校验（20_b1cfg_check.sql：视图 MTC_CA_V_B1CFG_ISSUES、TN 过程 MTC_CA_P_B1CFG_TN；用户 2026-10-29 决定进部署包）：
# 直接引用 B1 自定义表，B1 里还没建全时编译不过，所以带 -- @needs，部署程序检查这些表 / 字段都在才执行，缺了跳过并列出缺什么。
# 没有这个视图时 P05 不同步 @MTC_CA_PARAM，B1 补齐后重新部署即可装上。
B1CFG_NEEDS = '@MTC_CA_PARAM,@MTC_CA_POOL,@MTC_CA_POOL1,@MTC_CA_POOL2,OPRC.U_CalType,OITB.U_ItemGrpType'
f20 = os.path.join(ROOT, '新框架', 'sql', '20_b1cfg_check.sql')
for i, s20 in enumerate([x.strip() for x in rd(f20).split('\n@@\n') if x.strip()], 1):
    stmts.append(('B1 配置校验 20_b1cfg_check.sql #%d' % i, '-- @needs %s\n%s' % (B1CFG_NEEDS, s20)))
# 成本报表（21_reports.sql：24 个只读过程 MTC_CA_RPT_*，用户 2026-10-30）：引用旧模块的 B1 自定义表和字段，带 -- @needs，缺了跳过
RPT_NEEDS = '@MTC_SALORDTYPE,@MTC_OMRV,@MTC_COST_IOTYPE,OINV.U_SalOrdType,ORIN.U_SalOrdType,ODLN.U_SalOrdType,ORDN.U_SalOrdType,PDN1.U_InitPrice,PDN1.U_IsPrice'
f21 = os.path.join(ROOT, '新框架', 'sql', '21_reports.sql')
for i, s21 in enumerate([x.strip() for x in rd(f21).split('\n@@\n') if x.strip()], 1):
    stmts.append(('成本报表 21_reports.sql #%d' % i, '-- @needs %s\n%s' % (RPT_NEEDS, s21)))
# 历史回填（22_legacy_load.sql：旧框架结果转成历史运行 RunType H，报表合并，用户 2026-11-02）：读旧模块结果表，带 -- @needs，旧表齐了才执行
LEGACY_NEEDS = ('MTC_COST_0301_INVNT,MTC_COST_0302_INVNTDETAIL1,MTC_COST_0321_OWOR,MTC_COST_0321_OWOR1,MTC_COST_0321_OWOR1_REG,'
                'MTC_COST_0321_OWOR_SUM,MTC_COST_0322_OWOR_ZCP,MTC_COST_0322_OWOR_ZCP1,MTC_COST_0801_TOOJDT,MTC_COST_0802_OJDTBASEDETAIL,U_COILV,'
                '@MTC_OWOR,@MTC_WOR1,@U_CIOTRN,@MTC_COST_IOTYPE')
f22 = os.path.join(ROOT, '新框架', 'sql', '22_legacy_load.sql')
for i, s22 in enumerate([x.strip() for x in rd(f22).split('\n@@\n') if x.strip()], 1):
    stmts.append(('历史回填 22_legacy_load.sql #%d' % i, '-- @needs %s\n%s' % (LEGACY_NEEDS, s22)))
for k, n in DROP_INVALID:
    sv = 'SYS.VIEWS WHERE SCHEMA_NAME = CURRENT_SCHEMA AND VIEW_NAME' if k == 'VIEW' else 'SYS.PROCEDURES WHERE SCHEMA_NAME = CURRENT_SCHEMA AND PROCEDURE_NAME'
    stmts.append(('清理 删除无效的旧对象 %s %s' % (k, n),
                  "DO BEGIN\n    DECLARE n INT;\n    SELECT COUNT(*) INTO n FROM %s = '%s' AND IS_VALID <> 'TRUE';\n"
                  "    IF :n > 0 THEN EXEC 'DROP %s \"%s\"'; END IF;\nEND" % (sv, n, k, n)))

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, 'w', encoding='utf-8', newline='\n') as w:
    w.write('-- FH100 成本核算一次性部署包（由 新框架/tools/build_deploy.py 生成，不要手改）\n')
    w.write('-- 生成时间 %s；旧模块来源 0921-数据库同步/（%s）\n' % (datetime.datetime.now().strftime('%Y-%m-%d %H:%M'), rd(os.path.join(SYNC, '同步时间.txt')).split('\n')[0].strip()))
    w.write('-- 内容：旧成本模块 %d 个对象、配置数据 %d 行、新框架 %d 条语句。对象不带 schema 前缀，建在当前 schema。\n' % (
        len(order), len(data_stmts), len(stmts) - len(order) - len(data_stmts)))
    w.write('-- 语句之间用单独一行 @@ 分隔，每条以 "-- @stmt 说明" 开头。请用 部署包/ 里的执行程序执行（见 README.md）。\n')
    w.write('-- 已有的表、索引、序列、旧模块视图和过程会跳过（不会覆盖）；新框架的视图、过程是 CREATE OR REPLACE，配置初值是 UPSERT。\n')
    for n, why in skipped: w.write('-- 未包含：%s（%s）\n' % (n, why))
    for t, cs in require.items(): w.write('-- @require %s: %s\n' % (t, ','.join(cs)))
    for k, (st, must, why) in b1new: w.write('-- @b1new %s|%s|%s\n' % (k, must, why))
    for label, s in stmts:
        w.write('\n@@\n-- @stmt %s\n%s\n' % (label, s))
print('已生成 %s：%d 条语句（旧模块 %d、配置数据 %d），检查 %d 张表的字段，未包含 %d 个对象' % (
    os.path.relpath(OUT, ROOT), len(stmts), len(order), len(data_stmts), len(require), len(skipped)))
if unreg:
    print('\n⚠ 有 %d 个 B1 表 / 字段没有登记（新框架/B1对象登记.tsv）：要在 B1 前台新建的，登记为“新建”并写进 B1自定义表_费用配置.md 开头的汇总表；'
          'FH100 已有的登记为“已有”；扫描误报的登记为“误报”' % len(unreg))
    for k, fs in unreg: print('   %s  ← %s' % (k, '、'.join(sorted(fs)[:3])))
else:
    print('B1 字段核对：新代码引用的 B1 表 / 字段都已登记（要新建 %d 项，见 -- @b1new）' % len(b1new))
