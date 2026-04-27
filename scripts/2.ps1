$PSScriptRoot = if ($env:SETUP_WORKDIR) { $env:SETUP_WORKDIR } else { (Get-Location).Path }

Write-Host "--- XAMPP Deployment Script ---" -ForegroundColor Cyan

$SourceFolder = Join-Path -Path $PSScriptRoot -ChildPath "website"
$InstallerPath = Join-Path -Path $env:TEMP -ChildPath "xampp-installer.exe"
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


if ($XamppInstallDir) {
    Write-Host "Found existing XAMPP installation at: $XamppInstallDir" -ForegroundColor Green
} else {
    Write-Host "XAMPP not detected. Proceeding with download..." -ForegroundColor Yellow
    $XamppDownloadUrl = "https://sourceforge.net/projects/xampp/files/XAMPP%20Windows/8.2.12/xampp-windows-x64-8.2.12-0-VS16-installer.exe/download"
    try {
        Invoke-WebRequest -Uri $XamppDownloadUrl -OutFile $InstallerPath -UserAgent "Mozilla/5.0" -ErrorAction Stop
        if ((Get-Item $InstallerPath).Length -lt 1MB) { throw "Downloaded file is too small/corrupted." }
        Write-Host "Installing XAMPP..." -ForegroundColor Cyan
        $process = Start-Process -FilePath $InstallerPath -ArgumentList "--mode unattended --launchapps 0" -Wait -PassThru
        $XamppInstallDir = "C:\xampp" 
    } catch {
        Write-Error "Download failed or file corrupted: $($_.Exception.Message)"
        Pause; Exit
    }
}

$HtdocsDir = Join-Path -Path $XamppInstallDir -ChildPath "htdocs"
$WebappDestDir = Join-Path -Path $HtdocsDir -ChildPath "webapp"

if (Test-Path $SourceFolder) {
    if (Test-Path $HtdocsDir) {
        Write-Host "Deploying to $WebappDestDir..." -ForegroundColor Cyan
        if (Test-Path $WebappDestDir) { Remove-Item -Path $WebappDestDir -Recurse -Force }
        Copy-Item -Path $SourceFolder -Destination $WebappDestDir -Recurse -Force
        Write-Host "Successfully deployed!" -ForegroundColor Green
    } else {
        Write-Error "Could not find htdocs in $XamppInstallDir"
    }
} else {
    Write-Error "Source folder 'website' not found next to script."
}

if ($null -ne $InstallerPath -and (Test-Path $InstallerPath)) { 
    Remove-Item $InstallerPath -Force 
}

Write-Host "--------------------------------------"
Write-Host "XAMPP setup complete!"