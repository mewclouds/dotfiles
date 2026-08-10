:: These commands only change DC / battery behavior

::Disable CPU Turbo Boost on battery
powercfg /setdcvalueindex SCHEME_BALANCED SUB_PROCESSOR PERFBOOSTMODE 0

::Energy Performance Preference (0% favors performance, 100% favors efficiency)
powercfg /setdcvalueindex SCHEME_BALANCED SUB_PROCESSOR PERFEPP 80

::Sets PCIe Link State Power Management / ASPM to maximum power savings
powercfg /setdcvalueindex SCHEME_BALANCED SUB_PCIEXPRESS ASPM 2
powercfg /setactive SCHEME_BALANCED