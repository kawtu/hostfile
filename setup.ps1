# ── Config ────────────────────────────────────────────────────────────────────
$repoBase = "https://github.com/kawtu/hostfile/main"

$scriptList = @(
    "scripts/0.ps1",
    "scripts/1.ps1",
    "scripts/2.ps1",
    "scripts/3.ps1"
)

$elevateCmd = "irm $repoBase/setup.ps1 | iex"
# ──────────────────────────────────────────────────────────────────────────────

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if (-not $isAdmin) {
    Write-Warning "Administrator Privileges are required, elevating setup script..."
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -Command `"$elevateCmd`"" -Verb RunAs
    exit
}

$Host.UI.RawUI.BackgroundColor = "Black"
$Host.UI.RawUI.ForegroundColor = "White"
Clear-Host

Write-Host "`n[Message] Initializing..." -ForegroundColor Cyan

$workDir = Join-Path $env:TEMP "setup_workspace"
if (-not (Test-Path $workDir)) { New-Item -ItemType Directory -Path $workDir | Out-Null }
$env:SETUP_WORKDIR = $workDir
Write-Host "[Directory]: $workDir" -ForegroundColor Gray

foreach ($script in $scriptList) {
    $scriptName = Split-Path $script -Leaf
    $url        = "$repoBase/$script"
    $tmpFile    = Join-Path $workDir $scriptName

    Write-Host "[Execution]: executing $script" -ForegroundColor Yellow

    try {
        Invoke-RestMethod -Uri $url -OutFile $tmpFile

        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tmpFile

        if ($LASTEXITCODE -eq 0) {
            Write-Host "[Execution]: script $script was a success.`n" -ForegroundColor Green
        } else {
            Write-Warning "[Execution]: script $script exited with code $LASTEXITCODE"
        }
    }
    catch {
        Write-Error "[Execution] script $script failed to execute, error: $_"
    }
    finally {
        if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force }
    }
}

Write-Host "`n[Message] host has tricked" -ForegroundColor Cyan