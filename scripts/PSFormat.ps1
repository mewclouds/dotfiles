<#
.SYNOPSIS
Formats PowerShell files in this repository with the repository settings.

.PARAMETER Path
The directory to search. Relative paths are resolved from the repository root.
#>
[CmdletBinding()]
param(
    [string]$Path = '.'
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    throw 'PSScriptAnalyzer is required. Install it with: Install-Module PSScriptAnalyzer -Scope CurrentUser'
}
Import-Module PSScriptAnalyzer -ErrorAction Stop

$settingsPath = Join-Path $Path 'PSScriptAnalyzerSettings.psd1'

if (-not (Test-Path $settingsPath -PathType Leaf)) {
    Write-Warning ("No PSScriptAnalyzerSettings.psd1 found at $settingsPath" +
        ' - aborting to avoid reformatting with defaults.')
    exit 0
}

$resolvedSettingsPath = (Resolve-Path $settingsPath).Path
$files = Get-ChildItem -Path $Path -Recurse -Include *.ps1, *.psm1, *.psd1 |
    Where-Object { $_.FullName -ne $resolvedSettingsPath }

foreach ($file in $files) {
    $original = (Get-Content $file.FullName -Raw) -replace "`r`n?", "`n"

    try {
        $formatted = Invoke-Formatter -ScriptDefinition $original -Settings $settingsPath
    } catch {
        Write-Warning "Could not format $($file.FullName): $($_.Exception.Message)"
        continue
    }

    if ($original -ne $formatted) {
        Set-Content -Path $file.FullName -Value $formatted -Encoding utf8NoBOM -NoNewline
        Write-Host "Formatted: $($file.FullName)" -ForegroundColor Green
    }
}
