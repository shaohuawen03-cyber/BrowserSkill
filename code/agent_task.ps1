# agent_task.ps1 - stage 2 PHASE B: adaptive chat attempt on arena.ai.
# Reuses the phase-A session, waits for the SPA to fully render, locates the
# chat input (textarea or contenteditable), types a test message, presses
# Enter, waits for the AI reply and captures snapshot + screenshot + reply
# text. Every step is logged with its exit code; a failed send does NOT abort
# the round - diagnostics come back either way.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)   # repo root

$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$bsk = Join-Path $env:USERPROFILE '.local\bin\bsk.exe'
if (-not (Test-Path -LiteralPath $bsk)) {
    $f = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bsk = $f.FullName }
}
if (-not (Test-Path -LiteralPath $bsk)) { Write-Output '[FAIL] bsk.exe not found'; exit 1 }

$outDir = Join-Path (Get-Location).Path 'results\jobs\browser\phaseB'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$logPath = Join-Path $outDir 'phaseB.log'
$lines = New-Object System.Collections.Generic.List[string]
function Log([string]$s) { $script:lines.Add($s) | Out-Null; Write-Output $s }
function Clip([string]$s, [int]$n) {
    $t = ($s -replace '\s+', ' ').Trim()
    if ($t.Length -gt $n) { return $t.Substring(0, $n) + ' ...' }
    return $t
}

$env:BSK_AUTO_START = '0'
$sid = ''
$sidFile = Join-Path (Get-Location).Path 'results\status\bsk_session.txt'
if (Test-Path -LiteralPath $sidFile) { $sid = (Get-Content -LiteralPath $sidFile -Raw).Trim() }

# 0. session: reuse if alive, else open a new Agent Window
if ($sid) {
    $lst = (& $bsk session list --json 2>&1 | Out-String)
    if ($lst -match [regex]::Escape($sid)) {
        Log ('phaseB: reusing session ' + $sid)
    } else {
        Log 'phaseB: previous session gone - starting a new one'
        $sid = ''
    }
}
if (-not $sid) {
    $st = (& $bsk session start --no-focus --name 'arena-ai-chat' --json 2>&1 | Out-String)
    $st | Set-Content -LiteralPath (Join-Path $outDir 'session_start.json') -Encoding UTF8
    $m = [regex]::Match($st, '"session_id"\s*:\s*"([^"]+)"')
    if (-not $m.Success) { $m = [regex]::Match($st, '"id"\s*:\s*"([^"]+)"') }
    if ($m.Success) { $sid = $m.Groups[1].Value }
    if (-not $sid) { Log ('[FAIL] no session: ' + (Clip $st 250)); $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
    $sid | Set-Content -LiteralPath $sidFile -Encoding Ascii
    Log ('phaseB: started session ' + $sid)
}

# 1. reload arena.ai and let the SPA fully render
$null = (& $bsk navigate 'https://arena.ai' --session $sid 2>&1 | Out-String)
$null = (& $bsk wait-ms 15s --session $sid 2>&1 | Out-String)
Log 'phaseB: navigated, waited 15s'

# 2. recon: snapshot + screenshot + input candidates
$snap1 = (& $bsk snapshot --session $sid --max-tokens 30000 2>&1 | Out-String)
$snap1 | Set-Content -LiteralPath (Join-Path $outDir 'snapshot_before.txt') -Encoding UTF8
Log ('phaseB: snapshot_before bytes=' + $snap1.Length)
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'before.png') 2>&1 | Out-String)
$probe = '(function(){var ta=document.querySelector("textarea");var ce=document.querySelector("[contenteditable=\"true\"]");var btns=[].slice.call(document.querySelectorAll("button")).map(function(b){return (b.getAttribute("aria-label")||b.innerText||"").slice(0,30)}).filter(Boolean).slice(0,12);return JSON.stringify({textarea:!!ta,ph:(ta&&ta.placeholder)||"",contenteditable:!!ce,buttons:btns});})()'
$ev1 = (& $bsk evaluate $probe --session $sid 2>&1 | Out-String)
$ev1 | Set-Content -LiteralPath (Join-Path $outDir 'probe.json') -Encoding UTF8
Log ('phaseB: probe -> ' + (Clip $ev1 400))

# 3. type the test message and send
$msg = 'Hello! This message was sent by BrowserSkill browser automation (bsk CLI) as a connectivity test. Please reply with one short sentence.'
$sent = $false
$null = (& $bsk fill --selector 'textarea' --value $msg --session $sid 2>&1 | Out-String)
if ($LASTEXITCODE -eq 0) {
    $sent = $true; Log 'phaseB: filled textarea'
} else {
    $null = (& $bsk fill --selector '[contenteditable="true"]' --value $msg --session $sid 2>&1 | Out-String)
    if ($LASTEXITCODE -eq 0) { $sent = $true; Log 'phaseB: filled contenteditable' }
    else { Log 'phaseB: WARN no input could be filled (page may need a mode/model pick first)' }
}
if ($sent) {
    $null = (& $bsk press Enter --session $sid 2>&1 | Out-String)
    Log ('phaseB: Enter pressed, exit ' + $LASTEXITCODE)
    $null = (& $bsk wait-ms 20s --session $sid 2>&1 | Out-String)
    Log 'phaseB: waited 20s for the reply'
} else {
    $null = (& $bsk wait-ms 5s --session $sid 2>&1 | Out-String)
}

# 4. after: snapshot + screenshot + visible text extract
$snap2 = (& $bsk snapshot --session $sid --max-tokens 30000 2>&1 | Out-String)
$snap2 | Set-Content -LiteralPath (Join-Path $outDir 'snapshot_after.txt') -Encoding UTF8
Log ('phaseB: snapshot_after bytes=' + $snap2.Length)
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'after.png') 2>&1 | Out-String)
$ext = '(function(){var t=(document.querySelector("main")||document.body).innerText;return t.slice(-3000);})()'
$ev2 = (& $bsk evaluate $ext --session $sid 2>&1 | Out-String)
$ev2 | Set-Content -LiteralPath (Join-Path $outDir 'page_text.txt') -Encoding UTF8
Log ('phaseB: page_text bytes=' + $ev2.Length)
Log 'phaseB: done'
$lines | Set-Content -LiteralPath $logPath -Encoding UTF8
exit 0
