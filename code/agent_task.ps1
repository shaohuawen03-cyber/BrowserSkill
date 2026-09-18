# agent_task.ps1 - stage 2 PHASE C: reliable send via snapshot refs.
# Lessons from phase B: the CSS-selector fill did not stick (React state),
# the promo card overlays the page, and complex JS in `evaluate` breaks under
# PS 5.1 native quoting. Phase C therefore: clicks "Hide this" on the promo,
# takes a FRESH snapshot, addresses elements by their @eN refs, VERIFIES the
# text stuck before sending, clicks the real "Send message" button, then
# captures three timed snapshots + a final screenshot as evidence.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)   # repo root

$bsk = Join-Path $env:USERPROFILE '.local\bin\bsk.exe'
if (-not (Test-Path -LiteralPath $bsk)) {
    $f = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bsk = $f.FullName }
}
if (-not (Test-Path -LiteralPath $bsk)) { Write-Output '[FAIL] bsk.exe not found'; exit 1 }

$outDir = Join-Path (Get-Location).Path 'results\jobs\browser\phaseC'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$logPath = Join-Path $outDir 'phaseC.log'
$lines = New-Object System.Collections.Generic.List[string]
function Log([string]$s) { $script:lines.Add($s) | Out-Null; Write-Output $s }
function Snap([string]$name) {
    $s = (& $bsk snapshot --session $script:sid --max-tokens 30000 2>&1 | Out-String)
    $s | Set-Content -LiteralPath (Join-Path $outDir $name) -Encoding UTF8
    return $s
}

$env:BSK_AUTO_START = '0'
$sid = ''
$sidFile = Join-Path (Get-Location).Path 'results\status\bsk_session.txt'
if (Test-Path -LiteralPath $sidFile) { $sid = (Get-Content -LiteralPath $sidFile -Raw).Trim() }
$lst = (& $bsk session list --json 2>&1 | Out-String)
if (-not $sid -or $lst -notmatch [regex]::Escape($sid)) {
    $st = (& $bsk session start --no-focus --name 'arena-ai-chat-c' --json 2>&1 | Out-String)
    $m = [regex]::Match($st, '"session_id"\s*:\s*"([^"]+)"')
    if (-not $m.Success) { $m = [regex]::Match($st, '"id"\s*:\s*"([^"]+)"') }
    if ($m.Success) { $sid = $m.Groups[1].Value } else { Log ('[FAIL] no session: ' + $st.Substring(0, [Math]::Min(250, $st.Length))); $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
    $sid | Set-Content -LiteralPath $sidFile -Encoding Ascii
}
Log ('phaseC: session ' + $sid)

# 0. page state right now (no reload - keep the rendered SPA state)
$s0 = Snap 'snapshot_0.txt'
Log ('phaseC: snapshot_0 bytes=' + $s0.Length)

# 1. dismiss the promo card if present (its refs die on re-render, so re-snap after)
$hideRef = [regex]::Match($s0, '@(e\d+) button "Hide this').Groups[1].Value
if ($hideRef) {
    $null = (& $bsk click ('@' + $hideRef) --session $sid 2>&1 | Out-String)
    Log ('phaseC: clicked Hide this @' + $hideRef + ' (exit ' + $LASTEXITCODE + ')')
    $null = (& $bsk wait-ms 2s --session $sid 2>&1 | Out-String)
    $null = Snap 'snapshot_1_nopromo.txt'
} else {
    Log 'phaseC: no promo card visible'
}

# 2. fresh snapshot -> find the composer + send refs
$s1 = Snap 'snapshot_2_fresh.txt'
$tbRef = [regex]::Match($s1, '@(e\d+) textbox').Groups[1].Value
$sendRef = [regex]::Match($s1, '@(e\d+) button "Send message').Groups[1].Value
Log ('phaseC: textbox=@' + $tbRef + ' send=@' + $sendRef)
if (-not $tbRef) { Log '[FAIL] composer textbox not found in snapshot'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }

# 3. fill by ref, then VERIFY the text stuck
$msg = 'Hello! This message was sent by BrowserSkill browser automation (bsk CLI) as a connectivity test. Please reply with one short sentence.'
$null = (& $bsk fill ('@' + $tbRef) --value $msg --session $sid 2>&1 | Out-String)
Log ('phaseC: fill exit ' + $LASTEXITCODE)
$null = (& $bsk wait-ms 1s --session $sid 2>&1 | Out-String)
$s2 = Snap 'snapshot_3_afterfill.txt'
$stillEmpty = $s2 -match 'textbox[^\r\n]*\[empty\]'
if ($stillEmpty) {
    Log 'phaseC: WARN text did not stick - trying selector fill + click-focus fallback'
    $null = (& $bsk click ('@' + $tbRef) --session $sid 2>&1 | Out-String)
    $null = (& $bsk fill 'textarea' --value $msg --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 1s --session $sid 2>&1 | Out-String)
    $s2 = Snap 'snapshot_3b_retry.txt'
    $stillEmpty = $s2 -match 'textbox[^\r\n]*\[empty\]'
}
if ($stillEmpty) {
    Log '[FAIL] composer will not hold text - dumping state for the agent'
    $lines | Set-Content -LiteralPath $logPath -Encoding UTF8
    exit 1
}
Log 'phaseC: text verified in composer'

# 4. send: the real button first, Enter as fallback
if ($sendRef) {
    $null = (& $bsk click ('@' + $sendRef) --session $sid 2>&1 | Out-String)
    Log ('phaseC: clicked Send @' + $sendRef + ' (exit ' + $LASTEXITCODE + ')')
} else {
    $null = (& $bsk press Enter --session $sid 2>&1 | Out-String)
    Log ('phaseC: Enter fallback (exit ' + $LASTEXITCODE + ')')
}

# 5. watch for the echo of our message (=sent), then let a reply arrive
$echoAt = -1
for ($i = 1; $i -le 4; $i++) {
    $null = (& $bsk wait-ms 12s --session $sid 2>&1 | Out-String)
    $sx = Snap ('snapshot_send' + $i + '.txt')
    if ($sx -match 'BrowserSkill browser automation') { $echoAt = $i; Log ('phaseC: message echo visible at check ' + $i); break }
}
if ($echoAt -lt 0) { Log 'phaseC: WARN no echo of the message found - state captured anyway' }
$null = (& $bsk wait-ms 20s --session $sid 2>&1 | Out-String)
$null = Snap 'snapshot_reply1.txt'
$null = (& $bsk wait-ms 15s --session $sid 2>&1 | Out-String)
$sFinal = Snap 'snapshot_reply2.txt'
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'final.png') 2>&1 | Out-String)
$t = (& $bsk evaluate document.title --session $sid 2>&1 | Out-String)
Log ('phaseC: title -> ' + $t.Trim())
if ($sFinal -match 'Battle|Model|response') { Log 'phaseC: reply snapshot captured' }
Log 'phaseC: done'
$lines | Set-Content -LiteralPath $logPath -Encoding UTF8
exit 0
