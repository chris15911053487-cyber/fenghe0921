<#
  成本执行台服务器模式：重启后台服务（由 restart_service.bat 以管理员身份调用，2026-10-23）。
  什么时候用：更新了 dev_server.py / hana_odbc.py / dpapi.py，或改了 server.json、证书之后。
  只改 index.html、login.html、css\、js\、actions.json 不用重启（每次请求重新读取）。
  步骤：停开机任务 → 结束还在运行的 run_server.bat 循环和 dev_server.py --server 进程 → 等端口释放 → 启动任务 → 等端口开始监听，显示 server.log 最后几行。
  重启会断开所有人的登录；计算进行中重启会中断计算。
#>
$ErrorActionPreference = 'Stop'
$name = 'MTC Cost Console'
$cfgDir = if (Test-Path (Join-Path $PSScriptRoot 'console\dev_server.py')) { Join-Path $PSScriptRoot 'console' } else { Split-Path $PSScriptRoot -Parent }
$log = Join-Path $cfgDir 'logs\server.log'
$port = 8766
try { $p = [int]((Get-Content (Join-Path $cfgDir 'server.json') -Raw -Encoding UTF8 | ConvertFrom-Json).port); if ($p) { $port = $p } } catch { }
$listening = { [bool](Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) }

if (-not (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue)) {
  Write-Host "没有找到开机任务“$name”，请先右键 install_service.bat 以管理员身份运行。" -ForegroundColor Red; exit 1
}
Write-Host "将重启成本执行台服务（任务“$name”，端口 $port）。" -ForegroundColor Yellow
Write-Host '重启会断开所有人的登录；如果有人正在计算，计算会中断。'
if ((Read-Host '确认现在重启？(Y/N)') -notmatch '^[Yy]') { Write-Host '没有重启。'; exit 0 }

Write-Host '停止任务…'
Stop-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
# 任务停止后，它启动的进程可能还在：先结束 run_server.bat 的循环（否则 10 秒后又把 Python 拉起来），再结束 Python
Get-CimInstance Win32_Process -Filter "Name = 'cmd.exe'" | Where-Object { $_.CommandLine -like '*run_server.bat*' } |
  ForEach-Object { Write-Host "结束 run_server.bat（进程 $($_.ProcessId)）"; Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Get-CimInstance Win32_Process -Filter "Name like 'python%'" | Where-Object { $_.CommandLine -like '*dev_server.py*--server*' } |
  ForEach-Object { Write-Host "结束 dev_server.py（进程 $($_.ProcessId)）"; Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
for ($i = 0; $i -lt 15 -and (& $listening); $i++) { Start-Sleep -Seconds 1 }
if (& $listening) {
  $o = (Get-NetTCPConnection -LocalPort $port -State Listen | Select-Object -First 1).OwningProcess
  Write-Host "端口 $port 仍被进程 $o 占用（$((Get-Process -Id $o -ErrorAction SilentlyContinue).ProcessName)），请在任务管理器里结束它后再运行本脚本。" -ForegroundColor Red; exit 1
}

Write-Host '启动任务…'
Start-ScheduledTask -TaskName $name
for ($i = 0; $i -lt 60 -and -not (& $listening); $i++) { Start-Sleep -Seconds 1 }
if (Test-Path $log) { Write-Host "`n--- $log 最后 15 行 ---"; Get-Content $log -Tail 15 -Encoding UTF8 }
if (& $listening) { Write-Host "`n已重启，端口 $port 正在监听。用户需要重新登录。" -ForegroundColor Green }
else { Write-Host "`n60 秒内端口 $port 没有开始监听，请看上面的日志（常见：server.json 写错、HANA 连不上、hdbuserstore 键不是用服务账号建的）。" -ForegroundColor Red; exit 1 }
