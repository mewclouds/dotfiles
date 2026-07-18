$files = @(
    "install/bootstrap.ps1",
    "install/setup.ps1"
)

foreach ($file in $files) {
    $fullPath = Join-Path $PSScriptRoot $file
    if (Test-Path $fullPath) {
        $content = Get-Content -Path $fullPath -Raw
        Set-Content -Path $fullPath -Value $content -Encoding utf8BOM -NoNewline
        Write-Host "Re-encoded to UTF-8 BOM: $file" -ForegroundColor Green
    } else {
        Write-Warning "File not found: $file"
    }
}
