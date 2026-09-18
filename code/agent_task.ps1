# agent_task.ps1 - stage 4 PHASE F3: fresh-window law.
# Pattern across C/E3 (fresh window -> renders) vs E2/F1/F2 (reused window ->
# permanent loading shell / black viewport): a long-lived Agent Window wedges
# the arena.ai SPA and reloads cannot revive it. F3 therefore ALWAYS:
#   session stop --all  ->  ONE new focused window  ->  navigate  ->
#   poll render (reload at 50s)  ->  if still dead: close tab, brand-new tab,
#   navigate again  ->  Agent mode (AU)  ->  repo dropdown -> BrowserSkill.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

$bsk = Join-Path $env:USERPROFILE '.local\bin\bsk.exe'
if (-not (Test-Path -LiteralPath $bsk)) {
    $f = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bsk = $f.FullName }
}
$outDir = Join-Path (Get-Location).Path 'results\jobs\browser\phaseF3'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$logPath = Join-Path $outDir 'phaseF3.log'
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
function Test-Rendered([string]$s) {
    return ($s -match 'Ask anything') -or ($s -match 'combobox') -or ($s -match 'Get started')
}

$env:BSK_AUTO_START = '0'

# 0. clean slate: kill every session/window, start ONE fresh focused window
$null = (& $bsk session stop --all 2>&1 | Out-String)
$null = (& $bsk wait-ms 2s --session '' 2>&1 | Out-String)
$st = (& $bsk session start --name 'arena-agent-fresh' --json 2>&1 | Out-String)
$m = [regex]::Match($st, '"session_id"\s*:\s*"([^"]+)"')
if (-not $m.Success) { $m = [regex]::Match($st, '"id"\s*:\s*"([^"]+)"') }
$sid = ''
if ($m.Success) { $sid = $m.Groups[1].Value }
if (-not $sid) { Log '[FAIL] no fresh session'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
$sid | Set-Content -LiteralPath (Join-Path (Get-Location).Path 'results\status\bsk_session.txt') -Encoding Ascii
Log ('phaseF3: fresh window, session ' + $sid)

# 1. navigate + patient render poll (reload at 50s, new tab at ~100s)
$rendered = $false
for ($i = 1; $i -le 12; $i++) {
    if ($i -eq 1) { $null = (& $bsk navigate 'https://arena.ai' --session $sid 2>&1 | Out-String) }
    $null = (& $bsk wait-ms 10s --session $sid 2>&1 | Out-String)
    $s0 = Snap ('f3_s0_poll' + $i + '.txt')
    if (Test-Rendered $s0) { $rendered = $true; Log ('phaseF3: rendered at poll ' + $i); break }
    if ($i -eq 5) { Log 'phaseF3: 50s no render - reload'; $null = (& $bsk reload --session $sid 2>&1 | Out-String) }
    if ($i -eq 10) {
        Log 'phaseF3: 100s no render - brand-new tab'
        $tabs = (& $bsk tab list --session $sid --json 2>&1 | Out-String)
        $tid = [regex]::Match($tabs, '"tab_id"\s*:\s*(\d+)').Groups[1].Value
        if ($tid) { $null = (& $bsk tab close $tid --session $sid 2>&1 | Out-String) }
        $null = (& $bsk tab create 'https://arena.ai' --session $sid 2>&1 | Out-String)
    }
}
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'f3_render_state.png') 2>&1 | Out-String)
if (-not $rendered) { Log '[FAIL] still not rendering even in a fresh window'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }

