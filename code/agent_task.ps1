# agent_task.ps1 - stage 4 PHASE F4: root-cause diagnostics.
# Fresh windows stopped rendering arena.ai entirely (empty aria shell, black
# viewport). F4 answers: is the WINDOW sick or is ARENA blocking us?
#   1. fresh window -> example.com -> snapshot (control test)
#   2. arena.ai plain -> poll 60s
#   3. arena.ai with cache-buster -> poll 30s
#   4. get-html of the arena shell + body innerText length + location
# Evidence comes back either way; no flow actions.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

$bsk = Join-Path $env:USERPROFILE '.local\bin\bsk.exe'
if (-not (Test-Path -LiteralPath $bsk)) {
    $f = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bsk = $f.FullName }
}
$outDir = Join-Path (Get-Location).Path 'results\jobs\browser\phaseF4'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$logPath = Join-Path $outDir 'phaseF4.log'
$lines = New-Object System.Collections.Generic.List[string]
function Log([string]$s) { $script:lines.Add($s) | Out-Null; Write-Output $s }
function Snap([string]$name) {
    $s = (& $bsk snapshot --session $script:sid --max-tokens 30000 2>&1 | Out-String)
    $s | Set-Content -LiteralPath (Join-Path $outDir $name) -Encoding UTF8
    return $s
}
function Test-Rendered([string]$s) {
    return ($s -match 'Ask anything') -or ($s -match 'combobox') -or ($s -match 'Get started') -or ($s -match 'Example Domain')
}

$env:BSK_AUTO_START = '0'
$null = (& $bsk session stop --all 2>&1 | Out-String)
$null = (& $bsk wait-ms 2s --session '' 2>&1 | Out-String)
$st = (& $bsk session start --name 'arena-diag' --json 2>&1 | Out-String)
$m = [regex]::Match($st, '"session_id"\s*:\s*"([^"]+)"')
if (-not $m.Success) { $m = [regex]::Match($st, '"id"\s*:\s*"([^"]+)"') }
$sid = ''
if ($m.Success) { $sid = $m.Groups[1].Value }
if (-not $sid) { Log '[FAIL] no session'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
$sid | Set-Content -LiteralPath (Join-Path (Get-Location).Path 'results\status\bsk_session.txt') -Encoding Ascii
Log ('phaseF4: session ' + $sid)

# 1. control: example.com must render in this window
$null = (& $bsk navigate 'https://example.com' --session $sid 2>&1 | Out-String)
$null = (& $bsk wait-ms 8s --session $sid 2>&1 | Out-String)
$c = Snap 'f4_control_example.txt'
Log ('phaseF4: control example.com rendered=' + (Test-Rendered $c) + ' bytes=' + $c.Length)
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'f4_control.png') 2>&1 | Out-String)

# 2. arena.ai plain, 60s of polling
$null = (& $bsk navigate 'https://arena.ai' --session $sid 2>&1 | Out-String)
$ok = $false
for ($i = 1; $i -le 6; $i++) {
    $null = (& $bsk wait-ms 10s --session $sid 2>&1 | Out-String)
    $a = Snap ('f4_arena_poll' + $i + '.txt')
    if (Test-Rendered $a) { $ok = $true; Log ('phaseF4: arena rendered at poll ' + $i); break }
}
Log ('phaseF4: arena plain rendered=' + $ok)

# 3. cache-buster retry
if (-not $ok) {
    $stamp = Get-Date -Format 'HHmmss'
    $null = (& $bsk navigate ('https://arena.ai/?cb=' + $stamp) --session $sid 2>&1 | Out-String)
    for ($i = 1; $i -le 3; $i++) {
        $null = (& $bsk wait-ms 10s --session $sid 2>&1 | Out-String)
        $a = Snap ('f4_arena_cb_poll' + $i + '.txt')
        if (Test-Rendered $a) { $ok = $true; Log ('phaseF4: arena rendered via cache-buster at poll ' + $i); break }
    }
}

# 4. hard evidence from the shell
$html = (& $bsk get-html --session $sid 2>&1 | Out-String)
$html | Set-Content -LiteralPath (Join-Path $outDir 'f4_arena_shell.html') -Encoding UTF8
Log ('phaseF4: shell html bytes=' + $html.Length)
$bodyLen = (& $bsk evaluate document.body.innerText.length --session $sid 2>&1 | Out-String)
Log ('phaseF4: body innerText length -> ' + $bodyLen.Trim())
$href = (& $bsk evaluate location.href --session $sid 2>&1 | Out-String)
Log ('phaseF4: location -> ' + $href.Trim())
$wd = (& $bsk evaluate navigator.webdriver --session $sid 2>&1 | Out-String)
Log ('phaseF4: navigator.webdriver -> ' + $wd.Trim())
$cookie = (& $bsk evaluate document.cookie.length --session $sid 2>&1 | Out-String)
Log ('phaseF4: cookie length -> ' + $cookie.Trim())
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'f4_arena_state.png') 2>&1 | Out-String)
Log ('phaseF4: RESULT arena renderable=' + $ok)
Log 'phaseF4: done'
$lines | Set-Content -LiteralPath $logPath -Encoding UTF8
exit 0
