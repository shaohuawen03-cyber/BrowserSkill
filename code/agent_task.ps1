# agent_task.ps1 - one-off task pushed by the agent (local-runner pattern).
# Current task: fetch the OFFICIAL bsk v0.3.0 linux-x64 release tarball into
# results\jobs\ so the agent sandbox can extract it (the sandbox cannot reach
# release-assets.githubusercontent.com; this machine can).
# Idempotent: skips the download when the file already exists.

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072

# repo root = parent of code\ (robust against any inherited CWD)
Set-Location (Split-Path -Parent $PSScriptRoot)

$url = 'https://github.com/Tencent/BrowserSkill/releases/download/cli-v0.3.0/bsk-v0.3.0-x86_64-unknown-linux-musl.tar.gz'
$dir = Join-Path (Get-Location).Path 'results\jobs'
$dest = Join-Path $dir 'bsk-v0.3.0-x86_64-unknown-linux-musl.tar.gz'
New-Item -ItemType Directory -Force -Path $dir | Out-Null

if (Test-Path -LiteralPath $dest) {
    Write-Output ('task: file already present, skipping download: ' + $dest)
} else {
    Write-Output ('task: downloading official bsk release (cli-v0.3.0, linux-x64 musl) ...')
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
}

$item = Get-Item -LiteralPath $dest
$hash = Get-FileHash -LiteralPath $dest -Algorithm SHA256
Write-Output ('task: file=' + $dest)
Write-Output ('task: size=' + $item.Length)
Write-Output ('task: sha256=' + $hash.Hash.ToLower())
if ($item.Length -lt 1000000) {
    Write-Output '[FAIL] downloaded file looks too small'
    exit 1
}

# keep our own debug record where the watcher always pushes (results/)
Set-Content -LiteralPath (Join-Path (Get-Location).Path 'results\status\agent_task_last.txt') -Value ('ok ' + $item.Length + ' sha256=' + $hash.Hash.ToLower()) -Encoding Ascii
Write-Output 'task: done'
exit 0
