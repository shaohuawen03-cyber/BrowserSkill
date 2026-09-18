# agent_task.ps1 - housekeeping v2: window census + session sweep + where demo.
# User reports ~15 leftover automation windows. Agent Windows live inside the
# user's own Edge instance (extension-created), so we NEVER kill processes;
# we close them via the daemon registry (session stop --all) and take a
# window census (titles) before/after as evidence. Also refreshes the
# user-side scripts at the repo root (where.ps1/where.cmd/download.ps1) and
# runs the where.cmd demo the user asked for.

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)
$root = (Get-Location).Path

$out = Join-Path $root 'results\jobs\browser\housekeep2.log'
$l = New-Object System.Collections.Generic.List[string]
function Log([string]$s) { $script:l.Add($s); Write-Output $s }

# ---- 0. refresh user-side root scripts (new where tool + provenance dl)
$src = Join-Path $root 'skills\git-sync\scripts'
foreach ($f in @('where.ps1', 'where.cmd', 'download.ps1')) {
    $from = Join-Path $src $f
    if (Test-Path -LiteralPath $from) { Copy-Item -Force -LiteralPath $from -Destination (Join-Path $root $f) }
}
Log 'housekeep2: root scripts refreshed (where.ps1, where.cmd, download.ps1)'

# ---- 1. window census helper (Edge windows only; NO process killing)
$sig = @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public class WCensus {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
}
'@
try { Add-Type -TypeDefinition $sig -ErrorAction Stop } catch { }
function Get-EdgeWindows {
    $res = New-Object System.Collections.Generic.List[string]
    try {
        $procs = @{}
        Get-Process msedge -ErrorAction SilentlyContinue | ForEach-Object { $procs[[uint32]$_.Id] = 1 }
        $cb = [WCensus+EnumProc]{
            param($h, $lp)
            if ([WCensus]::IsWindowVisible($h)) {
                $cn = New-Object System.Text.StringBuilder 256
                $null = [WCensus]::GetClassName($h, $cn, 256)
                if ($cn.ToString() -eq 'Chrome_WidgetWin_1') {
                    $pid2 = [uint32]0
                    $null = [WCensus]::GetWindowThreadProcessId($h, [ref]$pid2)
                    if ($procs.ContainsKey($pid2)) {
                        $t = New-Object System.Text.StringBuilder 512
                        $n = [WCensus]::GetWindowText($h, $t, 512)
                        if ($n -gt 0) { $res.Add(($t.ToString() -replace '\s+', ' ').Trim()) }
                    }
                }
            }
            return $true
        }
        $null = [WCensus]::EnumWindows($cb, [IntPtr]::Zero)
    } catch { $res.Add('census-unavailable: ' + $_.Exception.Message) }
    return $res
}

$before = Get-EdgeWindows
Log ('housekeep2: EDGE WINDOWS BEFORE = ' + @($before).Count)
foreach ($t in $before) { if ($t) { Log ('  before-title: ' + $t.Substring(0, [Math]::Min(110, $t.Length))) } }

# ---- 2. daemon session sweep (the ONLY safe way to close Agent Windows)
$bsk = Join-Path $env:USERPROFILE '.local\bin\bsk.exe'
if (-not (Test-Path -LiteralPath $bsk)) {
    $f = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bsk = $f.FullName }
}
$env:BSK_AUTO_START = '0'
$s1 = (& $bsk session list --json 2>&1 | Out-String)
($s1 | Out-String) | Set-Content -LiteralPath (Join-Path $root 'results\jobs\browser\housekeep2_sessions_before.json') -Encoding UTF8
Log ('housekeep2: sessions before -> ' + (($s1 -replace '\s+', ' ').Trim().Substring(0, [Math]::Min(300, $s1.Trim().Length))))
$null = (& $bsk session stop --all 2>&1 | Out-String)
Log ('housekeep2: session stop --all exit ' + $LASTEXITCODE)
$null = Start-Sleep -Seconds 4
$s2 = (& $bsk session list --json 2>&1 | Out-String)
Log ('housekeep2: sessions after  -> ' + (($s2 -replace '\s+', ' ').Trim().Substring(0, [Math]::Min(300, $s2.Trim().Length))))

# ---- 3. census after
$after = Get-EdgeWindows
Log ('housekeep2: EDGE WINDOWS AFTER = ' + @($after).Count)
foreach ($t in $after) { if ($t) { Log ('  after-title: ' + $t.Substring(0, [Math]::Min(110, $t.Length))) } }

# ---- 4. where.cmd demo (the feature the user asked to see working)
$wd = (& cmd /c '.\where.cmd -Want 01a0b237' 2>&1 | Out-String)
Log 'housekeep2: where.cmd demo:'
foreach ($ln in ($wd -split "`r?`n")) { if ($ln.Trim()) { Log ('  | ' + $ln.Trim()) } }

Log 'housekeep2: done'
$l | Set-Content -LiteralPath $out -Encoding UTF8
exit 0
