<#
  FH100 成本核算部署包执行程序（Windows 版，通过本机 HANA ODBC 驱动）

  用法：双击 部署.bat（只有 32 位 HANA Client 时双击 部署_32位.bat）
        或 powershell -ExecutionPolicy Bypass -File deploy.ps1 [-Dsn 数据源] [-Server 地址:端口] [-Database 租户] [-Schema 名称] [-Yes]
  执行 同目录 全部部署.sql：已有的表 / 索引 / 序列 / 旧模块视图和过程跳过，不覆盖；视图和过程因依赖顺序失败的会自动重试。
  日志写到同目录 部署日志_<时间>.txt，只记录语句状态，不含业务数据。密码只在内存中使用。
#>
param([string]$Dsn = '', [string]$Server = '', [string]$Database = '', [string]$Schema = '', [switch]$Yes)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$utf8 = New-Object System.Text.UTF8Encoding($false)
Add-Type -AssemblyName System.Data
function Info($m) { Write-Host $m -ForegroundColor Cyan }
function Warn($m) { Write-Host $m -ForegroundColor Yellow }
function Err($m)  { Write-Host $m -ForegroundColor Red }
$log = New-Object System.Collections.Generic.List[string]
function Out($m, [string]$color = '') { if ($color) { Write-Host $m -ForegroundColor $color } else { Write-Host $m }; $log.Add($m) }

$sqlPath = Join-Path $here '全部部署.sql'
if (-not (Test-Path $sqlPath)) { Err "找不到 $sqlPath"; Read-Host '按回车退出'; exit 1 }

