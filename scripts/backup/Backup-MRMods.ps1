# Runs as a scheduled task weekly

# Set up logging
$LogDir = Join-Path $env:USERPROFILE 'runs\logs'
$LogFile = Join-Path $LogDir 'backup-mrmods.log'
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

function Write-BackupLog {
    param([string]$Message)
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $logLine = "[$timestamp] $Message"
    Add-Content -Path $LogFile -Value $logLine
    Write-Host $Message # Print to console as well for manual runs
}

Write-BackupLog "Starting MR Mods Backup Task..."

# Validate required environment variables before using them
if ([string]::IsNullOrWhiteSpace($env:MR_MODS_PATH)) {
    Write-BackupLog "Error: Missing required environment variable 'MR_MODS_PATH'."
    throw "Missing required environment variable 'MR_MODS_PATH'. Add a value to MR_MODS_PATH and try again."
}

if ([string]::IsNullOrWhiteSpace($env:MR_MODS_BACKUP)) {
    Write-BackupLog "Error: Missing required environment variable 'MR_MODS_BACKUP'."
    throw "Missing required environment variable 'MR_MODS_BACKUP'. Add a value to MR_MODS_BACKUP and try again."
}

# Work around since scheduled tasks can't be scheduled during startup and at a specific day
if ((Get-Date).DayOfWeek -ne [DayOfWeek]::Sunday) {
    Write-BackupLog "Skipping backup because today is not Sunday."
    exit 0
}

# Define source and destination paths
$SourceFolder = $env:MR_MODS_PATH
$BackupDir = $env:MR_MODS_BACKUP
$ArchivePackage = Join-Path -Path $BackupDir -ChildPath "MRMods_Backup.7z"

# Force create the source mods folder if it's missing
if (-not (Test-Path -Path $SourceFolder)) {
    New-Item -Path $SourceFolder -ItemType Directory | Out-Null
    Write-BackupLog "Created missing source folder: $SourceFolder"
}

# Force create the backup directory if it's missing
if (-not (Test-Path -Path $BackupDir)) {
    New-Item -Path $BackupDir -ItemType Directory | Out-Null
}

# Determine 7zip path
$sevenZipCmd = "7z"
if (-not (Get-Command $sevenZipCmd -ErrorAction SilentlyContinue)) {
    $sevenZipCmd = "C:\Program Files\7-Zip\7z.exe"
    if (-not (Test-Path $sevenZipCmd)) {
        Write-BackupLog "Error: 7z is not in PATH and not found at $sevenZipCmd"
        throw "7z is missing"
    }
}

# Deduce the base Marvel folder to preserve folder structure in the archive
$MarvelBase = Split-Path (Split-Path (Split-Path $SourceFolder -Parent) -Parent) -Parent
$Win64Folder = Join-Path $MarvelBase "Binaries\Win64"
$BypassDll = Join-Path $Win64Folder "dsound.dll"
$BypassPlugins = Join-Path $Win64Folder "plugins"

if (Test-Path $ArchivePackage) { Remove-Item $ArchivePackage -Force }

Write-BackupLog "Updating backup at $ArchivePackage..."

if (Test-Path $MarvelBase) {
    Push-Location $MarvelBase

    $itemsToZip = @("Content\Paks\~mods\*")
    if (Test-Path $BypassDll) { $itemsToZip += "Binaries\Win64\dsound.dll" }
    if (Test-Path $BypassPlugins) { $itemsToZip += "Binaries\Win64\plugins" }

    $argList = @("a", "-t7z", "-mx=1", "-y", $ArchivePackage) + $itemsToZip
    & $sevenZipCmd $argList | Out-Null

    Pop-Location
} else {
    # Fallback if the path structure is unexpected
    & $sevenZipCmd a -t7z -mx=1 -y $ArchivePackage "$SourceFolder\*" | Out-Null
}

if ($LASTEXITCODE -eq 0) {
    Write-BackupLog "Backup updated successfully!"
} else {
    Write-BackupLog "Error: 7z backup failed with exit code $LASTEXITCODE"
}
