# Load utilities script
if ($env:UTILITIES_PATH) {
    . $env:UTILITIES_PATH
} else {
    Write-Error "UTILITIES_PATH environment variable is not set. Please run preSetup.ps1 first."
}

# Load node version manager if available
if (CommandExists fnm) {
    fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression
}

# Import elevation tools if available
if (CommandExists gsudo -and Get-Module -ListAvailable -Name "gsudoModule") {
    Import-Module "gsudoModule"
}

# Customize PSStyle file listing colors (remove directory background blocks for readability)
if ($null -ne $PSStyle) {
    $PSStyle.FileInfo.Directory = "`e[34;1m"
    $PSStyle.FileInfo.SymbolicLink = "`e[36;1m"
}

function Initialize-PSReadLine {
    if (-not (Get-Module -ListAvailable PSReadLine)) {
        return
    }

    # Set basic options via splatting to avoid whitespace line continuation errors
    $psReadLineSettings = @{
        EditMode                      = 'Windows'
        HistoryNoDuplicates           = $true
        HistorySearchCursorMovesToEnd = $true
        PredictionSource              = 'HistoryAndPlugin'
        PredictionViewStyle           = 'ListView'
        BellStyle                     = 'None'
        MaximumHistoryCount           = 10000
    }
    Set-PSReadLineOption @psReadLineSettings

    # Colors mapped to Evergarden Skye palette
    Set-PSReadLineOption -Colors @{
        Command   = '#B2CFED' # Light blue
        Parameter = '#ADDEB9' # Mint/cyan
        Operator  = '#F8F9E8' # Cream white
        Variable  = '#F3C0E5' # Pink/purple
        String    = '#CAE0A7' # Sage green
        Number    = '#F5D098' # Peach/yellow
        Type      = '#B2CFED' # Light blue
        Comment   = '#96B4AA' # Sage gray
        Keyword   = '#F3C0E5' # Pink/purple
        Error     = '#F57F82' # Soft red
    }

    # Key Handlers for navigation and history search
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    Set-PSReadLineKeyHandler -Chord 'Ctrl+z' -Function Undo
    Set-PSReadLineKeyHandler -Chord 'Ctrl+y' -Function Redo

    # Prevent secrets from entering history
    Set-PSReadLineOption -AddToHistoryHandler {
        param([string]$line)
        $line -notmatch '(?i)(password|secret|token|apikey|connectionstring)'
    }
}

function Register-CustomCompletion {
    # Setup tab-completion for Bun (suggests custom project scripts only)
    Register-ArgumentCompleter -Native -CommandName bun -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $null = $commandAst
        $null = $cursorPosition
        $scripts = @('dev', 'build', 'start', 'lint', 'lint:fix', 'format', 'format:fix')
        $scripts |
            Where-Object { $_ -like "$wordToComplete*" } |
            ForEach-Object {
                [System.Management.Automation.CompletionResult]::new(
                    $_, $_, 'ParameterValue', $_
                )
            }
    }

    # Setup tab-completion for NPM (suggests core lifecycle scripts)
    Register-ArgumentCompleter -Native -CommandName npm -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $null = $commandAst
        $null = $cursorPosition
        $core = @('install', 'start', 'run', 'test', 'build')
        $core |
            Where-Object { $_ -like "$wordToComplete*" } |
            ForEach-Object {
                [System.Management.Automation.CompletionResult]::new(
                    $_, $_, 'ParameterValue', $_
                )
            }
    }
}

# Set the prompt to my liking
function prompt {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    $userPart = if ($isAdmin) { "&red@ADMIN" } else { "&sand@$($env:USERNAME)" }

    mccoloring ("&n" +
        "&sun$(Get-Date -UFormat "%a %m-%d %H:%M") &sky$($env:computername)" +
        "$userPart &ocean$(pwdd)&n" +
        "&coral> &r")
}

# Run initialization
Initialize-PSReadLine
Register-CustomCompletion
