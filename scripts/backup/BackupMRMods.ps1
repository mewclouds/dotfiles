# Runs as a scheduled task weekly

# Validate required environment variables before using them
if ([string]::IsNullOrWhiteSpace($env:MR_MODS_PATH)) {
	throw "Missing required environment variable 'MR_MODS_PATH'. Add a value to MR_MODS_PATH and try again."
}

if ([string]::IsNullOrWhiteSpace($env:MR_MODS_BACKUP)) {
	throw "Missing required environment variable 'MR_MODS_BACKUP'. Add a value to MR_MODS_BACKUP and try again."
}

# Work around since scheduled tasks can't be scheduled during startup and at a specific day
if ((Get-Date).DayOfWeek -ne [DayOfWeek]::Sunday) {
	Write-Host "Skipping backup because today is not Sunday." -ForegroundColor Yellow
	exit 0
}

# Define source and destination paths
$SourceFolder = $env:MR_MODS_PATH
$BackupDir = $env:MR_MODS_BACKUP
$ZipPackage = Join-Path -Path $BackupDir -ChildPath "MRMods_Backup.zip"

# Force create the source mods folder if it's missing
if (-not (Test-Path -Path $SourceFolder)) {
	New-Item -Path $SourceFolder -ItemType Directory | Out-Null
	Write-Host "Created missing source folder: $SourceFolder" -ForegroundColor Yellow
}

# Force create the backup directory if it's missing
if (-not (Test-Path -Path $BackupDir)) {
	New-Item -Path $BackupDir -ItemType Directory | Out-Null
}

# Zip the folder (and overwrite the previous zip if it exists)
Write-Host "Updating backup at $ZipPackage..." -ForegroundColor Cyan
Compress-Archive -Path "$SourceFolder\*" -DestinationPath $ZipPackage -Force
Write-Host "Backup updated successfully!" -ForegroundColor Green
