# 成本报表（用户 2026-10-30）：由 新框架/reports/rpt_defs.json 生成
#   ① 新框架/reports/B1查询语句.md   每张报表一条可粘贴进 B1 查询管理器的 CALL 语句
#   ② tools/console/js/rptdefs.js    执行台“成本报表”页的报表定义 RPTDEFS（含 B1 语句）
#   ③ tools/console/actions.json     rpt00 … rpt24 和下拉查询 rptGrpList / rptPoolList / rptCustType / rptSalType、参数校验 rp_*
# 并核对 rpt_defs.json 的参数顺序与 新框架/sql/21_reports.sql 的过程签名一致。改了 rpt_defs.json 或过程参数后运行：
#   python3 新框架/tools/gen_rpt.py
import json, os, re, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
DEFS = os.path.join(ROOT, '新框架', 'reports', 'rpt_defs.json')
SQL = os.path.join(ROOT, '新框架', 'sql', '21_reports.sql')
MD = os.path.join(ROOT, '新框架', 'reports', 'B1查询语句.md')
JS = os.path.join(ROOT, 'tools', 'console', 'js', 'rptdefs.js')
ACT = os.path.join(ROOT, 'tools', 'console', 'actions.json')

defs = json.load(open(DEFS, encoding='utf-8'))['reports']
sql = open(SQL, encoding='utf-8').read()

# 过程签名
sig = {}
for m in re.finditer(r'CREATE OR REPLACE PROCEDURE "(MTC_CA_RPT_\w+)"\s*\((.*?)\)\s*LANGUAGE', sql, re.S):
    sig[m.group(1)] = re.findall(r'\bIN\s+(\w+)\s+NVARCHAR', m.group(2))
bad = []
for r in defs:
    names = [p['name'] for p in r['params']]
    if sig.get(r['proc']) != names: bad.append('%s：定义 %s，过程 %s' % (r['proc'], names, sig.get(r['proc'])))
missing = set(sig) - {r['proc'] for r in defs}
if bad or missing:
    for b in bad: print('✗ 参数不一致 ' + b)
    for m in sorted(missing): print('✗ 过程没有定义 ' + m)
    sys.exit(1)

# B1 选择列表提示：/* SELECT FROM "表" Tn WHERE Tn."字段" = '[%n]' */（HANA 版 B1 是否弹出选择列表部署时验证；不生效也能手工填）
def b1_sql(r):
    lines, args = [], []
    for i, p in enumerate(r['params']):
        if p.get('b1'):
            t, c = p['b1'].split('.')
            lines.append('/* SELECT FROM "%s" T%d WHERE T%d."%s" = \'[%%%d]\' */' % (t, i, i, c, i))
        args.append("'[%%%d]'" % i)
    return '\n'.join(lines + ['CALL "%s"(%s);' % (r['proc'], ', '.join(args))])

TYPE_HINT = {'fc': '账期 YYYY-MM', 'grp': '物料组代码', 'pool': '费用池代码', 'custType': '客户类型（@MTC_SALORDTYPE.U_CustType）',
             'salType': '销售订单类型（@MTC_SALORDTYPE.Name）', 'yn': 'Y / N', 'num': '数字'}
def p_hint(p):
    if p.get('opts'): return '；'.join('%s = %s' % (v or '空', l) for v, l in p['opts'])
    h = p.get('hint') or TYPE_HINT.get(p['type'], '')
    if p['type'] == 'yn': h = 'Y / N，空 = N'
    if p.get('def') and p['type'] in ('yn', 'num'): h += '（执行台默认 %s）' % p['def']
    return h

out = ['# 成本报表：B1 查询管理器语句', '',
       '> 由 `新框架/tools/gen_rpt.py` 按 `新框架/reports/rpt_defs.json` 生成，不要手改。过程定义在 `新框架/sql/21_reports.sql`（用户 2026-10-30）。', '',
       '用法：B1 → 工具 → 查询 → 查询管理器 → 新建，把语句整段粘贴进去，保存到分类“成本报表（新）”（或运行 `python3 新框架/tools/sl_import_queries.py` 一次登记全部 24 条）。',
       '执行时 B1 依次弹出参数框：**留空 = 全部**；多个值用英文逗号；物料、订单号、业务伙伴按开头匹配，前面加 `=` 精确匹配（如 `=A1`）。',
       '账期留空 = 最近一个已计算账期。所有报表都取该账期“生成凭单所用运行”，没有生成凭单时取“最近一次成功正式运行”，与执行台“成本报表”页完全一致（看 R00）。', '',
       '`/* SELECT FROM … */` 注释行是给 B1 参数框认字段用的（弹出选择列表）；HANA 版 B1 是否生效部署时验证，不生效也可以直接手填。', '']
