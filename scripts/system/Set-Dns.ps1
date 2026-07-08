#Requires -RunAsAdministrator

[CmdletBinding()]
param()

Write-Host "Fetching DNS configuration from Bitwarden (MochiDNS)..." -ForegroundColor Cyan
$bwNote = & bw get notes MochiDNS 2>&1
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($bwNote)) {
    throw "Failed to fetch MochiDNS from Bitwarden. Are you logged in and synced?"
}

$ipv4Match = [regex]::Match($bwNote, 'IPv4 \((.*?)\)')
$ipv6Match = [regex]::Match($bwNote, 'IPv6 \((.*?)\)')
$dohMatch = [regex]::Match($bwNote, 'DoH \((.*?)\)')

if (-not $ipv4Match.Success -or -not $dohMatch.Success -or -not $ipv6Match.Success) {
    throw "Failed to parse MochiDNS formatting. Expected 'IPv4 (...)', 'IPv6 (...)' and 'DoH (...)'. Found: $bwNote"
}

$ips = [System.Collections.Generic.List[string]]::new()
$ipv4Match.Groups[1].Value -split ',' | ForEach-Object { $ips.Add($_.Trim()) }
$ipv6Match.Groups[1].Value -split ',' | ForEach-Object { $ips.Add($_.Trim()) }

$dohTemplate = $dohMatch.Groups[1].Value.Trim()

Write-Host "Registering DoH Templates..." -ForegroundColor Cyan
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

Write-Host "`nApplying DNS to Wi-Fi and Ethernet adapters..." -ForegroundColor Cyan
$adapters = Get-NetAdapter | Where-Object { $_.Name -match "Wi-Fi|WiFi|Wireless|WLAN|Ethernet" }
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
    Write-Host "No Wi-Fi or Ethernet adapter found." -ForegroundColor Yellow
}

Write-Host "`nDNS configuration complete! Press any key to close." -ForegroundColor Cyan
[Console]::ReadKey() | Out-Null
