function CommandExists($command) { [bool](Get-Command $command -ErrorAction SilentlyContinue) }

# Invokes an admin window in the current dir
function su {
    Start-Process wt -ArgumentList "-d `"$PWD`"" -Verb RunAs
}


# Run the full elevated system health check
function systemhealth {
    $checks = 'sfc /scannow; DISM /Online /Cleanup-Image /CheckHealth; ' +
    'DISM /Online /Cleanup-Image /ScanHealth'
    gsudo pwsh -NoProfile -Command $checks
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
function rmh() { Remove-Item (Get-PSReadLineOption).HistorySavePath }

# Compute file hashes
function sha256 { (Get-FileHash -Algorithm SHA256 $args).Hash }

# Launch Chris Titus Tech WinUtil
function winutil { Invoke-RestMethod https://christitus.com/win | Invoke-Expression }
function winutildev { Invoke-RestMethod https://christitus.com/windev | Invoke-Expression }

# Quickly open my dots
function dots {
    Set-Location (Join-Path $HOME "dotfiles")
    code .
}

# Quickly open rippie
function rippie {
    Set-Location (Join-Path $HOME "Rippie")
    code .
}

# Quickly open WinUtil
function codewinutil {
    Set-Location (Join-Path $HOME "oss\winutil")
    code .
}

function Get-ExePath {
    Get-ChildItem -Path $PWD -Filter "*.exe" -Recurse -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -notmatch '(?i)^[A-Z]:\\Windows\\' -and
            $_.FullName -notmatch '(?i)\\System Volume Information\\'
        } |
        Select-Object -ExpandProperty FullName
}

# Minecraft coloring (Evergarden Spring Palette Edition - High Contrast)
function mccoloring($tmp) {
    $033 = [char]27
    $tmp = "$tmp&r"

    # 24-bit True Color RGB Palette (Evergarden-inspired High Contrast pastels)
    $tmp = $tmp.replace("&ocean", "$033[38;2;194;223;255m") # Brightened Evergarden Blue
    $tmp = $tmp.replace("&sky", "$033[38;2;194;242;231m")   # Brightened Evergarden Mint
    $tmp = $tmp.replace("&coral", "$033[38;2;248;200;237m") # Brightened Evergarden Purple/Pink
    $tmp = $tmp.replace("&sand", "$033[38;2;250;219;176m")  # Brightened Evergarden Sage/Sand
    $tmp = $tmp.replace("&sun", "$033[38;2;252;219;168m")   # Brightened Evergarden Yellow/Peach
    $tmp = $tmp.replace("&leaf", "$033[38;2;220;242;188m")  # Brightened Evergarden Green
    $tmp = $tmp.replace("&cloud", "$033[38;2;251;252;235m") # Brightened Evergarden Cream White
    $tmp = $tmp.replace("&red", "$033[38;2;255;151;154m")    # Brightened Evergarden Red

    $tmp = $tmp.replace("&r", "$033[0m")
    $tmp = $tmp.replace("&n", "`r`n")
    $tmp
}

function PSLint {
    [CmdletBinding()]
    param(
        [string]$Path = '.',
        [switch]$Fix
    )

    $settingsPath = Join-Path $Path 'PSScriptAnalyzerSettings.psd1'

    # Filter out the settings file itself, otherwise Invoke-ScriptAnalyzer crashes with NullReferenceException
    $files = Get-ChildItem -Path $Path -Recurse -Include *.ps1, *.psm1, *.psd1 |
        Where-Object { $_.Name -ne 'PSScriptAnalyzerSettings.psd1' }
    if (-not $files) { return }

    if (-not (Test-Path $settingsPath)) {
        Write-Warning "No PSScriptAnalyzerSettings.psd1 found at $settingsPath - running with default rules."
        $files | Invoke-ScriptAnalyzer -Fix:$Fix
        return
    }

    $files | Invoke-ScriptAnalyzer -Settings $settingsPath -Fix:$Fix
}

function PSFormat {
    [CmdletBinding()]
    param(
        [string]$Path = '.'
    )

    $settingsPath = Join-Path $Path 'PSScriptAnalyzerSettings.psd1'
    if (-not (Test-Path $settingsPath)) {
        Write-Warning ("No PSScriptAnalyzerSettings.psd1 found at $settingsPath" +
            " - aborting to avoid reformatting with defaults.")
        return
    }

    $files = Get-ChildItem -Path $Path -Recurse -Include *.ps1, *.psm1, *.psd1 |
        Where-Object { $_.FullName -ne (Resolve-Path $settingsPath).Path }

    foreach ($file in $files) {
        $original = (Get-Content $file.FullName -Raw) -replace "`r`n?", "`n"
        try {
            $formatted = Invoke-Formatter -ScriptDefinition $original -Settings $settingsPath
        } catch {
            Write-Warning "Could not format $($file.FullName): $($_.Exception.Message)"
            continue
        }

        if ($original -ne $formatted) {
            Set-Content -Path $file.FullName -Value $formatted -Encoding utf8NoBOM -NoNewline
            Write-Host "Formatted: $($file.FullName)" -ForegroundColor Green
        }
    }
}


