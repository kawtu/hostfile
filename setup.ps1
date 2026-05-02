# ── Config ────────────────────────────────────────────────────────────────────
$XamppDownloadUrl   = "https://sourceforge.net/projects/xampp/files/XAMPP%20Windows/8.2.12/xampp-windows-x64-8.2.12-0-VS16-installer.exe/download"
$HttrackDownloadUrl = "https://download.httrack.com/httrack_x64-3.49.2.exe"
$repoBase           = "https://raw.githubusercontent.com/ketw/hostnet/main"
$repoApi            = "https://api.github.com/repos/ketw/hostnet/contents/scripts"
$elevateCmd         = "irm $repoBase/setup.ps1 | iex"
# ──────────────────────────────────────────────────────────────────────────────

# ── Module ────────────────────────────────────────────────────────────────────
$hnModule = Join-Path $env:TEMP "hn.psm1"
if (-not (Test-Path $hnModule)) {
    Invoke-RestMethod -Uri "$repoBase/modules/hn.psm1" -OutFile $hnModule -Headers @{ "User-Agent" = "Mozilla/5.0" }
}
Import-Module $hnModule -Force -DisableNameChecking
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
$_uri      = [System.Uri]$inputUrl
$baseDomain = ($_uri.Host -replace '^www\.', '')
$subPath    = $_uri.AbsolutePath.Trim('/')
Write-Host "[setup.ps1:SYSTEM@target] set to $($env:TARGET_URL)" -ForegroundColor Green

$workDir = Join-Path $env:TEMP "setup_workspace"
if (-not (Test-Path $workDir)) { New-Item -ItemType Directory -Path $workDir | Out-Null }
$env:SETUP_WORKDIR = $workDir
Write-Host "[setup.ps1:SYSTEM@dir]: $workDir" -ForegroundColor Gray

Write-Host ""

$httrackInstallDir  = "C:\Program Files\WinHTTrack"
$env:HTTRACK_EXE    = ""
Write-Host "[setup.ps1:HTTRACK] finding httrack..." -ForegroundColor Cyan
$httrackExe = Find-HttrackExe
if (-not $httrackExe) {
    Write-Host "[setup.ps1:HTTRACK-download] could not locate httrack, proceeding to download." -ForegroundColor Yellow
    $httrackExe = Install-Httrack -DownloadUrl $HttrackDownloadUrl -WorkDir $workDir
}
if (-not $httrackExe) { Write-Host "[setup.ps1:HTTRACK-install] failed, could not locate exe." -ForegroundColor Red; Exit 1 }
$env:HTTRACK_EXE = $httrackExe
Write-Host "[setup.ps1:HTTRACK] found httrack: $httrackExe" -ForegroundColor Green

Write-Host "[setup.ps1:XAMPP] finding xampp..."
$XamppInstallDir = Find-XamppDir
if (-not $XamppInstallDir) {
    Write-Host "[setup.ps1:XAMPP-download] could not locate xampp, proceeding to download..." -ForegroundColor Yellow
    $XamppInstallDir = Install-Xampp -DownloadUrl $XamppDownloadUrl -WorkDir $workDir
}
if (-not $XamppInstallDir) { Write-Host "[setup.ps1:XAMPP-install] failed." -ForegroundColor Red; Pause; Exit }
$env:XAMPP_DIR = $XamppInstallDir
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

$launchUrl = "http://$baseDomain"
if ($subPath -ne '') { $launchUrl = "http://$baseDomain/$subPath/" }
Start-Process $launchUrl

Pause; Remove-Item -Path $workDir -Recurse -Force; Exit;