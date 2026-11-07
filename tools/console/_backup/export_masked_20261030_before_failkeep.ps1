<#
  FH100 成本核算 · 导出排查数据（脱敏）

  作用：把指定账期的成本中间表 / 结果表导出成 CSV，打成一个 zip，用于交给 AI 排查（用户 2026-10-13 同意）。
        与 新框架\tools\export_masked.py 同一套规则（那个是 Python 版）：
          - 名称、备注、用户、项目等文本列清空（ItemName、CardName、Comments、Memo、Remark、Creator、UserCode…）；
          - 业务伙伴代码（CardCode / VendorCode）换成代号 BP0001…，其他文本列里出现的也一起替换；
          - 物料编码、金额、数量、日期、单号、科目、仓库、交易类型原样保留（用户确认不用脱敏）。
        代号对照表写在项目根目录 脱敏密钥\代码对照.csv，只留在本机，不要发出去。

  新框架的表按运行号取（2026-10-29）：默认 = 本账期最近一次运行（成功、未收敛、失败都算）+ 每种运行类型 / 场景最近一次成功的运行；
        也可以输入运行号（逗号分隔）或 ALL（全部运行）。MTC_CA_RUN 列出本账期全部运行。
        未收敛的运行要库上已执行 patch_20261029_noconv.sql 才保留快照和中间结果，否则只有迭代日志，脚本会提示。

  安全：只执行 SELECT，在事务中执行，结束后回滚；密码只保存在本次运行的内存中。

  用法：双击 tools\导出排查数据.bat（如果驱动是 32 位，双击 导出排查数据_32位.bat）
#>
param(
  [string]$Schema = '',
  [string]$FcCode = '',
  [string]$Runs = ''
)

$ErrorActionPreference = 'Stop'
$here       = Split-Path -Parent $MyInvocation.MyCommand.Path
$root       = Split-Path -Parent $here
$connFile   = Join-Path $here 'connection.txt'
$schemaFile = Join-Path $here 'console_schema.txt'
$utf8       = New-Object System.Text.UTF8Encoding($false)
$utf8Bom    = New-Object System.Text.UTF8Encoding($true)
$inv        = [Globalization.CultureInfo]::InvariantCulture
Add-Type -AssemblyName System.Data

function Info($m) { Write-Host $m -ForegroundColor Cyan }
function Warn($m) { Write-Host $m -ForegroundColor Yellow }
function Err($m)  { Write-Host $m -ForegroundColor Red }

$OldTables = @('MTC_COST_0201_DOCDETAL', 'MTC_COST_0301_INVNT', 'MTC_COST_0302_INVNTDETAIL1', 'MTC_COST_0303_INVNTLIST',
               'MTC_COST_0321_OWOR', 'MTC_COST_0321_OWOR1', 'MTC_COST_0321_OWOR2', 'MTC_COST_0321_OWOR_SUM',
               'MTC_COST_0322_OWOR_ZCP', 'MTC_COST_0322_OWOR_ZCP1', 'MTC_COST_0801_TOOJDT', 'MTC_COST_0802_OJDTBASEDETAIL',
               'U_COILV')
$reDrop  = New-Object Text.RegularExpressions.Regex('(ItemName|CardName|StockName|Comments|Remark|^Memo$|LineMemo|^U_Memo$|Creator|^User$|UserCode|CreateUser|Project|Address|Phone|Mail|ModelOutput)', 'IgnoreCase')
$reBp    = New-Object Text.RegularExpressions.Regex('(CardCode|VendorCode)$', 'IgnoreCase')
$reItem  = New-Object Text.RegularExpressions.Regex('(ItemCode|ProdItem|^Father$|StockCode)$', 'IgnoreCase')
# 纯代码列：不做文本替换（避免把与业务伙伴代码同形的科目、仓库等误替换）
$reCode  = New-Object Text.RegularExpressions.Regex('(FcCode|TransCode|WhsCode|Acct|OcrCode|CostCode|BusiType|Type|Status|StepCode|CheckId|^Code$|Cod$|Stat$|^Is|Canceled|Dir|Stage|Result|Scenario|Layer|Elem|Kind|Cat|Unit)', 'IgnoreCase')
$reToken = New-Object Text.RegularExpressions.Regex('[A-Za-z0-9_]+(?:[-./][A-Za-z0-9_]+)*')

# ------------------------------------------------------------------
# 连接（与执行台、排查服务共用 connection.txt，不含账号密码）
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

