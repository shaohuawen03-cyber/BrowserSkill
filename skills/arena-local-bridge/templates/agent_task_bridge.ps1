# agent_task_bridge.ps1 - generic bridge task: send results/status/arena_prompt2.txt
# into the connected arena conversation (continue-click + clipboard) and monitor.
# This is the K5 sequence packaged as the standard hook; see SKILL.md rule table.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

$bsk = Join-Path $env:USERPROFILE '.local\bin\bsk.exe'
if (-not (Test-Path -LiteralPath $bsk)) {
    $f = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bsk = $f.FullName }
}
$outDir = Join-Path (Get-Location).Path 'results\jobs\browser\bridge'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
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
$st = (& $bsk session start --name 'arena-bridge' --json 2>&1 | Out-String)
$m = [regex]::Match($st, '"session_id"\s*:\s*"([^"]+)"')
if (-not $m.Success) { $m = [regex]::Match($st, '"id"\s*:\s*"([^"]+)"') }
$sid = ''
if ($m.Success) { $sid = $m.Groups[1].Value }
if (-not $sid) { Log '[FAIL] no session'; $lines | Set-Content -LiteralPath (Join-Path $outDir 'bridge.log') -Encoding UTF8; exit 1 }
$sid | Set-Content -LiteralPath (Join-Path (Get-Location).Path 'results\status\bsk_session.txt') -Encoding Ascii
Log ('bridge: session ' + $sid)

$tabs = (& $bsk tab list --session $sid --json 2>&1 | Out-String)
$tid = ''
foreach ($mm in [regex]::Matches($tabs, '\{[^{}]*\}')) {
    if ($mm.Value -match 'arena\.ai') { $cand = [regex]::Match($mm.Value, '"tab_id"\s*:\s*(\d+)').Groups[1].Value; if ($cand -and -not $tid) { $tid = $cand } }
}
if (-not $tid) { Log '[FAIL] no arena tab'; $lines | Set-Content -LiteralPath (Join-Path $outDir 'bridge.log') -Encoding UTF8; exit 1 }
$bo = (& $bsk tab borrow $tid --session $sid --timeout 300 2>&1 | Out-String)
Log ('bridge: borrow exit ' + $LASTEXITCODE)
if ($LASTEXITCODE -ne 0) { $lines | Set-Content -LiteralPath (Join-Path $outDir 'bridge.log') -Encoding UTF8; exit 1 }
$null = (& $bsk tab select $tid --session $sid 2>&1 | Out-String)

$null = (& $bsk navigate 'https://arena.ai/agent' --session $sid 2>&1 | Out-String)
$rendered = $false
for ($i = 1; $i -le 30; $i++) {
    $null = (& $bsk wait-ms 5s --session $sid 2>&1 | Out-String)
    $s0 = Snap ('b_home_poll' + $i + '.txt')
    if (($s0 -match 'textbox') -and ($s0 -match 'Today')) { $rendered = $true; Log ('bridge: home rendered at poll ' + $i); break }
    if ($i -eq 10 -or $i -eq 20) { $null = (& $bsk tab select $tid --session $sid 2>&1 | Out-String); $null = (& $bsk reload --session $sid 2>&1 | Out-String) }
}
if (-not $rendered) { Log '[FAIL] home not rendering - user must click the arena tab once'; $lines | Set-Content -LiteralPath (Join-Path $outDir 'bridge.log') -Encoding UTF8; exit 1 }

# open the newest today conversation (quote-free DOM click on the first
# link inside the Today section)
$js = '(function(){var L=document.links;for(var i=0;i<L.length;i++){if(L[i].href.indexOf(String.fromCharCode(47,97,103,101,110,116,47))>=0){L[i].click();return "clicked";}}return "none";})()'
$opened = $false
for ($pass = 1; $pass -le 4 -and -not $opened; $pass++) {
    Scroll-Bottom
    $r = (& $bsk evaluate $js --session $sid 2>&1 | Out-String)
    Log ('bridge: pass ' + $pass + ' click -> ' + (($r -replace '\s+', ' ').Trim()))
    for ($i = 1; $i -le 12; $i++) {
        $null = (& $bsk wait-ms 5s --session $sid 2>&1 | Out-String)
        $s0 = Snap ('b_conv_pass' + $pass + '_p' + $i + '.txt')
        if (($s0 -match 'textbox') -and ($s0 -match 'combobox')) { $opened = $true; Log ('bridge: conversation open'); break }
    }
}
if (-not $opened) { Log '[FAIL] conversation never opened'; $lines | Set-Content -LiteralPath (Join-Path $outDir 'bridge.log') -Encoding UTF8; exit 1 }
Scroll-Bottom
$s0 = Snap 'b_conv_bottom.txt'

