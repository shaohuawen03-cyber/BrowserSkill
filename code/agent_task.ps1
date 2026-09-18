# agent_task.ps1 - stage 7 PHASE K4: borrow + black-shell aware retries.
# Data: borrow succeeds (100%) but the borrowed tab is sometimes a sleeping
# shell, and /agent in it then renders an alert-only page ("Agent Mode |"
# + alert, no composer). r30/r35 succeeded right after USER activity; the
# tab sleeps between rounds. K4: borrow -> if the home page is a shell:
#   1) tab select + reload; 2) navigate to plain arena.ai (landing is the
#   lightest page); 3) re-borrow (stop session first); 4) up to 2 full
#   recycle rounds with 60s settle gaps. THEN open the connected chat:
#   deep link first (error -> /agent list -> click the newest Today link).
# Rest as before: continue-click needle, clipboard prompt, send, monitor.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

$bsk = Join-Path $env:USERPROFILE '.local\bin\bsk.exe'
if (-not (Test-Path -LiteralPath $bsk)) {
    $f = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bsk = $f.FullName }
}
$outDir = Join-Path (Get-Location).Path 'results\jobs\browser\phaseK4'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$logPath = Join-Path $outDir 'phaseK4.log'
$lines = New-Object System.Collections.Generic.List[string]
function Log([string]$s) { $script:lines.Add($s) | Out-Null; Write-Output $s }
function Snap([string]$name) {
    $s = (& $bsk snapshot --session $script:sid --max-tokens 30000 2>&1 | Out-String)
    $s | Set-Content -LiteralPath (Join-Path $outDir $name) -Encoding UTF8
    return $s
}
function Scroll-Bottom {
    $null = (& $bsk evaluate '(function(){var d=document.scrollingElement;d.scrollTop=d.scrollHeight;return d.scrollTop;})()' --session $script:sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 3s --session $script:sid 2>&1 | Out-String)
}
function Test-Shell([string]$s) {
    return (($s -match 'RootWebArea\s*(\r?\n|$)') -and ($s.Length -lt 300)) -or ($s.Length -lt 200)
}

$env:BSK_AUTO_START = '0'

# ---- acquire an AWAKE arena tab (up to 3 recycle rounds) ----
$rendered = $false
for ($cycle = 1; $cycle -le 3 -and -not $rendered; $cycle++) {
    $null = (& $bsk session stop --all 2>&1 | Out-String)
    $null = (& $bsk wait-ms 3s --session '' 2>&1 | Out-String)
    $st = (& $bsk session start --name ('arena-k4-' + $cycle) --json 2>&1 | Out-String)
    $m = [regex]::Match($st, '"session_id"\s*:\s*"([^"]+)"')
    if (-not $m.Success) { $m = [regex]::Match($st, '"id"\s*:\s*"([^"]+)"') }
    $sid = ''
    if ($m.Success) { $sid = $m.Groups[1].Value }
    if (-not $sid) { Log ('[FAIL] no session on cycle ' + $cycle); continue }
    $sid | Set-Content -LiteralPath (Join-Path (Get-Location).Path 'results\status\bsk_session.txt') -Encoding Ascii
    Log ('phaseK4: cycle ' + $cycle + ' session ' + $sid)

    $tabs = (& $bsk tab list --session $sid --json 2>&1 | Out-String)
    $tid = ''
    foreach ($mm in [regex]::Matches($tabs, '\{[^{}]*\}')) {
        if ($mm.Value -match 'arena\.ai') { $cand = [regex]::Match($mm.Value, '"tab_id"\s*:\s*(\d+)').Groups[1].Value; if ($cand -and -not $tid) { $tid = $cand } }
    }
    Log ('phaseK4: cycle ' + $cycle + ' arena tab ' + $tid)
    if (-not $tid) { Log 'phaseK4: no arena tab - keep arena.ai open in your browser'; continue }
    $bo = (& $bsk tab borrow $tid --session $sid --timeout 300 2>&1 | Out-String)
    Log ('phaseK4: borrow exit ' + $LASTEXITCODE)
    if ($LASTEXITCODE -ne 0) { continue }
    $null = (& $bsk tab select $tid --session $sid 2>&1 | Out-String)

    # wake: landing page first (lightest), then the app
    $null = (& $bsk navigate 'https://arena.ai' --session $sid 2>&1 | Out-String)
    for ($i = 1; $i -le 24; $i++) {
        $null = (& $bsk wait-ms 5s --session $sid 2>&1 | Out-String)
        $w = Snap ('k4_wake_c' + $cycle + '_p' + $i + '.txt')
        if (-not (Test-Shell $w)) { Log ('phaseK4: tab awake (landing) at poll ' + $i); break }
        if ($i -eq 8 -or $i -eq 16) { $null = (& $bsk tab select $tid --session $sid 2>&1 | Out-String); $null = (& $bsk reload --session $sid 2>&1 | Out-String) }
    }
    $null = (& $bsk navigate 'https://arena.ai/agent' --session $sid 2>&1 | Out-String)
    for ($i = 1; $i -le 24; $i++) {
        $null = (& $bsk wait-ms 5s --session $sid 2>&1 | Out-String)
        $s0 = Snap ('k4_home_c' + $cycle + '_p' + $i + '.txt')
        if (($s0 -match 'textbox') -and ($s0 -match 'Today')) { $rendered = $true; Log ('phaseK4: home rendered, cycle ' + $cycle + ' poll ' + $i); break }
        if (Test-Shell $s0) { $null = (& $bsk tab select $tid --session $sid 2>&1 | Out-String); $null = (& $bsk reload --session $sid 2>&1 | Out-String) }
    }
    if ($rendered) { break }
    Log ('phaseK4: cycle ' + $cycle + ' failed - recycling')
}
if (-not $rendered) { Log '[FAIL] no awake tab after 3 cycles - the bridge needs user activity (open arena.ai once)'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'k4_home.png') 2>&1 | Out-String)

