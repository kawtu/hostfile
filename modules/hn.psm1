# hn.psm1 — shared helpers for hostnet scripts
# import via: Import-HnModule (defined in each script's bootstrap)

# ── Download with progress bar ────────────────────────────────────────────────
function Invoke-HnDownload {
    param(
        [string]$Uri,
        [string]$OutFile,
        [string]$UserAgent = "Mozilla/5.0"
    )
    $totalBytes = 0
    try {
        $req = [System.Net.HttpWebRequest]::Create($Uri)
        $req.Method = "HEAD"; $req.UserAgent = $UserAgent; $req.AllowAutoRedirect = $true
        $res = $req.GetResponse(); $totalBytes = $res.ContentLength; $res.Close()
    } catch { $totalBytes = 0 }

    $job = Start-Job -ScriptBlock {
        param($u, $o, $a)
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", $a)
        $wc.DownloadFile($u, $o)
    } -ArgumentList $Uri, $OutFile, $UserAgent

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $lastSize = 0; $lastTick = 0; $speed = "-- KB/s"; $bw = 28
    $cancelled = $false
    try {
        while ($job.State -eq 'Running') {
            Start-Sleep -Milliseconds 300
            if (-not (Test-Path $OutFile)) { continue }
            $size    = (Get-Item $OutFile).Length
            $now     = $sw.ElapsedMilliseconds
            $elapsed = $now - $lastTick
            if ($elapsed -ge 400 -and $elapsed -gt 0) {
                $kbps     = [math]::Round((($size - $lastSize) / 1KB) / ($elapsed / 1000))
                $speed    = if ($kbps -ge 1024) { "$([math]::Round($kbps/1024,1)) MB/s" } else { "$kbps KB/s" }
                $lastSize = $size; $lastTick = $now
            }
            $dlMB = [math]::Round($size / 1MB, 1)
            if ($totalBytes -gt 0) {
                $pct    = [math]::Min([math]::Floor($size / $totalBytes * 100), 100)
                $totMB  = [math]::Round($totalBytes / 1MB, 1)
                $filled = [math]::Floor($pct / 100 * $bw); $empty = $bw - $filled
                $bar    = ('#' * $filled) + ('-' * $empty)
                [Console]::Write("`r  [$bar] $pct%  $dlMB / $totMB MB  @ $speed   ")
            } else {
                $dots = '.' * (([int]($sw.Elapsed.TotalSeconds) % 4) + 1)
                $pad  = ' ' * (4 - $dots.Length)
                [Console]::Write("`r  [????] --  $dlMB MB  @ $speed$dots$pad   ")
            }
        }
    } finally {
        if ($job.State -eq 'Running') {
            Stop-Job $job; Remove-Job $job
            [Console]::Write("`r" + (" " * 72) + "`r")
            Write-Host "  download cancelled." -ForegroundColor Yellow
            if (Test-Path $OutFile) { Remove-Item $OutFile -Force }
            $cancelled = $true
        }
    }
    if ($cancelled) { return }
    [Console]::Write("`r" + (" " * 72) + "`r")
    Receive-Job $job -ErrorVariable jobErr | Out-Null; Remove-Job $job
    if ($jobErr) { throw $jobErr[0] }
}

# ── Find XAMPP install directory ──────────────────────────────────────────────
function Find-XamppDir {
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\xampp",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\xampp"
    )
    foreach ($p in $regPaths) {
        if (Test-Path $p) {
            $d = (Get-ItemProperty $p).InstallLocation
            if ($d -and (Test-Path "$d\apache\bin\httpd.exe")) { return $d }
        }
    }
    foreach ($p in @("C:\xampp", "D:\xampp")) {
        if (Test-Path "$p\apache\bin\httpd.exe") { return $p }
    }
    foreach ($drv in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        $pp = Join-Path $drv.Root "xampp"
        if (Test-Path "$pp\apache\bin\httpd.exe") { return $pp }
    }
    return $null
}

# ── Install XAMPP (download + unattended install) ─────────────────────────────
# Returns the install directory on success, $null on failure.
function Install-Xampp {
    param([string]$DownloadUrl, [string]$WorkDir)
    $installer = Join-Path $WorkDir "xampp-installer.exe"
    try {
        Invoke-HnDownload -Uri $DownloadUrl -OutFile $installer -UserAgent "Wget"
        $fileSize = (Get-Item $installer).Length
        if ($fileSize -lt 10MB) {
            throw "downloaded file too small ($([math]::Round($fileSize/1MB,1)) MB) - likely a redirect page, not the installer"
        }
        Start-Process -FilePath $installer -ArgumentList "--mode unattended", "--prefix `"C:\xampp`"" -Wait -Verb RunAs
        if (Test-Path $installer) { Remove-Item $installer -Force }
        $xamppDir = "C:\xampp"
        $deadline = (Get-Date).AddSeconds(30)
        while (-not (Test-Path "$xamppDir\apache\bin\httpd.exe") -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 2 }
        if (Test-Path "$xamppDir\apache\bin\httpd.exe") { return $xamppDir }
        throw "XAMPP install completed but apache was not found at $xamppDir"
    } catch {
        Write-Host "  XAMPP install failed: $_" -ForegroundColor Red
        return $null
    }
}

# ── Find HTTrack executable ───────────────────────────────────────────────────
function Find-HttrackExe {
    $exe = "C:\Program Files\WinHTTrack\httrack.exe"
    if (Test-Path $exe) { return $exe }
    $inPath = Get-Command "httrack.exe" -ErrorAction SilentlyContinue
    if ($inPath) { return $inPath.Source }
    return $null
}

# ── Install HTTrack (download + silent install) ───────────────────────────────
# Returns the exe path on success, $null on failure.
function Install-Httrack {
    param([string]$DownloadUrl, [string]$WorkDir)
    $installDir = "C:\Program Files\WinHTTrack"
    $installer  = Join-Path $WorkDir "httrack_setup.exe"
    try {
        Invoke-HnDownload -Uri $DownloadUrl -OutFile $installer
        Start-Process -FilePath $installer -ArgumentList "/VERYSILENT", "/SUPPRESSMSGBOXES", "/DIR=`"$installDir`"" -Wait
        if (Test-Path $installer) { Remove-Item $installer -Force }
        return Find-HttrackExe
    } catch {
        Write-Host "  HTTrack install failed: $_" -ForegroundColor Red
        return $null
    }
}

