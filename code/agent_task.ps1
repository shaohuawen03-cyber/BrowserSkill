# agent_task.ps1 - stage 5 PHASE G: the full Agent-mode run (resume version).
# Fired after arena.ai is reachable again. Chain: fresh window -> render wait
# -> Agent mode (AU recipe) -> repo mqgg5630-cyber/BrowserSkill -> fill the
# prompt (read UTF-8 from results/status/arena_prompt.txt; Chinese stays out
# of this ASCII-gated .ps1) -> verify -> Send -> wait for the reply/echo and
# capture evidence. Session stays OPEN so later rounds can follow progress.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

$bsk = Join-Path $env:USERPROFILE '.local\bin\bsk.exe'
if (-not (Test-Path -LiteralPath $bsk)) {
    $f = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bsk = $f.FullName }
}
$outDir = Join-Path (Get-Location).Path 'results\jobs\browser\phaseG'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$logPath = Join-Path $outDir 'phaseG.log'
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

# 0. fresh window (the wedged-window law)
$null = (& $bsk session stop --all 2>&1 | Out-String)
$st = (& $bsk session start --name 'arena-agent-run' --json 2>&1 | Out-String)
$m = [regex]::Match($st, '"session_id"\s*:\s*"([^"]+)"')
if (-not $m.Success) { $m = [regex]::Match($st, '"id"\s*:\s*"([^"]+)"') }
$sid = ''
if ($m.Success) { $sid = $m.Groups[1].Value }
if (-not $sid) { Log '[FAIL] no session'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
$sid | Set-Content -LiteralPath (Join-Path (Get-Location).Path 'results\status\bsk_session.txt') -Encoding Ascii
Log ('phaseG: fresh session ' + $sid)

# 1. render wait (up to ~120s, reload at 50s)
$rendered = $false
for ($i = 1; $i -le 12; $i++) {
    if ($i -eq 1) { $null = (& $bsk navigate 'https://arena.ai' --session $sid 2>&1 | Out-String) }
    $null = (& $bsk wait-ms 10s --session $sid 2>&1 | Out-String)
    $s0 = Snap ('g_s0_poll' + $i + '.txt')
    if (Test-Rendered $s0) { $rendered = $true; Log ('phaseG: rendered at poll ' + $i); break }
    if ($i -eq 5) { $null = (& $bsk reload --session $sid 2>&1 | Out-String) }
}
if (-not $rendered) { Log '[FAIL] arena.ai still not rendering - nothing to automate yet'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }

# 2. promo + Agent mode
$hideRef = [regex]::Match($s0, '@(e\d+) button "Hide this').Groups[1].Value
if ($hideRef) {
    $null = (& $bsk click ('@' + $hideRef) --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 2s --session $sid 2>&1 | Out-String)
    $s0 = Snap 'g_nopromo.txt'
}
if (-not (($s0 -match 'combobox[^\r\n]*="Agent"') -or ($s0 -match '\[. active: Agent'))) {
    $done = $false
    foreach ($r in @('AU', 'AD', 'TA')) {
        $cbRef = [regex]::Match($s0, '@(e\d+) combobox').Groups[1].Value
        if (-not $cbRef) { $s0 = Snap 'g_refind.txt'; $cbRef = [regex]::Match($s0, '@(e\d+) combobox').Groups[1].Value }
        $null = (& $bsk click ('@' + $cbRef) --session $sid 2>&1 | Out-String)
        $null = (& $bsk wait-ms 1500ms --session $sid 2>&1 | Out-String)
        if ($r -eq 'AU') { $null = (& $bsk press ArrowUp --session $sid 2>&1 | Out-String) }
        elseif ($r -eq 'AD') { $null = (& $bsk press ArrowDown --session $sid 2>&1 | Out-String) }
        else { $null = (& $bsk press a --session $sid 2>&1 | Out-String) }
        $null = (& $bsk wait-ms 400ms --session $sid 2>&1 | Out-String)
        $null = (& $bsk press Enter --session $sid 2>&1 | Out-String)
        $null = (& $bsk wait-ms 2500ms --session $sid 2>&1 | Out-String)
        $s0 = Snap ('g_after_' + $r + '.txt')
        if (($s0 -match 'combobox[^\r\n]*="Agent"') -or ($s0 -match '\[. active: Agent')) { $done = $true; Log ('phaseG: Agent via ' + $r); break }
    }
    if (-not $done) { Log '[FAIL] mode flip failed'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
} else {
    Log 'phaseG: already Agent'
}

# 3. repo: mqgg5630-cyber/BrowserSkill
$s2 = Snap 'g_s_agent.txt'
for ($i = 1; $i -le 6; $i++) {
    if ($s2 -notmatch 'Loading\.\.\.') { break }
    $null = (& $bsk wait-ms 5s --session $sid 2>&1 | Out-String)
    $s2 = Snap ('g_repo_poll' + $i + '.txt')
}
$repoRef = [regex]::Match($s2, '@(e\d+) (?:combobox|button)[^\r\n]*(?:Loading|repository|BrowserSkill|mqgg5630)').Groups[1].Value
Log ('phaseG: repo dropdown @' + $repoRef)
$sel = $false
if ($repoRef) {
    $null = (& $bsk click ('@' + $repoRef) --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 2500ms --session $sid 2>&1 | Out-String)
    $s3 = Snap 'g_repo_menu.txt'
    if (-not (($s3 -match 'option') -or ($s3 -match 'BrowserSkill'))) {
        $null = (& $bsk click ('@' + $repoRef) --session $sid 2>&1 | Out-String)
        $null = (& $bsk wait-ms 2000ms --session $sid 2>&1 | Out-String)
        $s3 = Snap 'g_repo_menu_retry.txt'
    }
    $optBtn = [regex]::Match($s3, '@(e\d+) button "[^"]*BrowserSkill').Groups[1].Value
    if ($optBtn) {
        $null = (& $bsk click ('@' + $optBtn) --session $sid 2>&1 | Out-String)
        Log ('phaseG: clicked option button @' + $optBtn)
    } else {
        $optRef = [regex]::Match($s3, '@(e\d+) option "[^"]*BrowserSkill').Groups[1].Value
        if ($optRef) { $null = (& $bsk click ('@' + $optRef) --session $sid 2>&1 | Out-String); Log ('phaseG: clicked option @' + $optRef) }
        else { $null = (& $bsk press b --session $sid 2>&1 | Out-String); $null = (& $bsk wait-ms 400ms --session $sid 2>&1 | Out-String); $null = (& $bsk press Enter --session $sid 2>&1 | Out-String) }
    }
    $null = (& $bsk wait-ms 3000ms --session $sid 2>&1 | Out-String)
    $s4 = Snap 'g_after_repo.txt'
    $sel = ($s4 -match 'combobox[^\r\n]*BrowserSkill') -or ($s4 -match 'mqgg5630-cyber/BrowserSkill')
    if ($sel) { Log 'phaseG: repo selected' } else { Log 'phaseG: WARN repo selection unconfirmed - continuing' }
} else {
    Log 'phaseG: WARN no repo dropdown found - continuing (repo may already be set)'
}

# 4. fill the prompt (UTF-8 file) and verify it sticks
$promptFile = Join-Path (Get-Location).Path 'results\status\arena_prompt.txt'
$msg = (Get-Content -LiteralPath $promptFile -Raw -Encoding UTF8).Trim()
Log ('phaseG: prompt chars=' + $msg.Length)
$s5 = Snap 'g_before_fill.txt'
$tbRef = [regex]::Match($s5, '@(e\d+) textbox').Groups[1].Value
Log ('phaseG: textbox @' + $tbRef)
$null = (& $bsk fill ('@' + $tbRef) --value $msg --session $sid 2>&1 | Out-String)
Log ('phaseG: fill exit ' + $LASTEXITCODE)
$null = (& $bsk wait-ms 1s --session $sid 2>&1 | Out-String)
$s6 = Snap 'g_after_fill.txt'
if ($s6 -match 'textbox[^\r\n]*\[empty\]') {
    Log 'phaseG: fill did not stick - click-focus + retry'
    $null = (& $bsk click ('@' + $tbRef) --session $sid 2>&1 | Out-String)
    $null = (& $bsk fill 'textarea' --value $msg --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 1s --session $sid 2>&1 | Out-String)
    $s6 = Snap 'g_after_fill2.txt'
}
if ($s6 -match 'textbox[^\r\n]*\[empty\]') { Log '[FAIL] composer will not hold the prompt'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
Log 'phaseG: prompt verified in composer'

# 5. send via the Send button
$sendRef = [regex]::Match($s6, '@(e\d+) button "Send message').Groups[1].Value
if ($sendRef) {
    $null = (& $bsk click ('@' + $sendRef) --session $sid 2>&1 | Out-String)
    Log ('phaseG: clicked Send @' + $sendRef)
} else {
    $null = (& $bsk press Enter --session $sid 2>&1 | Out-String)
    Log ('phaseG: Enter fallback')
}

# 6. confirm the echo and the agent starting to work
$echo = $false
for ($i = 1; $i -le 4; $i++) {
    $null = (& $bsk wait-ms 12s --session $sid 2>&1 | Out-String)
    $sx = Snap ('g_send_poll' + $i + '.txt')
    if ($sx -match '01a0aeb9') { $echo = $true; Log ('phaseG: prompt echo visible at poll ' + $i); break }
}
if (-not $echo) { Log 'phaseG: WARN no echo found - state captured' }
$null = (& $bsk wait-ms 30s --session $sid 2>&1 | Out-String)
$null = Snap 'g_progress1.txt'
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'g_final.png') 2>&1 | Out-String)
Log 'phaseG: done - agent conversation started, session left OPEN for follow-ups'
$lines | Set-Content -LiteralPath $logPath -Encoding UTF8
exit 0
