@echo off
rem MTC cost console - server mode. Keeps the Python service running (restarts it 10 s after any exit).
rem Output is shown in this window and appended to console\logs\server.log (dev_server.py --log=...).
rem Started at boot (no window) by the scheduled task created with install_service.bat.
chcp 65001 >nul
setlocal
title MTC Cost Console server - closing this window stops the service
set "D=%~dp0console"
if not exist "%D%\dev_server.py" set "D=%~dp0.."
set "PY=python"
if exist "%~dp0python\python.exe" set "PY=%~dp0python\python.exe"
set PYTHONIOENCODING=utf-8
set PYTHONUNBUFFERED=1
set "LOG=%D%\logs\server.log"
if not exist "%D%\logs" mkdir "%D%\logs"
:loop
echo [%date% %time%] starting
echo [%date% %time%] starting >> "%LOG%"
"%PY%" "%D%\dev_server.py" --server "--log=%LOG%"
echo [%date% %time%] exited with code %errorlevel%, restarting in 10 s
echo [%date% %time%] exited with code %errorlevel%, restarting in 10 s >> "%LOG%"
ping -n 11 127.0.0.1 >nul
goto loop