# ── Restart Apache (service or direct exe) ───────────────────────────────────
function Restart-Apache {
    param([string]$XamppDir)
    $svc = Get-Service | Where-Object { $_.Name -like "Apache*" }
    if ($svc) {
        try {
            Restart-Service -Name $svc.Name -Force -ErrorAction Stop
            Write-Host "  apache service restarted." -ForegroundColor Green
            return
        } catch { Write-Host "  service restart failed, trying executable..." -ForegroundColor Yellow }
    }
    $httpd = Join-Path $XamppDir "apache\bin\httpd.exe"
    if (Test-Path $httpd) {
        Get-Process "httpd" -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 1
        Start-Process -FilePath $httpd -WindowStyle Hidden
        Write-Host "  apache process restarted." -ForegroundColor Green
    } else {
        Write-Host "  could not locate httpd.exe at $httpd" -ForegroundColor Red
    }
}

# ── Add hosts file + vhost block for a domain ────────────────────────────────
function Add-HnHostEntry {
    param(
        [string]$Domain,
        [string]$DocRoot,
        [string]$HostsPath,
        [string]$VhostsPath,
        [string]$SubPathRedirect = ""   # optional: if set, adds RedirectMatch ^/$ /<subpath>/
    )
    $wwwAlias = "www.$Domain"
    $n = "`r`n"

    foreach ($d in @($Domain, $wwwAlias)) {
        if (!(Select-String -Path $HostsPath -Pattern ([regex]::Escape($d)) -Quiet)) {
            Add-Content -Path $HostsPath -Value "`r`n127.0.0.1`t$d" -ErrorAction SilentlyContinue
            Write-Host "  hosts: added $d" -ForegroundColor Green
        }
    }

    if (!(Select-String -Path $VhostsPath -Pattern ([regex]::Escape("ServerName $Domain")) -Quiet)) {
        $block  = "${n}# Custom Domain Automator: $Domain${n}"
        $block += "<VirtualHost *:80>${n}"
        $block += "    DocumentRoot `"$DocRoot`"${n}"
        $block += "    ServerName $Domain${n}"
        $block += "    ServerAlias $wwwAlias${n}"
        $block += "    <Directory `"$DocRoot`">${n}"
        $block += "        AllowOverride All${n}"
        $block += "        Require all granted${n}"
        $block += "    </Directory>${n}"
        if ($SubPathRedirect -ne '') {
            $block += "    RedirectMatch ^/`$ /$SubPathRedirect/${n}"
        }
        $block += "</VirtualHost>${n}"
        Add-Content -Path $VhostsPath -Value $block
        Write-Host "  vhost: added $Domain" -ForegroundColor Green
    } else {
        Write-Host "  vhost: $Domain already exists, skipping." -ForegroundColor Yellow
    }
}

# ── Find mirrored content folder inside HTTrack output ───────────────────────
function Find-MirrorSource {
    param([string]$MirrorOut, [string]$Domain)
    foreach ($candidate in @("$MirrorOut\$Domain", "$MirrorOut\www.$Domain")) {
        if (Test-Path $candidate) { return $candidate }
    }
    $subdirs = Get-ChildItem -Path $MirrorOut -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '^(hts-cache|hts-log)' }
    foreach ($d in $subdirs) {
        $hasFiles = Get-ChildItem -Path $d.FullName -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '\.(html?|css|js|php|aspx|png|jpg|jpeg|gif|pdf|svg|webp)$' } |
            Select-Object -First 1
        if ($hasFiles) { return $d.FullName }
    }
    return $null
}

# ── Mirror a URL with HTTrack ─────────────────────────────────────────────────
function Invoke-HnMirror {
    param([string]$Url, [string]$OutFolder, [string]$HttrackExe, [string]$Depth = "2")
    $htArgs = @($Url, "-O", $OutFolder, "-w", "-r$Depth", "-%e0", "-n", "-%s")
    & $HttrackExe $htArgs 2>&1 | Out-Null
}

# ── Direct file download fallback ────────────────────────────────────────────
function Invoke-HnDirectDownload {
    param([string]$Url, [string]$DestDir)
    try {
        $lu       = [System.Uri]$Url
        $filePath = $lu.AbsolutePath.TrimStart('/')
        $destFile = Join-Path $DestDir ($filePath -replace '[?#].*$', '' -replace '[/\\]', '\')
        $destFolder = Split-Path $destFile -Parent
        if (!(Test-Path $destFolder)) { New-Item -ItemType Directory -Path $destFolder -Force | Out-Null }
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "Mozilla/5.0")
        $wc.DownloadFile($Url, $destFile)
        $wc.Dispose()
        return $true
    } catch { return $false }
}

Export-ModuleMember -Function `
    Invoke-HnDownload, `
    Find-XamppDir, `
    Install-Xampp, `
    Find-HttrackExe, `
    Install-Httrack, `
    Restart-Apache, `
    Add-HnHostEntry, `
    Find-MirrorSource, `
    Invoke-HnMirror, `
    Invoke-HnDirectDownload
