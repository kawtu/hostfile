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

$XamppInstallDir = $env:XAMPP_DIR
$httrackExe      = $env:HTTRACK_EXE
$targetUrl       = $env:TARGET_URL

$uri        = [System.Uri]$targetUrl
$baseDomain = ($uri.Host -replace '^www\.', '')
$subPath    = $uri.AbsolutePath.Trim('/')

$htdocsPath   = "$XamppInstallDir\htdocs"
$apachePath   = "$XamppInstallDir\apache"
$hostsPath    = "$env:windir\System32\drivers\etc\hosts"
$vhostsPath   = "$apachePath\conf\extra\httpd-vhosts.conf"
$externalRoot = "$htdocsPath\$baseDomain-external"
# ──────────────────────────────────────────────────────────────────────────────

if ($subPath -eq '') {
    Write-Host "[3.ps1:SKIP] full domain was mirrored, no external link processing needed." -ForegroundColor Gray
    Exit 0
}
$deployedSubDir = "$htdocsPath\$baseDomain\$subPath"
if (!(Test-Path $deployedSubDir)) {
    Write-Host "[3.ps1:ERROR] deployed directory not found: $deployedSubDir" -ForegroundColor Red; Exit 1
}

Write-Host "[3.ps1:SCAN] scanning deployed files in: $deployedSubDir" -ForegroundColor Cyan
$htmlFiles   = Get-ChildItem -Path $deployedSubDir -Recurse -Include "*.html","*.htm" -File
$linkPattern = '(?:href|src|action)\s*=\s*["\x27]([^"\x27#\s][^"\x27\s]*)["\x27]'
$allLinks    = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($file in $htmlFiles) {
    $content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
    if (!$content) { continue }
    $reMatches = [regex]::Matches($content, $linkPattern)
    foreach ($m in $reMatches) {
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
            if ($linkSub -ne $subPath -and !$linkSub.StartsWith("$subPath/")) {
                [void]$sameDomainLinks.Add($link)
            }
        } else { [void]$externalLinks.Add($link) }
    } catch { }
}
Write-Host "[3.ps1:SCAN] same-domain links to mirror: $($sameDomainLinks.Count)" -ForegroundColor Gray
Write-Host "[3.ps1:SCAN] external links to mirror:     $($externalLinks.Count)" -ForegroundColor Gray

if ($sameDomainLinks.Count -gt 0) {
    Write-Host "[3.ps1:SAME-DOMAIN] mirroring $($sameDomainLinks.Count) same-domain paths..." -ForegroundColor Cyan
    $sdStaging = Join-Path $workDir "staging_samedomain"
    foreach ($link in $sameDomainLinks) {
        $lu      = [System.Uri]$link
        $linkSub = $lu.AbsolutePath.Trim('/')
        Write-Host "[3.ps1:SAME-DOMAIN] mirroring: $link" -ForegroundColor Yellow
        if (Test-Path $sdStaging) { Remove-Item $sdStaging -Recurse -Force }
        New-Item -ItemType Directory -Path $sdStaging | Out-Null
        $mirrorOut = Join-Path $workDir "Mirrored_sd_$($baseDomain -replace '[^a-zA-Z0-9]','_')"
        if (Test-Path $mirrorOut) { Remove-Item $mirrorOut -Recurse -Force }
        $ext   = [System.IO.Path]::GetExtension($lu.AbsolutePath).ToLower()
        $depth = if ($ext -in @('.pdf','.png','.jpg','.jpeg','.gif','.svg','.webp','.zip','.mp4','.mp3','.css','.js')) { "0" } else { "2" }
        Invoke-HnMirror -Url $link -OutFolder $mirrorOut -HttrackExe $httrackExe -Depth $depth
        $srcPath = Find-MirrorSource -MirrorOut $mirrorOut -Domain $baseDomain
        if (!$srcPath) {
            $ok = Invoke-HnDirectDownload -Url $link -DestDir "$htdocsPath\$baseDomain"
            if ($ok) { Write-Host "[3.ps1:SAME-DOMAIN] direct-downloaded $linkSub" -ForegroundColor Green }
            else { Write-Host "[3.ps1:SAME-DOMAIN] skipped (unreachable): $link" -ForegroundColor DarkGray }
            if (Test-Path $mirrorOut) { Remove-Item $mirrorOut -Recurse -Force }; continue
        }
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
            $lu = [System.Uri]$link
            Write-Host "[3.ps1:EXTERNAL] mirroring: $link" -ForegroundColor Yellow
            $mirrorOut = Join-Path $workDir "Mirrored_ext_$($extDomain -replace '[^a-zA-Z0-9]','_')"
            if (Test-Path $mirrorOut) { Remove-Item $mirrorOut -Recurse -Force }
            $ext   = [System.IO.Path]::GetExtension($lu.AbsolutePath).ToLower()
            $depth = if ($ext -in @('.pdf','.png','.jpg','.jpeg','.gif','.svg','.webp','.zip','.mp4','.mp3','.css','.js')) { "0" } else { "2" }
            Invoke-HnMirror -Url $link -OutFolder $mirrorOut -HttrackExe $httrackExe -Depth $depth
            $srcPath = Find-MirrorSource -MirrorOut $mirrorOut -Domain $extDomain
            if (!$srcPath) {
                $ok = Invoke-HnDirectDownload -Url $link -DestDir $extDocRoot
                if ($ok) { Write-Host "[3.ps1:EXTERNAL] direct-downloaded into $extDomain" -ForegroundColor Green }
                else { Write-Host "[3.ps1:EXTERNAL] skipped (unreachable): $link" -ForegroundColor DarkGray }
                if (Test-Path $mirrorOut) { Remove-Item $mirrorOut -Recurse -Force }; continue
            }
            Copy-Item -Path "$srcPath\*" -Destination $extDocRoot -Recurse -Force
            Write-Host "[3.ps1:EXTERNAL] deployed $extDomain into htdocs\$baseDomain-external\$extDomain" -ForegroundColor Green
            if (Test-Path $mirrorOut) { Remove-Item $mirrorOut -Recurse -Force }
        }
        Add-HnHostEntry -Domain $extDomain -DocRoot $extDocRoot -HostsPath $hostsPath -VhostsPath $vhostsPath
    }
}

