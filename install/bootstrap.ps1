[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$wingetSettingsDir = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState'
if (-not (Test-Path $wingetSettingsDir)) {
    New-Item -ItemType Directory -Path $wingetSettingsDir -Force | Out-Null
}
$wingetSettingsJson = Join-Path $wingetSettingsDir 'settings.json'
'{
    "telemetry": {
        "disable": true
    }
}' | Set-Content -Path $wingetSettingsJson -Force

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "Installing PowerShell 7..." -ForegroundColor Cyan
    winget install --id Microsoft.PowerShell --source winget `
        --accept-package-agreements --accept-source-agreements --silent
    Write-Host "`nPowerShell 7 installed. Please restart your terminal and run this script again." `
        -ForegroundColor Yellow
    exit
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "        Dotfiles Bootstrap (Phase 1)      " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

$corePackages = @(
    "Git.Git",
    "GitHub.cli",
    "7zip.7zip",
    "Bitwarden.cli"
)

Write-Host "`n[1/3] Installing core dependencies via winget..." -ForegroundColor Yellow
foreach ($pkg in $corePackages) {
    Write-Host "Installing $pkg..."
    winget install --id $pkg --source winget --accept-package-agreements --accept-source-agreements --silent | Out-Null
}

# Refresh environment variables so git, gh, bw are available
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
[System.Environment]::GetEnvironmentVariable("Path", "User")

Write-Host "`n[2/3] Authenticating..." -ForegroundColor Yellow

# Bitwarden
Write-Host "Please login to Bitwarden:" -ForegroundColor Cyan
bw login
$bwSession = bw unlock --raw
[Environment]::SetEnvironmentVariable("BW_SESSION", $bwSession, "User")
[Environment]::SetEnvironmentVariable("BW_SESSION", $bwSession, "Process")
Write-Host "Bitwarden unlocked." -ForegroundColor Green

# GitHub
gh config set telemetry disabled
Write-Host "`nPlease authenticate with GitHub CLI (this will generate an SSH key):" -ForegroundColor Cyan
gh auth login

Write-Host "`n[3/3] Cloning dotfiles repository..." -ForegroundColor Yellow
$repoUrl = "git@github.com:mewclouds/dotfiles.git"
$destPath = Join-Path $HOME "dotfiles"

if (Test-Path $destPath) {
    Write-Host "Repository already exists at $destPath. Skipping clone." -ForegroundColor DarkGray
} else {
    git clone $repoUrl $destPath
}

Write-Host "`nBootstrap complete! Ready for Phase 2." -ForegroundColor Green
Write-Host "Elevating privileges to run setup.ps1..." -ForegroundColor Cyan

$setupScript = Join-Path $destPath "install\setup.ps1"
Start-Process pwsh -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$setupScript`"" -Verb RunAs -Wait