# 2. promo + Agent mode
$hideRef = [regex]::Match($s0, '@(e\d+) button "Hide this').Groups[1].Value
if ($hideRef) {
    $null = (& $bsk click ('@' + $hideRef) --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 2s --session $sid 2>&1 | Out-String)
    $s0 = Snap 'f3_s0b_nopromo.txt'
}
if (-not (Test-AgentMode $s0)) {
    $done = $false
    foreach ($r in @('AU', 'AD', 'TA')) {
        $cbRef = [regex]::Match($s0, '@(e\d+) combobox').Groups[1].Value
        if (-not $cbRef) { $s0 = Snap 'f3_refind.txt'; $cbRef = [regex]::Match($s0, '@(e\d+) combobox').Groups[1].Value }
        $null = (& $bsk click ('@' + $cbRef) --session $sid 2>&1 | Out-String)
        $null = (& $bsk wait-ms 1500ms --session $sid 2>&1 | Out-String)
        if ($r -eq 'AU') { $null = (& $bsk press ArrowUp --session $sid 2>&1 | Out-String) }
        elseif ($r -eq 'AD') { $null = (& $bsk press ArrowDown --session $sid 2>&1 | Out-String) }
        else { $null = (& $bsk press a --session $sid 2>&1 | Out-String) }
        $null = (& $bsk wait-ms 400ms --session $sid 2>&1 | Out-String)
        $null = (& $bsk press Enter --session $sid 2>&1 | Out-String)
        $null = (& $bsk wait-ms 2500ms --session $sid 2>&1 | Out-String)
        $s0 = Snap ('f3_s1_after_' + $r + '.txt')
        if (Test-AgentMode $s0) { $done = $true; Log ('phaseF3: Agent via ' + $r); break }
    }
    if (-not $done) { Log 'phaseF3: WARN not Agent - dumping'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
} else {
    Log 'phaseF3: already Agent'
}

# 3. repo dropdown -> BrowserSkill
$s2 = Snap 'f3_s2_agent.txt'
$repoRef = ''
for ($i = 1; $i -le 6; $i++) {
    if ($s2 -notmatch 'Loading\.\.\.') { break }
    $null = (& $bsk wait-ms 5s --session $sid 2>&1 | Out-String)
    $s2 = Snap ('f3_s2_repo_poll' + $i + '.txt')
}
$repoRef = [regex]::Match($s2, '@(e\d+) (?:combobox|button)[^\r\n]*(?:Loading|repository|BrowserSkill|mqgg5630)').Groups[1].Value
Log ('phaseF3: repo dropdown @' + $repoRef)
$sel = $false
if ($repoRef) {
    $null = (& $bsk click ('@' + $repoRef) --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 2500ms --session $sid 2>&1 | Out-String)
    $s3 = Snap 'f3_s3_repo_menu.txt'
    $opened = ($s3 -match 'option') -or ($s3 -match 'BrowserSkill')
    if (-not $opened) {
        $null = (& $bsk click ('@' + $repoRef) --session $sid 2>&1 | Out-String)
        $null = (& $bsk wait-ms 2000ms --session $sid 2>&1 | Out-String)
        $s3 = Snap 'f3_s3b_retry.txt'
        $opened = ($s3 -match 'option') -or ($s3 -match 'BrowserSkill')
    }
    if ($opened) {
        $optBtn = [regex]::Match($s3, '@(e\d+) button "[^"]*BrowserSkill').Groups[1].Value
        if ($optBtn) {
            $null = (& $bsk click ('@' + $optBtn) --session $sid 2>&1 | Out-String)
            Log ('phaseF3: clicked option button @' + $optBtn)
        } else {
            $optRef = [regex]::Match($s3, '@(e\d+) option "[^"]*BrowserSkill').Groups[1].Value
            if ($optRef) { $null = (& $bsk click ('@' + $optRef) --session $sid 2>&1 | Out-String); Log ('phaseF3: clicked option @' + $optRef) }
            else { Log 'phaseF3: BrowserSkill absent - typeahead b'; $null = (& $bsk press b --session $sid 2>&1 | Out-String) }
            $null = (& $bsk wait-ms 500ms --session $sid 2>&1 | Out-String)
            $null = (& $bsk press Enter --session $sid 2>&1 | Out-String)
        }
        $null = (& $bsk wait-ms 3000ms --session $sid 2>&1 | Out-String)
        $s4 = Snap 'f3_s4_after_select.txt'
        $sel = ($s4 -match 'combobox[^\r\n]*BrowserSkill') -or ($s4 -match '="BrowserSkill') -or ($s4 -match 'mqgg5630-cyber/BrowserSkill')
        if ($sel) { Log 'phaseF3: SUCCESS - BrowserSkill selected' } else { Log 'phaseF3: WARN selection unconfirmed - evidence saved' }
    } else {
        Log 'phaseF3: repo dropdown never showed options'
    }
} else {
    Log 'phaseF3: no repo dropdown found'
}
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'f3_final.png') 2>&1 | Out-String)
Log 'phaseF3: done'
$lines | Set-Content -LiteralPath $logPath -Encoding UTF8
exit 0
