# agent_task.ps1 - stage 4 PHASE F1: pick the repository in Agent mode.
# E3 screenshot showed: Agent mode ON, a repo dropdown showing "Loading...",
# a branch dropdown "main", and a gear button. So GitHub is ALREADY connected;
# F1 waits for the repo list to finish loading, opens the repo dropdown,
# selects mqgg5630-cyber/BrowserSkill (inner-button click + keyboard fallback),
# verifies the selection, screenshots. No message is sent yet.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

$bsk = Join-Path $env:USERPROFILE '.local\bin\bsk.exe'
if (-not (Test-Path -LiteralPath $bsk)) {
    $f = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bsk = $f.FullName }
}
$outDir = Join-Path (Get-Location).Path 'results\jobs\browser\phaseF1'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$logPath = Join-Path $outDir 'phaseF1.log'
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
Log ('phaseF1: session ' + $sid)

# 0. land + render-wait
$rendered = $false
for ($i = 1; $i -le 7 -and -not $rendered; $i++) {
    if ($i -eq 1) { $null = (& $bsk navigate 'https://arena.ai' --session $sid 2>&1 | Out-String) }
    $null = (& $bsk wait-ms 10s --session $sid 2>&1 | Out-String)
    $s0 = Snap ('f1_s0_poll' + $i + '.txt')
    if (Test-Rendered $s0) { $rendered = $true; Log ('phaseF1: rendered at poll ' + $i) }
}
if (-not $rendered) { Log '[FAIL] not rendering'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }

# 1. promo
$hideRef = [regex]::Match($s0, '@(e\d+) button "Hide this').Groups[1].Value
if ($hideRef) {
    $null = (& $bsk click ('@' + $hideRef) --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 2s --session $sid 2>&1 | Out-String)
    $s0 = Snap 'f1_s0b_nopromo.txt'
}

# 2. Agent mode if needed (AU recipe first - it won twice)
if (-not (Test-AgentMode $s0)) {
    $recipes = @('AU', 'AD', 'TA')
    foreach ($r in $recipes) {
        $cbRef = [regex]::Match($s0, '@(e\d+) combobox').Groups[1].Value
        if (-not $cbRef) { $s0 = Snap 'f1_refind.txt'; $cbRef = [regex]::Match($s0, '@(e\d+) combobox').Groups[1].Value }
        $null = (& $bsk click ('@' + $cbRef) --session $sid 2>&1 | Out-String)
        $null = (& $bsk wait-ms 1500ms --session $sid 2>&1 | Out-String)
        if ($r -eq 'AU') { $null = (& $bsk press ArrowUp --session $sid 2>&1 | Out-String) }
        elseif ($r -eq 'AD') { $null = (& $bsk press ArrowDown --session $sid 2>&1 | Out-String) }
        else { $null = (& $bsk press a --session $sid 2>&1 | Out-String) }
        $null = (& $bsk wait-ms 400ms --session $sid 2>&1 | Out-String)
        $null = (& $bsk press Enter --session $sid 2>&1 | Out-String)
        $null = (& $bsk wait-ms 2500ms --session $sid 2>&1 | Out-String)
        $s0 = Snap ('f1_s1_after_' + $r + '.txt')
        if (Test-AgentMode $s0) { Log ('phaseF1: Agent via ' + $r); break }
    }
}
if (-not (Test-AgentMode $s0)) { Log 'phaseF1: WARN not in Agent mode - dumping and stopping'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }

# 3. wait for the repo dropdown to finish loading (text stops being Loading...)
$repoRef = ''
for ($i = 1; $i -le 6; $i++) {
    $s2 = Snap ('f1_s2_repolist_poll' + $i + '.txt')
    $repoRef = [regex]::Match($s2, '@(e\d+) (?:combobox|button)[^\r\n]*(?:Loading|repository|BrowserSkill|mqgg5630)').Groups[1].Value
    if ($s2 -notmatch 'Loading\.\.\.') { Log ('phaseF1: repo list settled at poll ' + $i); break }
    $null = (& $bsk wait-ms 5s --session $sid 2>&1 | Out-String)
}
Log ('phaseF1: repo dropdown ref @' + $repoRef)

# 4. open the repo dropdown and capture the option list
$opened = $false
if ($repoRef) {
    $null = (& $bsk click ('@' + $repoRef) --session $sid 2>&1 | Out-String)
    Log ('phaseF1: clicked repo dropdown (exit ' + $LASTEXITCODE + ')')
    $null = (& $bsk wait-ms 2500ms --session $sid 2>&1 | Out-String)
    $s3 = Snap 'f1_s3_repo_menu.txt'
    $hasOptions = ($s3 -match 'option') -or ($s3 -match 'BrowserSkill')
    if ($hasOptions) { $opened = $true } else {
        # maybe the click closed it; try the keyboard route on a second click
        $null = (& $bsk click ('@' + $repoRef) --session $sid 2>&1 | Out-String)
        $null = (& $bsk wait-ms 2000ms --session $sid 2>&1 | Out-String)
        $s3 = Snap 'f1_s3b_repo_menu_retry.txt'
        $opened = ($s3 -match 'option') -or ($s3 -match 'BrowserSkill')
    }
}
$sel = $false
if ($opened) {
    # inner button of the BrowserSkill option first
    $optBtn = [regex]::Match($s3, '@(e\d+) button "[^"]*BrowserSkill').Groups[1].Value
    if ($optBtn) {
        $null = (& $bsk click ('@' + $optBtn) --session $sid 2>&1 | Out-String)
        Log ('phaseF1: clicked BrowserSkill option button @' + $optBtn)
    } else {
        $optRef = [regex]::Match($s3, '@(e\d+) option "[^"]*BrowserSkill').Groups[1].Value
        if ($optRef) {
            $null = (& $bsk click ('@' + $optRef) --session $sid 2>&1 | Out-String)
            Log ('phaseF1: clicked BrowserSkill option @' + $optRef)
        } else {
            Log 'phaseF1: BrowserSkill not in the list - trying typeahead b'
            $null = (& $bsk press b --session $sid 2>&1 | Out-String)
        }
        $null = (& $bsk wait-ms 500ms --session $sid 2>&1 | Out-String)
        $null = (& $bsk press Enter --session $sid 2>&1 | Out-String)
    }
    $null = (& $bsk wait-ms 3000ms --session $sid 2>&1 | Out-String)
    $s4 = Snap 'f1_s4_after_select.txt'
    $sel = ($s4 -match 'combobox[^\r\n]*BrowserSkill') -or ($s4 -match '="BrowserSkill') -or ($s4 -match 'mqgg5630-cyber/BrowserSkill')
    if ($sel) { Log 'phaseF1: SUCCESS - BrowserSkill selected as the repo' } else { Log 'phaseF1: WARN selection not confirmed - evidence captured' }
} else {
    Log 'phaseF1: repo dropdown did not open with options - full snapshots saved'
}
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'f1_final.png') 2>&1 | Out-String)
Log 'phaseF1: done'
$lines | Set-Content -LiteralPath $logPath -Encoding UTF8
exit 0
