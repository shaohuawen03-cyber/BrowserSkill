# agent_task.ps1 - stage 3 PHASE D3: land on arena.ai FIRST (D2 lesson: a
# fresh session sits on the Edge new-tab page), then select Agent Mode
# (inner button + keyboard fallback), then find and click the GitHub connect
# control and record whether it redirects in place or opens a new tab.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

$bsk = Join-Path $env:USERPROFILE '.local\bin\bsk.exe'
if (-not (Test-Path -LiteralPath $bsk)) {
    $f = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bsk = $f.FullName }
}
$outDir = Join-Path (Get-Location).Path 'results\jobs\browser\phaseD3'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$logPath = Join-Path $outDir 'phaseD3.log'
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
Log ('phaseD3: session ' + $sid)

# 0. ALWAYS navigate to arena.ai and wait for the app to render
$null = (& $bsk navigate 'https://arena.ai' --session $sid 2>&1 | Out-String)
$null = (& $bsk wait-ms 12s --session $sid 2>&1 | Out-String)
$s0 = Snap 'd3_s0_home.txt'
Log ('phaseD3: home bytes=' + $s0.Length)

# 1. hide the promo card if present
$hideRef = [regex]::Match($s0, '@(e\d+) button "Hide this').Groups[1].Value
if ($hideRef) {
    $null = (& $bsk click ('@' + $hideRef) --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 2s --session $sid 2>&1 | Out-String)
    Log ('phaseD3: hid promo @' + $hideRef)
    $s0 = Snap 'd3_s0b_nopromo.txt'
}

# 2. switch to Agent Mode
if ($s0 -match 'combobox[^\r\n]*="Agent"') {
    Log 'phaseD3: already Agent mode'
} else {
    $cbRef = [regex]::Match($s0, '@(e\d+) combobox').Groups[1].Value
    $null = (& $bsk click ('@' + $cbRef) --session $sid 2>&1 | Out-String)
    Log ('phaseD3: opened menu @' + $cbRef)
    $null = (& $bsk wait-ms 2s --session $sid 2>&1 | Out-String)
    $s1 = Snap 'd3_s1_menu.txt'
    $btnRef = [regex]::Match($s1, '@(e\d+) button "Agent Mode').Groups[1].Value
    $ok = $false
    if ($btnRef) {
        $null = (& $bsk click ('@' + $btnRef) --session $sid 2>&1 | Out-String)
        Log ('phaseD3: clicked Agent Mode button @' + $btnRef + ' (exit ' + $LASTEXITCODE + ')')
        $null = (& $bsk wait-ms 3s --session $sid 2>&1 | Out-String)
        $s2 = Snap 'd3_s2_after_btn.txt'
        $ok = ($s2 -match 'combobox[^\r\n]*="Agent"') -or ($s2 -match 'active: Agent')
    }
    if (-not $ok) {
        Log 'phaseD3: keyboard fallback'
        $cbRef2 = [regex]::Match($s2, '@(e\d+) combobox').Groups[1].Value
        if ($cbRef2) {
            $null = (& $bsk click ('@' + $cbRef2) --session $sid 2>&1 | Out-String)
            $null = (& $bsk wait-ms 1s --session $sid 2>&1 | Out-String)
        }
        $null = (& $bsk press ArrowDown --session $sid 2>&1 | Out-String)
        $null = (& $bsk press Enter --session $sid 2>&1 | Out-String)
        $null = (& $bsk wait-ms 3s --session $sid 2>&1 | Out-String)
        $s2 = Snap 'd3_s3_after_keys.txt'
        $ok = ($s2 -match 'combobox[^\r\n]*="Agent"') -or ($s2 -match 'active: Agent')
    }
    if ($ok) { Log 'phaseD3: SUCCESS - Agent mode selected' } else { Log 'phaseD3: WARN mode not flipped - dumped state' }
}

# 3. recon the agent-mode UI for the GitHub control
$s3 = Snap 'd3_s4_agent_ui.txt'
$ghRef = ''
foreach ($mm in [regex]::Matches($s3, '@(e\d+) (?:button|link|menuitem)[^\r\n]*')) {
    if ($mm.Value -match 'GitHub|Connect|Repo') { $ghRef = $mm.Groups[1].Value; Log ('phaseD3: candidate control -> ' + $mm.Value.Trim().Substring(0, [Math]::Min(110, $mm.Value.Trim().Length))); if (-not $ghRef) { continue } }
}
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'd3_agent_ui.png') 2>&1 | Out-String)

# 4. click the first GitHub-ish control and record the navigation result
if ($ghRef) {
    $null = (& $bsk click ('@' + $ghRef) --session $sid 2>&1 | Out-String)
    Log ('phaseD3: clicked control @' + $ghRef + ' (exit ' + $LASTEXITCODE + ')')
    $null = (& $bsk wait-ms 6s --session $sid 2>&1 | Out-String)
    $s4 = Snap 'd3_s5_after_click.txt'
    $url = (& $bsk evaluate location.href --session $sid 2>&1 | Out-String)
    Log ('phaseD3: url now -> ' + $url.Trim().Substring(0, [Math]::Min(160, $url.Trim().Length)))
    $ttl = (& $bsk evaluate document.title --session $sid 2>&1 | Out-String)
    Log ('phaseD3: title now -> ' + $ttl.Trim().Substring(0, [Math]::Min(120, $ttl.Trim().Length)))
    $null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'd3_after_click.png') 2>&1 | Out-String)
} else {
    Log 'phaseD3: no GitHub control visible - full snapshot saved for analysis'
}
Log 'phaseD3: done'
$lines | Set-Content -LiteralPath $logPath -Encoding UTF8
exit 0
