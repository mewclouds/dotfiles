$env:UTILITIES_PATH = $env:USERPROFILE + "\dotfiles\PowerShell\TerminalUtilities.ps1"

# Load utilities script
.$env:UTILITIES_PATH

if (CommandExists fnm) {
	fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression
}

if (CommandExists fastfetch) {
	fastfetch
}

# Set the prompt to my liking
function prompt {
	mccoloring ("&n" +
		"&lp$(get-date -UFormat \"%a %m-%d %H:%M\") &l$($env:computername) &b$($env:USERNAME) &r$(pwdd)&n" +
		"> ")
}
