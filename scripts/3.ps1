$PSScriptRoot = if ($env:SETUP_WORKDIR) { $env:SETUP_WORKDIR } else { (Get-Location).Path }

$SourceFolder = Join-Path -Path $PSScriptRoot -ChildPath "website"
$InstallerPath = Join-Path -Path $env:TEMP -ChildPath "xampp-installer.exe"
$XamppInstallDir = $null
$RegistryPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\xampp",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\xampp"
)

foreach ($path in $RegistryPaths) {
    if (Test-Path $path) {
        $XamppInstallDir = (Get-ItemProperty -Path $path).InstallLocation
        if ($XamppInstallDir) { break }
    }
}

if (-not $XamppInstallDir) {
    $Drives = Get-PSDrive -PSProvider FileSystem
    foreach ($Drive in $Drives) {
        $PotentialPath = Join-Path -Path $Drive.Root -ChildPath "xampp"
        if (Test-Path "$PotentialPath\xampp-control.exe") {
            $XamppInstallDir = $PotentialPath
            break
        }
    }
}

if ($XamppInstallDir) {
    Write-Host "Found existing XAMPP installation at: $XamppInstallDir" -ForegroundColor Green
} else {
    Write-Host "XAMPP not detected. Proceeding with download..." -ForegroundColor Yellow
    $XamppDownloadUrl = "https://sourceforge.net/projects/xampp/files/XAMPP%20Windows/8.2.12/xampp-windows-x64-8.2.12-0-VS16-installer.exe/download"
    try {
        Invoke-WebRequest -Uri $XamppDownloadUrl -OutFile $InstallerPath -UserAgent "Mozilla/5.0" -ErrorAction Stop
        if ((Get-Item $InstallerPath).Length -lt 1MB) { throw "Downloaded file is too small/corrupted." }
        Write-Host "Installing XAMPP..." -ForegroundColor Cyan
        $process = Start-Process -FilePath $InstallerPath -ArgumentList "--mode unattended --launchapps 0" -Wait -PassThru
        $XamppInstallDir = "C:\xampp" 
    } catch {
        Write-Error "Download failed or file corrupted: $($_.Exception.Message)"
        Pause; Exit
    }
}

$xamppPath = $XamppInstallDir
if ([string]::IsNullOrWhiteSpace($xamppPath)) { $xamppPath = "C:\xampp" }
$HtdocsDir = Join-Path -Path $XamppInstallDir -ChildPath "htdocs"
$WebappDestDir = "webapp"

$projectFolder = $WebappDestDir

$customDomain = "sarkariresult.com.cm/up-police-si-asi-2026"
$cleanHostname = $customDomain -split '/' | Select-Object -First 1
$baseDomain = $cleanHostname -replace '^www\.', ''
$wwwDomain = "www.$baseDomain"

$apachePath = $xamppPath -replace "\\", "/"
$documentRoot = "$apachePath/htdocs/$projectFolder"
if ($customDomain -notlike "www.*") {
    $customDomain = "www.$customDomain"
}

if (!(Test-Path "$xamppPath\htdocs\$projectFolder")) {
    Write-Host "`n[ERROR] Could not find folder: $xamppPath\htdocs\$projectFolder" -ForegroundColor Red
    Exit
}

Write-Host "`nStarting setup for $baseDomain..." -ForegroundColor Cyan
$hostsPath = "$env:windir\System32\drivers\etc\hosts"
$entries = @("127.0.0.1`t$baseDomain", "127.0.0.1`t$wwwDomain")
foreach ($entry in $entries) {
    $domainOnly = $entry -split "`t" | Select-Object -Last 1
    if (!(Select-String -Path $hostsPath -Pattern ([regex]::Escape($domainOnly)) -Quiet)) {
        try {
            Add-Content -Path $hostsPath -Value "`r`n$entry" -ErrorAction Stop
            Write-Host "[SUCCESS] Added $domainOnly to hosts file." -ForegroundColor Green
        } 
        catch {
            Write-Host "`n[NOTICE] The hosts file is locked." -ForegroundColor Yellow
            $choice = Read-Host "Do you want to BACKUP and FORCE the change for $domainOnly? (Y/N)"
            if ($choice -eq 'Y' -or $choice -eq 'y') {
                try {
                    $backupPath = "$hostsPath.backup"
                    $currentContent = Get-Content -Path $hostsPath -Raw
                    $updatedContent = $currentContent.TrimEnd() + "`r`n$entry"
                    if (Test-Path $backupPath) { Remove-Item $backupPath -Force }
                    Rename-Item -Path $hostsPath -NewName "hosts.backup" -Force
                    $updatedContent | Out-File -FilePath $hostsPath -Encoding ASCII
                    Write-Host "[SUCCESS] Original saved as hosts.backup and new entries applied." -ForegroundColor Green
                } catch {
                    Write-Host "[ERROR] Hard lock detected. Close your text editors and try again." -ForegroundColor Red
                }
            }
        }
    } else {
        Write-Host "[SKIP] $domainOnly is already in the hosts file." -ForegroundColor Yellow
    }
}

