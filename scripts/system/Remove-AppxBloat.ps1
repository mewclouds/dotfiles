#Requires -RunAsAdministrator

if ($PSVersionTable.PSVersion.Major -ne 5) {
    throw "This script must be run in Windows PowerShell (v5.1) because DISM APIs " +
    "(like Get-AppxProvisionedPackage) fail with 'Class not registered' in PowerShell 7+."
}

$Packages = @(

    "Microsoft.WindowsFeedbackHub",
    "Microsoft.GetHelp",
    "Microsoft.OutlookForWindows",
    "MSTeams",
    "Clipchamp.Clipchamp",
    "Microsoft.MicrosoftOfficeHub",

    "Microsoft.ZuneMusic",   # Media Player

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

    # Xbox removals

    "Microsoft.GamingApp",
    "Microsoft.XboxSpeechToTextOverlay"

)

Write-Host ""
Write-Host "Removing bundled Windows apps..." -ForegroundColor Cyan
Write-Host ""

# Cache package lists once
$Installed = Get-AppxPackage
$Provisioned = Get-AppxProvisionedPackage -Online

foreach ($Package in $Packages) {
    Write-Host "[$Package]" -ForegroundColor Yellow

    # Remove installed package(s)
    $Apps = $Installed | Where-Object Name -EQ $Package

    if ($Apps) {
        foreach ($App in $Apps) {
            try {
                Remove-AppxPackage `
                    -Package $App.PackageFullName `
                    -ErrorAction Stop

                Write-Host "  Removed user package" -ForegroundColor Green
            } catch {
                Write-Host "  Skipped ($($_.Exception.Message))" -ForegroundColor DarkYellow
            }
        }
    } else {
        Write-Host "  Not installed"
    }

    # Remove provisioned package(s)
    $Prov = $Provisioned |
        Where-Object DisplayName -EQ $Package

    if ($Prov) {
        foreach ($P in $Prov) {
            try {
                Remove-AppxProvisionedPackage `
                    -Online `
                    -PackageName $P.PackageName `
                    -ErrorAction Stop | Out-Null

                Write-Host "  Removed provisioned package" -ForegroundColor Green
            } catch {
                Write-Host "  Provisioned package skipped" -ForegroundColor DarkYellow
            }
        }
    }
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host ""
Write-Host "Kept:" -ForegroundColor Cyan
Write-Host "  Xbox Game Bar"
Write-Host "  XboxIdentityProvider"
Write-Host "  Xbox.TCUI"
Write-Host "  Calculator"
Write-Host "  Photos"
Write-Host "  Paint"
Write-Host "  Notepad"
Write-Host "  Snipping Tool"
Write-Host "  Camera"
Write-Host "  Clock"
Write-Host "  Media Player"
Write-Host "  Store"
Write-Host "  Edge"
Write-Host "  Defender"
Write-Host "  Windows Update"