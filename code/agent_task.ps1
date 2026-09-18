# agent_task.ps1 - stage 3 PHASE D4: Radix-aware mode switch.
# Evidence: the mode control is a Radix Select (trigger combobox + portal
# listbox). Previous failures: clicking inner elements does not select, and a
# second trigger click CLOSED the menu before the keys landed. D4 does ONE
# trigger click, then keyboard-only selection inside the open menu:
#   attempt 1: ArrowDown + Enter   (Battle is active; Agent is the next item)
#   attempt 2: typeahead "a" + Enter
#   attempt 3: ArrowUp + Enter
# Verified by the combobox value flipping to ="Agent". Then screenshot + recon
# the agent-mode UI for the GitHub connect control.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

$bsk = Join-Path $env:USERPROFILE '.local\bin\bsk.exe'
if (-not (Test-Path -LiteralPath $bsk)) {
    $f = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bsk = $f.FullName }
}
$outDir = Join-Path (Get-Location).Path 'results\jobs\browser\phaseD4'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$logPath = Join-Path $outDir 'phaseD4.log'
$lines = New-Object System.Collections.Generic.List[string]
function Log([string]$s) { $script:lines.Add($s) | Out-Null; Write-Output $s }
function Snap([string]$name) {
    $s = (& $bsk snapshot --session $script:sid --max-tokens 30000 2>&1 | Out-String)
    $s | Set-Content -LiteralPath (Join-Path $outDir $name) -Encoding UTF8
    return $s
}

$env:BSK_AUTO_START = '0'
$sid = ''
$sidFile = Join-Path (Get-Location).Path 'results\status\bsk_session.txt'
if (Test-Path -LiteralPath $sidFile) { $sid = (Get-Content -LiteralPath $sidFile -Raw).Trim() }
$lst = (& $bsk session list --json 2>&1 | Out-String)
if (-not $sid -or $lst -notmatch [regex]::Escape($sid)) {
    $st = (& $bsk session start --no-focus --name 'arena-agent-mode' --json 2>&1 | Out-String)
    $m = [regex]::Match($st, '"session_id"\s*:\s*"([^"]+)"')
    if (-not $m.Success) { $m = [regex]::Match($st, '"id"\s*:\s*"([^"]+)"') }
    if ($m.Success) { $sid = $m.Groups[1].Value } else { Log ('[FAIL] no session'); $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
    $sid | Set-Content -LiteralPath $sidFile -Encoding Ascii
}
Log ('phaseD4: session ' + $sid)

# 0. land on arena.ai fresh
$null = (& $bsk navigate 'https://arena.ai' --session $sid 2>&1 | Out-String)
$null = (& $bsk wait-ms 12s --session $sid 2>&1 | Out-String)
$s0 = Snap 'd4_s0_home.txt'
$hideRef = [regex]::Match($s0, '@(e\d+) button "Hide this').Groups[1].Value
if ($hideRef) {
    $null = (& $bsk click ('@' + $hideRef) --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 2s --session $sid 2>&1 | Out-String)
    Log ('phaseD4: hid promo @' + $hideRef)
    $s0 = Snap 'd4_s0b_nopromo.txt'
}

function Test-AgentMode([string]$s) {
    return ($s -match 'combobox[^\r\n]*="Agent"') -or ($s -match '\[. active: Agent')
}

if (Test-AgentMode $s0) {
    Log 'phaseD4: already Agent mode'
} else {
    $cbRef = [regex]::Match($s0, '@(e\d+) combobox').Groups[1].Value
    Log ('phaseD4: trigger @' + $cbRef)
    # ONE click opens the menu; from here on keyboard only
    $null = (& $bsk click ('@' + $cbRef) --session $sid 2>&1 | Out-String)
    Log ('phaseD4: opened menu (exit ' + $LASTEXITCODE + ')')
    $null = (& $bsk wait-ms 1500ms --session $sid 2>&1 | Out-String)

    $flipped = $false
    # attempt 1: ArrowDown then Enter
    $null = (& $bsk press ArrowDown --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 400ms --session $sid 2>&1 | Out-String)
    $null = (& $bsk press Enter --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 2500ms --session $sid 2>&1 | Out-String)
    $s1 = Snap 'd4_s1_after_arrowdown_enter.txt'
    if (Test-AgentMode $s1) { $flipped = $true; Log 'phaseD4: SUCCESS via ArrowDown+Enter' }

    # attempt 2: reopen, typeahead "a", Enter
    if (-not $flipped) {
        Log 'phaseD4: attempt 2 - typeahead'
        $cb2 = [regex]::Match($s1, '@(e\d+) combobox').Groups[1].Value
        $null = (& $bsk click ('@' + $cb2) --session $sid 2>&1 | Out-String)
        $null = (& $bsk wait-ms 1200ms --session $sid 2>&1 | Out-String)
        $null = (& $bsk press a --session $sid 2>&1 | Out-String)
        $null = (& $bsk wait-ms 400ms --session $sid 2>&1 | Out-String)
        $null = (& $bsk press Enter --session $sid 2>&1 | Out-String)
        $null = (& $bsk wait-ms 2500ms --session $sid 2>&1 | Out-String)
        $s2 = Snap 'd4_s2_after_typeahead.txt'
        if (Test-AgentMode $s2) { $flipped = $true; Log 'phaseD4: SUCCESS via typeahead' } else { $s1 = $s2 }
    }

    # attempt 3: reopen, ArrowUp + Enter (in case highlight starts below Agent)
    if (-not $flipped) {
        Log 'phaseD4: attempt 3 - ArrowUp'
        $cb3 = [regex]::Match($s1, '@(e\d+) combobox').Groups[1].Value
        $null = (& $bsk click ('@' + $cb3) --session $sid 2>&1 | Out-String)
        $null = (& $bsk wait-ms 1200ms --session $sid 2>&1 | Out-String)
        $null = (& $bsk press ArrowUp --session $sid 2>&1 | Out-String)
        $null = (& $bsk wait-ms 400ms --session $sid 2>&1 | Out-String)
        $null = (& $bsk press Enter --session $sid 2>&1 | Out-String)
        $null = (& $bsk wait-ms 2500ms --session $sid 2>&1 | Out-String)
        $s3 = Snap 'd4_s3_after_arrowup.txt'
        if (Test-AgentMode $s3) { $flipped = $true; Log 'phaseD4: SUCCESS via ArrowUp' } else { $s1 = $s3 }
    }
    if (-not $flipped) { Log 'phaseD4: WARN all attempts failed - state dumped' }
}

# 4. recon the (hopefully) agent-mode UI
$s4 = Snap 'd4_s4_final.txt'
$hits = @()
foreach ($mm in [regex]::Matches($s4, '@e\d+ [^\r\n]*')) {
    if ($mm.Value -match 'GitHub|Connect|Repo|repo|Install') { $hits += $mm.Value.Trim() }
}
if ($hits.Count) { foreach ($h in $hits[0..([Math]::Min(8, $hits.Count - 1))]) { Log ('phaseD4: UI ' + $h.Substring(0, [Math]::Min(110, $h.Length))) } }
else { Log 'phaseD4: no GitHub-ish control named in the snapshot' }
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'd4_final.png') 2>&1 | Out-String)
Log 'phaseD4: done'
$lines | Set-Content -LiteralPath $logPath -Encoding UTF8
exit 0
