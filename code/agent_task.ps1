# agent_task.ps1 - stage 7 PHASE K: reuse the CONNECTED arena conversation.
# Round 1 is done; the connected conversation (arena.ai/agent/01a0b237-fad1-...)
# waits for a "continue working" click before it accepts a new task. K:
# borrow the live tab -> open the conversation -> render+scroll -> click the
# continue button (matched via runtime-built GBK-mojibake needle, ASCII-safe)
# -> clipboard-paste the round-2 prompt (3 self-loop rounds) -> verify ->
# send -> monitor 25 polls with rolling evidence.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

$bsk = Join-Path $env:USERPROFILE '.local\bin\bsk.exe'
if (-not (Test-Path -LiteralPath $bsk)) {
    $f = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bsk = $f.FullName }
}
$outDir = Join-Path (Get-Location).Path 'results\jobs\browser\phaseK'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$logPath = Join-Path $outDir 'phaseK.log'
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

$env:BSK_AUTO_START = '0'
$null = (& $bsk session stop --all 2>&1 | Out-String)
$st = (& $bsk session start --name 'arena-round2' --json 2>&1 | Out-String)
$m = [regex]::Match($st, '"session_id"\s*:\s*"([^"]+)"')
if (-not $m.Success) { $m = [regex]::Match($st, '"id"\s*:\s*"([^"]+)"') }
$sid = ''
if ($m.Success) { $sid = $m.Groups[1].Value }
if (-not $sid) { Log '[FAIL] no session'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
$sid | Set-Content -LiteralPath (Join-Path (Get-Location).Path 'results\status\bsk_session.txt') -Encoding Ascii
Log ('phaseK: session ' + $sid)

# 1. borrow the user's arena tab
$tabs = (& $bsk tab list --session $sid --json 2>&1 | Out-String)
$tabs | Set-Content -LiteralPath (Join-Path $outDir 'k_tabs.json') -Encoding UTF8
$tid = ''
foreach ($mm in [regex]::Matches($tabs, '\{[^{}]*\}')) {
    if ($mm.Value -match 'arena\.ai') {
        $cand = [regex]::Match($mm.Value, '"tab_id"\s*:\s*(\d+)').Groups[1].Value
        if ($cand -and -not $tid) { $tid = $cand }
    }
}
Log ('phaseK: arena tab ' + $tid)
if (-not $tid) { Log '[FAIL] no arena tab - keep arena.ai open'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
$bo = (& $bsk tab borrow $tid --session $sid --timeout 300 2>&1 | Out-String)
Log ('phaseK: borrow exit ' + $LASTEXITCODE)
if ($LASTEXITCODE -ne 0) { Log '[FAIL] borrow failed'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
$null = (& $bsk tab select $tid --session $sid 2>&1 | Out-String)

# 2. open the connected conversation (deep link first; on "couldn't load"
#    fall back to /agent and click the newest Today chat entry)
$null = (& $bsk navigate 'https://arena.ai/agent/01a0b237-fad1-7168-8115-d3f52e550489' --session $sid 2>&1 | Out-String)
$rendered = $false
for ($i = 1; $i -le 20; $i++) {
    $null = (& $bsk wait-ms 5s --session $sid 2>&1 | Out-String)
    $s0 = Snap ('k_poll' + $i + '.txt')
    if (($s0 -match 'textbox') -and ($s0 -match 'combobox')) { $rendered = $true; Log ('phaseK: conversation rendered at poll ' + $i); break }
    if ($s0 -match "couldn't load this chat") { Log ('phaseK: deep link failed at poll ' + $i); break }
}
if (-not $rendered) {
    Log 'phaseK: falling back to /agent + newest Today chat'
    $null = (& $bsk navigate 'https://arena.ai/agent' --session $sid 2>&1 | Out-String)
    $home = $false
    for ($i = 1; $i -le 20 -and -not $home; $i++) {
        $null = (& $bsk wait-ms 5s --session $sid 2>&1 | Out-String)
        $s0 = Snap ('k_home_poll' + $i + '.txt')
        if ($s0 -match 'textbox') { $home = $true }
    }
    Scroll-Bottom
    $s0 = Snap 'k_home_list.txt'
    $chatRef = [regex]::Match($s0, '@(e\d+) link[^(\r\n]{0,80}').Groups[1].Value
    Log ('phaseK: newest Today chat @' + $chatRef)
    if ($chatRef) {
        $null = (& $bsk click ('@' + $chatRef) --session $sid 2>&1 | Out-String)
        for ($i = 1; $i -le 20; $i++) {
            $null = (& $bsk wait-ms 5s --session $sid 2>&1 | Out-String)
            $s0 = Snap ('k_conv_poll' + $i + '.txt')
            if (($s0 -match 'textbox') -and ($s0 -match 'combobox')) { $rendered = $true; Log ('phaseK: conversation open via list click (poll ' + $i + ')'); break }
        }
    }
}
if (-not $rendered) { Log '[FAIL] conversation did not render'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
Scroll-Bottom
$s0 = Snap 'k_bottom.txt'

# 3. click the continue-working button (needle built from codepoints at runtime)
$needle = -join @([char]0x7F01, [char]0x0445, [char]0x753B, [char]0x5BB8, [char]0x30E4, [char]0x7D94)
$contRef = ''
foreach ($mm in [regex]::Matches($s0, '@(e\d+) button[^\r\n]*')) {
    if ($mm.Value.Contains($needle)) { $contRef = $mm.Groups[1].Value; Log ('phaseK: continue button @' + $contRef); break }
}
if ($contRef) {
    $null = (& $bsk click ('@' + $contRef) --session $sid 2>&1 | Out-String)
    Log ('phaseK: clicked continue (exit ' + $LASTEXITCODE + ')')
    $null = (& $bsk wait-ms 4s --session $sid 2>&1 | Out-String)
    Scroll-Bottom
    $s0 = Snap 'k_after_continue.txt'
} else {
    Log 'phaseK: no continue button visible - composer may already be free'
}

# 4. clipboard paste the round-2 prompt
$promptFile = Join-Path (Get-Location).Path 'results\status\arena_prompt2.txt'
$msg = (Get-Content -LiteralPath $promptFile -Raw -Encoding UTF8).Trim()
Log ('phaseK: prompt2 chars=' + $msg.Length)
Set-Clipboard -Value $msg
$filled = $false
for ($att = 1; $att -le 4 -and -not $filled; $att++) {
    $s1 = Snap ('k_att' + $att + '_a.txt')
    $tbRef = [regex]::Match($s1, '@(e\d+) textbox').Groups[1].Value
    if (-not $tbRef) { Log ('phaseK: att ' + $att + ' - no textbox'); continue }
    $null = (& $bsk click ('@' + $tbRef) --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 700ms --session $sid 2>&1 | Out-String)
    $null = (& $bsk press Ctrl+v --session $sid 2>&1 | Out-String)
    Log ('phaseK: att ' + $att + ' click @' + $tbRef + ' + Ctrl+v (exit ' + $LASTEXITCODE + ')')
    $null = (& $bsk wait-ms 1500ms --session $sid 2>&1 | Out-String)
    $s3 = Snap ('k_att' + $att + '_c.txt')
    if (($s3 -match '01a0aeb9') -or ($s3 -match 'textbox[^\r\n]*\[filled\]')) { $filled = $true; Log ('phaseK: att ' + $att + ' - PROMPT IN COMPOSER') }
    else {
        $s2 = Snap ('k_att' + $att + '_b.txt')
        $tbRef2 = [regex]::Match($s2, '@(e\d+) textbox').Groups[1].Value
        if ($tbRef2) { $null = (& $bsk fill ('@' + $tbRef2) --value $msg --session $sid 2>&1 | Out-String); Log ('phaseK: fallback fill exit ' + $LASTEXITCODE) }
        $null = (& $bsk wait-ms 1000ms --session $sid 2>&1 | Out-String)
        $s3 = Snap ('k_att' + $att + '_d.txt')
        if (($s3 -match '01a0aeb9') -or ($s3 -match 'textbox[^\r\n]*\[filled\]')) { $filled = $true; Log ('phaseK: att ' + $att + ' - PROMPT IN COMPOSER via fill') }
    }
}
if (-not $filled) { Log '[FAIL] composer never held the prompt'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }

# 5. send
$s4 = Snap 'k_before_send.txt'
$sendRef = [regex]::Match($s4, '@(e\d+) button "Send message').Groups[1].Value
if ($sendRef) {
    $null = (& $bsk click ('@' + $sendRef) --session $sid 2>&1 | Out-String)
    Log ('phaseK: clicked Send @' + $sendRef + ' (exit ' + $LASTEXITCODE + ')')
} else {
    $null = (& $bsk press Enter --session $sid 2>&1 | Out-String)
    Log 'phaseK: Enter fallback'
}

# 6. confirm dispatch, then monitor 25 polls (rolling evidence for the loop)
$echo = $false
for ($i = 1; $i -le 4; $i++) {
    $null = (& $bsk wait-ms 12s --session $sid 2>&1 | Out-String)
    $sx = Snap ('k_send_poll' + $i + '.txt')
    if ($sx -match 'Stop generating') { $echo = $true; Log ('phaseK: generation running (Stop button) at poll ' + $i); break }
    if ($sx -match '01a0aeb9') { $echo = $true; Log ('phaseK: prompt echo at poll ' + $i); break }
}
if (-not $echo) { Log 'phaseK: WARN dispatch unconfirmed - captured anyway' }
$found = $false
for ($i = 1; $i -le 25; $i++) {
    Scroll-Bottom
    $sx = Snap ('k_mon' + $i + '.txt')
    $running = ($sx -match 'Stop generating')
    Log ('phaseK: mon ' + $i + ' running=' + $running + ' bytes=' + $sx.Length)
    if (-not $running -and $i -gt 2) { $found = $true; Log ('phaseK: generation finished at mon ' + $i); break }
    $null = (& $bsk wait-ms 15s --session $sid 2>&1 | Out-String)
}
Scroll-Bottom
$t = (& $bsk evaluate document.body.innerText --session $sid 2>&1 | Out-String)
$t | Set-Content -LiteralPath (Join-Path $outDir 'k_page_text.txt') -Encoding UTF8
Log ('phaseK: page text bytes=' + $t.Length)
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'k_final.png') 2>&1 | Out-String)
Log 'phaseK: done - round-2 prompt sent and monitored'
$lines | Set-Content -LiteralPath $logPath -Encoding UTF8
exit 0
