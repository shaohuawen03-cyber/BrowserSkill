# where.ps1 - show WHICH local clone matches a session/branch, so the user
# always knows which folder to work in.
#
# Usage (repo root or anywhere):
#     .\where.ps1                              list every clone found
#     .\where.ps1 -Want arena/01a0b237-browserskill
#     .\where.ps1 -Want 01a09d79               partial match works (branch,
#                                              session id, or folder name)
#
# Scan roots: every ancestor of this script that is a git repo, plus the
# children of E:\0github, E:\0github\git-sync and E:\0zhongqi (one level).
# Output is pure ASCII on purpose (PowerShell 5.1 codepage safety).

param([string]$Want = '')

$ErrorActionPreference = 'SilentlyContinue'

$cands = New-Object System.Collections.Generic.List[string]
function Add-Cand([string]$d) {
    if ($d -and (Test-Path -LiteralPath (Join-Path $d '.git'))) { $script:cands.Add($d) }
}

# 1. ancestors of this script (covers "the clone I live in")
$start = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$cur = $start
while ($cur -and $cur -ne (Split-Path -Parent $cur)) {
    Add-Cand $cur
    $cur = Split-Path -Parent $cur
}

# 2. one-level children of the known work roots
$roots = @()
$cur = $start
while ($cur -and $cur -ne (Split-Path -Parent $cur)) { $roots += $cur; $cur = Split-Path -Parent $cur }
$roots += 'E:\0zhongqi'
foreach ($r in ($roots | Select-Object -Unique)) {
    if (-not (Test-Path -LiteralPath $r)) { continue }
    Get-ChildItem -LiteralPath $r -Directory | ForEach-Object { Add-Cand $_.FullName }
}

$cands = $cands | Select-Object -Unique
if (-not $cands -or @($cands).Count -eq 0) { Write-Host 'no git clones found'; exit 1 }

$needle = ''
if ($Want) { $needle = ($Want -replace '^arena/', '') }

$hits = New-Object System.Collections.Generic.List[string]
Write-Host '== local clones:'
foreach ($d in $cands) {
    $b = (git -C $d rev-parse --abbrev-ref HEAD 2>$null)
    if (-not $b) { continue }
    $u = (git -C $d remote get-url origin 2>$null)
    if (-not $u) { $u = '(no origin)' }
    $mark = '      '
    if ($needle) {
        $bb = $b -replace '^arena/', ''
        if (($bb -like ('*' + $needle + '*')) -or ($b -like ('*' + $needle + '*')) -or ((Split-Path -Leaf $d) -like ('*' + $needle + '*'))) {
            $mark = '[USE] '
            $hits.Add($d)
        }
    }
    Write-Host ('  {0}{1}' -f $mark, $d)
    Write-Host ('         branch: {0}    remote: {1}' -f $b, $u)
}

Write-Host ''
if ($Want) {
    if ($hits.Count -gt 0) {
        foreach ($h in $hits) { Write-Host ('== for "' + $Want + '" use THIS folder:  ' + $h) -ForegroundColor Green }
        exit 0
    }
    Write-Host ('== no clone matches "' + $Want + '"') -ForegroundColor Yellow
    exit 2
}
Write-Host 'tip: .\where.cmd -Want <branch-or-session-id>  marks the folder to use.'
exit 0
