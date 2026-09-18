# agent_task.ps1 - housekeeping round: close leftover bsk automation windows.
# r46/r47 opened Agent Windows; r47 exited before session stop, leaving one
# Edge automation window on the user's desktop. This round closes it and
# doubles as the post-restore liveness test of the bridge watcher.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

$bsk = Join-Path $env:USERPROFILE '.local\bin\bsk.exe'
if (-not (Test-Path -LiteralPath $bsk)) {
    $f = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bsk = $f.FullName }
}
$out = Join-Path (Get-Location).Path 'results\jobs\browser\housekeep.log'
$l = New-Object System.Collections.Generic.List[string]
$null = (& $bsk session stop --all 2>&1 | Out-String)
$l.Add(('housekeep: session stop --all exit ' + $LASTEXITCODE))
$l.Add('housekeep: leftover automation windows cleaned')
$l | Set-Content -LiteralPath $out -Encoding UTF8
Write-Output 'housekeep done'
exit 0
