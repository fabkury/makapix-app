#!/usr/bin/env bash
# build_ios.sh — build the Makapix Rust engine as a STATIC xcframework for iOS.
#
# macOS-ONLY. Cross-compiling to Apple targets needs the Apple SDK + linker, so this
# cannot run on Windows/Linux (see docs/ios-release/PLAN.md §1). It runs on the cloud
# Mac (Phase 2) and in Codemagic CI (Phase 3), always BEFORE `flutter build ipa`.
#
# Why static: app/lib/engine_ffi.dart resolves the engine via DynamicLibrary.process()
# on iOS — i.e. the Rust symbols (mkpx_run, mkpx_display, …) must be linked INTO the
# Runner binary, not shipped as a loadable .dylib. crates/ffi emits a `staticlib`
# (libmakapix_ffi.a); this script fattens the simulator slice and packages a device +
# simulator xcframework that app/ios/makapix_ffi.podspec vendors into the Runner target.
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

# Repo root = dir of this script.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

CRATE="makapix-ffi"
LIB="libmakapix_ffi.a"

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
mkdir -p "$OUT/sim"

echo "==> Fattening simulator archive (arm64-sim + x86_64-sim)"
lipo -create \
  "target/$SIM_ARM_TARGET/$PROFILE/$LIB" \
  "target/$SIM_X86_TARGET/$PROFILE/$LIB" \
  -output "$OUT/sim/$LIB"

XCFRAMEWORK="$ROOT/app/ios/MakapixFFI.xcframework"
echo "==> Packaging $XCFRAMEWORK"
rm -rf "$XCFRAMEWORK"
xcodebuild -create-xcframework \
  -library "target/$DEVICE_TARGET/$PROFILE/$LIB" \
  -library "$OUT/sim/$LIB" \
  -output "$XCFRAMEWORK"

echo "==> Done."
echo "    $XCFRAMEWORK"
echo "    Vendored by app/ios/makapix_ffi.podspec; linked into Runner on 'flutter build ipa'."