$conn = New-Object System.Data.Odbc.OdbcConnection($fullCs)
try { $conn.Open() } catch {
  Err "连接失败：$($_.Exception.Message)"
  if ($_.Exception.Message -match 'IM002|IM014|architecture|未发现数据源|找不到') {
    Warn '提示：ODBC 驱动的位数要和程序一致。如果本机只装了 32 位 HANA Client，请改用 导出排查数据_32位.bat。'
  }
  Read-Host '按回车退出'; exit 1
}
$tx = $conn.BeginTransaction()

function Q([string]$sql, [object[]]$vals = @()) {
  $cmd = $conn.CreateCommand(); $cmd.Transaction = $tx; $cmd.CommandText = $sql; $cmd.CommandTimeout = 0
  foreach ($v in $vals) { $x = $cmd.CreateParameter(); $x.OdbcType = [System.Data.Odbc.OdbcType]::NVarChar; $x.Value = [string]$v; [void]$cmd.Parameters.Add($x) }
  $rd = $cmd.ExecuteReader(); $rows = New-Object System.Collections.ArrayList
  try { while ($rd.Read()) { $o = New-Object object[] $rd.FieldCount; [void]$rd.GetValues($o); [void]$rows.Add($o) } } finally { $rd.Close() }
  return ,$rows
}

