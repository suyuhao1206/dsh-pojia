@echo off
rem dsh-pojia installer for DeepSeek Harness desktop (no dsh/node/pnpm needed).
rem Double-click this file, or run:  install.cmd -Mode link -DryRun
setlocal
chcp 65001 >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install-desktop.ps1" %*
set "rc=%errorlevel%"
echo.
if /i not "%1"=="-NoPause" pause
exit /b %rc%
