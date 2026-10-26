@echo off
chcp 65001 >nul
echo DeepSeek Harness seasonal icon rotator - installer
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
echo.
echo Exit code: %ERRORLEVEL%
pause
