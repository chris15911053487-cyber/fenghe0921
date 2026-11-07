# 生成一次性部署包：部署包/全部部署.sql（旧成本模块 + 配置数据 + 新框架 01–16），供 部署包/ 里的执行程序使用。
# 用法：python3 新框架/tools/build_deploy.py
# 来源：旧模块取 0921-数据库同步/（跳过备份/测试对象和坏对象），新框架取 新框架/sql/01–16（10 放在 11–16 之后）。
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
    for label, s in stmts:
        w.write('\n@@\n-- @stmt %s\n%s\n' % (label, s))
print('已生成 %s：%d 条语句（旧模块 %d、配置数据 %d），检查 %d 张表的字段，未包含 %d 个对象' % (
    os.path.relpath(OUT, ROOT), len(stmts), len(order), len(data_stmts), len(require), len(skipped)))
