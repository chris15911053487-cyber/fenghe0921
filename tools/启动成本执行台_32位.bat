@echo off
chcp 65001 >nul
title FH100 Cost Console (32-bit)
"%SystemRoot%\SysWOW64\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0cost_console.ps1"
if errorlevel 1 pause
