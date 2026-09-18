# agent_task.ps1 - stage 4 PHASE F2: reuse tabs, patient render wait, select repo.
# Lessons: arena.ai rendering is flaky (E3 fine, F1 loading-shell for 70s) and
# F1 re-navigated needlessly. F2: reuse any live session + any open arena.ai
# tab, wait up to ~100s for a real render (reload between polls), then Agent
# mode (AU recipe) and the repo dropdown -> BrowserSkill -> verify.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

$bsk = Join-Path $env:USERPROFILE '.local\bin\bsk.exe'
if (-not (Test-Path -LiteralPath $bsk)) {
    $f = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bsk = $f.FullName }
}
$outDir = Join-Path (Get-Location).Path 'results\jobs\browser\phaseF2'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$logPath = Join-Path $outDir 'phaseF2.log'
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
$sid = ''
$sidFile = Join-Path (Get-Location).Path 'results\status\bsk_session.txt'
if (Test-Path -LiteralPath $sidFile) { $sid = (Get-Content -LiteralPath $sidFile -Raw).Trim() }
$lst = (& $bsk session list --json 2>&1 | Out-String)
if (-not $sid -or $lst -notmatch [regex]::Escape($sid)) {
    $null = (& $bsk session stop --all 2>&1 | Out-String)
    $st = (& $bsk session start --name 'arena-agent-repo' --json 2>&1 | Out-String)
    $m = [regex]::Match($st, '"session_id"\s*:\s*"([^"]+)"')
    if (-not $m.Success) { $m = [regex]::Match($st, '"id"\s*:\s*"([^"]+)"') }
    if ($m.Success) { $sid = $m.Groups[1].Value } else { Log ('[FAIL] no session'); $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
    $sid | Set-Content -LiteralPath $sidFile -Encoding Ascii
}
Log ('phaseF2: session ' + $sid)

# 0. find an existing arena.ai tab in this window; reuse it, else navigate
$tabs = (& $bsk tab list --session $sid --json 2>&1 | Out-String)
$tabs | Set-Content -LiteralPath (Join-Path $outDir 'f2_tabs0.json') -Encoding UTF8
$arenaTab = ''
foreach ($mm in [regex]::Matches($tabs, '\{[^{}]*\}')) {
    if ($mm.Value -match 'arena\.ai') {
        $tid = [regex]::Match($mm.Value, '"tab_id"\s*:\s*(\d+)').Groups[1].Value
        $act = ($mm.Value -match '"active"\s*:\s*true')
        if ($tid) { if (-not $arenaTab -or $act) { $arenaTab = $tid } }
    }
}
if ($arenaTab) {
    $null = (& $bsk tab select $arenaTab --session $sid 2>&1 | Out-String)
    Log ('phaseF2: reusing arena tab ' + $arenaTab)
} else {
    Log 'phaseF2: no arena tab yet - navigating'
    $null = (& $bsk navigate 'https://arena.ai' --session $sid 2>&1 | Out-String)
}

# 1. patient render wait (~100s, reload at 40s and 75s)
$rendered = $false
for ($i = 1; $i -le 10; $i++) {
    $null = (& $bsk wait-ms 10s --session $sid 2>&1 | Out-String)
    $s0 = Snap ('f2_s0_poll' + $i + '.txt')
    if (Test-Rendered $s0) { $rendered = $true; Log ('phaseF2: rendered at poll ' + $i); break }
    if ($i -eq 4 -or $i -eq 7) {
        Log ('phaseF2: poll ' + $i + ' still a shell - reloading')
        $null = (& $bsk reload --session $sid 2>&1 | Out-String)
    }
}
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'f2_render_state.png') 2>&1 | Out-String)
if (-not $rendered) { Log '[FAIL] arena.ai not rendering after ~100s'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }

