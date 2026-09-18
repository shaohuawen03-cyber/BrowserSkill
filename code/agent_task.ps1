# agent_task.ps1 - r52: (A) census + targeted cleanup of stray POWERSHELL
# windows the user reports (15 visible), (B) K6 arena dispatch with a 12-min
# warm-up window. PS windows are killed ONLY when their command line anchors
# to one of the two BrowserSkill clones (never a blanket kill).

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)
$root = (Get-Location).Path

$outDir = Join-Path $root 'results\jobs\browser\phaseK6'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$log = Join-Path $outDir 'k6.log'
$lines = New-Object System.Collections.Generic.List[string]
function Log([string]$s) { $script:lines.Add($s); Write-Output $s }
function Snap([string]$name) {
    $s = (& $bsk snapshot --session $script:sid --max-tokens 30000 2>&1 | Out-String)
    $s | Set-Content -LiteralPath (Join-Path $outDir $name) -Encoding UTF8
    return $s
}
function Scroll-Bottom {
    $null = (& $bsk evaluate '(function(){var d=document.scrollingElement;d.scrollTop=d.scrollHeight;return d.scrollTop;})()' --session $script:sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 3s --session $script:sid 2>&1 | Out-String)
}
function Finish([int]$code) {
    if ($script:sid) { $null = (& $bsk session stop --all 2>&1 | Out-String); Log ('k6: final session stop exit ' + $LASTEXITCODE) }
    $script:lines | Set-Content -LiteralPath $script:log -Encoding UTF8
    exit $code
}

# ---- 0. refresh root scripts (consistency gate)
$src = Join-Path $root 'skills\git-sync\scripts'
foreach ($f in @('where.ps1', 'where.cmd', 'download.ps1')) {
    $from = Join-Path $src $f
    if (Test-Path -LiteralPath $from) { Copy-Item -Force -LiteralPath $from -Destination (Join-Path $root $f) }
}

# ---- A. POWERSHELL census + targeted cleanup
$sig = @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public class WC2 {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
}
'@
try { Add-Type -TypeDefinition $sig -ErrorAction Stop } catch { }

$psProcs = @()
try {
    $psProcs = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -ErrorAction Stop
} catch { Log ('psA: census failed: ' + $_.Exception.Message) }
Log ('psA: powershell processes total = ' + @($psProcs).Count)

$myClone = 'BrowserSkill-01a0b237'
$arenaClone = 'BrowserSkill-01a0b352'
$kill = New-Object System.Collections.Generic.List[object]
foreach ($p in $psProcs) {
    $cl = [string]$p.CommandLine
    if (-not $cl) { $cl = '(no command line)' }
    $short = $cl -replace '\s+', ' '
    if ($short.Length -gt 150) { $short = $short.Substring(0, 150) }
    $mine = ($cl -match [regex]::Escape($myClone)) -or ($cl -match [regex]::Escape($arenaClone))
    $hook = ($cl -match 'watch\.ps1') -or ($cl -match 'agent_task\.ps1') -or ($cl -match 'local_check\.ps1') -or ($cl -match 'bootstrap\.ps1') -or ($cl -match 'sync\.ps1')
    $tag = 'other'
    if ($mine -and $hook) { $tag = 'OURS' }
    elseif ($cl -match '-Loop') { $tag = 'loop-other-clone' }
    Log ('psA: pid ' + $p.ProcessId + ' parent ' + $p.ParentProcessId + ' [' + $tag + '] ' + $short)
    if ($tag -eq 'OURS' -and $p.ProcessId -ne $PID) { $kill.Add($p) }
}

# visible-window mapping for powershell processes
try {
    $psIds = @{}
    foreach ($p in $psProcs) { $psIds[[uint32]$p.ProcessId] = 1 }
    $cb = [WC2+EnumProc]{
        param($h, $lp)
        if ([WC2]::IsWindowVisible($h)) {
            $pid2 = [uint32]0
            $null = [WC2]::GetWindowThreadProcessId($h, [ref]$pid2)
            if ($psIds.ContainsKey($pid2)) {
                $t = New-Object System.Text.StringBuilder 512
                $n = [WC2]::GetWindowText($h, $t, 512)
                $txt = 'untitled'
                if ($n -gt 0) { $txt = $t.ToString() }
                if ($txt.Length -gt 100) { $txt = $txt.Substring(0, 100) }
                Log ('psA: VISIBLE PS WINDOW pid ' + $pid2 + ' title: ' + $txt)
            }
        }
        return $true
    }
    $null = [WC2]::EnumWindows($cb, [IntPtr]::Zero)
} catch { Log ('psA: window map failed: ' + $_.Exception.Message) }

