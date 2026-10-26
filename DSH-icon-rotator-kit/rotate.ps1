<#
    rotate.ps1 - DeepSeek Harness icon rotator (manual control / diagnostics).

    Icon library (scanned on every run, so new files are picked up immediately):
      %LOCALAPPDATA%\DSH-icon-rotator\icons\*.ico   (the ONLY source; install.cmd
                                                     copies the kit icons here)
    Files whose name contains "original" or "backup" are ignored, and only real
    ICO files (header 00 00 01 00) are used.

    Single icon chain (v6): the chosen icon is always copied into the install
    dir - <install>\resources\tray.ico for the tray, and
    <install>\resources\DSH-icon-chain\<name>.ico for the three shortcuts.
    Shortcut IconLocation never points at the library/kit folder again (icons
    inside the DSH sandbox workspace render as blank).

    Usage:
        rotate.ps1                  random icon, different from the current one
        rotate.ps1 -Season winter   install a specific one (any file base name)
        rotate.ps1 -List            show the discovered library
        rotate.ps1 -Season restore  restore the original icon
        rotate.ps1 -Quiet           no console output (used by scripts)
#>
[CmdletBinding()]
param(
    [string]$Season = 'random',
    [switch]$List,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

$Root      = Join-Path $env:LOCALAPPDATA 'DSH-icon-rotator'
$IconsDir  = Join-Path $Root 'icons'
$LogPath   = Join-Path $Root 'rotate.log'
$StatePath = Join-Path $Root 'state.json'
$LastFile  = Join-Path $Root 'last-icon.txt'

function Write-Log([string]$Message) {
    try {
        $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
        $lines = @(Get-Content -LiteralPath $LogPath -Encoding UTF8 -ErrorAction SilentlyContinue)
        if ($lines.Count -gt 300) {
            $tail = $lines[($lines.Count - 300)..($lines.Count - 1)]
            Set-Content -LiteralPath $LogPath -Value $tail -Encoding UTF8
        }
    } catch { }
}

function Get-HashSafe([string]$Path) {
    if ([string]::IsNullOrEmpty($Path)) { return $null }
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try { $bytes = $sha.ComputeHash($fs) } finally { $fs.Dispose(); $sha.Dispose() }
        return ([System.BitConverter]::ToString($bytes) -replace '-', '')
    } catch { return $null }
}

function Get-FileSizeSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return -1 }
    try { return (Get-Item -LiteralPath $Path).Length } catch { return -1 }
}

function Test-Ico([string]$Path) {
    try {
        $buf = New-Object byte[] 4
        $fs = [System.IO.File]::OpenRead($Path)
        try { $n = $fs.Read($buf, 0, 4) } finally { $fs.Dispose() }
        if ($n -lt 4) { return $false }
        return ($buf[0] -eq 0 -and $buf[1] -eq 0 -and $buf[2] -eq 1 -and $buf[3] -eq 0)
    } catch { return $false }
}

