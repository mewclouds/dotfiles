<#
.SYNOPSIS
    Provides helper functions required by the PowerShell profile.

.DESCRIPTION
    This file is kept separate so the profile can load a small, reusable helper
    surface without importing the rest of the terminal utilities.
#>

#region shellutils

function CommandExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    [bool](Get-Command $Command -ErrorAction SilentlyContinue)
}

# Open the current directory in the file explorer
function here() { Invoke-Item . }

# Unix-like which command
function which($name) { Get-Command $name | Select-Object -ExpandProperty Definition }

# Unix-like touch command
function touch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
        [string[]]$Path
    )

    foreach ($file in $Path) {
        if (Test-Path -LiteralPath $file) {
            (Get-Item -LiteralPath $file).LastWriteTime = [DateTime]::Now
        } else {
            New-Item -ItemType File -Path $file -Force | Out-Null
        }
    }
}

# Easily go to home DIR
function ~ { Set-Location $HOME }

# Invokes an admin window in the current dir
function su {
    Start-Process wt -ArgumentList "-d `"$PWD`"" -Verb RunAs
}

# Clear the console and history
function rmh() { Remove-Item (Get-PSReadLineOption).HistorySavePath }

# Force sync WT config with reverse syncing
function Sync-TerminalConfig {
    [CmdletBinding()]
    param(
        [switch]$Reverse
    )

    $repoRoot = Join-Path $HOME 'dotfiles'
    $repoConfig = Join-Path $repoRoot '.config\windows-terminal.json'
    $wtJson = "$($env:LOCALAPPDATA)/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"

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

#endregion

#region gitutils

function glog {
    git log --graph --pretty=format:'%Cred%h%Creset %an: %s - %Creset %C(yellow)%d%Creset %Cgreen(%cr)%Creset' `
        --abbrev-commit --date=relative
}

function gst() { git status -sb }

# Undoes the last commit, keeping its changes staged
function gundo { git reset --soft HEAD~1 }

# Hard-resets the working tree, discarding uncommitted changes
function greset {
    param(
        [string]$Ref = 'HEAD'
    )

    git reset --hard $Ref
}

# Restages current changes into the last commit without changing its message
function gamend { git commit --amend --no-edit }

# Lists local branches by most recently committed, with upstream tracking info
function gbranches { git branch -vv --sort=-committerdate }

# Stashes changes, including untracked files
function gstash { git stash push -u }

# Switches to an existing branch, or creates it if it doesn't exist yet
function gco {
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
        [string[]]$Name
    )

    $branch = $Name -join ' '
    if (git show-ref --verify --quiet "refs/heads/$branch") {
        git switch $branch
    } else {
        git switch -c $branch
    }
}

#endregion

# region sysutils
function syshealth {
    $checks = 'sfc /scannow; DISM /Online /Cleanup-Image /CheckHealth; ' +
    'DISM /Online /Cleanup-Image /ScanHealth'
    gsudo pwsh -NoProfile -Command $checks
}

# Compute file hashes, or compare a hash when one is provided
function sha256 {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [string]$ExpectedHash
    )

    $hash = (Get-FileHash -Algorithm SHA256 -Path $Path).Hash
    if ($PSBoundParameters.ContainsKey('ExpectedHash')) {
        return $hash -ieq $ExpectedHash
    }

    $hash
}
#endregion


#region promptutils

function pwdd {
    "$PWD".Replace($HOME, '~')
}

function mccoloring {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $escape = [char]27
    $coloredText = "$Text&r"

    $coloredText = $coloredText.Replace('&ocean', "$escape[38;2;194;223;255m")
    $coloredText = $coloredText.Replace('&sky', "$escape[38;2;194;242;231m")
    $coloredText = $coloredText.Replace('&coral', "$escape[38;2;248;200;237m")
    $coloredText = $coloredText.Replace('&sand', "$escape[38;2;250;219;176m")
    $coloredText = $coloredText.Replace('&sun', "$escape[38;2;252;219;168m")
    $coloredText = $coloredText.Replace('&leaf', "$escape[38;2;220;242;188m")
    $coloredText = $coloredText.Replace('&cloud', "$escape[38;2;251;252;235m")
    $coloredText = $coloredText.Replace('&red', "$escape[38;2;255;151;154m")

    $coloredText = $coloredText.Replace('&r', "$escape[0m")
    $coloredText.Replace('&n', "`r`n")
}
#endregion

#region winutil

function winutil {
    Invoke-RestMethod https://christitus.com/win | Invoke-Expression
}

function winutildev {
    Invoke-RestMethod https://christitus.com/windev | Invoke-Expression
}

#endregion


#region Aliases
Set-Alias syncwt -Value Sync-TerminalConfig
#endregion
