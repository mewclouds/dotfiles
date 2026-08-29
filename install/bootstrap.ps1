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
$bootstrapScriptUrl = 'https://raw.githubusercontent.com/mewclouds/dotfiles/main/install/bootstrap.ps1'

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
    continue with per-user tools after it returns. Start-Process requires a
    file path to elevate, which does not exist when this script runs through
    `irm | iex`, so that case downloads a temporary copy of itself first.
    #>
    $scriptPath = $PSCommandPath
    if (-not $scriptPath) {
        $scriptPath = Join-Path ([System.IO.Path]::GetTempPath()) 'dotfiles-bootstrap.ps1'
        Invoke-RestMethod -Uri $bootstrapScriptUrl -OutFile $scriptPath
    }

    Write-Host 'Running administrator-required setup...' -ForegroundColor Cyan
    $powerShellPath = if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) {
        'pwsh.exe'
    } else {
        'powershell.exe'
    }
    $quotedScriptPath = '"' + $scriptPath + '"'
    $argumentList = "-NoProfile -ExecutionPolicy Bypass -File $quotedScriptPath -SystemOnly"
    Invoke-ElevatedProcess -FilePath $powerShellPath -ArgumentList $argumentList
}

function Invoke-CheckedCommand {
    <#
    .SYNOPSIS
    Runs a native command and stops on failure.

    .DESCRIPTION
    Native commands report failure through LASTEXITCODE instead of PowerShell
    exceptions, so all bootstrap commands use this helper for consistent
    error handling.

    .PARAMETER Name
    The executable or command name to run.

    .PARAMETER Arguments
    Arguments passed to the command.

    .PARAMETER Description
    Human-readable command description used in failure messages.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [string[]]$Arguments = @(),

        [string]$Description = $Name
    )

    $output = & $Name @Arguments
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        throw "$Description failed with exit code $exitCode."
    }

    $output
}

function Install-BootstrapPackage {
    <#
    .SYNOPSIS
    Installs a package through the selected Windows package manager.

    .DESCRIPTION
    Keeps package-manager-specific arguments in one place while sharing the
    same native-command failure handling for WinGet and Scoop.

    .PARAMETER Manager
    Package manager to use: WinGet or Scoop.

    .PARAMETER Id
    Package identifier understood by the selected manager.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('WinGet', 'Scoop')]
        [string]$Manager,

        [Parameter(Mandatory = $true)]
        [string]$Id
    )

    switch ($Manager) {
        'WinGet' {
            $commandName = 'winget'
            $arguments = @(
                'install', '--id', $Id, '--exact',
                '--accept-package-agreements', '--accept-source-agreements', '--silent'
            )
        }
        'Scoop' {
            $commandName = 'scoop'
            $arguments = @('install', $Id)
        }
    }

    Write-Host "Installing $Id through $Manager..." -ForegroundColor Cyan
    $description = "$Manager installation of $Id"
    Invoke-CheckedCommand -Name $commandName -Arguments $arguments `
        -Description $description | Out-Host
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
        Install-BootstrapPackage -Manager WinGet -Id 'Microsoft.PowerShell'
        Write-Host 'PowerShell 7 was installed. Run this bootstrap again from pwsh.' -ForegroundColor Green
        return $false
    }

    [Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', '1', 'Machine')

    # Requirements needed before the user-level setup can continue.
    Install-BootstrapPackage -Manager WinGet -Id 'GitHub.cli'
    Install-BootstrapPackage -Manager WinGet -Id 'Bitwarden.CLI'
    Install-BootstrapPackage -Manager WinGet -Id 'RubyInstallerTeam.RubyWithDevKit.4.0'
    Install-BootstrapPackage -Manager WinGet -Id 'FiloSottile.age'
    Install-BootstrapPackage -Manager WinGet -Id 'Fastfetch-cli.Fastfetch'
    Install-BootstrapPackage -Manager WinGet -Id 'gerardog.gsudo'

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
    param()

    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-Host 'Installing Scoop for the current user...' -ForegroundColor Cyan
        Invoke-RestMethod -Uri 'https://get.scoop.sh' | Invoke-Expression
    }

    $scoopShims = Join-Path $HOME 'scoop\shims'
    $env:Path = "$scoopShims;$env:Path"

    Install-BootstrapPackage -Manager Scoop -Id 'git'

    $bucketList = Invoke-CheckedCommand -Name 'scoop' -Arguments @('bucket', 'list') `
        -Description 'Scoop bucket list' | Out-String
    if ($bucketList -notmatch '(?m)^\s*extras\s') {
        Invoke-CheckedCommand -Name 'scoop' -Arguments @('bucket', 'add', 'extras') `
            -Description 'Scoop extras bucket setup' | Out-Host
    }

    Install-BootstrapPackage -Manager Scoop -Id 'extras/vcredist2022'
    Install-BootstrapPackage -Manager Scoop -Id 'mise'

    # Scoop prints these as manual follow-up steps after installing git and 7zip; the
    # target registry keys are all under HKEY_CURRENT_USER, so no elevation is needed.
    $gitAppDirectory = Join-Path $HOME 'scoop\apps\git\current'
    $sevenZipAppDirectory = Join-Path $HOME 'scoop\apps\7zip\current'
    Invoke-CheckedCommand -Name 'reg' `
        -Arguments @('import', (Join-Path $gitAppDirectory 'install-associations.reg')) `
        -Description 'Git file association registration' | Out-Null
    Invoke-CheckedCommand -Name 'reg' `
        -Arguments @('import', (Join-Path $gitAppDirectory 'install-context.reg')) `
        -Description 'Git context menu registration' | Out-Null
    Invoke-CheckedCommand -Name 'reg' `
        -Arguments @('import', (Join-Path $sevenZipAppDirectory 'install-context.reg')) `
        -Description '7-Zip context menu registration' | Out-Null
    Invoke-CheckedCommand -Name 'git' -Arguments @('config', '--system', 'credential.helper', 'manager') `
        -Description 'Git system credential helper configuration' | Out-Null

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

Invoke-CheckedCommand -Name 'gh' -Arguments @('config', 'set', 'telemetry', 'disabled') `
    -Description 'GitHub CLI telemetry configuration' | Out-Null

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
