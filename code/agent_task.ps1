# agent_task.ps1 - stage 3 PHASE E2: render-robust Agent mode + GitHub recon.
# E1 failed because the SPA sometimes never renders (only a loading shell).
# E2 polls the aria snapshot until the composer actually appears (max ~70s,
# one reload retry), THEN flips to Agent mode (3 keyboard recipes) and opens
# the GitHub settings menu + Add-connections menu with captures.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

$bsk = Join-Path $env:USERPROFILE '.local\bin\bsk.exe'
if (-not (Test-Path -LiteralPath $bsk)) {
    $f = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bsk = $f.FullName }
}
$outDir = Join-Path (Get-Location).Path 'results\jobs\browser\phaseE2'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$logPath = Join-Path $outDir 'phaseE2.log'
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
    $st = (& $bsk session start --no-focus --name 'arena-agent-mode' --json 2>&1 | Out-String)
    $m = [regex]::Match($st, '"session_id"\s*:\s*"([^"]+)"')
    if (-not $m.Success) { $m = [regex]::Match($st, '"id"\s*:\s*"([^"]+)"') }
    if ($m.Success) { $sid = $m.Groups[1].Value } else { Log ('[FAIL] no session'); $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
    $sid | Set-Content -LiteralPath $sidFile -Encoding Ascii
}
Log ('phaseE2: session ' + $sid)

# 0. navigate + wait for a REAL render (poll, reload once)
$rendered = $false
for ($try = 1; $try -le 2 -and -not $rendered; $try++) {
    $null = (& $bsk navigate 'https://arena.ai' --session $sid 2>&1 | Out-String)
    for ($i = 1; $i -le 7; $i++) {
        $null = (& $bsk wait-ms 10s --session $sid 2>&1 | Out-String)
        $s0 = Snap ('e2_s0_try' + $try + '_poll' + $i + '.txt')
        if (Test-Rendered $s0) { $rendered = $true; Log ('phaseE2: rendered on try ' + $try + ' poll ' + $i); break }
    }
    if (-not $rendered) { Log ('phaseE2: try ' + $try + ' - still a loading shell, reloading'); }
}
if (-not $rendered) { Log '[FAIL] arena.ai never rendered'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }

# 1. promo
$hideRef = [regex]::Match($s0, '@(e\d+) button "Hide this').Groups[1].Value
if ($hideRef) {
    $null = (& $bsk click ('@' + $hideRef) --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 2s --session $sid 2>&1 | Out-String)
    $s0 = Snap 'e2_s0b_nopromo.txt'
    Log ('phaseE2: hid promo @' + $hideRef)
}

# 2. Agent mode (three recipes)
if (Test-AgentMode $s0) {
    Log 'phaseE2: already Agent'
} else {
    $done = $false
    foreach ($recipe in @('AD', 'TA', 'AU')) {
        $cbRef = [regex]::Match($s0, '@(e\d+) combobox').Groups[1].Value
        if (-not $cbRef) { $s0 = Snap 'e2_refind_trigger.txt'; $cbRef = [regex]::Match($s0, '@(e\d+) combobox').Groups[1].Value }
        if (-not $cbRef) { Log 'phaseE2: WARN no combobox trigger in the tree'; break }
        $null = (& $bsk click ('@' + $cbRef) --session $sid 2>&1 | Out-String)
        $null = (& $bsk wait-ms 1500ms --session $sid 2>&1 | Out-String)
        if ($recipe -eq 'AD') { $null = (& $bsk press ArrowDown --session $sid 2>&1 | Out-String) }
        elseif ($recipe -eq 'TA') { $null = (& $bsk press a --session $sid 2>&1 | Out-String) }
        else { $null = (& $bsk press ArrowUp --session $sid 2>&1 | Out-String) }
        $null = (& $bsk wait-ms 400ms --session $sid 2>&1 | Out-String)
        $null = (& $bsk press Enter --session $sid 2>&1 | Out-String)
        $null = (& $bsk wait-ms 2500ms --session $sid 2>&1 | Out-String)
        $s0 = Snap ('e2_s1_after_' + $recipe + '.txt')
        if (Test-AgentMode $s0) { $done = $true; Log ('phaseE2: Agent mode via ' + $recipe); break }
        Log ('phaseE2: recipe ' + $recipe + ' did not stick')
    }
    if (-not $done) { Log 'phaseE2: WARN mode flip failed - capturing evidence and continuing' }
}

# 3. GitHub settings menu
$s2 = Snap 'e2_s2_agent.txt'
$ghRef = [regex]::Match($s2, '@(e\d+) button "GitHub settings').Groups[1].Value
Log ('phaseE2: GitHub settings @' + $ghRef)
if ($ghRef) {
    $null = (& $bsk click ('@' + $ghRef) --session $sid 2>&1 | Out-String)
    Log ('phaseE2: clicked GitHub settings (exit ' + $LASTEXITCODE + ')')
    $null = (& $bsk wait-ms 4s --session $sid 2>&1 | Out-String)
    $null = Snap 'e2_s3_gh_menu.txt'
    $null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'e2_gh_menu.png') 2>&1 | Out-String)
    $tabs = (& $bsk tab list --session $sid --json 2>&1 | Out-String)
    $tabs | Set-Content -LiteralPath (Join-Path $outDir 'e2_tabs.json') -Encoding UTF8
    Log ('phaseE2: tabs -> ' + (($tabs -replace '\s+', ' ').Trim().Substring(0, [Math]::Min(240, $tabs.Trim().Length))))
    $url = (& $bsk evaluate location.href --session $sid 2>&1 | Out-String)
    Log ('phaseE2: url -> ' + $url.Trim().Substring(0, [Math]::Min(140, $url.Trim().Length)))
    $null = (& $bsk press Escape --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 1200ms --session $sid 2>&1 | Out-String)
}

# 4. Add files and connections menu
$s3 = Snap 'e2_s4_fresh.txt'
$addRef = [regex]::Match($s3, '@(e\d+) button "Add files and connections').Groups[1].Value
Log ('phaseE2: Add files and connections @' + $addRef)
if ($addRef) {
    $null = (& $bsk click ('@' + $addRef) --session $sid 2>&1 | Out-String)
    Log ('phaseE2: clicked Add files and connections (exit ' + $LASTEXITCODE + ')')
    $null = (& $bsk wait-ms 3s --session $sid 2>&1 | Out-String)
    $null = Snap 'e2_s5_add_menu.txt'
    $null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'e2_add_menu.png') 2>&1 | Out-String)
    $null = (& $bsk press Escape --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 1s --session $sid 2>&1 | Out-String)
}
Log 'phaseE2: done'
$lines | Set-Content -LiteralPath $logPath -Encoding UTF8
exit 0
