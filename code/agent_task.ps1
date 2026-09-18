# agent_task.ps1 - stage 3 PHASE E3: foreground session + render diagnostics.
# E2 hypothesis: the --no-focus Agent Window gets JS-throttled by Edge and the
# SPA never finishes rendering. E3 opens a FOCUSED session (visible window),
# polls render state with readyState/title/href diagnostics + screenshots,
# reloads once, then flips Agent mode and captures the GitHub menus.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

$bsk = Join-Path $env:USERPROFILE '.local\bin\bsk.exe'
if (-not (Test-Path -LiteralPath $bsk)) {
    $f = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bsk = $f.FullName }
}
$outDir = Join-Path (Get-Location).Path 'results\jobs\browser\phaseE3'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$logPath = Join-Path $outDir 'phaseE3.log'
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

# 0. stop any old sessions, start ONE FOCUSED session
$null = (& $bsk session stop --all 2>&1 | Out-String)
$st = (& $bsk session start --name 'arena-agent-mode' --json 2>&1 | Out-String)
$st | Set-Content -LiteralPath (Join-Path $outDir 'session_start.json') -Encoding UTF8
$m = [regex]::Match($st, '"session_id"\s*:\s*"([^"]+)"')
if (-not $m.Success) { $m = [regex]::Match($st, '"id"\s*:\s*"([^"]+)"') }
$sid = ''
if ($m.Success) { $sid = $m.Groups[1].Value }
if (-not $sid) { Log ('[FAIL] no session: ' + (($st -replace '\s+', ' ').Trim().Substring(0, [Math]::Min(200, $st.Trim().Length)))); $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
$sid | Set-Content -LiteralPath (Join-Path (Get-Location).Path 'results\status\bsk_session.txt') -Encoding Ascii
Log ('phaseE3: focused session ' + $sid)

# 1. navigate + poll render with diagnostics
$rendered = $false
for ($try = 1; $try -le 2 -and -not $rendered; $try++) {
    $null = (& $bsk navigate 'https://arena.ai' --session $sid 2>&1 | Out-String)
    for ($i = 1; $i -le 6; $i++) {
        $null = (& $bsk wait-ms 10s --session $sid 2>&1 | Out-String)
        $rs = (& $bsk evaluate document.readyState --session $sid 2>&1 | Out-String)
        $ttl = (& $bsk evaluate document.title --session $sid 2>&1 | Out-String)
        $s0 = Snap ('e3_s_try' + $try + '_poll' + $i + '.txt')
        Log ('phaseE3: try' + $try + ' poll' + $i + ' ready=' + $rs.Trim() + ' title=' + $ttl.Trim().Substring(0, [Math]::Min(40, $ttl.Trim().Length)) + ' bytes=' + $s0.Length)
        if ($i -eq 2) { $null = (& $bsk screenshot --session $sid --out (Join-Path $outDir ('e3_try' + $try + '_early.png')) 2>&1 | Out-String) }
        if (Test-Rendered $s0) { $rendered = $true; Log ('phaseE2: rendered on try ' + $try + ' poll ' + $i); break }
    }
    if (-not $rendered) { Log ('phaseE3: try ' + $try + ' failed - reloading'); $null = (& $bsk reload --session $sid 2>&1 | Out-String) }
}
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'e3_rendered.png') 2>&1 | Out-String)
if (-not $rendered) { Log '[FAIL] arena.ai still not rendering - evidence captured'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }

# 2. promo
$hideRef = [regex]::Match($s0, '@(e\d+) button "Hide this').Groups[1].Value
if ($hideRef) {
    $null = (& $bsk click ('@' + $hideRef) --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 2s --session $sid 2>&1 | Out-String)
    $s0 = Snap 'e3_s0b_nopromo.txt'
    Log ('phaseE3: hid promo @' + $hideRef)
}

