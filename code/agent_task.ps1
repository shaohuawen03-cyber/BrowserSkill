# agent_task.ps1 - stage 6 PHASE H2: borrow + wake + run.
# H proof: borrow works with zero clicks (user disabled the confirm) but the
# idle tab arrives SLEEPING (68-byte snapshot). H2: borrow -> diagnose
# (title/href/readyState) -> navigate the borrowed tab to /agent (wakes it;
# the human session cookies ride along) -> render wait -> J-style
# ref-refreshing fill -> send -> echo + evidence. Tab stays borrowed.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

$bsk = Join-Path $env:USERPROFILE '.local\bin\bsk.exe'
if (-not (Test-Path -LiteralPath $bsk)) {
    $f = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bsk = $f.FullName }
}
$outDir = Join-Path (Get-Location).Path 'results\jobs\browser\phaseH2'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$logPath = Join-Path $outDir 'phaseH2.log'
$lines = New-Object System.Collections.Generic.List[string]
function Log([string]$s) { $script:lines.Add($s) | Out-Null; Write-Output $s }
function Snap([string]$name) {
    $s = (& $bsk snapshot --session $script:sid --max-tokens 30000 2>&1 | Out-String)
    $s | Set-Content -LiteralPath (Join-Path $outDir $name) -Encoding UTF8
    return $s
}

