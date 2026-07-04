::
:: Switching from iGPU to dGPU mode doesn't take into account the refresh rate
:: and other display settings (Windows 11 twirks), so I have decided to automate the process.
::
:: This is triggered when my laptop is unplugged/plugged in
::
:: Usage: SetRes.bat [quiet|normal] (defaults to Normal)
::

@echo off
setlocal EnableExtensions
set "LOGDIR=%USERPROFILE%\runs\logs"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"
set "LOG=%LOGDIR%\set-display.log"
set "MODE=%~1"

if /I "%MODE%"=="" set "MODE=normal"
if /I "%MODE%"=="/?" goto :usage
if /I "%MODE%"=="-?" goto :usage
if /I "%MODE%"=="/h" goto :usage
if /I "%MODE%"=="/help" goto :usage
if /I not "%MODE%"=="quiet" if /I not "%MODE%"=="normal" goto :usage

if /I "%MODE%"=="quiet" (
  set "MODE_LABEL=Quiet"
  set "REFRESH=60"
) else (
  set "MODE_LABEL=Normal"
  set "REFRESH=240"
)

echo [%date% %time%] Start %MODE_LABEL% >> "%LOG%"

:: LogPixels = 144 (0x90)
reg query "HKCU\Control Panel\Desktop" /v LogPixels 2>nul | findstr /i "0x90" >nul
if errorlevel 1 (
  echo [%date% %time%] Setting LogPixels=144 >> "%LOG%"
  reg add "HKCU\Control Panel\Desktop" /v LogPixels /t REG_DWORD /d 144 /f >> "%LOG%" 2>&1
) else (
  echo [%date% %time%] LogPixels already 144 >> "%LOG%"
)

:: Win8DpiScaling = 1 (0x1)
reg query "HKCU\Control Panel\Desktop" /v Win8DpiScaling 2>nul | findstr /i "0x1" >nul
if errorlevel 1 (
  echo [%date% %time%] Setting Win8DpiScaling=1 >> "%LOG%"
  reg add "HKCU\Control Panel\Desktop" /v Win8DpiScaling /t REG_DWORD /d 1 /f >> "%LOG%" 2>&1
) else (
  echo [%date% %time%] Win8DpiScaling already 1 >> "%LOG%"
)

:: run nircmd (in PATH)
C:\nircmd\nircmd.exe setdisplay 2560 1600 32 %REFRESH% -updatereg >> "%LOG%" 2>&1

if errorlevel 1 (
  echo [%date% %time%] nircmd failed >> "%LOG%"
) else (
  echo [%date% %time%] nircmd success >> "%LOG%"
)

endlocal
exit /b 0

:usage
echo Usage: %~nx0 [quiet^|normal] (defaults to normal when none given)
echo.
echo   quiet   Set the display to 60 Hz
echo   normal  Set the display to 240 Hz
exit /b 1
