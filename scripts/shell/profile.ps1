<#
.SYNOPSIS
    Configures the interactive PowerShell session for this repository.

.DESCRIPTION
    Loads the profile extensions beside this file, enables the tools used in the
    interactive shell, configures PSReadLine, and provides the custom prompt.
#>

if (-not [Environment]::UserInteractive -or
    [Console]::IsInputRedirected -or
    [Console]::IsOutputRedirected) {
    return
}

$profileDirectory = Split-Path -Parent $PROFILE
$profileExtensionsPath = Join-Path $profileDirectory 'ProfileExtensions.ps1'

if (-not (Test-Path $profileExtensionsPath -PathType Leaf)) {
    throw "Profile extensions were not found at $profileExtensionsPath."
}

. $profileExtensionsPath

# Optional private files
$privateProfilePath = Join-Path $profileDirectory 'PrivateProfile.ps1'
$privateExtensionsPath = Join-Path $profileDirectory 'PrivateProfileExtensions.ps1'

if (Test-Path $privateProfilePath -PathType Leaf) {
    . $privateProfilePath
}

if (Test-Path $privateExtensionsPath -PathType Leaf) {
    . $privateExtensionsPath
}

if (Get-Module -ListAvailable PSReadLine) {
    # Set basic options via splatting to avoid whitespace line continuation errors
    $psReadLineSettings = @{
        EditMode = 'Windows'
        HistoryNoDuplicates = $true
        HistorySearchCursorMovesToEnd = $true
        PredictionSource = 'HistoryAndPlugin'
        PredictionViewStyle = 'ListView'
        BellStyle = 'None'
        MaximumHistoryCount = 10000
    }
    Set-PSReadLineOption @psReadLineSettings

    # Key Handlers for navigation and history search
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    Set-PSReadLineKeyHandler -Chord 'Ctrl+z' -Function Undo
    Set-PSReadLineKeyHandler -Chord 'Ctrl+y' -Function Redo

    Set-PSReadLineOption -AddToHistoryHandler {
        param([string]$line)
        $line -notmatch '(?i)(password|secret|token|apikey|connectionstring)'
    }
}

if (CommandExists mise) {
    (& mise activate pwsh --shims) | Out-String | Invoke-Expression
}

if (CommandExists gsudo) {
    Import-Module 'gsudoModule' -ErrorAction SilentlyContinue
}

function prompt {
    $exitCode = $global:LASTEXITCODE

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $userPart = if ($isAdmin) { '&red@ADMIN' } else { "&sand@$($env:USERNAME)" }

    # .git is a directory in a clone and a file in a worktree or submodule.
    $inGit = $false
    if ($PWD.Provider.Name -eq 'FileSystem') {
        $directory = [IO.DirectoryInfo]$PWD.ProviderPath
        while ($directory) {
            $dotGit = Join-Path $directory.FullName '.git'
            if ([IO.Directory]::Exists($dotGit) -or [IO.File]::Exists($dotGit)) {
                $inGit = $true
                break
            }
            $directory = $directory.Parent
        }
    }

    $gitPart = ''
    if ($inGit) {
        $branchPrefix = '# branch.head '
        $status = git status --porcelain=v2 --branch 2>$null
        if ($LASTEXITCODE -eq 0) {
            $branch = $null
            $isDirty = $false
            foreach ($line in $status) {
                if ($line.StartsWith($branchPrefix)) {
                    $branch = $line.Substring($branchPrefix.Length)
                } elseif (-not $line.StartsWith('#')) {
                    $isDirty = $true
                    break
                }
            }
            if ($branch) {
                $gitColor = if ($isDirty) { '&red' } else { '&leaf' }
                $gitPart = " $gitColor($branch)"
            }
        }
    }

    $global:LASTEXITCODE = $exitCode

    mccoloring ("&n" +
        "&sun$(Get-Date -UFormat '%a %m-%d %H:%M') &sky$($env:COMPUTERNAME)" +
        "$userPart &ocean$(pwdd)$gitPart&n" +
        '&coral> &r')
}

# zoxide wraps $function:prompt, so it has to come after the definition above.
if (CommandExists zoxide) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}

if (CommandExists fastfetch) {
    fastfetch
}
