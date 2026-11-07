@echo off
chcp 65001 >nul
title FH100 Cost Check Server
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0cost_server.ps1"
if errorlevel 1 pause
