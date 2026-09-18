# agent_task.ps1 - stage 6 PHASE H3: clipboard paste into the /agent composer.
# H2 proof: borrow + wake works, mode = Agent; only `fill` fails (exit 3 - the
# rich-text composer rejects CDP value injection). H3: click the composer,
# put the prompt on the real Windows clipboard (Set-Clipboard -Value from the
# UTF-8 file), press Ctrl+V (a genuine paste that every editor accepts),
# verify, then send via the newest Send ref. fill attempts stay as fallback.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

$bsk = Join-Path $env:USERPROFILE '.local\bin\bsk.exe'
if (-not (Test-Path -LiteralPath $bsk)) {
    $f = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bsk = $f.FullName }
}
$outDir = Join-Path (Get-Location).Path 'results\jobs\browser\phaseH3'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$logPath = Join-Path $outDir 'phaseH3.log'
$lines = New-Object System.Collections.Generic.List[string]
function Log([string]$s) { $script:lines.Add($s) | Out-Null; Write-Output $s }
function Snap([string]$name) {
    $s = (& $bsk snapshot --session $script:sid --max-tokens 30000 2>&1 | Out-String)
    $s | Set-Content -LiteralPath (Join-Path $outDir $name) -Encoding UTF8
    return $s
}

$env:BSK_AUTO_START = '0'
$null = (& $bsk session stop --all 2>&1 | Out-String)
$st = (& $bsk session start --name 'arena-h3' --json 2>&1 | Out-String)
$m = [regex]::Match($st, '"session_id"\s*:\s*"([^"]+)"')
if (-not $m.Success) { $m = [regex]::Match($st, '"id"\s*:\s*"([^"]+)"') }
$sid = ''
if ($m.Success) { $sid = $m.Groups[1].Value }
if (-not $sid) { Log '[FAIL] no session'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
$sid | Set-Content -LiteralPath (Join-Path (Get-Location).Path 'results\status\bsk_session.txt') -Encoding Ascii
Log ('phaseH3: session ' + $sid)

# 1. find + borrow the user's arena tab
$tabs = (& $bsk tab list --session $sid --json 2>&1 | Out-String)
$tabs | Set-Content -LiteralPath (Join-Path $outDir 'h3_tabs.json') -Encoding UTF8
$tid = ''
foreach ($mm in [regex]::Matches($tabs, '\{[^{}]*\}')) {
    if ($mm.Value -match 'arena\.ai') {
        $cand = [regex]::Match($mm.Value, '"tab_id"\s*:\s*(\d+)').Groups[1].Value
        if ($cand -and -not $tid) { $tid = $cand }
    }
}
Log ('phaseH3: arena tab ' + $tid)
if (-not $tid) { Log '[FAIL] no arena tab - open arena.ai once'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
$bo = (& $bsk tab borrow $tid --session $sid --timeout 300 2>&1 | Out-String)
Log ('phaseH3: borrow exit ' + $LASTEXITCODE)
if ($LASTEXITCODE -ne 0) { Log '[FAIL] borrow failed'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
$null = (& $bsk wait-ms 2s --session $sid 2>&1 | Out-String)

# 2. wake on /agent
$null = (& $bsk navigate 'https://arena.ai/agent' --session $sid 2>&1 | Out-String)
$rendered = $false
for ($i = 1; $i -le 12; $i++) {
    $null = (& $bsk wait-ms 10s --session $sid 2>&1 | Out-String)
    $s0 = Snap ('h3_poll' + $i + '.txt')
    if (($s0 -match 'Ask anything') -or ($s0 -match 'combobox') -or ($s0 -match 'What would you like')) { $rendered = $true; Log ('phaseH3: RENDERED at poll ' + $i); break }
    if ($i -eq 5 -or $i -eq 9) { $null = (& $bsk reload --session $sid 2>&1 | Out-String) }
}
if (-not $rendered) { Log '[FAIL] not rendering'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
Log ('phaseH3: mode reads: ' + [regex]::Match($s0, '@e\d+ combobox "([^"]*)"').Groups[1].Value)

# 3. promo
$hideRef = [regex]::Match($s0, '@(e\d+) button "Hide this').Groups[1].Value
if ($hideRef) {
    $null = (& $bsk click ('@' + $hideRef) --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 2s --session $sid 2>&1 | Out-String)
    Log ('phaseH3: hid promo @' + $hideRef)
}

# 4. clipboard paste loop
$promptFile = Join-Path (Get-Location).Path 'results\status\arena_prompt.txt'
$msg = (Get-Content -LiteralPath $promptFile -Raw -Encoding UTF8).Trim()
Log ('phaseH3: prompt chars=' + $msg.Length)
Set-Clipboard -Value $msg
Log 'phaseH3: prompt placed on the clipboard'
$filled = $false
for ($att = 1; $att -le 4 -and -not $filled; $att++) {
    $s1 = Snap ('h3_att' + $att + '_a.txt')
    $tbRef = [regex]::Match($s1, '@(e\d+) textbox').Groups[1].Value
    if (-not $tbRef) { Log ('phaseH3: att ' + $att + ' - no textbox'); continue }
    $null = (& $bsk click ('@' + $tbRef) --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 700ms --session $sid 2>&1 | Out-String)
    $null = (& $bsk press Ctrl+v --session $sid 2>&1 | Out-String)
    Log ('phaseH3: att ' + $att + ' clicked @' + $tbRef + ' + Ctrl+v (exit ' + $LASTEXITCODE + ')')
    $null = (& $bsk wait-ms 1500ms --session $sid 2>&1 | Out-String)
    $s3 = Snap ('h3_att' + $att + '_c.txt')
    if (($s3 -match '01a0aeb9') -or ($s3 -match 'textbox[^\r\n]*\[filled\]')) { $filled = $true; Log ('phaseH3: att ' + $att + ' - PROMPT IN COMPOSER') }
    else {
        Log ('phaseH3: att ' + $att + ' - empty after paste; one fill fallback')
        $s2 = Snap ('h3_att' + $att + '_b.txt')
        $tbRef2 = [regex]::Match($s2, '@(e\d+) textbox').Groups[1].Value
        if ($tbRef2) { $null = (& $bsk fill ('@' + $tbRef2) --value $msg --session $sid 2>&1 | Out-String); Log ('phaseH3: fallback fill exit ' + $LASTEXITCODE) }
        $null = (& $bsk wait-ms 1000ms --session $sid 2>&1 | Out-String)
        $s3 = Snap ('h3_att' + $att + '_d.txt')
        if (($s3 -match '01a0aeb9') -or ($s3 -match 'textbox[^\r\n]*\[filled\]')) { $filled = $true; Log ('phaseH3: att ' + $att + ' - PROMPT IN COMPOSER via fill') }
    }
}
if (-not $filled) { Log '[FAIL] composer never held the prompt'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }

# 5. send
$s4 = Snap 'h3_before_send.txt'
$sendRef = [regex]::Match($s4, '@(e\d+) button "Send message').Groups[1].Value
if ($sendRef) {
    $null = (& $bsk click ('@' + $sendRef) --session $sid 2>&1 | Out-String)
    Log ('phaseH3: clicked Send @' + $sendRef + ' (exit ' + $LASTEXITCODE + ')')
} else {
    $null = (& $bsk press Enter --session $sid 2>&1 | Out-String)
    Log 'phaseH3: Enter fallback'
}

# 6. echo + evidence
$echo = $false
for ($i = 1; $i -le 4; $i++) {
    $null = (& $bsk wait-ms 12s --session $sid 2>&1 | Out-String)
    $sx = Snap ('h3_send_poll' + $i + '.txt')
    if ($sx -match '01a0aeb9') { $echo = $true; Log ('phaseH3: prompt echo at poll ' + $i); break }
}
if (-not $echo) { Log 'phaseH3: WARN no echo yet' }
$null = (& $bsk wait-ms 30s --session $sid 2>&1 | Out-String)
$null = Snap 'h3_progress1.txt'
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'h3_sent.png') 2>&1 | Out-String)
Log 'phaseH3: done - round-1 prompt sent in the borrowed tab; session OPEN'
$lines | Set-Content -LiteralPath $logPath -Encoding UTF8
exit 0
