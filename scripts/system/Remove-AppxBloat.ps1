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
    $ps5ScriptBlock = {
        $provs = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            Where-Object DisplayName -Like "*$Using:Package*"
        if ($null -ne $provs) {
            foreach ($prov in $provs) {
                Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName `
                    -ErrorAction SilentlyContinue | Out-Null
            }
        }
    }

    powershell.exe -NoProfile -NonInteractive -Command $ps5ScriptBlock
    Write-Host "  Removed provisioned package (if existed)" -ForegroundColor Green
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