# ── Config ────────────────────────────────────────────────────────────────────
$XamppDownloadUrl   = "https://sourceforge.net/projects/xampp/files/XAMPP%20Windows/8.2.12/xampp-windows-x64-8.2.12-0-VS16-installer.exe/download"
$HttrackDownloadUrl = "https://download.httrack.com/httrack_x64-3.49.2.exe"

$repoBase       = "https://raw.githubusercontent.com/ketw/hostnet/main"
$repoApi        = "https://api.github.com/repos/ketw/hostnet/contents/scripts"

$elevateCmd = "irm $repoBase/setup.ps1 | iex"
# ──────────────────────────────────────────────────────────────────────────────

$uIdentity = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = ($uIdentity).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if (-not $isAdmin) {
    Write-Warning "Administrator Privileges are required, elevating setup script..."
    if ($PSCommandPath) { Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs }
    else { Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"$elevateCmd`"" -Verb RunAs }; Exit;
}

$Host.UI.RawUI.BackgroundColor = "Black"
$Host.UI.RawUI.ForegroundColor = "White"
Clear-Host

Write-Host "[Message] Initializing..." -ForegroundColor Cyan
do {
    $inputUrl = Read-Host "[setup.ps1:SYSTEM-input] target URL (e.g. https://example.com/path)"
    $inputUrl = $inputUrl.Trim()
    if ([string]::IsNullOrWhiteSpace($inputUrl)) {
        Write-Host "[Input-Warning] target URL cannot be empty." -ForegroundColor Yellow
    }
} while ([string]::IsNullOrWhiteSpace($inputUrl))
if ($inputUrl -notmatch '^https?://') { $inputUrl = "https://$inputUrl" }
Write-Host ""; $env:TARGET_URL = $inputUrl;
Write-Host "[setup.ps1:SYSTEM@target] set to $($env:TARGET_URL)" -ForegroundColor Green

$workDir = Join-Path $env:TEMP "setup_workspace"
if (-not (Test-Path $workDir)) { New-Item -ItemType Directory -Path $workDir | Out-Null }
$env:SETUP_WORKDIR = $workDir
Write-Host "[setup.ps1:SYSTEM@dir]: $workDir" -ForegroundColor Gray

Write-Host ""

$httrackInstallDir  = "C:\Program Files\WinHTTrack"
$env:HTTRACK_EXE    = ""
$httrackExe         = Join-Path $httrackInstallDir "httrack.exe"
Write-Host "[setup.ps1:HTTRACK] finding httrack..." -ForegroundColor Cyan

if (-not (Test-Path $httrackExe)) {
    $httrackInPath = Get-Command "httrack.exe" -ErrorAction SilentlyContinue
    if ($httrackInPath) { $httrackExe = $httrackInPath.Source }
}
if (-not (Test-Path $httrackExe)) {
    Write-Host "[setup.ps1:HTTRACK-download] could not locate httrack, proceeding to download." -ForegroundColor Yellow
    $httrackInstaller = Join-Path $workDir "httrack_setup.exe"
    try {
        Write-Host "[setup.ps1:HTTRACK-download] downloading HTTRACK..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri $HttrackDownloadUrl -OutFile $httrackInstaller -UseBasicParsing
        Write-Host "[setup.ps1:HTTRACK-install] installing HTTRACK..." -ForegroundColor Yellow
        Start-Process -FilePath $httrackInstaller -ArgumentList "/VERYSILENT", "/SUPPRESSMSGBOXES", "/DIR=`"$httrackInstallDir`"" -Wait
        if (Test-Path $httrackInstaller) { Remove-Item $httrackInstaller -Force }
        $httrackExe = Join-Path $httrackInstallDir "httrack.exe"
    } catch { Write-Host "[setup.ps1:HTTRACK-download] failed to download/install, error: $_" -ForegroundColor Red; Exit 1; }
}
if (Test-Path $httrackExe) { $env:HTTRACK_EXE = $httrackExe } else {
    Write-Host "[setup.ps1:HTTRACK-install] failed, could not locate exe at $httrackExe" -ForegroundColor Red; Exit 1; }
Write-Host "[setup.ps1:HTTRACK] found httrack: $httrackExe" -ForegroundColor Green

$XamppInstallDir    = $null
$env:XAMPP_DIR      = ""
$RegistryPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\xampp",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\xampp"
)
Write-Host "[setup.ps1:XAMPP] finding xampp..."
foreach ($path in $RegistryPaths) {
    if (Test-Path $path) {
        $XamppInstallDir = (Get-ItemProperty -Path $path).InstallLocation;
        if ($XamppInstallDir) { break } }
}
if (-not $XamppInstallDir) {
    $Drives = Get-PSDrive -PSProvider FileSystem
    foreach ($Drive in $Drives) {
        $PotentialPath = Join-Path -Path $Drive.Root -ChildPath "xampp"
        if (Test-Path "$PotentialPath\xampp-control.exe")
        { $XamppInstallDir = $PotentialPath; break; }
    }
}
if (-not $XamppInstallDir) {
    Write-Host "[setup.ps1:XAMPP-download] could not locate xampp, proceeding to download..." -ForegroundColor Yellow
    $InstallerPath = Join-Path -Path $workDir -ChildPath "xampp-installer.exe"
    try {
        Write-Host "[setup.ps1:XAMPP-download] downloading XAMPP..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $XamppDownloadUrl -OutFile $InstallerPath -UseBasicParsing -UserAgent "Wget" -ErrorAction Stop
        $fileSize = (Get-Item $InstallerPath).Length
        if ($fileSize -lt 10MB) {
            Write-Host "[setup.ps1:XAMPP-download] error occured due to internals outdated, likely link redirection issue." -ForegroundColor Red
            throw "[setup.ps1:XAMPP-download] failed to download, file was too small ($([math]::Round($fileSize/1MB,1))mb)"
        }
        Write-Host "[setup.ps1:XAMPP-install] installing XAMPP..." -ForegroundColor Cyan
        $proc = Start-Process -FilePath $InstallerPath -ArgumentList "--mode unattended", "--unattendedmodeui none", "--launchapps 0" -Wait -PassThru
        if ($null -ne $InstallerPath -and (Test-Path $InstallerPath)) { Remove-Item $InstallerPath -Force }
        $XamppInstallDir = $null
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
                if (Test-Path "$PotentialPath\xampp-control.exe") { $XamppInstallDir = $PotentialPath; break }
            }
        }
        if (-not $XamppInstallDir) { $XamppInstallDir = "C:\xampp" }
        $env:XAMPP_DIR = $XamppInstallDir
    } catch { Write-Host "[setup.ps1:XAMPP-download] download failed: $($_.Exception.Message)" -ForegroundColor Red; Pause; Exit; }
} else {
    $env:XAMPP_DIR = $XamppInstallDir
}
Write-Host "[setup.ps1:XAMPP] found xampp: $XamppInstallDir" -ForegroundColor Green

Write-Host ""

Write-Host "[Fetch] fetching list from GitHub..." -ForegroundColor Cyan
try {
    $files = Invoke-RestMethod -Uri $repoApi -Headers @{ "User-Agent" = "setup-script" }
    $scriptList = $files |
        Where-Object { $_.type -eq "file" -and $_.name -like "*.ps1" } |
        Sort-Object { $_.name } |
        ForEach-Object { "scripts/$($_.name)" }
    Write-Host "[Fetch] retrieved $($scriptList.Count) scripts to run:" -ForegroundColor Gray
    $scriptList | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }
} catch { Write-Host "[Fetch] failed to fetch script list from GitHub: $_" -ForegroundColor Red; Pause; Exit 1; }

foreach ($script in $scriptList) {
    $scriptName = Split-Path $script -Leaf
    $url        = "$repoBase/$script"
    $tmpFile    = Join-Path $workDir $scriptName
    Write-Host ""; Write-Host "[Execution]: executing $script" -ForegroundColor Yellow;
    try {
        $headers = @{ "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" }
        Write-Host "────────────────────────────────────────────────────"
        Invoke-RestMethod -Uri $url -OutFile $tmpFile -Headers $headers
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tmpFile
        Write-Host "────────────────────────────────────────────────────"
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[Execution]: script '$script' was a success." -ForegroundColor Green
        } else {Write-Host "[Execution]: script '$script' exited with code $LASTEXITCODE" -ForegroundColor Red}
    }
    catch { Write-Host "[Execution] script '$script' failed to execute, error: $_" -ForegroundColor Red }
    finally {if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force }}
}

Write-Host ""

Write-Host "[Message] patch planted" -ForegroundColor Cyan
Pause; Remove-Item -Path $workDir -Recurse -Force; Exit;