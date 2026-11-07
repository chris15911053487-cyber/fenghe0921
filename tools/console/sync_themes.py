"""把 Online-report 的界面主题（frontend/src/theme/themes.css）原样同步成执行台的 css/themes.css。

执行台的颜色变量（--bg、--accent、--hdr-* 等）在 css/app.css 的 :root 里映射到 themes.css 的 --c-* 语义变量，
所以两边的六套主题（warm / ent / tech / ind / mono / dark）完全一致；Online-report 改了配色后重跑本脚本即可。
用法：python3 tools/console/sync_themes.py [themes.css 路径]
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Documents/AI/Claude/Online-report/frontend/src/theme/themes.css")
DST = os.path.join(HERE, "css", "themes.css")
HEAD = "/* 成本执行台 · 界面主题：Online-report frontend/src/theme/themes.css 的原样副本，勿手改；Online-report 改了配色后运行 python3 tools/console/sync_themes.py */\n"

css = open(SRC, encoding="utf-8").read().strip()
open(DST, "w", encoding="utf-8").write(HEAD + css + "\n")
print("已同步", SRC, "→", DST)
