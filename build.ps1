# Build the Makapix engine DLL + the Windows app, and bundle the DLL next to the exe.
# Usage:  ./build.ps1            (release build)
#         ./build.ps1 -Run       (build then launch the app)
param([switch]$Run)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

Write-Host "==> Building Rust engine FFI DLL (release)..." -ForegroundColor Cyan
cargo build -p makapix-ffi --release
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "==> Running engine test suite..." -ForegroundColor Cyan
cargo test 2>&1 | Select-String "test result"

Write-Host "==> Building Flutter Windows app (release)..." -ForegroundColor Cyan
Push-Location "$root/app"
flutter build windows --release
Pop-Location
if ($LASTEXITCODE -ne 0) { exit 1 }

$exeDir = "$root/app/build/windows/x64/runner/Release"
Copy-Item "$root/target/release/makapix_ffi.dll" $exeDir -Force
Write-Host "==> Done. App: $exeDir/makapix_editor.exe" -ForegroundColor Green

if ($Run) { Start-Process "$exeDir/makapix_editor.exe" }
