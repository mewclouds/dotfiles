$requiredPowerShellMajorVersion = 7
if ($PSVersionTable.PSVersion.Major -lt $requiredPowerShellMajorVersion) {
	throw "PowerShell $requiredPowerShellMajorVersion or later is required. Run this script with pwsh 7+ instead of Windows PowerShell."
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

	if (Test-Path $LinkPath) {
		$existingLink = Get-Item -Force $LinkPath
		if ($existingLink.LinkType) {
			$currentTarget = (Resolve-Path $existingLink.Target).Path
			$expectedTarget = (Resolve-Path $TargetPath).Path
			if ($currentTarget -eq $expectedTarget) {
				Write-Host "Symlink already exists: $LinkPath -> $TargetPath"
				return
			}
		}

		throw "A path already exists at $LinkPath. Move it aside or delete it before running setup.ps1."
	}

	New-Item -ItemType SymbolicLink -Path $LinkPath -Target $TargetPath | Out-Null
	Write-Host "Created symlink: $LinkPath -> $TargetPath"
}

function Initialize-RepositorySymlinks {
	param(
		[Parameter(Mandatory = $true)]
		[string]$RepoRoot
	)

	$repoProfilePath = Join-Path $RepoRoot 'PowerShell\profile.ps1'
	$repoFastfetchConfigPath = Join-Path $RepoRoot '.config\fastfetch-win.jsonc'
	$profilePath = $PROFILE
	$fastfetchConfigPath = 'C:\ProgramData\fastfetch\config.jsonc'
	$windowsTerminalJsonPath = $env:WT_JSON
	$repoWindowsTerminalJson = Join-Path $RepoRoot '.config\windows-terminal.json'

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
}

function Register-BackupScheduledTask {
	param(
		[Parameter(Mandatory = $true)]
		[string]$RepoRoot
	)

	$backupTaskName = 'Backup MR Mods'
	$backupScriptPath = Join-Path $RepoRoot 'PowerShell\BackupMRMods.ps1'
	$backupTaskArguments = "-NoProfile -ExecutionPolicy Bypass -File `"$backupScriptPath`""

	if (-not (Test-Path $backupScriptPath)) {
		throw "Could not find the backup script at $backupScriptPath. Make sure the dotfiles repo is checked out in $RepoRoot."
	}

	if (Get-ScheduledTask -TaskName $backupTaskName -ErrorAction SilentlyContinue) {
		Write-Host "Scheduled task already exists: $backupTaskName"
		return
	}

	$backupTaskAction = New-ScheduledTaskAction -Execute $PSHOME\pwsh.exe -Argument $backupTaskArguments
	$backupTaskTrigger = New-ScheduledTaskTrigger -AtStartup
	$backupTaskPrincipal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType S4U -RunLevel Highest

	Register-ScheduledTask -TaskName $backupTaskName -Action $backupTaskAction -Trigger $backupTaskTrigger -Principal $backupTaskPrincipal -Description 'Back up MR mods weekly.' -Force | Out-Null
	Write-Host "Registered scheduled task: $backupTaskName" -ForegroundColor Green
}

function Install-WingetPackages {
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
		[string]$RepoRoot = $PSScriptRoot
	)

	Initialize-RepositorySymlinks -RepoRoot $RepoRoot
	Register-BackupScheduledTask -RepoRoot $RepoRoot
	Install-WingetPackages -ManifestPath (Join-Path $RepoRoot 'winget-packages.json')
}

$repoRoot = $PSScriptRoot
Invoke-Setup -RepoRoot $repoRoot
