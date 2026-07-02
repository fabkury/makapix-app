# Build the Makapix Android APK: cross-compile the Rust engine to .so for Android ABIs,
# bundle into jniLibs, and build a release APK.
#
# Prereqs (one-time):
#   rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
#   cargo install cargo-ndk
#   Android SDK + NDK installed (Android Studio or sdkmanager)
#
# Usage:  ./build_android.ps1            (build APK, dev back end)
#         ./build_android.ps1 -Install   (build APK, then install to a USB-connected phone)
#         ./build_android.ps1 -Prod      (point the app at the production back end, makapix.club)
#         ./build_android.ps1 -Bundle    (build a signed .aab for Play upload instead of an APK)
param([switch]$Install, [switch]$Prod, [switch]$Bundle)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

# Locate the NDK (newest installed under the SDK).
$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { "$env:LOCALAPPDATA\Android\Sdk" }
$ndkDir = Get-ChildItem "$sdk\ndk" -Directory | Sort-Object Name -Descending | Select-Object -First 1
if (-not $ndkDir) { throw "No NDK found under $sdk\ndk. Install it via Android Studio > SDK Manager > SDK Tools > NDK." }
$env:ANDROID_NDK_HOME = $ndkDir.FullName
Write-Host "==> Using NDK: $($env:ANDROID_NDK_HOME)" -ForegroundColor Cyan

# x86_64 is included because `flutter build apk` ships x86_64 Flutter libs by default; without a
# matching engine .so, x86_64 devices (BlueStacks, emulators, Intel Chromebooks) install the x86_64
# ABI and dlopen fails at runtime.
Write-Host "==> Cross-compiling engine to Android (.so) for arm64-v8a + armeabi-v7a + x86_64..." -ForegroundColor Cyan
cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 -o "$root\app\android\app\src\main\jniLibs" build -p makapix-ffi --release
if ($LASTEXITCODE -ne 0) { exit 1 }

# CLUB_ENV selects the back end (club_config.dart); default `dev`, `prod` targets makapix.club.
$clubEnv = if ($Prod) { "prod" } else { "dev" }

if ($Bundle) {
  # Signed Android App Bundle for the Play Store (release signing comes from app/android/key.properties).
  Write-Host "==> Building release AAB (CLUB_ENV=$clubEnv)..." -ForegroundColor Cyan
  Push-Location "$root\app"
  flutter build appbundle --release --dart-define=CLUB_ENV=$clubEnv
  Pop-Location
  if ($LASTEXITCODE -ne 0) { exit 1 }

  $aab = "$root\app\build\app\outputs\bundle\release\app-release.aab"
  Write-Host "==> AAB ready: $aab" -ForegroundColor Green
  if ($Install) { Write-Host "    (-Install is ignored for -Bundle; an .aab is uploaded to Play, not adb-installed.)" -ForegroundColor Yellow }
  return
}

Write-Host "==> Building release APK (CLUB_ENV=$clubEnv)..." -ForegroundColor Cyan
Push-Location "$root\app"
flutter build apk --release --dart-define=CLUB_ENV=$clubEnv
Pop-Location
if ($LASTEXITCODE -ne 0) { exit 1 }

$apk = "$root\app\build\app\outputs\flutter-apk\app-release.apk"
Write-Host "==> APK ready: $apk" -ForegroundColor Green

if ($Install) {
  $adb = "$sdk\platform-tools\adb.exe"
  Write-Host "==> Installing to connected device..." -ForegroundColor Cyan
  & $adb install -r $apk
}
