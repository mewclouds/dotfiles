#Requires -Version 7.0
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [switch]$Clean
)

Add-Type -AssemblyName System.Windows.Forms

function Get-FolderSelection {
    param([string]$VarName, [string]$Prompt)
    $current = [Environment]::GetEnvironmentVariable($VarName, 'User')
    if ($current) {
        [Environment]::SetEnvironmentVariable($VarName, $current, 'Process')
        return
    }

    Write-Host "`n$Prompt" -ForegroundColor Yellow
    $browser = New-Object System.Windows.Forms.FolderBrowserDialog
    $browser.Description = $Prompt
    $browser.ShowNewFolderButton = $true

    if ($browser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        [Environment]::SetEnvironmentVariable($VarName, $browser.SelectedPath, 'User')
        [Environment]::SetEnvironmentVariable($VarName, $browser.SelectedPath, 'Process')
        Write-Host "Set $VarName to $($browser.SelectedPath)" -ForegroundColor Green
    }
}

function Get-FileSelection {
    param([string]$VarName, [string]$Prompt, [string]$Filter = 'All Files (*.*)|*.*')
    $current = [Environment]::GetEnvironmentVariable($VarName, 'User')
    if ($current) {
        [Environment]::SetEnvironmentVariable($VarName, $current, 'Process')
        return
    }

    Write-Host "`n$Prompt" -ForegroundColor Yellow
    $browser = New-Object System.Windows.Forms.OpenFileDialog
    $browser.Title = $Prompt
    $browser.Filter = $Filter

    if ($browser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        [Environment]::SetEnvironmentVariable($VarName, $browser.FileName, 'User')
        [Environment]::SetEnvironmentVariable($VarName, $browser.FileName, 'Process')
        Write-Host "Set $VarName to $($browser.FileName)" -ForegroundColor Green
    }
}

function Resolve-EnvironmentVariable {
    # UTILITIES_PATH
    $utilitiesPath = Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'scripts\shell\TerminalUtilities.ps1'
    if (Test-Path $utilitiesPath) {
        [Environment]::SetEnvironmentVariable('UTILITIES_PATH', $utilitiesPath, 'User')
        [Environment]::SetEnvironmentVariable('UTILITIES_PATH', $utilitiesPath, 'Process')
    }

    # WT_JSON
    $defaultWtJson = Join-Path $env:LOCALAPPDATA `
        'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    if (-not [Environment]::GetEnvironmentVariable('WT_JSON', 'User') -and (Test-Path $defaultWtJson)) {
        [Environment]::SetEnvironmentVariable('WT_JSON', $defaultWtJson, 'User')
        [Environment]::SetEnvironmentVariable('WT_JSON', $defaultWtJson, 'Process')
        Write-Host "Set WT_JSON to $defaultWtJson (auto-detected)" -ForegroundColor Green
    } else {
        Get-FileSelection -VarName 'WT_JSON' `
            -Prompt 'Select your Windows Terminal settings.json' `
            -Filter 'JSON Files (*.json)|*.json'
    }

    Get-FolderSelection -VarName 'MR_MODS_PATH' -Prompt 'Select your MR Mods directory'
    Get-FolderSelection -VarName 'MR_MODS_BACKUP' -Prompt 'Select your MR Mods backup directory'
}

function Install-NirCmd {
    $nircmdDir = 'C:\nircmd'
    $nircmdZip = Join-Path $env:TEMP 'nircmd-x64.zip'
    $nircmdUrl = 'https://www.nirsoft.net/utils/nircmd-x64.zip'

    try {
        if (-not (Test-Path $nircmdDir)) {
            Write-Host "`nDownloading NirCmd..." -ForegroundColor Cyan
            Invoke-WebRequest -Uri $nircmdUrl -OutFile $nircmdZip -ErrorAction Stop

            Write-Host "Extracting NirCmd to $nircmdDir..." -ForegroundColor Cyan
            Expand-Archive -Path $nircmdZip -DestinationPath $nircmdDir -Force -ErrorAction Stop

            Remove-Item $nircmdZip -Force -ErrorAction SilentlyContinue
        } else {
            Write-Host "`nNirCmd is already installed at $nircmdDir." -ForegroundColor DarkGray
        }

        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if ($userPath -notlike "*$nircmdDir*") {
            $newPath = $userPath + ';' + $nircmdDir
            [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
            $processPath = [Environment]::GetEnvironmentVariable('Path', 'Process')
            [Environment]::SetEnvironmentVariable('Path', $processPath + ';' + $nircmdDir, 'Process')
            Write-Host "Added $nircmdDir to User PATH." -ForegroundColor Green
        }
    } catch {
        Write-Host "`nFailed to install NirCmd: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-AppxDebloat {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    $appxScript = Join-Path $RepoRoot 'scripts\system\Remove-AppxBloat.ps1'

    if (Test-Path $appxScript) {
        Write-Host "`nRemoving Windows Appx bloat..." -ForegroundColor Cyan
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File $appxScript
    } else {
        Write-Host "`nAppx debloat script not found at $appxScript" -ForegroundColor Yellow
    }
}


