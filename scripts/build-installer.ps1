# ============================================================
# IceDownloader — Build Script
# Requirements: PowerShell 7+, Inno Setup 6
# ============================================================

$ErrorActionPreference = "Stop"
$ROOT     = Split-Path -Parent $PSScriptRoot
$EXT_DIR  = Join-Path $ROOT "IceDownloader"
$ISS_FILE = Join-Path $ROOT "installer.iss"
$INNO     = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"

Write-Host "`n=== IceDownloader Build ===" -ForegroundColor Cyan

# Step 1: Rust
Write-Host "`n[1/2] Building Rust daemon..." -ForegroundColor Yellow
Push-Location (Join-Path $ROOT "ice-daemon")
cargo build --release
if ($LASTEXITCODE -ne 0) { Pop-Location; throw "Rust build failed" }
Pop-Location
Write-Host "      OK" -ForegroundColor Green

# Step 2: Inno Setup
Write-Host "[2/2] Building installer..." -ForegroundColor Yellow
& $INNO $ISS_FILE
if ($LASTEXITCODE -ne 0) { throw "Inno Setup compilation failed" }

$out = "$Env:USERPROFILE\Documents\Inno Setup Examples Output\IceDownloaderSetup.exe"
Write-Host "`n=== Done! ===" -ForegroundColor Cyan
Write-Host "Installer    : $out"
