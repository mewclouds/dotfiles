function CommandExists {
    param ($command)
    $preference = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try { if (Get-Command $command) { return $true } }
    catch { Write-Host "$command does not exist"; return $false }
    finally { $ErrorActionPreference = $preference }
}

# Invokes an admin window in the current dir
function su {
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
function rmh() { Remove-Item (Get-PSReadLineOption).HistorySavePath }

# Compute file hashes
function sha256 { Get-FileHash -Algorithm SHA256 $args }

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

    Get-ChildItem -Path $Path -Recurse -Include *.ps1, *.psm1, *.psd1 | ForEach-Object {
        $original = Get-Content $_.FullName -Raw
        $formatted = Invoke-Formatter -ScriptDefinition $original -Settings $settingsPath
        if ($original -ne $formatted) {
            Set-Content -Path $_.FullName -Value $formatted -NoNewline
            Write-Host "Formatted: $($_.FullName)" -ForegroundColor Green
        }
    }
}

function PSBuild {
    [CmdletBinding()]
    param(
        [string]$Path = '.'
    )

    $files = Get-ChildItem -Path $Path -Include *.ps1, *.psm1, *.psd1 -Recurse
    $definedCmds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    # Pre-populate with all known system commands
    Get-Command -ErrorAction SilentlyContinue | ForEach-Object { $null = $definedCmds.Add($_.Name) }

    # Pass 1: Extract all dynamically defined functions and aliases across the repo
    foreach ($file in $files) {
        $errs = $null; $tokens = $null;
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errs)
        if ($ast) {
            $funcs = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
            foreach ($f in $funcs) { $null = $definedCmds.Add($f.Name) }

            $aliases = $ast.FindAll({
                    $args[0] -is [System.Management.Automation.Language.CommandAst] -and
                    $args[0].GetCommandName() -eq 'Set-Alias'
                }, $true)
            foreach ($a in $aliases) {
                $nameParam = $a.CommandElements |
                    Where-Object { $_ -is [System.Management.Automation.Language.StringConstantExpressionAst] } |
                    Select-Object -First 1
                if ($nameParam) { $null = $definedCmds.Add($nameParam.Value) }
            }
        }
    }

    # Pass 2: Syntax check and unknown command check
    $errorsTotal = 0
    $warningsTotal = 0

    foreach ($file in $files) {
        $errs = $null; $tokens = $null;
        [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errs)

        if ($errs) {
            Write-Host "[ERROR] $($file.Name) has syntax errors:" -ForegroundColor Red
            $errs | ForEach-Object {
                Write-Host "  Line $($_.Extent.StartLineNumber): $($_.Message)"
            }
            $errorsTotal += $errs.Count
        }

        # Check for unknown commands (limit to verb-noun or standard dotfiles tools to reduce noise)
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errs)
        if ($ast) {
            $cmds = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)
            foreach ($cmd in $cmds) {
                $name = $cmd.GetCommandName()
                # Flag if it has a hyphen (like a cmdlet) but isn't known, ignoring paths/variables
                if ($name -match '-' -and -not $definedCmds.Contains($name) -and
                    $name -notmatch '^\w:\\' -and $name -notmatch '^\.') {
                    Write-Host "[WARNING] $($file.Name):$($cmd.Extent.StartLineNumber) Unknown command '$name'" `
                        -ForegroundColor Yellow
                    $warningsTotal++
                }
            }
        }
    }

    if ($errorsTotal -eq 0 -and $warningsTotal -eq 0) {
        Write-Host "All scripts parsed successfully! (0 syntax errors, 0 unknown functions)" -ForegroundColor Green
    } else {
        Write-Host "Found $errorsTotal syntax errors and $warningsTotal unknown functions." -ForegroundColor Yellow
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
    $dirSizes = @{}
    $files = Get-ChildItem -Recurse -File -Force -ErrorAction SilentlyContinue
    if ($null -ne $files) {
        foreach ($file in $files) {
            $parent = $file.DirectoryName
            while ($parent -and $parent -like "$($PWD.Path)*") {
                $dirSizes[$parent] = [long]($dirSizes[$parent]) + $file.Length
                $parent = Split-Path -Path $parent -Parent
            }
        }
    }

    $results = Get-ChildItem -Recurse -Directory | ForEach-Object {
        $size = if ($dirSizes.Contains($_.FullName)) { $dirSizes[$_.FullName] } else { 0 }
        $formattedSize = if ($size -ge 1GB) {
            "{0:N2} GB" -f ($size / 1GB)
        } elseif ($size -ge 1MB) {
            "{0:N2} MB" -f ($size / 1MB)
        } elseif ($size -ge 1KB) {
            "{0:N2} KB" -f ($size / 1KB)
        } else {
            "$size Bytes"
        }

        [PSCustomObject]@{
            Folder = (Resolve-Path -Relative $_.FullName) -replace '^\.\\', ''
            SizeRaw = $size
            Size = $formattedSize
        }
    } | Sort-Object SizeRaw -Descending

    $maxLen = 20
    foreach ($item in $results) {
        if ($item.Folder.Length -gt $maxLen) { $maxLen = $item.Folder.Length }
    }
    if ($maxLen -gt 80) { $maxLen = 80 }
    $padding = $maxLen + 2

    $dashLine = "-" * ($padding + 15)

    # Styled header
    Write-Host ""
    Write-Host "*~* Folder Sizes *~*" -ForegroundColor Yellow
    Write-Host $dashLine -ForegroundColor Cyan
    Write-Host ("{0,-$padding}" -f 'Folder') -NoNewline -ForegroundColor Yellow
    Write-Host "Size" -ForegroundColor Green
    Write-Host $dashLine -ForegroundColor Cyan

    foreach ($item in $results) {
        $folderName = if ($item.Folder.Length -gt $maxLen) {
            $item.Folder.Substring(0, $maxLen - 3) + "..."
        } else {
            $item.Folder
        }
        Write-Host ("{0,-$padding}" -f $folderName) -NoNewline
        Write-Host $item.Size -ForegroundColor Green
    }

    # Sum all files to get the grand total
    $totalRaw = 0
    if ($null -ne $files) {
        foreach ($file in $files) {
            $totalRaw += $file.Length
        }
    }

    $totalFormatted = if ($totalRaw -ge 1GB) {
        "{0:N2} GB" -f ($totalRaw / 1GB)
    } elseif ($totalRaw -ge 1MB) {
        "{0:N2} MB" -f ($totalRaw / 1MB)
    } elseif ($totalRaw -ge 1KB) {
        "{0:N2} KB" -f ($totalRaw / 1KB)
    } else {
        "$totalRaw Bytes"
    }

    Write-Host $dashLine -ForegroundColor Cyan
    Write-Host ("{0,-$padding}" -f 'Total Current Directory:') -NoNewline -ForegroundColor Red
    Write-Host $totalFormatted -ForegroundColor Yellow
    Write-Host ""
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
    $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $source = Join-Path $repoRoot '.config\windows-terminal.json'
    $destination = $env:WT_JSON

    if (-not (Test-Path $source)) {
        Write-Error "Source config not found at $source"
        return
    }

    if ([string]::IsNullOrWhiteSpace($destination)) {
        Write-Error "WT_JSON environment variable is not defined."
        return
    }

    Write-Host "Syncing Windows Terminal config..." -ForegroundColor Cyan
    Write-Host "Source: $source" -ForegroundColor DarkGray
    Write-Host "Destination: $destination" -ForegroundColor DarkGray

    # Construct the command string directly with variables expanded
    $cmd = "Start-Sleep -Seconds 1; " +
    "Stop-Process -Name 'WindowsTerminal' -Force -ErrorAction SilentlyContinue; " +
    "Stop-Process -Name 'wt' -Force -ErrorAction SilentlyContinue; " +
    "Start-Sleep -Milliseconds 500; " +
    "Copy-Item -Path '$source' -Destination '$destination' -Force; " +
    "Start-Process -FilePath 'wt.exe'"

    $pwshExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }
    $startArgs = @{
        FilePath = $pwshExe
        ArgumentList = @(
            "-NoProfile",
            "-WindowStyle", "Hidden",
            "-Command", $cmd
        )
        NoNewWindow = $false
    }
    Start-Process @startArgs
    Write-Host "Sync initiated in the background. Windows Terminal will restart shortly." -ForegroundColor Green
}

Set-Alias ofid -Value OrganizeFilesInDir
Set-Alias stexe -Value Get-ExePath
Set-Alias gfs -Value Get-FolderSize
Set-Alias sudo -Value gsudo
Set-Alias syncwt -Value Sync-TerminalConfig
