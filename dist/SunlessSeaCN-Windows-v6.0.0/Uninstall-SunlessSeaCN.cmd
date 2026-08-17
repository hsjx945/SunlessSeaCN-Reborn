@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall-SunlessSeaCN.ps1" %*
if errorlevel 1 echo 卸载失败。
pause
