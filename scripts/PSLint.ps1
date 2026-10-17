<#
.SYNOPSIS
Runs PSScriptAnalyzer against PowerShell files in this repository.

.PARAMETER Path
Files or directories to analyze. Relative paths are resolved from the repository
root. The default is the whole repository.
#>
[CmdletBinding()]
param(
    [string[]]$Path = '.'
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$resolvedPaths = @(
    foreach ($item in $Path) {
        $candidate = if ([IO.Path]::IsPathRooted($item)) {
            $item
        } else {
            Join-Path $repositoryRoot $item
        }
        (Resolve-Path $candidate).Path
    }
)

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    throw 'PSScriptAnalyzer is required. Install it with: Install-Module PSScriptAnalyzer -Scope CurrentUser'
}
Import-Module PSScriptAnalyzer -ErrorAction Stop

$settingsPath = Join-Path $repositoryRoot 'PSScriptAnalyzerSettings.psd1'
$virtualEnvironmentPath = Join-Path $repositoryRoot '.venv'
$virtualEnvironmentPrefix = "$virtualEnvironmentPath$([IO.Path]::DirectorySeparatorChar)"
$files = Get-ChildItem -Path $resolvedPaths -Recurse -Include *.ps1, *.psm1, *.psd1 |
    Where-Object {
        $_.Name -ne 'PSScriptAnalyzerSettings.psd1' -and
        -not $_.FullName.StartsWith($virtualEnvironmentPrefix, [StringComparison]::OrdinalIgnoreCase)
    }

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

exit 0
