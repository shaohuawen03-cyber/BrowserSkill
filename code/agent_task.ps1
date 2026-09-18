# agent_task.ps1 - stage 1: BrowserSkill LOCAL stack on this machine
# (official bsk CLI + local daemon on 127.0.0.1:52800). The extension popup
# in local mode connects to that daemon. Orchestrated by the agent through
# the git-sync loop; idempotent - safe to run on every check round.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)   # repo root

$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$bskDir = Join-Path $env:USERPROFILE '.local\bin'
$bsk = Join-Path $bskDir 'bsk.exe'

# ---- 1. the official bsk CLI -------------------------------------------------
if (-not (Test-Path -LiteralPath $bsk)) {
    Write-Output 'task: bsk.exe not found - running the OFFICIAL install.ps1 ...'
    $inst = Join-Path $env:TEMP 'bsk-install.ps1'
    Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/Tencent/BrowserSkill/main/install.ps1' -OutFile $inst -UseBasicParsing
    $null = (& $psExe -NoProfile -ExecutionPolicy Bypass -File $inst 2>&1 | Out-String)
    Write-Output ('task: install.ps1 exit ' + $LASTEXITCODE)
}
if (-not (Test-Path -LiteralPath $bsk)) {
    $found = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $bsk = $found.FullName }
}
if (-not (Test-Path -LiteralPath $bsk)) {
    Write-Output '[FAIL] bsk.exe still missing after install'
    Set-Content -LiteralPath (Join-Path (Get-Location).Path 'results\status\agent_task_last.txt') -Value 'FAIL bsk.exe missing' -Encoding Ascii
    exit 1
}
$ver = ((& $bsk --version) 2>&1 | Out-String).Trim()
Write-Output ('task: bsk --version -> ' + $ver)

# ---- 2. the local daemon (mode local, port 52800) ----------------------------
$env:BSK_AUTO_START = '0'
$st = ((& $bsk status --json) 2>&1 | Out-String).Trim()
if ($st -notmatch '"browsers"') {
    Write-Output 'task: local daemon not answering - starting it ...'
    $null = (& $bsk daemon start 2>&1 | Out-String)
    Start-Sleep -Seconds 4
    $st = ((& $bsk status --json) 2>&1 | Out-String).Trim()
}
$stOne = ($st -replace '\s+', ' ')
if ($stOne.Length -gt 600) { $stOne = $stOne.Substring(0, 600) + ' ...' }
Write-Output ('task: bsk status -> ' + $stOne)
if ($st -match '"browsers"') {
    Write-Output 'task: local daemon is UP (extension connects in local mode, port 52800)'
    Set-Content -LiteralPath (Join-Path (Get-Location).Path 'results\status\agent_task_last.txt') -Value ('ok bsk=' + $ver + ' daemon=up') -Encoding Ascii
    Write-Output 'task: done'
    exit 0
}
Write-Output '[WARN] daemon still not reporting - will retry next round'
Set-Content -LiteralPath (Join-Path (Get-Location).Path 'results\status\agent_task_last.txt') -Value ('WARN bsk=' + $ver + ' status=' + $stOne) -Encoding Ascii
exit 0
