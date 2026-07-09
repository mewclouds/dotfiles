#Requires -RunAsAdministrator

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
    "Microsoft.YourPhone",   # Phone Link
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
    "TobiiAB.TobiiEyeTrackingPortal", # Lenovo Tobii Eye Tracking

    # Xbox removals

    "Microsoft.GamingApp",
    "Microsoft.XboxSpeechToTextOverlay"

)

Write-Host ""
Write-Host "Removing bundled Windows apps..." -ForegroundColor Cyan
Write-Host ""

foreach ($Package in $Packages) {
    Write-Host "[$Package]" -ForegroundColor Yellow

    # Remove installed package(s)
    $pkgs = Get-AppxPackage "*$Package*" -AllUsers -ErrorAction SilentlyContinue
    if ($null -ne $pkgs) {
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

    # DISM cmdlets like Get-AppxProvisionedPackage often fail with "Class not registered" or hang in PowerShell 7.
    # We shell out to Windows PowerShell 5.1 (powershell.exe) to reliably remove the provisioned packages.
    $ps5Command = "
        `$provs = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            Where-Object DisplayName -Like '*$Package*'
        if (`$null -ne `$provs) {
            foreach (`$prov in `$provs) {
                `$n = `$prov.PackageName
                Remove-AppxProvisionedPackage -Online -PackageName `$n -ErrorAction SilentlyContinue | Out-Null
            }
        }
    "

    powershell.exe -NoProfile -NonInteractive -Command $ps5Command
    Write-Host "  Removed provisioned package (if existed)" -ForegroundColor Green
}

Write-Host "`nDone." -ForegroundColor Green