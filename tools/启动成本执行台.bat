@echo off
chcp 65001 >nul
title FH100 Cost Console
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0cost_console.ps1"
if errorlevel 1 pause
