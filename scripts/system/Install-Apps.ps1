<#
.SYNOPSIS
Installs personal applications listed in a JSON manifest.

.DESCRIPTION
Each manifest entry is installed through the package manager (or direct
script) its `type` selects: winget, scoop, choco, npm, or script. An entry
that fails - including one that is already installed - is reported and
skipped rather than stopping the rest of the manifest.

.PARAMETER ManifestPath
Path to the JSON manifest describing which apps to install and how.
#>
[CmdletBinding()]
param(
    [string]$ManifestPath
)

$ErrorActionPreference = 'Stop'

# $PSScriptRoot is empty when evaluated as a param() default under -File with
# a relative script path, so the default is computed here instead.
if (-not $ManifestPath) {
    $ManifestPath = Join-Path $PSScriptRoot '..\..\private\apps.json'
}

function Install-WingetApp {
    param([Parameter(Mandatory = $true)][string]$Id)

    # No --exact: winget's exact match is case-sensitive, and manifest IDs
    # are hand-typed.
    & winget install --id $Id --accept-package-agreements --accept-source-agreements `
        --disable-interactivity --silent
    if ($LASTEXITCODE -ne 0) {
        throw "winget install exited with code $LASTEXITCODE for '$Id'."
    }
}

function Install-ScoopApp {
    param([Parameter(Mandatory = $true)][string]$Name)

    & scoop install $Name
    if ($LASTEXITCODE -ne 0) {
        throw "scoop install exited with code $LASTEXITCODE for '$Name'."
    }
}

function Install-ChocoApp {
    param([Parameter(Mandatory = $true)][string]$Name)

    & choco install $Name -y
    if ($LASTEXITCODE -ne 0) {
        throw "choco install exited with code $LASTEXITCODE for '$Name'."
    }
}

function Install-NpmApp {
    param([Parameter(Mandatory = $true)][string]$Name)

    # npm is mise-managed, not on PATH directly. `mise exec --` still parses
    # `-g` as its own flag even after the separator, so the command has to
    # go through -c as one string instead.
    & mise exec -c "npm install -g $Name"
    if ($LASTEXITCODE -ne 0) {
        throw "npm install exited with code $LASTEXITCODE for '$Name'."
    }
}

function Invoke-ScriptApp {
    param([Parameter(Mandatory = $true)][string]$Command)

    Invoke-Expression $Command
}

if (-not (Test-Path $ManifestPath -PathType Leaf)) {
    throw "App manifest not found: $ManifestPath"
}

$manifest = Get-Content -Path $ManifestPath -Raw | ConvertFrom-Json
$apps = @($manifest.apps)

if (-not $apps) {
    Write-Host 'No apps listed in the manifest.' -ForegroundColor Yellow
    exit 0
}

$issueCount = 0

foreach ($app in $apps) {
    $label = switch ($app.type) {
        'winget' { $app.id }
        'script' { $app.command }
        default { $app.name }
    }

    Write-Host "[$($app.type)] $label" -ForegroundColor Cyan

    try {
        switch ($app.type) {
            'winget' { Install-WingetApp -Id $app.id }
            'scoop' { Install-ScoopApp -Name $app.name }
            'choco' { Install-ChocoApp -Name $app.name }
            'npm' { Install-NpmApp -Name $app.name }
            'script' { Invoke-ScriptApp -Command $app.command }
            default { throw "Unknown app type: $($app.type)" }
        }
        Write-Host '  Done.' -ForegroundColor Green
    } catch {
        $issueCount++
        Write-Warning "  Skipped ($($_.Exception.Message))"
    }
}

Write-Host "`nProcessed $($apps.Count) app(s), $issueCount reported an issue (already installed or otherwise)." `
    -ForegroundColor Cyan
