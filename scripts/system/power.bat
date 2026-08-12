@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "PLAN_NAME=Laptop Efficient AC"

:: Reuse the plan if it already exists
for /f "tokens=4" %%G in ('powercfg /list ^| findstr /I /C:"%PLAN_NAME%"') do (
    set "GUID=%%G"
)

:: Otherwise create it from Balanced
if not defined GUID (
    for /f "tokens=4" %%G in ('powercfg /duplicatescheme SCHEME_BALANCED') do (
        set "GUID=%%G"
    )

    powercfg /changename !GUID! "%PLAN_NAME%" "Lower-power AC profile for laptops"
)

:: Let the CPU clock down properly when idle
powercfg /setacvalueindex !GUID! SUB_PROCESSOR PROCTHROTTLEMIN 5

:: Keep full processor state available when it actually needs it
powercfg /setacvalueindex !GUID! SUB_PROCESSOR PROCTHROTTLEMAX 100

:: Allow boost, but use the efficiency-focused boost policy
powercfg /setacvalueindex !GUID! SUB_PROCESSOR PERFBOOSTMODE 3

:: Prefer efficiency without being as aggressive as battery mode
powercfg /setacvalueindex !GUID! SUB_PROCESSOR PERFEPP 60

:: Use maximum PCIe link power savings
powercfg /setacvalueindex !GUID! SUB_PCIEXPRESS ASPM 2