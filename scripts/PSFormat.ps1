<#
.SYNOPSIS
Formats PowerShell files in this repository with the repository settings.

.PARAMETER Path
The directory to search. Relative paths are resolved from the repository root.

.PARAMETER Check
Reports files that would change without modifying them and exits with failure
when formatting differences or formatter errors are found.
#>
[CmdletBinding()]
param(
    [string]$Path = '.',

    [switch]$Check
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
$checkFailed = $false

foreach ($file in $files) {
    $original = (Get-Content $file.FullName -Raw) -replace "`r`n?", "`n"

    try {
        $formatted = Invoke-Formatter -ScriptDefinition $original -Settings $settingsPath
    } catch {
        Write-Warning "Could not format $($file.FullName): $($_.Exception.Message)"
        $checkFailed = $true
        continue
    }

    if ($original -ne $formatted) {
        if ($Check) {
            Write-Warning "Formatting differs: $($file.FullName)"
            $checkFailed = $true
        } else {
            Set-Content -Path $file.FullName -Value $formatted -Encoding utf8NoBOM -NoNewline
            Write-Host "Formatted: $($file.FullName)" -ForegroundColor Green
        }
    }
}

if ($Check -and $checkFailed) {
    exit 1
}
