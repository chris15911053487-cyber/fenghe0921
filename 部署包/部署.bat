@echo off
chcp 65001 >nul
title FH100 Cost Deploy
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy.ps1"
if errorlevel 1 pause
