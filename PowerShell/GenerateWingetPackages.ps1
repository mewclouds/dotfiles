[CmdletBinding()]
param(
	[string]$OutputPath = ('winget-packages.json')
)

$ErrorActionPreference = 'Stop'

function New-PackageEntry {
	param(
		[string]$Name,
		[string]$Id
	)

	[pscustomobject]@{
		Name = $Name
		Id   = $Id
	}
}

$wingetOutput = & winget list --details --disable-interactivity --nowarn
if ($LASTEXITCODE -ne 0) {
	throw 'winget list --details failed.'
}

$packages = New-Object System.Collections.Generic.List[object]
$currentPackage = $null

foreach ($line in ($wingetOutput -split "`r?`n")) {
	if ($line -match '^\(\d+/\d+\)\s+(?<name>.+?)\s+\[(?<id>.+)\]$') {
		if ($currentPackage -and $currentPackage.IsWingetSource) {
			$packages.Add($currentPackage)
		}

		$currentPackage = [ordered]@{
			Name           = $matches.name.Trim()
			Id             = $matches.id.Trim()
			IsWingetSource = $false
		}

		continue
	}

	if (-not $currentPackage) {
		continue
	}

	if ($line -match '^\s*Origin Source:\s+(?<source>\S+)\s*$') {
		if ($matches.source -ieq 'winget') {
			$currentPackage.IsWingetSource = $true
		}
	}
}

if ($currentPackage -and $currentPackage.IsWingetSource) {
	$packages.Add($currentPackage)
}

$outputEntries = foreach ($package in $packages) {
	New-PackageEntry -Name $package.Name -Id $package.Id
}

$outputEntries |
ConvertTo-Json -Depth 2 |
Set-Content -Path $OutputPath -Encoding utf8

Write-Host "Wrote $($outputEntries.Count) package entries to $OutputPath"