$httpdConfPath = "$xamppPath\apache\conf\httpd.conf"
if (Test-Path $httpdConfPath) {
    (Get-Content $httpdConfPath) -replace "^#\s*(Include conf/extra/httpd-vhosts.conf)", "`$1" | Set-Content $httpdConfPath
    Write-Host "[SUCCESS] Ensured vhosts are enabled in httpd.conf." -ForegroundColor Green
}

# 5. Add Virtual Host to httpd-vhosts.conf
$vhostsPath = "$xamppPath\apache\conf\extra\httpd-vhosts.conf"

# Notice the addition of ServerAlias here!
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

$localhostFallback = @"
<VirtualHost *:80>
    DocumentRoot `"$apachePath/htdocs`"
    ServerName localhost
</VirtualHost>
"@

if (Test-Path $vhostsPath) {
    # Check for localhost fallback
    if (!(Select-String -Path $vhostsPath -Pattern "ServerName localhost" -Quiet)) {
        Add-Content -Path $vhostsPath -Value $localhostFallback
    }

    # Add the new custom domain (Check using baseDomain)
    if (!(Select-String -Path $vhostsPath -Pattern "ServerName $baseDomain" -Quiet)) {
        Add-Content -Path $vhostsPath -Value $vhostConfig
        Write-Host "[SUCCESS] Added Virtual Host for $baseDomain (with www alias)." -ForegroundColor Green
    } else {
        Write-Host "[SKIP] Virtual Host for $baseDomain already exists." -ForegroundColor Yellow
    }
} else {
    Write-Host "[ERROR] Could not find httpd-vhosts.conf at $vhostsPath" -ForegroundColor Red
}

Clear-DnsClientCache
Write-Host "[SUCCESS] Flushed Windows DNS Cache." -ForegroundColor Green
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Setup Complete!" -ForegroundColor Green

Write-Host "`nRestarting Apache to apply changes..." -ForegroundColor Cyan
$ApacheService = Get-Service | Where-Object { $_.Name -like "Apache*" }
if ($ApacheService) {
    Write-Host "Found Apache service: $($ApacheService.Name). Restarting..." -ForegroundColor Gray
    try {
        Restart-Service -Name $ApacheService.Name -Force -ErrorAction Stop
        Write-Host "Apache service restarted successfully." -ForegroundColor Green
    } catch {
        Write-Warning "Failed to restart service. Attempting manual process restart..."
    }
} else {
    $HttpdPath = Join-Path -Path $XamppInstallDir -ChildPath "apache\bin\httpd.exe"
    if (Test-Path $HttpdPath) {
        Write-Host "Service not found. Restarting via executable..." -ForegroundColor Gray
        Get-Process "httpd" -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 1
        Start-Process -FilePath $HttpdPath -WindowStyle Hidden
        Write-Host "Apache process started successfully." -ForegroundColor Green
    } else {
        Write-Error "Could not locate httpd.exe at $HttpdPath"
    }
}

Write-Host "========================================" -ForegroundColor Cyan

$url = $customDomain
Start-Process $url
Write-Host "[SUCCESS] WEBAPP setup complete!" -ForegroundColor Green

Write-Host "`nCleaning up trash..." -ForegroundColor Cyan
Get-ChildItem -Path $PSScriptRoot -Directory | ForEach-Object {
    Write-Host "Deleting folder and all contents: $($_.Name)" -ForegroundColor Yellow
    Remove-Item -Path $_.FullName -Recurse -Force
}
Write-Host "Clean-Up Complete!" -ForegroundColor Green