# ---------------- 连接 ----------------
$plat = if ([Environment]::Is64BitProcess) { '64-bit' } else { '32-bit' }
if (-not $Dsn -and -not $Server) {
  $dsns = @()
  try { $dsns = @(Get-OdbcDsn -ErrorAction Stop | Where-Object { $_.DriverName -match 'HDB|HANA' }) } catch { }
  if ($dsns.Count -gt 0) {
    Write-Host '本机找到以下 HANA ODBC 数据源：'
    for ($i = 0; $i -lt $dsns.Count; $i++) {
      $mark = if ($dsns[$i].Platform -eq $plat) { '' } else { '  ← 位数与当前程序不同，选它可能连不上' }
      Write-Host ("  [{0}] {1}   驱动 {2}，{3}{4}" -f ($i + 1), $dsns[$i].Name, $dsns[$i].DriverName, $dsns[$i].Platform, $mark)
    }
    Write-Host '  [M] 不用数据源，手工输入服务器地址'
    $c = Read-Host '请选择'
    if ($c -match '^\d+$' -and [int]$c -ge 1 -and [int]$c -le $dsns.Count) { $Dsn = $dsns[[int]$c - 1].Name }
  }
  if (-not $Dsn) {
    $Server = Read-Host 'HANA 服务器地址和端口（例如 192.168.1.10:30015）'
    if (-not $Database) { $Database = Read-Host '租户数据库名（没有可直接回车）' }
  }
}
if ($Dsn) { $cs = "DSN=$Dsn" }
else {
  $drv = if ([Environment]::Is64BitProcess) { 'HDBODBC' } else { 'HDBODBC32' }
  $cs = "DRIVER={$drv};SERVERNODE=$Server"
  if ($Database) { $cs += ";DATABASENAME=$Database" }
}
$user = Read-Host '数据库账号（数据源里已保存账号时可直接回车）'
if ($user) {
  $sec = Read-Host '密码' -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
  try { $pw = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
  $cs += ';UID=' + $user + ';PWD={' + $pw.Replace('}', '}}') + '}'
  $pw = $null
}
if (-not $Schema) { $Schema = Read-Host '目标 schema' }
$Schema = $Schema.Replace('"', '')

try {
  $conn = New-Object System.Data.Odbc.OdbcConnection($cs)
  $conn.Open()
} catch {
  Err "连接失败：$($_.Exception.Message)"
  if ($_.Exception.Message -match 'IM002|IM014|architecture|未发现数据源|找不到') { Warn 'ODBC 驱动的位数要和程序一致；只装了 32 位 HANA Client 时请用 部署_32位.bat。' }
  Read-Host '按回车退出'; exit 1
}
$cs = $null

function Exec([string]$sql) { $cmd = $conn.CreateCommand(); $cmd.CommandTimeout = 0; $cmd.CommandText = $sql; [void]$cmd.ExecuteNonQuery() }
function Rows([string]$sql, [object[]]$p = @()) {
  $cmd = $conn.CreateCommand(); $cmd.CommandText = $sql
  foreach ($v in $p) { $x = $cmd.CreateParameter(); $x.Value = $v; [void]$cmd.Parameters.Add($x) }
  $r = $cmd.ExecuteReader(); $res = New-Object System.Collections.Generic.List[object]
  while ($r.Read()) { $a = New-Object object[] $r.FieldCount; [void]$r.GetValues($a); $res.Add($a) }
  $r.Close(); return ,$res
}
try { Exec ('SET SCHEMA "' + $Schema + '"') } catch { Err "schema $Schema 不存在或无权限：$($_.Exception.Message)"; Read-Host '按回车退出'; exit 1 }

# ---------------- 读部署包 ----------------
$text = [IO.File]::ReadAllText($sqlPath, $utf8).Replace("`r`n", "`n")
$parts = $text -split "`n@@`n"
$header = $parts[0]
$stmts = @()
foreach ($p in $parts[1..($parts.Count - 1)]) {
  $nl = $p.IndexOf("`n")
  $stmts += ,@($p.Substring(0, $nl).Replace('-- @stmt ', '').Trim(), $p.Substring($nl + 1).Trim())
}

# ---------------- 确认目标 ----------------
$t = (Rows "SELECT CURRENT_USER, CURRENT_SCHEMA, (SELECT DATABASE_NAME FROM SYS.M_DATABASE) FROM DUMMY")[0]
$nOld = (Rows "SELECT COUNT(*) FROM SYS.PROCEDURES WHERE SCHEMA_NAME = CURRENT_SCHEMA AND PROCEDURE_NAME LIKE 'MTC_COST_PROC%'")[0][0]
$nNew = (Rows "SELECT COUNT(*) FROM SYS.OBJECTS WHERE SCHEMA_NAME = CURRENT_SCHEMA AND OBJECT_NAME LIKE 'MTC\_CA\_%' ESCAPE '\'")[0][0]
Out ("目标：账号 {0}，租户 {1}，schema {2}；已有旧模块过程 {3} 个、新框架对象 {4} 个" -f $t[0], $t[2], $t[1], $nOld, $nNew) 'Cyan'

$miss = @()
foreach ($m in [regex]::Matches($header, '(?m)^-- @require ([^:]+): (.*)$')) {
  $tb = $m.Groups[1].Value
  $have = @{}; foreach ($r in (Rows 'SELECT COLUMN_NAME FROM SYS.TABLE_COLUMNS WHERE SCHEMA_NAME = CURRENT_SCHEMA AND TABLE_NAME = ?' @($tb))) { $have[[string]$r[0]] = 1 }
  if ($have.Count -eq 0) { $miss += "$tb（整张表）"; continue }
  $lack = @($m.Groups[2].Value.Split(',') | Where-Object { -not $have.ContainsKey($_) })
  if ($lack.Count) { $miss += "$tb." + ($lack -join ',') }
}
if ($miss.Count) { Out '以下 B1 自定义表 / 字段不存在，相关对象会编译失败：' 'Yellow'; foreach ($m in $miss) { Out "  $m" 'Yellow' } }
# 新框架要在 B1 前台新建的表 / 字段（新框架/B1对象登记.tsv 登记为“新建”的，2026-10-29）：只提示，不影响部署
$lack = @()
foreach ($m in [regex]::Matches($header, '(?m)^-- @b1new ([^|]+)\|([^|]*)\|(.*)$')) {
  $obj = $m.Groups[1].Value; $tb = $obj; $col = ''
  $i = $obj.IndexOf('.'); if ($i -gt 0) { $tb = $obj.Substring(0, $i); $col = $obj.Substring($i + 1) }
  if ($col) { $n = (Rows 'SELECT COUNT(*) FROM SYS.TABLE_COLUMNS WHERE SCHEMA_NAME = CURRENT_SCHEMA AND TABLE_NAME = ? AND COLUMN_NAME = ?' @($tb, $col))[0][0] }
  else { $n = (Rows 'SELECT COUNT(*) FROM SYS.TABLES WHERE SCHEMA_NAME = CURRENT_SCHEMA AND TABLE_NAME = ?' @($tb))[0][0] }
  if ([int]$n -eq 0) { $lack += ('{0}{1}：{2}' -f $obj, $(if ($m.Groups[2].Value -eq '是') { '（必须）' } else { '（可选）' }), $m.Groups[3].Value.TrimEnd()) }
}
if ($lack.Count) { Out '以下表 / 字段要在 B1 前台新建（见 新框架/B1自定义表_费用配置.md 开头的汇总表），不影响本次部署：' 'Yellow'; foreach ($m in $lack) { Out "  $m" 'Yellow' } }
if (-not $Yes) {
  # 要求完整输入账套名，防止连错账套
  $typed = (Read-Host "确认部署到 $($t[1])？请完整输入账套名继续").Trim()
  if ($typed.ToUpper() -ne ([string]$t[1]).ToUpper()) { Warn '输入与目标账套不一致，已取消'; Read-Host '按回车退出'; exit 1 }
}

# ---------------- 逐条执行 ----------------
$reCreate = New-Object regex '^CREATE\s+(?:(?:COLUMN|ROW|UNIQUE)\s+)?(TABLE|INDEX|SEQUENCE|VIEW|PROCEDURE|FUNCTION)\s+(?:"([^"]+)"|([A-Za-z_][\w$#]*))', 'IgnoreCase'
$reCode   = New-Object regex '^CREATE\s+(?:OR\s+REPLACE\s+)?(VIEW|PROCEDURE|FUNCTION)\b', 'IgnoreCase'
function Strip([string]$s) { return [regex]::Replace($s, '^(\s*--[^\n]*\n)*\s*', '') }
$ok = 0; $skip = 0; $fail = 0
$retry = New-Object System.Collections.Generic.List[object]
for ($i = 0; $i -lt $stmts.Count; $i++) {
  $label = $stmts[$i][0]; $sql = $stmts[$i][1]; $head = Strip $sql
  $m = $reCreate.Match($head)
  # 不带引号的名称按大写存储
  $oname = if ($m.Groups[2].Success) { $m.Groups[2].Value } else { $m.Groups[3].Value.ToUpper() }
  if ($m.Success -and (Rows 'SELECT COUNT(*) FROM SYS.OBJECTS WHERE SCHEMA_NAME = CURRENT_SCHEMA AND OBJECT_NAME = ?' @($oname))[0][0] -gt 0) {
    $skip++; $log.Add("跳过`t$label`t已存在"); continue
  }
  try { Exec $sql; $ok++; $log.Add("成功`t$label") }
  catch {
    $e = $_.Exception.Message
    if ($reCode.IsMatch($head)) { $retry.Add(@($label, $sql, $e)) } else { $fail++; Out "失败`t$label`t$e" 'Red' }
  }
  if (($i + 1) % 50 -eq 0) { Write-Host ("  已执行 {0} / {1}" -f ($i + 1), $stmts.Count) }
}
while ($retry.Count -gt 0) {
  $next = New-Object System.Collections.Generic.List[object]
  foreach ($r in $retry) {
    try { Exec $r[1]; $ok++; $log.Add("成功（重试）`t$($r[0])") } catch { $next.Add(@($r[0], $r[1], $_.Exception.Message)) }
  }
  if ($next.Count -eq $retry.Count) { foreach ($r in $next) { $fail++; Out "失败`t$($r[0])`t$($r[2])" 'Red' }; break }
  $retry = $next
}

# ---------------- 结果 ----------------
$inv = Rows "SELECT 'PROCEDURE', PROCEDURE_NAME FROM SYS.PROCEDURES WHERE SCHEMA_NAME = CURRENT_SCHEMA AND IS_VALID <> 'TRUE' AND PROCEDURE_NAME LIKE 'MTC%' UNION ALL SELECT 'FUNCTION', FUNCTION_NAME FROM SYS.FUNCTIONS WHERE SCHEMA_NAME = CURRENT_SCHEMA AND IS_VALID <> 'TRUE' AND FUNCTION_NAME LIKE 'MTC%' UNION ALL SELECT 'VIEW', VIEW_NAME FROM SYS.VIEWS WHERE SCHEMA_NAME = CURRENT_SCHEMA AND IS_VALID <> 'TRUE' AND VIEW_NAME LIKE 'MTC%'"
foreach ($r in $inv) { Out "无效对象`t$($r[0])`t$($r[1])" 'Red' }
$color = if ($fail -or $inv.Count) { 'Red' } else { 'Green' }
Out ("完成：成功 {0}，跳过 {1}，失败 {2}" -f $ok, $skip, $fail) $color
$conn.Close()
$logFile = Join-Path $here ('部署日志_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.txt')
[IO.File]::WriteAllText($logFile, ($log -join "`r`n") + "`r`n", $utf8)
Write-Host "日志：$logFile"
if (-not $Yes) { Read-Host '按回车退出' }
if ($fail -or $inv.Count) { exit 1 } else { exit 0 }
