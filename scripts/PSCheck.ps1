<#
.SYNOPSIS
Runs the repository PowerShell format check and lint in one process.

.DESCRIPTION
The pre-commit hook calls this script so a commit pays for one pwsh start and
one PSScriptAnalyzer import instead of two. Without parameters it checks the
whole repository, exactly like running PSFormat.ps1 -Check and PSLint.ps1.

.PARAMETER Changed
Checks only PowerShell files staged for commit. The full-repository scan stays
in CI through .github/workflows/lint.yml.
#>
[CmdletBinding()]
param(
    [switch]$Changed
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot

if ($Changed) {
    # -z keeps unusual path characters readable; git quotes names otherwise.
    $staged = git -C $repositoryRoot diff --cached --name-only --diff-filter=ACMR -z -- '*.ps1' '*.psm1' '*.psd1'
    if ($LASTEXITCODE -ne 0) {
        throw "git diff --cached failed with exit code $LASTEXITCODE."
    }

    $paths = @($staged -split "`0" | Where-Object { $_ })

    if ($paths.Count -eq 0) {
        Write-Host 'No staged PowerShell files; nothing to check.'
        exit 0
    }

    Write-Host "Checking $($paths.Count) staged PowerShell file(s)."
} else {
    $paths = @('.')
}

& (Join-Path $PSScriptRoot 'PSFormat.ps1') -Check -Path $paths
if ($LASTEXITCODE -ne 0) {
    exit 1
}

& (Join-Path $PSScriptRoot 'PSLint.ps1') -Path $paths
exit $LASTEXITCODE
