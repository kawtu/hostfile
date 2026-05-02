# ── Variables ─────────────────────────────────────────────────────────────────
$workDir = if ($env:SETUP_WORKDIR) { $env:SETUP_WORKDIR } else { (Get-Location).Path }

$XamppInstallDir = $env:XAMPP_DIR
$httrackExe      = $env:HTTRACK_EXE
$targetUrl       = $env:TARGET_URL

$uri        = [System.Uri]$targetUrl
$baseDomain = ($uri.Host -replace '^www\.', '')
$subPath    = $uri.AbsolutePath.Trim('/')

$htdocsPath  = "$XamppInstallDir\htdocs"
$apachePath  = "$XamppInstallDir\apache"
$hostsPath   = "$env:windir\System32\drivers\etc\hosts"
$vhostsPath  = "$apachePath\conf\extra\httpd-vhosts.conf"

$externalRoot = "$htdocsPath\$baseDomain-external"
# ──────────────────────────────────────────────────────────────────────────────

# ── Helper ────────────────────────────────────────────────────────────────────
function Find-MirrorSource {
    param([string]$MirrorOut, [string]$Domain)
    foreach ($candidate in @("$MirrorOut\$Domain", "$MirrorOut\www.$Domain")) {
        if (Test-Path $candidate) { return $candidate }
    }
    $subdirs = Get-ChildItem -Path $MirrorOut -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '^(hts-cache|hts-log)' }
    foreach ($d in $subdirs) {
        $hasFiles = Get-ChildItem -Path $d.FullName -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '\.(html?|css|js|php|aspx|png|jpg|pdf)$' } |
            Select-Object -First 1
        if ($hasFiles) { return $d.FullName }
    }
    return $null
}
function Invoke-Mirror {
    param([string]$Url, [string]$OutFolder, [string]$Depth = "1")
    $htArgs = @($Url, "-O", $OutFolder, "-w", "-r$Depth", "-%e0")
    & $httrackExe $htArgs 2>&1 | Out-Null
}
# ──────────────────────────────────────────────────────────────────────────────

if ($subPath -eq '') {
    Write-Host "[3.ps1:SKIP] full domain was mirrored, no external link processing needed." -ForegroundColor Gray
    Exit 0
}
$deployedSubDir = "$htdocsPath\$baseDomain\$subPath"
if (!(Test-Path $deployedSubDir)) {
    Write-Host "[3.ps1:ERROR] deployed directory not found: $deployedSubDir" -ForegroundColor Red; Exit 1
}

function Add-HostEntry {
    param([string]$domain, [string]$docRoot)
    $wwwAlias = "www.$domain"
    $n = "`r`n"
    foreach ($d in @($domain, $wwwAlias)) {
        if (!(Select-String -Path $hostsPath -Pattern ([regex]::Escape($d)) -Quiet)) {
            Add-Content -Path $hostsPath -Value "`r`n127.0.0.1`t$d" -ErrorAction SilentlyContinue
            Write-Host "[3.ps1:HOST-add] added $d" -ForegroundColor Green
        }
    }
    if (!(Select-String -Path $vhostsPath -Pattern ([regex]::Escape("ServerName $domain")) -Quiet)) {
        $block  = "${n}# Custom Domain Automator: $domain${n}"
        $block += "<VirtualHost *:80>${n}"
        $block += "    DocumentRoot `"$docRoot`"${n}"
        $block += "    ServerName $domain${n}"
        $block += "    ServerAlias $wwwAlias${n}"
        $block += "    <Directory `"$docRoot`">${n}"
        $block += "        AllowOverride All${n}"
        $block += "        Require all granted${n}"
        $block += "    </Directory>${n}"
        $block += "</VirtualHost>${n}"
        Add-Content -Path $vhostsPath -Value $block
        Write-Host "[3.ps1:VHOST-add] added vhost for $domain" -ForegroundColor Green
    } else {
        Write-Host "[3.ps1:VHOST-skip] vhost for $domain already exists." -ForegroundColor Yellow
    }
}

