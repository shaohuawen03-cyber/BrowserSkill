# agent_task.ps1 - stage 4 PHASE F6: Vercel-challenge hypothesis test.
# Evidence: a _next chunk logged "Visit ID: ..." (Vercel attack-challenge
# signature); body never mounts; third-party beacons die with
# ERR_CONNECTION_CLOSED. F6: probe what the server returns for '/' and for a
# static chunk (status + challenge markers in the body), then WAIT up to 90s
# for a challenge to self-solve (they auto-reload when done), polling.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

$bsk = Join-Path $env:USERPROFILE '.local\bin\bsk.exe'
if (-not (Test-Path -LiteralPath $bsk)) {
    $f = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bsk = $f.FullName }
}
$outDir = Join-Path (Get-Location).Path 'results\jobs\browser\phaseF6'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$logPath = Join-Path $outDir 'phaseF6.log'
$lines = New-Object System.Collections.Generic.List[string]
function Log([string]$s) { $script:lines.Add($s) | Out-Null; Write-Output $s }
function Snap([string]$name) {
    $s = (& $bsk snapshot --session $script:sid --max-tokens 30000 2>&1 | Out-String)
    $s | Set-Content -LiteralPath (Join-Path $outDir $name) -Encoding UTF8
    return $s
}
function Test-Rendered([string]$s) {
    return ($s -match 'Ask anything') -or ($s -match 'combobox') -or ($s -match 'Get started')
}

$env:BSK_AUTO_START = '0'
$sid = ''
$sidFile = Join-Path (Get-Location).Path 'results\status\bsk_session.txt'
if (Test-Path -LiteralPath $sidFile) { $sid = (Get-Content -LiteralPath $sidFile -Raw).Trim() }
$lst = (& $bsk session list --json 2>&1 | Out-String)
if (-not $sid -or $lst -notmatch [regex]::Escape($sid)) {
    $null = (& $bsk session stop --all 2>&1 | Out-String)
    $st = (& $bsk session start --name 'arena-probe' --json 2>&1 | Out-String)
    $m = [regex]::Match($st, '"session_id"\s*:\s*"([^"]+)"')
    if (-not $m.Success) { $m = [regex]::Match($st, '"id"\s*:\s*"([^"]+)"') }
    if ($m.Success) { $sid = $m.Groups[1].Value } else { Log '[FAIL] no session'; $lines | Set-Content -LiteralPath $logPath -Encoding UTF8; exit 1 }
    $sid | Set-Content -LiteralPath $sidFile -Encoding Ascii
}
Log ('phaseF6: session ' + $sid)

# 0. land on arena.ai (the challenge page itself, whatever it is)
$null = (& $bsk navigate 'https://arena.ai' --session $sid 2>&1 | Out-String)
$null = (& $bsk wait-ms 10s --session $sid 2>&1 | Out-String)

# 1. simple-string probes (PS 5.1-safe): fetch status of '/' and a chunk
$p1 = 'fetch(location.origin, {credentials:"include"}).then(function(r){return "root-status-" + r.status})'
$v1 = (& $bsk evaluate $p1 --session $sid 2>&1 | Out-String)
Log ('phaseF6: root fetch -> ' + (($v1 -replace '\s+', ' ').Trim().Substring(0, [Math]::Min(100, $v1.Trim().Length))))
$p2 = 'fetch(location.origin + "/favicon.ico", {credentials:"include"}).then(function(r){return "favicon-status-" + r.status})'
$v2 = (& $bsk evaluate $p2 --session $sid 2>&1 | Out-String)
Log ('phaseF6: favicon fetch -> ' + (($v2 -replace '\s+', ' ').Trim().Substring(0, [Math]::Min(100, $v2.Trim().Length))))
$p3 = 'fetch(location.origin).then(function(r){return r.text()}).then(function(t){return t.length + "|" + (t.indexOf("challenge") >= 0 ? "HAS-challenge" : "no-challenge") + "|" + t.slice(0, 80).replace(/\s+/g, " ")})'
$v3 = (& $bsk evaluate $p3 --session $sid 2>&1 | Out-String)
$v3 | Set-Content -LiteralPath (Join-Path $outDir 'f6_root_probe.txt') -Encoding UTF8
Log ('phaseF6: root body probe -> ' + (($v3 -replace '\s+', ' ').Trim().Substring(0, [Math]::Min(220, $v3.Trim().Length))))

