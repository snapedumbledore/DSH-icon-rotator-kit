<#
    install.ps1 - one-shot installer for the DeepSeek Harness seasonal tray icon
    rotator. Intended to be copied together with this folder ("DSH-icon-rotator-kit")
    to any Windows PC that already has DeepSeek Harness installed.

    No administrator rights are required: everything is written under the current
    user's profile plus one HKCU Run entry.

    Usage:
        install.ps1
        install.ps1 -InstallDir "D:\Apps\DeepSeek Harness"
        install.ps1 -Season winter            # first icon to install
#>
[CmdletBinding()]
param(
    [string]$InstallDir = '',
    # any icon name found in the library, or "random"
    [string]$Season = 'random'
)

$ErrorActionPreference = 'Stop'

# ignore junk passed positionally (e.g. files dropped onto install.cmd)
if ($Season -match '[\\/:*?"<>|]') { $Season = 'random' }

$KitDir = $PSScriptRoot
$Root   = Join-Path $env:LOCALAPPDATA 'DSH-icon-rotator'
$Icons  = Join-Path $Root 'icons'
$RunKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$RunName = 'DSH-icon-rotator'

function Write-Step([string]$Text) { Write-Output ("  - " + $Text) }

$Shortcuts = @(
    (Join-Path $env:USERPROFILE 'Desktop\DeepSeek Harness.lnk'),
    (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\DeepSeek Harness.lnk'),
    (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\DeepSeek Harness.lnk')
)

# ---------------------------------------------------------------- 1. locate app
function Find-InstallDir([string]$Hint) {
    $tries = New-Object System.Collections.ArrayList
    if ($Hint) { [void]$tries.Add($Hint) }
    [void]$tries.Add((Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness'))
    if ($env:ProgramFiles) { [void]$tries.Add((Join-Path $env:ProgramFiles 'DeepSeek Harness')) }
    if (${env:ProgramFiles(x86)}) { [void]$tries.Add((Join-Path ${env:ProgramFiles(x86)} 'DeepSeek Harness')) }
    foreach ($t in $tries) {
        if ($t -and (Test-Path -LiteralPath (Join-Path $t 'DeepSeek Harness.exe'))) { return $t }
    }
    # follow the shortcuts
    try {
        $ws = New-Object -ComObject WScript.Shell
        foreach ($lnk in $Shortcuts) {
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

Write-Output 'DeepSeek Harness seasonal icon rotator - installer'
Write-Output ''

$appDir = Find-InstallDir $InstallDir
if (-not $appDir) {
    Write-Output 'ERROR: DeepSeek Harness was not found.'
    Write-Output 'Install it first, or pass the folder that contains "DeepSeek Harness.exe":'
    Write-Output '    install.ps1 -InstallDir "D:\Apps\DeepSeek Harness"'
    exit 1
}
$appExe = Join-Path $appDir 'DeepSeek Harness.exe'
$trayFile = Join-Path $appDir 'resources\tray.ico'
Write-Step ("application : " + $appDir)
Write-Step ("tray icon   : " + $trayFile)
if (-not (Test-Path -LiteralPath $trayFile)) {
    Write-Output 'ERROR: resources\tray.ico not found - this DeepSeek Harness build does not use an external tray icon.'
    exit 1
}

# ------------------------------------------------------- 2. prepare data folder
foreach ($d in @($Root, $Icons)) {
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

foreach ($f in 'rotate.ps1', 'guard.vbs', 'diagnose.ps1', 'README.txt') {
    $srcFile = Join-Path $KitDir $f
    if (Test-Path -LiteralPath $srcFile) {
        Copy-Item -LiteralPath $srcFile -Destination (Join-Path $Root $f) -Force
    }
}
$copied = 0
foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $KitDir 'icons') -Filter *.ico -File -ErrorAction SilentlyContinue)) {
    $base = $f.BaseName.ToLowerInvariant()
    if ($base -like '*original*' -or $base -like '*backup*') { continue }
    Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $Icons $f.Name) -Force
    $copied++
}
Set-Content -LiteralPath (Join-Path $Root 'install-path.txt') -Value $appDir -Encoding ASCII
Set-Content -LiteralPath (Join-Path $Root 'kit-path.txt') -Value $KitDir -Encoding ASCII
Write-Step ("files copied to " + $Root + " (" + $copied + " .ico)")

# keep the very first original icon as the rollback source
$original = Join-Path $Root 'original-tray.ico'
if (-not (Test-Path -LiteralPath $original)) {
    Copy-Item -LiteralPath $trayFile -Destination $original -Force
    Write-Step 'original tray icon backed up'
} else {
    Write-Step 'original tray icon backup already present (kept)'
}

# ------------------------------------------------------------ 3. back up links
$lnkBackup = Join-Path $Root 'lnk-backup'
if (-not (Test-Path -LiteralPath $lnkBackup)) { New-Item -ItemType Directory -Path $lnkBackup -Force | Out-Null }
$map = @{}
$map['desktop']   = $Shortcuts[0]
$map['startmenu'] = $Shortcuts[1]
$map['pinned']    = $Shortcuts[2]
foreach ($k in $map.Keys) {
    $src = $map[$k]
    $dst = Join-Path $lnkBackup ("$k.lnk")
    if ((Test-Path -LiteralPath $src) -and -not (Test-Path -LiteralPath $dst)) {
        Copy-Item -LiteralPath $src -Destination $dst -Force
    }
}
Write-Step 'shortcut backups in place'

# ------------------------------------------------------------------ 4. guard
Get-WmiObject Win32_Process -Filter "Name='wscript.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -like '*guard.vbs*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 400

Set-ItemProperty -Path $RunKey -Name $RunName -Value ('wscript.exe //nologo "{0}"' -f (Join-Path $Root 'guard.vbs'))

# Start the guard through WMI so its parent is WmiPrvSE, not this installer:
# that keeps it outside the installer's (and the app's) process tree, so it
# cannot be killed as a child when DeepSeek Harness exits.
$guardCmd = 'wscript.exe //nologo "' + (Join-Path $Root 'guard.vbs') + '"'
$created = $null
try { $created = Invoke-WmiMethod -Class Win32_Process -Name Create -ArgumentList $guardCmd -ErrorAction Stop } catch { }
if (-not $created -or $created.ReturnValue -ne 0) {
    Start-Process -FilePath 'wscript.exe' -ArgumentList ('"{0}"' -f (Join-Path $Root 'guard.vbs')) -WindowStyle Hidden
}
Start-Sleep -Milliseconds 1500
$guard = @(Get-WmiObject Win32_Process -Filter "Name='wscript.exe'" -ErrorAction SilentlyContinue |
           Where-Object { $_.CommandLine -and $_.CommandLine -like '*guard.vbs*' })
if ($guard.Count -gt 0) {
    $parent = Get-WmiObject Win32_Process -Filter ("ProcessId=" + $guard[0].ParentProcessId) -ErrorAction SilentlyContinue
    Write-Step ("guard started (pid " + $guard[0].ProcessId + ", ~" + [math]::Round($guard[0].WorkingSetSize / 1MB, 1) + " MB, parent " + $parent.Name + ")")
} else {
    Write-Step 'WARNING: guard did not start - check diagnose.ps1; logon rotation will retry next sign-in'
}

# --------------------------------------------------------------- 5. first icon
# rotate.ps1 (v6) copies the chosen icon into the install dir - tray.ico for
# the tray, resources\DSH-icon-chain\<name>.ico for the three shortcuts. One
# icon chain, all under the install directory (+ the taskbar pin, a shortcut).
# NOTE: never reuse a name that differs only by case from a parameter above -
# PowerShell is case insensitive and assignment would re-validate the parameter.
$firstIcon = $null
try { $firstIcon = & (Join-Path $Root 'rotate.ps1') -Season $Season } catch { }
if ($firstIcon) {
    Write-Step ("first icon installed: " + $firstIcon)
} else {
    Write-Step 'WARNING: first icon not installed - the guard will rotate on the next exit'
}

Write-Output ''
Write-Output 'DONE.'
Write-Output 'Close DeepSeek Harness completely (tray icon -> Quit), then start it again.'
Write-Output 'From now on every cold start shows a different seasonal icon, and the three'
Write-Output 'shortcuts keep the same icon as the tray.'
Write-Output ''
Write-Output ("State file : " + (Join-Path $Root 'state.json'))
Write-Output ("Logs       : " + (Join-Path $Root 'rotate.log') + " , " + (Join-Path $Root 'guard.log'))
Write-Output ("Rollback   : powershell -NoProfile -ExecutionPolicy Bypass -File """ + (Join-Path $Root 'uninstall.ps1') + """")