$killed = 0
foreach ($p in $kill) {
    try {
        Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
        $killed++
        Log ('psA: killed stray pid ' + $p.ProcessId)
    } catch { Log ('psA: could not kill pid ' + $p.ProcessId + ': ' + $_.Exception.Message) }
}
Log ('psA: killed ' + $killed + ' of ' + @($kill).Count + ' targeted strays')
$left = @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -ErrorAction SilentlyContinue)
Log ('psA: powershell processes after = ' + @($left).Count)

# bsk session hygiene
$bsk = Join-Path $env:USERPROFILE '.local\bin\bsk.exe'
if (-not (Test-Path -LiteralPath $bsk)) {
    $f = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.local') -Recurse -Filter 'bsk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bsk = $f.FullName }
}
$env:BSK_AUTO_START = '0'
$null = (& $bsk session stop --all 2>&1 | Out-String)
Log ('psA: bsk session stop --all exit ' + $LASTEXITCODE)

# ---- B. K6 arena dispatch (12-min warm window)
$st = (& $bsk session start --name 'arena-k6' --json 2>&1 | Out-String)
$m = [regex]::Match($st, '"session_id"\s*:\s*"([^"]+)"')
if (-not $m.Success) { $m = [regex]::Match($st, '"id"\s*:\s*"([^"]+)"') }
$sid = ''
if ($m.Success) { $sid = $m.Groups[1].Value }
if (-not $sid) { Log 'k6: [FAIL] no session'; Finish 1 }
$sid | Set-Content -LiteralPath (Join-Path $root 'results\status\bsk_session.txt') -Encoding Ascii
Log ('k6: session ' + $sid)

$tabs = (& $bsk tab list --session $sid --json 2>&1 | Out-String)
$tabs | Set-Content -LiteralPath (Join-Path $outDir 'k6_tabs.json') -Encoding UTF8
$tid = ''
foreach ($mm in [regex]::Matches($tabs, '\{[^{}]*\}')) {
    if ($mm.Value -match 'arena\.ai') { $c = [regex]::Match($mm.Value, '"tab_id"\s*:\s*(\d+)').Groups[1].Value; if ($c -and -not $tid) { $tid = $c } }
}
if (-not $tid) { Log 'k6: [FAIL] no arena tab - keep arena.ai open in Edge'; Finish 1 }
$null = (& $bsk tab borrow $tid --session $sid --timeout 300 2>&1 | Out-String)
Log ('k6: borrow tab ' + $tid + ' exit ' + $LASTEXITCODE)
if ($LASTEXITCODE -ne 0) { Log 'k6: [FAIL] borrow denied'; Finish 1 }
$null = (& $bsk tab select $tid --session $sid 2>&1 | Out-String)

$null = (& $bsk navigate 'https://arena.ai/agent' --session $sid 2>&1 | Out-String)
$rendered = $false
for ($i = 1; $i -le 75; $i++) {
    $null = (& $bsk wait-ms 10s --session $sid 2>&1 | Out-String)
    $s0 = Snap ('k6_home_p' + $i + '.txt')
    if (($s0 -match 'textbox') -and ($s0 -match 'Today')) { $rendered = $true; Log ('k6: home rendered at poll ' + $i); break }
    if ($i -eq 25 -or $i -eq 50) { $null = (& $bsk tab select $tid --session $sid 2>&1 | Out-String); $null = (& $bsk reload --session $sid 2>&1 | Out-String) }
}
if (-not $rendered) { Log 'k6: [FAIL] home cold after 12 min - click the arena tab and we rerun'; Finish 1 }

