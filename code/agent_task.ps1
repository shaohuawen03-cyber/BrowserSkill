# agent_task.ps1 - one-off task pushed by the agent (local-runner pattern).
# Current task: fetch the OFFICIAL bsk v0.3.0 linux-x64 release tarball into
# sources\ so the agent sandbox can extract it (the sandbox cannot reach
# release-assets.githubusercontent.com; this machine can).
# Idempotent: skips the download when the file already exists.

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072

$url = 'https://github.com/Tencent/BrowserSkill/releases/download/cli-v0.3.0/bsk-v0.3.0-x86_64-unknown-linux-musl.tar.gz'
$root = (Get-Location).Path
$dir = Join-Path $root 'sources'
$dest = Join-Path $dir 'bsk-v0.3.0-x86_64-unknown-linux-musl.tar.gz'
New-Item -ItemType Directory -Force -Path $dir | Out-Null

if (Test-Path -LiteralPath $dest) {
    Write-Output ('task: file already present, skipping download: ' + (Split-Path -Leaf $dest))
} else {
    Write-Output 'task: downloading official bsk release (cli-v0.3.0, linux-x64 musl) ...'
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
}

$item = Get-Item -LiteralPath $dest
$hash = Get-FileHash -LiteralPath $dest -Algorithm SHA256
Write-Output ('task: ' + $item.Name + ' size=' + $item.Length)
Write-Output ('task: sha256=' + $hash.Hash.ToLower())
if ($item.Length -lt 1000000) {
    Write-Output '[FAIL] downloaded file looks too small'
    exit 1
}
Write-Output 'task: done'
exit 0
