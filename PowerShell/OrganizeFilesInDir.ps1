param(
	[Parameter(Mandatory = $true)]
	[string]$SourceFolder
)

# Define file type categories
$imageExtensions = @('.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp', '.svg', '.ico', '.tiff', '.raw', '.heic')
$documentExtensions = @('.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.txt', '.csv', '.odt', '.ods', '.odp', '.md', '.rtf')

# Create destination folders
$imagesFolder = Join-Path $SourceFolder "Images"
$documentsFolder = Join-Path $SourceFolder "Documents"
$miscFolder = Join-Path $SourceFolder "Misc"

New-Item -ItemType Directory -Force -Path $imagesFolder | Out-Null
New-Item -ItemType Directory -Force -Path $documentsFolder | Out-Null
New-Item -ItemType Directory -Force -Path $miscFolder | Out-Null

# Grab all files recursively, skip the destination folders themselves
$allFiles = Get-ChildItem -Path $SourceFolder -Recurse -File | Where-Object {
	$_.FullName -notlike "$imagesFolder*" -and
	$_.FullName -notlike "$documentsFolder*" -and
	$_.FullName -notlike "$miscFolder*"
}

foreach ($file in $allFiles) {
	$ext = $file.Extension.ToLower()

	if ($imageExtensions -contains $ext) {
		$destination = $imagesFolder
	}
	elseif ($documentExtensions -contains $ext) {
		$destination = $documentsFolder
	}
	else {
		$destination = $miscFolder
	}

	$destPath = Join-Path $destination $file.Name

	# Handle duplicates by appending a number
	if (Test-Path $destPath) {
		$counter = 1
		$baseName = $file.BaseName
		do {
			$destPath = Join-Path $destination "$baseName`_$counter$ext"
			$counter++
		} while (Test-Path $destPath)
	}

	Write-Host "Moving: $($file.FullName) -> $destPath"
	Move-Item -Path $file.FullName -Destination $destPath
}

# Delete empty folders (excluding the 3 main ones)
Get-ChildItem -Path $SourceFolder -Recurse -Directory |
Where-Object {
	$_.FullName -notlike "$imagesFolder*" -and
	$_.FullName -notlike "$documentsFolder*" -and
	$_.FullName -notlike "$miscFolder*" -and
	$_.FullName -ne $imagesFolder -and
	$_.FullName -ne $documentsFolder -and
	$_.FullName -ne $miscFolder
} |
Sort-Object -Property FullName -Descending |  # Sort deepest first
ForEach-Object {
	if ((Get-ChildItem -Path $_.FullName -Force | Measure-Object).Count -eq 0) {
		Write-Host "Removing empty folder: $($_.FullName)"
		Remove-Item -Path $_.FullName
	}
}

Write-Host "`nDone! Your folder is now organized."
