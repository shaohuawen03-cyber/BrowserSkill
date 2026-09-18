# agent_task.ps1 - stage 4 PHASE F5: console evidence + site-data repair.
# F4 proved: window healthy, arena HTML arrives (524KB), body stays empty ->
# client-side JS crash. Prime suspects: a poisoned service worker / cache /
# localStorage. F5: read the buffered console exceptions (evidence), clear
# localStorage + sessionStorage (sync), unregister service workers + clear
# CacheStorage (async, fire-and-forget then verify), reload, poll render.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

$bsk = Join-Path $env:USERPROFILE '.local\bin\bsk.exe'
if (-not (Test-Path -LiteralPath $bsk)) {
    $f = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bsk = $f.FullName }
}
$outDir = Join-Path (Get-Location).Path 'results\jobs\browser\phaseF5'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$logPath = Join-Path $outDir 'phaseF5.log'
$lines = New-Object System.Collections.Generic.List[string]
function Log([string]$s) { $script:lines.Add($s) | Out-Null; Write-Output $s }
function Snap([string]$name) {
    $s = (& $bsk snapshot --session $script:sid --max-tokens 30000 2>&1 | Out-String)
    $s | Set-Content -LiteralPath (Join-Path $outDir $name) -Encoding UTF8
    return $s
}
function Test-Rendered([string]$s) {
    return ($s -match 'Ask anything') -or ($s -match 'combobox') -or ($s -match 'Get started')
}

$env:BSK_AUTO_START = '0'
$sid = ''
$sidFile = Join-Path (Get-Location).Path 'results\status\bsk_session.txt'
if (Test-Path -LiteralPath $sidFile) { $sid = (Get-Content -LiteralPath $sidFile -Raw).Trim() }
$lst = (& $bsk session list --json 2>&1 | Out-String)
if (-not $sid -or $lst -notmatch [regex]::Escape($sid)) {
    $null = (& $bsk session stop --all 2>&1 | Out-String)
    $st = (& $bsk session start --name 'arena-repair' --json 2>&1 | Out-String)
    $m = [regex]::Match($st, '"session_id"\s*:\s*"([^"]+)"')
    if (-not $m.Success) { $m = [regex]::Match($st, '"id"\s*:\s*"([^"]+)"') }
    if ($m.Success) { $sid = $m.Groups[1].Value } else { Log '[FAIL] no session'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
    $sid | Set-Content -LiteralPath $sidFile -Encoding Ascii
}
Log ('phaseF5: session ' + $sid)

# 0. on the crashed arena page
$null = (& $bsk navigate 'https://arena.ai' --session $sid 2>&1 | Out-String)
$null = (& $bsk wait-ms 15s --session $sid 2>&1 | Out-String)

# 1. console evidence (the buffered exceptions)
$cons = (& $bsk console --session $sid 2>&1 | Out-String)
$cons | Set-Content -LiteralPath (Join-Path $outDir 'f5_console.txt') -Encoding UTF8
Log ('phaseF5: console bytes=' + $cons.Length)
foreach ($ln in ($cons -split "`r?`n")) {
    if ($ln -match 'error|Error|Uncaught|exception|Failed') { Log ('phaseF5: CONSOLE ' + $ln.Trim().Substring(0, [Math]::Min(150, $ln.Trim().Length))) }
}

# 2. sync clears
$r1 = (& $bsk evaluate 'localStorage.clear() && sessionStorage.clear() && "stores cleared"' --session $sid 2>&1 | Out-String)
Log ('phaseF5: clear stores -> ' + (($r1 -replace '\s+', ' ').Trim().Substring(0, [Math]::Min(80, $r1.Trim().Length))))

# 3. async clears (fire and forget, then give them a moment)
$null = (& $bsk evaluate 'navigator.serviceWorker.getRegistrations().then(function(a){a.forEach(function(r){r.unregister()});return a.length})' --session $sid 2>&1 | Out-String)
$null = (& $bsk evaluate 'caches.keys().then(function(k){k.forEach(function(n){caches.delete(n)})}); "caches ok"' --session $sid 2>&1 | Out-String)
$null = (& $bsk wait-ms 3s --session $sid 2>&1 | Out-String)
$sw = (& $bsk evaluate 'navigator.serviceWorker.getRegistrations().then(function(a){return a.length})' --session $sid 2>&1 | Out-String)
Log ('phaseF5: sw registrations after clear -> ' + (($sw -replace '\s+', ' ').Trim().Substring(0, [Math]::Min(60, $sw.Trim().Length))))

# 4. hard reload + poll
$null = (& $bsk reload --session $sid 2>&1 | Out-String)
$ok = $false
for ($i = 1; $i -le 8; $i++) {
    $null = (& $bsk wait-ms 10s --session $sid 2>&1 | Out-String)
    $a = Snap ('f5_after_poll' + $i + '.txt')
    if (Test-Rendered $a) { $ok = $true; Log ('phaseF5: RENDERED at poll ' + $i); break }
}
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'f5_state.png') 2>&1 | Out-String)

# 5. if still dead, one more console read for the fresh crash
if (-not $ok) {
    $cons2 = (& $bsk console --session $sid 2>&1 | Out-String)
    $cons2 | Set-Content -LiteralPath (Join-Path $outDir 'f5_console_after.txt') -Encoding UTF8
    Log ('phaseF5: still dead - console-after bytes=' + $cons2.Length)
    foreach ($ln in ($cons2 -split "`r?`n")) {
        if ($ln -match 'error|Error|Uncaught|exception|Failed') { Log ('phaseF5: AFTER ' + $ln.Trim().Substring(0, [Math]::Min(150, $ln.Trim().Length))) }
    }
}
Log ('phaseF5: RESULT rendered=' + $ok)
Log 'phaseF5: done'
$lines | Set-Content -LiteralPath $logPath -Encoding UTF8
exit 0
