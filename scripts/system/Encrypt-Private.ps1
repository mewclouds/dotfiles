<#
.SYNOPSIS
Creates the encrypted private-state archive when its source content changes.

.DESCRIPTION
The source directory is hashed before encryption so unchanged private state does
not produce a new encrypted archive. The temporary ZIP archive and encrypted
output and Bitwarden identity file are removed if the operation fails.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent
$privatePath = Join-Path $repositoryRoot 'private'
$archivePath = Join-Path $repositoryRoot 'private.age'
$hashPath = Join-Path $repositoryRoot 'private.age.hash'
$temporaryArchivePath = Join-Path $env:TEMP "dotfiles-private-$PID.zip"
$temporaryEncryptedPath = "$archivePath.tmp.$PID"
$temporaryIdentityPath = Join-Path $env:TEMP "dotfiles-age-identity-$PID.txt"
$bitwardenItemName = 'dotfiles-age-keys'

function Get-AgeRecipient {
    <#
    .SYNOPSIS
    Derives the public age recipient from the Bitwarden-stored identity.

    .DESCRIPTION
    The private identity is needed only long enough to derive the public recipient
    used for encryption. Keeping the identity in Bitwarden avoids storing the
    decryption key in the repository or requiring it as a command-line argument.

    The temporary identity file exists because age-keygen accepts an identity file.
    It is removed immediately after the recipient is derived.
    #>
    if (-not (Get-Command bw -ErrorAction SilentlyContinue)) {
        throw 'Bitwarden CLI (bw) is required to retrieve the age identity.'
    }

    if (-not (Get-Command age-keygen -ErrorAction SilentlyContinue)) {
        throw 'age-keygen is required to derive the age recipient.'
    }

    $identity = & bw get notes $bitwardenItemName
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($identity -join "`n"))) {
        throw "Could not retrieve '$bitwardenItemName' from Bitwarden. Unlock the vault and try again."
    }

    try {
        Set-Content -LiteralPath $temporaryIdentityPath -Value ($identity -join [Environment]::NewLine) -NoNewline
        $recipient = (& age-keygen -y $temporaryIdentityPath).Trim()
        if ($LASTEXITCODE -ne 0 -or $recipient -notmatch '^age1') {
            throw 'Could not derive an age recipient from the Bitwarden identity.'
        }

        return $recipient
    } finally {
        Remove-Item -LiteralPath $temporaryIdentityPath -Force -ErrorAction SilentlyContinue
    }
}


function Get-DirectoryFingerprint {
    <#
    .SYNOPSIS
    Creates a stable fingerprint for the files under a private-state directory.

    .DESCRIPTION
    The fingerprint combines each file's repository-relative path with its
    SHA-256 content hash. This makes the result independent of the machine's
    absolute paths while still detecting added, removed, or modified files.

    The fingerprint is used only as a local cache key to avoid rebuilding an
    unchanged encrypted archive; it is not a replacement for age encryption.

    .PARAMETER Path
    Directory whose file contents should be fingerprinted.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $entries = foreach ($file in Get-ChildItem -LiteralPath $Path -File -Recurse | Sort-Object FullName) {
        $relativePath = [IO.Path]::GetRelativePath($Path, $file.FullName).Replace('\', '/')
        $fileHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        "$relativePath`t$fileHash"
    }

    $content = [Text.Encoding]::UTF8.GetBytes($entries -join "`n")
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        return [Convert]::ToHexString($sha256.ComputeHash($content)).ToLowerInvariant()
    } finally {
        $sha256.Dispose()
    }
}

if (-not (Test-Path -LiteralPath $privatePath -PathType Container)) {
    throw "Private state directory does not exist: $privatePath"
}

$sourceHash = Get-DirectoryFingerprint -Path $privatePath
$recordedHash = if (Test-Path -LiteralPath $hashPath -PathType Leaf) {
    (Get-Content -LiteralPath $hashPath -Raw).Trim()
} else {
    $null
}

if ((Test-Path -LiteralPath $archivePath -PathType Leaf) -and $recordedHash -eq $sourceHash) {
    Write-Host 'Private state is unchanged; keeping the existing archive.'
    return
}

$recipient = Get-AgeRecipient

try {
    Compress-Archive -LiteralPath $privatePath -DestinationPath $temporaryArchivePath -Force

    & age.exe --encrypt --recipient $Recipient --output $temporaryEncryptedPath $temporaryArchivePath
    if ($LASTEXITCODE -ne 0) {
        throw "age failed with exit code $LASTEXITCODE."
    }

    Move-Item -LiteralPath $temporaryEncryptedPath -Destination $archivePath -Force
    Set-Content -LiteralPath $hashPath -Value $sourceHash -NoNewline
    Write-Host "Encrypted private state to $archivePath"
} finally {
    Remove-Item -LiteralPath $temporaryArchivePath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temporaryEncryptedPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temporaryIdentityPath -Force -ErrorAction SilentlyContinue
}