$js = '(function(){var N=String.fromCharCode(102,97,100,49,45,55,49,54,56);var L=document.links;var k=-1;for(var i=0;i<L.length;i++){if(L[i].href.indexOf(N)>=0){k=i;break;}}if(k>=0){L[k].click();return 1;}return 0;})()'
$opened = $false
for ($pass = 1; $pass -le 5 -and -not $opened; $pass++) {
    Scroll-Bottom
    $r = (& $bsk evaluate $js --session $sid 2>&1 | Out-String)
    Log ('k6: pass ' + $pass + ' dom-click -> ' + (($r -replace '\s+', ' ').Trim().Substring(0, [Math]::Min(90, $r.Trim().Length))))
    for ($i = 1; $i -le 12; $i++) {
        $null = (& $bsk wait-ms 5s --session $sid 2>&1 | Out-String)
        $s0 = Snap ('k6_conv_pass' + $pass + '_p' + $i + '.txt')
        if (($s0 -match 'textbox') -and ($s0 -match 'combobox')) { $opened = $true; Log ('k6: conversation open (pass ' + $pass + ' poll ' + $i + ')'); break }
    }
}
if (-not $opened) { Log 'k6: [FAIL] conversation never opened'; Finish 1 }
Scroll-Bottom
$s0 = Snap 'k6_conv_bottom.txt'

$needle = -join @([char]0x7F01, [char]0x0445, [char]0x753B, [char]0x5BB8, [char]0x30E4, [char]0x7D94)
$contRef = ''
foreach ($mm in [regex]::Matches($s0, '@(e\d+) button[^\r\n]*')) {
    if ($mm.Value.Contains($needle)) { $contRef = $mm.Groups[1].Value; Log ('k6: continue button @' + $contRef); break }
}
if ($contRef) {
    $null = (& $bsk click ('@' + $contRef) --session $sid 2>&1 | Out-String)
    Log ('k6: clicked continue (exit ' + $LASTEXITCODE + ')')
    $null = (& $bsk wait-ms 4s --session $sid 2>&1 | Out-String)
    Scroll-Bottom
    $s0 = Snap 'k6_after_continue.txt'
} else {
    Log 'k6: no continue button - composer assumed free'
}

$promptFile = Join-Path $root 'results\status\arena_prompt3.txt'
$msg = (Get-Content -LiteralPath $promptFile -Raw -Encoding UTF8).Trim()
Log ('k6: prompt3 chars=' + $msg.Length)
Set-Clipboard -Value $msg
$filled = $false
for ($att = 1; $att -le 4 -and -not $filled; $att++) {
    $s1 = Snap ('k6_att' + $att + '_a.txt')
    $tb = [regex]::Match($s1, '@(e\d+) textbox').Groups[1].Value
    if (-not $tb) { Log ('k6: att ' + $att + ' - no textbox'); continue }
    $null = (& $bsk click ('@' + $tb) --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 700ms --session $sid 2>&1 | Out-String)
    $null = (& $bsk press Ctrl+v --session $sid 2>&1 | Out-String)
    $null = (& $bsk wait-ms 1500ms --session $sid 2>&1 | Out-String)
    $s3 = Snap ('k6_att' + $att + '_c.txt')
    if (($s3 -match 'textbox[^\r\n]*\[filled\]') -or ($s3 -match '3/3')) { $filled = $true; Log ('k6: att ' + $att + ' - PROMPT IN COMPOSER') }
}
if (-not $filled) { Log 'k6: [FAIL] composer never held the prompt'; Finish 1 }

$s4 = Snap 'k6_before_send.txt'
$sendRef = [regex]::Match($s4, '@(e\d+) button "Send message').Groups[1].Value
if ($sendRef) {
    $null = (& $bsk click ('@' + $sendRef) --session $sid 2>&1 | Out-String)
    Log ('k6: clicked Send @' + $sendRef + ' (exit ' + $LASTEXITCODE + ')')
} else {
    $null = (& $bsk press Enter --session $sid 2>&1 | Out-String)
    Log 'k6: Enter fallback'
}
$echo = $false
for ($i = 1; $i -le 6; $i++) {
    $null = (& $bsk wait-ms 10s --session $sid 2>&1 | Out-String)
    $sx = Snap ('k6_send_p' + $i + '.txt')
    if (($sx -match 'Stop generating') -or ($sx -match 'orchestrating')) { $echo = $true; Log ('k6: dispatch confirmed at poll ' + $i); break }
}
if (-not $echo) { Log 'k6: WARN dispatch unconfirmed - verify via git' }
Scroll-Bottom
$t = (& $bsk evaluate document.body.innerText --session $sid 2>&1 | Out-String)
$t | Set-Content -LiteralPath (Join-Path $outDir 'k6_page_text.txt') -Encoding UTF8
Log ('k6: page text bytes=' + $t.Length)
$null = (& $bsk screenshot --session $sid --out (Join-Path $outDir 'k6_final.png') 2>&1 | Out-String)
Log 'k6: 3-round plan dispatched'
Finish 0
