#Requires -RunAsAdministrator

# Dump a backup to the desktop first just in case
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupCsv = "$env:USERPROFILE\Desktop\ServicesBackup-$timestamp.csv"
Get-CimInstance Win32_Service |
    Select-Object Name, DisplayName, State, StartMode, StartName |
    Export-Csv -NoTypeInformation -Path $backupCsv
Write-Host "Backup saved to: $backupCsv" -ForegroundColor Cyan

function Resolve-Service {
    param([string[]]$Patterns)
    $all = Get-CimInstance -ClassName Win32_Service
    $results = foreach ($p in $Patterns) {
        $all | Where-Object { $_.Name -like $p -or $_.DisplayName -like $p }
    }
    $results | Sort-Object Name -Unique
}

function Set-Startup {
    param(
        [object[]]$Services,
        [ValidateSet('Automatic', 'Manual', 'Disabled')]$Mode
    )
    foreach ($s in $Services) {
        try {
            Set-Service -Name $s.Name -StartupType $Mode -ErrorAction Stop
            Write-Host ("      -> {0,-45} [{1}]" -f $s.Name, $Mode) -ForegroundColor Gray
        } catch {
            Write-Host "   [!] Failed to set $($s.Name) to $Mode" -ForegroundColor Yellow
        }
    }
}

function Stop-And-Disable {
    param([object[]]$Services)
    foreach ($s in $Services) {
        try {
            if ($s.State -eq 'Running') {
                Stop-Service -Name $s.Name -Force -ErrorAction SilentlyContinue
            }
            Set-Service -Name $s.Name -StartupType Disabled -ErrorAction Stop
            Write-Host ("      -> {0,-45} [Disabled]" -f $s.Name) -ForegroundColor DarkGray
        } catch {
            Write-Host "   [!] Failed to disable $($s.Name)" -ForegroundColor Yellow
        }
    }
}

# Service Lists

$Telemetry_Disable = @(
    'DiagTrack',
    'dptftcs',
    'wuqisvc',
    'dmwappushservice',
    'ESRV_*QUEENCREEK*',
    'USER_ESRV_*QUEENCREEK*',
    'SystemUsageReport*',
    'InventorySvc'
)

$Lenovo_Disable = @(
    'webthreatdefsvc',
    'webthreatdefusersvc*',
    'LRAvatarService',
    'NahimicService'
)

$Lenovo_Manual = @(
    'Lenovo*Communication*',
    'LnvVCam*',
    'SmartAppearance*',
    'CameraEventService',
    'AISpeechService',
    'UDCService'
)

$Updaters_Manual = @(
    'GoogleUpdaterService*',
    'GoogleUpdaterInternalService*',
    'edgeupdate',
    'edgeupdatem',
    'brave',
    'bravem'
)

$Peripherals_Disable = @(
    'logi_lamparray_service',
    'TobiiALENOVOYXX0',
    'Tobii Service'
)

$WSA_Disable = @(
    'WSAIFabricSvc'
)

$Optional_Manual = @(
    'MapsBroker',
    'WMPNetworkSvc',
    'SharedAccess',
    'lfsvc',
    'PhoneSvc',
    'XblAuthManager',
    'XblGameSave',
    'XboxGipSvc',
    'XboxNetApiSvc',
    'TbtHostControllerService',
    'TbtP2pShortcutService',
    'GameInputSvc',
    'StiSvc',
    'WiaRpc',
    'FDResPub',
    'fdPHost',
    'SSDPSRV',
    'NvBroadcast.ContainerLocalSystem',
    'XTU3SERVICE',
    'DSAService',
    'DSAUpdateService'
)

# Execution

Write-Host "Stripping Telemetry..." -ForegroundColor Magenta
Stop-And-Disable (Resolve-Service $Telemetry_Disable)

Write-Host "Purging Lenovo Bloat..." -ForegroundColor Magenta
Stop-And-Disable (Resolve-Service $Lenovo_Disable)
Set-Startup -Services (Resolve-Service $Lenovo_Manual) -Mode Manual

Write-Host "Shifting Third-Party Updaters to Manual..." -ForegroundColor Magenta
Set-Startup -Services (Resolve-Service $Updaters_Manual) -Mode Manual

Write-Host "Dropping Unused Peripherals..." -ForegroundColor Magenta
Stop-And-Disable (Resolve-Service $Peripherals_Disable)

Write-Host "Dropping WSA Fabric..." -ForegroundColor Magenta
Stop-And-Disable (Resolve-Service $WSA_Disable)

Write-Host "Adjusting Optional Windows Services to Manual..." -ForegroundColor Magenta
Set-Startup -Services (Resolve-Service $Optional_Manual) -Mode Manual

Write-Host "Service optimization complete." -ForegroundColor Green
Write-Host "--------------------------------------------------------" -ForegroundColor Gray
Write-Host "Note: Essential background layers were left untouched." -ForegroundColor Gray
Write-Host "--------------------------------------------------------" -ForegroundColor Gray

$reboot = Read-Host "Reboot now to finalize changes? (y/n)"
if ($reboot -eq 'y') {
    Restart-Computer -Force
}
