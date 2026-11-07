#!/bin/bash
# Mac 上双击运行成本执行台（在“终端”中打开）。需要 Python 3 和 hdbcli。
cd "$(dirname "$0")/.." || exit 1
if ! python3 -c "import hdbcli" 2>/dev/null; then
  echo "缺少 HANA 的 Python 驱动 hdbcli，请先在终端执行：pip3 install hdbcli"
  read -r -p "按回车关闭" _; exit 1
fi
python3 tools/console/dev_server.py
read -r -p "服务已停止，按回车关闭窗口" _
