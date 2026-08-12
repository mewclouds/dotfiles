@echo off

:: Use efficient boost on battery so apps can still burst when needed
powercfg /setdcvalueindex SCHEME_BALANCED SUB_PROCESSOR PERFBOOSTMODE 3

:: Prefer efficiency pretty heavily on battery
powercfg /setdcvalueindex SCHEME_BALANCED SUB_PROCESSOR PERFEPP 80

:: Let the CPU clock down properly when idle
powercfg /setdcvalueindex SCHEME_BALANCED SUB_PROCESSOR PROCTHROTTLEMIN 5

:: Don't artificially cap the maximum processor state
powercfg /setdcvalueindex SCHEME_BALANCED SUB_PROCESSOR PROCTHROTTLEMAX 100

:: Use maximum PCIe power savings
powercfg /setdcvalueindex SCHEME_BALANCED SUB_PCIEXPRESS ASPM 2
powercfg /setactive SCHEME_BALANCED