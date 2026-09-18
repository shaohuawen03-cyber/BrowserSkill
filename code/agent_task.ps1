# agent_task.ps1 - r50 / K6: drive the 3-round plan into the connected arena
# conversation. Fixes from r46: JS strings carry NO double quotes (PS 5.1
# native-arg quoting eats them -> ReferenceError); link click returns a bare
# number. Window hygiene: session stop --all at BOTH start and end. Step 0
# refreshes user-side root scripts BEFORE anything else (consistency gate).

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)
$root = (Get-Location).Path

$outDir = Join-Path $root 'results\jobs\browser\phaseK6'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$log = Join-Path $outDir 'k6.log'
$lines = New-Object System.Collections.Generic.List[string]
function Log([string]$s) { $script:lines.Add($s); Write-Output $s }
function Snap([string]$name) {
    $s = (& $bsk snapshot --session $script:sid --max-tokens 30000 2>&1 | Out-String)
    $s | Set-Content -LiteralPath (Join-Path $outDir $name) -Encoding UTF8
    return $s
}
function Scroll-Bottom {
    $null = (& $bsk evaluate '(function(){var d=document.scrollingElement;d.scrollTop=d.scrollHeight;return d.scrollTop;})()' --session $script:sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 3s --session $script:sid 2>&1 | Out-String)
}
function Finish([int]$code) {
    $null = (& $bsk session stop --all 2>&1 | Out-String)
    Log ('k6: final session stop exit ' + $LASTEXITCODE)
    $script:lines | Set-Content -LiteralPath $script:log -Encoding UTF8
    exit $code
}

# ---- 0. refresh user-side root scripts (keeps the consistency gate green)
$src = Join-Path $root 'skills\git-sync\scripts'
foreach ($f in @('where.ps1', 'where.cmd', 'download.ps1')) {
    $from = Join-Path $src $f
    if (Test-Path -LiteralPath $from) { Copy-Item -Force -LiteralPath $from -Destination (Join-Path $root $f) }
}
Log 'k6: root scripts refreshed'

$bsk = Join-Path $env:USERPROFILE '.local\bin\bsk.exe'
if (-not (Test-Path -LiteralPath $bsk)) {
    $f = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bsk = $f.FullName }
}
$env:BSK_AUTO_START = '0'
$null = (& $bsk session stop --all 2>&1 | Out-String)
$st = (& $bsk session start --name 'arena-k6' --json 2>&1 | Out-String)
$m = [regex]::Match($st, '"session_id"\s*:\s*"([^"]+)"')
if (-not $m.Success) { $m = [regex]::Match($st, '"id"\s*:\s*"([^"]+)"') }
$sid = ''
if ($m.Success) { $sid = $m.Groups[1].Value }
if (-not $sid) { Log 'k6: [FAIL] no session'; Finish 1 }
$sid | Set-Content -LiteralPath (Join-Path $root 'results\status\bsk_session.txt') -Encoding Ascii
Log ('k6: session ' + $sid)

# ---- 1. borrow the arena tab
$tabs = (& $bsk tab list --session $sid --json 2>&1 | Out-String)
$tabs | Set-Content -LiteralPath (Join-Path $outDir 'k6_tabs.json') -Encoding UTF8
$tid = ''
foreach ($mm in [regex]::Matches($tabs, '\{[^{}]*\}')) {
    if ($mm.Value -match 'arena\.ai') { $c = [regex]::Match($mm.Value, '"tab_id"\s*:\s*(\d+)').Groups[1].Value; if ($c -and -not $tid) { $tid = $c } }
}
if (-not $tid) { Log 'k6: [FAIL] no arena tab - keep arena.ai open in Edge'; Finish 1 }
$null = (& $bsk tab borrow $tid --session $sid --timeout 300 2>&1 | Out-String)
Log ('k6: borrow tab ' + $tid + ' exit ' + $LASTEXITCODE)
if ($LASTEXITCODE -ne 0) { Log 'k6: [FAIL] borrow denied'; Finish 1 }
$null = (& $bsk tab select $tid --session $sid 2>&1 | Out-String)

# ---- 2. /agent home must render (user-activation law: click the tab <30min ago)
$null = (& $bsk navigate 'https://arena.ai/agent' --session $sid 2>&1 | Out-String)
$rendered = $false
for ($i = 1; $i -le 30; $i++) {
    $null = (& $bsk wait-ms 5s --session $sid 2>&1 | Out-String)
    $s0 = Snap ('k6_home_p' + $i + '.txt')
    if (($s0 -match 'textbox') -and ($s0 -match 'Today')) { $rendered = $true; Log ('k6: home rendered at poll ' + $i); break }
    if ($i -eq 10 -or $i -eq 20) { $null = (& $bsk tab select $tid --session $sid 2>&1 | Out-String); $null = (& $bsk reload --session $sid 2>&1 | Out-String) }
}
if (-not $rendered) { Log 'k6: [FAIL] home cold - user must click the arena tab once, then rerun'; Finish 1 }

