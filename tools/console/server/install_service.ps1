<#
  成本执行台服务器模式：注册开机任务 + 防火墙规则（由 install_service.bat 以管理员身份调用）。
  任务以指定的服务账号运行 run_server.bat，不限运行时长，异常退出 1 分钟后重启（run_server.bat 自己也会循环重启）。
  hdbuserstore 键要在同一个服务账号下创建，见 tools/README.md“服务器部署”。
  卸载：Unregister-ScheduledTask -TaskName 'MTC Cost Console'；Remove-NetFirewallRule -DisplayName 'MTC Cost Console'
#>
$ErrorActionPreference = 'Stop'
$name = 'MTC Cost Console'
$bat = Join-Path $PSScriptRoot 'run_server.bat'
$cfgDir = if (Test-Path (Join-Path $PSScriptRoot 'console\dev_server.py')) { Join-Path $PSScriptRoot 'console' } else { Split-Path $PSScriptRoot -Parent }
$cfg = Join-Path $cfgDir 'server.json'
if (-not (Test-Path $cfg)) { Write-Host "找不到 $cfg，请先把 server.example.json 复制为 server.json 并修改。" -ForegroundColor Red; exit 1 }
$port = [int]((Get-Content $cfg -Raw -Encoding UTF8 | ConvertFrom-Json).port)
if (-not $port) { $port = 8766 }

Write-Host "将注册开机任务“$name”，运行 $bat，端口 $port。"
$acct = Read-Host '服务账号（如 .\svc_mtcca 或 域\账号；不要用个人账号）'
$cred = Get-Credential -UserName $acct -Message '服务账号的 Windows 密码'
$nets = Read-Host '允许访问的客户端网段，逗号分隔（如 192.168.1.0/24；直接回车 = 本地子网）'
$remote = if ($nets.Trim()) { $nets.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ } } else { 'LocalSubnet' }

$action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument ('/c "' + $bat + '"') -WorkingDirectory $PSScriptRoot
$trigger = New-ScheduledTaskTrigger -AtStartup
$set = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Settings $set -User $cred.UserName -Password $cred.GetNetworkCredential().Password -RunLevel Limited -Force | Out-Null

Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule -DisplayName $name -Direction Inbound -Protocol TCP -LocalPort $port -RemoteAddress $remote -Action Allow | Out-Null

Write-Host "已注册。现在启动：Start-ScheduledTask -TaskName '$name'（或重启服务器）。日志：$cfgDir\logs\server.log" -ForegroundColor Green
$go = Read-Host '现在就启动？(Y/N)'
if ($go -match '^[Yy]') { Start-ScheduledTask -TaskName $name; Write-Host '已启动，稍等几秒后用浏览器访问。' }
