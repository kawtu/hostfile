# ── Variables ─────────────────────────────────────────────────────────────────
$PSScriptRoot = if ($env:SETUP_WORKDIR) { $env:SETUP_WORKDIR } else { (Get-Location).Path }

$customDomain  = $env:TARGET_URL -replace '^https?://', '' -replace '/$', ''
$cleanHostname = $customDomain -split '/' | Select-Object -First 1
$baseDomain    = $cleanHostname -replace '^www\.', ''
$wwwDomain     = "www.$baseDomain"

# ──────────────────────────────────────────────────────────────────────────────

if ($customDomain -notlike "www.*") { $customDomain = "www.$customDomain"; }