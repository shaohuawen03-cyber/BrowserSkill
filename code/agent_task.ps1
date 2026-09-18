# agent_task.ps1 - stage 7 PHASE K3: OWN tab (no borrowing).
# User guidance: borrowing wedges on sleepy tabs; open arena fresh in the
# Agent Window instead. K3: fresh session -> tab create -> arena.ai/agent
# HOME (never the deep link; it 500s) -> multi-strategy render wait ->
# scroll the Today list -> click the CONNECTED conversation entry -> verify
# -> continue-click (GBK needle) -> clipboard the 3-round prompt -> send ->
# monitor. Own tabs close with the session - the user's browser is untouched.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

$bsk = Join-Path $env:USERPROFILE '.local\bin\bsk.exe'
if (-not (Test-Path -LiteralPath $bsk)) {
    $f = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bsk = $f.FullName }
}
$outDir = Join-Path (Get-Location).Path 'results\jobs\browser\phaseK3'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$logPath = Join-Path $outDir 'phaseK3.log'
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
$st = (& $bsk session start --name 'arena-round2-own' --json 2>&1 | Out-String)
$m = [regex]::Match($st, '"session_id"\s*:\s*"([^"]+)"')
if (-not $m.Success) { $m = [regex]::Match($st, '"id"\s*:\s*"([^"]+)"') }
$sid = ''
if ($m.Success) { $sid = $m.Groups[1].Value }
if (-not $sid) { Log '[FAIL] no session'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
$sid | Set-Content -LiteralPath (Join-Path (Get-Location).Path 'results\status\bsk_session.txt') -Encoding Ascii
Log ('phaseK3: session ' + $sid)

# 1. open arena HOME in an OWN tab inside the Agent Window
$null = (& $bsk tab create 'https://arena.ai/agent' --session $sid 2>&1 | Out-String)
$rendered = $false
for ($i = 1; $i -le 40; $i++) {
    $null = (& $bsk wait-ms 5s --session $sid 2>&1 | Out-String)
    $s0 = Snap ('k3_home_poll' + $i + '.txt')
    if (($s0 -match 'textbox') -and ($s0 -match 'Today')) { $rendered = $true; Log ('phaseK3: home rendered at poll ' + $i); break }
    if ($i -eq 12 -or $i -eq 26) { Log ('phaseK3: poll ' + $i + ' - reload'); $null = (& $bsk reload --session $sid 2>&1 | Out-String) }
    if ($i -eq 20) {
        Log 'phaseK3: poll 20 - trying a brand-new second tab'
        $null = (& $bsk tab create 'https://arena.ai/agent' --session $sid 2>&1 | Out-String)
    }
}
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'k3_home.png') 2>&1 | Out-String)
if (-not $rendered) { Log '[FAIL] arena home not rendering in own tab'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }

