# diagnose.ps1 - one-shot status report for the DSH seasonal icon rotator.
# Run it on the machine that shows the problem and paste the output back.
# Read-only: it never changes icons or settings.

$ErrorActionPreference = 'SilentlyContinue'
$Root = Join-Path $env:LOCALAPPDATA 'DSH-icon-rotator'

function Section($t) { Write-Output ""; Write-Output ("== " + $t + " ==") }

Write-Output ("time            : " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Write-Output ("windows         : " + (Get-CimInstance Win32_OperatingSystem).Caption)
Write-Output ("powershell      : " + $PSVersionTable.PSVersion)

Section 'install path'
$marker = Join-Path $Root 'install-path.txt'
if (Test-Path $marker) { Write-Output ("recorded        : " + (Get-Content $marker -Raw).Trim()) } else { Write-Output 'recorded        : (missing)' }
$detected = $null
foreach ($c in @((Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness'),
                 (Join-Path $env:ProgramFiles 'DeepSeek Harness'))) {
    if ($c -and (Test-Path (Join-Path $c 'DeepSeek Harness.exe'))) { $detected = $c; break }
}
Write-Output ("detected        : " + $(if ($detected) { $detected } else { '(not found)' }))
$tray = if ($detected) { Join-Path $detected 'resources\tray.ico' } else { $null }
if ($tray -and (Test-Path $tray)) {
    $size = (Get-Item $tray).Length
    $name = 'unknown'
    try {
        $sha = (Get-FileHash -LiteralPath $tray -Algorithm SHA256).Hash
        foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $Root 'icons') -Filter *.ico -ErrorAction SilentlyContinue)) {
            if ((Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash -eq $sha) { $name = $f.BaseName; break }
        }
    } catch { }
    Write-Output ("tray.ico        : " + $size + " bytes -> " + $name)
} else {
    Write-Output 'tray.ico        : NOT FOUND'
}

Section 'autostart'
$run = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'DSH-icon-rotator').'DSH-icon-rotator'
Write-Output ("HKCU Run        : " + $(if ($run) { $run } else { '(missing)' }))

Section 'guard process'
$guards = @(Get-CimInstance Win32_Process -Filter "Name='wscript.exe'" | Where-Object { $_.CommandLine -like '*guard.vbs*' })
if ($guards.Count -eq 0) {
    Write-Output 'state           : NOT RUNNING  <-- this is why the icon never changes'
} else {
    foreach ($g in $guards) {
        $parent = Get-CimInstance Win32_Process -Filter ("ProcessId=" + $g.ParentProcessId)
        Write-Output ("pid             : " + $g.ProcessId)
        Write-Output ("started         : " + $g.CreationDate)
        Write-Output ("parent          : " + $parent.Name + " (pid " + $g.ParentProcessId + ")")
        Write-Output ("memory          : " + [math]::Round($g.WorkingSetSize / 1MB, 1) + " MB")
    }
}

Section 'shortcuts'
$ws = New-Object -ComObject WScript.Shell
$resources = if ($detected) { Join-Path $detected 'resources' } else { $null }
if ($resources) { Write-Output ("  expected under: " + $resources) }
foreach ($p in @(
        (Join-Path $env:USERPROFILE 'Desktop\DeepSeek Harness.lnk'),
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\DeepSeek Harness.lnk'),
        (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\DeepSeek Harness.lnk'))) {
    $label = Split-Path (Split-Path $p -Parent) -Leaf
    if (Test-Path $p) {
        $l = $ws.CreateShortcut($p)
        Write-Output ("  target : " + $l.TargetPath)
        Write-Output ("  icon   : " + $l.IconLocation)
        if ($resources) {
            $iconOnly = ($l.IconLocation -split ',')[0]
            $inInstall = $iconOnly.StartsWith($resources, [System.StringComparison]::OrdinalIgnoreCase)
            Write-Output ("  chain  : " + $(if ($inInstall) { 'OK (install dir)' } else { 'MISMATCH - expected a file under ' + $resources }))
        }
    } else {
        Write-Output ("  missing: " + $p)
    }
}

Section 'guard.log (tail)'
$gl = Join-Path $Root 'guard.log'
if (Test-Path $gl) { Get-Content $gl -Tail 15 } else { Write-Output '(missing)' }

Section 'rotate.log (tail)'
$rl = Join-Path $Root 'rotate.log'
if (Test-Path $rl) { Get-Content $rl -Tail 8 } else { Write-Output '(missing)' }

Section 'state.json'
$st = Join-Path $Root 'state.json'
if (Test-Path $st) { Get-Content $st -Raw } else { Write-Output '(missing)' }

Section 'running DeepSeek Harness processes'
Get-CimInstance Win32_Process -Filter "Name='DeepSeek Harness.exe'" |
    Select-Object ProcessId, CreationDate | Format-Table -AutoSize | Out-String
