# ── Variables ─────────────────────────────────────────────────────────────────
$PSScriptRoot = if ($env:SETUP_WORKDIR) { $env:SETUP_WORKDIR } else { (Get-Location).Path }

$XamppInstallDir = $env:XAMPP_DIR
$httrackExe = $env:HTTRACK_EXE
$url = $env:TARGET_URL

$baseDomain = $url -replace '^https?://', '' -replace '^www\.', '' -split '/' | Select-Object -First 1
# ──────────────────────────────────────────────────────────────────────────────

try {
    $uri = [System.Uri]$url; $folderName = $uri.Host -replace '[^a-zA-Z0-9]', '_'
} catch { $folderName = "Site_Download"; }
$outputFolder = Join-Path $PSScriptRoot "Mirrored_$folderName"
$destinationPath = Join-Path -Path $PSScriptRoot -ChildPath "website"
if (-not (Test-Path $destinationPath)) { New-Item -ItemType Directory -Path $destinationPath | Out-Null }

if (Test-Path $httrackExe) {
    Write-Host "[1.ps1:HTTRACK-mirror] automated mirror of: $url" -ForegroundColor Cyan
    Write-Host "[1.ps1:HTTRACK-config] action 'Download web site(s)'" -ForegroundColor Cyan
    if (-not (Test-Path $outputFolder)) { New-Item -ItemType Directory -Path $outputFolder | Out-Null }
    Write-Host "[1.ps1:HTTRACK-mirror] starting mirror" -ForegroundColor Yellow
    $arguments = @($url, "-O", $outputFolder, "-w") & $httrackExe $arguments
    Write-Host "[1.ps1:HTTRACK-mirror] mirror complete" -ForegroundColor Green
    
    Write-Host "[1.ps1:XAMPP-extract] converting mirror into webapp" -ForegroundColor Yellow
    $possiblePaths = @(
        (Join-Path -Path $outputFolder -ChildPath $baseDomain),
        (Join-Path -Path $outputFolder -ChildPath "www.$baseDomain")
    )
    $innerSourcePath = $null
    Write-Host "[1.ps1:XAMPP-fetch] locating..." -ForegroundColor Yellow
    foreach ($path in $possiblePaths) { if (Test-Path $path) { $innerSourcePath = $path; break; } }
    if ($innerSourcePath) {
        Write-Host "[1.ps1:XAMPP-fetch] located: $innerSourcePath" -ForegroundColor Green
        
        Write-Host "[1.ps1:XAMPP-extract] extracting..." -ForegroundColor Yellow
        Copy-Item -Path "$innerSourcePath\*" -Destination $destinationPath -Recurse -Force
        Write-Host "[1.ps1:XAMPP-extract] extraction complete." -ForegroundColor Green
    } else { Write-Host "[1.ps1:XAMPP-fetch] could not locate the directory: $baseDomain" -ForegroundColor Yellow; Exit 1; }
}
else { Write-Host "[1.ps1:HTTRACK-install] could not locate exe at $httrackExe" -ForegroundColor Red; Exit 1; }