function Find-InstallDir {
    $marker = Join-Path $Root 'install-path.txt'
    if (Test-Path -LiteralPath $marker) {
        $recorded = (Get-Content -LiteralPath $marker -Raw -ErrorAction SilentlyContinue)
        if ($recorded) {
            $recorded = $recorded.Trim()
            if ($recorded -and (Test-Path -LiteralPath (Join-Path $recorded 'DeepSeek Harness.exe'))) { return $recorded }
        }
    }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness'),
        (Join-Path $env:ProgramFiles 'DeepSeek Harness'),
        (Join-Path ${env:ProgramFiles(x86)} 'DeepSeek Harness')
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath (Join-Path $c 'DeepSeek Harness.exe'))) { return $c }
    }
    try {
        $ws = New-Object -ComObject WScript.Shell
        foreach ($lnk in @(
                (Join-Path $env:USERPROFILE 'Desktop\DeepSeek Harness.lnk'),
                (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\DeepSeek Harness.lnk'))) {
            if (-not (Test-Path -LiteralPath $lnk)) { continue }
            $target = $ws.CreateShortcut($lnk).TargetPath
            if ($target -and (Test-Path -LiteralPath $target)) {
                $dir = Split-Path -Parent $target
                if (Test-Path -LiteralPath (Join-Path $dir 'DeepSeek Harness.exe')) { return $dir }
            }
        }
    } catch { }
    return $null
}

$InstallDir = Find-InstallDir
if (-not $InstallDir) {
    Write-Log 'ERROR install dir not found'
    if (-not $Quiet) { Write-Error 'DeepSeek Harness install dir not found.' }
    exit 2
}
$TrayPath = Join-Path $InstallDir 'resources\tray.ico'

# ---------------------------------------------------------------- icon library
# v7: single source - the managed folder only. New icons must be copied there
# (install.cmd does that for the kit's icons\ folder).
$Library = [ordered]@{}
foreach ($dir in @($IconsDir)) {
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    foreach ($file in (Get-ChildItem -LiteralPath $dir -Filter *.ico -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($file.Name).ToLowerInvariant()
        if ($base -like '*original*' -or $base -like '*backup*') { continue }
        if ($Library.Contains($base)) { continue }
        if (-not (Test-Ico $file.FullName)) {
            Write-Log ("WARN not a valid ico, ignored: " + $file.FullName)
            continue
        }
        $Library[$base] = $file.FullName
    }
}

# identical icons often exist under different names: dedupe by file size
$seenSizes = @{}
$deduped = [ordered]@{}
foreach ($k in $Library.Keys) {
    $sz = Get-FileSizeSafe $Library[$k]
    if ($seenSizes.ContainsKey($sz)) { continue }
    $seenSizes[$sz] = $true
    $deduped[$k] = $Library[$k]
}
$Library = $deduped

if ($List) {
    Write-Output ("install dir : " + $InstallDir)
    Write-Output ("sources     : " + $IconsDir)
    Write-Output ("library     : " + $Library.Count + " icon(s)")
    Write-Output ("canonical   : " + $TrayPath)
    Write-Output ("chain dir   : " + (Join-Path (Split-Path -Parent $TrayPath) 'DSH-icon-chain'))
    foreach ($k in $Library.Keys) {
        Write-Output ("  " + $k.PadRight(14) + " " + $Library[$k])
    }
    $current = Get-HashSafe $TrayPath
    foreach ($k in $Library.Keys) {
        if ((Get-HashSafe $Library[$k]) -eq $current) { Write-Output ("current     : " + $k) }
    }
    exit 0
}

if ($Library.Count -eq 0) {
    Write-Log 'ERROR no usable icons found'
    if (-not $Quiet) { Write-Error 'No usable .ico files found.' }
    exit 3
}

$CurrentHash = Get-HashSafe $TrayPath
$CurrentSize = Get-FileSizeSafe $TrayPath
$LastSeason = ''
if (Test-Path -LiteralPath $LastFile) {
    try { $LastSeason = (Get-Content -LiteralPath $LastFile -Raw).Trim().ToLowerInvariant() } catch { }
}

if ($Season -eq 'restore') {
    $Source = Join-Path $Root 'original-tray.ico'
    if (-not (Test-Path -LiteralPath $Source)) {
        Write-Log 'ERROR original icon backup missing'
        if (-not $Quiet) { Write-Error 'Original icon backup missing.' }
        exit 4
    }
    $Label = 'original'
    $NewLast = ''
}
elseif ($Season -eq 'random') {
    $Pool = @($Library.Keys | Where-Object {
            $_ -ne $LastSeason -and (Get-FileSizeSafe $Library[$_]) -ne $CurrentSize
        })
    if ($Pool.Count -eq 0) { $Pool = @($Library.Keys | Where-Object { $_ -ne $LastSeason }) }
    if ($Pool.Count -eq 0) { $Pool = @($Library.Keys) }
    $rng = New-Object System.Random
    $pickName = $Pool[$rng.Next($Pool.Count)]
    $Label = $pickName
    $Source = $Library[$pickName]
    $NewLast = $pickName
}
else {
    $want = $Season.ToLowerInvariant()
    if (-not $Library.Contains($want)) {
        $known = ($Library.Keys -join ', ')
        Write-Log ("ERROR unknown icon '" + $Season + "'; known: " + $known)
        if (-not $Quiet) { Write-Error ("Unknown icon '" + $Season + "'. Known: " + $known) }
        exit 5
    }
    $Label = $want
    $Source = $Library[$want]
    $NewLast = $want
}

# install: write a temp file next to the target, then replace
$ok = $false
for ($attempt = 0; $attempt -lt 3; $attempt++) {
    try {
        $tmp = "$TrayPath.tmp"
        Copy-Item -LiteralPath $Source -Destination $tmp -Force
        Move-Item -LiteralPath $tmp -Destination $TrayPath -Force
        $ok = $true
        break
    } catch { Start-Sleep -Milliseconds 150 }
}
if (-not $ok) {
    Write-Log "ERROR could not replace tray.ico at $TrayPath"
    if (-not $Quiet) { Write-Error 'Could not replace tray.ico (file in use?).' }
    exit 6
}

# v6: the shortcuts get their own copy inside the install dir, named after the
# library icon. A stable filename with changing content would be served from
# the shell icon cache (old image); a per-icon filename can never go stale.
$ChainDir = Join-Path (Split-Path -Parent $TrayPath) 'DSH-icon-chain'
if (-not (Test-Path -LiteralPath $ChainDir)) { New-Item -ItemType Directory -Path $ChainDir -Force | Out-Null }
$ChainIcon = Join-Path $ChainDir ([System.IO.Path]::GetFileNameWithoutExtension($Source).ToLowerInvariant() + '.ico')
if ((Get-HashSafe $ChainIcon) -ne (Get-HashSafe $Source)) {
    Copy-Item -LiteralPath $Source -Destination $ChainIcon -Force
}
$ShortcutIcon = $ChainIcon

# mirror the choice on the shortcuts (icon only)
$Shortcuts = @(
    (Join-Path $env:USERPROFILE 'Desktop\DeepSeek Harness.lnk'),
    (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\DeepSeek Harness.lnk'),
    (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\DeepSeek Harness.lnk')
)
$notify = $false
try {
    if (-not ('DshIconNotify' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DshIconNotify {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern void SHChangeNotify(int eventId, uint flags, string item1, IntPtr item2);
    // SHCNE_UPDATEITEM | SHCNF_PATHW: this .lnk changed
    public static void UpdateItem(string path) {
        SHChangeNotify(0x00002000, 0x0005, path, IntPtr.Zero);
    }
    // SHCNE_UPDATEIMAGE | SHCNF_PATHW: the image of this icon file changed
    public static void UpdateImage(string path) {
        SHChangeNotify(0x00008000, 0x0005, path, IntPtr.Zero);
    }
}
'@
    }
    $notify = $true
} catch { Write-Log 'WARN shell notify unavailable, continuing' }

$Updated = 0
try {
    $WsShell = New-Object -ComObject WScript.Shell
    foreach ($Lnk in $Shortcuts) {
        if (-not (Test-Path -LiteralPath $Lnk)) { continue }
        try {
            $Link = $WsShell.CreateShortcut($Lnk)
            $Wanted = "$ShortcutIcon,0"
            # v6: always rewrite the link. All three icons share one file
            # (<install>\resources\tray.ico) whose path never changes, so touch
            # the .lnk and notify the shell to re-read the image.
            $Link.IconLocation = $Wanted
            $Link.Save()
            $Updated++
            if ($notify) {
                [DshIconNotify]::UpdateImage($ShortcutIcon)
                [DshIconNotify]::UpdateItem($Lnk)
            }
        } catch {
            Write-Log ("WARN shortcut failed: {0} :: {1}" -f $Lnk, $_.Exception.Message)
        }
    }
} catch {
    Write-Log ("WARN shortcut sync failed :: {0}" -f $_.Exception.Message)
}

try { Set-Content -LiteralPath $LastFile -Value $NewLast -Encoding ASCII } catch { }

$TrayHash = Get-HashSafe $TrayPath
$stamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
$json = @(
    '{',
    ('  "time": "{0}",' -f $stamp),
    ('  "season": "{0}",' -f $Label),
    ('  "trayHash": "{0}",' -f $TrayHash),
    ('  "iconPath": "{0}",' -f ($ShortcutIcon -replace '\\', '\\')),
    ('  "source": "{0}"' -f ($Source -replace '\\', '\\')),
    '}'
)
try { Set-Content -LiteralPath $StatePath -Value $json -Encoding UTF8 } catch { }

Write-Log ("rotated -> {0} (shortcuts updated: {1})" -f $Label, $Updated)
if (-not $Quiet) { Write-Output $Label }
