if ($PSVersionTable.PSVersion.Major -lt 7) {
	throw "PowerShell 7 or later is required. Please run this with pwsh."
}

Add-Type -AssemblyName System.Windows.Forms

function Get-FolderSelection {
	param(
		[string]$VarName,
		[string]$Prompt
	)

	$current = [Environment]::GetEnvironmentVariable($VarName, 'User')
	if ($current) {
		Write-Host "$VarName is currently set to: $current" -ForegroundColor Cyan
		$reply = Read-Host "Change this path? (y/N)"
		if ($reply -ne 'y') { return }
	}

	Write-Host "`n$Prompt" -ForegroundColor Yellow
	$browser = New-Object System.Windows.Forms.FolderBrowserDialog
	$browser.Description = $Prompt
	$browser.ShowNewFolderButton = $true

	if ($browser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
		[Environment]::SetEnvironmentVariable($VarName, $browser.SelectedPath, 'User')
		Write-Host "Set $VarName to $($browser.SelectedPath)" -ForegroundColor Green
	}
 else {
		Write-Host "Skipped $VarName" -ForegroundColor DarkYellow
	}
}

function Get-FileSelection {
	param(
		[string]$VarName,
		[string]$Prompt,
		[string]$Filter = 'All Files (*.*)|*.*'
	)

	$current = [Environment]::GetEnvironmentVariable($VarName, 'User')
	if ($current) {
		Write-Host "$VarName is currently set to: $current" -ForegroundColor Cyan
		$reply = Read-Host "Change this path? (y/N)"
		if ($reply -ne 'y') { return }
	}

	Write-Host "`n$Prompt" -ForegroundColor Yellow
	$browser = New-Object System.Windows.Forms.OpenFileDialog
	$browser.Title = $Prompt
	$browser.Filter = $Filter

	if ($browser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
		[Environment]::SetEnvironmentVariable($VarName, $browser.FileName, 'User')
		Write-Host "Set $VarName to $($browser.FileName)" -ForegroundColor Green
	}
 else {
		Write-Host "Skipped $VarName" -ForegroundColor DarkYellow
	}
}

Write-Host "Configuring dotfiles environment variables..." -ForegroundColor Cyan

Get-FileSelection -VarName 'WT_JSON' -Prompt 'Select your Windows Terminal settings.json' -Filter 'JSON Files (*.json)|*.json'
Get-FolderSelection -VarName 'MR_MODS_PATH' -Prompt 'Select your MR Mods directory'
Get-FolderSelection -VarName 'MR_MODS_BACKUP' -Prompt 'Select your MR Mods backup directory'

Write-Host "`nConfiguration state:" -ForegroundColor Cyan
$vars = @('WT_JSON', 'MR_MODS_PATH', 'MR_MODS_BACKUP')
$allGood = $true

foreach ($v in $vars) {
	$val = [Environment]::GetEnvironmentVariable($v, 'User')
	if ($val) {
		Write-Host "  $v = $val"
	}
 else {
		Write-Host "  $v = NOT SET" -ForegroundColor Red
		$allGood = $false
	}
}

if ($allGood) {
	Write-Host "`nReady to run setup.ps1." -ForegroundColor Green
}
else {
	Write-Host "`nMissing environment variables. Please configure all variables before running setup.ps1." -ForegroundColor Yellow
}
