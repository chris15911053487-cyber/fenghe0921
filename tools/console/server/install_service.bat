@echo off
rem Run as administrator: registers the boot-time task and the firewall rule for the cost console server.
chcp 65001 >nul
net session >nul 2>&1 || (echo Please right-click this file and choose "Run as administrator". & pause & exit /b 1)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_service.ps1"
pause
