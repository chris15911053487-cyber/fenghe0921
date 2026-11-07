@echo off
rem Run as administrator: restarts the cost console server task (after updating dev_server.py, server.json etc.).
chcp 65001 >nul
net session >nul 2>&1 || (echo Please right-click this file and choose "Run as administrator". & pause & exit /b 1)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0restart_service.ps1"
pause
