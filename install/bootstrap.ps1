<#
    .SYNOPSIS
    Bootstraps the tools required to start the Ruby dotfiles orchestrator.

    .DESCRIPTION
    This script elevates when necessary, ensures PowerShell 7 is available,
    installs the required command-line tools, authenticates GitHub over SSH,
    and clones the public dotfiles repository.

    .PARAMETER RubyOnly
    Skips installation, authentication, cloning, and other machine changes.
    Runs only the Ruby entry point from the existing repository.
#>

[CmdletBinding()]
param(
    [switch]$RubyOnly
)

$ErrorActionPreference = 'Stop'

$repositoryPath = Join-Path $HOME 'dotfiles'

if (-not $RubyOnly) {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    $isAdministrator = $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )

    if (-not $isAdministrator) {
        if (-not $PSCommandPath) {
            throw 'Bootstrap must be run from a saved PowerShell script when elevation is required.'
        }

        Write-Host 'Elevating bootstrap script...'
        $powerShellPath = if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) {
            'pwsh.exe'
        } else {
            'powershell.exe'
        }

        $elevatedProcess = Start-Process $powerShellPath `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
            -Verb RunAs -Wait -PassThru
        exit $elevatedProcess.ExitCode
    }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'winget is required but was not found.'
    }

    # Disable winget telemetry
    $wingetSettingsDirectory = Join-Path $env:LOCALAPPDATA `
        'Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState'
    $wingetSettingsPath = Join-Path $wingetSettingsDirectory 'settings.json'
    if (-not (Test-Path $wingetSettingsDirectory)) {
        New-Item -ItemType Directory -Path $wingetSettingsDirectory -Force | Out-Null
    }

    @'
{
    "telemetry": {
        "disable": true
    }
}
'@ | Set-Content -Path $wingetSettingsPath -Force

    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-Host 'PowerShell 7 is required. Installing it now...' -ForegroundColor Yellow
        & winget install --id Microsoft.PowerShell --exact `
            --accept-package-agreements --accept-source-agreements --silent

        if ($LASTEXITCODE -ne 0) {
            throw "PowerShell 7 installation failed with exit code $LASTEXITCODE."
        }

        Write-Host 'PowerShell 7 was installed. Run this bootstrap again from pwsh.' -ForegroundColor Green
        exit 0
    }

    # Disable PS7 Telemetry
    [Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', '1', 'Machine')


    function Install-WingetPackage {
        <#
        .SYNOPSIS
        Installs one package through WinGet and stops on failure.

        .PARAMETER Id
        The exact WinGet package identifier to install.
    #>
        param(
            [Parameter(Mandatory = $true)]
            [string]$Id
        )

        Write-Host "Installing $Id..." -ForegroundColor Cyan
        & winget install --id $Id --exact `
            --accept-package-agreements --accept-source-agreements --silent

        if ($LASTEXITCODE -ne 0) {
            throw "winget failed to install $Id with exit code $LASTEXITCODE."
        }
    }

    # Requirements in any Windows machine
    Install-WingetPackage -Id 'Git.Git'
    Install-WingetPackage -Id 'GitHub.cli'
    Install-WingetPackage -Id 'Bitwarden.cli'
    Install-WingetPackage -Id 'RubyInstallerTeam.RubyWithDevKit.4.0'
    Install-WingetPackage -Id 'FiloSottile.age'

    # Sync path to access any tools immediately
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machinePath;$userPath"

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'Git was installed but is not available on PATH.'
    }

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw 'GitHub CLI was installed but is not available on PATH.'
    }

    if (-not (Get-Command ruby -ErrorAction SilentlyContinue)) {
        throw 'Ruby was installed but is not available on PATH.'
    }

    $null = gh auth status --hostname github.com 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'GitHub CLI authentication is required.' -ForegroundColor Yellow
        gh auth login --hostname github.com --git-protocol ssh

        if ($LASTEXITCODE -ne 0) {
            throw "GitHub CLI authentication failed with exit code $LASTEXITCODE."
        }
    }

    gh config set telemetry disabled


    if (Test-Path $repositoryPath) {
        Write-Host "Repository already exists at $repositoryPath. Skipping clone." -ForegroundColor Yellow
    } else {
        Write-Host "Cloning repository to $repositoryPath..." -ForegroundColor Cyan
        & gh repo clone mewclouds/dotfiles $repositoryPath

        if ($LASTEXITCODE -ne 0) {
            throw "gh repo clone failed with exit code $LASTEXITCODE."
        }
    }
}

if (-not (Get-Command ruby -ErrorAction SilentlyContinue)) {
    throw 'Ruby is required but was not found on PATH.'
}

$rubyEntrypoint = Join-Path $repositoryPath 'bin\dotfiles'
if (-not (Test-Path $rubyEntrypoint -PathType Leaf)) {
    throw "Ruby entry point was not found at $rubyEntrypoint."
}

Write-Host 'Starting Ruby orchestrator...' -ForegroundColor Cyan
& ruby $rubyEntrypoint status
if ($LASTEXITCODE -ne 0) {
    throw "Ruby orchestrator failed with exit code $LASTEXITCODE."
}

Write-Host 'Bootstrap complete.' -ForegroundColor Green
