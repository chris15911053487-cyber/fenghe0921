<#
  FH100 成本核算排查 · 本机查询服务

  作用：在本机 127.0.0.1 上打开一个小网页服务，让《FH100成本核算关系图.html》
        可以通过本机的 HANA ODBC 驱动，直接运行 checks\MTC_COST_CHECKS.sql 里的校验。

  安全：
    1. 只执行 checks\MTC_COST_CHECKS.sql 中预先写好的查询，不接受任意 SQL。
    2. 执行前检查语句只能以 SELECT / WITH 开头，且不含写操作关键字。
    3. 每次查询都在只读事务中执行，结束后一律回滚。
    4. 账期、物料编码、订单号先校验格式，再以参数方式传入。
    5. 只监听 127.0.0.1，并拒绝来自其他网站的请求。
    密码只保存在本次运行的内存中，不写入任何文件。

  用法：双击 tools\启动成本核算排查.bat（如果驱动是 32 位，双击 启动成本核算排查_32位.bat）
#>
param(
  [int]$Port = 8765,
  [string]$Schema = '',
  [int]$MaxRows = 2000
)

$ErrorActionPreference = 'Stop'
$here      = Split-Path -Parent $MyInvocation.MyCommand.Path
$root      = Split-Path -Parent $here
$pagePath  = Join-Path $root 'FH100成本核算关系图.html'
$checksPath= Join-Path $root 'checks\MTC_COST_CHECKS.sql'
$connFile  = Join-Path $here 'connection.txt'
$schemaFile= Join-Path $here 'schema.txt'
$utf8      = New-Object System.Text.UTF8Encoding($false)
Add-Type -AssemblyName System.Data

function Info($m) { Write-Host $m -ForegroundColor Cyan }
function Warn($m) { Write-Host $m -ForegroundColor Yellow }
function Err($m)  { Write-Host $m -ForegroundColor Red }

foreach ($p in @($pagePath, $checksPath)) {
  if (-not (Test-Path $p)) { Err "找不到文件：$p"; Read-Host '按回车退出'; exit 1 }
}

# ------------------------------------------------------------------
# 连接
# ------------------------------------------------------------------
$is64 = [Environment]::Is64BitProcess
$plat = if ($is64) { '64-bit' } else { '32-bit' }

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
    if ($c -match '^\d+$' -and [int]$c -ge 1 -and [int]$c -le $dsns.Count) {
      $cs = 'DSN=' + $dsns[[int]$c - 1].Name
    }
  } else {
    Warn "没有找到 $plat 的 HANA ODBC 数据源，改为手工输入服务器地址。"
  }
  if (-not $cs) {
    $node = Read-Host 'HANA 服务器地址和端口（例如 192.168.1.10:30015）'
    $db   = Read-Host '租户数据库名（没有可直接回车）'
    $drv  = if ($is64) { 'HDBODBC' } else { 'HDBODBC32' }
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
    Warn '提示：ODBC 驱动的位数要和程序一致。如果本机只装了 32 位 HANA Client，请改用 启动成本核算排查_32位.bat。'
  }
  Read-Host '按回车退出'; exit 1
}

# ------------------------------------------------------------------
# 只读执行
# ------------------------------------------------------------------
$forbidden = '\b(INSERT|UPDATE|DELETE|MERGE|UPSERT|CREATE|DROP|ALTER|TRUNCATE|GRANT|REVOKE|CALL|EXEC|EXECUTE|COMMIT|LOAD|IMPORT|EXPORT|RENAME|LOCK)\b'
function Test-ReadOnlySql([string]$sql) {
  $s = [regex]::Replace($sql, '/\*[\s\S]*?\*/', ' ')
  $s = [regex]::Replace($s, '--[^\r\n]*', ' ')
  $s = [regex]::Replace($s, "'(?:[^']|'')*'", "''")
  $s = [regex]::Replace($s, '"[^"]*"', '""')
  if ($s -notmatch '^\s*(WITH|SELECT)\b') { return $false }
  if ($s -match $forbidden) { return $false }
  if ($s.Contains(';')) { return $false }
  return $true
}

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

