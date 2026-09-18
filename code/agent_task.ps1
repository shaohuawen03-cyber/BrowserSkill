# agent_task.ps1 - stage 3 PHASE D2: actually select Agent Mode.
# D1 evidence: the menu option is @eN option "Agent Mode..." wrapping an inner
# @eM button; clicking the option element did not register. D2 clicks the inner
# BUTTON, verifies the combobox value flipped to Agent, falls back to keyboard
# navigation (ArrowDown + Enter), then recon modes/repo UI and screenshots.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

$bsk = Join-Path $env:USERPROFILE '.local\bin\bsk.exe'
if (-not (Test-Path -LiteralPath $bsk)) {
    $f = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bsk = $f.FullName }
}
$outDir = Join-Path (Get-Location).Path 'results\jobs\browser\phaseD2'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$logPath = Join-Path $outDir 'phaseD2.log'
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
Log ('phaseD2: session ' + $sid)

# 0. current state
$s0 = Snap 'd2_s0.txt'
if ($s0 -notmatch 'textbox|combobox') {
    $null = (& $bsk navigate 'https://arena.ai' --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 10s --session $sid 2>&1 | Out-String)
    $s0 = Snap 'd2_s0b_home.txt'
}
if ($s0 -match 'combobox[^\r\n]*="Agent"') { Log 'phaseD2: already in Agent mode - nothing to do' }
else {
    # 1. open the mode menu
    $cbRef = [regex]::Match($s0, '@(e\d+) combobox').Groups[1].Value
    $null = (& $bsk click ('@' + $cbRef) --session $sid 2>&1 | Out-String)
    Log ('phaseD2: opened menu @' + $cbRef + ' (exit ' + $LASTEXITCODE + ')')
    $null = (& $bsk wait-ms 2s --session $sid 2>&1 | Out-String)
    $s1 = Snap 'd2_s1_menu.txt'

    # 2. click the inner button of the Agent option
    $btnRef = [regex]::Match($s1, '@(e\d+) button "Agent Mode').Groups[1].Value
    $ok = $false
    if ($btnRef) {
        $null = (& $bsk click ('@' + $btnRef) --session $sid 2>&1 | Out-String)
        Log ('phaseD2: clicked inner button @' + $btnRef + ' (exit ' + $LASTEXITCODE + ')')
        $null = (& $bsk wait-ms 3s --session $sid 2>&1 | Out-String)
        $s2 = Snap 'd2_s2_after_btn.txt'
        $ok = ($s2 -match 'combobox[^\r\n]*="Agent"') -or ($s2 -match 'active: Agent')
    } else { $s2 = $s1 }

    # 3. keyboard fallback: open menu, ArrowDown to Agent, Enter
    if (-not $ok) {
        Log 'phaseD2: button click did not flip the mode - keyboard fallback'
        $cbRef2 = [regex]::Match($s2, '@(e\d+) combobox').Groups[1].Value
        if ($cbRef2) {
            $null = (& $bsk click ('@' + $cbRef2) --session $sid 2>&1 | Out-String)
            $null = (& $bsk wait-ms 1s --session $sid 2>&1 | Out-String)
        }
        $null = (& $bsk press ArrowDown --session $sid 2>&1 | Out-String)
        $null = (& $bsk press Enter --session $sid 2>&1 | Out-String)
        $null = (& $bsk wait-ms 3s --session $sid 2>&1 | Out-String)
        $s2 = Snap 'd2_s3_after_keys.txt'
        $ok = ($s2 -match 'combobox[^\r\n]*="Agent"') -or ($s2 -match 'active: Agent')
    }
    if ($ok) { Log 'phaseD2: SUCCESS - mode is now Agent' }
    else { Log 'phaseD2: WARN mode still not Agent - state dumped' }
}

# 4. recon the agent-mode composer: look for GitHub / repo UI
$s3 = Snap 'd2_s4_agent_ui.txt'
$gh = [regex]::Matches($s3, '@e\d+ [^\r\n]*[^\r\n]')
$hits = @()
foreach ($x in $gh) { if ($x.Value -match 'GitHub|github|Connect|Repo|repository') { $hits += $x.Value.Trim() } }
if ($hits.Count) { foreach ($h in $hits[0..([Math]::Min(8, $hits.Count - 1))]) { Log ('phaseD2: UI ' + $h.Substring(0, [Math]::Min(110, $h.Length))) } }
else { Log 'phaseD2: no GitHub/repo UI visible yet in the snapshot' }
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'd2_agent_mode.png') 2>&1 | Out-String)
Log 'phaseD2: done'
$lines | Set-Content -LiteralPath $logPath -Encoding UTF8
exit 0