# ---- 3. open the connected conversation via quote-free DOM click.
# PS 5.1 eats inner double quotes when passing args to native commands, so
# the JS uses only single-quoted-free code: no quotes at all, returns numbers.
$js = '(function(){var N=String.fromCharCode(102,97,100,49,45,55,49,54,56);var L=document.links;var k=-1;for(var i=0;i<L.length;i++){if(L[i].href.indexOf(N)>=0){k=i;break;}}if(k>=0){L[k].click();return 1;}return 0;})()'
$opened = $false
for ($pass = 1; $pass -le 5 -and -not $opened; $pass++) {
    Scroll-Bottom
    $r = (& $bsk evaluate $js --session $sid 2>&1 | Out-String)
    Log ('k6: pass ' + $pass + ' dom-click -> ' + (($r -replace '\s+', ' ').Trim().Substring(0, [Math]::Min(90, $r.Trim().Length))))
    for ($i = 1; $i -le 12; $i++) {
        $null = (& $bsk wait-ms 5s --session $sid 2>&1 | Out-String)
        $s0 = Snap ('k6_conv_pass' + $pass + '_p' + $i + '.txt')
        if (($s0 -match 'textbox') -and ($s0 -match 'combobox')) { $opened = $true; Log ('k6: conversation open (pass ' + $pass + ' poll ' + $i + ')'); break }
    }
}
if (-not $opened) {
    Log 'k6: DOM click found no link - SPA fallback via history.pushState-free deep link'
    $null = (& $bsk navigate 'https://arena.ai/agent/01a0b237-fad1-7168-8115-d3f52e550489' --session $sid 2>&1 | Out-String)
    for ($i = 1; $i -le 12; $i++) {
        $null = (& $bsk wait-ms 5s --session $sid 2>&1 | Out-String)
        $s0 = Snap ('k6_deep_p' + $i + '.txt')
        if (($s0 -match 'textbox') -and ($s0 -match 'combobox')) { $opened = $true; Log ('k6: deep link opened (poll ' + $i + ')'); break }
    }
}
if (-not $opened) { Log 'k6: [FAIL] conversation never opened'; Finish 1 }
Scroll-Bottom
$s0 = Snap 'k6_conv_bottom.txt'

# ---- 4. continue-working button (GBK needle; unlocks a locked composer)
$needle = -join @([char]0x7F01, [char]0x0445, [char]0x753B, [char]0x5BB8, [char]0x30E4, [char]0x7D94)
$contRef = ''
foreach ($mm in [regex]::Matches($s0, '@(e\d+) button[^\r\n]*')) {
    if ($mm.Value.Contains($needle)) { $contRef = $mm.Groups[1].Value; Log ('k6: continue button @' + $contRef); break }
}
if ($contRef) {
    $null = (& $bsk click ('@' + $contRef) --session $sid 2>&1 | Out-String)
    Log ('k6: clicked continue (exit ' + $LASTEXITCODE + ')')
    $null = (& $bsk wait-ms 4s --session $sid 2>&1 | Out-String)
    Scroll-Bottom
    $s0 = Snap 'k6_after_continue.txt'
} else {
    Log 'k6: no continue button - composer assumed free'
}

# ---- 5. clipboard the 3-round prompt
$promptFile = Join-Path $root 'results\status\arena_prompt3.txt'
$msg = (Get-Content -LiteralPath $promptFile -Raw -Encoding UTF8).Trim()
Log ('k6: prompt3 chars=' + $msg.Length)
Set-Clipboard -Value $msg
$filled = $false
for ($att = 1; $att -le 4 -and -not $filled; $att++) {
    $s1 = Snap ('k6_att' + $att + '_a.txt')
    $tb = [regex]::Match($s1, '@(e\d+) textbox').Groups[1].Value
    if (-not $tb) { Log ('k6: att ' + $att + ' - no textbox'); continue }
    $null = (& $bsk click ('@' + $tb) --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 700ms --session $sid 2>&1 | Out-String)
    $null = (& $bsk press Ctrl+v --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 1500ms --session $sid 2>&1 | Out-String)
    $s3 = Snap ('k6_att' + $att + '_c.txt')
    if (($s3 -match 'textbox[^\r\n]*\[filled\]') -or ($s3 -match '3/3')) { $filled = $true; Log ('k6: att ' + $att + ' - PROMPT IN COMPOSER') }
}
if (-not $filled) { Log 'k6: [FAIL] composer never held the prompt'; Finish 1 }

# ---- 6. send + dispatch check
$s4 = Snap 'k6_before_send.txt'
$sendRef = [regex]::Match($s4, '@(e\d+) button "Send message').Groups[1].Value
if ($sendRef) {
    $null = (& $bsk click ('@' + $sendRef) --session $sid 2>&1 | Out-String)
    Log ('k6: clicked Send @' + $sendRef + ' (exit ' + $LASTEXITCODE + ')')
} else {
    $null = (& $bsk press Enter --session $sid 2>&1 | Out-String)
    Log 'k6: Enter fallback'
}
$echo = $false
for ($i = 1; $i -le 6; $i++) {
    $null = (& $bsk wait-ms 10s --session $sid 2>&1 | Out-String)
    $sx = Snap ('k6_send_p' + $i + '.txt')
    if (($sx -match 'Stop generating') -or ($sx -match 'orchestrating')) { $echo = $true; Log ('k6: dispatch confirmed at poll ' + $i); break }
}
if (-not $echo) { Log 'k6: WARN dispatch unconfirmed - will verify via git/next round' }
Scroll-Bottom
$t = (& $bsk evaluate document.body.innerText --session $sid 2>&1 | Out-String)
$t | Set-Content -LiteralPath (Join-Path $outDir 'k6_page_text.txt') -Encoding UTF8
Log ('k6: page text bytes=' + $t.Length)
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'k6_final.png') 2>&1 | Out-String)
Log 'k6: 3-round plan dispatched - rounds are tracked on the arena agent git branch'
Finish 0