$needle = -join @([char]0x7F01, [char]0x0445, [char]0x753B, [char]0x5BB8, [char]0x30E4, [char]0x7D94)
$contRef = ''
foreach ($mm in [regex]::Matches($s0, '@(e\d+) button[^\r\n]*')) {
    if ($mm.Value.Contains($needle)) { $contRef = $mm.Groups[1].Value; break }
}
if ($contRef) {
    $null = (& $bsk click ('@' + $contRef) --session $sid 2>&1 | Out-String)
    Log ('bridge: clicked continue @' + $contRef)
    $null = (& $bsk wait-ms 4s --session $sid 2>&1 | Out-String)
    Scroll-Bottom
    $s0 = Snap 'b_after_continue.txt'
}

$promptFile = Join-Path (Get-Location).Path 'results\status\arena_prompt2.txt'
$msg = (Get-Content -LiteralPath $promptFile -Raw -Encoding UTF8).Trim()
Set-Clipboard -Value $msg
Log ('bridge: prompt chars=' + $msg.Length)
$filled = $false
for ($att = 1; $att -le 4 -and -not $filled; $att++) {
    $s1 = Snap ('b_att' + $att + '_a.txt')
    $tbRef = [regex]::Match($s1, '@(e\d+) textbox').Groups[1].Value
    if (-not $tbRef) { continue }
    $null = (& $bsk click ('@' + $tbRef) --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 700ms --session $sid 2>&1 | Out-String)
    $null = (& $bsk press Ctrl+v --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 1500ms --session $sid 2>&1 | Out-String)
    $s3 = Snap ('b_att' + $att + '_c.txt')
    if (($s3 -match 'textbox[^\r\n]*\[filled\]') -or ($msg.Length -gt 0 -and $s3 -match '01a0aeb9')) { $filled = $true; Log ('bridge: att ' + $att + ' - PROMPT IN COMPOSER') }
    else {
        $s2 = Snap ('b_att' + $att + '_b.txt')
        $tbRef2 = [regex]::Match($s2, '@(e\d+) textbox').Groups[1].Value
        if ($tbRef2) { $null = (& $bsk fill ('@' + $tbRef2) --value $msg --session $sid 2>&1 | Out-String) }
        $null = (& $bsk wait-ms 1000ms --session $sid 2>&1 | Out-String)
        $s3 = Snap ('b_att' + $att + '_d.txt')
        if (($s3 -match 'textbox[^\r\n]*\[filled\]') -or ($s3 -match '01a0aeb9')) { $filled = $true; Log ('bridge: att ' + $att + ' - PROMPT via fill') }
    }
}
if (-not $filled) { Log '[FAIL] composer never held the prompt'; $lines | Set-Content -LiteralPath (Join-Path $outDir 'bridge.log') -Encoding UTF8; exit 1 }

$s4 = Snap 'b_before_send.txt'
$sendRef = [regex]::Match($s4, '@(e\d+) button "Send message').Groups[1].Value
if ($sendRef) {
    $null = (& $bsk click ('@' + $sendRef) --session $sid 2>&1 | Out-String)
    Log ('bridge: clicked Send @' + $sendRef)
} else {
    $null = (& $bsk press Enter --session $sid 2>&1 | Out-String)
}
$echo = $false
for ($i = 1; $i -le 4; $i++) {
    $null = (& $bsk wait-ms 12s --session $sid 2>&1 | Out-String)
    $sx = Snap ('b_send_poll' + $i + '.txt')
    if ($sx -match 'Stop generating') { $echo = $true; Log ('bridge: generation running'); break }
}
if (-not $echo) { Log 'bridge: WARN dispatch unconfirmed' }
for ($i = 1; $i -le 40; $i++) {
    Scroll-Bottom
    $sx = Snap ('b_mon' + $i + '.txt')
    $running = ($sx -match 'Stop generating') -or ($sx -match 'orchestrating')
    Log ('bridge: mon ' + $i + ' running=' + $running)
    if (-not $running -and $i -gt 3) { Log ('bridge: agent finished at mon ' + $i); break }
    $null = (& $bsk wait-ms 20s --session $sid 2>&1 | Out-String)
}
Scroll-Bottom
$t = (& $bsk evaluate document.body.innerText --session $sid 2>&1 | Out-String)
$t | Set-Content -LiteralPath (Join-Path $outDir 'b_page_text.txt') -Encoding UTF8
Log ('bridge: page text bytes=' + $t.Length)
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'b_final.png') 2>&1 | Out-String)
Log 'bridge: done'
$lines | Set-Content -LiteralPath (Join-Path $outDir 'bridge.log') -Encoding UTF8
exit 0