# 2. open the connected conversation from the Today list (scroll first)
$chatRef = ''
for ($pass = 1; $pass -le 4 -and -not $chatRef; $pass++) {
    Scroll-Bottom
    $s0 = Snap ('k3_list_pass' + $pass + '.txt')
    foreach ($mm in [regex]::Matches($s0, '@(e\d+) link[^\r\n]*')) {
        if ($mm.Value -match '01a0aeb9' -or $mm.Value -match '\[https://github.com/shaohuawen03-cyber/new/tree/arena') { $chatRef = $mm.Groups[1].Value; Log ('phaseK3: connected chat @' + $chatRef); break }
    }
    if (-not $chatRef) { Log ('phaseK3: pass ' + $pass + ' - connected chat not in list yet'); $null = (& $bsk wait-ms 5s --session $sid 2>&1 | Out-String) }
}
$opened = $false
if ($chatRef) {
    $null = (& $bsk click ('@' + $chatRef) --session $sid 2>&1 | Out-String)
    Log ('phaseK3: clicked the connected chat (exit ' + $LASTEXITCODE + ')')
    for ($i = 1; $i -le 20; $i++) {
        $null = (& $bsk wait-ms 5s --session $sid 2>&1 | Out-String)
        $s0 = Snap ('k3_conv_poll' + $i + '.txt')
        if (($s0 -match 'textbox') -and ($s0 -match 'combobox')) { $opened = $true; Log ('phaseK3: conversation open (poll ' + $i + ')'); break }
    }
} else {
    # list never showed it: use the deep link AFTER the app was already alive
    Log 'phaseK3: list lacks the chat - trying the deep link now'
    $null = (& $bsk navigate 'https://arena.ai/agent/01a0b237-fad1-7168-8115-d3f52e550489' --session $sid 2>&1 | Out-String)
    for ($i = 1; $i -le 24; $i++) {
        $null = (& $bsk wait-ms 5s --session $sid 2>&1 | Out-String)
        $s0 = Snap ('k3_deep_poll' + $i + '.txt')
        if (($s0 -match 'textbox') -and ($s0 -match 'combobox')) { $opened = $true; Log ('phaseK3: deep link opened (poll ' + $i + ')'); break }
        if ($s0 -match "couldn't load this chat") { Log ('phaseK3: deep link error at poll ' + $i); $null = (& $bsk reload --session $sid 2>&1 | Out-String) }
    }
}
if (-not $opened) { Log '[FAIL] conversation never opened'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
Scroll-Bottom
$s0 = Snap 'k3_conv_bottom.txt'
Log ('phaseK3: mode reads: ' + [regex]::Match($s0, '@e\d+ combobox "([^"]*)"').Groups[1].Value)

# 3. continue-working button (GBK needle built at runtime)
$needle = -join @([char]0x7F01, [char]0x0445, [char]0x753B, [char]0x5BB8, [char]0x30E4, [char]0x7D94)
$contRef = ''
foreach ($mm in [regex]::Matches($s0, '@(e\d+) button[^\r\n]*')) {
    if ($mm.Value.Contains($needle)) { $contRef = $mm.Groups[1].Value; Log ('phaseK3: continue button @' + $contRef); break }
}
if ($contRef) {
    $null = (& $bsk click ('@' + $contRef) --session $sid 2>&1 | Out-String)
    Log ('phaseK3: clicked continue (exit ' + $LASTEXITCODE + ')')
    $null = (& $bsk wait-ms 4s --session $sid 2>&1 | Out-String)
    Scroll-Bottom
    $s0 = Snap 'k3_after_continue.txt'
} else {
    Log 'phaseK3: no continue button visible - composer may be free'
}

# 4. clipboard the round-2 prompt
$promptFile = Join-Path (Get-Location).Path 'results\status\arena_prompt2.txt'
$msg = (Get-Content -LiteralPath $promptFile -Raw -Encoding UTF8).Trim()
Log ('phaseK3: prompt2 chars=' + $msg.Length)
Set-Clipboard -Value $msg
$filled = $false
for ($att = 1; $att -le 4 -and -not $filled; $att++) {
    $s1 = Snap ('k3_att' + $att + '_a.txt')
    $tbRef = [regex]::Match($s1, '@(e\d+) textbox').Groups[1].Value
    if (-not $tbRef) { Log ('phaseK3: att ' + $att + ' - no textbox'); continue }
    $null = (& $bsk click ('@' + $tbRef) --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 700ms --session $sid 2>&1 | Out-String)
    $null = (& $bsk press Ctrl+v --session $sid 2>&1 | Out-String)
    Log ('phaseK3: att ' + $att + ' click @' + $tbRef + ' + Ctrl+v (exit ' + $LASTEXITCODE + ')')
    $null = (& $bsk wait-ms 1500ms --session $sid 2>&1 | Out-String)
    $s3 = Snap ('k3_att' + $att + '_c.txt')
    if (($s3 -match '01a0aeb9') -or ($s3 -match 'textbox[^\r\n]*\[filled\]')) { $filled = $true; Log ('phaseK3: att ' + $att + ' - PROMPT IN COMPOSER') }
    else {
        $s2 = Snap ('k3_att' + $att + '_b.txt')
        $tbRef2 = [regex]::Match($s2, '@(e\d+) textbox').Groups[1].Value
        if ($tbRef2) { $null = (& $bsk fill ('@' + $tbRef2) --value $msg --session $sid 2>&1 | Out-String); Log ('phaseK3: fallback fill exit ' + $LASTEXITCODE) }
        $null = (& $bsk wait-ms 1000ms --session $sid 2>&1 | Out-String)
        $s3 = Snap ('k3_att' + $att + '_d.txt')
        if (($s3 -match '01a0aeb9') -or ($s3 -match 'textbox[^\r\n]*\[filled\]')) { $filled = $true; Log ('phaseK3: att ' + $att + ' - PROMPT IN COMPOSER via fill') }
    }
}
if (-not $filled) { Log '[FAIL] composer never held the prompt'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }

# 5. send
$s4 = Snap 'k3_before_send.txt'
$sendRef = [regex]::Match($s4, '@(e\d+) button "Send message').Groups[1].Value
if ($sendRef) {
    $null = (& $bsk click ('@' + $sendRef) --session $sid 2>&1 | Out-String)
    Log ('phaseK3: clicked Send @' + $sendRef + ' (exit ' + $LASTEXITCODE + ')')
} else {
    $null = (& $bsk press Enter --session $sid 2>&1 | Out-String)
    Log 'phaseK3: Enter fallback'
}

# 6. confirm dispatch + monitor (rolling)
$echo = $false
for ($i = 1; $i -le 4; $i++) {
    $null = (& $bsk wait-ms 12s --session $sid 2>&1 | Out-String)
    $sx = Snap ('k3_send_poll' + $i + '.txt')
    if ($sx -match 'Stop generating') { $echo = $true; Log ('phaseK3: generation running at poll ' + $i); break }
}
if (-not $echo) { Log 'phaseK3: WARN dispatch unconfirmed' }
$found = $false
for ($i = 1; $i -le 25; $i++) {
    Scroll-Bottom
    $sx = Snap ('k3_mon' + $i + '.txt')
    $running = ($sx -match 'Stop generating')
    Log ('phaseK3: mon ' + $i + ' running=' + $running + ' bytes=' + $sx.Length)
    if (-not $running -and $i -gt 2) { $found = $true; Log ('phaseK3: generation finished at mon ' + $i); break }
    $null = (& $bsk wait-ms 15s --session $sid 2>&1 | Out-String)
}
Scroll-Bottom
$t = (& $bsk evaluate document.body.innerText --session $sid 2>&1 | Out-String)
$t | Set-Content -LiteralPath (Join-Path $outDir 'k3_page_text.txt') -Encoding UTF8
Log ('phaseK3: page text bytes=' + $t.Length)
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'k3_final.png') 2>&1 | Out-String)
Log 'phaseK3: done - round-2 prompt sent in an own tab; session OPEN'
$lines | Set-Content -LiteralPath $logPath -Encoding UTF8
exit 0
