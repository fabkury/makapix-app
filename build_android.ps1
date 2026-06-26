# Build the Makapix Android APK: cross-compile the Rust engine to .so for Android ABIs,
# bundle into jniLibs, and build a release APK.
#
# Prereqs (one-time):
#   rustup target add aarch64-linux-android armv7-linux-androideabi
#   cargo install cargo-ndk
#   Android SDK + NDK installed (Android Studio or sdkmanager)
#
# Usage:  ./build_android.ps1            (build APK)
#         ./build_android.ps1 -Install   (build, then install to a USB-connected phone)
param([switch]$Install)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

# Locate the NDK (newest installed under the SDK).
$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { "$env:LOCALAPPDATA\Android\Sdk" }
$ndkDir = Get-ChildItem "$sdk\ndk" -Directory | Sort-Object Name -Descending | Select-Object -First 1
if (-not $ndkDir) { throw "No NDK found under $sdk\ndk. Install it via Android Studio > SDK Manager > SDK Tools > NDK." }
$env:ANDROID_NDK_HOME = $ndkDir.FullName
Write-Host "==> Using NDK: $($env:ANDROID_NDK_HOME)" -ForegroundColor Cyan

Write-Host "==> Cross-compiling engine to Android (.so) for arm64-v8a + armeabi-v7a..." -ForegroundColor Cyan
cargo ndk -t arm64-v8a -t armeabi-v7a -o "$root\app\android\app\src\main\jniLibs" build -p makapix-ffi --release
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "==> Building release APK..." -ForegroundColor Cyan
Push-Location "$root\app"
flutter build apk --release
Pop-Location
if ($LASTEXITCODE -ne 0) { exit 1 }

$apk = "$root\app\build\app\outputs\flutter-apk\app-release.apk"
Write-Host "==> APK ready: $apk" -ForegroundColor Green

if ($Install) {
  $adb = "$sdk\platform-tools\adb.exe"
  Write-Host "==> Installing to connected device..." -ForegroundColor Cyan
  & $adb install -r $apk
}
