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

if ((CommandExists gsudo) -and (Get-Module -ListAvailable -Name 'gsudoModule')) {
    Import-Module 'gsudoModule'
}

if (CommandExists mise) {
    (& mise activate pwsh) | Out-String | Invoke-Expression
}

if (CommandExists fastfetch) {
    fastfetch
}

function Initialize-PSReadLine {
    if (-not (Get-Module -ListAvailable PSReadLine)) {
        return
    }

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

    # Colors mapped to Evergarden Skye palette
    Set-PSReadLineOption -Colors @{
        Command = '#B2CFED'
        Parameter = '#ADDEB9'
        Operator = '#F8F9E8'
        Variable = '#F3C0E5'
        String = '#CAE0A7'
        Number = '#F5D098'
        Type = '#B2CFED'
        Comment = '#96B4AA'
        Keyword = '#F3C0E5'
        Error = '#F57F82'
    }

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

function prompt {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $userPart = if ($isAdmin) { '&red@ADMIN' } else { "&sand@$($env:USERNAME)" }

    $gitPart = ''
    $insideGit = git rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -eq 0 -and $insideGit -eq 'true') {
        $branch = git rev-parse --abbrev-ref HEAD 2>$null
        if ($branch) {
            $isDirty = [bool](git status --porcelain 2>$null)
            $gitColor = if ($isDirty) { '&red' } else { '&leaf' }
            $gitPart = " $gitColor($branch)"
        }
    }

    mccoloring ("&n" +
        "&sun$(Get-Date -UFormat '%a %m-%d %H:%M') &sky$($env:COMPUTERNAME)" +
        "$userPart &ocean$(pwdd)$gitPart&n" +
        '&coral> &r')
}

if ($null -ne $PSStyle) {
    # This ensures that directories and parameters stay visible due to the theme applied
    $PSStyle.FileInfo.Directory = "`e[34;1m"
    $PSStyle.FileInfo.SymbolicLink = "`e[36;1m"
}

Initialize-PSReadLine

if (CommandExists zoxide) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}