$ErrorActionPreference = 'Stop'

$isAdmin = [bool]([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    Write-Host "Elevating to Administrator..." -ForegroundColor Yellow
    $pwshExe = if ($PSVersionTable.PSVersion.Major -ge 7) { "pwsh.exe" } else { "powershell.exe" }
    Start-Process $pwshExe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs -Wait
    exit
}

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

Clear-Host
$banner = @'
██████╗  ██████╗  ██████╗ ████████╗███████╗████████╗██████╗  █████╗ ██████╗
██╔══██╗██╔═══██╗██╔═══██╗╚══██╔══╝██╔════╝╚══██╔══╝██╔══██╗██╔══██╗██╔══██╗
██████╔╝██║   ██║██║   ██║   ██║   ███████╗   ██║   ██████╔╝███████║██████╔╝
██╔══██╗██║   ██║██║   ██║   ██║   ╚════██║   ██║   ██╔══██╗██╔══██║██╔═══╝
██████╔╝╚██████╔╝╚██████╔╝   ██║   ███████║   ██║   ██║  ██║██║  ██║██║
╚═════╝  ╚═════╝  ╚═════╝    ╚═╝   ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝
'@
Write-Host $banner -ForegroundColor Cyan

# Disable pwsh telemetry
[System.Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', '1', 'Machine')

$corePackages = @(
    "Git.Git",
    "GitHub.cli",
    "7zip.7zip",
    "Bitwarden.cli"
)

Write-Host "`nInstalling core dependencies via winget..." -ForegroundColor Yellow
foreach ($pkg in $corePackages) {
    Write-Host "Installing $pkg..."
    winget install --id $pkg --source winget --accept-package-agreements --accept-source-agreements --silent | Out-Null
}

# Add 7z to path
$sevenZipPath = 'C:\Program Files\7-Zip'
$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
if ($machinePath -notlike "*$sevenZipPath*") {
    [Environment]::SetEnvironmentVariable('Path', $machinePath + ';' + $sevenZipPath, 'Machine')
    Write-Host "Added $sevenZipPath to Machine PATH" -ForegroundColor Green
}

# Refresh environment variables so git, gh, bw are available
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
[System.Environment]::GetEnvironmentVariable("Path", "User")

Write-Host "`nAuthenticating..." -ForegroundColor Yellow

# Bitwarden
$bwSession = [Environment]::GetEnvironmentVariable("BW_SESSION", "User")
if (-not $bwSession -or -not (bw status | Select-String "unlocked" -Quiet)) {
    Write-Host "Please login to Bitwarden:" -ForegroundColor Cyan
    bw login
    $bwSession = bw unlock --raw
    [Environment]::SetEnvironmentVariable("BW_SESSION", $bwSession, "User")
    [Environment]::SetEnvironmentVariable("BW_SESSION", $bwSession, "Process")
    Write-Host "Bitwarden unlocked." -ForegroundColor Green
} else {
    Write-Host "Bitwarden already unlocked." -ForegroundColor DarkGray
}

# GitHub
if (-not (gh auth status 2>&1 | Select-String "Logged in" -Quiet)) {
    Write-Host "`nPlease authenticate with GitHub CLI (this will generate an SSH key):" -ForegroundColor Cyan
    gh auth login
} else {
    Write-Host "`nGitHub already authenticated." -ForegroundColor DarkGray
}

Write-Host "`nCloning dotfiles repository..." -ForegroundColor Yellow
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

Start-Process pwsh.exe `
    -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$setupScript`" -Clean" `
    -Verb RunAs -Wait
