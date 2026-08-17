@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-SunlessSeaCN.ps1" %*
if errorlevel 1 echo 安装失败。
pause
