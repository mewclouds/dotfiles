@echo off
setlocal

pushd "%~dp0"
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\PSFormat.ps1" -Check %*
if errorlevel 1 (
    set "exitCode=%ERRORLEVEL%"
    popd
    exit /b %exitCode%
)

pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\PSLint.ps1" %*
set "exitCode=%ERRORLEVEL%"
popd

exit /b %exitCode%
