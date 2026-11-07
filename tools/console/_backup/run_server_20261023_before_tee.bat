@echo off
rem MTC cost console - server mode. Keeps the Python service running (restarts it 10 s after any exit).
rem Log: console\logs\server.log. Started at boot by the scheduled task created with install_service.bat.
chcp 65001 >nul
setlocal
set "D=%~dp0console"
if not exist "%D%\dev_server.py" set "D=%~dp0.."
set "PY=python"
if exist "%~dp0python\python.exe" set "PY=%~dp0python\python.exe"
set PYTHONIOENCODING=utf-8
set PYTHONUNBUFFERED=1
if not exist "%D%\logs" mkdir "%D%\logs"
:loop
echo [%date% %time%] starting >> "%D%\logs\server.log"
"%PY%" "%D%\dev_server.py" --server >> "%D%\logs\server.log" 2>&1
echo [%date% %time%] exited with code %errorlevel%, restarting in 10 s >> "%D%\logs\server.log"
timeout /t 10 /nobreak >nul
goto loop
