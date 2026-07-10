#!/usr/bin/env bash
# build_ios.sh — build the Makapix Rust engine as a DYNAMIC framework xcframework for iOS.
#
# macOS-ONLY. Cross-compiling to Apple targets needs the Apple SDK + linker, so this
# cannot run on Windows/Linux (see docs/ios-release/PLAN.md §1). It runs in Codemagic CI
# (Phase 3), always BEFORE `flutter build ipa`.
#
# Why DYNAMIC (changed 2026-07-09): the engine originally linked statically into Runner
# and was reached via DynamicLibrary.process(). That requires the _mkpx_* symbols to
# survive -dead_strip AND stay in the main executable's export trie — behavior that
# Xcode 26's linker broke (-u roots silently stripped, -exported_symbol/-export_dynamic
# ignored; builds #8/#9 proved the flags reached the xcconfig yet the symbols vanished
# with no link error). A dynamic framework sidesteps the entire class of problem: a
# dylib IS its own export table, is never dead-stripped by the app link, and matches
# how Windows (.dll) and Android (.so) already ship. Dart opens it with
# DynamicLibrary.open('MakapixFFI.framework/MakapixFFI').
#
# Output: app/ios/MakapixFFI.xcframework   (git-ignored; regenerated every build)
#
# Usage:  ./build_ios.sh          # release (default)
#         ./build_ios.sh --debug  # debug arches (faster; for local Mac iteration)
set -euo pipefail

PROFILE="release"
CARGO_PROFILE_FLAG="--release"
if [[ "${1:-}" == "--debug" ]]; then
  PROFILE="debug"
  CARGO_PROFILE_FLAG=""
fi

# The workspace release profile uses thin-LTO, which makes Rust emit each crate's codegen units
# as LLVM bitcode instead of native objects. Apple's linker can't read Rust's newer-LLVM bitcode
# ("Unknown attribute kind"), so it silently drops the objects that hold our #[no_mangle] mkpx_*
# symbols — the app then links but DynamicLibrary.process() finds nothing at runtime. Force native
# codegen for the iOS cross-compile so the symbols land in the archive. This is scoped to iOS on
# purpose: the Windows DLL / Android .so link with Rust's own toolchain, where thin-LTO is fine, so
# the override lives here rather than in the shared [profile.release].
export CARGO_PROFILE_RELEASE_LTO=off

# Repo root = dir of this script.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

CRATE="makapix-ffi"
DYLIB="libmakapix_ffi.dylib"
FW_NAME="MakapixFFI"

DEVICE_TARGET="aarch64-apple-ios"        # iPhone/iPad (arm64)
SIM_ARM_TARGET="aarch64-apple-ios-sim"   # Apple-silicon simulator
SIM_X86_TARGET="x86_64-apple-ios"        # Intel simulator (older Macs / CI images)

echo "==> Ensuring Rust iOS targets are installed"
rustup target add "$DEVICE_TARGET" "$SIM_ARM_TARGET" "$SIM_X86_TARGET"

echo "==> Building $CRATE ($PROFILE) for device + simulator arches"
for T in "$DEVICE_TARGET" "$SIM_ARM_TARGET" "$SIM_X86_TARGET"; do
  echo "    - $T"
  cargo build -p "$CRATE" $CARGO_PROFILE_FLAG --target "$T"
done

OUT="$ROOT/target/ios"
rm -rf "$OUT"
mkdir -p "$OUT/device" "$OUT/sim"

# Wrap a dylib into a minimal framework bundle. Apple validates embedded frameworks'
# Info.plists at upload (ITMS), so the keys below are the required set.
#   $1 = dylib path   $2 = out dir   $3 = platform (iPhoneOS | iPhoneSimulator)
make_framework() {
  local FW="$2/$FW_NAME.framework"
  mkdir -p "$FW"
  cp "$1" "$FW/$FW_NAME"
  install_name_tool -id "@rpath/$FW_NAME.framework/$FW_NAME" "$FW/$FW_NAME"
  cat > "$FW/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>$FW_NAME</string>
  <key>CFBundleIdentifier</key><string>club.makapix.ffi</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$FW_NAME</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleSupportedPlatforms</key><array><string>$3</string></array>
  <key>MinimumOSVersion</key><string>13.0</string>
</dict>
</plist>
PLIST
}

echo "==> Fattening simulator dylib (arm64-sim + x86_64-sim)"
lipo -create \
  "target/$SIM_ARM_TARGET/$PROFILE/$DYLIB" \
  "target/$SIM_X86_TARGET/$PROFILE/$DYLIB" \
  -output "$OUT/sim/$DYLIB"

echo "==> Wrapping dylibs as frameworks"
make_framework "target/$DEVICE_TARGET/$PROFILE/$DYLIB" "$OUT/device" "iPhoneOS"
make_framework "$OUT/sim/$DYLIB" "$OUT/sim" "iPhoneSimulator"

XCFRAMEWORK="$ROOT/app/ios/$FW_NAME.xcframework"
echo "==> Packaging $XCFRAMEWORK"
rm -rf "$XCFRAMEWORK"
xcodebuild -create-xcframework \
  -framework "$OUT/device/$FW_NAME.framework" \
  -framework "$OUT/sim/$FW_NAME.framework" \
  -output "$XCFRAMEWORK"

echo "==> Done."
echo "    $XCFRAMEWORK"
echo "    Vendored by app/ios/makapix_ffi.podspec; embedded+signed into Runner.app/Frameworks."
