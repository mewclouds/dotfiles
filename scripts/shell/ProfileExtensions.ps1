<#
.SYNOPSIS
    Provides helper functions required by the PowerShell profile.

.DESCRIPTION
    This file is kept separate so the profile can load a small, reusable helper
    surface without importing the rest of the terminal utilities.
#>

function CommandExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    [bool](Get-Command $Command -ErrorAction SilentlyContinue)
}

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
