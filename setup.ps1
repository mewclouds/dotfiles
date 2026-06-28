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
			$currentTarget = (Resolve-Path $LinkPath).Path
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

$repoRoot = $PSScriptRoot
$repoProfilePath = Join-Path $repoRoot 'PowerShell\profile.ps1'
$repoFastfetchConfigPath = Join-Path $repoRoot '.config\fastfetch-win.jsonc'
$profilePath = $PROFILE
$fastfetchConfigPath = 'C:\ProgramData\fastfetch\config.jsonc'


New-Item -ItemType Directory -Path (Split-Path -Parent $repoProfilePath) -Force | Out-Null
if (-not (Test-Path $repoProfilePath)) {
	New-Item -ItemType File -Path $repoProfilePath -Force | Out-Null
}

New-RepositorySymlink -LinkPath $profilePath -TargetPath $repoProfilePath
New-RepositorySymlink -LinkPath $fastfetchConfigPath -TargetPath $repoFastfetchConfigPath
