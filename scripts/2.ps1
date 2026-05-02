# ── Module ────────────────────────────────────────────────────────────────────
$_repoBase = "https://raw.githubusercontent.com/ketw/hostnet/main"
$_hnModule = Join-Path $env:TEMP "hn.psm1"
if (-not (Test-Path $_hnModule)) {
    Invoke-RestMethod -Uri "$_repoBase/modules/hn.psm1" -OutFile $_hnModule -Headers @{ "User-Agent" = "Mozilla/5.0" }
}
Import-Module $_hnModule -Force -DisableNameChecking
# ──────────────────────────────────────────────────────────────────────────────

# ── Variables ─────────────────────────────────────────────────────────────────
$workDir = if ($env:SETUP_WORKDIR) { $env:SETUP_WORKDIR } else { (Get-Location).Path }

$uri           = [System.Uri]$env:TARGET_URL
$baseDomain    = ($uri.Host -replace '^www\.', '')
$wwwDomain     = "www.$baseDomain"
$subPath       = $uri.AbsolutePath.Trim('/')

$hostsPath       = "$env:windir\System32\drivers\etc\hosts"
$XamppInstallDir = $env:XAMPP_DIR
$apachePath      = "$XamppInstallDir\apache"
$htdocsPath      = "$XamppInstallDir\htdocs"

$documentRoot = "$htdocsPath\$baseDomain"
# ──────────────────────────────────────────────────────────────────────────────

if (!(Test-Path $documentRoot)) {
    Write-Host "[2.ps1:XAMPP-fetch] could not locate the project: $documentRoot" -ForegroundColor Red; Exit 1
}

Write-Host "[2.ps1:HOST] setting up host file patches for $baseDomain" -ForegroundColor Cyan
$entries = @("127.0.0.1`t$baseDomain", "127.0.0.1`t$wwwDomain")
foreach ($entry in $entries) {
    $domainOnly = $entry -split "`t" | Select-Object -Last 1
    Write-Host "[2.ps1:HOST-add] proceeding to add $domainOnly to the host file." -ForegroundColor Cyan
    if (!(Select-String -Path $hostsPath -Pattern ([regex]::Escape($domainOnly)) -Quiet)) {
        try {
            Write-Host "[2.ps1:HOST-add] adding..." -ForegroundColor Yellow
            Add-Content -Path $hostsPath -Value "`r`n$entry" -ErrorAction Stop
            Write-Host "[2.ps1:HOST-add] added $domainOnly" -ForegroundColor Green
        } catch {
            Write-Host "[2.ps1:HOST-alert] the host file is locked, most likely in-use by other applications." -ForegroundColor Red
            $choice = Read-Host "Proceed with backup and force-addition of $domainOnly to the host file? [y/n]"
            if ($choice -eq 'Y' -or $choice -eq 'y') {
                try {
                    Write-Host "[2.ps1:HOST-backup] creating a backup..." -ForegroundColor Yellow
                    $backupPath     = "$hostsPath.backup"
                    $currentContent = Get-Content -Path $hostsPath -Raw
                    $updatedContent = $currentContent.TrimEnd() + "`r`n$entry"
                    if (Test-Path $backupPath) { Remove-Item $backupPath -Force }
                    Rename-Item -Path $hostsPath -NewName "hosts.backup" -Force
                    Write-Host "[2.ps1:HOST-backup] backup created." -ForegroundColor Green
                    $updatedContent | Out-File -FilePath $hostsPath -Encoding ASCII
                    Write-Host "[2.ps1:HOST-update] successfully updated." -ForegroundColor Green
                } catch { Write-Host "[2.ps1:HOST-lock] hard lock detected, close programs and try again." -ForegroundColor Red }
            }
        }
    } else { Write-Host "[2.ps1:HOST-skip] $domainOnly is already in the host file." -ForegroundColor Yellow }
}

$httpdConfPath = "$apachePath\conf\httpd.conf"
if (Test-Path $httpdConfPath) {
    Write-Host "[2.ps1:APACHE-httpd] ensuring vhosts is enabled..." -ForegroundColor Yellow
    (Get-Content $httpdConfPath) -replace "^#\s*(Include conf/extra/httpd-vhosts.conf)", '$1' | Set-Content $httpdConfPath
    Write-Host "[2.ps1:APACHE-httpd] vhosts are enabled." -ForegroundColor Green
}

$vhostsPath = "$apachePath\conf\extra\httpd-vhosts.conf"
if (Test-Path $vhostsPath) {
    Write-Host "[2.ps1:VHOST-add] adding fallback-config..." -ForegroundColor Yellow
    if (!(Select-String -Path $vhostsPath -Pattern "ServerName localhost" -Quiet)) {
        $n = "`r`n"
        $localhostFallback  = "${n}<VirtualHost *:80>${n}"
        $localhostFallback += "    DocumentRoot `"$htdocsPath`"${n}"
        $localhostFallback += "    ServerName localhost${n}"
        $localhostFallback += "</VirtualHost>${n}"
        Add-Content -Path $vhostsPath -Value $localhostFallback
    }
    Write-Host "[2.ps1:VHOST-add] added fallback-config." -ForegroundColor Green
    Write-Host "[2.ps1:VHOST-add] adding $baseDomain config..." -ForegroundColor Yellow
    Add-HnHostEntry -Domain $baseDomain -DocRoot $documentRoot -HostsPath $hostsPath -VhostsPath $vhostsPath -SubPathRedirect $subPath
} else { Write-Host "[2.ps1:VHOST-error] could not locate httpd-vhosts.conf at: $vhostsPath" -ForegroundColor Red; Exit 1 }

Write-Host "[2.ps1:SYSTEM-dns] flushing dns cache..." -ForegroundColor Yellow
Clear-DnsClientCache
Write-Host "[2.ps1:SYSTEM-dns] flush successful" -ForegroundColor Green

Write-Host "[2.ps1:XAMPP-apache] apache restart required, restarting..." -ForegroundColor Cyan
Restart-Apache -XamppDir $XamppInstallDir

Write-Host "[2.ps1:message] host cooked, deep fried even" -ForegroundColor Green