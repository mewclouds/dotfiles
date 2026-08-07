<#
.SYNOPSIS
Runs PSScriptAnalyzer against PowerShell files in this repository.

.PARAMETER Path
The directory to search. Relative paths are resolved from the repository root.
#>
[CmdletBinding()]
param(
    [string]$Path = '.'
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$resolvedPath = if ([IO.Path]::IsPathRooted($Path)) {
    $Path
} else {
    Join-Path $repositoryRoot $Path
}
$resolvedPath = (Resolve-Path $resolvedPath).Path

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    throw 'PSScriptAnalyzer is required. Install it with: Install-Module PSScriptAnalyzer -Scope CurrentUser'
}
Import-Module PSScriptAnalyzer -ErrorAction Stop

$settingsPath = Join-Path $resolvedPath 'PSScriptAnalyzerSettings.psd1'
$files = Get-ChildItem -Path $resolvedPath -Recurse -Include *.ps1, *.psm1, *.psd1 |
    Where-Object { $_.Name -ne 'PSScriptAnalyzerSettings.psd1' }

if (-not $files) {
    exit 0
}

if (-not (Test-Path $settingsPath -PathType Leaf)) {
    Write-Warning "No PSScriptAnalyzerSettings.psd1 found at $settingsPath."
    $diagnostics = $files | Invoke-ScriptAnalyzer
} else {
    $diagnostics = $files | Invoke-ScriptAnalyzer -Settings $settingsPath
}

if ($diagnostics) {
    $diagnostics | Format-Table -AutoSize | Out-Host
    exit 1
}
