if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "PowerShell 7 or later is required. Please run this with pwsh."
}

Add-Type -AssemblyName System.Windows.Forms

function Get-FolderSelection {
    param(
        [string]$VarName,
        [string]$Prompt
    )

    $current = [Environment]::GetEnvironmentVariable($VarName, 'User')
    if ($current) {
        Write-Host "$VarName is currently set to: $current" -ForegroundColor Cyan
        $reply = Read-Host "Change this path? (y/N)"
        if ($reply -ne 'y') { return }
    }

    Write-Host "`n$Prompt" -ForegroundColor Yellow
    $browser = New-Object System.Windows.Forms.FolderBrowserDialog
    $browser.Description = $Prompt
    $browser.ShowNewFolderButton = $true

    if ($browser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        [Environment]::SetEnvironmentVariable($VarName, $browser.SelectedPath, 'User')
        Write-Host "Set $VarName to $($browser.SelectedPath)" -ForegroundColor Green
    } else {
        Write-Host "Skipped $VarName" -ForegroundColor DarkYellow
    }
}

function Get-FileSelection {
    param(
        [string]$VarName,
        [string]$Prompt,
        [string]$Filter = 'All Files (*.*)|*.*'
    )

    $current = [Environment]::GetEnvironmentVariable($VarName, 'User')
    if ($current) {
        Write-Host "$VarName is currently set to: $current" -ForegroundColor Cyan
        $reply = Read-Host "Change this path? (y/N)"
        if ($reply -ne 'y') { return }
    }

    Write-Host "`n$Prompt" -ForegroundColor Yellow
    $browser = New-Object System.Windows.Forms.OpenFileDialog
    $browser.Title = $Prompt
    $browser.Filter = $Filter

    if ($browser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        [Environment]::SetEnvironmentVariable($VarName, $browser.FileName, 'User')
        Write-Host "Set $VarName to $($browser.FileName)" -ForegroundColor Green
    } else {
        Write-Host "Skipped $VarName" -ForegroundColor DarkYellow
    }
}

Write-Host "Configuring dotfiles environment variables..." -ForegroundColor Cyan

# Automatically set UTILITIES_PATH relative to where we're running
$utilitiesPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\shell\TerminalUtilities.ps1'
if (Test-Path $utilitiesPath) {
    [Environment]::SetEnvironmentVariable('UTILITIES_PATH', $utilitiesPath, 'User')
    Write-Host "Set UTILITIES_PATH to $utilitiesPath" -ForegroundColor Green
} else {
    Write-Host "Warning: Could not find TerminalUtilities.ps1 at $utilitiesPath" -ForegroundColor Yellow
}

# Auto-detect Windows Terminal JSON path
$defaultWtJson = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
$currentWtJson = [Environment]::GetEnvironmentVariable('WT_JSON', 'User')

if (-not $currentWtJson -and (Test-Path $defaultWtJson)) {
    [Environment]::SetEnvironmentVariable('WT_JSON', $defaultWtJson, 'User')
    Write-Host "Set WT_JSON to $defaultWtJson (auto-detected)" -ForegroundColor Green
} else {
    Get-FileSelection -VarName 'WT_JSON' `
        -Prompt 'Select your Windows Terminal settings.json' `
        -Filter 'JSON Files (*.json)|*.json'
}
Get-FolderSelection -VarName 'MR_MODS_PATH' -Prompt 'Select your MR Mods directory'
Get-FolderSelection -VarName 'MR_MODS_BACKUP' -Prompt 'Select your MR Mods backup directory'

Write-Host "`nConfiguration state:" -ForegroundColor Cyan
$vars = @('UTILITIES_PATH', 'WT_JSON', 'MR_MODS_PATH', 'MR_MODS_BACKUP')
$allGood = $true

foreach ($v in $vars) {
    $val = [Environment]::GetEnvironmentVariable($v, 'User')
    if ($val) {
        Write-Host "  $v = $val"
    } else {
        Write-Host "  $v = NOT SET" -ForegroundColor Red
        $allGood = $false
    }
}

if ($allGood) {
    Write-Host "`nReady to run setup.ps1." -ForegroundColor Green
} else {
    Write-Host "`nMissing environment variables. Please configure all variables before running setup.ps1." `
        -ForegroundColor Yellow
}