function Invoke-ReadOnly([string]$sql, [object[]]$params, [int]$limit) {
  if (-not (Test-ReadOnlySql $sql)) { throw '这条语句不是只读查询，已拒绝执行。' }
  Ensure-Conn
  $tx = $script:conn.BeginTransaction()
  try {
    $c0 = $script:conn.CreateCommand(); $c0.Transaction = $tx
    $c0.CommandText = 'SET TRANSACTION READ ONLY'
    try { [void]$c0.ExecuteNonQuery() } catch { }
    $cmd = $script:conn.CreateCommand(); $cmd.Transaction = $tx
    $cmd.CommandText = $sql
    $cmd.CommandTimeout = 900
    foreach ($p in $params) {
      $op = $cmd.CreateParameter()
      $op.OdbcType = [System.Data.Odbc.OdbcType]::NVarChar
      $op.Value = [string]$p
      [void]$cmd.Parameters.Add($op)
    }
    $r = $cmd.ExecuteReader()
    try {
      $cols = @(); for ($i = 0; $i -lt $r.FieldCount; $i++) { $cols += (JStr $r.GetName($i)) }
      $sb = New-Object System.Text.StringBuilder
      $n = 0; $trunc = $false
      while ($r.Read()) {
        if ($n -ge $limit) { $trunc = $true; break }
        if ($n -gt 0) { [void]$sb.Append(',') }
        [void]$sb.Append('[')
        for ($i = 0; $i -lt $r.FieldCount; $i++) {
          if ($i -gt 0) { [void]$sb.Append(',') }
          [void]$sb.Append((JVal $r.GetValue($i)))
        }
        [void]$sb.Append(']')
        $n++
      }
    } finally { $r.Close() }
    return @{ columns = ($cols -join ','); rows = $sb.ToString(); count = $n; truncated = $trunc }
  } finally {
    try { $tx.Rollback() } catch { }
  }
}

# ------------------------------------------------------------------
# 校验 SQL
# ------------------------------------------------------------------
function Get-Checks {
  $lines = ([IO.File]::ReadAllText($checksPath, $utf8)) -split "`r?`n"
  $list = @{}; $cur = $null; $mode = ''
  foreach ($ln in $lines) {
    if ($ln -match '^-- @check (\S+) \| (.+)$') {
      $cur = @{ id = $Matches[1]; title = $Matches[2].Trim(); body = New-Object System.Collections.Generic.List[string] }
      $list[$cur.id] = $cur; $mode = 'head'; continue
    }
    if ($cur -eq $null) { continue }
    if ($mode -eq 'head') {
      if ($ln -match '^-- @\w+' -or $ln.StartsWith('--      ')) { continue }
      $mode = 'body'
    }
    $cur.body.Add($ln)
  }
  foreach ($k in @($list.Keys)) {
    $sql = ($list[$k].body -join "`n")
    $sql = [regex]::Replace($sql, '/\*[\s\S]*?\*/', '')
    $list[$k].sql = $sql.Trim().TrimEnd(';').Trim()
  }
  return $list
}

function Bind-Params([string]$sql, [string]$fc, [string]$item, [string]$wn) {
  $params = New-Object System.Collections.Generic.List[object]
  $pat = "'2026-08' AS ""FC""|'<物料编码>' AS ""ITEM""|'<订单号 WorNum>' AS ""WN"""
  foreach ($m in [regex]::Matches($sql, $pat)) {
    if ($m.Value.EndsWith('"FC"')) { $params.Add($fc) }
    elseif ($m.Value.EndsWith('"ITEM"')) { $params.Add($item) }
    else { $params.Add($wn) }
  }
  $sql = $sql.Replace("'2026-08' AS ""FC""", 'CAST(? AS NVARCHAR(10)) AS "FC"')
  $sql = $sql.Replace("'<物料编码>' AS ""ITEM""", 'CAST(? AS NVARCHAR(100)) AS "ITEM"')
  $sql = $sql.Replace("'<订单号 WorNum>' AS ""WN""", 'CAST(? AS NVARCHAR(50)) AS "WN"')
  return @{ sql = $sql; params = $params.ToArray() }
}

# ------------------------------------------------------------------
# 从数据库同步对象定义（只读：只查询 SYS 系统视图）
# ------------------------------------------------------------------
$syncRoot = Join-Path $root '0921-数据库同步'
$kindDirs = [ordered]@{ proc = '存储过程'; func = '表函数'; view = '视图'; table = '表结构'; data = '配置数据' }
$configTables = @('@MTC_COST_IOTYPE', '@U_CIOTRN', '@MTC_MRVTYPE', '@MTC_SALORDTYPE', 'OTRC')
# 按定义中的关键字补充对象（过程和触发器），用来找名称不以 MTC_ 开头、但写成本相关数据的代码，例如生成 ProWW 重估单的过程
$syncKeywords = @('ProWW', 'MTC_OMRV')
# B1 主数据：写到 主数据\ 文件夹，供分析使用，不进网页（OITM 可能很大）
$masterDir = '主数据'
$masterTables = [ordered]@{
  'OACT' = '科目表'; 'OITB' = '物料组'; 'OGAR' = '物料组科目确定'; 'OWHS' = '仓库'; 'OPRC' = '成本中心'
  'OITM' = '物料主数据'
}
$oitmCols = @('ItemCode', 'ItemName', 'FrgnName', 'ItmsGrpCod', 'ItemType', 'InvntItem', 'SellItem', 'PrchseItem',
  'EvalSystem', 'GLMethod', 'ByWh', 'MngMethod', 'PrcrmntMtd', 'InvntryUom', 'BuyUnitMsr', 'SalUnitMsr', 'DfltWH',
  'validFor', 'frozenFor', 'CreateDate', 'UpdateDate')

