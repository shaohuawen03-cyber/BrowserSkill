# agent_task.ps1 - stage 6 PHASE J: ref-refreshing fill loop for /agent.
# Evidence: /agent renders fast and defaults to Agent mode; the composer is a
# rich textbox whose refs die on re-render (e13 -> e32/e34 between snaps).
# J: fresh window -> /agent -> (promo) -> LOOP { fresh snap -> newest textbox
# ref -> click it -> fresh snap -> fill that ref -> verify } up to 4 times ->
# Send via the newest Send-button ref -> echo + progress evidence.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

$bsk = Join-Path $env:USERPROFILE '.local\bin\bsk.exe'
if (-not (Test-Path -LiteralPath $bsk)) {
    $f = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bsk = $f.FullName }
}
$outDir = Join-Path (Get-Location).Path 'results\jobs\browser\phaseJ'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$logPath = Join-Path $outDir 'phaseJ.log'
$lines = New-Object System.Collections.Generic.List[string]
function Log([string]$s) { $script:lines.Add($s) | Out-Null; Write-Output $s }
function Snap([string]$name) {
    $s = (& $bsk snapshot --session $script:sid --max-tokens 30000 2>&1 | Out-String)
    $s | Set-Content -LiteralPath (Join-Path $outDir $name) -Encoding UTF8
    return $s
}

$env:BSK_AUTO_START = '0'
$null = (& $bsk session stop --all 2>&1 | Out-String)
$st = (& $bsk session start --name 'arena-agent-j' --json 2>&1 | Out-String)
$m = [regex]::Match($st, '"session_id"\s*:\s*"([^"]+)"')
if (-not $m.Success) { $m = [regex]::Match($st, '"id"\s*:\s*"([^"]+)"') }
$sid = ''
if ($m.Success) { $sid = $m.Groups[1].Value }
if (-not $sid) { Log '[FAIL] no session'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
$sid | Set-Content -LiteralPath (Join-Path (Get-Location).Path 'results\status\bsk_session.txt') -Encoding Ascii
Log ('phaseJ: fresh session ' + $sid)

# 1. /agent + render wait
$rendered = $false
for ($i = 1; $i -le 12; $i++) {
    if ($i -eq 1) { $null = (& $bsk navigate 'https://arena.ai/agent' --session $sid 2>&1 | Out-String) }
    $null = (& $bsk wait-ms 10s --session $sid 2>&1 | Out-String)
    $s0 = Snap ('j_s0_poll' + $i + '.txt')
    if (($s0 -match 'Ask anything') -or ($s0 -match 'combobox') -or ($s0 -match 'What would you like')) { $rendered = $true; Log ('phaseJ: rendered at poll ' + $i); break }
    if ($i -eq 5 -or $i -eq 9) { $null = (& $bsk reload --session $sid 2>&1 | Out-String) }
}
if (-not $rendered) { Log '[FAIL] /agent not rendering'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
$mode = [regex]::Match($s0, '@e\d+ combobox "([^"]*)"').Groups[1].Value
Log ('phaseJ: mode reads: ' + $mode)

# 2. promo
$hideRef = [regex]::Match($s0, '@(e\d+) button "Hide this').Groups[1].Value
if ($hideRef) {
    $null = (& $bsk click ('@' + $hideRef) --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 2s --session $sid 2>&1 | Out-String)
    Log ('phaseJ: hid promo @' + $hideRef)
}

# 3. the ref-refreshing fill loop
$promptFile = Join-Path (Get-Location).Path 'results\status\arena_prompt.txt'
$msg = (Get-Content -LiteralPath $promptFile -Raw -Encoding UTF8).Trim()
Log ('phaseJ: prompt chars=' + $msg.Length)
$filled = $false
for ($att = 1; $att -le 4 -and -not $filled; $att++) {
    $s1 = Snap ('j_att' + $att + '_a.txt')
    $tbRef = [regex]::Match($s1, '@(e\d+) textbox').Groups[1].Value
    if (-not $tbRef) { Log ('phaseJ: att ' + $att + ' - no textbox in tree'); continue }
    $null = (& $bsk click ('@' + $tbRef) --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 600ms --session $sid 2>&1 | Out-String)
    $s2 = Snap ('j_att' + $att + '_b.txt')
    $tbRef2 = [regex]::Match($s2, '@(e\d+) textbox').Groups[1].Value
    if (-not $tbRef2) { $tbRef2 = $tbRef }
    $fillOut = (& $bsk fill ('@' + $tbRef2) --value $msg --session $sid 2>&1 | Out-String)
    $fillCode = $LASTEXITCODE
    Log ('phaseJ: att ' + $att + ' fill @' + $tbRef2 + ' exit ' + $fillCode + ' ' + (($fillOut -replace '\s+', ' ').Trim().Substring(0, [Math]::Min(120, $fillOut.Trim().Length))))
    $null = (& $bsk wait-ms 1200ms --session $sid 2>&1 | Out-String)
    $s3 = Snap ('j_att' + $att + '_c.txt')
    if (($s3 -match '01a0aeb9') -or ($s3 -match 'textbox[^\r\n]*\[filled\]')) { $filled = $true; Log ('phaseJ: att ' + $att + ' - PROMPT IS IN THE COMPOSER'); }
    else { Log ('phaseJ: att ' + $att + ' - still empty, retrying with fresh refs') }
}
if (-not $filled) { Log '[FAIL] composer never held the prompt'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }

# 4. send via the newest Send button
$s4 = Snap 'j_before_send.txt'
$sendRef = [regex]::Match($s4, '@(e\d+) button "Send message').Groups[1].Value
if ($sendRef) {
    $null = (& $bsk click ('@' + $sendRef) --session $sid 2>&1 | Out-String)
    Log ('phaseJ: clicked Send @' + $sendRef + ' (exit ' + $LASTEXITCODE + ')')
} else {
    $null = (& $bsk press Enter --session $sid 2>&1 | Out-String)
    Log 'phaseJ: Send button not in tree - Enter fallback'
}

# 5. echo + early progress
$echo = $false
for ($i = 1; $i -le 4; $i++) {
    $null = (& $bsk wait-ms 12s --session $sid 2>&1 | Out-String)
    $sx = Snap ('j_send_poll' + $i + '.txt')
    if ($sx -match '01a0aeb9') { $echo = $true; Log ('phaseJ: prompt echo at poll ' + $i); break }
}
if (-not $echo) { Log 'phaseJ: WARN no echo yet - captured' }
$null = (& $bsk wait-ms 30s --session $sid 2>&1 | Out-String)
$null = Snap 'j_progress1.txt'
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'j_sent.png') 2>&1 | Out-String)
Log 'phaseJ: done - round-1 prompt sent; session OPEN for round 2'
$lines | Set-Content -LiteralPath $logPath -Encoding UTF8
exit 0
