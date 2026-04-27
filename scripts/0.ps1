# ── Variables ─────────────────────────────────────────────────────────────────
$PSScriptRoot = if ($env:SETUP_WORKDIR) { $env:SETUP_WORKDIR } else { (Get-Location).Path }

$customDomain  = $env:TARGET_URL -replace '^https?://', '' -replace '/$', ''
$cleanHostname = $customDomain -split '/' | Select-Object -First 1
$baseDomain    = $cleanHostname -replace '^www\.', ''
$wwwDomain     = "www.$baseDomain"

$XamppInstallDir = $env:XAMPP_DIR
# ──────────────────────────────────────────────────────────────────────────────

$hostsPath = "$env:windir\System32\drivers\etc\hosts"
$vhostsPath = "$XamppInstallDir\apache\conf\extra\httpd-vhosts.conf"
Write-Host "[0.ps1:SYSTEM] system checkup for $baseDomain..." -ForegroundColor Cyan
if (Test-Path $hostsPath) {
    $hostsContent = Get-Content -Path $hostsPath
    $newHostsContent = $hostsContent | Where-Object { $_ -notmatch [regex]::Escape($baseDomain) }
    $newHostsContent | Out-File -FilePath $hostsPath -Encoding ASCII -Force
    Write-Host "[0.ps1:SYSTEM-success] sanitized $baseDomain entries from the hosts file." -ForegroundColor Green
}
if (Test-Path $vhostsPath) {
    $vhostsContent = Get-Content -Path $vhostsPath -Raw
    $pattern = "(?s)# Custom Domain Automator: $baseDomain.*?<VirtualHost \*:80>.*?</VirtualHost>\s*"
    if ($vhostsContent -match $pattern) {
        $newVhostsContent = $vhostsContent -replace $pattern, ""
        $newVhostsContent | Out-File -FilePath $vhostsPath -Encoding ASCII -Force
        Write-Host "[0.ps1:SYSTEM-sucess] sanitized 'Virtual-Host' block from httpd-vhosts.conf." -ForegroundColor Green
    } else {
        Write-Host "[0.ps1:SYSTEM-skip] no contaminations in 'Virtual-Host' block." -ForegroundColor Yellow
    }
}

Write-Host "[0.ps1:SYSTEM-dns] flushing dns cache..." -ForegroundColor Cyan
Clear-DnsClientCache
Write-Host "[0.ps1:SYSTEM-dns] flush successful" -ForegroundColor Green

$ApacheService = Get-Service | Where-Object { $_.Name -like "Apache*" }
Write-Host "[0.ps1:XAMPP-apache] apache restart required, restarting..." -ForegroundColor Cyan
if ($ApacheService) {
    Restart-Service -Name $ApacheService.Name -Force -ErrorAction SilentlyContinue
    Write-Host "[0.ps1:XAMPP-apache] service restarted." -ForegroundColor Green
} else {
    $HttpdPath = Join-Path -Path $XamppInstallDir -ChildPath "apache\bin\httpd.exe"
    if (Test-Path $HttpdPath) {
        Get-Process "httpd" -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 1
        Start-Process -FilePath $HttpdPath -WindowStyle Hidden
        Write-Host "[0.ps1:XAMPP-apache] process restarted." -ForegroundColor Green
    }
}

Write-Host "[0.ps1:message] system sanitized" -ForegroundColor Green