$uIdentity = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = ($uIdentity).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
$isAlone = [string]::IsNullOrWhiteSpace($env:SETUP_WORKDIR)
if (-not $isAdmin) {
    Write-Warning "no administrator privileges detected, self-elevating..."
    if ($PSCommandPath) {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    } else {
        $elevateCmd = "irm https://raw.githubusercontent.com/ketw/hostnet/main/scripts/0.ps1 | iex"
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"$elevateCmd`"" -Verb RunAs
    }; Exit;
}
if ($isAlone) {
    Write-Host "[0.ps1:SCRIPT] running solo..." -ForegroundColor Cyan

    Write-Host "[0.ps1:SCRIPT] URL required, please provide a URL that you wish to sanitize."
    do {
        $inputUrl = Read-Host "[0.ps1:SYSTEM-input] target URL (e.g. https://example.com/path)"
        $inputUrl = $inputUrl.Trim()
        if ([string]::IsNullOrWhiteSpace($inputUrl)) {
            Write-Host "[Input-Warning] target URL cannot be empty." -ForegroundColor Yellow
        }
    } while ([string]::IsNullOrWhiteSpace($inputUrl))
    if ($inputUrl -notmatch '^https?://') { $inputUrl = "https://$inputUrl" }
    Write-Host ""; $env:TARGET_URL = $inputUrl;
    Write-Host "[0.ps1:SYSTEM@target] set to $inputUrl" -ForegroundColor Green

    $RegistryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\xampp",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\xampp"
    )
    $XamppInstallDir    = $null
    $env:XAMPP_DIR      = $null
    Write-Host "[0.ps1:XAMPP-locate] finding xampp..."
    foreach ($path in $RegistryPaths) {
        if (Test-Path $path) {
            $XamppInstallDir = (Get-ItemProperty -Path $path).InstallLocation;
            if ($XamppInstallDir) { break } }
    }
    if (-not $XamppInstallDir) {
        $Drives = Get-PSDrive -PSProvider FileSystem
        foreach ($Drive in $Drives) {
            $PotentialPath = Join-Path -Path $Drive.Root -ChildPath "xampp"
            if (Test-Path "$PotentialPath\xampp-control.exe") { $XamppInstallDir = $PotentialPath; break; }
        }
    }
    if (-not $XamppInstallDir) {
        Write-Host "[0.ps1:XAMPP-locate] could not locate xampp, setting to null" -ForegroundColor Yellow
        $env:XAMPP_DIR = $null
    } else {
        $env:XAMPP_DIR = $XamppInstallDir
        Write-Host "[0.ps1:XAMPP-locate] found xampp: $XamppInstallDir" -ForegroundColor Green
    }
}

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
$htdocsPath = "$XamppInstallDir\htdocs"
$domainDir  = "$htdocsPath\$baseDomain"
Write-Host "[0.ps1:SYSTEM] system checkup for $baseDomain..." -ForegroundColor Cyan
if (Test-Path $hostsPath) {
    $hostsContent = Get-Content -Path $hostsPath
    $newHostsContent = $hostsContent | Where-Object { $_ -notmatch [regex]::Escape($baseDomain) }
    $newHostsContent | Out-File -FilePath $hostsPath -Encoding ASCII -Force
    Write-Host "[0.ps1:SYSTEM-success] sanitized $baseDomain entries from the hosts file." -ForegroundColor Green
}
if (Test-Path $vhostsPath) {
    $vhostsContent = Get-Content -Path $vhostsPath -Raw
    $pattern = "(?s)# Custom Domain Automator: $([regex]::Escape($baseDomain)).*?</VirtualHost>\s*"
    if ($vhostsContent -match $pattern) {
        $newVhostsContent = $vhostsContent -replace $pattern, ""
        $newVhostsContent | Out-File -FilePath $vhostsPath -Encoding ASCII -Force
        Write-Host "[0.ps1:SYSTEM-success] sanitized VirtualHost block from httpd-vhosts.conf." -ForegroundColor Green
    } else {
        Write-Host "[0.ps1:SYSTEM-skip] no contaminations in VirtualHost block." -ForegroundColor Yellow
    }
}
if (Test-Path $domainDir) {
    Write-Host "[0.ps1:SYSTEM-clean] removing deployed files at htdocs\$baseDomain..." -ForegroundColor Yellow
    Remove-Item -Path $domainDir -Recurse -Force
    Write-Host "[0.ps1:SYSTEM-clean] removed htdocs\$baseDomain." -ForegroundColor Green
}

Write-Host "[0.ps1:SYSTEM-dns] flushing dns cache..." -ForegroundColor Yellow
Clear-DnsClientCache
Write-Host "[0.ps1:SYSTEM-dns] flush successful" -ForegroundColor Green

Write-Host "[0.ps1:XAMPP-apache] checking apache status..." -ForegroundColor Cyan
$ApacheService = Get-Service | Where-Object { $_.Name -like "Apache*" }
$HttpdPath = Join-Path -Path $XamppInstallDir -ChildPath "apache\bin\httpd.exe"
if ($ApacheService) {
    Write-Host "[0.ps1:XAMPP-apache] found service, restarting..." -ForegroundColor Yellow
    try {
        Restart-Service -Name $ApacheService.Name -Force -ErrorAction SilentlyContinue
        Write-Host "[0.ps1:XAMPP-apache] service restarted." -ForegroundColor Green
    } catch { Write-Host "[0.ps1:XAMPP-apache] failed to restart service, manually attempting to restart..." -ForegroundColor Yellow; }
} elseif (Test-Path $HttpdPath) {
    $httpdRunning = Get-Process "httpd" -ErrorAction SilentlyContinue
    if ($httpdRunning) {
        Write-Host "[0.ps1:XAMPP-apache] no service found, restarting process..." -ForegroundColor Yellow
        $httpdRunning | Stop-Process -Force
        Start-Sleep -Seconds 1
        Start-Process -FilePath $HttpdPath -WindowStyle Hidden
        Write-Host "[0.ps1:XAMPP-apache] process restarted." -ForegroundColor Green
    } else {
        Write-Host "[0.ps1:XAMPP-apache] apache is not running, skipping restart." -ForegroundColor Yellow
    }
} else {
    Write-Host "[0.ps1:XAMPP-apache] could not locate httpd.exe at $HttpdPath, apache may not be installed correctly." -ForegroundColor Red
}

Write-Host "[0.ps1:message] system sanitized" -ForegroundColor Green