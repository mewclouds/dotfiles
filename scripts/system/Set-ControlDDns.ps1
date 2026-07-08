[CmdletBinding()]
param()

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]$identity
$adminRole = [Security.Principal.WindowsBuiltInRole]::Administrator
if (-not $principal.IsInRole($adminRole)) {
    Write-Host "Elevating privileges to apply DNS settings..." -ForegroundColor Yellow
    Start-Process pwsh -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$ips = @('76.76.2.2', '76.76.10.2', '2606:1a40::2', '2606:1a40:1::2')
$dohTemplate = "https://freedns.controld.com/p2"

Write-Host "Registering ControlD DoH Templates..." -ForegroundColor Cyan
foreach ($ip in $ips) {
    try {
        # Check if already exists to prevent duplicate errors
        $existing = Get-DnsClientDohServerAddress -ServerAddress $ip -ErrorAction SilentlyContinue
        if (-not $existing) {
            Add-DnsClientDohServerAddress -ServerAddress $ip -DohTemplate $dohTemplate `
                -AllowFallbackToUdp $false -AutoUpgrade $true -ErrorAction Stop
            Write-Host "  Registered DoH for $ip" -ForegroundColor Green
        } else {
            Write-Host "  DoH already registered for $ip" -ForegroundColor DarkGray
        }
    } catch {
        Write-Host "  Failed to register DoH for $($ip): $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`nApplying ControlD DNS to Wi-Fi adapter..." -ForegroundColor Cyan
$adapters = Get-NetAdapter | Where-Object { $_.Name -match "Wi-Fi|WiFi|Wireless|WLAN" }
if ($adapters) {
    foreach ($adapter in $adapters) {
        try {
            Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses $ips -ErrorAction Stop
            Write-Host "  Successfully applied DNS to adapter: $($adapter.Name)" -ForegroundColor Green

            # Flush DNS to ensure immediate effect
            Clear-DnsClientCache
            Write-Host "  Flushed DNS cache." -ForegroundColor Green
        } catch {
            Write-Host "  Failed to set DNS on $($adapter.Name): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
} else {
    Write-Host "No Wi-Fi adapter found." -ForegroundColor Yellow
}

Write-Host "`nDNS configuration complete! Press any key to close." -ForegroundColor Cyan
[Console]::ReadKey() | Out-Null
