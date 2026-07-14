# Load utilities script
if ($env:UTILITIES_PATH) {
    . $env:UTILITIES_PATH
} else {
    Write-Error "UTILITIES_PATH environment variable is not set. Please run preSetup.ps1 first."
}

if (CommandExists fnm) {
    fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression
}

#if (CommandExists fastfetch) {
#fastfetch
#}

if (CommandExists gsudo -and Get-Module -ListAvailable -Name "gsudoModule") {
    Import-Module "gsudoModule"
}

# Set the prompt to my liking
function prompt {
    $isAdmin = [bool]([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )

    $userPart = if ($isAdmin) { "&red@ADMIN" } else { "&sand@$($env:USERNAME)" }

    mccoloring ("&n" +
        "&sun$(Get-Date -UFormat "%a %m-%d %H:%M") &sky$($env:computername)" +
        "$userPart &ocean$(pwdd)&n" +
        "&coral> &r")
}
