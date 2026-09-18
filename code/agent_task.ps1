# agent_task.ps1 - stage 6 PHASE M2: re-borrow monitor.
# The borrowed-tab session dies between rounds (idle limit), returning the
# tab home - but the arena conversation itself keeps running there. M2 does a
# complete borrow-monitor-release cycle per round: fresh session -> borrow
# (confirm off = silent) -> poll up to ~8 min for PS-block markers ->
# extract full page text -> screenshot -> exit (session closes, tab returns).
# The agent reads MONITOR: FOUND / NOT_YET and the extracted text file.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

$bsk = Join-Path $env:USERPROFILE '.local\bin\bsk.exe'
if (-not (Test-Path -LiteralPath $bsk)) {
    $f = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bsk = $f.FullName }
}
$outDir = Join-Path (Get-Location).Path 'results\jobs\browser\phaseM2'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$logPath = Join-Path $outDir 'phaseM2.log'
$lines = New-Object System.Collections.Generic.List[string]
function Log([string]$s) { $script:lines.Add($s) | Out-Null; Write-Output $s }

$env:BSK_AUTO_START = '0'
$null = (& $bsk session stop --all 2>&1 | Out-String)
$st = (& $bsk session start --name 'arena-monitor' --json 2>&1 | Out-String)
$m = [regex]::Match($st, '"session_id"\s*:\s*"([^"]+)"')
if (-not $m.Success) { $m = [regex]::Match($st, '"id"\s*:\s*"([^"]+)"') }
$sid = ''
if ($m.Success) { $sid = $m.Groups[1].Value }
if (-not $sid) { Log '[FAIL] no session'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
$sid | Set-Content -LiteralPath (Join-Path (Get-Location).Path 'results\status\bsk_session.txt') -Encoding Ascii
Log ('phaseM2: session ' + $sid)

$tabs = (& $bsk tab list --session $sid --json 2>&1 | Out-String)
$tabs | Set-Content -LiteralPath (Join-Path $outDir 'm2_tabs.json') -Encoding UTF8
$tid = ''
foreach ($mm in [regex]::Matches($tabs, '\{[^{}]*\}')) {
    if ($mm.Value -match 'arena\.ai') {
        $cand = [regex]::Match($mm.Value, '"tab_id"\s*:\s*(\d+)').Groups[1].Value
        if ($cand -and -not $tid) { $tid = $cand }
    }
}
Log ('phaseM2: arena tab ' + $tid)
if (-not $tid) { Log '[FAIL] no arena tab - keep arena.ai open'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
$bo = (& $bsk tab borrow $tid --session $sid --timeout 300 2>&1 | Out-String)
Log ('phaseM2: borrow exit ' + $LASTEXITCODE)
if ($LASTEXITCODE -ne 0) { Log '[FAIL] borrow failed'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
$null = (& $bsk tab select $tid --session $sid 2>&1 | Out-String)
$null = (& $bsk wait-ms 5s --session $sid 2>&1 | Out-String)

$found = $false
for ($i = 1; $i -le 25; $i++) {
    $null = (& $bsk evaluate '(function(){var d=document.scrollingElement;d.scrollTop=d.scrollHeight;return d.scrollTop;})()' --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 3s --session $sid 2>&1 | Out-String)
    $s = (& $bsk snapshot --session $sid --max-tokens 30000 2>&1 | Out-String)
    $s | Set-Content -LiteralPath (Join-Path $outDir ('m2_poll' + $i + '.txt')) -Encoding UTF8
    if ((($s -match 'Set-ExecutionPolicy') -and ($s -notmatch 'Stop generating')) -or ($s -match 'watch\.ps1 -Register')) { $found = $true; Log ('phaseM2: FOUND block markers at poll ' + $i); break }
    Log ('phaseM2: poll ' + $i + ' - not yet (bytes=' + $s.Length + ')')
    $null = (& $bsk wait-ms 20s --session $sid 2>&1 | Out-String)
}
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'm2_final.png') 2>&1 | Out-String)
$null = (& $bsk evaluate '(function(){var d=document.scrollingElement;d.scrollTop=d.scrollHeight;return d.scrollTop;})()' --session $sid 2>&1 | Out-String)
$null = (& $bsk wait-ms 3s --session $sid 2>&1 | Out-String)
$t = (& $bsk evaluate document.body.innerText --session $sid 2>&1 | Out-String)
$t | Set-Content -LiteralPath (Join-Path $outDir 'm2_page_text.txt') -Encoding UTF8
Log ('phaseM2: page text bytes=' + $t.Length)
if ($found) { Log 'phaseM2: MONITOR: FOUND' } else { Log 'phaseM2: MONITOR: NOT_YET' }
Log 'phaseM2: done'
$lines | Set-Content -LiteralPath $logPath -Encoding UTF8
exit 0
