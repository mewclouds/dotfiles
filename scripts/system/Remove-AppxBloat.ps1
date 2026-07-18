<#
    This script forces execution under Windows PowerShell 5.1.

    Many Windows AppX management cmdlets - including:
        - Get-AppxPackage
        - Remove-AppxPackage
        - Get-AppxProvisionedPackage
        - Remove-AppxProvisionedPackage

    rely on COM-based Windows APIs that exist only in the full .NET Framework.

    PowerShell 7 runs on .NET Core, which does NOT include the AppX deployment
    COM interfaces. As a result, PowerShell 7 can list AppX packages but cannot
    reliably remove them. Attempts to uninstall built-in or provisioned packages
    from PowerShell 7 typically fail with errors such as:

        "Access is denied."
        "Class not registered."
        or silent no-op failures.

    To ensure consistent and reliable removal of both user-installed and
    provisioned AppX packages, this script automatically relaunches itself
    under Windows PowerShell 5.1 when executed from PowerShell 7 or later.
#>


#Requires -RunAsAdministrator

if ($PSVersionTable.PSVersion.Major -ne 5) {
    Write-Host "This script must run in Windows PowerShell 5.1. Relaunching..." -ForegroundColor Yellow

    $scriptPath = $MyInvocation.MyCommand.Path

    # Relaunch in Windows PowerShell 5.1
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath
    exit
}

$Packages = @(
    "Microsoft.WindowsFeedbackHub",
    "Microsoft.GetHelp",
    "Microsoft.OutlookForWindows",
    "MSTeams",
    "Clipchamp.Clipchamp",
    "Microsoft.MicrosoftOfficeHub",
    "Microsoft.ZuneMusic",
    "Microsoft.BingSearch",
    "MicrosoftCorporationII.QuickAssist",
    "Microsoft.Windows.DevHome",
    "Microsoft.Todos",
    "Microsoft.PowerAutomateDesktop",
    "Microsoft.YourPhone",
    "Microsoft.MicrosoftStickyNotes",
    "Microsoft.WindowsSoundRecorder",
    "Microsoft.Copilot",
    "Microsoft.BingNews",
    "Microsoft.BingWeather",
    "Microsoft.StartExperiencesApp",
    "Microsoft.MicrosoftSolitaireCollection",
    "MicrosoftCorporationII.MicrosoftFamily",
    "MicrosoftWindows.CrossDevice",
    # Lenovo / OEM removals
    "TobiiAB.TobiiEyeTrackingPortal",
    # Xbox removals
    "Microsoft.GamingApp",
    "Microsoft.XboxSpeechToTextOverlay"
)

Write-Host ""
Write-Host "Removing provisioned Windows apps..." -ForegroundColor Cyan
Write-Host ""

foreach ($Package in $Packages) {
    $provs = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object DisplayName -Like "*$Package*"

    if ($provs) {
        foreach ($prov in $provs) {
            Remove-AppxProvisionedPackage -Online `
                -PackageName $prov.PackageName `
                -ErrorAction SilentlyContinue | Out-Null
        }
    }
}

Write-Host "  Finished checking and removing provisioned packages." -ForegroundColor Green

Write-Host "`nRemoving user packages..." -ForegroundColor Cyan
foreach ($Package in $Packages) {
    Write-Host "[$Package]" -ForegroundColor Yellow

    $pkgs = Get-AppxPackage "*$Package*" -AllUsers -ErrorAction SilentlyContinue

    if ($pkgs) {
        foreach ($pkg in $pkgs) {
            try {
                Remove-AppxPackage -AllUsers -Package $pkg.PackageFullName -ErrorAction Stop
                Write-Host "  Removed user package" -ForegroundColor Green
            } catch {
                Write-Host "  Skipped ($($_.Exception.Message))" -ForegroundColor DarkYellow
            }
        }
    } else {
        Write-Host "  Not installed"
    }
}

Write-Host "`nDone." -ForegroundColor Green

