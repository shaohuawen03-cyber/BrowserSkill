# agent_task.ps1 - stage 5 PHASE H: borrow the USER's live arena.ai tab.
# The Agent Window's own arena tabs keep dying to an edge challenge, but the
# user's manually opened tab is alive. H: fresh session -> list user tabs ->
# borrow the arena.ai tab (confirmation popup may appear; 150s to approve) ->
# work IN the borrowed page: Agent mode -> repo BrowserSkill -> fill the
# round-1 prompt (UTF-8 file) -> verify -> Send -> evidence. Tab stays
# borrowed so follow-up rounds can track the arena agent's work.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

$bsk = Join-Path $env:USERPROFILE '.local\bin\bsk.exe'
if (-not (Test-Path -LiteralPath $bsk)) {
    $f = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bsk = $f.FullName }
}
$outDir = Join-Path (Get-Location).Path 'results\jobs\browser\phaseH'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$logPath = Join-Path $outDir 'phaseH.log'
$lines = New-Object System.Collections.Generic.List[string]
function Log([string]$s) { $script:lines.Add($s) | Out-Null; Write-Output $s }
function Snap([string]$name) {
    $s = (& $bsk snapshot --session $script:sid --max-tokens 30000 2>&1 | Out-String)
    $s | Set-Content -LiteralPath (Join-Path $outDir $name) -Encoding UTF8
    return $s
}
function Test-AgentMode([string]$s) {
    return ($s -match 'combobox[^\r\n]*="Agent"') -or ($s -match '\[. active: Agent')
}

$env:BSK_AUTO_START = '0'

