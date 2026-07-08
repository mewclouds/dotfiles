<#
.SYNOPSIS
Sets display resolution, refresh rate, and scaling.

.DESCRIPTION
Switching from iGPU to dGPU mode doesn't take into account the refresh rate
and other display settings (Windows 11 quirks), so this script automates the process.
This is triggered when the laptop is unplugged/plugged in.

.PARAMETER Mode
Specifies the mode. 'Normal' sets 240Hz, 'Quiet' sets 60Hz. Defaults to 'Normal'.
#>
[CmdletBinding()]
param(
    [ValidateSet('Normal', 'Quiet')]
    [string]$Mode = 'Normal'
)

$ErrorActionPreference = 'Stop'

# Set up logging
$LogDir = Join-Path $env:USERPROFILE 'runs\logs'
$LogFile = Join-Path $LogDir 'set-display.log'
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

function Write-BackupLog {
    param([string]$Message)
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $logLine = "[$timestamp] $Message"
    Add-Content -Path $LogFile -Value $logLine
}

$refresh = if ($Mode -eq 'Quiet') { 60 } else { 240 }
Write-BackupLog "Start $Mode mode ($refresh Hz)"

$regPath = "HKCU:\Control Panel\Desktop"

# LogPixels = 144 (150% scaling)
$logPixels = Get-ItemProperty -Path $regPath -Name "LogPixels" -ErrorAction SilentlyContinue
if ($logPixels.LogPixels -ne 144) {
    Write-BackupLog "Setting LogPixels=144"
    Set-ItemProperty -Path $regPath -Name "LogPixels" -Value 144 -Type DWord
} else {
    Write-BackupLog "LogPixels already 144"
}

# Win8DpiScaling = 1
$win8Dpi = Get-ItemProperty -Path $regPath -Name "Win8DpiScaling" -ErrorAction SilentlyContinue
if ($win8Dpi.Win8DpiScaling -ne 1) {
    Write-BackupLog "Setting Win8DpiScaling=1"
    Set-ItemProperty -Path $regPath -Name "Win8DpiScaling" -Value 1 -Type DWord
} else {
    Write-BackupLog "Win8DpiScaling already 1"
}

# Run nircmd
$nircmdPath = Get-Command nircmd -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
if (-not (Test-Path $nircmdPath)) {
    $nircmdPath = 'C:\nircmd\nircmd.exe'
}

if ($nircmdPath) {
    try {
        Write-BackupLog "Running nircmd: setdisplay 2560 1600 32 $refresh -updatereg"
        $nircmdArgs = @{
            FilePath = $nircmdPath
            ArgumentList = "setdisplay 2560 1600 32 $refresh -updatereg"
            Wait = $true
            NoNewWindow = $true
            PassThru = $true
        }
        $process = Start-Process @nircmdArgs
        if ($process.ExitCode -eq 0) {
            Write-BackupLog "nircmd success"
        } else {
            Write-BackupLog "nircmd failed with exit code $($process.ExitCode)"
        }
    } catch {
        Write-BackupLog "Failed to execute nircmd: $($_.Exception.Message)"
    }
} else {
    Write-BackupLog "Error: nircmd not found at C:\nircmd\nircmd.exe or in PATH"
}
