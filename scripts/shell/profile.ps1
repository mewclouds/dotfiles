# Load utilities script
if ($env:UTILITIES_PATH) {
    . $env:UTILITIES_PATH
} else {
    Write-Error "UTILITIES_PATH environment variable is not set. Please run preSetup.ps1 first."
}

if (CommandExists fnm) {
    fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression
}

if (CommandExists fastfetch) {
    fastfetch
}

if (CommandExists gsudo -and Get-Module -ListAvailable -Name "gsudoModule") {
    Import-Module "gsudoModule"
}

# Set the prompt to my liking
function prompt {
    mccoloring ("&n" +
        "&su3&su3$(Get-Date -UFormat "%a %m-%d %H:%M") &su1$($env:computername)" +
        "&su2@&su2$($env:USERNAME) &su1$(pwdd)&n" +
        "&su2> &r")
}
