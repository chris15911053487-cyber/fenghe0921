<#
  FH100 成本核算 · 140801 委外加工物资-材料 专项排查导出（用户 2026-11-12）

  作用：财务 140801 − 业务委外在产品 ≠ “历史委外差异”待转清单时，把排查要用的数据导成 CSV 并打成 zip，交给 AI 对数。
        只读：只执行 SELECT，在事务中执行，结束后回滚。
        不导名称、备注、用户、业务伙伴：只有订单 / 单据编号、物料编码、账期、日期、科目、凭证代码和金额（用户 2026-10-13 确认物料编码、金额不用脱敏）。
  连接：同 导出排查数据.bat（共用 tools\connection.txt，账号密码只在本次运行的内存中）。
  默认取该账期最近一次成功的正式运行（RunType F、无场景），也可以输入运行号。
  输出：<项目根目录>\排查数据\ww140801_<账期>_<时间>\*.csv + .zip

  导出内容：01 历史委外差异清单；02/03 财务对账 WW_MAT / WW_FEE 两行及来源；04 140801 总账按月 × 凭证代码（含未清凭单）；
            05 140801 手工 / 非 WW01、WW03 的分录逐张；06/07 旧在产品表委外订单 2026-06 起逐期、每张订单最后一行；
            08 期初承接订单 ZCP / ZCP1 两个口径；09/10 本次运行委外订单期初 / 期末及材料行；11 清单订单在 B1 的全部收发（按月）；
            12 本次运行 S_EXP 的 WWHIST 行；13 本账期凭单记录。

  用法：双击 tools\导出140801排查数据.bat（32 位驱动用 导出140801排查数据_32位.bat）
#>
param([string]$Schema = '', [string]$FcCode = '', [string]$RunId = '')

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

