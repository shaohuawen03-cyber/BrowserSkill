# agent_task.ps1 - stage 6 PHASE M: monitor the running arena agent.
# The round-1 prompt is IN and arena shows "orchestrating". M reuses the OPEN
# borrowed-tab session (do NOT stop/restart it - that would kill the borrow),
# polls the page every 20s for up to ~8.5 min, saves rolling evidence, and
# extracts the full page text (quote-free innerText evaluate) once a PowerShell
# block (git clone / E:\\0github / auth.ps1) appears. Exit 0 either way; the
# agent reads MONITOR: FOUND / NOT_YET from the log.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

$bsk = Join-Path $env:USERPROFILE '.local\bin\bsk.exe'
if (-not (Test-Path -LiteralPath $bsk)) {
    $f = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bsk = $f.FullName }
}
$outDir = Join-Path (Get-Location).Path 'results\jobs\browser\phaseM'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$logPath = Join-Path $outDir 'phaseM.log'
$lines = New-Object System.Collections.Generic.List[string]
function Log([string]$s) { $script:lines.Add($s) | Out-Null; Write-Output $s }

$env:BSK_AUTO_START = '0'
$sid = ''
$sidFile = Join-Path (Get-Location).Path 'results\status\bsk_session.txt'
if (Test-Path -LiteralPath $sidFile) { $sid = (Get-Content -LiteralPath $sidFile -Raw).Trim() }
$lst = (& $bsk session list --json 2>&1 | Out-String)
if (-not $sid -or $lst -notmatch [regex]::Escape($sid)) {
    Log '[FAIL] the borrowed-tab session is gone - cannot monitor without it'
    $lines | Set-Content -LiteralPath $logPath -Encoding UTF8
    exit 1
}
Log ('phaseM: monitoring session ' + $sid)

$found = $false
for ($i = 1; $i -le 25; $i++) {
    $null = (& $bsk wait-ms 20s --session $sid 2>&1 | Out-String)
    $s = (& $bsk snapshot --session $sid --max-tokens 30000 2>&1 | Out-String)
    $s | Set-Content -LiteralPath (Join-Path $outDir ('m_poll' + $i + '.txt')) -Encoding UTF8
    $log = (& $bsk evaluate document.body.innerText --session $sid 2>&1 | Out-String)
    if ($s -match 'git clone' -or $s -match 'auth\.ps1' -or $s -match 'bootstrap\.ps1') { $found = $true; Log ('phaseM: FOUND block markers at poll ' + $i); break }
    Log ('phaseM: poll ' + $i + ' - not yet (bytes=' + $s.Length + ')')
}
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'm_final.png') 2>&1 | Out-String)

# full text extraction (quote-free JS, PS 5.1-safe)
$t = (& $bsk evaluate document.body.innerText --session $sid 2>&1 | Out-String)
$t | Set-Content -LiteralPath (Join-Path $outDir 'm_page_text.txt') -Encoding UTF8
Log ('phaseM: page text bytes=' + $t.Length)
if ($found) { Log 'phaseM: MONITOR: FOUND' } else { Log 'phaseM: MONITOR: NOT_YET' }
Log 'phaseM: done'
$lines | Set-Content -LiteralPath $logPath -Encoding UTF8
exit 0
