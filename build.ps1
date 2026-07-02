# Build the Makapix engine DLL + the Windows app, and bundle the DLL next to the exe.
# Usage:  ./build.ps1            (release build, prod back end — the default everywhere)
#         ./build.ps1 -Run       (build then launch the app)
#         ./build.ps1 -Dev       (point the app at the development back end)
param([switch]$Run, [switch]$Dev)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

Write-Host "==> Building Rust engine FFI DLL (release)..." -ForegroundColor Cyan
cargo build -p makapix-ffi --release
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "==> Running engine test suite..." -ForegroundColor Cyan
cargo test 2>&1 | Select-String "test result"

# CLUB_ENV selects the back end (club_config.dart); default `prod`, `-Dev` opts in to the dev server.
$clubEnv = if ($Dev) { "dev" } else { "prod" }
Write-Host "==> Building Flutter Windows app (release, CLUB_ENV=$clubEnv)..." -ForegroundColor Cyan
Push-Location "$root/app"
flutter build windows --release --dart-define=CLUB_ENV=$clubEnv
Pop-Location
if ($LASTEXITCODE -ne 0) { exit 1 }

$exeDir = "$root/app/build/windows/x64/runner/Release"
Copy-Item "$root/target/release/makapix_ffi.dll" $exeDir -Force
Write-Host "==> Done. App: $exeDir/makapix_club.exe" -ForegroundColor Green

if ($Run) { Start-Process "$exeDir/makapix_club.exe" }