# 2. patient wait: challenges self-solve and reload the page
$ok = $false
for ($i = 1; $i -le 9; $i++) {
    $null = (& $bsk wait-ms 10s --session $sid 2>&1 | Out-String)
    $a = Snap ('f6_wait_poll' + $i + '.txt')
    if (Test-Rendered $a) { $ok = $true; Log ('phaseF6: RENDERED during patient wait at poll ' + $i); break }
    if ($i -eq 4) { $null = (& $bsk reload --session $sid 2>&1 | Out-String) }
}
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'f6_state.png') 2>&1 | Out-String)
Log ('phaseF6: RESULT rendered=' + $ok)

# 3. if alive, go Agent mode + pick repo (push the task forward in one round)
if ($ok) {
    $s0 = Snap 'f6_s_alive.txt'
    $hideRef = [regex]::Match($s0, '@(e\d+) button "Hide this').Groups[1].Value
    if ($hideRef) {
        $null = (& $bsk click ('@' + $hideRef) --session $sid 2>&1 | Out-String)
        $null = (& $bsk wait-ms 2s --session $sid 2>&1 | Out-String)
        $s0 = Snap 'f6_nopromo.txt'
    }
    if (-not (($s0 -match 'combobox[^\r\n]*="Agent"') -or ($s0 -match '\[. active: Agent'))) {
        foreach ($r in @('AU', 'AD', 'TA')) {
            $cbRef = [regex]::Match($s0, '@(e\d+) combobox').Groups[1].Value
            if (-not $cbRef) { $s0 = Snap 'f6_refind.txt'; $cbRef = [regex]::Match($s0, '@(e\d+) combobox').Groups[1].Value }
            $null = (& $bsk click ('@' + $cbRef) --session $sid 2>&1 | Out-String)
            $null = (& $bsk wait-ms 1500ms --session $sid 2>&1 | Out-String)
            if ($r -eq 'AU') { $null = (& $bsk press ArrowUp --session $sid 2>&1 | Out-String) }
            elseif ($r -eq 'AD') { $null = (& $bsk press ArrowDown --session $sid 2>&1 | Out-String) }
            else { $null = (& $bsk press a --session $sid 2>&1 | Out-String) }
            $null = (& $bsk wait-ms 400ms --session $sid 2>&1 | Out-String)
            $null = (& $bsk press Enter --session $sid 2>&1 | Out-String)
            $null = (& $bsk wait-ms 2500ms --session $sid 2>&1 | Out-String)
            $s0 = Snap ('f6_after_' + $r + '.txt')
            if (($s0 -match 'combobox[^\r\n]*="Agent"') -or ($s0 -match '\[. active: Agent')) { Log ('phaseF6: Agent via ' + $r); break }
        }
    } else { Log 'phaseF6: already Agent' }
    $s2 = Snap 'f6_s_agent.txt'
    $repoRef = [regex]::Match($s2, '@(e\d+) (?:combobox|button)[^\r\n]*(?:Loading|repository|BrowserSkill|mqgg5630)').Groups[1].Value
    Log ('phaseF6: repo dropdown @' + $repoRef)
    if ($repoRef) {
        $null = (& $bsk click ('@' + $repoRef) --session $sid 2>&1 | Out-String)
        $null = (& $bsk wait-ms 2500ms --session $sid 2>&1 | Out-String)
        $s3 = Snap 'f6_repo_menu.txt'
        $optBtn = [regex]::Match($s3, '@(e\d+) button "[^"]*BrowserSkill').Groups[1].Value
        if ($optBtn) {
            $null = (& $bsk click ('@' + $optBtn) --session $sid 2>&1 | Out-String)
            Log ('phaseF6: clicked option button @' + $optBtn)
        } else {
            $optRef = [regex]::Match($s3, '@(e\d+) option "[^"]*BrowserSkill').Groups[1].Value
            if ($optRef) { $null = (& $bsk click ('@' + $optRef) --session $sid 2>&1 | Out-String); Log ('phaseF6: clicked option @' + $optRef) }
            else { $null = (& $bsk press b --session $sid 2>&1 | Out-String); $null = (& $bsk press Enter --session $sid 2>&1 | Out-String) }
        }
        $null = (& $bsk wait-ms 3000ms --session $sid 2>&1 | Out-String)
        $s4 = Snap 'f6_after_select.txt'
        if (($s4 -match 'combobox[^\r\n]*BrowserSkill') -or ($s4 -match 'mqgg5630-cyber/BrowserSkill')) { Log 'phaseF6: SUCCESS - repo selected' } else { Log 'phaseF6: repo selection unconfirmed' }
    }
    $null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'f6_final.png') 2>&1 | Out-String)
}
Log 'phaseF6: done'
$lines | Set-Content -LiteralPath $logPath -Encoding UTF8
exit 0