function Get-Rows([string]$sql, [object[]]$params, [int]$limit = 200000) {
  if (-not (Test-ReadOnlySql $sql)) { throw '这条语句不是只读查询，已拒绝执行。' }
  Ensure-Conn
  $tx = $script:conn.BeginTransaction()
  try {
    $c0 = $script:conn.CreateCommand(); $c0.Transaction = $tx
    $c0.CommandText = 'SET TRANSACTION READ ONLY'
    try { [void]$c0.ExecuteNonQuery() } catch { }
    $cmd = $script:conn.CreateCommand(); $cmd.Transaction = $tx
    $cmd.CommandText = $sql; $cmd.CommandTimeout = 900
    foreach ($p in $params) {
      $op = $cmd.CreateParameter(); $op.OdbcType = [System.Data.Odbc.OdbcType]::NVarChar; $op.Value = [string]$p
      [void]$cmd.Parameters.Add($op)
    }
    $r = $cmd.ExecuteReader()
    $cols = @(); for ($i = 0; $i -lt $r.FieldCount; $i++) { $cols += $r.GetName($i) }
    $rows = New-Object System.Collections.Generic.List[object]
    try {
      while ($rows.Count -lt $limit -and $r.Read()) {
        $vals = New-Object object[] $r.FieldCount
        [void]$r.GetValues($vals)
        for ($i = 0; $i -lt $vals.Length; $i++) { if ([DBNull]::Value.Equals($vals[$i])) { $vals[$i] = $null } }
        $rows.Add($vals)
      }
    } finally { $r.Close() }
    return @{ cols = $cols; rows = $rows }
  } finally { try { $tx.Rollback() } catch { } }
}

function Norm-Text([string]$t) {
  if ($t -eq $null) { return '' }
  $lines = ($t -replace "`r`n", "`n") -split "`n" | ForEach-Object { ($_ -replace '\s+', ' ').Trim() } | Where-Object { $_ -ne '' }
  return (($lines -join "`n").Trim().TrimEnd(';').Trim())
}
function Col-Signature([string]$ddl) {
  $ms = [regex]::Matches($ddl, '"([^"]+)"\s+([A-Z]+(?:\(\d+(?:,\s*\d+)?\))?)')
  return (($ms | ForEach-Object { $_.Groups[1].Value + ' ' + ($_.Groups[2].Value -replace '\s', '') }) -join '|')
}
function Find-Baseline([string]$kind, [string]$name) {
  $cands = @()
  if ($kind -eq 'table') { $cands += (Join-Path $root "0921-表\index\FH100\MT\$name\create.sql") }
  else { $cands += (Join-Path $root "0921-存储过程\export\FH100\MT\$name\create.sql") }
  $cands += (Join-Path $root "0921-补充对象\$name.sql")
  foreach ($c in $cands) { if (Test-Path $c) { return [IO.File]::ReadAllText($c, $utf8) } }
  return $null
}
function Safe-Name([string]$n) { return ($n -replace '[\\/:*?"<>|]', '_') }
function Fmt-Type($typ, $len, $scale) {
  if ($typ -match '^(N?VARCHAR|N?CHAR|ALPHANUM|VARBINARY|BINARY|SHORTTEXT)$' -and $len -ne $null) { return "$typ($len)" }
  if ($typ -eq 'DECIMAL' -and $len -ne $null -and $scale -ne $null) { return "$typ($len,$scale)" }
  return $typ
}