# 3. Agent mode (three recipes)
if (Test-AgentMode $s0) {
    Log 'phaseE3: already Agent'
} else {
    $done = $false
    foreach ($recipe in @('AD', 'TA', 'AU')) {
        $cbRef = [regex]::Match($s0, '@(e\d+) combobox').Groups[1].Value
        if (-not $cbRef) { $s0 = Snap 'e3_refind.txt'; $cbRef = [regex]::Match($s0, '@(e\d+) combobox').Groups[1].Value }
        if (-not $cbRef) { Log 'phaseE3: no combobox trigger'; break }
        $null = (& $bsk click ('@' + $cbRef) --session $sid 2>&1 | Out-String)
        $null = (& $bsk wait-ms 1500ms --session $sid 2>&1 | Out-String)
        if ($recipe -eq 'AD') { $null = (& $bsk press ArrowDown --session $sid 2>&1 | Out-String) }
        elseif ($recipe -eq 'TA') { $null = (& $bsk press a --session $sid 2>&1 | Out-String) }
        else { $null = (& $bsk press ArrowUp --session $sid 2>&1 | Out-String) }
        $null = (& $bsk wait-ms 400ms --session $sid 2>&1 | Out-String)
        $null = (& $bsk press Enter --session $sid 2>&1 | Out-String)
        $null = (& $bsk wait-ms 2500ms --session $sid 2>&1 | Out-String)
        $s0 = Snap ('e3_s1_after_' + $recipe + '.txt')
        if (Test-AgentMode $s0) { $done = $true; Log ('phaseE3: Agent mode via ' + $recipe); break }
        Log ('phaseE3: recipe ' + $recipe + ' did not stick')
    }
    if (-not $done) { Log 'phaseE3: WARN mode flip failed - continuing with evidence' }
}

# 4. GitHub settings menu
$s2 = Snap 'e3_s2_agent.txt'
$ghRef = [regex]::Match($s2, '@(e\d+) button "GitHub settings').Groups[1].Value
Log ('phaseE3: GitHub settings @' + $ghRef)
if ($ghRef) {
    $null = (& $bsk click ('@' + $ghRef) --session $sid 2>&1 | Out-String)
    Log ('phaseE3: clicked GitHub settings (exit ' + $LASTEXITCODE + ')')
    $null = (& $bsk wait-ms 4s --session $sid 2>&1 | Out-String)
    $null = Snap 'e3_s3_gh_menu.txt'
    $null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'e3_gh_menu.png') 2>&1 | Out-String)
    $tabs = (& $bsk tab list --session $sid --json 2>&1 | Out-String)
    $tabs | Set-Content -LiteralPath (Join-Path $outDir 'e3_tabs.json') -Encoding UTF8
    Log ('phaseE3: tabs -> ' + (($tabs -replace '\s+', ' ').Trim().Substring(0, [Math]::Min(240, $tabs.Trim().Length))))
    $url = (& $bsk evaluate location.href --session $sid 2>&1 | Out-String)
    Log ('phaseE3: url -> ' + $url.Trim().Substring(0, [Math]::Min(140, $url.Trim().Length)))
    $null = (& $bsk press Escape --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 1200ms --session $sid 2>&1 | Out-String)
}

# 5. Add files and connections menu
$s3 = Snap 'e3_s4_fresh.txt'
$addRef = [regex]::Match($s3, '@(e\d+) button "Add files and connections').Groups[1].Value
Log ('phaseE3: Add files and connections @' + $addRef)
if ($addRef) {
    $null = (& $bsk click ('@' + $addRef) --session $sid 2>&1 | Out-String)
    Log ('phaseE3: clicked Add files and connections (exit ' + $LASTEXITCODE + ')')
    $null = (& $bsk wait-ms 3s --session $sid 2>&1 | Out-String)
    $null = Snap 'e3_s5_add_menu.txt'
    $null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'e3_add_menu.png') 2>&1 | Out-String)
    $null = (& $bsk press Escape --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 1s --session $sid 2>&1 | Out-String)
}
Log 'phaseE3: done'
$lines | Set-Content -LiteralPath $logPath -Encoding UTF8
exit 0
