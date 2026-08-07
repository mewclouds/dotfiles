<#
    .SYNOPSIS
    Bootstraps the tools required to start the Ruby dotfiles orchestrator.

    .DESCRIPTION
    Runs administrator-required setup in a separate elevated process, then
    installs user-level tools through Scoop and clones the dotfiles repository.

    .PARAMETER SystemOnly
    Runs only administrator-required setup. This is used internally by the
    non-elevated bootstrap process.
#>

[CmdletBinding()]
param(
    [switch]$SystemOnly
)

$ErrorActionPreference = 'Stop'
$repositoryPath = Join-Path $HOME 'dotfiles'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-ElevatedProcess {
    <#
    .SYNOPSIS
    Runs a process with administrator privileges and waits for completion.

    .DESCRIPTION
    Centralizes UAC process handling so elevated setup and future elevated Ruby
    operations use the same exit-code and working-directory behavior.

    .PARAMETER FilePath
    The executable to run with administrator privileges.

    .PARAMETER ArgumentList
    The arguments passed to the elevated process as one command-line string.

    .PARAMETER WorkingDirectory
    The directory from which the elevated process should run.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string]$ArgumentList,

        [string]$WorkingDirectory
    )

    $startParameters = @{
        FilePath = $FilePath
        ArgumentList = $ArgumentList
        Verb = 'RunAs'
        Wait = $true
        PassThru = $true
    }

    if ($WorkingDirectory) {
        $startParameters.WorkingDirectory = $WorkingDirectory
    }

    $elevatedProcess = Start-Process @startParameters

    if ($elevatedProcess.ExitCode -ne 0) {
        throw "Elevated process failed with exit code $($elevatedProcess.ExitCode)."
    }
}

function Invoke-SystemBootstrap {
    <#
    .SYNOPSIS
    Starts the administrator-required bootstrap phase.

    .DESCRIPTION
    The elevated child performs only system setup so the parent process can
    continue with per-user tools after it returns.
    #>
    if (-not $PSCommandPath) {
        throw 'Bootstrap must be run from a saved PowerShell script when elevation is required.'
    }

    Write-Host 'Running administrator-required setup...' -ForegroundColor Cyan
    $powerShellPath = if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) {
        'pwsh.exe'
    } else {
        'powershell.exe'
    }
    $quotedScriptPath = '"' + $PSCommandPath + '"'
    $argumentList = "-NoProfile -ExecutionPolicy Bypass -File $quotedScriptPath -SystemOnly"
    Invoke-ElevatedProcess -FilePath $powerShellPath -ArgumentList $argumentList
}

function Install-WingetPackage {
    <#
    .SYNOPSIS
    Installs one package through WinGet and stops on failure.

    .PARAMETER Id
    The exact WinGet package identifier to install.

    .DESCRIPTION
    Centralizes WinGet installation and failure handling so every required
    system package behaves consistently during bootstrap.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id
    )

    Write-Host "Installing $Id..." -ForegroundColor Cyan
    & winget install --id $Id --exact --accept-package-agreements --accept-source-agreements --silent

    if ($LASTEXITCODE -ne 0) {
        throw "winget failed to install $Id with exit code $LASTEXITCODE."
    }
}

function Invoke-SystemOnlySetup {
    <#
    .SYNOPSIS
    Installs prerequisites that require administrator privileges.

    .DESCRIPTION
    This phase is isolated because the normal bootstrap process must remain
    non-elevated for per-user package managers such as Scoop.
    #>
    if (-not (Test-IsAdministrator)) {
        throw 'SystemOnly setup must run in an elevated PowerShell process.'
    }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'winget is required but was not found.'
    }

    # Disable winget telemetry.
    $wingetPackagePath = 'Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState'
    $wingetSettingsDirectory = Join-Path $env:LOCALAPPDATA $wingetPackagePath
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
        Install-WingetPackage -Id 'Microsoft.PowerShell'
        Write-Host 'PowerShell 7 was installed. Run this bootstrap again from pwsh.' -ForegroundColor Green
        return $false
    }

    [Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', '1', 'Machine')

    # Requirements needed before the user-level setup can continue.
    Install-WingetPackage -Id 'GitHub.cli'
    Install-WingetPackage -Id 'Bitwarden.cli'
    Install-WingetPackage -Id 'RubyInstallerTeam.RubyWithDevKit.4.0'
    Install-WingetPackage -Id 'FiloSottile.age'

    return $true
}

function Install-ScoopTooling {
    <#
    .SYNOPSIS
    Installs the user-level tools required by the bootstrap.

    .DESCRIPTION
    Scoop is intentionally run in the original non-elevated process so its
    shims, applications, and PATH changes belong to the current user.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingPositionalParameters',
        '',
        Justification = 'Scoop uses positional subcommands and package names by design.'
    )]
    param()

    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-Host 'Installing Scoop for the current user...' -ForegroundColor Cyan
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        Invoke-RestMethod -Uri 'https://get.scoop.sh' | Invoke-Expression
    }

    $scoopShims = Join-Path $HOME 'scoop\shims'
    $env:Path = "$scoopShims;$env:Path"

    Write-Host 'Installing Git through Scoop...' -ForegroundColor Cyan
    scoop install git

    $bucketList = scoop bucket list | Out-String
    if ($bucketList -notmatch '(?m)^\s*extras\s') {
        scoop bucket add extras
    }

    Write-Host 'Installing Visual C++ runtime...' -ForegroundColor Cyan
    scoop install extras/vcredist2022

    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$scoopShims;$machinePath;$userPath"
}

if ($SystemOnly) {
    Invoke-SystemOnlySetup | Out-Null
    exit 0
}

if (Test-IsAdministrator) {
    throw 'Run bootstrap from a non-elevated PowerShell session so user-level tools install for your account.'
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Invoke-SystemBootstrap
    Write-Host 'PowerShell 7 was installed. Run this bootstrap again from pwsh.' -ForegroundColor Green
    exit 0
}

Invoke-SystemBootstrap
Install-ScoopTooling

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git was installed through Scoop but is not available on PATH.'
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
