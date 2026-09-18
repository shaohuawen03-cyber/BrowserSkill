# agent_task.ps1 - stage 6 PHASE I: the direct /agent run (user guidance).
# https://arena.ai/agent defaults to AGENT mode and pre-selects the last-used
# GitHub repo - no mode flip, no repo picker. I: fresh window -> navigate
# straight to /agent -> render wait -> log the defaults -> fill the round-1
# prompt (UTF-8 file) -> verify -> send -> confirm echo + early progress.
# Session stays OPEN so round 2 can be sent into the same conversation.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

$bsk = Join-Path $env:USERPROFILE '.local\bin\bsk.exe'
if (-not (Test-Path -LiteralPath $bsk)) {
    $f = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bsk = $f.FullName }
}
$outDir = Join-Path (Get-Location).Path 'results\jobs\browser\phaseI'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$logPath = Join-Path $outDir 'phaseI.log'
$lines = New-Object System.Collections.Generic.List[string]
function Log([string]$s) { $script:lines.Add($s) | Out-Null; Write-Output $s }
function Snap([string]$name) {
    $s = (& $bsk snapshot --session $script:sid --max-tokens 30000 2>&1 | Out-String)
    $s | Set-Content -LiteralPath (Join-Path $outDir $name) -Encoding UTF8
    return $s
}
function Test-Rendered([string]$s) {
    return ($s -match 'Ask anything') -or ($s -match 'combobox') -or ($s -match 'What would you like')
}

$env:BSK_AUTO_START = '0'
$null = (& $bsk session stop --all 2>&1 | Out-String)
$st = (& $bsk session start --name 'arena-agent-direct' --json 2>&1 | Out-String)
$m = [regex]::Match($st, '"session_id"\s*:\s*"([^"]+)"')
if (-not $m.Success) { $m = [regex]::Match($st, '"id"\s*:\s*"([^"]+)"') }
$sid = ''
if ($m.Success) { $sid = $m.Groups[1].Value }
if (-not $sid) { Log '[FAIL] no session'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
$sid | Set-Content -LiteralPath (Join-Path (Get-Location).Path 'results\status\bsk_session.txt') -Encoding Ascii
Log ('phaseI: fresh session ' + $sid)

# 1. straight to /agent + patient render wait
$rendered = $false
for ($i = 1; $i -le 12; $i++) {
    if ($i -eq 1) { $null = (& $bsk navigate 'https://arena.ai/agent' --session $sid 2>&1 | Out-String) }
    $null = (& $bsk wait-ms 10s --session $sid 2>&1 | Out-String)
    $s0 = Snap ('i_s0_poll' + $i + '.txt')
    if (Test-Rendered $s0) { $rendered = $true; Log ('phaseI: rendered at poll ' + $i); break }
    if ($i -eq 5 -or $i -eq 9) { Log ('phaseI: poll ' + $i + ' no render - reload'); $null = (& $bsk reload --session $sid 2>&1 | Out-String) }
}
if (-not $rendered) { Log '[FAIL] /agent not rendering'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'i_rendered.png') 2>&1 | Out-String)

# 2. log the defaults (mode pill + repo combo)
$mode = [regex]::Match($s0, '@e\d+ combobox "([^"]*)"').Groups[1].Value
Log ('phaseI: mode combobox reads: ' + $mode)
$repoLine = [regex]::Match($s0, '@e\d+ combobox[^\r\n]*(?:BrowserSkill|mqgg5630|Loading)[^\r\n]*').Value
Log ('phaseI: repo combo line: ' + $repoLine.Substring(0, [Math]::Min(120, $repoLine.Length)))

# 3. promo
$hideRef = [regex]::Match($s0, '@(e\d+) button "Hide this').Groups[1].Value
if ($hideRef) {
    $null = (& $bsk click ('@' + $hideRef) --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 2s --session $sid 2>&1 | Out-String)
    $s0 = Snap 'i_nopromo.txt'
    Log ('phaseI: hid promo @' + $hideRef)
}

# 4. fill the round-1 prompt + verify
$promptFile = Join-Path (Get-Location).Path 'results\status\arena_prompt.txt'
$msg = (Get-Content -LiteralPath $promptFile -Raw -Encoding UTF8).Trim()
Log ('phaseI: prompt chars=' + $msg.Length)
$tbRef = [regex]::Match($s0, '@(e\d+) textbox').Groups[1].Value
Log ('phaseI: textbox @' + $tbRef)
$null = (& $bsk fill ('@' + $tbRef) --value $msg --session $sid 2>&1 | Out-String)
Log ('phaseI: fill exit ' + $LASTEXITCODE)
$null = (& $bsk wait-ms 1s --session $sid 2>&1 | Out-String)
$s6 = Snap 'i_after_fill.txt'
if ($s6 -match 'textbox[^\r\n]*\[empty\]') {
    Log 'phaseI: fill did not stick - click-focus retry'
    $null = (& $bsk click ('@' + $tbRef) --session $sid 2>&1 | Out-String)
    $null = (& $bsk fill 'textarea' --value $msg --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 1s --session $sid 2>&1 | Out-String)
    $s6 = Snap 'i_after_fill2.txt'
}
if ($s6 -match 'textbox[^\r\n]*\[empty\]') { Log '[FAIL] composer will not hold the prompt'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
Log 'phaseI: prompt verified in composer'

# 5. send
$sendRef = [regex]::Match($s6, '@(e\d+) button "Send message').Groups[1].Value
if ($sendRef) {
    $null = (& $bsk click ('@' + $sendRef) --session $sid 2>&1 | Out-String)
    Log ('phaseI: clicked Send @' + $sendRef)
} else {
    $null = (& $bsk press Enter --session $sid 2>&1 | Out-String)
    Log 'phaseI: Enter fallback'
}

# 6. echo + early progress
$echo = $false
for ($i = 1; $i -le 4; $i++) {
    $null = (& $bsk wait-ms 12s --session $sid 2>&1 | Out-String)
    $sx = Snap ('i_send_poll' + $i + '.txt')
    if ($sx -match '01a0aeb9') { $echo = $true; Log ('phaseI: prompt echo at poll ' + $i); break }
}
if (-not $echo) { Log 'phaseI: WARN no echo yet' }
$null = (& $bsk wait-ms 30s --session $sid 2>&1 | Out-String)
$null = Snap 'i_progress1.txt'
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'i_sent.png') 2>&1 | Out-String)
Log 'phaseI: done - round-1 prompt sent; session OPEN for round 2'
$lines | Set-Content -LiteralPath $logPath -Encoding UTF8
exit 0
