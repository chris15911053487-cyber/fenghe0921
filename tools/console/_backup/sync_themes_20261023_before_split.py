"""把 Online-report 的界面主题（frontend/src/theme/themes.css）原样同步进执行台 index.html。

执行台的颜色变量（--bg、--accent、--hdr-* 等）都映射到 themes.css 的 --c-* 语义变量，
所以两边的六套主题（warm / ent / tech / ind / mono / dark）完全一致；Online-report 改了配色后重跑本脚本即可。
用法：python3 tools/console/sync_themes.py [themes.css 路径]
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Documents/AI/Claude/Online-report/frontend/src/theme/themes.css")
PAGE = os.path.join(HERE, "index.html")
BEGIN, END = "/* ==== themes.css BEGIN（Online-report 同步，勿手改；用 sync_themes.py 更新） ==== */", "/* ==== themes.css END ==== */"

css = open(SRC, encoding="utf-8").read().strip()
page = open(PAGE, encoding="utf-8").read()
block = f"{BEGIN}\n{css}\n{END}"
if BEGIN in page:
    page = re.sub(re.escape(BEGIN) + r".*?" + re.escape(END), lambda m: block, page, count=1, flags=re.S)
else:
    sys.exit("index.html 里没有 themes.css 标记，先按 CLAUDE.md 说明加上")
open(PAGE, "w", encoding="utf-8").write(page)
print("已同步", SRC, "→", PAGE)
