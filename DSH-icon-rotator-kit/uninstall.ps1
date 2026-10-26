<#
    uninstall.ps1 - remove the rotator from this PC:
      * stop the guard and delete the logon entry
      * restore the original tray icon
      * restore the three shortcut icons

    The folder %LOCALAPPDATA%\DSH-icon-rotator is kept (logs/backup); delete it
    manually for a clean removal.
#>
$ErrorActionPreference = 'Stop'

$Root   = Join-Path $env:LOCALAPPDATA 'DSH-icon-rotator'
$RunKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$RunName = 'DSH-icon-rotator'

Remove-ItemProperty -Path $RunKey -Name $RunName -ErrorAction SilentlyContinue
Get-WmiObject Win32_Process -Filter "Name='wscript.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -like '*guard.vbs*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Write-Output 'guard stopped, logon entry removed'

if (Test-Path -LiteralPath (Join-Path $Root 'rotate.ps1')) {
    & (Join-Path $Root 'rotate.ps1') -Season restore -Quiet
    Write-Output 'tray icon and shortcut icons restored'
} else {
    Write-Output 'nothing to restore (rotator files not found)'
}

$state = Join-Path $Root 'state.json'
if (Test-Path -LiteralPath $state) { Get-Content -LiteralPath $state -Encoding UTF8 }
