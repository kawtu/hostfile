$PSScriptRoot = if ($env:SETUP_WORKDIR) { $env:SETUP_WORKDIR } else { (Get-Location).Path }

$url = "https://sarkariresult.com.cm/up-police-si-asi-2026/"
$scriptPath = $PSScriptRoot
if ([string]::IsNullOrEmpty($scriptPath)) { $scriptPath = (Get-Location).Path } 

$downloadPath = Join-Path $scriptPath "httrack_setup.exe"
$installDir = "C:\Program Files\WinHTTrack"
$httrackExe = Join-Path $installDir "httrack.exe"

try {
    $uri = [System.Uri]$url
    $folderName = $uri.Host -replace '[^a-zA-Z0-9]', '_'
} catch {
    $folderName = "Site_Download"
}
$outputFolder = Join-Path $scriptPath "Mirrored_$folderName"

if (-not (Test-Path $httrackExe)) {
    Write-Host "HTTrack not found. Downloading the latest 64-bit version..." -ForegroundColor Yellow
    $installerUrl = "https://download.httrack.com/httrack_x64-3.49.2.exe"
    Invoke-WebRequest -Uri $installerUrl -OutFile $downloadPath
    Write-Host "Installing HTTrack silently..." -ForegroundColor Yellow
    Start-Process -FilePath $downloadPath -ArgumentList "/VERYSILENT", "/SUPPRESSMSGBOXES", "/DIR=`"$installDir`"" -Wait
    if (Test-Path $downloadPath) { Remove-Item $downloadPath }
}

if (Test-Path $httrackExe) {
    Write-Host "Starting automated mirror for: $url" -ForegroundColor Green
    Write-Host "Action selected: Download web site(s)" -ForegroundColor Green
    if (-not (Test-Path $outputFolder)) { New-Item -ItemType Directory -Path $outputFolder | Out-Null }
    $arguments = @(
        $url,
        "-O", $outputFolder,
        "-w"
    )
    & $httrackExe $arguments
    Write-Host "Mirroring complete!" -ForegroundColor Green
    # Invoke-Item $outputFolder

    Write-Host "Extracting into a webapp..." -ForegroundColor Green
    $baseDomain = $url -replace '^https?://', '' -replace '^www\.', '' -split '/' | Select-Object -First 1
    $possiblePaths = @(
        (Join-Path -Path $outputFolder -ChildPath $baseDomain),
        (Join-Path -Path $outputFolder -ChildPath "www.$baseDomain")
    )
    $innerSourcePath = $null
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            $innerSourcePath = $path
            break
        }
    }
    $destinationPath = Join-Path -Path $PSScriptRoot -ChildPath "website"
    if ($innerSourcePath) {
        Write-Host "Found it at: $innerSourcePath" -ForegroundColor Cyan
        if (-not (Test-Path $destinationPath)) { New-Item -ItemType Directory -Path $destinationPath | Out-Null }
        Copy-Item -Path "$innerSourcePath\*" -Destination $destinationPath -Recurse -Force
        Write-Host "Done! Extraction complete." -ForegroundColor Green
    } else {
        Write-Warning "Could not find a folder for $baseDomain (checked with and without 'www.')"
        Write-Host "Check your output folder: $outputFolder" -ForegroundColor Yellow
    }
}
else {
    Write-Error "HTTrack installation failed or the executable could not be found at $httrackExe."
}