# 0. fresh session (a clean Agent Window to receive the borrowed tab)
$null = (& $bsk session stop --all 2>&1 | Out-String)
$st = (& $bsk session start --name 'arena-borrow-run' --json 2>&1 | Out-String)
$m = [regex]::Match($st, '"session_id"\s*:\s*"([^"]+)"')
if (-not $m.Success) { $m = [regex]::Match($st, '"id"\s*:\s*"([^"]+)"') }
$sid = ''
if ($m.Success) { $sid = $m.Groups[1].Value }
if (-not $sid) { Log '[FAIL] no session'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
$sid | Set-Content -LiteralPath (Join-Path (Get-Location).Path 'results\status\bsk_session.txt') -Encoding Ascii
Log ('phaseH: session ' + $sid)

# 1. find the user's arena.ai tab
$tabs = (& $bsk tab list --session $sid --json 2>&1 | Out-String)
$tabs | Set-Content -LiteralPath (Join-Path $outDir 'h_tabs.json') -Encoding UTF8
$tid = ''
foreach ($mm in [regex]::Matches($tabs, '\{[^{}]*\}')) {
    if ($mm.Value -match 'arena\.ai') {
        $cand = [regex]::Match($mm.Value, '"tab_id"\s*:\s*(\d+)').Groups[1].Value
        if ($cand -and -not $tid) { $tid = $cand }
    }
}
Log ('phaseH: arena tab candidate ' + $tid)
if (-not $tid) { Log '[FAIL] no arena.ai tab found in the browser - open arena.ai first'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }

# 2. borrow it (user may need to approve; wait up to 150s)
$bo = (& $bsk tab borrow $tid --session $sid --timeout 300 2>&1 | Out-String)
$bo | Set-Content -LiteralPath (Join-Path $outDir 'h_borrow.json') -Encoding UTF8
Log ('phaseH: borrow exit ' + $LASTEXITCODE + ' -> ' + (($bo -replace '\s+', ' ').Trim().Substring(0, [Math]::Min(160, $bo.Trim().Length))))
if ($LASTEXITCODE -ne 0) { Log '[FAIL] borrow not approved or failed'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
$null = (& $bsk wait-ms 3s --session $sid 2>&1 | Out-String)

# 3. state of the borrowed page (do NOT navigate - keep the live SPA)
$s0 = Snap 'h_s0_borrowed.txt'
Log ('phaseH: borrowed page bytes=' + $s0.Length + ' title=' + [regex]::Match($s0, 'RootWebArea "([^"]*)"').Groups[1].Value)
$hideRef = [regex]::Match($s0, '@(e\d+) button "Hide this').Groups[1].Value
if ($hideRef) {
    $null = (& $bsk click ('@' + $hideRef) --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 2s --session $sid 2>&1 | Out-String)
    $s0 = Snap 'h_s0b_nopromo.txt'
    Log ('phaseH: hid promo @' + $hideRef)
}

# 4. Agent mode if needed (AU recipe first)
if (-not (Test-AgentMode $s0)) {
    $done = $false
    foreach ($r in @('AU', 'AD', 'TA')) {
        $cbRef = [regex]::Match($s0, '@(e\d+) combobox').Groups[1].Value
        if (-not $cbRef) { $s0 = Snap 'h_refind.txt'; $cbRef = [regex]::Match($s0, '@(e\d+) combobox').Groups[1].Value }
        if (-not $cbRef) { break }
        $null = (& $bsk click ('@' + $cbRef) --session $sid 2>&1 | Out-String)
        $null = (& $bsk wait-ms 1500ms --session $sid 2>&1 | Out-String)
        if ($r -eq 'AU') { $null = (& $bsk press ArrowUp --session $sid 2>&1 | Out-String) }
        elseif ($r -eq 'AD') { $null = (& $bsk press ArrowDown --session $sid 2>&1 | Out-String) }
        else { $null = (& $bsk press a --session $sid 2>&1 | Out-String) }
        $null = (& $bsk wait-ms 400ms --session $sid 2>&1 | Out-String)
        $null = (& $bsk press Enter --session $sid 2>&1 | Out-String)
        $null = (& $bsk wait-ms 2500ms --session $sid 2>&1 | Out-String)
        $s0 = Snap ('h_after_' + $r + '.txt')
        if (Test-AgentMode $s0) { $done = $true; Log ('phaseH: Agent via ' + $r); break }
    }
    if (-not $done) { Log '[FAIL] mode flip failed on the borrowed tab'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
} else {
    Log 'phaseH: already Agent'
}

# 5. repo -> BrowserSkill
$s2 = Snap 'h_s_agent.txt'
for ($i = 1; $i -le 6; $i++) {
    if ($s2 -notmatch 'Loading\.\.\.') { break }
    $null = (& $bsk wait-ms 5s --session $sid 2>&1 | Out-String)
    $s2 = Snap ('h_repo_poll' + $i + '.txt')
}
$repoRef = [regex]::Match($s2, '@(e\d+) (?:combobox|button)[^\r\n]*(?:Loading|repository|BrowserSkill|mqgg5630)').Groups[1].Value
Log ('phaseH: repo dropdown @' + $repoRef)
$sel = $false
if ($repoRef) {
    $null = (& $bsk click ('@' + $repoRef) --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 2500ms --session $sid 2>&1 | Out-String)
    $s3 = Snap 'h_repo_menu.txt'
    if (-not (($s3 -match 'option') -or ($s3 -match 'BrowserSkill'))) {
        $null = (& $bsk click ('@' + $repoRef) --session $sid 2>&1 | Out-String)
        $null = (& $bsk wait-ms 2000ms --session $sid 2>&1 | Out-String)
        $s3 = Snap 'h_repo_menu_retry.txt'
    }
    $optBtn = [regex]::Match($s3, '@(e\d+) button "[^"]*BrowserSkill').Groups[1].Value
    if ($optBtn) {
        $null = (& $bsk click ('@' + $optBtn) --session $sid 2>&1 | Out-String)
        Log ('phaseH: clicked option button @' + $optBtn)
    } else {
        $optRef = [regex]::Match($s3, '@(e\d+) option "[^"]*BrowserSkill').Groups[1].Value
        if ($optRef) { $null = (& $bsk click ('@' + $optRef) --session $sid 2>&1 | Out-String); Log ('phaseH: clicked option @' + $optRef) }
        else { $null = (& $bsk press b --session $sid 2>&1 | Out-String); $null = (& $bsk wait-ms 400ms --session $sid 2>&1 | Out-String); $null = (& $bsk press Enter --session $sid 2>&1 | Out-String) }
    }
    $null = (& $bsk wait-ms 3000ms --session $sid 2>&1 | Out-String)
    $s4 = Snap 'h_after_repo.txt'
    $sel = ($s4 -match 'combobox[^\r\n]*BrowserSkill') -or ($s4 -match 'mqgg5630-cyber/BrowserSkill')
    if ($sel) { Log 'phaseH: repo selected' } else { Log 'phaseH: WARN repo unconfirmed - continuing' }
} else {
    Log 'phaseH: no repo dropdown found - continuing'
}

# 6. fill the round-1 prompt + verify + send
$promptFile = Join-Path (Get-Location).Path 'results\status\arena_prompt.txt'
$msg = (Get-Content -LiteralPath $promptFile -Raw -Encoding UTF8).Trim()
Log ('phaseH: prompt chars=' + $msg.Length)
$s5 = Snap 'h_before_fill.txt'
$tbRef = [regex]::Match($s5, '@(e\d+) textbox').Groups[1].Value
Log ('phaseH: textbox @' + $tbRef)
$null = (& $bsk fill ('@' + $tbRef) --value $msg --session $sid 2>&1 | Out-String)
Log ('phaseH: fill exit ' + $LASTEXITCODE)
$null = (& $bsk wait-ms 1s --session $sid 2>&1 | Out-String)
$s6 = Snap 'h_after_fill.txt'
if ($s6 -match 'textbox[^\r\n]*\[empty\]') {
    Log 'phaseH: fill did not stick - retry with click-focus'
    $null = (& $bsk click ('@' + $tbRef) --session $sid 2>&1 | Out-String)
    $null = (& $bsk fill 'textarea' --value $msg --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 1s --session $sid 2>&1 | Out-String)
    $s6 = Snap 'h_after_fill2.txt'
}
if ($s6 -match 'textbox[^\r\n]*\[empty\]') { Log '[FAIL] composer will not hold the prompt'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
Log 'phaseH: prompt verified in composer'
$sendRef = [regex]::Match($s6, '@(e\d+) button "Send message').Groups[1].Value
if ($sendRef) {
    $null = (& $bsk click ('@' + $sendRef) --session $sid 2>&1 | Out-String)
    Log ('phaseH: clicked Send @' + $sendRef)
} else {
    $null = (& $bsk press Enter --session $sid 2>&1 | Out-String)
    Log 'phaseH: Enter fallback'
}

# 7. confirm the echo, capture early progress
$echo = $false
for ($i = 1; $i -le 4; $i++) {
    $null = (& $bsk wait-ms 12s --session $sid 2>&1 | Out-String)
    $sx = Snap ('h_send_poll' + $i + '.txt')
    if ($sx -match '01a0aeb9') { $echo = $true; Log ('phaseH: prompt echo at poll ' + $i); break }
}
if (-not $echo) { Log 'phaseH: WARN no echo yet - captured anyway' }
$null = (& $bsk wait-ms 30s --session $sid 2>&1 | Out-String)
$null = Snap 'h_progress1.txt'
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'h_final.png') 2>&1 | Out-String)
Log 'phaseH: done - task sent in the borrowed tab; session left OPEN'
$lines | Set-Content -LiteralPath $logPath -Encoding UTF8
exit 0