#region git

### Git Aliases/Utilities
function ginit() {
    git init
    git add .
    git commit -m "feat: initialize repository"
}

function glog() {
    git log --graph --pretty=format:'%Cred%h%Creset %an: %s - %Creset %C(yellow)%d%Creset %Cgreen(%cr)%Creset' `
        --abbrev-commit --date=relative
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

# region Cleanups
function Repair-UserPath {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ([string]::IsNullOrWhiteSpace($userPath)) { return }

    $paths = $userPath -split ';' | Where-Object { $_ -match '\S' }
    $validPaths = @()
    $changed = $false

    foreach ($path in $paths) {
        $expandedPath = [System.Environment]::ExpandEnvironmentVariables($path)

        if (Test-Path $expandedPath) {
            $validPaths += $path
        } else {
            $response = Read-Host "The path '$path' does not exist. Remove it from User PATH? (y/n)"
            if ($response -match '^[yY]') {
                Write-Host "Removing: $path" -ForegroundColor Yellow
                $changed = $true
            } else {
                $validPaths += $path
            }
        }
    }

    if ($changed) {
        $newPath = $validPaths -join ';'
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        Write-Host "User PATH updated successfully. (Please restart your terminal to see the changes)." `
            -ForegroundColor Green
    } else {
        Write-Host "No changes were made to User PATH." -ForegroundColor Cyan
    }
}

function Get-FolderSize {
    Get-ChildItem -Directory | ForEach-Object {
        $files = Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue
        $size = ($files | Measure-Object -Property Length -Sum).Sum
        $fmt = if ($size -ge 1GB) { "{0:N2} GB" -f ($size / 1GB) }
        elseif ($size -ge 1MB) { "{0:N2} MB" -f ($size / 1MB) }
        elseif ($size -ge 1KB) { "{0:N2} KB" -f ($size / 1KB) }
        else { "$size Bytes" }

        [PSCustomObject]@{ Folder = $_.Name; Size = $fmt; SizeBytes = $size }
    } | Sort-Object SizeBytes -Descending | Select-Object Folder, Size
}


function OrganizeFilesInDir {
    param(
        [string]$Path = $PWD
    )

    $imageExtensions = @('.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp', '.svg', '.ico', '.tiff', '.raw', '.heic')
    $documentExtensions = @(
        '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
        '.txt', '.csv', '.odt', '.ods', '.odp', '.md', '.rtf'
    )

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
        } elseif ($documentExtensions -contains $ext) {
            $destination = $documentsFolder
        } else {
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
# endregion

function Sync-TerminalConfig {
    [CmdletBinding()]
    param(
        [switch]$Reverse
    )

    $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $repoConfig = Join-Path $repoRoot '.config\windows-terminal.json'
    $wtJson = $env:WT_JSON

    if ([string]::IsNullOrWhiteSpace($wtJson)) {
        Write-Error "WT_JSON environment variable is not defined."
        return
    }

    try {
        if ($Reverse) {
            if (-not (Test-Path $wtJson)) {
                Write-Error "Source config not found at $wtJson"
                return
            }

            Write-Host "Syncing Terminal config to repo..." -ForegroundColor Cyan
            Write-Host "Source: $wtJson" -ForegroundColor Cyan
            Write-Host "Destination: $repoConfig" -ForegroundColor Cyan

            Copy-Item -Path $wtJson -Destination $repoConfig -Force -ErrorAction Stop
        } else {
            if (-not (Test-Path $repoConfig)) {
                Write-Error "Source config not found at $repoConfig"
                return
            }

            Write-Host "Syncing Windows Terminal config..." -ForegroundColor Cyan
            Write-Host "Source: $repoConfig" -ForegroundColor Cyan
            Write-Host "Destination: $wtJson" -ForegroundColor Cyan

            Copy-Item -Path $repoConfig -Destination $wtJson -Force -ErrorAction Stop
        }

        Write-Host "Sync complete." -ForegroundColor Green
    } catch {
        Write-Error "Sync failed: $($_.Exception.Message)"
    }
}

Set-Alias ofid -Value OrganizeFilesInDir
Set-Alias stexe -Value Get-ExePath
Set-Alias gfs -Value Get-FolderSize
Set-Alias sudo -Value gsudo
Set-Alias syncwt -Value Sync-TerminalConfig