# 2. promo + Agent mode
$hideRef = [regex]::Match($s0, '@(e\d+) button "Hide this').Groups[1].Value
if ($hideRef) {
    $null = (& $bsk click ('@' + $hideRef) --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 2s --session $sid 2>&1 | Out-String)
    $s0 = Snap 'f2_s0b_nopromo.txt'
}
if (-not (Test-AgentMode $s0)) {
    $done = $false
    foreach ($r in @('AU', 'AD', 'TA')) {
        $cbRef = [regex]::Match($s0, '@(e\d+) combobox').Groups[1].Value
        if (-not $cbRef) { $s0 = Snap 'f2_refind.txt'; $cbRef = [regex]::Match($s0, '@(e\d+) combobox').Groups[1].Value }
        $null = (& $bsk click ('@' + $cbRef) --session $sid 2>&1 | Out-String)
        $null = (& $bsk wait-ms 1500ms --session $sid 2>&1 | Out-String)
        if ($r -eq 'AU') { $null = (& $bsk press ArrowUp --session $sid 2>&1 | Out-String) }
        elseif ($r -eq 'AD') { $null = (& $bsk press ArrowDown --session $sid 2>&1 | Out-String) }
        else { $null = (& $bsk press a --session $sid 2>&1 | Out-String) }
        $null = (& $bsk wait-ms 400ms --session $sid 2>&1 | Out-String)
        $null = (& $bsk press Enter --session $sid 2>&1 | Out-String)
        $null = (& $bsk wait-ms 2500ms --session $sid 2>&1 | Out-String)
        $s0 = Snap ('f2_s1_after_' + $r + '.txt')
        if (Test-AgentMode $s0) { $done = $true; Log ('phaseF2: Agent via ' + $r); break }
    }
    if (-not $done) { Log 'phaseF2: WARN not Agent - dumping'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
} else {
    Log 'phaseF2: already Agent'
}

# 3. repo dropdown -> BrowserSkill (same recipe as F1)
$repoRef = ''
for ($i = 1; $i -le 6; $i++) {
    $s2 = Snap ('f2_s2_repo_poll' + $i + '.txt')
    if ($s2 -notmatch 'Loading\.\.\.') { Log ('phaseF2: repo list settled at poll ' + $i); break }
    $null = (& $bsk wait-ms 5s --session $sid 2>&1 | Out-String)
}
$repoRef = [regex]::Match($s2, '@(e\d+) (?:combobox|button)[^\r\n]*(?:Loading|repository|BrowserSkill|mqgg5630)').Groups[1].Value
Log ('phaseF2: repo dropdown @' + $repoRef)
$sel = $false
if ($repoRef) {
    $null = (& $bsk click ('@' + $repoRef) --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 2500ms --session $sid 2>&1 | Out-String)
    $s3 = Snap 'f2_s3_repo_menu.txt'
    $opened = ($s3 -match 'option') -or ($s3 -match 'BrowserSkill')
    if (-not $opened) {
        $null = (& $bsk click ('@' + $repoRef) --session $sid 2>&1 | Out-String)
        $null = (& $bsk wait-ms 2000ms --session $sid 2>&1 | Out-String)
        $s3 = Snap 'f2_s3b_repo_menu_retry.txt'
        $opened = ($s3 -match 'option') -or ($s3 -match 'BrowserSkill')
    }
    if ($opened) {
        $optBtn = [regex]::Match($s3, '@(e\d+) button "[^"]*BrowserSkill').Groups[1].Value
        if ($optBtn) {
            $null = (& $bsk click ('@' + $optBtn) --session $sid 2>&1 | Out-String)
            Log ('phaseF2: clicked option button @' + $optBtn)
        } else {
            $optRef = [regex]::Match($s3, '@(e\d+) option "[^"]*BrowserSkill').Groups[1].Value
            if ($optRef) { $null = (& $bsk click ('@' + $optRef) --session $sid 2>&1 | Out-String); Log ('phaseF2: clicked option @' + $optRef) }
            else { Log 'phaseF2: BrowserSkill absent - typeahead b'; $null = (& $bsk press b --session $sid 2>&1 | Out-String) }
            $null = (& $bsk wait-ms 500ms --session $sid 2>&1 | Out-String)
            $null = (& $bsk press Enter --session $sid 2>&1 | Out-String)
        }
        $null = (& $bsk wait-ms 3000ms --session $sid 2>&1 | Out-String)
        $s4 = Snap 'f2_s4_after_select.txt'
        $sel = ($s4 -match 'combobox[^\r\n]*BrowserSkill') -or ($s4 -match '="BrowserSkill') -or ($s4 -match 'mqgg5630-cyber/BrowserSkill')
        if ($sel) { Log 'phaseF2: SUCCESS - BrowserSkill is the selected repo' } else { Log 'phaseF2: WARN selection unconfirmed - evidence saved' }
    } else {
        Log 'phaseF2: repo dropdown never showed options'
    }
} else {
    Log 'phaseF2: no repo dropdown control found'
}
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'f2_final.png') 2>&1 | Out-String)
Log 'phaseF2: done'
$lines | Set-Content -LiteralPath $logPath -Encoding UTF8
exit 0