for r in defs:
    out += ['## R%s %s' % (r['id'], r['name']), '', r['desc'], '', '| # | 参数 | 填法 |', '|---|---|---|']
    for i, p in enumerate(r['params']):
        out.append('| [%%%d] | %s `%s` | %s |' % (i, p['label'], p['name'], p_hint(p)))
    out += ['', '```sql', b1_sql(r), '```', '']
open(MD, 'w', encoding='utf-8', newline='\n').write('\n'.join(out))

# 执行台定义
js_defs = [dict(r, b1=b1_sql(r)) for r in defs]
open(JS, 'w', encoding='utf-8', newline='\n').write(
    '// 成本执行台 · rptdefs.js — 成本报表定义（由 新框架/tools/gen_rpt.py 按 新框架/reports/rpt_defs.json 生成，不要手改）\n'
    '"use strict";\nconst RPTDEFS = ' + json.dumps(js_defs, ensure_ascii=False, indent=1) + ';\n')

# actions.json
VAL = {'fc': r'^(\d{4}-\d{2})?$', 'text': r'^[^\x00-\x1f]{0,500}$', 'grp': r'^[^\x00-\x1f]{0,500}$', 'pool': r'^[^\x00-\x1f]{0,500}$',
       'custType': r'^[^\x00-\x1f]{0,200}$', 'salType': r'^[^\x00-\x1f]{0,500}$', 'sel': r'^[^\x00-\x1f]{0,50}$', 'stype': r'^\d?$',
       'yn': r'^[YN]?$', 'num': r'^(\d{1,9}(\.\d{1,4})?)?$'}
txt = open(ACT, encoding='utf-8').read()
d = json.loads(txt)
for k in [k for k in d['validators'] if k.startswith('rp_')]: del d['validators'][k]
for k in [k for k in d['actions'] if re.match(r'^rpt(\d\d|GrpList|PoolList|CustType|SalType)$', k)]: del d['actions'][k]
types = {}
for r in defs:
    for p in r['params']:
        if types.setdefault(p['name'], p['type']) != p['type'] and VAL[types[p['name']]] != VAL[p['type']]:
            sys.exit('✗ 参数 %s 在不同报表里类型不同（%s / %s），校验规则冲突' % (p['name'], types[p['name']], p['type']))
for n, t in sorted(types.items()): d['validators']['rp_' + n] = VAL[t]
for r in defs:
    d['actions']['rpt' + r['id']] = {'kind': 'query', 'title': 'R%s %s' % (r['id'], r['name']),
                                     'params': ['rp_' + p['name'] for p in r['params']],
                                     'sql': 'CALL "%s"(%s)' % (r['proc'], ', '.join('?' * len(r['params'])))}
d['actions']['rptGrpList'] = {'kind': 'query', 'params': [], 'sql': 'SELECT TO_NVARCHAR("ItmsGrpCod") AS "Code", "ItmsGrpNam" AS "Name" FROM "OITB" ORDER BY "ItmsGrpCod"'}
d['actions']['rptPoolList'] = {'kind': 'query', 'params': [], 'sql': 'SELECT "PoolCode" AS "Code", "PoolName" AS "Name" FROM "MTC_CA_C_POOL" ORDER BY "PoolCode"'}
d['actions']['rptCustType'] = {'kind': 'query', 'params': [], 'sql': 'SELECT DISTINCT "U_CustType" AS "Code", "U_CustType" AS "Name" FROM "@MTC_SALORDTYPE" WHERE IFNULL("U_CustType", \'\') <> \'\' ORDER BY 1'}
d['actions']['rptSalType'] = {'kind': 'query', 'params': [], 'sql': 'SELECT "Name" AS "Code", "Name" AS "Name" FROM "@MTC_SALORDTYPE" ORDER BY "Name"'}
open(ACT, 'w', encoding='utf-8', newline='\n').write(json.dumps(d, ensure_ascii=False, indent=2) + '\n')
print('已生成 %s、%s，更新 %s：%d 张报表' % tuple([os.path.relpath(x, ROOT) for x in (MD, JS, ACT)] + [len(defs)]))
