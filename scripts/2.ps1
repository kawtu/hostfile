# ── Variables ─────────────────────────────────────────────────────────────────
$PSScriptRoot = if ($env:SETUP_WORKDIR) { $env:SETUP_WORKDIR } else { (Get-Location).Path }

$customDomain  = $env:TARGET_URL -replace '^https?://', '' -replace '/$', ''
$cleanHostname = $customDomain -split '/' | Select-Object -First 1
$baseDomain    = $cleanHostname -replace '^www\.', ''
$wwwDomain     = "www.$baseDomain"

$hostsPath = "$env:windir\System32\drivers\etc\hosts"
$XamppInstallDir = $env:XAMPP_DIR

$apachePath = "$XamppInstallDir/apache"
$htdocsPath = "$XamppInstallDir/htdocs"

$documentRoot = "$htdocsPath/webapp"
# ──────────────────────────────────────────────────────────────────────────────

if ($customDomain -notlike "www.*") { $customDomain = "www.$customDomain"; }
if (!(Test-Path "$documentRoot")) {
    Write-Host "`[3.ps1:XAMPP-fetch] could not locate the project: $documentRoot" -ForegroundColor Red; Exit 1;
}

Write-Host "[2.ps1:HOST] setting up host file patches for $baseDomain" -ForegroundColor Cyan
$entries = @("127.0.0.1`t$baseDomain", "127.0.0.1`t$wwwDomain")
foreach ($entry in $entries) {
    Write-Host "[2.ps1:HOST-add] proceeding to add $domainOnly to the host file." -ForegroundColor Cyan
    $domainOnly = $entry -split "`t" | Select-Object -Last 1
    if (!(Select-String -Path $hostsPath -Pattern ([regex]::Escape($domainOnly)) -Quiet)) {
        try {
            Write-Host "[2.ps1:HOST-add] adding..." -ForegroundColor Yellow
            Add-Content -Path $hostsPath -Value "`r`n$entry" -ErrorAction Stop
            Write-Host "[2.ps1:HOST-add] added $domainOnly" -ForegroundColor Green
        } 
        catch {
            Write-Host "[2.ps1:HOST-alert] the host file is locked, most likely in-use by other applications." -ForegroundColor Red
            $choice = Read-Host "Proceed with backup and force-addition of $domainOnly to the host file? [y/n]:" -ForegroundColor Yellow
            if ($choice -eq 'Y' -or $choice -eq 'y') {
                try {
                    Write-Host "[2.ps1:HOST-backup] creating a backup..." -ForegroundColor Yellow
                    $backupPath = "$hostsPath.backup"; $currentContent = Get-Content -Path $hostsPath -Raw;
                    $updatedContent = $currentContent.TrimEnd() + "`r`n$entry"
                    if (Test-Path $backupPath) { Remove-Item $backupPath -Force }
                    Rename-Item -Path $hostsPath -NewName "hosts.backup" -Force
                    Write-Host "[2.ps1:HOST-backup] backup created." -ForegroundColor Green
                    Write-Host "[2.ps1:HOST-update] updating host file with new content..." -ForegroundColor Yellow
                    $updatedContent | Out-File -FilePath $hostsPath -Encoding ASCII
                    Write-Host "[2.ps1:HOST-update] successfully updated." -ForegroundColor Green
                } catch { Write-Host "[2.ps1:HOST-lock] hard lock detected, close programs and try again." -ForegroundColor Red; }
            }
        }
    } else { Write-Host "[2.ps1:HOST-skip] $domainOnly is already in the host file." -ForegroundColor Yellow; }
}
