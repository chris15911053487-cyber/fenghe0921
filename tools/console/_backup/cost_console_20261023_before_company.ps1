<#
  FH100 成本执行台 · 本机服务（新框架 MTC_CA_*）

  作用：在本机 127.0.0.1 上打开执行台网页（tools\console\index.html），通过本机 HANA ODBC 驱动
        发起新框架计算、期初承接，查看运行步骤、校验、新旧比对、物料单价、订单成本和凭证。

  安全：
    1. 只执行 tools\console\actions.json 里登记的语句，不接受任意 SQL；参数先按格式校验，再以参数方式传入。
    2. 查询在只读事务中执行，结束后一律回滚。
    3. 写操作只有两个：成本计算（MTC_CA_P_RUN）和期初承接（MTC_CA_P_BOOTSTRAP），只写 MTC_CA_* 表；
       正式计算和期初承接要在网页上完整输入账套名确认，服务端再核对一次；同一时间只允许一个。
    4. 只监听 127.0.0.1，并拒绝来自其他网站的请求。密码只保存在本次运行的内存中。
    5. 与排查服务 cost_server.ps1 分开：那个服务保持只读，本服务才有写操作。

  用法：双击 tools\启动成本执行台.bat（如果驱动是 32 位，双击 启动成本执行台_32位.bat）
#>
param(
  [int]$Port = 8766,
  [string]$Schema = '',
  [int]$MaxRows = 2000,
  [int]$ExportMax = 200000   # 表格“导出全部”时的上限（用户 2026-10-23）
)

$ErrorActionPreference = 'Stop'
$here        = Split-Path -Parent $MyInvocation.MyCommand.Path
$pagePath    = Join-Path $here 'console\index.html'
$actionsPath = Join-Path $here 'console\actions.json'
$connFile    = Join-Path $here 'connection.txt'
$schemaFile  = Join-Path $here 'console_schema.txt'
$utf8        = New-Object System.Text.UTF8Encoding($false)
Add-Type -AssemblyName System.Data

function Info($m) { Write-Host $m -ForegroundColor Cyan }
function Warn($m) { Write-Host $m -ForegroundColor Yellow }
function Err($m)  { Write-Host $m -ForegroundColor Red }

foreach ($p in @($pagePath, $actionsPath)) {
  if (-not (Test-Path $p)) { Err "找不到文件：$p"; Read-Host '按回车退出'; exit 1 }
}

# ------------------------------------------------------------------
# 连接（与排查服务共用 connection.txt，不含账号密码）
# ------------------------------------------------------------------
$plat = if ([Environment]::Is64BitProcess) { '64-bit' } else { '32-bit' }

function Get-BaseConnString {
  if (Test-Path $connFile) {
    $saved = ([IO.File]::ReadAllText($connFile, $utf8)).Trim()
    if ($saved) {
      Info "使用已保存的连接：$saved"
      $use = Read-Host '直接使用？(回车=是，N=重新选择)'
      if ($use -notmatch '^[Nn]') { return $saved }
    }
  }
  $cs = $null
  $dsns = @()
  try { $dsns = @(Get-OdbcDsn -ErrorAction Stop | Where-Object { $_.DriverName -match 'HDB|HANA' }) } catch { }
  if ($dsns.Count -gt 0) {
    Write-Host ''
    Write-Host '本机找到以下 HANA ODBC 数据源：'
    for ($i = 0; $i -lt $dsns.Count; $i++) {
      $mark = if ($dsns[$i].Platform -eq $plat) { '' } else { '  ← 位数与当前程序不同，选它可能连不上' }
      Write-Host ("  [{0}] {1}   驱动 {2}，{3}{4}" -f ($i + 1), $dsns[$i].Name, $dsns[$i].DriverName, $dsns[$i].Platform, $mark)
    }
    Write-Host '  [M] 不用数据源，手工输入服务器地址'
    $c = Read-Host '请选择'
    if ($c -match '^\d+$' -and [int]$c -ge 1 -and [int]$c -le $dsns.Count) { $cs = 'DSN=' + $dsns[[int]$c - 1].Name }
  }
  if (-not $cs) {
    $node = Read-Host 'HANA 服务器地址和端口（例如 192.168.1.10:30015）'
    $db   = Read-Host '租户数据库名（没有可直接回车）'
    $drv  = if ([Environment]::Is64BitProcess) { 'HDBODBC' } else { 'HDBODBC32' }
    $cs   = "DRIVER={$drv};SERVERNODE=$node"
    if ($db) { $cs += ";DATABASENAME=$db" }
  }
  $save = Read-Host '保存这个连接（不含账号密码），下次直接使用？(Y/N)'
  if ($save -match '^[Yy]') { [IO.File]::WriteAllText($connFile, $cs, $utf8); Info "已保存到 $connFile" }
  return $cs
}

