@echo off
chcp 65001 >nul
title FH100 Export 140801
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0export_ww140801.ps1"
if errorlevel 1 pause