function Invoke-Sync {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $S = $Schema
  Info "开始同步 $S 中的成本相关对象..."
  # 1. 起点：成本模块的过程、函数、表
  $objs = [ordered]@{}
  function Add-Obj($name, $type, $via) { if (-not $objs.Contains($name)) { $objs[$name] = @{ type = $type; via = $via } } }
  (Get-Rows 'SELECT PROCEDURE_NAME FROM SYS.PROCEDURES WHERE SCHEMA_NAME = ? AND (PROCEDURE_NAME LIKE ''MTC\_COST%'' ESCAPE ''\'' OR PROCEDURE_NAME LIKE ''MTC\_CO\_%'' ESCAPE ''\'' OR PROCEDURE_NAME LIKE ''MTC\_PRT\_CO%'' ESCAPE ''\'' OR PROCEDURE_NAME LIKE ''MTC\_RPT\_CO%'' ESCAPE ''\'')' @($S)).rows | ForEach-Object { Add-Obj $_[0] 'PROCEDURE' '起点' }
  (Get-Rows 'SELECT FUNCTION_NAME FROM SYS.FUNCTIONS WHERE SCHEMA_NAME = ? AND (FUNCTION_NAME LIKE ''MTC\_COST%'' ESCAPE ''\'' OR FUNCTION_NAME LIKE ''MTC\_CO\_%'' ESCAPE ''\'')' @($S)).rows | ForEach-Object { Add-Obj $_[0] 'FUNCTION' '起点' }
  (Get-Rows 'SELECT TABLE_NAME FROM SYS.TABLES WHERE SCHEMA_NAME = ? AND (TABLE_NAME LIKE ''MTC\_COST%'' ESCAPE ''\'' OR TABLE_NAME = ''U_COILV'')' @($S)).rows | ForEach-Object { Add-Obj $_[0] 'TABLE' '起点' }
  foreach ($kw in $syncKeywords) {
    try { (Get-Rows 'SELECT PROCEDURE_NAME FROM SYS.PROCEDURES WHERE SCHEMA_NAME = ? AND DEFINITION LIKE ?' @($S, "%$kw%")).rows | ForEach-Object { Add-Obj $_[0] 'PROCEDURE' "关键字 $kw" } }
    catch { Warn "  按关键字 $kw 查找过程失败：$($_.Exception.Message)" }
    try { (Get-Rows 'SELECT TRIGGER_NAME FROM SYS.TRIGGERS WHERE SCHEMA_NAME = ? AND DEFINITION LIKE ?' @($S, "%$kw%")).rows | ForEach-Object { Add-Obj $_[0] 'TRIGGER' "关键字 $kw" } }
    catch { Warn "  按关键字 $kw 查找触发器失败：$($_.Exception.Message)" }
  }
  # 2. 沿依赖关系补齐
  $deps = (Get-Rows 'SELECT DEPENDENT_OBJECT_NAME, BASE_SCHEMA_NAME, BASE_OBJECT_NAME, BASE_OBJECT_TYPE FROM SYS.OBJECT_DEPENDENCIES WHERE DEPENDENT_SCHEMA_NAME = ?' @($S)).rows
  $byDep = @{}
  foreach ($d in $deps) { if (-not $byDep.ContainsKey($d[0])) { $byDep[$d[0]] = New-Object System.Collections.Generic.List[object] }; $byDep[$d[0]].Add($d) }
  $edges = New-Object System.Collections.Generic.List[string]
  $queue = New-Object System.Collections.Generic.Queue[string]
  foreach ($k in @($objs.Keys)) { $queue.Enqueue($k) }
  while ($queue.Count -gt 0) {
    $cur = $queue.Dequeue()
    if (-not $byDep.ContainsKey($cur)) { continue }
    foreach ($d in $byDep[$cur]) {
      if ($d[1] -ne $S -or $d[3] -notin @('PROCEDURE', 'FUNCTION', 'VIEW', 'TABLE')) { continue }
      $edges.Add(($cur, $d[2], $d[3]) -join "`t")
      if (-not $objs.Contains($d[2])) { Add-Obj $d[2] $d[3] $cur; $queue.Enqueue($d[2]) }
    }
  }
  # 3. 取定义并写文件
  if (Test-Path $syncRoot) { Remove-Item -LiteralPath $syncRoot -Recurse -Force }
  foreach ($d in $kindDirs.Values) { [void](New-Item -ItemType Directory -Path (Join-Path $syncRoot $d) -Force) }
  $manifest = New-Object System.Collections.Generic.List[string]
  $manifest.Add("类型`t名称`t来源`t行数`t与导出包/对话版本比较（忽略缩进和空行）")
  $cnt = @{ proc = 0; func = 0; view = 0; table = 0; data = 0 }
  $differ = New-Object System.Collections.Generic.List[string]
  $newOnly = New-Object System.Collections.Generic.List[string]
  $noDef = New-Object System.Collections.Generic.List[string]
  $b1 = New-Object System.Collections.Generic.List[string]
  foreach ($name in @($objs.Keys)) {
    $o = $objs[$name]; $text = $null; $kind = $null
    if ($o.type -eq 'TABLE' -and $name -notmatch '^(MTC|@|U_)') { $b1.Add($name); continue }
    try {
      switch ($o.type) {
        'PROCEDURE' { $kind = 'proc'; $rs = (Get-Rows 'SELECT DEFINITION FROM SYS.PROCEDURES WHERE SCHEMA_NAME = ? AND PROCEDURE_NAME = ?' @($S, $name)).rows; if ($rs.Count) { $text = [string]$rs[0][0] } }
        'FUNCTION'  { $kind = 'func'; $rs = (Get-Rows 'SELECT DEFINITION FROM SYS.FUNCTIONS WHERE SCHEMA_NAME = ? AND FUNCTION_NAME = ?' @($S, $name)).rows; if ($rs.Count) { $text = [string]$rs[0][0] } }
        'TRIGGER'   { $kind = 'proc'; $rs = (Get-Rows 'SELECT DEFINITION FROM SYS.TRIGGERS WHERE SCHEMA_NAME = ? AND TRIGGER_NAME = ?' @($S, $name)).rows; if ($rs.Count) { $text = [string]$rs[0][0] } }
        'VIEW'      { $kind = 'view'; $rs = (Get-Rows 'SELECT DEFINITION FROM SYS.VIEWS WHERE SCHEMA_NAME = ? AND VIEW_NAME = ?' @($S, $name)).rows
          # DEFINITION 不含列名清单；没有别名的列（如 TO_CHAR(x)、常量）要靠列名清单才能重建出原列名
          $vc = @((Get-Rows 'SELECT COLUMN_NAME FROM SYS.VIEW_COLUMNS WHERE SCHEMA_NAME = ? AND VIEW_NAME = ? ORDER BY POSITION' @($S, $name)).rows | ForEach-Object { '"' + ([string]$_[0] -replace '"', '""') + '"' })
          if ($rs.Count -and $rs[0][0]) { $text = "CREATE VIEW `"$S`".`"$name`" (" + ($vc -join ', ') + ") AS " + [string]$rs[0][0] } }
        'TABLE' {
          $kind = 'table'
          $cols = (Get-Rows 'SELECT COLUMN_NAME, DATA_TYPE_NAME, LENGTH, SCALE, IS_NULLABLE, DEFAULT_VALUE FROM SYS.TABLE_COLUMNS WHERE SCHEMA_NAME = ? AND TABLE_NAME = ? ORDER BY POSITION' @($S, $name)).rows
          $pk = @((Get-Rows 'SELECT COLUMN_NAME FROM SYS.CONSTRAINTS WHERE SCHEMA_NAME = ? AND TABLE_NAME = ? AND IS_PRIMARY_KEY = ''TRUE'' ORDER BY POSITION' @($S, $name)).rows | ForEach-Object { '"' + $_[0] + '"' })
          $tt = (Get-Rows 'SELECT TABLE_TYPE FROM SYS.TABLES WHERE SCHEMA_NAME = ? AND TABLE_NAME = ?' @($S, $name)).rows
          $lines = @($cols | ForEach-Object {
            $l = '"' + $_[0] + '" ' + (Fmt-Type $_[1] $_[2] $_[3])
            if ($_[5] -ne $null) {
              # 字符型默认值在 DEFAULT_VALUE 中不带引号，要补上
              $dv = [string]$_[5]
              if ($_[1] -match 'CHAR|ALPHANUM|SHORTTEXT' -and $dv -notmatch "^'") { $dv = "'" + ($dv -replace "'", "''") + "'" }
              $l += " DEFAULT $dv" }
            if ($_[4] -eq 'FALSE') { $l += ' NOT NULL' }
            $l })
          if ($pk.Count) { $lines += ('PRIMARY KEY (' + ($pk -join ', ') + ')') }
          $ttxt = if ($tt.Count -and $tt[0][0]) { [string]$tt[0][0] } else { 'COLUMN' }
          if ($lines.Count) { $text = "CREATE $ttxt TABLE `"$S`".`"$name`" (`n    " + ($lines -join ",`n    ") + "`n)" }
        }
      }
    } catch { Warn "  读取 $name 失败：$($_.Exception.Message)" }
    if (-not $text) { $noDef.Add($name); $manifest.Add("$($o.type)`t$name`t$($o.via)`t0`t无法读取定义（可能没有权限）"); continue }
    $text = $text -replace "`r`n", "`n"
    $file = Join-Path (Join-Path $syncRoot $kindDirs[$kind]) ((Safe-Name $name) + '.sql')
    [IO.File]::WriteAllText($file, $text, $utf8)
    $cnt[$kind]++
    $base = Find-Baseline $kind $name
    if ($base -eq $null) { $cmp = '导出包和对话中都没有'; $newOnly.Add($name) }
    elseif ($kind -eq 'table') { if ((Col-Signature $base) -eq (Col-Signature $text)) { $cmp = '字段相同' } else { $cmp = '字段不同'; $differ.Add($name) } }
    elseif ((Norm-Text $base) -eq (Norm-Text $text)) { $cmp = '相同' }
    else { $cmp = '不同'; $differ.Add($name) }
    $manifest.Add("$($o.type)`t$name`t$($o.via)`t$(($text -split "`n").Count)`t$cmp")
  }
  foreach ($n in $b1) { $manifest.Add("TABLE`t$n`tB1 标准表`t0`t未导出结构") }
  # 4. 配置表数据
  foreach ($t in $configTables) {
    try {
      $sql = if ($t -eq 'OTRC') { 'SELECT "TrnsCode", "TrnsCodDsc" FROM OTRC ORDER BY "TrnsCode"' } else { 'SELECT * FROM "' + $t + '"' }
      $res = Get-Rows $sql @() 5000
      $sb = New-Object System.Text.StringBuilder
      [void]$sb.AppendLine(($res.cols -join "`t"))
      foreach ($r in $res.rows) { [void]$sb.AppendLine((($r | ForEach-Object { if ($_ -eq $null) { '' } else { ([string]$_) -replace '[\t\r\n]', ' ' } }) -join "`t")) }
      [IO.File]::WriteAllText((Join-Path (Join-Path $syncRoot $kindDirs['data']) ('配置数据_' + (Safe-Name $t) + '.tsv')), $sb.ToString().TrimEnd(), $utf8)
      $cnt['data']++
    } catch { Warn "  读取配置表 $t 失败：$($_.Exception.Message)" }
  }
  # 5. B1 主数据（科目、物料组、科目确定、仓库、成本中心、物料）
  $mdir = Join-Path $syncRoot $masterDir
  [void](New-Item -ItemType Directory -Path $mdir -Force)
  $cnt['master'] = 0
  foreach ($t in $masterTables.Keys) {
    try {
      if ($t -eq 'OITM') {
        $have = @((Get-Rows 'SELECT COLUMN_NAME FROM SYS.TABLE_COLUMNS WHERE SCHEMA_NAME = ? AND TABLE_NAME = ''OITM'' ORDER BY POSITION' @($S)).rows | ForEach-Object { [string]$_[0] })
        $pick = @($have | Where-Object { $oitmCols -contains $_ -or $_.StartsWith('U_') })
        $sql = 'SELECT ' + (($pick | ForEach-Object { '"' + $_ + '"' }) -join ', ') + ' FROM OITM ORDER BY "ItemCode"'
      } else { $sql = 'SELECT * FROM ' + $t }
      $res = Get-Rows $sql @() 500000
      $sb = New-Object System.Text.StringBuilder
      [void]$sb.AppendLine(($res.cols -join "`t"))
      foreach ($r in $res.rows) { [void]$sb.AppendLine((($r | ForEach-Object { if ($_ -eq $null) { '' } else { ([string]$_) -replace '[\t\r\n]', ' ' } }) -join "`t")) }
      [IO.File]::WriteAllText((Join-Path $mdir ($t + '_' + $masterTables[$t] + '.tsv')), $sb.ToString().TrimEnd(), $utf8)
      $cnt['master']++
      Info "  主数据 $t（$($masterTables[$t])）：$($res.rows.Count) 行"
    } catch { Warn "  读取主数据 $t 失败：$($_.Exception.Message)" }
  }
  [IO.File]::WriteAllText((Join-Path $syncRoot '清单.tsv'), ($manifest -join "`n"), $utf8)
  [IO.File]::WriteAllText((Join-Path $syncRoot '依赖关系.tsv'), ("调用方`t被调用对象`t类型`n" + ($edges -join "`n")), $utf8)
  $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm')
  [IO.File]::WriteAllText((Join-Path $syncRoot '同步时间.txt'), "$stamp`nschema=$S", $utf8)
  $sw.Stop()
  Info ("同步完成：过程 {0}，函数 {1}，视图 {2}，表 {3}，配置数据 {4}，主数据 {5}；与原版本不同 {6} 个，新增 {7} 个，用时 {8:N1} 秒" -f $cnt.proc, $cnt.func, $cnt.view, $cnt.table, $cnt.data, $cnt.master, $differ.Count, $newOnly.Count, ($sw.ElapsedMilliseconds / 1000))
  $arr = { param($l) '[' + (($l | ForEach-Object { JStr $_ }) -join ',') + ']' }
  return '{"ok":true,"syncedAt":' + (JStr $stamp) + ',"syncSchema":' + (JStr $S) + ',"folder":' + (JStr $syncRoot) +
    ',"counts":{"proc":' + $cnt.proc + ',"func":' + $cnt.func + ',"view":' + $cnt.view + ',"table":' + $cnt.table + ',"data":' + $cnt.data + '}' +
    ',"differ":' + (& $arr $differ) + ',"newOnly":' + (& $arr $newOnly) + ',"noDef":' + (& $arr $noDef) + ',"b1Tables":' + $b1.Count + ',"ms":' + $sw.ElapsedMilliseconds + '}'
}

function Get-DbSourcesJson {
  if (-not (Test-Path $syncRoot)) { return '{"ok":true,"syncedAt":null,"items":[]}' }
  $stamp = ''; $syncSchema = ''
  $sf = Join-Path $syncRoot '同步时间.txt'
  if (Test-Path $sf) {
    $sl = ([IO.File]::ReadAllText($sf, $utf8)) -split "`n"
    $stamp = $sl[0].Trim()
    if ($sl.Count -gt 1 -and $sl[1] -match '^schema=(.+)$') { $syncSchema = $Matches[1].Trim() }
  }
  $items = New-Object System.Collections.Generic.List[string]
  foreach ($k in $kindDirs.Keys) {
    $dir = Join-Path $syncRoot $kindDirs[$k]
    if (-not (Test-Path $dir)) { continue }
    foreach ($f in Get-ChildItem -LiteralPath $dir -File) {
      $items.Add('{"name":' + (JStr $f.BaseName) + ',"kind":' + (JStr $k) + ',"path":' + (JStr ('0921-数据库同步\' + $kindDirs[$k] + '\' + $f.Name)) + ',"text":' + (JStr ([IO.File]::ReadAllText($f.FullName, $utf8))) + '}')
    }
  }
  return '{"ok":true,"syncedAt":' + (JStr $stamp) + ',"syncSchema":' + (JStr $syncSchema) + ',"items":[' + ($items -join ',') + ']}'
}

# ------------------------------------------------------------------
# 选择 SCHEMA，并生成连接说明（显示在网页上）
# ------------------------------------------------------------------
$connDesc = $baseCs
if ($baseCs -match 'DSN=([^;]+)') { $connDesc = 'ODBC 数据源 ' + $Matches[1] }
elseif ($baseCs -match 'SERVERNODE=([^;]+)') {
  $connDesc = $Matches[1]
  if ($baseCs -match 'DATABASENAME=([^;]+)') { $connDesc += ' / ' + $Matches[1] }
}

function Select-Schema {
  $cands = @()
  try { $cands = @((Get-Rows 'SELECT DISTINCT SCHEMA_NAME FROM SYS.TABLES WHERE TABLE_NAME = ''MTC_COST_0301_INVNT'' ORDER BY SCHEMA_NAME' @()).rows | ForEach-Object { [string]$_[0] }) } catch { }
  $saved = ''
  if (Test-Path $schemaFile) { $saved = ([IO.File]::ReadAllText($schemaFile, $utf8)).Trim() }
  $def = if ($saved) { $saved } elseif ($cands -contains 'FH100') { 'FH100' } elseif ($cands.Count) { $cands[0] } else { 'FH100' }
  Write-Host ''
  if ($cands.Count) {
    Write-Host '以下 SCHEMA 中有成本核算表（MTC_COST_0301_INVNT）：'
    for ($i = 0; $i -lt $cands.Count; $i++) { Write-Host ("  [{0}] {1}" -f ($i + 1), $cands[$i]) }
  } else {
    Warn '没有在任何 SCHEMA 中找到成本核算表 MTC_COST_0301_INVNT（也可能是账号没有权限查看）。'
  }
  while ($true) {
    $in = (Read-Host "请输入要使用的 SCHEMA（编号或名称，直接回车 = $def）").Trim()
    if (-not $in) { $sel = $def }
    elseif ($in -match '^\d+$' -and [int]$in -ge 1 -and [int]$in -le $cands.Count) { $sel = $cands[[int]$in - 1] }
    else { $sel = $in.Trim('"') }
    $found = [int](Get-Rows 'SELECT COUNT(*) FROM SYS.SCHEMAS WHERE SCHEMA_NAME = ?' @($sel)).rows[0][0]
    if ($found -eq 0 -and $sel -cne $sel.ToUpper()) {
      if ([int](Get-Rows 'SELECT COUNT(*) FROM SYS.SCHEMAS WHERE SCHEMA_NAME = ?' @($sel.ToUpper())).rows[0][0] -gt 0) { $sel = $sel.ToUpper(); $found = 1 }
    }
    if ($found -gt 0) { break }
    Warn "找不到 SCHEMA：$sel，请重新输入。"
  }
  $n = [int](Get-Rows 'SELECT COUNT(*) FROM SYS.TABLES WHERE SCHEMA_NAME = ? AND TABLE_NAME LIKE ''MTC\_COST%'' ESCAPE ''\''' @($sel)).rows[0][0]
  if ($n -eq 0) { Warn "注意：$sel 中没有 MTC_COST_ 开头的表，校验查询会报错。" }
  [IO.File]::WriteAllText($schemaFile, $sel, $utf8)
  return $sel
}

if (-not $Schema) { $Schema = Select-Schema }
try { Open-Conn } catch { Err "切换到 SCHEMA $Schema 失败：$($_.Exception.Message)"; Read-Host '按回车退出'; exit 1 }
$who = ''
try { $who = [string](Get-Rows 'SELECT CURRENT_USER FROM DUMMY' @()).rows[0][0] } catch { }

# ------------------------------------------------------------------
# HTTP（只监听 127.0.0.1）
# ------------------------------------------------------------------
function Send-Resp($stream, [int]$code, [string]$ctype, [byte[]]$body) {
  $txt = @{ 200 = 'OK'; 400 = 'Bad Request'; 403 = 'Forbidden'; 404 = 'Not Found'; 405 = 'Method Not Allowed'; 500 = 'Internal Server Error' }[$code]
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
  $headText = [Text.Encoding]::ASCII.GetString($all, 0, $headEnd)
  $hl = $headText -split "`r`n"
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
  if ($path -like '/api/*' -and $hdr['x-requested-with'] -ne 'cost-page') { Send-Resp $stream 403 'text/plain' ($utf8.GetBytes('forbidden')); return }

  if ($method -eq 'GET' -and ($path -eq '/' -or $path -eq '/index.html')) {
    Send-Resp $stream 200 'text/html; charset=utf-8' ([IO.File]::ReadAllBytes($pagePath)); return
  }
  if ($method -eq 'GET' -and $path -eq '/api/ping') {
    try {
      $r = Invoke-ReadOnly 'SELECT CURRENT_USER AS "U", CURRENT_SCHEMA AS "S" FROM DUMMY' @() 1
      Send-Json $stream ('{"ok":true,"conn":' + (JStr $connDesc) + ',"schema":' + (JStr $Schema) + ',"columns":[' + $r.columns + '],"rows":[' + $r.rows + ']}')
    } catch { Send-Json $stream (Json-Error $_.Exception.Message) }
    return
  }
  if ($method -eq 'GET' -and $path -eq '/api/periods') {
    try {
      $r = Invoke-ReadOnly 'SELECT TOP 60 "Code", "PeriodStat" FROM OFPR ORDER BY "Code" DESC' @() 60
      Send-Json $stream ('{"ok":true,"rows":[' + $r.rows + ']}')
    } catch { Send-Json $stream (Json-Error $_.Exception.Message) }
    return
  }
  if ($method -eq 'POST' -and $path -eq '/api/sync') {
    try { Send-Json $stream (Invoke-Sync) } catch { Err "同步出错：$($_.Exception.Message)"; Send-Json $stream (Json-Error $_.Exception.Message) }
    return
  }
  if ($method -eq 'GET' -and $path -eq '/api/db-sources') {
    try { Send-Json $stream (Get-DbSourcesJson) } catch { Send-Json $stream (Json-Error $_.Exception.Message) }
    return
  }
  if ($method -eq 'POST' -and $path -eq '/api/run') {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
      $req = $bodyText | ConvertFrom-Json
      $id = [string]$req.id; $fc = [string]$req.fc; $item = [string]$req.item; $wn = [string]$req.wn
      if ($fc -notmatch '^\d{4}-\d{2}$') { throw '账期格式应为 YYYY-MM，例如 2026-08。' }
      if ($item -and $item -notmatch '^[\w\.\-/]{1,50}$') { throw '物料编码只能包含字母、数字、下划线、点、横线和斜线。' }
      if ($wn -and $wn -notmatch '^[\w\.\-]{1,30}$') { throw '订单号只能包含字母、数字、下划线、点和横线。' }
      $checks = Get-Checks
      if (-not $checks.ContainsKey($id)) { throw "校验文件中没有 $id。" }
      $sql = $checks[$id].sql
      if ($sql.Contains("'<物料编码>'") -and -not $item) { throw '这个查询需要填写物料编码。' }
      if ($sql.Contains("'<订单号 WorNum>'") -and -not $wn) { throw '这个查询需要填写订单号。' }
      $b = Bind-Params $sql $fc $item $wn
      Write-Host ("{0:HH:mm:ss}  运行 {1}（账期 {2}）..." -f (Get-Date), $id, $fc) -NoNewline
      $r = Invoke-ReadOnly $b.sql $b.params $MaxRows
      $sw.Stop()
      Write-Host (" {0} 行，{1:N1} 秒" -f $r.count, ($sw.ElapsedMilliseconds / 1000))
      Send-Json $stream ('{"ok":true,"id":' + (JStr $id) + ',"columns":[' + $r.columns + '],"rows":[' + $r.rows + '],"rowCount":' + $r.count + ',"truncated":' + ($(if ($r.truncated) { 'true' } else { 'false' })) + ',"ms":' + $sw.ElapsedMilliseconds + '}')
    } catch {
      Write-Host ''
      Err "  出错：$($_.Exception.Message)"
      Send-Json $stream (Json-Error $_.Exception.Message)
    }
    return
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

$url = "http://127.0.0.1:$Port/"
Write-Host ''
Info "已连接 HANA：$connDesc，账号 $who，SCHEMA $Schema"
Info "页面地址：$url"
Info '保持这个窗口打开；关闭窗口或按 Ctrl+C 即停止服务。'
Write-Host ''
Start-Process $url

try {
  while ($true) {
    if (-not $listener.Pending()) { Start-Sleep -Milliseconds 100; continue }
    $client = $listener.AcceptTcpClient()
    try { Handle-Client $client } catch { Err "请求处理出错：$($_.Exception.Message)" } finally { $client.Close() }
  }
} finally {
  $listener.Stop()
  if ($script:conn -ne $null) { $script:conn.Dispose() }
}