try {
  function Csv([string]$s) {
    if ($s.IndexOfAny([char[]]@(',', '"', "`r", "`n")) -ge 0) { return '"' + $s.Replace('"', '""') + '"' }
    return $s
  }
  function Fmt($v) {
    if ($v -is [DBNull] -or $v -eq $null) { return '' }
    if ($v -is [DateTime]) { if ($v.TimeOfDay.Ticks -eq 0) { return $v.ToString('yyyy-MM-dd', $inv) } else { return $v.ToString('yyyy-MM-dd HH:mm:ss', $inv) } }
    if ($v -is [IFormattable]) { return $v.ToString($null, $inv) }
    if ($v -is [byte[]]) { return [Convert]::ToBase64String($v) }
    return [string]$v
  }

  # ---------------- 选账套 ----------------
  if (-not $Schema) {
    $rs = Q 'SELECT DISTINCT "SCHEMA_NAME" FROM "SYS"."TABLES" WHERE "TABLE_NAME" IN (''MTC_COST_0302_INVNTDETAIL1'',''MTC_CA_RUN'') ORDER BY 1'
    $cands = @(foreach ($r in $rs) { [string]$r[0] })
    $saved = ''
    if (Test-Path $schemaFile) { $saved = ([IO.File]::ReadAllText($schemaFile, $utf8)).Trim() }
    Write-Host ''
    Write-Host '以下账套（SCHEMA）有成本核算表：'
    for ($i = 0; $i -lt $cands.Count; $i++) { Write-Host ("  [{0}] {1}" -f ($i + 1), $cands[$i]) }
    $def = if ($saved -and $cands -contains $saved) { $saved } elseif ($cands.Count -eq 1) { $cands[0] } else { '' }
    while (-not $Schema) {
      $prompt = if ($def) { "请输入账套（编号或名称，直接回车 = $def）" } else { '请输入账套（编号或名称）' }
      $in = (Read-Host $prompt).Trim()
      if (-not $in) { $Schema = $def }
      elseif ($in -match '^\d+$' -and [int]$in -ge 1 -and [int]$in -le $cands.Count) { $Schema = $cands[[int]$in - 1] }
      else { $hit = @($cands | Where-Object { $_.ToUpper() -eq $in.Trim('"').ToUpper() }); if ($hit.Count) { $Schema = $hit[0] } else { Warn "没有账套 $in" } }
    }
  }
  $c0 = $conn.CreateCommand(); $c0.Transaction = $tx; $c0.CommandText = 'SET SCHEMA "' + $Schema.Replace('"', '') + '"'; [void]$c0.ExecuteNonQuery()

  # ---------------- 选账期和范围 ----------------
  if (-not $FcCode) {
    $defFc = (Get-Date).AddMonths(-1).ToString('yyyy-MM')
    $in = (Read-Host "请输入账期（例如 2026-09，直接回车 = $defFc）").Trim()
    $FcCode = if ($in) { $in } else { $defFc }
  }
  if ($FcCode -notmatch '^\d{4}-\d{2}$') { throw "账期格式不对：$FcCode" }
  Write-Host ''
  Write-Host '导出哪些表：  [1] 新框架和旧流程都导（默认）  [2] 只导新框架 MTC_CA_*  [3] 只导旧流程 MTC_COST_*'
  $set = (Read-Host '请选择（直接回车 = 1）').Trim()
  $tables = New-Object System.Collections.ArrayList
  if ($set -ne '3') {
    foreach ($r in (Q 'SELECT "TABLE_NAME" FROM "SYS"."TABLES" WHERE "SCHEMA_NAME"=? AND "TABLE_NAME" LIKE ''MTC\_CA\_%'' ESCAPE ''\'' ORDER BY 1' @($Schema))) {
      if ([string]$r[0] -notmatch '_(BACKUP|TEST|\d{6,})') { [void]$tables.Add([string]$r[0]) }
    }
  }
  if ($set -ne '2') { foreach ($t in $OldTables) { [void]$tables.Add($t) } }

  # ---------------- 选运行（新框架的表只取这些运行）----------------
  $runRows = @()
  $runIds = @()
  if ($set -ne '3') {
    try { $runRows = Q 'SELECT "RunId","RunType","Scenario","Status","IterCount","Converged","StartTime" FROM "MTC_CA_RUN" WHERE "FcCode"=? ORDER BY "RunId"' @($FcCode) }
    catch { Warn "读不到 MTC_CA_RUN：$($_.Exception.Message)" }
    if ($runRows.Count) {
      Write-Host ''
      Write-Host "账期 $FcCode 的运行（最近 15 次）："
      $from = [Math]::Max(0, $runRows.Count - 15)
      for ($i = $from; $i -lt $runRows.Count; $i++) {
        $r = $runRows[$i]
        $rt = if ([string]$r[1] -eq 'F') { '正式' } else { '模拟 ' + [string]$r[2] }
        Write-Host ("  #{0,-6} {1,-12} {2,-8} 迭代 {3,3} 轮  {4}" -f $r[0], $rt, $r[3], $r[4], (Fmt $r[6]))
      }
      if (-not $Runs) { $Runs = (Read-Host '导出哪些运行（运行号逗号分隔 / ALL = 全部；直接回车 = 最近一次运行 + 各类最近一次成功）').Trim() }
      if ($Runs -match '^(?i)all$') { $runIds = @(foreach ($r in $runRows) { [long]$r[0] }) }
      elseif ($Runs) { $runIds = @(foreach ($x in $Runs.Split(',')) { if ($x.Trim() -match '^\d+$') { [long]$x.Trim() } }) }
      else {
        $lastOk = @{}
        foreach ($r in $runRows) { if ([string]$r[3] -eq 'OK') { $lastOk[[string]$r[1] + '|' + [string]$r[2]] = [long]$r[0] } }
        $runIds = @(@([long]$runRows[$runRows.Count - 1][0]) + @($lastOk.Values) | Sort-Object -Unique)
      }
      Info ('选中的运行：' + (($runIds | ForEach-Object { '#' + $_ }) -join ', '))
    } else { Warn "账期 $FcCode 没有新框架运行记录" }
  }
  $runIn = if ($runIds.Count) { ($runIds | ForEach-Object { [string]$_ }) -join ',' } else { 'NULL' }

  # ---------------- 业务伙伴代号 ----------------
  $keyDir = Join-Path $root '脱敏密钥'
  if (-not (Test-Path $keyDir)) { [void](New-Item -ItemType Directory -Path $keyDir) }
  $mapFile = Join-Path $keyDir '代码对照.csv'
  $map = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
  $n = 0
  if (Test-Path $mapFile) {
    foreach ($l in [IO.File]::ReadAllLines($mapFile, $utf8)) {
      $p = $l.Split(','); if ($p.Count -eq 2 -and $p[1] -like 'BP*') { $map[$p[0]] = $p[1]; $n = [Math]::Max($n, [int]$p[1].Substring(2)) }
    }
  }
  $rs = Q 'SELECT "CardCode" FROM "OCRD"'
  $newCodes = @(foreach ($r in $rs) { $c = [string]$r[0]; if ($c -and -not $map.ContainsKey($c)) { $c } }) | Sort-Object { Get-Random }
  foreach ($c in $newCodes) { $n++; $map[$c] = 'BP{0:D4}' -f $n }
  $sb = New-Object Text.StringBuilder
  foreach ($kv in ($map.GetEnumerator() | Sort-Object Value)) { [void]$sb.Append($kv.Key).Append(',').Append($kv.Value).Append("`r`n") }
  [IO.File]::WriteAllText($mapFile, $sb.ToString(), $utf8Bom)
  $eval = [Text.RegularExpressions.MatchEvaluator] { param($m) $v = $null; if ($map.TryGetValue($m.Value, [ref]$v)) { $v } else { $m.Value } }

  # ---------------- 导出 ----------------
  $outName = '{0}_{1}' -f $FcCode, (Get-Date -Format 'yyyyMMdd_HHmm')
  $outDir = Join-Path (Join-Path $root '排查数据') $outName
  [void](New-Item -ItemType Directory -Path $outDir -Force)
  $notes = New-Object Text.StringBuilder
  $okCnt = 0; $badCnt = 0
  [void]$notes.Append("账套 $Schema，账期 $FcCode，导出时间 $(Get-Date -Format 'yyyy-MM-dd HH:mm')。物料编码和金额为原值；业务伙伴代码已换成代号。`r`n")
  [void]$notes.Append("列处理：drop=清空为 *，map=代码换成代号，text=文本中的业务伙伴代码换成代号；未列出的列原样保留。`r`n")
  if ($runIds.Count) {
    [void]$notes.Append("新框架的表只含这些运行（MTC_CA_RUN 列出本账期全部运行）：`r`n")
    foreach ($r in $runRows) { if ($runIds -contains [long]$r[0]) { [void]$notes.Append(("  #{0} {1} {2} {3} 迭代 {4} 轮 收敛 {5}`r`n" -f $r[0], $r[1], $r[2], $r[3], $r[4], $r[5])) } }
  }
  [void]$notes.Append("`r`n")
  Write-Host ''
  # 导出一个查询：列规则按读取器返回的列名和类型判断（表和函数结果同一套）
  function Export-Query([string]$t, [string]$sql, [object[]]$args2) {
    $cmd = $conn.CreateCommand(); $cmd.Transaction = $tx; $cmd.CommandText = $sql; $cmd.CommandTimeout = 0
    foreach ($v in $args2) { $x = $cmd.CreateParameter(); $x.OdbcType = [System.Data.Odbc.OdbcType]::NVarChar; $x.Value = [string]$v; [void]$cmd.Parameters.Add($x) }
    $cnt = 0; $names = @(); $rules = @()
    $w = New-Object IO.StreamWriter((Join-Path $outDir "$t.csv"), $false, $utf8Bom)
    try {
      $rd = $cmd.ExecuteReader()
      try {
        $nc = $rd.FieldCount
        $names = @(for ($i = 0; $i -lt $nc; $i++) { $rd.GetName($i) })
        $rules = @(for ($i = 0; $i -lt $nc; $i++) {
          $nm = $names[$i]; $isText = ($rd.GetFieldType($i) -eq [string])
          if ($reBp.IsMatch($nm)) { 'map' }
          elseif ($reDrop.IsMatch($nm) -and -not $reItem.IsMatch($nm)) { 'drop' }
          elseif ($isText -and -not $reCode.IsMatch($nm) -and -not $reItem.IsMatch($nm)) { 'text' }
          else { 'keep' }
        })
        $w.WriteLine((($names | ForEach-Object { Csv $_ }) -join ','))
        while ($rd.Read()) {
          $cells = New-Object string[] $nc
          for ($i = 0; $i -lt $nc; $i++) {
            $v = $null
            try { $v = $rd.GetValue($i) } catch { try { $v = $rd.GetString($i) } catch { $v = '?' } }
            $s = Fmt $v
            if ($s -ne '') {
              switch ($rules[$i]) {
                'drop' { $s = '*' }
                'map'  { $m2 = $null; if ($map.TryGetValue($s, [ref]$m2)) { $s = $m2 } else { $s = $reToken.Replace($s, $eval) } }
                'text' { $s = $reToken.Replace($s, $eval) }
              }
            }
            $cells[$i] = Csv $s
          }
          $w.WriteLine(($cells -join ','))
          $cnt++
        }
      } finally { $rd.Close() }
    } catch {
      $script:badCnt++; Warn "$t 导出失败：$($_.Exception.Message)"; [void]$notes.Append("$t`t导出失败 $($_.Exception.Message)`r`n"); return
    } finally { $w.Close() }
    Write-Host ("  {0,-34} {1,8} 行" -f $t, $cnt)
    $script:okCnt++
    [void]$notes.Append("$t`t$cnt`r`n")
    $special = @(for ($i = 0; $i -lt $names.Count; $i++) { if ($rules[$i] -ne 'keep') { "$($names[$i]):$($rules[$i])" } })
    if ($special.Count) { [void]$notes.Append("`t" + ($special -join ', ') + "`r`n") }
  }

  foreach ($t in $tables) {
    $cols = Q 'SELECT "COLUMN_NAME" FROM "SYS"."TABLE_COLUMNS" WHERE "SCHEMA_NAME"=? AND "TABLE_NAME"=? ORDER BY "POSITION"' @($Schema, $t)
    if ($cols.Count -eq 0) { $badCnt++; Warn "跳过 $t：不存在"; [void]$notes.Append("$t`t不存在`r`n"); continue }
    $names = @(foreach ($c in $cols) { [string]$c[0] })
    $sql = 'SELECT * FROM "' + $t + '"'; $args2 = @()
    if ($t -like 'MTC_CA_*' -and $t -ne 'MTC_CA_RUN' -and $names -contains 'RunId') { $sql += ' WHERE "RunId" IN (' + $runIn + ')' }
    elseif ($names -contains 'FcCode') { $sql += ' WHERE "FcCode"=?'; $args2 = @($FcCode) }
    elseif ($names -contains '期间') { $sql += ' WHERE "期间"=?'; $args2 = @($FcCode) }   # 0322_OWOR_ZCP 的账期列
    Export-Query $t $sql $args2
  }

  # 财务对账的总账 / 未清凭单分录（2026-10-17）：表里没有，从只读函数取。本账期每种运行类型最近一次成功的运行；
  # F_RECON_LEDGER = 对账科目按来源 × 凭证代码汇总，F_TB_LINE = 成本相关科目逐笔分录（Memo 清空、VendorCode 换代号）
  # 未收敛的运行有没有留下中间结果
  foreach ($r in $runRows) {
    if ([string]$r[3] -eq 'NOCONV' -and $runIds -contains [long]$r[0] -and $tables -contains 'MTC_CA_R_ITEM') {
      $c1 = Q ('SELECT COUNT(*) FROM "MTC_CA_R_ITEM" WHERE "RunId"=' + [long]$r[0])
      if ([long]$c1[0][0] -eq 0) {
        $m = "运行 #$($r[0]) 未收敛，但快照和中间结果已被删除（库上还没执行 patch_20261029_noconv.sql，或参数 KEEP_NOCONV = N），只导出了迭代日志。部署补丁后重新计算一次再导出。"
        Warn $m; [void]$notes.Append("⚠ $m`r`n")
      }
    }
  }

  # 只对成功的运行（未收敛的没有定稿和凭证）
  if ($tables -contains 'MTC_CA_RUN') {
    $ids = @(foreach ($r in $runRows) { if ([string]$r[3] -eq 'OK' -and $runIds -contains [long]$r[0]) { [string]$r[0] } })
    if ($ids.Count) {
      $u1 = ($ids | ForEach-Object { 'SELECT ' + $_ + ' AS "RunId", L.* FROM "MTC_CA_F_RECON_LEDGER"(' + $_ + ') L' }) -join ' UNION ALL '
      Export-Query 'F_RECON_LEDGER' $u1 @()
      $u2 = ($ids | ForEach-Object { 'SELECT ' + $_ + ' AS "RunId", L.* FROM "MTC_CA_F_TB_LINE"(' + $_ + ', '''') L' }) -join ' UNION ALL '
      Export-Query 'F_TB_LINE' $u2 @()
    }
  }
  [IO.File]::WriteAllText((Join-Path $outDir '说明.txt'), $notes.ToString(), $utf8Bom)

  $zip = "$outDir.zip"
  try { Compress-Archive -Path (Join-Path $outDir '*') -DestinationPath $zip -Force } catch { Warn "打包 zip 失败：$($_.Exception.Message)"; $zip = $null }
  Write-Host ''
  if ($badCnt -eq 0) { Write-Host "==== 导出完成：$okCnt 张表全部成功 ====" -ForegroundColor Green }
  else { Warn "==== 导出完成：$okCnt 张表成功，$badCnt 张跳过或失败（见上面黄色行和 说明.txt）====" }
  Info "已导出到：$outDir"
  if ($zip) { Info "压缩包：$zip （把这个文件拷到 Mac 项目的 排查数据 文件夹里即可）" }
  Warn "脱敏密钥\代码对照.csv 只留在本机，不要发出去。"
  Start-Process explorer.exe (Split-Path -Parent $outDir)
} catch {
  Err "出错：$($_.Exception.Message)"
} finally {
  try { $tx.Rollback() } catch { }
  $conn.Dispose()
}
Read-Host '按回车退出'