Write-Host "[3.ps1:SCAN] scanning deployed files in: $deployedSubDir" -ForegroundColor Cyan
$htmlFiles = Get-ChildItem -Path $deployedSubDir -Recurse -Include "*.html","*.htm" -File
$linkPattern = '(?:href|src|action)\s*=\s*["\x27]([^"\x27#\s][^"\x27\s]*)["\x27]'
$allLinks    = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($file in $htmlFiles) {
    $content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
    if (!$content) { continue }
    $matches = [regex]::Matches($content, $linkPattern)
    foreach ($m in $matches) {
        $val = $m.Groups[1].Value.Trim()
        try {
            $resolved = [System.Uri]::new([System.Uri]$targetUrl, $val)
            [void]$allLinks.Add($resolved.AbsoluteUri)
        } catch { }
    }
}
Write-Host "[3.ps1:SCAN] found $($allLinks.Count) unique links." -ForegroundColor Gray

$sameDomainLinks = [System.Collections.Generic.List[string]]::new()
$externalLinks   = [System.Collections.Generic.List[string]]::new()
foreach ($link in $allLinks) {
    try {
        $lu = [System.Uri]$link
        if (!$lu.IsAbsoluteUri) { continue }
        if ($lu.Scheme -notin @('http','https')) { continue }
        $linkDomain = $lu.Host -replace '^www\.', ''
        if ($linkDomain -eq $baseDomain) {
            $linkSub = $lu.AbsolutePath.Trim('/')
            if ($linkSub -ne $subPath -and !$linkSub.StartsWith("$subPath/")) { [void]$sameDomainLinks.Add($link); }
        } else { [void]$externalLinks.Add($link); }
    } catch { }
}
Write-Host "[3.ps1:SCAN] same-domain links to mirror: $($sameDomainLinks.Count)" -ForegroundColor Gray
Write-Host "[3.ps1:SCAN] external links to mirror:     $($externalLinks.Count)" -ForegroundColor Gray

if ($sameDomainLinks.Count -gt 0) {
    Write-Host "[3.ps1:SAME-DOMAIN] mirroring $($sameDomainLinks.Count) same-domain paths..." -ForegroundColor Cyan
    $sdStaging = Join-Path $workDir "staging_samedomain"
    foreach ($link in $sameDomainLinks) {
        $lu       = [System.Uri]$link
        $linkSub  = $lu.AbsolutePath.Trim('/')
        Write-Host "[3.ps1:SAME-DOMAIN] mirroring: $link" -ForegroundColor Yellow
        if (Test-Path $sdStaging) { Remove-Item $sdStaging -Recurse -Force }
        New-Item -ItemType Directory -Path $sdStaging | Out-Null
        $mirrorOut = Join-Path $workDir "Mirrored_sd_$($baseDomain -replace '[^a-zA-Z0-9]','_')"
        if (Test-Path $mirrorOut) { Remove-Item $mirrorOut -Recurse -Force }
        Invoke-Mirror -Url $link -OutFolder $mirrorOut -Depth "1"
        $srcPath = Find-MirrorSource -MirrorOut $mirrorOut -Domain $baseDomain
        if (!$srcPath) { Write-Host "[3.ps1:SAME-DOMAIN] could not locate mirrored output for $link, skipping." -ForegroundColor Yellow; continue }
        Copy-Item -Path "$srcPath\*" -Destination $sdStaging -Recurse -Force
        $deployTarget = "$htdocsPath\$baseDomain"
        if (!(Test-Path $deployTarget)) { New-Item -ItemType Directory -Path $deployTarget | Out-Null }
        Copy-Item -Path "$sdStaging\*" -Destination $deployTarget -Recurse -Force
        Write-Host "[3.ps1:SAME-DOMAIN] deployed $linkSub into htdocs\$baseDomain" -ForegroundColor Green
        if (Test-Path $mirrorOut) { Remove-Item $mirrorOut -Recurse -Force }
    }
    if (Test-Path $sdStaging) { Remove-Item $sdStaging -Recurse -Force }
}

