<#
.SYNOPSIS
Installs personal applications listed in a JSON manifest.

.DESCRIPTION
Each manifest entry is installed through the package manager (or direct
script) its `type` selects: winget, scoop, choco, npm, or script. An entry
that fails - including one that is already installed - is reported and
skipped rather than stopping the rest of the manifest.

This script must run unelevated: Scoop refuses to install correctly under
an administrator token, so it errors out rather than silently misbehaving.
Choco is the one type that needs admin rights, so it elevates itself
per-entry (one UAC prompt per choco install) instead of requiring the
whole run to be elevated.

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

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
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

function Add-ScoopBucketIfMissing {
    # scoop.exe is a positional external CLI, not a cmdlet with named parameters.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPositionalParameters', '')]
    param([Parameter(Mandatory = $true)][string]$Bucket)

    $bucketList = & scoop bucket list | Out-String
    if ($bucketList -notmatch "(?m)^\s*$Bucket\s") {
        & scoop bucket add $Bucket
        if ($LASTEXITCODE -ne 0) {
            throw "scoop bucket add exited with code $LASTEXITCODE for '$Bucket'."
        }
    }
}

function Install-ScoopApp {
    param([Parameter(Mandatory = $true)][string]$Name)

    # Scoop installs per-user and refuses to behave correctly when elevated,
    # so this has to fail loudly rather than let scoop misbehave silently.
    if (Test-IsAdministrator) {
        throw "Scoop must not run elevated (installing '$Name'). Run this script without administrator rights."
    }

    # Names like "nerd-fonts/Meslo-NF" need their bucket added first, or
    # scoop fails outright instead of prompting.
    if ($Name -match '^(?<bucket>[^/]+)/') {
        Add-ScoopBucketIfMissing -Bucket $Matches.bucket
    }

    & scoop install $Name
    if ($LASTEXITCODE -ne 0) {
        throw "scoop install exited with code $LASTEXITCODE for '$Name'."
    }
}

function Install-ChocoApp {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (Test-IsAdministrator) {
        & choco install $Name -y
        if ($LASTEXITCODE -ne 0) {
            throw "choco install exited with code $LASTEXITCODE for '$Name'."
        }
        return
    }

    # Choco needs admin rights. Elevate just this install instead of requiring
    # the whole manifest run to be elevated, which would break Scoop above.
    $process = Start-Process -FilePath 'choco' -ArgumentList @('install', $Name, '-y') -Verb RunAs -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "Elevated choco install exited with code $($process.ExitCode) for '$Name'."
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
