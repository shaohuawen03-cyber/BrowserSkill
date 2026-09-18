# agent_task.ps1 - stage 2 PHASE A: drive the browser via the LOCAL daemon
# (bsk on THIS machine): open arena.ai in an Agent Window and capture an
# aria-snapshot + screenshot. Reconnaissance round - no typing yet; the agent
# reads the artifacts and scripts phase B (the actual chat) from real refs.
# Idempotent; leaves the session OPEN for phase B.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)   # repo root

$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$bsk = Join-Path $env:USERPROFILE '.local\bin\bsk.exe'
if (-not (Test-Path -LiteralPath $bsk)) {
    $f = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bsk = $f.FullName }
}
if (-not (Test-Path -LiteralPath $bsk)) { Write-Output '[FAIL] bsk.exe not found'; exit 1 }

$outDir = Join-Path (Get-Location).Path 'results\jobs\browser'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$logPath = Join-Path $outDir 'phaseA.log'
$lines = New-Object System.Collections.Generic.List[string]
function Log([string]$s) { $script:lines.Add($s) | Out-Null; Write-Output $s }
function Clip([string]$s, [int]$n) {
    $t = ($s -replace '\s+', ' ').Trim()
    if ($t.Length -gt $n) { return $t.Substring(0, $n) + ' ...' }
    return $t
}

Log ('task: bsk=' + $bsk)
$env:BSK_AUTO_START = '0'   # never spawn a second daemon from a task

# 0. a connected browser must be present; if not, try to (re)start the daemon once
$br = (& $bsk browsers --json 2>&1 | Out-String)
$br | Set-Content -LiteralPath (Join-Path $outDir 'browsers.json') -Encoding UTF8
Log ('task: browsers -> ' + (Clip $br 300))
if ($br -notmatch '"instance_id"') {
    Log 'task: no browser visible - trying daemon start once'
    $null = (& $bsk daemon start 2>&1 | Out-String)
    Start-Sleep -Seconds 5
    $br = (& $bsk browsers --json 2>&1 | Out-String)
    $br | Set-Content -LiteralPath (Join-Path $outDir 'browsers.json') -Encoding UTF8
    Log ('task: browsers retry -> ' + (Clip $br 300))
}
if ($br -notmatch '"instance_id"') {
    Log '[FAIL] no browser connected to the local daemon (extension popup must show Ready)'
    $lines | Set-Content -LiteralPath $logPath -Encoding UTF8
    exit 1
}

# 1. reuse a live session if possible, else open a new Agent Window
$sid = ''
$lst = (& $bsk session list --json 2>&1 | Out-String)
$lst | Set-Content -LiteralPath (Join-Path $outDir 'sessions.json') -Encoding UTF8
$m = [regex]::Match($lst, '"session_id"\s*:\s*"([^"]+)"')
if (-not $m.Success) { $m = [regex]::Match($lst, '"id"\s*:\s*"([^"]+)"') }
if ($m.Success) { $sid = $m.Groups[1].Value; Log ('task: reusing session ' + $sid) }
if (-not $sid) {
    $st = (& $bsk session start --no-focus --name 'arena-ai-task' --json 2>&1 | Out-String)
    $st | Set-Content -LiteralPath (Join-Path $outDir 'session_start.json') -Encoding UTF8
    $m = [regex]::Match($st, '"session_id"\s*:\s*"([^"]+)"')
    if (-not $m.Success) { $m = [regex]::Match($st, '"id"\s*:\s*"([^"]+)"') }
    if ($m.Success) { $sid = $m.Groups[1].Value }
    if (-not $sid) {
        Log ('[FAIL] could not start a session: ' + (Clip $st 300))
        $lines | Set-Content -LiteralPath $logPath -Encoding UTF8
        exit 1
    }
    Log ('task: started session ' + $sid)
}
$sid | Set-Content -LiteralPath (Join-Path (Get-Location).Path 'results\status\bsk_session.txt') -Encoding Ascii

# 2. navigate to arena.ai and let it settle
$nav = (& $bsk navigate 'https://arena.ai' --session $sid 2>&1 | Out-String)
Log ('task: navigate -> ' + (Clip $nav 200))
$null = (& $bsk wait-ms 8s --session $sid 2>&1 | Out-String)

# 3. capture evidence: aria snapshot + screenshot
$snap = (& $bsk snapshot --session $sid --max-tokens 20000 2>&1 | Out-String)
$snap | Set-Content -LiteralPath (Join-Path $outDir 'arena_snapshot.txt') -Encoding UTF8
Log ('task: snapshot bytes=' + $snap.Length)
$shot = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'arena_page.png') 2>&1 | Out-String)
Log ('task: screenshot -> ' + (Clip $shot 200))

# 4. session stays OPEN for phase B
Log 'task: phase A done (session left open for phase B)'
$lines | Set-Content -LiteralPath $logPath -Encoding UTF8
exit 0
