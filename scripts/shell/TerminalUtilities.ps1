function CommandExists {
	Param ($command)
	$preference = $ErrorActionPreference
	$ErrorActionPreference = 'SilentlyContinue'
	try { if (Get-Command $command) { RETURN $true } }
	Catch { Write-Host "$command does not exist"; RETURN $false }
	Finally { $ErrorActionPreference = $preference }
}

# Unix-like sudo
function sudo {
	Start-Process wt -ArgumentList "-d `"$PWD`"" -Verb RunAs
}

# Open the current directory in the file explorer
function here() { Invoke-Item . }

# Unix-like which command
function which($name) { Get-Command $name | Select-Object -ExpandProperty Definition }

# Unix-like touch command
function touch() { New-Item -ItemType File -Name $args[0] }

# Utility to easily go home
function ~ { Set-Location $HOME }

# Replace the current directory with the home directory
function pwdd { $("$PWD".replace($HOME, '~')) }

# Clear the console and history
function rmh() { Remove-Item (Get-PSReadlineOption).HistorySavePath }

# Compute file hashes
function sha1 { Get-FileHash -Algorithm SHA1 $args }
function sha256 { Get-FileHash -Algorithm SHA256 $args }


function OrganizeFilesInDir {
	param(
		[string]$Path = $PWD
	)

	$imageExtensions = @('.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp', '.svg', '.ico', '.tiff', '.raw', '.heic')
	$documentExtensions = @('.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.txt', '.csv', '.odt', '.ods', '.odp', '.md', '.rtf')

	$imagesFolder = Join-Path $Path "Images"
	$documentsFolder = Join-Path $Path "Documents"
	$miscFolder = Join-Path $Path "Misc"

	New-Item -ItemType Directory -Force -Path $imagesFolder | Out-Null
	New-Item -ItemType Directory -Force -Path $documentsFolder | Out-Null
	New-Item -ItemType Directory -Force -Path $miscFolder | Out-Null

	$allFiles = Get-ChildItem -Path $Path -Recurse -File | Where-Object {
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

	Get-ChildItem -Path $Path -Recurse -Directory |
	Where-Object {
		$_.FullName -notlike "$imagesFolder*" -and
		$_.FullName -notlike "$documentsFolder*" -and
		$_.FullName -notlike "$miscFolder*" -and
		$_.FullName -ne $imagesFolder -and
		$_.FullName -ne $documentsFolder -and
		$_.FullName -ne $miscFolder
	} |
	Sort-Object -Property FullName -Descending |
	ForEach-Object {
		if ((Get-ChildItem -Path $_.FullName -Force | Measure-Object).Count -eq 0) {
			Write-Host "Removing empty folder: $($_.FullName)"
			Remove-Item -Path $_.FullName
		}
	}

	Write-Host "`nDone! $Path is now organized."
}

# Minecraft coloring (useful for prompt)
function mccoloring($tmp) {
	$033 = [char]27
	$tmp = "$tmp&r"
	$tmp = $tmp.replace("&lp", "$033[38;5;217m") # Light Pink
	$tmp = $tmp.replace("&p", "$033[38;5;218m")  # Pink
	$tmp = $tmp.replace("&l", "$033[38;5;183m")  # Plum
	$tmp = $tmp.replace("&g", "$033[38;5;135m")  # Medium Purple 2
	$tmp = $tmp.replace("&b", "$033[38;5;153m")  # Light Sky Blue 1
	$tmp = $tmp.replace("&r", "$033[0m")
	$tmp = $tmp.replace("&n", "`r`n")
	$tmp
}

#region git

### Git Aliases/Utilities
function ginit() {
	git init
	git add .
	git commit -m "feat: initialize repository"
}

function glog() {
	git log --graph --pretty=format:'%Cred%h%Creset %an: %s - %Creset %C(yellow)%d%Creset %Cgreen(%cr)%Creset' --abbrev-commit --date=relative
}

function gd() { git diff --color }

function lazycom() {
	git add .
	git commit -m "$args"
	gpsh
}

function gst() { git status -sb }

function gpsh() { git push origin HEAD }

function gpl() { git pull --prune }

function gco() {
	git switch -c $args 2>$null || git switch $args
}
#endregion

Set-Alias ofid -Value OrganizeFilesInDir