function Invoke-DnsSetup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    $dnsScript = Join-Path $RepoRoot 'scripts\system\Set-Dns.ps1'
    if (Test-Path $dnsScript) {
        Write-Host "`nConfiguring DNS settings..." -ForegroundColor Cyan
        & $dnsScript
    } else {
        Write-Host "`nDNS script not found at $dnsScript" -ForegroundColor Yellow
    }
}

function Invoke-InstallLosslessCut {
    $installDir = 'C:\Program Files\LosslessCut'
    $apiUrl = 'https://api.github.com/repos/mifi/lossless-cut/releases/latest'
    $tempDir = Join-Path $env:TEMP "LosslessCut-Install-$([guid]::NewGuid())"

    try {
        Write-Host "`nFetching latest LosslessCut release info..." -ForegroundColor Cyan
        $release = Invoke-RestMethod -Uri $apiUrl -Headers @{ 'User-Agent' = 'PowerShell' }
        Write-Host "  Latest version: $($release.tag_name)" -ForegroundColor Green

        # Find the 7z asset (e.g. LosslessCut-win-x64.7z)
        $asset = $release.assets | Where-Object { $_.name -like '*win-x64*.7z' } | Select-Object -First 1
        if (-not $asset) {
            Write-Error "No Windows 7z found in the latest LosslessCut release assets. Skipping."
            return
        }
        Write-Host "  Found: $($asset.name)" -ForegroundColor Green

        # Download the asset
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        $archivePath = Join-Path $tempDir $asset.name

        Write-Host "  Downloading LosslessCut..." -ForegroundColor Cyan
        $oldProgress = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $archivePath -UseBasicParsing
        $ProgressPreference = $oldProgress
        Write-Host "  Download complete." -ForegroundColor Green

        # Extract it
        Write-Host "  Extracting LosslessCut..." -ForegroundColor Cyan
        if (-not (Test-Path $installDir)) {
            New-Item -ItemType Directory -Path $installDir -Force | Out-Null
        }

        # Use 7z to extract
        $extractArgs = @('x', $archivePath, "-o$installDir", '-y')
        Start-Process -FilePath '7z' -ArgumentList $extractArgs -Wait -NoNewWindow -ErrorAction Stop

        Write-Host "  LosslessCut installed successfully to $installDir" -ForegroundColor Green
    } catch {
        Write-Host "  Failed to install LosslessCut: $($_.Exception.Message)" -ForegroundColor Red
    } finally {
        if (Test-Path $tempDir) {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function New-RepositorySymlink {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LinkPath,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    $linkDirectory = Split-Path -Path $LinkPath -Parent
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

    New-Item -ItemType Directory -Path (Split-Path -Path $repoProfilePath -Parent) -Force | Out-Null
    if (-not (Test-Path $repoProfilePath)) {
        New-Item -ItemType File -Path $repoProfilePath -Force | Out-Null
    }

    if ([string]::IsNullOrWhiteSpace($windowsTerminalJsonPath)) {
        throw 'Windows Terminal settings path is not set in env variables. Set it before proceeding.'
    }

    New-RepositorySymlink -LinkPath $profilePath -TargetPath $repoProfilePath
    New-RepositorySymlink -LinkPath $fastfetchConfigPath -TargetPath $repoFastfetchConfigPath

    # Copy Windows Terminal settings file instead of symlinking it
    if ((Test-Path $windowsTerminalJsonPath) -or (Get-Item $windowsTerminalJsonPath -ErrorAction SilentlyContinue)) {
        Write-Host ("Removing existing Windows Terminal file/symlink at " +
            "$windowsTerminalJsonPath...") -ForegroundColor Yellow
        Remove-Item $windowsTerminalJsonPath -Force -ErrorAction SilentlyContinue
    }
    Copy-Item -Path $repoWindowsTerminalJson -Destination $windowsTerminalJsonPath -Force
    Write-Host "Copied Windows Terminal config: $repoWindowsTerminalJson -> $windowsTerminalJsonPath"

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

function Install-CuratedPackage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManifestPath
    )

    if (-not (Test-Path $ManifestPath)) {
        throw "Could not find the package manifest at $ManifestPath."
    }

    $categories = Get-Content -Raw -Path $ManifestPath | ConvertFrom-Json
    $propertyNames = $categories.psobject.properties.name

    foreach ($categoryName in $propertyNames) {
        $packages = $categories.$categoryName
        if (-not $packages -or $packages.Count -eq 0) { continue }

        Write-Host "`nInstalling category: $categoryName" -ForegroundColor Yellow

        foreach ($package in $packages) {
            if ($package.type -eq 'winget') {
                Write-Host "Installing winget package: $($package.name) ($($package.id))" -ForegroundColor Cyan
                & winget install -e --id $package.id --accept-package-agreements --accept-source-agreements | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "Warning: winget install failed for $($package.id)." -ForegroundColor Red
                }
            } elseif ($package.type -eq 'script') {
                Write-Host "Installing via script: $($package.name)" -ForegroundColor Cyan
                Invoke-Expression $package.command
            } else {
                Write-Host "Warning: Unknown package type '$($package.type)' for $($package.name)" `
                    -ForegroundColor DarkYellow
            }
        }

        # Refresh environment variables process scope
        foreach ($level in @('Machine', 'User')) {
            [Environment]::GetEnvironmentVariables($level).GetEnumerator() | ForEach-Object {
                [Environment]::SetEnvironmentVariable($_.Key, $_.Value, 'Process')
            }
        }
    }
}

function Show-WelcomeBanner {
    Clear-Host
    $banner = @'
███╗   ███╗███████╗██╗    ██╗██████╗  ██████╗ ████████╗███████╗   ██╗   ██╗
████╗ ████║██╔════╝██║    ██║██╔══██╗██╔═══██╗╚══██╔══╝██╔════╝  ████╗ ████╗
██╔████╔██║█████╗  ██║ █╗ ██║██║  ██║██║   ██║   ██║   ███████╗  ╚████████╔╝
██║╚██╔╝██║██╔══╝  ██║███╗██║██║  ██║██║   ██║   ██║   ╚════██║   ╚██████╔╝
██║ ╚═╝ ██║███████╗╚███╔███╔╝██████╔╝╚██████╔╝   ██║   ███████║    ╚████╔╝
╚═╝     ╚═╝╚══════╝ ╚══╝╚══╝ ╚═════╝  ╚═════╝    ╚═╝   ╚══════╝     ╚══╝
'@
    Write-Host $banner -ForegroundColor Cyan
    Write-Host "`nWelcome to MewDots Setup! ꨄ" -ForegroundColor Green
    Write-Host "Setting up environment and utilities...`n" -ForegroundColor DarkCyan
}

function Invoke-Setup {
    param(
        [Parameter(Mandatory = $false)]
        [string]$RepoRoot = $PSScriptRoot,

        [switch]$Clean
    )

    Show-WelcomeBanner
    Resolve-EnvironmentVariable
    Initialize-RepositorySymlink -RepoRoot $RepoRoot -Clean:$Clean
    Register-BackupScheduledTask -RepoRoot $RepoRoot
    $manifest = Join-Path $RepoRoot 'install\packages.json'
    Install-CuratedPackage -ManifestPath $manifest
    Install-NirCmd
    Invoke-AppxDebloat -RepoRoot $RepoRoot
    Invoke-DnsSetup -RepoRoot $RepoRoot
    #Invoke-InstallLosslessCut
}

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
Invoke-Setup -RepoRoot $repoRoot -Clean:$Clean
Write-Host "`nSetup complete! Press any key to close." -ForegroundColor Cyan
[Console]::ReadKey() | Out-Null


