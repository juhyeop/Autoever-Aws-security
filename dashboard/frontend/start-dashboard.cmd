@echo off
setlocal
set "PYTHON_RUNTIME=%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
if exist "%PYTHON_RUNTIME%" (
  "%PYTHON_RUNTIME%" "%~dp0run.py" %*
) else (
  python "%~dp0run.py" %*
)
