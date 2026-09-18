# agent_task.ps1 - final phase: cleanup. Stop the bsk session (closes the
# Agent Window created for the arena.ai task; the conversation itself stays
# in the user's arena.ai account history). Idempotent.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

$bsk = Join-Path $env:USERPROFILE '.local\bin\bsk.exe'
if (-not (Test-Path -LiteralPath $bsk)) {
    $f = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bsk = $f.FullName }
}
$env:BSK_AUTO_START = '0'
$sid = ''
$sidFile = Join-Path (Get-Location).Path 'results\status\bsk_session.txt'
if (Test-Path -LiteralPath $sidFile) { $sid = (Get-Content -LiteralPath $sidFile -Raw).Trim() }

if ($sid) {
    $out = (& $bsk session stop $sid 2>&1 | Out-String)
    Write-Output ('task: session stop ' + $sid + ' exit ' + $LASTEXITCODE + ' ' + (($out -replace '\s+', ' ').Trim().Substring(0, [Math]::Min(120, $out.Trim().Length))))
} else {
    Write-Output 'task: no session id on record'
}
$lst = (& $bsk session list --json 2>&1 | Out-String)
Write-Output ('task: remaining sessions -> ' + (($lst -replace '\s+', ' ').Trim()))
Set-Content -LiteralPath (Join-Path (Get-Location).Path 'results\status\agent_task_last.txt') -Value 'ok cleanup done' -Encoding Ascii
Write-Output 'task: done'
exit 0
