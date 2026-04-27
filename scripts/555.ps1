$PSScriptRoot = if ($env:SETUP_WORKDIR) { $env:SETUP_WORKDIR } else { (Get-Location).Path }

Write-Host "`nCleaning up..." -ForegroundColor Cyan
Get-ChildItem -Path $PSScriptRoot -Directory | ForEach-Object {
    Write-Host "Deleting folder and all contents: $($_.Name)" -ForegroundColor Yellow
    Remove-Item -Path $_.FullName -Recurse -Force
}

$customDomain = "sarkariresult.com.cm/up-police-si-asi-2026"
$cleanHostname = $customDomain -split '/' | Select-Object -First 1
$baseDomain = $cleanHostname -replace '^www\.', ''
$wwwDomain = "www.$baseDomain"

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

if (-not $XamppInstallDir) {
    Write-Error "Could not locate XAMPP installation to perform cleanup."
    Pause; Exit
}

Write-Host "Starting Cleanup for $baseDomain..." -ForegroundColor Cyan

$hostsPath = "$env:windir\System32\drivers\etc\hosts"
if (Test-Path $hostsPath) {
    $hostsContent = Get-Content -Path $hostsPath
    $newHostsContent = $hostsContent | Where-Object { $_ -notmatch [regex]::Escape($baseDomain) }
    $newHostsContent | Out-File -FilePath $hostsPath -Encoding ASCII -Force
    Write-Host "[SUCCESS] Removed $baseDomain entries from hosts file." -ForegroundColor Green
}

$vhostsPath = "$XamppInstallDir\apache\conf\extra\httpd-vhosts.conf"
if (Test-Path $vhostsPath) {
    $vhostsContent = Get-Content -Path $vhostsPath -Raw
    $pattern = "(?s)# Custom Domain Automator: $baseDomain.*?<VirtualHost \*:80>.*?</VirtualHost>\s*"
    if ($vhostsContent -match $pattern) {
        $newVhostsContent = $vhostsContent -replace $pattern, ""
        $newVhostsContent | Out-File -FilePath $vhostsPath -Encoding ASCII -Force
        Write-Host "[SUCCESS] Removed Virtual Host block from httpd-vhosts.conf." -ForegroundColor Green
    } else {
        Write-Host "[SKIP] No Virtual Host block found for $baseDomain." -ForegroundColor Yellow
    }
}

Clear-DnsClientCache
Write-Host "[SUCCESS] Flushed Windows DNS Cache." -ForegroundColor Green
Write-Host "`nRestarting Apache to apply changes..." -ForegroundColor Cyan
$ApacheService = Get-Service | Where-Object { $_.Name -like "Apache*" }
if ($ApacheService) {
    Restart-Service -Name $ApacheService.Name -Force -ErrorAction SilentlyContinue
    Write-Host "Apache service restarted." -ForegroundColor Green
} else {
    $HttpdPath = Join-Path -Path $XamppInstallDir -ChildPath "apache\bin\httpd.exe"
    if (Test-Path $HttpdPath) {
        Get-Process "httpd" -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 1
        Start-Process -FilePath $HttpdPath -WindowStyle Hidden
        Write-Host "Apache process restarted." -ForegroundColor Green
    }
}
Write-Host "`nCleanup Complete! $baseDomain has been removed." -ForegroundColor Green
