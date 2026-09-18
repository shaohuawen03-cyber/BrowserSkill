# agent_task.ps1 - stage 3 PHASE D1: switch the arena.ai composer to AGENT
# mode (it defaulted to Battle) and recon the agent-mode UI (GitHub connect /
# repo picker). Steps: new chat -> dismiss promo -> open the mode combobox ->
# snapshot the menu -> click the Agent option -> verify + recon artifacts.
# No typing yet; the agent scripts the GitHub flow from the evidence.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

$bsk = Join-Path $env:USERPROFILE '.local\bin\bsk.exe'
if (-not (Test-Path -LiteralPath $bsk)) {
    $f = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bsk = $f.FullName }
}
if (-not (Test-Path -LiteralPath $bsk)) { Write-Output '[FAIL] bsk.exe not found'; exit 1 }

$outDir = Join-Path (Get-Location).Path 'results\jobs\browser\phaseD1'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$logPath = Join-Path $outDir 'phaseD1.log'
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
    if ($m.Success) { $sid = $m.Groups[1].Value } else { Log ('[FAIL] no session: ' + $st.Substring(0, [Math]::Min(250, $st.Length))); $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
    $sid | Set-Content -LiteralPath $sidFile -Encoding Ascii
}
Log ('phaseD1: session ' + $sid)

# 0. land on arena.ai (a stopped session restarts on a blank page)
$null = (& $bsk navigate 'https://arena.ai' --session $sid 2>&1 | Out-String)
$null = (& $bsk wait-ms 10s --session $sid 2>&1 | Out-String)
$s0 = Snap 'd1_s0_home.txt'
Log ('phaseD1: s0 bytes=' + $s0.Length)

# 1. start a NEW chat so the old Battle conversation is not reused
$newRef = [regex]::Match($s0, '@(e\d+) link "New Chat"').Groups[1].Value
if ($newRef) {
    $null = (& $bsk click ('@' + $newRef) --session $sid 2>&1 | Out-String)
    Log ('phaseD1: clicked New Chat @' + $newRef)
    $null = (& $bsk wait-ms 4s --session $sid 2>&1 | Out-String)
} else {
    Log 'phaseD1: no New Chat link - staying on the current view'
}

# 2. dismiss the promo card if it reappeared
$s1 = Snap 'd1_s1_newchat.txt'
$hideRef = [regex]::Match($s1, '@(e\d+) button "Hide this').Groups[1].Value
if ($hideRef) {
    $null = (& $bsk click ('@' + $hideRef) --session $sid 2>&1 | Out-String)
    Log ('phaseD1: hid promo @' + $hideRef)
    $null = (& $bsk wait-ms 2s --session $sid 2>&1 | Out-String)
    $s1 = Snap 'd1_s1b_nopromo.txt'
}

# 3. open the mode combobox (currently "Battle")
$cbRef = [regex]::Match($s1, '@(e\d+) combobox').Groups[1].Value
Log ('phaseD1: mode combobox @' + $cbRef)
if (-not $cbRef) { Log '[FAIL] mode combobox not found'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
$null = (& $bsk click ('@' + $cbRef) --session $sid 2>&1 | Out-String)
Log ('phaseD1: clicked combobox (exit ' + $LASTEXITCODE + ')')
$null = (& $bsk wait-ms 2s --session $sid 2>&1 | Out-String)

# 4. the open menu: snapshot and click the Agent option
$s2 = Snap 'd1_s2_menu_open.txt'
$optRef = ''
foreach ($pat in '@(e\d+) (?:button|option|menuitem|link) "Agent', '@(e\d+) [^\r\n]*"Agent\b') {
    $mm = [regex]::Match($s2, $pat)
    if ($mm.Success) { $optRef = $mm.Groups[1].Value; break }
}
Log ('phaseD1: Agent option @' + $optRef)
if ($optRef) {
    $null = (& $bsk click ('@' + $optRef) --session $sid 2>&1 | Out-String)
    Log ('phaseD1: clicked Agent option (exit ' + $LASTEXITCODE + ')')
    $null = (& $bsk wait-ms 3s --session $sid 2>&1 | Out-String)
} else {
    Log 'phaseD1: WARN no Agent option found in the open menu - snapshot captured for analysis'
}

# 5. verify + recon the agent-mode composer
$s3 = Snap 'd1_s3_after_select.txt'
$modeNow = [regex]::Match($s3, '@e\d+ combobox "([^"]*)"').Groups[1].Value
Log ('phaseD1: mode combobox now reads: ' + $modeNow)
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'd1_agent_mode.png') 2>&1 | Out-String)
Log ('phaseD1: mode line present: ' + ($s3 -match 'Agent'))
Log 'phaseD1: done'
$lines | Set-Content -LiteralPath $logPath -Encoding UTF8
exit 0
