# agent_task.ps1 - stage 6 PHASE H4: keep-the-tab-awake run.
# Pattern: the borrowed tab renders instantly while it is AWAKE (r27) and
# fails while asleep (r29). H4: borrow -> ACTIVATE the tab (tab select) ->
# 150s patient render wait (5s polls, reloads at 8/16/24) -> if still dead:
# stop session (tab returns home awake-ish), re-borrow, navigate, one more
# wait -> then Agent-mode check + clipboard paste + send + echo.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

$bsk = Join-Path $env:USERPROFILE '.local\bin\bsk.exe'
if (-not (Test-Path -LiteralPath $bsk)) {
    $f = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bsk = $f.FullName }
}
$outDir = Join-Path (Get-Location).Path 'results\jobs\browser\phaseH4'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$logPath = Join-Path $outDir 'phaseH4.log'
$lines = New-Object System.Collections.Generic.List[string]
function Log([string]$s) { $script:lines.Add($s) | Out-Null; Write-Output $s }
function Snap([string]$name) {
    $s = (& $bsk snapshot --session $script:sid --max-tokens 30000 2>&1 | Out-String)
    $s | Set-Content -LiteralPath (Join-Path $outDir $name) -Encoding UTF8
    return $s
}
function Wait-Render([string]$tag) {
    $ok = $false
    for ($i = 1; $i -le 30; $i++) {
        $null = (& $bsk wait-ms 5s --session $script:sid 2>&1 | Out-String)
        $s = Snap ($tag + '_poll' + $i + '.txt')
        if (($s -match 'Ask anything') -or ($s -match 'combobox') -or ($s -match 'What would you like')) { return $true }
        if ($i -eq 8 -or $i -eq 16 -or $i -eq 24) { $null = (& $bsk reload --session $script:sid 2>&1 | Out-String) }
    }
    return $ok
}

