# ── Variables ─────────────────────────────────────────────────────────────────
$PSScriptRoot = if ($env:SETUP_WORKDIR) { $env:SETUP_WORKDIR } else { (Get-Location).Path }

$customDomain  = $env:TARGET_URL -replace '^https?://', '' -replace '/$', ''
$cleanHostname = $customDomain -split '/' | Select-Object -First 1
$baseDomain    = $cleanHostname -replace '^www\.', ''
$wwwDomain     = "www.$baseDomain"

$hostsPath = "$env:windir\System32\drivers\etc\hosts"
$XamppInstallDir = $env:XAMPP_DIR

$apachePath = "$XamppInstallDir/apache"
$htdocsPath = "$XamppInstallDir/htdocs"

$documentRoot = "$htdocsPath/webapp"
# ──────────────────────────────────────────────────────────────────────────────

if ($customDomain -notlike "www.*") { $customDomain = "www.$customDomain"; }
if (!(Test-Path "$documentRoot")) {
    Write-Host "`[3.ps1:XAMPP-fetch] could not locate the project: $documentRoot" -ForegroundColor Red; Exit 1;
}

Write-Host "[2.ps1:HOST] setting up host file patches for $baseDomain" -ForegroundColor Cyan
$entries = @("127.0.0.1`t$baseDomain", "127.0.0.1`t$wwwDomain")
foreach ($entry in $entries) {
    Write-Host "[2.ps1:HOST-add] proceeding to add $domainOnly to the host file." -ForegroundColor Cyan
    $domainOnly = $entry -split "`t" | Select-Object -Last 1
    if (!(Select-String -Path $hostsPath -Pattern ([regex]::Escape($domainOnly)) -Quiet)) {
        try {
            Write-Host "[2.ps1:HOST-add] adding..." -ForegroundColor Yellow
            Add-Content -Path $hostsPath -Value "`r`n$entry" -ErrorAction Stop
            Write-Host "[2.ps1:HOST-add] added $domainOnly" -ForegroundColor Green
        } 
        catch {
            Write-Host "[2.ps1:HOST-alert] the host file is locked, most likely in-use by other applications." -ForegroundColor Red
            $choice = Read-Host "Proceed with backup and force-addition of $domainOnly to the host file? [y/n]:" -ForegroundColor Yellow
            if ($choice -eq 'Y' -or $choice -eq 'y') {
                try {
                    Write-Host "[2.ps1:HOST-backup] creating a backup..." -ForegroundColor Yellow
                    $backupPath = "$hostsPath.backup"; $currentContent = Get-Content -Path $hostsPath -Raw;
                    $updatedContent = $currentContent.TrimEnd() + "`r`n$entry"
                    if (Test-Path $backupPath) { Remove-Item $backupPath -Force }
                    Rename-Item -Path $hostsPath -NewName "hosts.backup" -Force
                    Write-Host "[2.ps1:HOST-backup] backup created." -ForegroundColor Green
                    Write-Host "[2.ps1:HOST-update] updating host file with new content..." -ForegroundColor Yellow
                    $updatedContent | Out-File -FilePath $hostsPath -Encoding ASCII
                    Write-Host "[2.ps1:HOST-update] successfully updated." -ForegroundColor Green
                } catch { Write-Host "[2.ps1:HOST-lock] hard lock detected, close programs and try again." -ForegroundColor Red; }
            }
        }
    } else { Write-Host "[2.ps1:HOST-skip] $domainOnly is already in the host file." -ForegroundColor Yellow; }
}

$httpdConfPath = "$apachePath\conf\httpd.conf"
if (Test-Path $httpdConfPath) {
    Write-Host "[2.ps1:APACHE-httpd] ensuring vhosts is enabled..." -ForegroundColor Yellow
    (Get-Content $httpdConfPath) -replace "^#\s*(Include conf/extra/httpd-vhosts.conf)", "`$1" | Set-Content $httpdConfPath
    Write-Host "[2.ps1:APACHE-httpd] vhosts are enabled." -ForegroundColor Green
}

$vhostsPath = "$apachePath\conf\extra\httpd-vhosts.conf"
$localhostFallback = @"
<VirtualHost *:80>
    DocumentRoot `"$htdocsPath`"
    ServerName localhost
</VirtualHost>
"@
$vhostConfig = @"

# Custom Domain Automator: $baseDomain
<VirtualHost *:80>
    DocumentRoot `"$documentRoot`"
    ServerName $baseDomain
    ServerAlias $wwwDomain
    <Directory `"$documentRoot`">
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
"@
if (Test-Path $vhostsPath) {
    Write-Host "[2.ps1:VHOST-add] adding fallback-config..." -ForegroundColor Yellow
    if (!(Select-String -Path $vhostsPath -Pattern "ServerName localhost" -Quiet)) {
        Add-Content -Path $vhostsPath -Value $localhostFallback
    }
    Write-Host "[2.ps1:VHOST-add] added fallback-config." -ForegroundColor Green
    Write-Host "[2.ps1:VHOST-add] adding $baseDomain config..." -ForegroundColor Yellow
    if (!(Select-String -Path $vhostsPath -Pattern "ServerName $baseDomain" -Quiet)) {
        Add-Content -Path $vhostsPath -Value $vhostConfig
        Write-Host "[2.ps1:VHOST-add] added $baseDomain (with www alias)." -ForegroundColor Green
    } else { Write-Host "[2.ps1:VHOST-skip] vhost config for $baseDomain already exists." -ForegroundColor Yellow; }
} else { Write-Host "[2.ps1:VHOST-error] could not locate httpd-vhosts.conf at: $vhostsPath" -ForegroundColor Red; Exit 1; }

Write-Host "[2.ps1:SYSTEM-dns] flushing dns cache..." -ForegroundColor Yellow
Clear-DnsClientCache
Write-Host "[2.ps1:SYSTEM-dns] flush successful" -ForegroundColor Green

Write-Host "[0.ps1:XAMPP-apache] apache restart required, restarting..." -ForegroundColor Cyan
$ApacheService = Get-Service | Where-Object { $_.Name -like "Apache*" }
if ($ApacheService) {
    Write-Host "[0.ps1:XAMPP-apache] found service, restarting..." -ForegroundColor Yellow
    try {
        Restart-Service -Name $ApacheService.Name -Force -ErrorAction SilentlyContinue
        Write-Host "[0.ps1:XAMPP-apache] service restarted." -ForegroundColor Green
    } catch { Write-Host "[0.ps1:XAMPP-apache] failed to restart service, manually attempting to restart..." -ForegroundColor Yellow; }
} else {
    $HttpdPath = Join-Path -Path $XamppInstallDir -ChildPath "apache\bin\httpd.exe"
    if (Test-Path $HttpdPath) {
        Write-Host "[0.ps1:XAMPP-apache] service not found, restarting via executable..." -ForegroundColor Yellow
        Get-Process "httpd" -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 1
        Start-Process -FilePath $HttpdPath -WindowStyle Hidden
        Write-Host "[0.ps1:XAMPP-apache] process restarted." -ForegroundColor Green
    } else {
        Write-Host "[0.ps1:XAMPP-apache] could not locate httpd.exe at $HttpdPath" -ForegroundColor Red
    }
}