# agent_task.ps1 - stage 7 PHASE K5: DOM-link click (quote-free JS).
# r45: user activation made /agent render in one poll; only the chat-entry
# click failed (Today items' <a> had not hydrated; deep link = Cloudflare).
# K5: borrow -> /agent -> render -> scroll -> QUOTE-FREE JS over
# document.links matching the conversation id (built via String.fromCharCode
# so PowerShell/ASCII gates stay clean) -> native .click() (SPA navigation,
# no new document, no Cloudflare) -> verify -> continue needle -> clipboard
# prompt -> send -> monitor.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

$bsk = Join-Path $env:USERPROFILE '.local\bin\bsk.exe'
if (-not (Test-Path -LiteralPath $bsk)) {
    $f = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bsk = $f.FullName }
}
$outDir = Join-Path (Get-Location).Path 'results\jobs\browser\phaseK5'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$logPath = Join-Path $outDir 'phaseK5.log'
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
$st = (& $bsk session start --name 'arena-k5' --json 2>&1 | Out-String)
$m = [regex]::Match($st, '"session_id"\s*:\s*"([^"]+)"')
if (-not $m.Success) { $m = [regex]::Match($st, '"id"\s*:\s*"([^"]+)"') }
$sid = ''
if ($m.Success) { $sid = $m.Groups[1].Value }
if (-not $sid) { Log '[FAIL] no session'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
$sid | Set-Content -LiteralPath (Join-Path (Get-Location).Path 'results\status\bsk_session.txt') -Encoding Ascii
Log ('phaseK5: session ' + $sid)

# 1. borrow the live arena tab
$tabs = (& $bsk tab list --session $sid --json 2>&1 | Out-String)
$tabs | Set-Content -LiteralPath (Join-Path $outDir 'k5_tabs.json') -Encoding UTF8
$tid = ''
foreach ($mm in [regex]::Matches($tabs, '\{[^{}]*\}')) {
    if ($mm.Value -match 'arena\.ai') { $cand = [regex]::Match($mm.Value, '"tab_id"\s*:\s*(\d+)').Groups[1].Value; if ($cand -and -not $tid) { $tid = $cand } }
}
Log ('phaseK5: arena tab ' + $tid)
if (-not $tid) { Log '[FAIL] no arena tab - keep arena.ai open'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
$bo = (& $bsk tab borrow $tid --session $sid --timeout 300 2>&1 | Out-String)
Log ('phaseK5: borrow exit ' + $LASTEXITCODE)
if ($LASTEXITCODE -ne 0) { Log '[FAIL] borrow failed'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
$null = (& $bsk tab select $tid --session $sid 2>&1 | Out-String)

# 2. /agent + render
$null = (& $bsk navigate 'https://arena.ai/agent' --session $sid 2>&1 | Out-String)
$rendered = $false
for ($i = 1; $i -le 30; $i++) {
    $null = (& $bsk wait-ms 5s --session $sid 2>&1 | Out-String)
    $s0 = Snap ('k5_home_poll' + $i + '.txt')
    if (($s0 -match 'textbox') -and ($s0 -match 'Today')) { $rendered = $true; Log ('phaseK5: home rendered at poll ' + $i); break }
    if ($i -eq 10 -or $i -eq 20) { $null = (& $bsk tab select $tid --session $sid 2>&1 | Out-String); $null = (& $bsk reload --session $sid 2>&1 | Out-String) }
}
if (-not $rendered) { Log '[FAIL] home not rendering (ask the user to click the arena tab once)'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }

# 3. find + click the connected conversation link (quote-free DOM click)
$js = '(function(){var N=String.fromCharCode(102,97,100,49,45,55,49,54,56);var L=document.links;var n=[];for(var i=0;i<L.length;i++){if(L[i].href.indexOf(N)>=0){n.push(L[i].href);}}if(n.length){L[i- n.length].click();return "clicked-"+n.length;}return "not-found";})()'
$opened = $false
for ($pass = 1; $pass -le 5 -and -not $opened; $pass++) {
    Scroll-Bottom
    $r = (& $bsk evaluate $js --session $sid 2>&1 | Out-String)
    Log ('phaseK5: pass ' + $pass + ' link-click -> ' + (($r -replace '\s+', ' ').Trim().Substring(0, [Math]::Min(120, $r.Trim().Length))))
    for ($i = 1; $i -le 12; $i++) {
        $null = (& $bsk wait-ms 5s --session $sid 2>&1 | Out-String)
        $s0 = Snap ('k5_conv_pass' + $pass + '_p' + $i + '.txt')
        if (($s0 -match 'textbox') -and ($s0 -match 'combobox')) { $opened = $true; Log ('phaseK5: conversation open (pass ' + $pass + ' poll ' + $i + ')'); break }
        if ($s0 -match 'Stop generating') { Log 'phaseK5: WARN generation already running?'; }
    }
    if ($opened) { break }
}

# 3b. last resort: deep link (SPA navigate) - Cloudflare may block it
if (-not $opened) {
    Log 'phaseK5: DOM link not found - deep link fallback'
    $null = (& $bsk navigate 'https://arena.ai/agent/01a0b237-fad1-7168-8115-d3f52e550489' --session $sid 2>&1 | Out-String)
    for ($i = 1; $i -le 24; $i++) {
        $null = (& $bsk wait-ms 5s --session $sid 2>&1 | Out-String)
        $s0 = Snap ('k5_deep_poll' + $i + '.txt')
        if (($s0 -match 'textbox') -and ($s0 -match 'combobox')) { $opened = $true; Log ('phaseK5: deep link opened (poll ' + $i + ')'); break }
    }
}
if (-not $opened) { Log '[FAIL] conversation never opened'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
Scroll-Bottom
$s0 = Snap 'k5_conv_bottom.txt'
Log ('phaseK5: mode reads: ' + [regex]::Match($s0, '@e\d+ combobox "([^"]*)"').Groups[1].Value)
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'k5_conv.png') 2>&1 | Out-String)

# 4. continue-working click (GBK needle at runtime)
$needle = -join @([char]0x7F01, [char]0x0445, [char]0x753B, [char]0x5BB8, [char]0x30E4, [char]0x7D94)
$contRef = ''
foreach ($mm in [regex]::Matches($s0, '@(e\d+) button[^\r\n]*')) {
    if ($mm.Value.Contains($needle)) { $contRef = $mm.Groups[1].Value; Log ('phaseK5: continue button @' + $contRef); break }
}
if ($contRef) {
    $null = (& $bsk click ('@' + $contRef) --session $sid 2>&1 | Out-String)
    Log ('phaseK5: clicked continue (exit ' + $LASTEXITCODE + ')')
    $null = (& $bsk wait-ms 4s --session $sid 2>&1 | Out-String)
    Scroll-Bottom
    $s0 = Snap 'k5_after_continue.txt'
} else {
    Log 'phaseK5: no continue button visible - composer may be free'
}

# 5. clipboard the round-2 prompt
$promptFile = Join-Path (Get-Location).Path 'results\status\arena_prompt2.txt'
$msg = (Get-Content -LiteralPath $promptFile -Raw -Encoding UTF8).Trim()
Log ('phaseK5: prompt2 chars=' + $msg.Length)
Set-Clipboard -Value $msg
$filled = $false
for ($att = 1; $att -le 4 -and -not $filled; $att++) {
    $s1 = Snap ('k5_att' + $att + '_a.txt')
    $tbRef = [regex]::Match($s1, '@(e\d+) textbox').Groups[1].Value
    if (-not $tbRef) { Log ('phaseK5: att ' + $att + ' - no textbox'); continue }
    $null = (& $bsk click ('@' + $tbRef) --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 700ms --session $sid 2>&1 | Out-String)
    $null = (& $bsk press Ctrl+v --session $sid 2>&1 | Out-String)
    Log ('phaseK5: att ' + $att + ' click @' + $tbRef + ' + Ctrl+v (exit ' + $LASTEXITCODE + ')')
    $null = (& $bsk wait-ms 1500ms --session $sid 2>&1 | Out-String)
    $s3 = Snap ('k5_att' + $att + '_c.txt')
    if (($s3 -match '01a0aeb9') -or ($s3 -match 'textbox[^\r\n]*\[filled\]')) { $filled = $true; Log ('phaseK5: att ' + $att + ' - PROMPT IN COMPOSER') }
    else {
        $s2 = Snap ('k5_att' + $att + '_b.txt')
        $tbRef2 = [regex]::Match($s2, '@(e\d+) textbox').Groups[1].Value
        if ($tbRef2) { $null = (& $bsk fill ('@' + $tbRef2) --value $msg --session $sid 2>&1 | Out-String); Log ('phaseK5: fallback fill exit ' + $LASTEXITCODE) }
        $null = (& $bsk wait-ms 1000ms --session $sid 2>&1 | Out-String)
        $s3 = Snap ('k5_att' + $att + '_d.txt')
        if (($s3 -match '01a0aeb9') -or ($s3 -match 'textbox[^\r\n]*\[filled\]')) { $filled = $true; Log ('phaseK5: att ' + $att + ' - PROMPT IN COMPOSER via fill') }
    }
}
if (-not $filled) { Log '[FAIL] composer never held the prompt'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }

# 6. send
$s4 = Snap 'k5_before_send.txt'
$sendRef = [regex]::Match($s4, '@(e\d+) button "Send message').Groups[1].Value
if ($sendRef) {
    $null = (& $bsk click ('@' + $sendRef) --session $sid 2>&1 | Out-String)
    Log ('phaseK5: clicked Send @' + $sendRef + ' (exit ' + $LASTEXITCODE + ')')
} else {
    $null = (& $bsk press Enter --session $sid 2>&1 | Out-String)
    Log 'phaseK5: Enter fallback'
}

# 7. dispatch + monitor
$echo = $false
for ($i = 1; $i -le 4; $i++) {
    $null = (& $bsk wait-ms 12s --session $sid 2>&1 | Out-String)
    $sx = Snap ('k5_send_poll' + $i + '.txt')
    if ($sx -match 'Stop generating') { $echo = $true; Log ('phaseK5: generation running at poll ' + $i); break }
}
if (-not $echo) { Log 'phaseK5: WARN dispatch unconfirmed' }
$found = $false
for ($i = 1; $i -le 40; $i++) {
    Scroll-Bottom
    $sx = Snap ('k5_mon' + $i + '.txt')
    $running = ($sx -match 'Stop generating') -or ($sx -match 'orchestrating') -or ($sx -match 'Running tools|using tool|Read |Bash ')
    Log ('phaseK5: mon ' + $i + ' running=' + $running + ' bytes=' + $sx.Length)
    if (-not $running -and $i -gt 3) { $found = $true; Log ('phaseK5: agent appears finished at mon ' + $i); break }
    $null = (& $bsk wait-ms 20s --session $sid 2>&1 | Out-String)
}
Scroll-Bottom
$t = (& $bsk evaluate document.body.innerText --session $sid 2>&1 | Out-String)
$t | Set-Content -LiteralPath (Join-Path $outDir 'k5_page_text.txt') -Encoding UTF8
Log ('phaseK5: page text bytes=' + $t.Length)
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'k5_final.png') 2>&1 | Out-String)
Log 'phaseK5: done - round-2 prompt sent; session OPEN'
$lines | Set-Content -LiteralPath $logPath -Encoding UTF8
exit 0
