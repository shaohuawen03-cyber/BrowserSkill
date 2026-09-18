# agent_task.ps1 - stage 3 PHASE E1: recon the GitHub controls in Agent mode.
# D4 flipped the mode to Agent; the snapshot shows "Add files and connections"
# and "GitHub settings" buttons. E1: (re)enter Agent mode if needed, open
# "GitHub settings", capture the submenu, Escape, open "Add files and
# connections", capture that too. Screenshots at every step. No flow commits.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

$bsk = Join-Path $env:USERPROFILE '.local\bin\bsk.exe'
if (-not (Test-Path -LiteralPath $bsk)) {
    $f = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bsk = $f.FullName }
}
$outDir = Join-Path (Get-Location).Path 'results\jobs\browser\phaseE1'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$logPath = Join-Path $outDir 'phaseE1.log'
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
Log ('phaseE1: session ' + $sid)

# 0. land + state
$null = (& $bsk navigate 'https://arena.ai' --session $sid 2>&1 | Out-String)
$null = (& $bsk wait-ms 12s --session $sid 2>&1 | Out-String)
$s0 = Snap 'e1_s0_home.txt'
$hideRef = [regex]::Match($s0, '@(e\d+) button "Hide this').Groups[1].Value
if ($hideRef) {
    $null = (& $bsk click ('@' + $hideRef) --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 2s --session $sid 2>&1 | Out-String)
    $s0 = Snap 'e1_s0b_nopromo.txt'
    Log ('phaseE1: hid promo @' + $hideRef)
}

# 1. ensure Agent mode (ArrowUp recipe that worked in D4)
if (-not (Test-AgentMode $s0)) {
    $cbRef = [regex]::Match($s0, '@(e\d+) combobox').Groups[1].Value
    if ($cbRef) {
        $null = (& $bsk click ('@' + $cbRef) --session $sid 2>&1 | Out-String)
        $null = (& $bsk wait-ms 1500ms --session $sid 2>&1 | Out-String)
        $null = (& $bsk press ArrowDown --session $sid 2>&1 | Out-String)
        $null = (& $bsk wait-ms 300ms --session $sid 2>&1 | Out-String)
        $null = (& $bsk press Enter --session $sid 2>&1 | Out-String)
        $null = (& $bsk wait-ms 2000ms --session $sid 2>&1 | Out-String)
        $s0 = Snap 'e1_s0c_flip1.txt'
        if (-not (Test-AgentMode $s0)) {
            $cb2 = [regex]::Match($s0, '@(e\d+) combobox').Groups[1].Value
            $null = (& $bsk click ('@' + $cb2) --session $sid 2>&1 | Out-String)
            $null = (& $bsk wait-ms 1500ms --session $sid 2>&1 | Out-String)
            $null = (& $bsk press ArrowUp --session $sid 2>&1 | Out-String)
            $null = (& $bsk wait-ms 300ms --session $sid 2>&1 | Out-String)
            $null = (& $bsk press Enter --session $sid 2>&1 | Out-String)
            $null = (& $bsk wait-ms 2500ms --session $sid 2>&1 | Out-String)
            $s0 = Snap 'e1_s0d_flip2.txt'
        }
    }
    if (Test-AgentMode $s0) { Log 'phaseE1: Agent mode on' } else { Log 'phaseE1: WARN mode not Agent - continuing with evidence' }
} else {
    Log 'phaseE1: already Agent mode'
}

# 2. open "GitHub settings" and capture its submenu
$s1 = Snap 'e1_s1_agent.txt'
$ghRef = [regex]::Match($s1, '@(e\d+) button "GitHub settings').Groups[1].Value
Log ('phaseE1: GitHub settings @' + $ghRef)
if ($ghRef) {
    $null = (& $bsk click ('@' + $ghRef) --session $sid 2>&1 | Out-String)
    Log ('phaseE1: clicked GitHub settings (exit ' + $LASTEXITCODE + ')')
    $null = (& $bsk wait-ms 4s --session $sid 2>&1 | Out-String)
    $s2 = Snap 'e1_s2_ghsettings_menu.txt'
    $null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'e1_ghsettings.png') 2>&1 | Out-String)
    $url = (& $bsk evaluate location.href --session $sid 2>&1 | Out-String)
    Log ('phaseE1: url -> ' + $url.Trim().Substring(0, [Math]::Min(140, $url.Trim().Length)))
    $tabs = (& $bsk tab list --session $sid --json 2>&1 | Out-String)
    $tabs | Set-Content -LiteralPath (Join-Path $outDir 'e1_tabs.json') -Encoding UTF8
    Log ('phaseE1: tabs -> ' + (($tabs -replace '\s+', ' ').Trim().Substring(0, [Math]::Min(240, $tabs.Trim().Length))))
    $null = (& $bsk press Escape --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 1200ms --session $sid 2>&1 | Out-String)
} else {
    Log 'phaseE1: GitHub settings button not found'
}

# 3. open "Add files and connections" and capture
$s3 = Snap 'e1_s3_afresh.txt'
$addRef = [regex]::Match($s3, '@(e\d+) button "Add files and connections').Groups[1].Value
Log ('phaseE1: Add files and connections @' + $addRef)
if ($addRef) {
    $null = (& $bsk click ('@' + $addRef) --session $sid 2>&1 | Out-String)
    Log ('phaseE1: clicked Add files and connections (exit ' + $LASTEXITCODE + ')')
    $null = (& $bsk wait-ms 3s --session $sid 2>&1 | Out-String)
    $s4 = Snap 'e1_s4_addfiles_menu.txt'
    $null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'e1_addfiles.png') 2>&1 | Out-String)
    $null = (& $bsk press Escape --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 1s --session $sid 2>&1 | Out-String)
} else {
    Log 'phaseE1: Add files and connections not found'
}
Log 'phaseE1: done'
$lines | Set-Content -LiteralPath $logPath -Encoding UTF8
exit 0