$baseCs = Get-BaseConnString
$user = Read-Host '数据库账号（数据源里已保存账号时可直接回车）'
$fullCs = $baseCs
if ($user) {
  $sec = Read-Host '密码' -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
  try { $plainPwd = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
  $fullCs = $baseCs + ';UID=' + $user + ';PWD={' + $plainPwd.Replace('}', '}}') + '}'
  $plainPwd = $null
}

$script:conn = $null
function Open-Conn {
  if ($script:conn -ne $null) { try { $script:conn.Dispose() } catch { } }
  $script:conn = New-Object System.Data.Odbc.OdbcConnection($fullCs)
  $script:conn.Open()
  if ($Schema) {
    $cmd = $script:conn.CreateCommand()
    $cmd.CommandText = 'SET SCHEMA "' + $Schema.Replace('"', '') + '"'
    [void]$cmd.ExecuteNonQuery()
  }
}
function Ensure-Conn {
  if ($script:conn -eq $null -or $script:conn.State -ne [System.Data.ConnectionState]::Open) { Open-Conn }
}
try { Open-Conn } catch {
  Err "连接失败：$($_.Exception.Message)"
  if ($_.Exception.Message -match 'IM002|IM014|architecture|未发现数据源|找不到') {
    Warn '提示：ODBC 驱动的位数要和程序一致。如果本机只装了 32 位 HANA Client，请改用 启动成本执行台_32位.bat。'
  }
  Read-Host '按回车退出'; exit 1
}

# ------------------------------------------------------------------
# JSON 与只读查询
# ------------------------------------------------------------------
function JStr([string]$s) {
  if ($s -eq $null) { return 'null' }
  $s = $s.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
  $s = [regex]::Replace($s, '[\x00-\x1F]', { param($m) '\u{0:x4}' -f [int][char]$m.Value })
  return '"' + $s + '"'
}
$inv = [Globalization.CultureInfo]::InvariantCulture
function JVal($v) {
  if ($v -eq $null -or [DBNull]::Value.Equals($v)) { return 'null' }
  if ($v -is [datetime]) { return (JStr ($v.ToString('yyyy-MM-dd HH:mm:ss', $inv) -replace ' 00:00:00$', '')) }
  if ($v -is [bool]) { if ($v) { return 'true' } else { return 'false' } }
  if ($v -is [decimal] -or $v -is [double] -or $v -is [single] -or $v -is [int] -or $v -is [long] -or $v -is [int16] -or $v -is [byte]) {
    if (($v -is [double] -or $v -is [single]) -and ([double]::IsNaN($v) -or [double]::IsInfinity($v))) { return 'null' }
    return [Convert]::ToString($v, $inv)
  }
  if ($v -is [byte[]]) { return (JStr ([BitConverter]::ToString($v))) }
  return (JStr ([string]$v))
}
function Read-Result($r, [int]$limit) {
  $cols = @(); for ($i = 0; $i -lt $r.FieldCount; $i++) { $cols += (JStr $r.GetName($i)) }
  $sb = New-Object System.Text.StringBuilder
  $n = 0; $trunc = $false
  while ($r.Read()) {
    if ($n -ge $limit) { $trunc = $true; break }
    if ($n -gt 0) { [void]$sb.Append(',') }
    [void]$sb.Append('[')
    for ($i = 0; $i -lt $r.FieldCount; $i++) { if ($i -gt 0) { [void]$sb.Append(',') }; [void]$sb.Append((JVal $r.GetValue($i))) }
    [void]$sb.Append(']')
    $n++
  }
  return '"columns":[' + ($cols -join ',') + '],"rows":[' + $sb.ToString() + '],"truncated":' + $(if ($trunc) { 'true' } else { 'false' })
}
function Invoke-ReadOnly([string]$sql, [object[]]$params, [int]$limit = $MaxRows) {
  Ensure-Conn
  $tx = $script:conn.BeginTransaction()
  try {
    $c0 = $script:conn.CreateCommand(); $c0.Transaction = $tx
    $c0.CommandText = 'SET TRANSACTION READ ONLY'
    try { [void]$c0.ExecuteNonQuery() } catch { }
    $cmd = $script:conn.CreateCommand(); $cmd.Transaction = $tx
    $cmd.CommandText = $sql; $cmd.CommandTimeout = 300
    foreach ($p in $params) {
      $op = $cmd.CreateParameter(); $op.OdbcType = [System.Data.Odbc.OdbcType]::NVarChar; $op.Value = [string]$p
      [void]$cmd.Parameters.Add($op)
    }
    $r = $cmd.ExecuteReader()
    try { return (Read-Result $r $limit) } finally { $r.Close() }
  } finally { try { $tx.Rollback() } catch { } }
}

# AI 面板（设计稿 8.3 A 档）：页面把“将要发给大模型的内容”交给本机服务，服务先原样写入本地审计日志再决定是否发出。
# 用户 2026-10-13 决定暂不接大模型：一律不发出，返回“大模型未配置”。以后接入时只在这里加发送，审计日志照写。
$aiConf   = Join-Path $here 'console\ai_config.json'
$auditDir = Join-Path $here 'console\audit'
$aiReason = '大模型未配置（设计稿 Q30：用户 2026-10-13 决定先不接入）'
function AI-Chat([string]$payloadJson) {
  if (-not (Test-Path $auditDir)) { [void](New-Item -ItemType Directory -Path $auditDir) }
  $fn = Join-Path $auditDir ((Get-Date).ToString('yyyy-MM-dd') + '.jsonl')
  $rec = '{"time":' + (JStr (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) + ',"osUser":' + (JStr $env:USERNAME) + ',"schema":' + (JStr $Schema) +
         ',"status":"blocked","reason":' + (JStr $aiReason) + ',"payload":' + $payloadJson + '}'
  [IO.File]::AppendAllText($fn, $rec + "`n", $utf8)
  return ('tools\console\audit\' + (Split-Path $fn -Leaf))
}

function Invoke-Write([string]$sql, [object[]]$params) {
  Ensure-Conn
  $tx = $script:conn.BeginTransaction()
  try {
    $c0 = $script:conn.CreateCommand(); $c0.Transaction = $tx
    $c0.CommandText = 'SET TRANSACTION READ WRITE'   # 查询时设成了只读，写之前改回来
    try { [void]$c0.ExecuteNonQuery() } catch { }
    $cmd = $script:conn.CreateCommand(); $cmd.Transaction = $tx
    $cmd.CommandText = $sql; $cmd.CommandTimeout = 60
    foreach ($p in $params) {
      $op = $cmd.CreateParameter(); $op.OdbcType = [System.Data.Odbc.OdbcType]::NVarChar; $op.Value = [string]$p
      [void]$cmd.Parameters.Add($op)
    }
    $r = $cmd.ExecuteReader()
    try { $res = Read-Result $r $MaxRows } finally { $r.Close() }
    $tx.Commit()
    return $res
  } catch { try { $tx.Rollback() } catch { }; throw }
}

# ------------------------------------------------------------------
# 白名单
# ------------------------------------------------------------------
function Get-Actions {
  $d = [IO.File]::ReadAllText($actionsPath, $utf8) | ConvertFrom-Json
  # sqlFile：语句放在单独的 .sql 文件里（取数 SQL，带分段注释，用户 2026-10-19）；resultSql 替换文件中“-- @result”之后的输出段
  foreach ($a in $d.actions.PSObject.Properties) {
    $spec = $a.Value
    if ($spec.PSObject.Properties['sqlFile'] -ne $null -and $spec.sqlFile) {
      $t = [IO.File]::ReadAllText((Join-Path (Split-Path $actionsPath) ([string]$spec.sqlFile)), $utf8)
      if ($spec.PSObject.Properties['resultSql'] -ne $null -and $spec.resultSql) { $t = $t.Substring(0, $t.IndexOf('-- @result')) + [string]$spec.resultSql }
      $spec | Add-Member -NotePropertyName sql -NotePropertyValue $t.Trim([char]0xFEFF, ' ', "`r", "`n", "`t") -Force
    }
  }
  return $d
}
function Bind-Args($spec, $validators, $argObj) {   # 不能叫 $args（PowerShell 自动变量）
  $vals = New-Object System.Collections.Generic.List[object]
  foreach ($p in @($spec.params)) {
    $v = ''
    if ($argObj -ne $null -and $argObj.PSObject.Properties[$p] -ne $null -and $argObj.$p -ne $null) { $v = [string]$argObj.$p }
    $re = [string]$validators.$p
    if (-not $re -or $v -notmatch $re) { throw "参数 $p 格式不对" }
    $vals.Add($v)
  }
  return ,$vals.ToArray()
}

# ------------------------------------------------------------------
# 选择 SCHEMA
# ------------------------------------------------------------------
function Q1([string]$sql, [object[]]$p = @()) {
  $cmd = $script:conn.CreateCommand(); $cmd.CommandText = $sql
  foreach ($v in $p) { $x = $cmd.CreateParameter(); $x.OdbcType = [System.Data.Odbc.OdbcType]::NVarChar; $x.Value = [string]$v; [void]$cmd.Parameters.Add($x) }
  $r = $cmd.ExecuteReader(); $res = New-Object System.Collections.Generic.List[object]
  try { while ($r.Read()) { $a = New-Object object[] $r.FieldCount; [void]$r.GetValues($a); $res.Add($a) } } finally { $r.Close() }
  return ,$res
}
function Select-Schema {
  $cands = @()
  try { $cands = @((Q1 "SELECT DISTINCT SCHEMA_NAME FROM SYS.PROCEDURES WHERE PROCEDURE_NAME = 'MTC_CA_P_RUN' ORDER BY SCHEMA_NAME") | ForEach-Object { [string]$_[0] }) } catch { }
  $saved = ''
  if (Test-Path $schemaFile) { $saved = ([IO.File]::ReadAllText($schemaFile, $utf8)).Trim() }
  Write-Host ''
  if ($cands.Count) {
    Write-Host '以下账套（SCHEMA）已部署新框架：'
    for ($i = 0; $i -lt $cands.Count; $i++) { Write-Host ("  [{0}] {1}" -f ($i + 1), $cands[$i]) }
  } else { Warn '没有找到已部署新框架（MTC_CA_P_RUN）的账套，请先用 部署包 部署。' }
  $def = if ($saved -and $cands -contains $saved) { $saved } elseif ($cands.Count -eq 1) { $cands[0] } else { '' }
  while ($true) {
    $prompt = if ($def) { "请输入要使用的账套（编号或名称，直接回车 = $def）" } else { '请输入要使用的账套（编号或名称）' }
    $in = (Read-Host $prompt).Trim()
    if (-not $in) { $sel = $def }
    elseif ($in -match '^\d+$' -and [int]$in -ge 1 -and [int]$in -le $cands.Count) { $sel = $cands[[int]$in - 1] }
    else { $sel = $in.Trim('"') }
    if (-not $sel) { continue }
    $hit = @($cands | Where-Object { $_.ToUpper() -eq $sel.ToUpper() })
    if ($hit.Count) { $sel = $hit[0]; break }
    Warn "账套 $sel 中没有新框架，请重新输入。"
  }
  [IO.File]::WriteAllText($schemaFile, $sel, $utf8)
  return $sel
}
if (-not $Schema) { $Schema = Select-Schema }
try { Open-Conn } catch { Err "切换到账套 $Schema 失败：$($_.Exception.Message)"; Read-Host '按回车退出'; exit 1 }

$connDesc = $baseCs
if ($baseCs -match 'DSN=([^;]+)') { $connDesc = 'ODBC 数据源 ' + $Matches[1] }
elseif ($baseCs -match 'SERVERNODE=([^;]+)') { $connDesc = $Matches[1]; if ($baseCs -match 'DATABASENAME=([^;]+)') { $connDesc += ' / ' + $Matches[1] } }

# ------------------------------------------------------------------
# 后台任务（计算、承接）：另开一个连接，在单独的 runspace 中执行，网页轮询进度
# ------------------------------------------------------------------
$script:job = @{ state = 'idle' }
$jobScript = {
  param([string]$cs, [string]$schema, [string]$sql, [object[]]$vals)
  Add-Type -AssemblyName System.Data
  $c = New-Object System.Data.Odbc.OdbcConnection($cs)
  $c.Open()
  try {
    $s = $c.CreateCommand(); $s.CommandText = 'SET SCHEMA "' + $schema.Replace('"', '') + '"'; [void]$s.ExecuteNonQuery()
    $cmd = $c.CreateCommand(); $cmd.CommandText = $sql; $cmd.CommandTimeout = 0
    foreach ($v in $vals) { $x = $cmd.CreateParameter(); $x.OdbcType = [System.Data.Odbc.OdbcType]::NVarChar; $x.Value = [string]$v; [void]$cmd.Parameters.Add($x) }
    $r = $cmd.ExecuteReader()
    $cols = @(); $rows = @()
    try {
      for ($i = 0; $i -lt $r.FieldCount; $i++) { $cols += $r.GetName($i) }
      while ($r.Read()) { $a = New-Object object[] $r.FieldCount; [void]$r.GetValues($a); $rows += ,$a }
    } finally { $r.Close() }
    return @{ cols = $cols; rows = $rows }
  } finally { $c.Dispose() }
}
function Start-Job2([string]$action, [string]$title, [string]$sql, [object[]]$vals) {
  $ps = [PowerShell]::Create()
  [void]$ps.AddScript($jobScript).AddArgument($fullCs).AddArgument($Schema).AddArgument($sql).AddArgument($vals)
  $script:job = @{ state = 'running'; action = $action; title = $title; start = Get-Date; seen = $false; ps = $ps; handle = $ps.BeginInvoke() }
}
function Update-Job {
  $j = $script:job
  if ($j.state -ne 'running' -or -not $j.handle.IsCompleted) { return }
  try {
    $out = $j.ps.EndInvoke($j.handle)
    if ($j.ps.Streams.Error.Count -gt 0) { throw $j.ps.Streams.Error[0].Exception }
    $res = $out | Select-Object -Last 1
    $cols = @($res.cols | ForEach-Object { JStr $_ })
    $rows = @($res.rows | ForEach-Object { '[' + ((@($_) | ForEach-Object { JVal $_ }) -join ',') + ']' })
    $j.result = '{"columns":[' + ($cols -join ',') + '],"rows":[' + ($rows -join ',') + ']}'
    $j.state = 'done'
  } catch {
    $e = $_.Exception; while ($e.InnerException) { $e = $e.InnerException }
    $j.error = $e.Message; $j.state = 'error'
  } finally {
    $j.end = Get-Date
    try { $j.ps.Dispose() } catch { }
    $j.ps = $null; $j.handle = $null
  }
  Write-Host ("{0:HH:mm:ss}  {1} 结束：{2}" -f (Get-Date), $j.title, $j.state)
}
function Job-Json {
  Update-Job
  $j = $script:job
  if ($j.state -eq 'idle') { return '{"ok":true,"state":"idle"}' }
  $end = if ($j.end) { $j.end } else { Get-Date }
  $s = '{"ok":true,"state":' + (JStr $j.state) + ',"action":' + (JStr $j.action) + ',"title":' + (JStr $j.title) +
       ',"elapsed":' + [int]($end - $j.start).TotalSeconds + ',"seen":' + $(if ($j.seen) { 'true' } else { 'false' })
  if ($j.result) { $s += ',"result":' + $j.result }
  if ($j.error) { $s += ',"error":' + (JStr $j.error) }
  return $s + '}'
}

# ------------------------------------------------------------------
# HTTP（只监听 127.0.0.1）
# ------------------------------------------------------------------
function Send-Resp($stream, [int]$code, [string]$ctype, [byte[]]$body) {
  $txt = @{ 200 = 'OK'; 400 = 'Bad Request'; 403 = 'Forbidden'; 404 = 'Not Found' }[$code]
  $h = "HTTP/1.1 $code $txt`r`nContent-Type: $ctype`r`nContent-Length: $($body.Length)`r`nCache-Control: no-store`r`nX-Content-Type-Options: nosniff`r`nConnection: close`r`n`r`n"
  $hb = [Text.Encoding]::ASCII.GetBytes($h)
  $stream.Write($hb, 0, $hb.Length)
  if ($body.Length -gt 0) { $stream.Write($body, 0, $body.Length) }
  $stream.Flush()
}
function Send-Json($stream, [string]$json) { Send-Resp $stream 200 'application/json; charset=utf-8' ($utf8.GetBytes($json)) }
function Json-Error([string]$msg) { return '{"ok":false,"error":' + (JStr $msg) + '}' }

function Handle-Client($client) {
  $stream = $client.GetStream()
  $stream.ReadTimeout = 15000
  $buf = New-Object byte[] 65536
  $ms = New-Object IO.MemoryStream
  $headEnd = -1
  while ($headEnd -lt 0) {
    $n = $stream.Read($buf, 0, $buf.Length)
    if ($n -le 0) { return }
    $ms.Write($buf, 0, $n)
    if ($ms.Length -gt 1048576) { return }
    $headEnd = [Text.Encoding]::ASCII.GetString($ms.ToArray()).IndexOf("`r`n`r`n")
  }
  $all = $ms.ToArray()
  $hl = ([Text.Encoding]::ASCII.GetString($all, 0, $headEnd)) -split "`r`n"
  $parts = $hl[0] -split ' '
  if ($parts.Count -lt 2) { return }
  $method = $parts[0]; $path = ($parts[1] -split '\?')[0]
  $hdr = @{}
  if ($hl.Count -gt 1) { foreach ($l in $hl[1..($hl.Count - 1)]) { $i = $l.IndexOf(':'); if ($i -gt 0) { $hdr[$l.Substring(0, $i).Trim().ToLower()] = $l.Substring($i + 1).Trim() } } }
  $len = 0; if ($hdr.ContainsKey('content-length')) { $len = [int]$hdr['content-length'] }
  if ($len -gt 1048576) { Send-Resp $stream 400 'text/plain' ([byte[]]@()); return }
  $bodyStart = $headEnd + 4
  $body = New-Object IO.MemoryStream
  if ($all.Length -gt $bodyStart) { $body.Write($all, $bodyStart, $all.Length - $bodyStart) }
  while ($body.Length -lt $len) { $n = $stream.Read($buf, 0, $buf.Length); if ($n -le 0) { break }; $body.Write($buf, 0, $n) }
  $bodyText = $utf8.GetString($body.ToArray())

  # 只接受本机地址访问，防止其他网站借道调用
  $hostH = $hdr['host']
  if ($hostH -ne "127.0.0.1:$Port" -and $hostH -ne "localhost:$Port") { Send-Resp $stream 403 'text/plain' ($utf8.GetBytes('forbidden')); return }
  if ($path -like '/api/*' -and $hdr['x-requested-with'] -ne 'cost-console') { Send-Resp $stream 403 'text/plain' ($utf8.GetBytes('forbidden')); return }

  if ($method -eq 'GET' -and ($path -eq '/' -or $path -eq '/index.html')) {
    Send-Resp $stream 200 'text/html; charset=utf-8' ([IO.File]::ReadAllBytes($pagePath)); return
  }
  # 页面的样式和脚本（2026-10-23 拆分）：只认 console\css\*.css、console\js\*.js，文件名只能是小写字母、数字、下划线
  if ($method -eq 'GET' -and $path -cmatch '^/(css|js)/([a-z0-9_]+)\.(css|js)$' -and $Matches[1] -eq $Matches[3]) {
    $ext = $Matches[3]
    $f = Join-Path (Join-Path (Split-Path $pagePath) $Matches[1]) ($Matches[2] + '.' + $ext)
    if (Test-Path -LiteralPath $f -PathType Leaf) {
      Send-Resp $stream 200 $(if ($ext -eq 'css') { 'text/css; charset=utf-8' } else { 'text/javascript; charset=utf-8' }) ([IO.File]::ReadAllBytes($f)); return
    }
  }
  try {
    if ($method -eq 'GET' -and $path -eq '/api/info') {
      $d = Get-Actions
      Ensure-Conn
      $rs = Q1 ([string]$d.actions.ping.sql)
      $r = $rs[0]
      Send-Json $stream ('{"ok":true,"conn":' + (JStr $connDesc) + ',"user":' + (JStr ([string]$r[0])) + ',"schema":' + (JStr ([string]$r[1])) +
        ',"hasNew":' + $(if ([int]$r[3] -gt 0) { 'true' } else { 'false' }) + ',"osUser":' + (JStr $env:USERNAME) + '}')
      return
    }
    if ($method -eq 'GET' -and $path -eq '/api/job') { Send-Json $stream (Job-Json); return }
    if ($method -eq 'GET' -and $path -eq '/api/ai/status') {
      $prov = $null; if (Test-Path $aiConf) { try { $prov = ([IO.File]::ReadAllText($aiConf, $utf8) | ConvertFrom-Json).provider } catch { } }
      Send-Json $stream ('{"ok":true,"configured":false,"provider":' + $(if ($prov) { JStr ([string]$prov) } else { 'null' }) + ',"reason":' + (JStr $aiReason) + '}'); return
    }
    if ($method -eq 'POST' -and $path -eq '/api/ai/chat') {
      $req = $bodyText | ConvertFrom-Json
      if ($req.payload -eq $null) { throw '请求格式不对' }
      # 原样记录页面提交的 payload 文本（不经 PowerShell 重新序列化）
      $i = $bodyText.IndexOf('"payload"'); $pj = $bodyText.Substring($bodyText.IndexOf(':', $i) + 1).Trim()
      if ($pj.EndsWith('}')) { $pj = $pj.Substring(0, $pj.Length - 1) }
      $fn = AI-Chat $pj
      Send-Json $stream ('{"ok":false,"blocked":true,"audit":' + (JStr $fn) + ',"error":' + (JStr ($aiReason + '；本次内容没有发出，已记入本机审计日志 ' + $fn)) + '}'); return
    }
    if ($method -eq 'POST' -and $path -eq '/api/sql') {
      # 页面“SQL”按钮：返回只读查询（kind=query）登记的语句和参数名，不执行（用户 2026-10-18）
      $req = $bodyText | ConvertFrom-Json
      $d = Get-Actions
      $spec = $d.actions.PSObject.Properties[[string]$req.action]
      if ($spec -eq $null -or $spec.Value.kind -ne 'query') { throw '不允许的查询' }
      $spec = $spec.Value
      $ps = @($spec.params | ForEach-Object { JStr ([string]$_) }) -join ','
      Send-Json $stream ('{"ok":true,"action":' + (JStr ([string]$req.action)) + ',"title":' + (JStr ([string]$spec.title)) + ',"sql":' + (JStr ([string]$spec.sql)) + ',"params":[' + $ps + ']}')
      return
    }
    if ($method -eq 'POST' -and $path -eq '/api/job/ack') { $script:job.seen = $true; Send-Json $stream '{"ok":true}'; return }
    if ($method -eq 'POST' -and $path -eq '/api/exec') {
      # 同步的小写操作（kind=exec，维护模拟场景）：普通事务，成功提交、失败回滚
      $req = $bodyText | ConvertFrom-Json
      $d = Get-Actions
      $spec = $d.actions.PSObject.Properties[[string]$req.action]
      if ($spec -eq $null -or $spec.Value.kind -ne 'exec') { throw '不允许的操作' }
      $spec = $spec.Value
      $vals = Bind-Args $spec $d.validators $req.args
      Send-Json $stream ('{"ok":true,' + (Invoke-Write ([string]$spec.sql) $vals) + '}')
      Write-Host ("{0:HH:mm:ss}  {1}" -f (Get-Date), [string]$req.action)
      return
    }
    if ($method -eq 'POST' -and ($path -eq '/api/q' -or $path -eq '/api/call')) {
      $req = $bodyText | ConvertFrom-Json
      $d = Get-Actions
      $name = [string]$req.action
      $spec = $d.actions.PSObject.Properties[$name]
      if ($spec -eq $null) { throw '不允许的操作' }
      $spec = $spec.Value
      if ($path -eq '/api/q') {
        if ($spec.kind -ne 'query') { throw '不允许的查询' }
        $vals = Bind-Args $spec $d.validators $req.args
        $lim = $(if ($req.all -eq $true) { $ExportMax } else { $MaxRows })   # all：表格“导出全部”，不受页面 2000 行限制
        Send-Json $stream ('{"ok":true,' + (Invoke-ReadOnly ([string]$spec.sql) $vals $lim) + '}')
        return
      }
      if ($spec.kind -ne 'call') { throw '不允许的操作' }
      $a = $req.args
      $cf = [string]$spec.confirm
      $needConfirm = ($cf -eq 'always') -or ($cf -eq 'runTypeF' -and $a -ne $null -and [string]$a.runType -eq 'F')
      if ($needConfirm -and ([string]$a.confirm).Trim().ToUpper() -ne $Schema.ToUpper()) { throw '确认的账套名与当前账套不一致' }
      $vals = Bind-Args $spec $d.validators $a
      Update-Job
      if ($script:job.state -eq 'running') { throw '已有操作在运行，请等它结束' }
      Write-Host ("{0:HH:mm:ss}  开始 {1}（{2}）" -f (Get-Date), $spec.title, ($vals -join ', '))
      Start-Job2 $name ([string]$spec.title) ([string]$spec.sql) $vals
      Send-Json $stream '{"ok":true}'
      return
    }
  } catch {
    Send-Json $stream (Json-Error $_.Exception.Message); return
  }
  Send-Resp $stream 404 'text/plain' ($utf8.GetBytes('not found'))
}

$listener = $null
for ($try = 0; $try -lt 10; $try++) {
  try {
    $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $Port)
    $listener.Start(); break
  } catch { $listener = $null; $Port++ }
}
if ($listener -eq $null) { Err '找不到可用端口。'; Read-Host '按回车退出'; exit 1 }

$who = ''
try { $who = [string](Q1 'SELECT CURRENT_USER FROM DUMMY')[0][0] } catch { }
$url = "http://127.0.0.1:$Port/"
Write-Host ''
Info "已连接 HANA：$connDesc，账号 $who，账套 $Schema"
Info "执行台地址：$url"
Info '保持这个窗口打开；计算进行中关闭窗口会中断计算。'
Write-Host ''
Start-Process $url

try {
  while ($true) {
    if (-not $listener.Pending()) { Start-Sleep -Milliseconds 100; Update-Job; continue }
    $client = $listener.AcceptTcpClient()
    try { Handle-Client $client } catch { Err "请求处理出错：$($_.Exception.Message)" } finally { $client.Close() }
  }
} finally {
  $listener.Stop()
  if ($script:conn -ne $null) { $script:conn.Dispose() }
}
