@echo off
setlocal
cd /d "%~dp0"

set "PYTHON_BIN=%~dp0backend\.venv\Scripts\python.exe"
if exist "%PYTHON_BIN%" goto :run

for /f "delims=" %%I in ('where python 2^>nul') do (
  set "PYTHON_BIN=%%I"
  goto :run
)

echo Python nao encontrado. Instale Python 3 ou execute scripts\start_demo.ps1.
pause
exit /b 1

:run
"%PYTHON_BIN%" "%~dp0scripts\pc_web_demo.py" %*
if errorlevel 1 (
  echo.
  echo Ocorreu um erro ao iniciar o GranMap no PC.
  pause
  exit /b 1
)
