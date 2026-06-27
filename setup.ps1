$repoRoot = $PSScriptRoot
$repoProfilePath = Join-Path $repoRoot 'PowerShell\profile.ps1'
$profilePath = $PROFILE
$profileDirectory = Split-Path -Parent $profilePath

New-Item -ItemType Directory -Path (Split-Path -Parent $repoProfilePath) -Force | Out-Null
if (-not (Test-Path $repoProfilePath)) {
    New-Item -ItemType File -Path $repoProfilePath -Force | Out-Null
}

New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null

if (Test-Path $profilePath) {
    $existingProfile = Get-Item -Force $profilePath
    if ($existingProfile.LinkType) {
        $currentTarget = (Resolve-Path $profilePath).Path
        $expectedTarget = (Resolve-Path $repoProfilePath).Path
        if ($currentTarget -eq $expectedTarget) {
            Write-Host "Profile link already exists: $profilePath -> $repoProfilePath"
            return
        }
    }

    throw "A profile already exists at $profilePath. Move it aside or delete it before running setup.ps1."
}

New-Item -ItemType SymbolicLink -Path $profilePath -Target $repoProfilePath | Out-Null
Write-Host "Created profile link: $profilePath -> $repoProfilePath"