# ---- open the connected conversation ----
Scroll-Bottom
$s0 = Snap 'k4_homelist.txt'
$chatRef = ''
foreach ($mm in [regex]::Matches($s0, '@(e\d+) link[^\r\n]*')) {
    if ($mm.Value -match '01a0aeb9') { $chatRef = $mm.Groups[1].Value; break }
}
$opened = $false
if ($chatRef) {
    $null = (& $bsk click ('@' + $chatRef) --session $sid 2>&1 | Out-String)
    Log ('phaseK4: clicked the connected chat @' + $chatRef)
    for ($i = 1; $i -le 24; $i++) {
        $null = (& $bsk wait-ms 5s --session $sid 2>&1 | Out-String)
        $s0 = Snap ('k4_conv_poll' + $i + '.txt')
        if (($s0 -match 'textbox') -and ($s0 -match 'combobox')) { $opened = $true; Log ('phaseK4: conversation open (poll ' + $i + ')'); break }
    }
}
if (-not $opened) {
    Log 'phaseK4: list route failed - deep link'
    $null = (& $bsk navigate 'https://arena.ai/agent/01a0b237-fad1-7168-8115-d3f52e550489' --session $sid 2>&1 | Out-String)
    for ($i = 1; $i -le 24; $i++) {
        $null = (& $bsk wait-ms 5s --session $sid 2>&1 | Out-String)
        $s0 = Snap ('k4_deep_poll' + $i + '.txt')
        if (($s0 -match 'textbox') -and ($s0 -match 'combobox')) { $opened = $true; Log ('phaseK4: deep link opened (poll ' + $i + ')'); break }
        if ($s0 -match "couldn't load this chat") { $null = (& $bsk reload --session $sid 2>&1 | Out-String) }
    }
}
if (-not $opened) { Log '[FAIL] conversation never opened'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
Scroll-Bottom
$s0 = Snap 'k4_conv_bottom.txt'
Log ('phaseK4: mode reads: ' + [regex]::Match($s0, '@e\d+ combobox "([^"]*)"').Groups[1].Value)

# ---- continue-working click (GBK needle at runtime) ----
$needle = -join @([char]0x7F01, [char]0x0445, [char]0x753B, [char]0x5BB8, [char]0x30E4, [char]0x7D94)
$contRef = ''
foreach ($mm in [regex]::Matches($s0, '@(e\d+) button[^\r\n]*')) {
    if ($mm.Value.Contains($needle)) { $contRef = $mm.Groups[1].Value; Log ('phaseK4: continue button @' + $contRef); break }
}
if ($contRef) {
    $null = (& $bsk click ('@' + $contRef) --session $sid 2>&1 | Out-String)
    Log ('phaseK4: clicked continue (exit ' + $LASTEXITCODE + ')')
    $null = (& $bsk wait-ms 4s --session $sid 2>&1 | Out-String)
    Scroll-Bottom
    $s0 = Snap 'k4_after_continue.txt'
} else {
    Log 'phaseK4: no continue button visible - composer may be free'
}

# ---- clipboard the round-2 prompt ----
$promptFile = Join-Path (Get-Location).Path 'results\status\arena_prompt2.txt'
$msg = (Get-Content -LiteralPath $promptFile -Raw -Encoding UTF8).Trim()
Log ('phaseK4: prompt2 chars=' + $msg.Length)
Set-Clipboard -Value $msg
$filled = $false
for ($att = 1; $att -le 4 -and -not $filled; $att++) {
    $s1 = Snap ('k4_att' + $att + '_a.txt')
    $tbRef = [regex]::Match($s1, '@(e\d+) textbox').Groups[1].Value
    if (-not $tbRef) { Log ('phaseK4: att ' + $att + ' - no textbox'); continue }
    $null = (& $bsk click ('@' + $tbRef) --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 700ms --session $sid 2>&1 | Out-String)
    $null = (& $bsk press Ctrl+v --session $sid 2>&1 | Out-String)
    Log ('phaseK4: att ' + $att + ' click @' + $tbRef + ' + Ctrl+v (exit ' + $LASTEXITCODE + ')')
    $null = (& $bsk wait-ms 1500ms --session $sid 2>&1 | Out-String)
    $s3 = Snap ('k4_att' + $att + '_c.txt')
    if (($s3 -match '01a0aeb9') -or ($s3 -match 'textbox[^\r\n]*\[filled\]')) { $filled = $true; Log ('phaseK4: att ' + $att + ' - PROMPT IN COMPOSER') }
    else {
        $s2 = Snap ('k4_att' + $att + '_b.txt')
        $tbRef2 = [regex]::Match($s2, '@(e\d+) textbox').Groups[1].Value
        if ($tbRef2) { $null = (& $bsk fill ('@' + $tbRef2) --value $msg --session $sid 2>&1 | Out-String); Log ('phaseK4: fallback fill exit ' + $LASTEXITCODE) }
        $null = (& $bsk wait-ms 1000ms --session $sid 2>&1 | Out-String)
        $s3 = Snap ('k4_att' + $att + '_d.txt')
        if (($s3 -match '01a0aeb9') -or ($s3 -match 'textbox[^\r\n]*\[filled\]')) { $filled = $true; Log ('phaseK4: att ' + $att + ' - PROMPT IN COMPOSER via fill') }
    }
}
if (-not $filled) { Log '[FAIL] composer never held the prompt'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }

# ---- send ----
$s4 = Snap 'k4_before_send.txt'
$sendRef = [regex]::Match($s4, '@(e\d+) button "Send message').Groups[1].Value
if ($sendRef) {
    $null = (& $bsk click ('@' + $sendRef) --session $sid 2>&1 | Out-String)
    Log ('phaseK4: clicked Send @' + $sendRef + ' (exit ' + $LASTEXITCODE + ')')
} else {
    $null = (& $bsk press Enter --session $sid 2>&1 | Out-String)
    Log 'phaseK4: Enter fallback'
}

# ---- dispatch + monitor ----
$echo = $false
for ($i = 1; $i -le 4; $i++) {
    $null = (& $bsk wait-ms 12s --session $sid 2>&1 | Out-String)
    $sx = Snap ('k4_send_poll' + $i + '.txt')
    if ($sx -match 'Stop generating') { $echo = $true; Log ('phaseK4: generation running at poll ' + $i); break }
}
if (-not $echo) { Log 'phaseK4: WARN dispatch unconfirmed' }
$found = $false
for ($i = 1; $i -le 25; $i++) {
    Scroll-Bottom
    $sx = Snap ('k4_mon' + $i + '.txt')
    $running = ($sx -match 'Stop generating')
    Log ('phaseK4: mon ' + $i + ' running=' + $running + ' bytes=' + $sx.Length)
    if (-not $running -and $i -gt 2) { $found = $true; Log ('phaseK4: generation finished at mon ' + $i); break }
    $null = (& $bsk wait-ms 15s --session $sid 2>&1 | Out-String)
}
Scroll-Bottom
$t = (& $bsk evaluate document.body.innerText --session $sid 2>&1 | Out-String)
$t | Set-Content -LiteralPath (Join-Path $outDir 'k4_page_text.txt') -Encoding UTF8
Log ('phaseK4: page text bytes=' + $t.Length)
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'k4_final.png') 2>&1 | Out-String)
Log 'phaseK4: done - round-2 prompt sent; session OPEN'
$lines | Set-Content -LiteralPath $logPath -Encoding UTF8
exit 0