$env:BSK_AUTO_START = '0'
$null = (& $bsk session stop --all 2>&1 | Out-String)
$st = (& $bsk session start --name 'arena-h4' --json 2>&1 | Out-String)
$m = [regex]::Match($st, '"session_id"\s*:\s*"([^"]+)"')
if (-not $m.Success) { $m = [regex]::Match($st, '"id"\s*:\s*"([^"]+)"') }
$sid = ''
if ($m.Success) { $sid = $m.Groups[1].Value }
if (-not $sid) { Log '[FAIL] no session'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
$sid | Set-Content -LiteralPath (Join-Path (Get-Location).Path 'results\status\bsk_session.txt') -Encoding Ascii
Log ('phaseH4: session ' + $sid)

# 1. find + borrow + ACTIVATE
$tabs = (& $bsk tab list --session $sid --json 2>&1 | Out-String)
$tabs | Set-Content -LiteralPath (Join-Path $outDir 'h4_tabs.json') -Encoding UTF8
$tid = ''
foreach ($mm in [regex]::Matches($tabs, '\{[^{}]*\}')) {
    if ($mm.Value -match 'arena\.ai') {
        $cand = [regex]::Match($mm.Value, '"tab_id"\s*:\s*(\d+)').Groups[1].Value
        if ($cand -and -not $tid) { $tid = $cand }
    }
}
Log ('phaseH4: arena tab ' + $tid)
if (-not $tid) { Log '[FAIL] no arena tab - keep arena.ai open'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
$bo = (& $bsk tab borrow $tid --session $sid --timeout 300 2>&1 | Out-String)
Log ('phaseH4: borrow exit ' + $LASTEXITCODE)
if ($LASTEXITCODE -ne 0) { Log '[FAIL] borrow failed'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
$null = (& $bsk wait-ms 2s --session $sid 2>&1 | Out-String)
$null = (& $bsk tab select $tid --session $sid 2>&1 | Out-String)
Log ('phaseH4: tab select exit ' + $LASTEXITCODE)

# 2. render (attempt 1: activate + wait; attempt 2: navigate; attempt 3: re-borrow + navigate)
$rendered = Wait-Render 'h4_a1'
if (-not $rendered) {
    Log 'phaseH4: attempt 1 failed - navigating the borrowed tab'
    $null = (& $bsk navigate 'https://arena.ai/agent' --session $sid 2>&1 | Out-String)
    $rendered = Wait-Render 'h4_a2'
}
if (-not $rendered) {
    Log 'phaseH4: attempt 2 failed - full recycle: stop, re-borrow, navigate'
    $null = (& $bsk session stop --all 2>&1 | Out-String)
    $null = (& $bsk wait-ms 3s --session '' 2>&1 | Out-String)
    $st = (& $bsk session start --name 'arena-h4b' --json 2>&1 | Out-String)
    $m = [regex]::Match($st, '"session_id"\s*:\s*"([^"]+)"')
    if (-not $m.Success) { $m = [regex]::Match($st, '"id"\s*:\s*"([^"]+)"') }
    if ($m.Success) { $sid = $m.Groups[1].Value }
    $sid | Set-Content -LiteralPath (Join-Path (Get-Location).Path 'results\status\bsk_session.txt') -Encoding Ascii
    $bo = (& $bsk tab borrow $tid --session $sid --timeout 300 2>&1 | Out-String)
    Log ('phaseH4: re-borrow exit ' + $LASTEXITCODE)
    if ($LASTEXITCODE -eq 0) {
        $null = (& $bsk tab select $tid --session $sid 2>&1 | Out-String)
        $null = (& $bsk navigate 'https://arena.ai/agent' --session $sid 2>&1 | Out-String)
        $rendered = Wait-Render 'h4_a3'
    }
}
if (-not $rendered) { Log '[FAIL] still not rendering after 3 attempts'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
Log 'phaseH4: RENDERED'

# 3. promo
$s0 = Snap 'h4_rendered.txt'
$hideRef = [regex]::Match($s0, '@(e\d+) button "Hide this').Groups[1].Value
if ($hideRef) {
    $null = (& $bsk click ('@' + $hideRef) --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 2s --session $sid 2>&1 | Out-String)
    Log ('phaseH4: hid promo @' + $hideRef)
}
Log ('phaseH4: mode reads: ' + [regex]::Match($s0, '@e\d+ combobox "([^"]*)"').Groups[1].Value)

# 4. clipboard paste loop
$promptFile = Join-Path (Get-Location).Path 'results\status\arena_prompt.txt'
$msg = (Get-Content -LiteralPath $promptFile -Raw -Encoding UTF8).Trim()
Log ('phaseH4: prompt chars=' + $msg.Length)
Set-Clipboard -Value $msg
Log 'phaseH4: prompt placed on the clipboard'
$filled = $false
for ($att = 1; $att -le 4 -and -not $filled; $att++) {
    $s1 = Snap ('h4_att' + $att + '_a.txt')
    $tbRef = [regex]::Match($s1, '@(e\d+) textbox').Groups[1].Value
    if (-not $tbRef) { Log ('phaseH4: att ' + $att + ' - no textbox'); continue }
    $null = (& $bsk click ('@' + $tbRef) --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 700ms --session $sid 2>&1 | Out-String)
    $null = (& $bsk press Ctrl+v --session $sid 2>&1 | Out-String)
    Log ('phaseH4: att ' + $att + ' click @' + $tbRef + ' + Ctrl+v (exit ' + $LASTEXITCODE + ')')
    $null = (& $bsk wait-ms 1500ms --session $sid 2>&1 | Out-String)
    $s3 = Snap ('h4_att' + $att + '_c.txt')
    if (($s3 -match '01a0aeb9') -or ($s3 -match 'textbox[^\r\n]*\[filled\]')) { $filled = $true; Log ('phaseH4: att ' + $att + ' - PROMPT IN COMPOSER') }
    else {
        $s2 = Snap ('h4_att' + $att + '_b.txt')
        $tbRef2 = [regex]::Match($s2, '@(e\d+) textbox').Groups[1].Value
        if ($tbRef2) { $null = (& $bsk fill ('@' + $tbRef2) --value $msg --session $sid 2>&1 | Out-String); Log ('phaseH4: fallback fill exit ' + $LASTEXITCODE) }
        $null = (& $bsk wait-ms 1000ms --session $sid 2>&1 | Out-String)
        $s3 = Snap ('h4_att' + $att + '_d.txt')
        if (($s3 -match '01a0aeb9') -or ($s3 -match 'textbox[^\r\n]*\[filled\]')) { $filled = $true; Log ('phaseH4: att ' + $att + ' - PROMPT IN COMPOSER via fill') }
    }
}
if (-not $filled) { Log '[FAIL] composer never held the prompt'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }

# 5. send
$s4 = Snap 'h4_before_send.txt'
$sendRef = [regex]::Match($s4, '@(e\d+) button "Send message').Groups[1].Value
if ($sendRef) {
    $null = (& $bsk click ('@' + $sendRef) --session $sid 2>&1 | Out-String)
    Log ('phaseH4: clicked Send @' + $sendRef + ' (exit ' + $LASTEXITCODE + ')')
} else {
    $null = (& $bsk press Enter --session $sid 2>&1 | Out-String)
    Log 'phaseH4: Enter fallback'
}

# 6. echo + evidence
$echo = $false
for ($i = 1; $i -le 4; $i++) {
    $null = (& $bsk wait-ms 12s --session $sid 2>&1 | Out-String)
    $sx = Snap ('h4_send_poll' + $i + '.txt')
    if ($sx -match '01a0aeb9') { $echo = $true; Log ('phaseH4: prompt echo at poll ' + $i); break }
}
if (-not $echo) { Log 'phaseH4: WARN no echo yet' }
$null = (& $bsk wait-ms 30s --session $sid 2>&1 | Out-String)
$null = Snap 'h4_progress1.txt'
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'h4_sent.png') 2>&1 | Out-String)
Log 'phaseH4: done - round-1 prompt sent; session OPEN'
$lines | Set-Content -LiteralPath $logPath -Encoding UTF8
exit 0
