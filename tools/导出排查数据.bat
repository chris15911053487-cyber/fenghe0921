@echo off
chcp 65001 >nul
title FH100 Export
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0export_masked.ps1"
if errorlevel 1 pause
