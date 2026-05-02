# ── Variables ─────────────────────────────────────────────────────────────────
$workDir = if ($env:SETUP_WORKDIR) { $env:SETUP_WORKDIR } else { (Get-Location).Path }

$XamppInstallDir = $env:XAMPP_DIR
$httrackExe      = $env:HTTRACK_EXE
$url             = $env:TARGET_URL

$HtdocsPath = Join-Path -Path $XamppInstallDir -ChildPath "htdocs"

$uri        = [System.Uri]$url
$baseDomain = ($uri.Host -replace '^www\.', '')
$subPath    = $uri.AbsolutePath.Trim('/')

$HtdocsDestinationPath = Join-Path -Path $HtdocsPath -ChildPath $baseDomain
# ──────────────────────────────────────────────────────────────────────────────

try {
    $folderName = $uri.Host -replace '[^a-zA-Z0-9]', '_'
} catch { $folderName = "Site_Download" }

$outputFolder   = Join-Path $workDir "Mirrored_$folderName"
$stagingPath    = Join-Path $workDir "staging"
if (-not (Test-Path $stagingPath)) { New-Item -ItemType Directory -Path $stagingPath | Out-Null }

if (Test-Path $httrackExe) {
    Write-Host "[1.ps1:HTTRACK-mirror] automated mirror of: $url" -ForegroundColor Cyan
    Write-Host "[1.ps1:HTTRACK-config] action 'Download web site(s)'" -ForegroundColor Cyan
    if (-not (Test-Path $outputFolder)) { New-Item -ItemType Directory -Path $outputFolder | Out-Null }
    Write-Host "[1.ps1:HTTRACK-mirror] starting mirror" -ForegroundColor Yellow
    $arguments = @($url, "-O", $outputFolder, "-w"); & $httrackExe $arguments
    Write-Host "[1.ps1:HTTRACK-mirror] mirror complete" -ForegroundColor Green

    Write-Host "[1.ps1:XAMPP-extract] locating mirrored content..." -ForegroundColor Yellow
    $possiblePaths = @(
        (Join-Path -Path $outputFolder -ChildPath $baseDomain),
        (Join-Path -Path $outputFolder -ChildPath "www.$baseDomain")
    )
    $innerSourcePath = $null
    foreach ($path in $possiblePaths) { if (Test-Path $path) { $innerSourcePath = $path; break } }
    if (-not $innerSourcePath) { Write-Host "[1.ps1:XAMPP-fetch] could not locate mirrored directory for: $baseDomain" -ForegroundColor Red; Exit 1 }
    Write-Host "[1.ps1:XAMPP-fetch] located: $innerSourcePath" -ForegroundColor Green

    Write-Host "[1.ps1:XAMPP-extract] extracting..." -ForegroundColor Yellow
    Copy-Item -Path "$innerSourcePath\*" -Destination $stagingPath -Recurse -Force
    Write-Host "[1.ps1:XAMPP-extract] extraction complete." -ForegroundColor Green

    if (-not (Test-Path $HtdocsPath)) { Write-Host "[1.ps1:XAMPP-fetch] could not locate htdocs: $HtdocsPath" -ForegroundColor Red; Exit 1 }

    Write-Host "[1.ps1:XAMPP-deploy] deployment target: $HtdocsDestinationPath" -ForegroundColor Cyan
    if (-not (Test-Path $HtdocsDestinationPath)) { New-Item -ItemType Directory -Path $HtdocsDestinationPath | Out-Null }
    Write-Host "[1.ps1:XAMPP-deploy] deploying..." -ForegroundColor Yellow
    Copy-Item -Path "$stagingPath\*" -Destination $HtdocsDestinationPath -Recurse -Force
    Write-Host "[1.ps1:XAMPP-deploy] deployed to htdocs\$baseDomain" -ForegroundColor Green
} else {
    Write-Host "[1.ps1:HTTRACK-install] could not locate exe at $httrackExe" -ForegroundColor Red; Exit 1
}