$env:BSK_AUTO_START = '0'
$null = (& $bsk session stop --all 2>&1 | Out-String)
$st = (& $bsk session start --name 'arena-h2' --json 2>&1 | Out-String)
$m = [regex]::Match($st, '"session_id"\s*:\s*"([^"]+)"')
if (-not $m.Success) { $m = [regex]::Match($st, '"id"\s*:\s*"([^"]+)"') }
$sid = ''
if ($m.Success) { $sid = $m.Groups[1].Value }
if (-not $sid) { Log '[FAIL] no session'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
$sid | Set-Content -LiteralPath (Join-Path (Get-Location).Path 'results\status\bsk_session.txt') -Encoding Ascii
Log ('phaseH2: session ' + $sid)

# 1. find + borrow the user's arena tab (no confirm needed now)
$tabs = (& $bsk tab list --session $sid --json 2>&1 | Out-String)
$tabs | Set-Content -LiteralPath (Join-Path $outDir 'h2_tabs.json') -Encoding UTF8
$tid = ''
foreach ($mm in [regex]::Matches($tabs, '\{[^{}]*\}')) {
    if ($mm.Value -match 'arena\.ai') {
        $cand = [regex]::Match($mm.Value, '"tab_id"\s*:\s*(\d+)').Groups[1].Value
        if ($cand -and -not $tid) { $tid = $cand }
    }
}
Log ('phaseH2: arena tab ' + $tid)
if (-not $tid) { Log '[FAIL] no arena tab in the browser - open arena.ai once'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
$bo = (& $bsk tab borrow $tid --session $sid --timeout 300 2>&1 | Out-String)
$bo | Set-Content -LiteralPath (Join-Path $outDir 'h2_borrow.json') -Encoding UTF8
Log ('phaseH2: borrow exit ' + $LASTEXITCODE + ' ' + (($bo -replace '\s+', ' ').Trim().Substring(0, [Math]::Min(140, $bo.Trim().Length))))
if ($LASTEXITCODE -ne 0) { Log '[FAIL] borrow failed'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
$null = (& $bsk wait-ms 2s --session $sid 2>&1 | Out-String)

# 2. diagnose the sleeping tab
$d1 = (& $bsk evaluate document.title + ' | ' + document.readyState + ' | ' + location.href --session $sid 2>&1 | Out-String)
Log ('phaseH2: borrowed tab now -> ' + (($d1 -replace '\s+', ' ').Trim().Substring(0, [Math]::Min(150, $d1.Trim().Length))))

# 3. wake it: navigate the borrowed tab to /agent
$null = (& $bsk navigate 'https://arena.ai/agent' --session $sid 2>&1 | Out-String)
$rendered = $false
for ($i = 1; $i -le 12; $i++) {
    $null = (& $bsk wait-ms 10s --session $sid 2>&1 | Out-String)
    $s0 = Snap ('h2_poll' + $i + '.txt')
    if (($s0 -match 'Ask anything') -or ($s0 -match 'combobox') -or ($s0 -match 'What would you like')) { $rendered = $true; Log ('phaseH2: RENDERED at poll ' + $i); break }
    if ($i -eq 5 -or $i -eq 9) { $null = (& $bsk reload --session $sid 2>&1 | Out-String) }
}
if (-not $rendered) { Log '[FAIL] borrowed tab will not render /agent'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
$mode = [regex]::Match($s0, '@e\d+ combobox "([^"]*)"').Groups[1].Value
Log ('phaseH2: mode reads: ' + $mode)
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'h2_rendered.png') 2>&1 | Out-String)

# 4. promo
$hideRef = [regex]::Match($s0, '@(e\d+) button "Hide this').Groups[1].Value
if ($hideRef) {
    $null = (& $bsk click ('@' + $hideRef) --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 2s --session $sid 2>&1 | Out-String)
    Log ('phaseH2: hid promo @' + $hideRef)
}

# 5. ref-refreshing fill loop (J recipe)
$promptFile = Join-Path (Get-Location).Path 'results\status\arena_prompt.txt'
$msg = (Get-Content -LiteralPath $promptFile -Raw -Encoding UTF8).Trim()
Log ('phaseH2: prompt chars=' + $msg.Length)
$filled = $false
for ($att = 1; $att -le 4 -and -not $filled; $att++) {
    $s1 = Snap ('h2_att' + $att + '_a.txt')
    $tbRef = [regex]::Match($s1, '@(e\d+) textbox').Groups[1].Value
    if (-not $tbRef) { Log ('phaseH2: att ' + $att + ' - no textbox'); continue }
    $null = (& $bsk click ('@' + $tbRef) --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 600ms --session $sid 2>&1 | Out-String)
    $s2 = Snap ('h2_att' + $att + '_b.txt')
    $tbRef2 = [regex]::Match($s2, '@(e\d+) textbox').Groups[1].Value
    if (-not $tbRef2) { $tbRef2 = $tbRef }
    $null = (& $bsk fill ('@' + $tbRef2) --value $msg --session $sid 2>&1 | Out-String)
    Log ('phaseH2: att ' + $att + ' fill @' + $tbRef2 + ' exit ' + $LASTEXITCODE)
    $null = (& $bsk wait-ms 1200ms --session $sid 2>&1 | Out-String)
    $s3 = Snap ('h2_att' + $att + '_c.txt')
    if (($s3 -match '01a0aeb9') -or ($s3 -match 'textbox[^\r\n]*\[filled\]')) { $filled = $true; Log ('phaseH2: att ' + $att + ' - PROMPT IN COMPOSER') }
    else { Log ('phaseH2: att ' + $att + ' - still empty') }
}
if (-not $filled) { Log '[FAIL] composer never held the prompt'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }

# 6. send
$s4 = Snap 'h2_before_send.txt'
$sendRef = [regex]::Match($s4, '@(e\d+) button "Send message').Groups[1].Value
if ($sendRef) {
    $null = (& $bsk click ('@' + $sendRef) --session $sid 2>&1 | Out-String)
    Log ('phaseH2: clicked Send @' + $sendRef + ' (exit ' + $LASTEXITCODE + ')')
} else {
    $null = (& $bsk press Enter --session $sid 2>&1 | Out-String)
    Log 'phaseH2: Enter fallback'
}

# 7. echo + evidence
$echo = $false
for ($i = 1; $i -le 4; $i++) {
    $null = (& $bsk wait-ms 12s --session $sid 2>&1 | Out-String)
    $sx = Snap ('h2_send_poll' + $i + '.txt')
    if ($sx -match '01a0aeb9') { $echo = $true; Log ('phaseH2: prompt echo at poll ' + $i); break }
}
if (-not $echo) { Log 'phaseH2: WARN no echo yet' }
$null = (& $bsk wait-ms 30s --session $sid 2>&1 | Out-String)
$null = Snap 'h2_progress1.txt'
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'h2_sent.png') 2>&1 | Out-String)
Log 'phaseH2: done - round-1 prompt sent in the borrowed tab; session OPEN'
$lines | Set-Content -LiteralPath $logPath -Encoding UTF8
exit 0
