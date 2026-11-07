# 把 新框架/sql/*.sql 中 CREATE COLUMN TABLE 字段行尾的 “-- 说明” 生成为 COMMENT ON COLUMN 语句，
# 写到 新框架/sql/18_meta_comments.sql；部署后 MTC_CA_P_META_SYNC 会把它们同步进数据字典 MTC_CA_M_COLUMN，
# 执行台“说明”页和系统说明书从数据字典读取。
# 用法：python3 新框架/tools/build_meta_comments.py（改了建表语句的注释后重新生成，再重新生成部署包）
import os, re, glob

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SQL = os.path.join(ROOT, '新框架', 'sql')
OUT = os.path.join(SQL, '18_meta_comments.sql')

def lit(s): return "'" + s.replace("'", "''") + "'"

out, seen = [], set()
for f in sorted(glob.glob(os.path.join(SQL, '[01][0-9]_*.sql'))):
    if os.path.basename(f).startswith('18_'): continue
    for blk in open(f, encoding='utf-8').read().split('\n@@\n'):
        m = re.search(r'CREATE COLUMN TABLE "(MTC_CA_[A-Z0-9_]+)"\s*\((.*)\)\s*$', blk, re.S)
        if not m: continue
        table, body = m.group(1), m.group(2)
        for line in body.split('\n'):
            if '--' not in line: continue
            code, note = line.split('--', 1)
            note = note.strip()
            cols = re.findall(r'"([A-Za-z0-9_]+)"\s+(?:NVARCHAR|VARCHAR|DECIMAL|INT|INTEGER|BIGINT|DATE|TIMESTAMP|NCLOB|SMALLINT|DOUBLE)', code)
            if not note or not cols: continue
            for c in cols:
                if (table, c) in seen: continue
                seen.add((table, c))
                out.append('COMMENT ON COLUMN "%s"."%s" IS %s' % (table, c, lit(note[:500])))

# 快照 / 结果表都带的运行键，没有行尾注释时给统一说明
STD = {'FcCode': '账期（OFPR.Code）', 'RunType': 'F 正式 / S 模拟', 'Scenario': '模拟场景（正式运行为空串）', 'RunId': '运行号（MTC_CA_RUN.RunId）'}
for f in sorted(glob.glob(os.path.join(SQL, '[01][0-9]_*.sql'))):
    if os.path.basename(f).startswith('18_'): continue
    for m in re.finditer(r'CREATE COLUMN TABLE "(MTC_CA_[A-Z0-9_]+)"\s*\((.*?)\n\)', open(f, encoding='utf-8').read(), re.S):
        for c, note in STD.items():
            if re.search(r'"%s"\s+(NVARCHAR|BIGINT)' % c, m.group(2)) and (m.group(1), c) not in seen:
                seen.add((m.group(1), c))
                out.append('COMMENT ON COLUMN "%s"."%s" IS %s' % (m.group(1), c, lit(note)))

hdr = ('-- 由 新框架/tools/build_meta_comments.py 从建表语句的行尾注释生成，不要手改；共 %d 条。\n'
       '-- 部署后执行 CALL "MTC_CA_P_META_SYNC"() 同步到数据字典（部署包最后会自动执行）。\n' % len(out))
open(OUT, 'w', encoding='utf-8', newline='\n').write(hdr + '\n@@\n'.join(out) + '\n')
print('已生成 %s：%d 条字段说明' % (OUT, len(out)))