# ---------------- 查询（{run} {fc} {boot} {acct} {wwwt} {d1} 运行时代入）----------------
$Qs = New-Object 'System.Collections.Specialized.OrderedDictionary'
$Qs.Add('01_ww_hist', @'
SELECT "OrderType", "OrderEntry", "DocNum", "ItemCode", "B1Status", "CloseDate", "LastFc", "Amount",
       "LoadFc", "LoadTime", "PlanFc", "PlanTime", "Manual"
  FROM "MTC_CA_WW_HIST" ORDER BY "OrderType", "OrderEntry"
'@)
$Qs.Add('02_recon', @'
SELECT * FROM "MTC_CA_F_RECON"({run}) WHERE "Area" IN ('WW_MAT', 'WW_FEE')
'@)
$Qs.Add('03_recon_ledger', @'
SELECT * FROM "MTC_CA_F_RECON_LEDGER"({run}) WHERE "Area" IN ('WW_MAT', 'WW_FEE')
'@)
$Qs.Add('04_gl_month', @'
SELECT 'GL' AS "Src", TO_NVARCHAR(H."RefDate", 'YYYY-MM') AS "Mon", IFNULL(H."TransCode", '') AS "TransCode",
       TO_NVARCHAR(H."TransType") AS "TransType", COUNT(*) AS "Lines", SUM(J."Debit") AS "Debit", SUM(J."Credit") AS "Credit",
       SUM(J."Debit" - J."Credit") AS "Net"
  FROM "OJDT" H JOIN "JDT1" J ON J."TransId" = H."TransId"
 WHERE H."RefDate" <= '{d1}' AND J."Account" = '{acct}'
 GROUP BY TO_NVARCHAR(H."RefDate", 'YYYY-MM'), IFNULL(H."TransCode", ''), TO_NVARCHAR(H."TransType")
UNION ALL
SELECT 'DRAFT', TO_NVARCHAR(T0."RefDate", 'YYYY-MM'), IFNULL(T0."TransCode", ''), TO_NVARCHAR(T0."TransType"), COUNT(*),
       SUM(T1."Debit"), SUM(T1."Credit"), SUM(T1."Debit" - T1."Credit")
  FROM "OBTF" T0 JOIN "BTF1" T1 ON T1."TransId" = T0."TransId" AND T1."BatchNum" = T0."BatchNum"
 WHERE T0."BtfStatus" = 'O' AND T0."RefDate" <= '{d1}' AND T1."Account" = '{acct}'
 GROUP BY TO_NVARCHAR(T0."RefDate", 'YYYY-MM'), IFNULL(T0."TransCode", ''), TO_NVARCHAR(T0."TransType")
 ORDER BY 2, 3, 4
'@)
$Qs.Add('05_gl_manual', @'
SELECT H."TransId", H."Number", H."RefDate", TO_NVARCHAR(H."TransType") AS "TransType", IFNULL(H."TransCode", '') AS "TransCode",
       H."StornoToTr", COUNT(*) AS "Lines", SUM(J."Debit") AS "Debit", SUM(J."Credit") AS "Credit", SUM(J."Debit" - J."Credit") AS "Net"
  FROM "OJDT" H JOIN "JDT1" J ON J."TransId" = H."TransId"
 WHERE H."RefDate" <= '{d1}' AND J."Account" = '{acct}'
   AND (TO_NVARCHAR(H."TransType") = '30' OR IFNULL(H."TransCode", '') NOT IN ('WW01', 'WW03'))
 GROUP BY H."TransId", H."Number", H."RefDate", TO_NVARCHAR(H."TransType"), IFNULL(H."TransCode", ''), H."StornoToTr"
 ORDER BY H."RefDate", H."TransId"
'@)
$Qs.Add('06_zcp', @'
SELECT "期间" AS "Fc", IFNULL("DocType", '202') AS "OrderType", "WorEntry" AS "OrderEntry", MAX("WorType") AS "WorType",
       MAX("订单状态") AS "Status", MAX("订单关单日期") AS "CloseDate", MAX("关单结算期间") AS "CloseFc",
       SUM(IFNULL("在产品新", 0)) AS "WipNew", SUM(IFNULL("在产品金额", 0)) AS "WipOld", SUM(IFNULL("关单差异", 0)) AS "CloseDif",
       SUM(IFNULL("累计材料", 0)) AS "CumMat", SUM(IFNULL("累计完工材料合计", 0)) AS "CumDoneMat", SUM(IFNULL("累计委外费用", 0)) AS "CumSub"
  FROM "MTC_COST_0322_OWOR_ZCP" Z
 WHERE ("期间" >= '2026-06' AND "期间" <= '{boot}')
   AND ("WorType" = '50' OR EXISTS (SELECT 1 FROM "MTC_CA_WW_HIST" H WHERE H."OrderType" = IFNULL(Z."DocType", '202') AND H."OrderEntry" = Z."WorEntry"))
 GROUP BY "期间", IFNULL("DocType", '202'), "WorEntry"
 ORDER BY 2, 3, 1
'@)
$Qs.Add('07_zcp_last', @'
SELECT * FROM (
  SELECT IFNULL("DocType", '202') AS "OrderType", "WorEntry" AS "OrderEntry", "期间" AS "LastFc", MAX("WorType") AS "WorType",
         SUM(IFNULL("在产品新", 0)) AS "WipNew",
         ROW_NUMBER() OVER (PARTITION BY IFNULL("DocType", '202'), "WorEntry" ORDER BY "期间" DESC) AS "Rn"
    FROM "MTC_COST_0322_OWOR_ZCP" WHERE "期间" <= '{boot}'
   GROUP BY IFNULL("DocType", '202'), "WorEntry", "期间")
 WHERE "Rn" = 1 AND ("WorType" = '50' OR "WipNew" <> 0)
'@)
$Qs.Add('08_boot_order', @'
SELECT B."OrderType", B."OrderEntry", B."ZcpWip", B."Zcp1Wip", M."MatWip", M."Mats",
       CASE WHEN B."OrderType" = 'MTC_OWOR' THEN MO."U_OrdType" ELSE W."U_OrdType" END AS "B1WorType",
       CASE WHEN B."OrderType" = 'MTC_OWOR' THEN MO."U_Status" ELSE W."Status" END AS "B1Status"
  FROM "MTC_CA_BOOT_ORDER" B
  LEFT JOIN (SELECT "OrderType", "OrderEntry", SUM("WipAmt") AS "MatWip", COUNT(*) AS "Mats"
               FROM "MTC_CA_BOOT_ORDER_MAT" WHERE "FcCode" = '{boot}' GROUP BY "OrderType", "OrderEntry") M
         ON M."OrderType" = B."OrderType" AND M."OrderEntry" = B."OrderEntry"
  LEFT JOIN "OWOR" W ON B."OrderType" = '202' AND W."DocEntry" = B."OrderEntry"
  LEFT JOIN "@MTC_OWOR" MO ON B."OrderType" = 'MTC_OWOR' AND MO."DocEntry" = B."OrderEntry"
 WHERE B."FcCode" = '{boot}' 
'@)
$Qs.Add('09_run_order', @'
SELECT O."OrderType", O."OrderEntry", O."OrderNum", O."WorType", O."ItemCode", O."B1Status", O."CloseDate", O."StatusAtEnd",
       O."ClosedInFc", O."InScope", O."RecvQty", O."PrevRecvQty",
       OP."Beg", OP."BegSub", RM."Wip", RM."WipSub", RM."Mats"
  FROM "MTC_CA_S_ORDER" O
  LEFT JOIN (SELECT "OrderType", "OrderEntry",
                    SUM(CASE WHEN "ItemCode" <> '#SUBFEE' THEN IFNULL("CumIssueMat",0)+IFNULL("CumIssueMfg",0)+IFNULL("CumIssueLab",0)+IFNULL("CumIssueSub",0)
                             -IFNULL("CumCarriedMat",0)-IFNULL("CumCarriedMfg",0)-IFNULL("CumCarriedLab",0)-IFNULL("CumCarriedSub",0) ELSE 0 END) AS "Beg",
                    SUM(CASE WHEN "ItemCode" = '#SUBFEE' THEN IFNULL("CumIssueSub",0)-IFNULL("CumCarriedSub",0) ELSE 0 END) AS "BegSub"
               FROM "MTC_CA_S_ORDER_OPEN" WHERE "RunId" = {run} GROUP BY "OrderType", "OrderEntry") OP
         ON OP."OrderType" = O."OrderType" AND OP."OrderEntry" = O."OrderEntry"
  LEFT JOIN (SELECT "OrderType", "OrderEntry", COUNT(*) AS "Mats",
                    SUM(CASE WHEN "ItemCode" <> '#SUBFEE' THEN "WipMat"+"WipMfg"+"WipLab"+"WipSub" ELSE 0 END) AS "Wip",
                    SUM(CASE WHEN "ItemCode" = '#SUBFEE' THEN "WipSub" ELSE 0 END) AS "WipSub"
               FROM "MTC_CA_R_ORDER_MAT" WHERE "RunId" = {run} GROUP BY "OrderType", "OrderEntry") RM
         ON RM."OrderType" = O."OrderType" AND RM."OrderEntry" = O."OrderEntry"
 WHERE O."RunId" = {run} AND (LOCATE('{wwwt}', ',' || IFNULL(O."WorType", '') || ',') > 0
       OR EXISTS (SELECT 1 FROM "MTC_CA_WW_HIST" H WHERE H."OrderType" = O."OrderType" AND H."OrderEntry" = O."OrderEntry"))
'@)
$Qs.Add('10_run_order_mat', @'
SELECT M.* FROM "MTC_CA_R_ORDER_MAT" M JOIN "MTC_CA_S_ORDER" O ON O."RunId" = M."RunId" AND O."OrderType" = M."OrderType" AND O."OrderEntry" = M."OrderEntry"
 WHERE M."RunId" = {run} AND LOCATE('{wwwt}', ',' || IFNULL(O."WorType", '') || ',') > 0
'@)
$Qs.Add('11_hist_moves', @'
SELECT G."OrderType", G."OrderEntry", G."ObjType", G."U_BusiType", TO_NVARCHAR(IFNULL(I."DocDate", E."DocDate"), 'YYYY-MM') AS "Mon",
       COUNT(*) AS "Lines", SUM(V."Qty") AS "Qty", SUM(V."Amt") AS "Amt"
  FROM "MTC_CA_F_GI_ORDER"('{fc}', NULL, '{d1}') G
  JOIN "MTC_CA_WW_HIST" H ON H."OrderType" = G."OrderType" AND TO_NVARCHAR(H."OrderEntry") = G."OrderEntry"
  LEFT JOIN "OIGN" I ON G."ObjType" = '59' AND TO_NVARCHAR(I."DocEntry") = G."DocEntry"
  LEFT JOIN "OIGE" E ON G."ObjType" = '60' AND TO_NVARCHAR(E."DocEntry") = G."DocEntry"
  LEFT JOIN (SELECT TO_NVARCHAR("TransType") AS "TT", TO_NVARCHAR("CreatedBy") AS "DE", TO_NVARCHAR("DocLineNum") AS "LN",
                    SUM("InQty" - "OutQty") AS "Qty", SUM("SumStock") AS "Amt"
               FROM "OIVL" WHERE "TransType" IN (59, 60) GROUP BY "TransType", "CreatedBy", "DocLineNum") V
         ON V."TT" = G."ObjType" AND V."DE" = G."DocEntry" AND V."LN" = G."LineNum"
 GROUP BY G."OrderType", G."OrderEntry", G."ObjType", G."U_BusiType", TO_NVARCHAR(IFNULL(I."DocDate", E."DocDate"), 'YYYY-MM')
 ORDER BY 1, 2, 5
'@)
$Qs.Add('12_run_exp_hist', @'
SELECT "Src", "SrcKey", "Amount" FROM "MTC_CA_S_EXP" WHERE "RunId" = {run} AND "Src" = 'WWHIST' 
'@)
$Qs.Add('13_jv', @'
SELECT "FcCode", "TransCode", "Status", "BatchNum", "RunId", "Debit", "Credit" FROM "MTC_CA_JV" WHERE "FcCode" = '{fc}' 
'@)
$DropCols = @('CardCode', 'CardName', 'ItemName', 'Memo', 'Comments', 'Ref1', 'Ref2', 'Ref3', 'UserSign', 'Creator', 'PlanUser', 'PlanNote', 'CreateUser', 'DelUser')

# ---------------- 连接（同 export_masked.ps1）----------------
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
    Warn '提示：ODBC 驱动的位数要和程序一致。如果本机只装了 32 位 HANA Client，请改用 导出140801排查数据_32位.bat。'
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
function Csv([string]$s) {
  if ($s.IndexOfAny([char[]]@(',', '"', "`r", "`n")) -ge 0) { return '"' + $s.Replace('"', '""') + '"' }
  return $s
}
function Fmt($v) {
  if ($v -is [DBNull] -or $v -eq $null) { return '' }
  if ($v -is [DateTime]) { if ($v.TimeOfDay.Ticks -eq 0) { return $v.ToString('yyyy-MM-dd', $inv) } else { return $v.ToString('yyyy-MM-dd HH:mm:ss', $inv) } }
  if ($v -is [IFormattable]) { return $v.ToString($null, $inv) }
  return [string]$v
}

try {
  # ---------------- 选账套 ----------------
  if (-not $Schema) {
    $rs = Q 'SELECT DISTINCT "SCHEMA_NAME" FROM "SYS"."TABLES" WHERE "TABLE_NAME" = ''MTC_CA_WW_HIST'' ORDER BY 1'
    $cands = @(foreach ($r in $rs) { [string]$r[0] })
    if (-not $cands.Count) { throw '没有账套有 MTC_CA_WW_HIST（历史委外差异清单）' }
    $saved = ''
    if (Test-Path $schemaFile) { $saved = ([IO.File]::ReadAllText($schemaFile, $utf8)).Trim() }
    Write-Host ''
    Write-Host '以下账套（SCHEMA）有历史委外差异清单：'
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

  # ---------------- 账期、运行、参数 ----------------
  if (-not $FcCode) {
    $in = (Read-Host '请输入账期（直接回车 = 2026-10）').Trim()
    $FcCode = if ($in) { $in } else { '2026-10' }
  }
  if ($FcCode -notmatch '^\d{4}-\d{2}$') { throw "账期格式不对：$FcCode" }
  $runs = Q 'SELECT "RunId","Status","StartTime" FROM "MTC_CA_RUN" WHERE "FcCode"=? AND "RunType"=''F'' AND IFNULL("Scenario",'''')='''' ORDER BY "RunId"' @($FcCode)
  $lastOk = ''
  foreach ($r in $runs) { if ([string]$r[1] -eq 'OK') { $lastOk = [string]$r[0] } }
  if ($runs.Count) {
    Write-Host ''
    Write-Host "账期 $FcCode 的正式运行（最近 10 次）："
    for ($i = [Math]::Max(0, $runs.Count - 10); $i -lt $runs.Count; $i++) { Write-Host ("  #{0,-6} {1,-8} {2}" -f $runs[$i][0], $runs[$i][1], (Fmt $runs[$i][2])) }
  }
  if (-not $RunId) {
    $prompt = if ($lastOk) { "导出哪次运行（直接回车 = 最近一次成功 #$lastOk）" } else { '导出哪次运行（输入运行号）' }
    $in = (Read-Host $prompt).Trim().TrimStart('#')
    $RunId = if ($in) { $in } else { $lastOk }
  }
  if ($RunId -notmatch '^\d+$') { throw "$FcCode 没有成功的正式运行，请输入运行号" }

  $one = { param($sql, $vals) $x = Q $sql $vals; if ($x.Count) { Fmt $x[0][0] } else { '' } }
  $P = [ordered]@{
    run  = $RunId
    fc   = $FcCode
    boot = & $one 'SELECT "MTC_CA_F_PARAM"(''BOOTSTRAP_FC'', ?) FROM DUMMY' @($FcCode)
    acct = & $one 'SELECT "MTC_CA_F_ACCT"(''WW_MAT'', ?) FROM DUMMY' @($FcCode)
    wwwt = & $one 'SELECT IFNULL("MTC_CA_F_PARAM"(''WW_WORTYPES'', ?), '',50,'') FROM DUMMY' @($FcCode)
    d1   = & $one 'SELECT TO_NVARCHAR(MAX(TO_DATE("T_RefDate")), ''YYYY-MM-DD'') FROM "OFPR" WHERE "Code"=?' @($FcCode)
  }
  Info ("账套 $Schema，账期 $FcCode，运行 #$($P.run)，承接账期 $($P.boot)，科目 $($P.acct)，期末 $($P.d1)")
  foreach ($k in @('boot', 'acct', 'd1')) { if (-not $P[$k]) { throw "取不到参数 $k" } }

  # ---------------- 导出 ----------------
  $outDir = Join-Path (Join-Path $root '排查数据') ('ww140801_{0}_{1}' -f $FcCode, (Get-Date -Format 'yyyyMMdd_HHmm'))
  [void](New-Item -ItemType Directory -Path $outDir -Force)
  $notes = New-Object Text.StringBuilder
  [void]$notes.Append("账套 $Schema，导出时间 $(Get-Date -Format 'yyyy-MM-dd HH:mm')`r`n")
  foreach ($k in $P.Keys) { [void]$notes.Append("$k=$($P[$k])`r`n") }
  [void]$notes.Append("`r`n")
  $okCnt = 0; $badCnt = 0
  Write-Host ''
  foreach ($name in $Qs.Keys) {
    $sql = [string]$Qs[$name]
    foreach ($k in $P.Keys) { $sql = $sql.Replace('{' + $k + '}', [string]$P[$k]) }
    $w = New-Object IO.StreamWriter((Join-Path $outDir "$name.csv"), $false, $utf8Bom)
    $cnt = 0
    try {
      $cmd = $conn.CreateCommand(); $cmd.Transaction = $tx; $cmd.CommandText = $sql; $cmd.CommandTimeout = 0
      $rd = $cmd.ExecuteReader()
      try {
        $nc = $rd.FieldCount
        $keep = @(for ($i = 0; $i -lt $nc; $i++) { if ($DropCols -notcontains $rd.GetName($i)) { $i } })
        $w.WriteLine((($keep | ForEach-Object { Csv $rd.GetName($_) }) -join ','))
        while ($rd.Read()) {
          $cells = foreach ($i in $keep) { $v = $null; try { $v = $rd.GetValue($i) } catch { try { $v = $rd.GetString($i) } catch { $v = '?' } }; Csv (Fmt $v) }
          $w.WriteLine(($cells -join ','))
          $cnt++
        }
      } finally { $rd.Close() }
      Write-Host ("  {0,-20} {1,8} 行" -f $name, $cnt)
      [void]$notes.Append("$name`t$cnt`r`n"); $okCnt++
    } catch {
      $badCnt++; Warn "$name 导出失败：$($_.Exception.Message)"; [void]$notes.Append("$name`t导出失败 $($_.Exception.Message)`r`n")
    } finally { $w.Close() }
  }
  [IO.File]::WriteAllText((Join-Path $outDir '说明.txt'), $notes.ToString(), $utf8Bom)
  $zip = "$outDir.zip"
  try { Compress-Archive -Path (Join-Path $outDir '*') -DestinationPath $zip -Force } catch { Warn "打包 zip 失败：$($_.Exception.Message)"; $zip = $null }
  Write-Host ''
  if ($badCnt -eq 0) { Write-Host "==== 导出完成：$okCnt 个文件全部成功 ====" -ForegroundColor Green }
  else { Warn "==== 导出完成：$okCnt 个成功，$badCnt 个失败（见上面黄色行和 说明.txt，把失败信息发给 AI）====" }
  Info "已导出到：$outDir"
  if ($zip) { Info "压缩包：$zip （把这个文件拷到 Mac 项目的 排查数据 文件夹里即可）" }
  Start-Process explorer.exe (Split-Path -Parent $outDir)
} catch {
  Err "出错：$($_.Exception.Message)"
} finally {
  try { $tx.Rollback() } catch { }
  $conn.Dispose()
}
Read-Host '按回车退出'
