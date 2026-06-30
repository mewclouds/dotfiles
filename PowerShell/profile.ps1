# Load utilities script
if ($env:UTILITIES_PATH) {
	. $env:UTILITIES_PATH
} else {
	Write-Error "UTILITIES_PATH environment variable is not set. Please run pre-setup.ps1 first."
}

if (CommandExists fnm) {
	fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression
}

if (CommandExists fastfetch) {
	fastfetch
}

# Set the prompt to my liking
function prompt {
	mccoloring ("&n" +
		"&lp$(get-date -UFormat "%a %m-%d %H:%M") &l$($env:computername) &b$($env:USERNAME) &r$(pwdd)&n" +
		"> ")
}
