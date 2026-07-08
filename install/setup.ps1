[CmdletBinding()]
param(
    [switch]$Clean
)

$requiredPowerShellMajorVersion = 7
if ($PSVersionTable.PSVersion.Major -lt $requiredPowerShellMajorVersion) {
    throw "PowerShell $requiredPowerShellMajorVersion or later is required. " +
    "Run this script with pwsh 7+ instead of Windows PowerShell."
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]$identity
$adminRole = [Security.Principal.WindowsBuiltInRole]::Administrator

if (-not $principal.IsInRole($adminRole)) {
    throw "Elevated privileges required. Please run this script as an administrator."
}

function New-RepositorySymlink {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LinkPath,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    $linkDirectory = Split-Path -Parent $LinkPath
    if ($linkDirectory) {
        New-Item -ItemType Directory -Path $linkDirectory -Force | Out-Null
    }

    if ((Test-Path $LinkPath) -or (Get-Item $LinkPath -ErrorAction SilentlyContinue)) {
        $existingLink = Get-Item -Force $LinkPath -ErrorAction SilentlyContinue
        if ($existingLink -and $existingLink.LinkType) {
            $currentTarget = $null
            try {
                $currentTarget = (Resolve-Path $existingLink.Target -ErrorAction Stop).Path
            } catch {
                Write-Debug "Could not resolve symlink target '$($existingLink.Target)': $($_.Exception.Message)"
            }
            $expectedTarget = (Resolve-Path $TargetPath).Path

            if ($currentTarget -eq $expectedTarget) {
                Write-Host "Symlink already exists: $LinkPath -> $TargetPath"
                return
            } else {
                Write-Host "Removing incorrect or broken symlink at $LinkPath" -ForegroundColor Yellow
                Remove-Item -Path $LinkPath -Force
            }
        } else {
            throw "A file already exists at $LinkPath and it is not a symlink. " +
            "Move it aside or delete it before running setup.ps1."
        }
    }

    New-Item -ItemType SymbolicLink -Path $LinkPath -Target $TargetPath | Out-Null
    Write-Host "Created symlink: $LinkPath -> $TargetPath"
}

function Initialize-RepositorySymlink {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [switch]$Clean
    )

    $repoProfilePath = Join-Path $RepoRoot 'scripts\shell\Profile.ps1'
    $repoFastfetchConfigPath = Join-Path $RepoRoot '.config\fastfetch-win.jsonc'
    $repoGitConfigPath = Join-Path $RepoRoot '.config\.gitconfig'
    $profilePath = $PROFILE
    $fastfetchConfigPath = 'C:\ProgramData\fastfetch\config.jsonc'
    $gitConfigPath = Join-Path $env:USERPROFILE '.gitconfig'
    $windowsTerminalJsonPath = $env:WT_JSON
    $repoWindowsTerminalJson = Join-Path $RepoRoot '.config\windows-terminal.json'

    if ($Clean) {
        Write-Host "`n[Clean] Wiping all known symlinks..." -ForegroundColor Yellow
        foreach ($path in @($profilePath, $fastfetchConfigPath, $gitConfigPath, $windowsTerminalJsonPath)) {
            if ($path -and ((Test-Path $path) -or (Get-Item $path -ErrorAction SilentlyContinue))) {
                Remove-Item -Path $path -Force -ErrorAction SilentlyContinue
                Write-Host "Removed: $path" -ForegroundColor DarkGray
            }
        }
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $repoProfilePath) -Force | Out-Null
    if (-not (Test-Path $repoProfilePath)) {
        New-Item -ItemType File -Path $repoProfilePath -Force | Out-Null
    }

    if ([string]::IsNullOrWhiteSpace($windowsTerminalJsonPath)) {
        throw 'Windows Terminal settings path is not set in env variables. Set it before proceeding.'
    }

    New-RepositorySymlink -LinkPath $profilePath -TargetPath $repoProfilePath
    New-RepositorySymlink -LinkPath $fastfetchConfigPath -TargetPath $repoFastfetchConfigPath
    New-RepositorySymlink -LinkPath $windowsTerminalJsonPath -TargetPath $repoWindowsTerminalJson
    New-RepositorySymlink -LinkPath $gitConfigPath -TargetPath $repoGitConfigPath
}

function Register-BackupScheduledTask {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    $backupTaskName = 'Backup MR Mods'
    $backupScriptPath = Join-Path $RepoRoot 'scripts\backup\Backup-MRMods.ps1'
    $backupTaskArguments = "-NoProfile -ExecutionPolicy Bypass -File `"$backupScriptPath`""

    if (-not (Test-Path $backupScriptPath)) {
        throw "Could not find the backup script at $backupScriptPath. " +
        "Make sure the dotfiles repo is checked out in $RepoRoot."
    }

    if (Get-ScheduledTask -TaskName $backupTaskName -ErrorAction SilentlyContinue) {
        Write-Host "Scheduled task already exists: $backupTaskName"
        return
    }

    $backupTaskAction = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument $backupTaskArguments
    $backupTaskTrigger = New-ScheduledTaskTrigger -AtStartup
    $backupTaskPrincipal = New-ScheduledTaskPrincipal `
        -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) `
        -LogonType S4U `
        -RunLevel Highest

    Register-ScheduledTask `
        -TaskName $backupTaskName `
        -Action $backupTaskAction `
        -Trigger $backupTaskTrigger `
        -Principal $backupTaskPrincipal `
        -Description 'Back up MR mods weekly.' `
        -Force | Out-Null
    Write-Host "Registered scheduled task: $backupTaskName" -ForegroundColor Green
}

function Install-WingetPackage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManifestPath
    )

    if (-not (Test-Path $ManifestPath)) {
        throw "Could not find the winget package manifest at $ManifestPath."
    }

    $packages = Get-Content -Raw -Path $ManifestPath | ConvertFrom-Json
    foreach ($package in $packages) {
        if (-not $package.Id) {
            throw "Encountered a package entry without an Id in $ManifestPath."
        }

        Write-Host "Installing winget package: $($package.Name) ($($package.Id))" -ForegroundColor Cyan
        & winget install -e --id $package.Id --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) {
            throw "winget install failed for $($package.Id)."
        }
    }
}

function Invoke-Setup {
    param(
        [Parameter(Mandatory = $false)]
        [string]$RepoRoot = $PSScriptRoot,

        [switch]$Clean
    )

    Initialize-RepositorySymlink -RepoRoot $RepoRoot -Clean:$Clean
    Register-BackupScheduledTask -RepoRoot $RepoRoot
    Install-WingetPackage -ManifestPath (Join-Path $RepoRoot 'install\winget-packages.json')
}

$repoRoot = Split-Path -Parent $PSScriptRoot
Invoke-Setup -RepoRoot $repoRoot -Clean:$Clean