if ($externalLinks.Count -gt 0) {
    Write-Host "[3.ps1:EXTERNAL] mirroring $($externalLinks.Count) external links..." -ForegroundColor Cyan
    if (!(Test-Path $externalRoot)) { New-Item -ItemType Directory -Path $externalRoot | Out-Null }
    $byDomain = $externalLinks | Group-Object { ([System.Uri]$_).Host -replace '^www\.', '' }
    foreach ($group in $byDomain) {
        $extDomain  = $group.Name
        $extDocRoot = "$externalRoot\$extDomain"
        if (!(Test-Path $extDocRoot)) { New-Item -ItemType Directory -Path $extDocRoot | Out-Null }
        Write-Host "[3.ps1:EXTERNAL] processing domain: $extDomain ($($group.Count) links)" -ForegroundColor Cyan
        foreach ($link in $group.Group) {
            $lu      = [System.Uri]$link
            $extPath = $lu.AbsolutePath.Trim('/')
            Write-Host "[3.ps1:EXTERNAL] mirroring: $link" -ForegroundColor Yellow
            $mirrorOut = Join-Path $workDir "Mirrored_ext_$($extDomain -replace '[^a-zA-Z0-9]','_')"
            if (Test-Path $mirrorOut) { Remove-Item $mirrorOut -Recurse -Force }
            $ext   = [System.IO.Path]::GetExtension($lu.AbsolutePath).ToLower()
            $depth = if ($ext -in @('.pdf','.png','.jpg','.jpeg','.gif','.svg','.webp','.zip','.mp4','.mp3')) { "0" } else { "1" }
            Invoke-Mirror -Url $link -OutFolder $mirrorOut -Depth $depth
            $srcPath = Find-MirrorSource -MirrorOut $mirrorOut -Domain $extDomain
            if (!$srcPath) { Write-Host "[3.ps1:EXTERNAL] could not locate mirrored output for $link, skipping." -ForegroundColor Yellow; continue }
            $deployTarget = $extDocRoot
            if (!(Test-Path $deployTarget)) { New-Item -ItemType Directory -Path $deployTarget | Out-Null }
            Copy-Item -Path "$srcPath\*" -Destination $deployTarget -Recurse -Force
            Write-Host "[3.ps1:EXTERNAL] deployed $extDomain into htdocs\$baseDomain-external\$extDomain" -ForegroundColor Green
            if (Test-Path $mirrorOut) { Remove-Item $mirrorOut -Recurse -Force }
        }
        Add-HostEntry -domain $extDomain -docRoot $extDocRoot
    }
}

Write-Host "[3.ps1:SYSTEM-dns] flushing dns cache..." -ForegroundColor Yellow
Clear-DnsClientCache
Write-Host "[3.ps1:SYSTEM-dns] flush successful" -ForegroundColor Green

Write-Host "[3.ps1:XAMPP-apache] checking apache status..." -ForegroundColor Cyan
$ApacheService = Get-Service | Where-Object { $_.Name -like "Apache*" }
$HttpdPath = Join-Path -Path $XamppInstallDir -ChildPath "apache\bin\httpd.exe"
if ($ApacheService) {
    Write-Host "[3.ps1:XAMPP-apache] found service, restarting..." -ForegroundColor Yellow
    try {
        Restart-Service -Name $ApacheService.Name -Force -ErrorAction SilentlyContinue
        Write-Host "[3.ps1:XAMPP-apache] service restarted." -ForegroundColor Green
    } catch { Write-Host "[3.ps1:XAMPP-apache] failed to restart service, manually attempting to restart..." -ForegroundColor Yellow; }
} elseif (Test-Path $HttpdPath) {
    $httpdRunning = Get-Process "httpd" -ErrorAction SilentlyContinue
    if ($httpdRunning) {
        Write-Host "[3.ps1:XAMPP-apache] no service found, restarting process..." -ForegroundColor Yellow
        $httpdRunning | Stop-Process -Force
        Start-Sleep -Seconds 1
        Start-Process -FilePath $HttpdPath -WindowStyle Hidden
        Write-Host "[3.ps1:XAMPP-apache] process restarted." -ForegroundColor Green
    } else {
        Write-Host "[3.ps1:XAMPP-apache] apache is not running, skipping restart." -ForegroundColor Yellow
    }
} else {
    Write-Host "[3.ps1:XAMPP-apache] could not locate httpd.exe at $HttpdPath, apache may not be installed correctly." -ForegroundColor Red
}

Write-Host "[3.ps1:message] external links wired up" -ForegroundColor Green