$allMirroredDomains = [System.Collections.Generic.List[string]]::new()
[void]$allMirroredDomains.Add($baseDomain)
[void]$allMirroredDomains.Add("www.$baseDomain")
if (Test-Path $externalRoot) {
    Get-ChildItem -Path $externalRoot -Directory | ForEach-Object {
        [void]$allMirroredDomains.Add($_.Name)
        [void]$allMirroredDomains.Add("www.$($_.Name)")
    }
}

Write-Host "[3.ps1:REWRITE] rewriting https links to http for mirrored domains..." -ForegroundColor Cyan
$rewriteTargets = @("$htdocsPath\$baseDomain")
if (Test-Path $externalRoot) {
    Get-ChildItem -Path $externalRoot -Directory | ForEach-Object { $rewriteTargets += $_.FullName }
}
$rewriteCount = 0
foreach ($dir in $rewriteTargets) {
    Get-ChildItem -Path $dir -Recurse -Include "*.html","*.htm" -File -ErrorAction SilentlyContinue | ForEach-Object {
        $content = Get-Content -Path $_.FullName -Raw -ErrorAction SilentlyContinue
        if (!$content) { return }
        $original = $content
        foreach ($domain in $allMirroredDomains) {
            $content = $content -replace "https://([wW]{3}\.)?$([regex]::Escape($domain))/", "http://$domain/"
        }
        if ($content -ne $original) {
            $content | Set-Content -Path $_.FullName -Encoding UTF8 -NoNewline
            $rewriteCount++
        }
    }
}
Write-Host "[3.ps1:REWRITE] rewrote $rewriteCount HTML files." -ForegroundColor Green

Write-Host "[3.ps1:HSTS] disabling HSTS enforcement for mirrored domains..." -ForegroundColor Cyan
$hstsPolicies = @(
    "HKLM:\SOFTWARE\Policies\Microsoft\Edge\HSTSBypassList",
    "HKLM:\SOFTWARE\Policies\Google\Chrome\HSTSBypassList"
)
foreach ($regPath in $hstsPolicies) {
    if (!(Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
    $idx = 1
    foreach ($domain in $allMirroredDomains) {
        $existing   = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        $alreadySet = $false
        if ($existing) { $existing.PSObject.Properties | Where-Object { $_.Value -eq $domain } | ForEach-Object { $alreadySet = $true } }
        if (!$alreadySet) {
            while ($null -ne (Get-ItemProperty -Path $regPath -Name "$idx" -ErrorAction SilentlyContinue)."$idx") { $idx++ }
            Set-ItemProperty -Path $regPath -Name "$idx" -Value $domain -Type String; $idx++
        }
    }
}
Write-Host "[3.ps1:HSTS] HSTS bypass set for $($allMirroredDomains.Count) domains." -ForegroundColor Green

Write-Host "[3.ps1:SYSTEM-dns] flushing dns cache..." -ForegroundColor Yellow
Clear-DnsClientCache
Write-Host "[3.ps1:SYSTEM-dns] flush successful" -ForegroundColor Green

Write-Host "[3.ps1:XAMPP-apache] restarting apache..." -ForegroundColor Cyan
Restart-Apache -XamppDir $XamppInstallDir

Write-Host "[3.ps1:message] external links wired up" -ForegroundColor Green