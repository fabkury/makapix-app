# Building Makapix Club from source

This is the developer companion to the end-user [README](../README.md): how the repository is laid
out, how to build and run the app on each platform, and where the deeper documentation lives.

## What's in this repository

One Flutter binary with two co-equal pillars:

1. **Makapix Editor** — the built-in animated pixel-art editor: a deterministic, headless **Rust
   engine** (`crates/`) under a thin **Flutter** shell (`app/lib/editor/`).
2. **The Club social layer** — feeds, reactions, comments, follows, profiles, search, notifications,
   players, and publishing. Entirely Dart (`app/lib/club/`).

> **Terminology** (so the docs stay unambiguous):
> - **Makapix Club** — the product/community. It has two faces: the **website**
>   ([makapix.club](https://makapix.club), a separate repo) and **this app**.
> - **Makapix Editor** — the pixel-art editor *feature inside this app*. Not a separate product, not
>   the app.
> - **This app** — the native Makapix Club client = *Makapix Editor* (the editor pillar) **+** the
>   social experience (the Club pillar).

## Documents

> **`SPEC.md`** and **`SPEC-CLUB.md`** are detailed internal design specifications (the editor engine
> and the social layer + server contract, respectively) and are **not included in this public
> repository** — references to them in the docs won't resolve in a public checkout.

- **[`STATUS.md`](../STATUS.md)** — honest implementation coverage; the status document.
- **[`CLAUDE.md`](../CLAUDE.md)** — the working repo guide (build commands, architecture, platform
  gotchas).
- **`docs/`** — deep dives: [`docs/mkpx-format/`](mkpx-format/) (the `.mkpx` container spec),
  [`docs/memlab/REPORT.md`](memlab/REPORT.md) (measured memory limits on real devices),
  [`docs/play-release.md`](play-release.md) + [`docs/ios-release/PLAN.md`](ios-release/PLAN.md)
  (store release pipelines).

## Core decisions

- Rust core, first-class & up front; Flutter shell over a hand-written C-ABI FFI (`dart:ffi`).
- Deterministic, headless engine is the source of truth; CPU reference compositor is canonical.
- 8-bit RGBA sRGB; premultiplied internal; integer-exact (goldens never fork per platform).
- Canvas 1×1–512×512 (256 until 2026-09-03, ADR 0021); frames 1–1024; layers 1–64; per-frame
  128-state undo with auto-compaction.
- Tiling (32×32) + copy-on-write + lazy alloc are mandatory; enforced memory budgets keep worst-case
  documents inside real device limits ([`docs/memlab/REPORT.md`](memlab/REPORT.md)).
- Lossless, chunked, versioned `.mkpx` (v10: content-addressed tile dictionary, byte-deterministic);
  first-class palettes; full import (GIF/WebP/PNG/APNG/JPEG/BMP).
- The **social layer lives entirely in Dart** (`app/lib/club`); the Rust engine stays network-free &
  dependency-free. Dart fetches, Rust computes.
- Dev/test on **Windows** (engine + desktop + Android device); **iOS builds in Codemagic cloud CI**.

## The editor dev loop, in one line

`edit Rust → cargo test / mkpx run … (oracles, ASCII dumps, PNG diffs) → read results → edit Rust` —
all on a Windows workstation, no device or emulator in the common case.

## Toolchain setup (Windows 11)

The engine loop needs only Rust; the interactive and Android tiers need more. Each row has a
verification command.

| Tool | Install | Verify |
|------|---------|--------|
| **Rust (MSVC)** | `winget install Rustlang.Rustup` → `rustup default stable-x86_64-pc-windows-msvc` | `rustc --version` (the workspace floor is `rust-version = "1.96"` in `Cargo.toml`) |
| **VS Build Tools (C++)** | the "Desktop development with C++" workload (MSVC linker; Flutter Windows needs it too) **plus the "C++ ATL" component** (`flutter_secure_storage_windows` includes `<atlstr.h>`) | `cl.exe` resolves in a dev shell |
| **Git** | `winget install Git.Git` | `git --version` |
| **Flutter SDK** | download stable, add to `PATH`; then `flutter config --enable-windows-desktop` | `flutter doctor`; `flutter devices` lists **Windows** |
| **Android Studio** | `winget install Google.AndroidStudio` (SDK, platform-tools) + the **NDK** via the SDK Manager | `adb --version` |
| **Rust Android targets** | `rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android` | `rustup target list --installed` |
| **cargo-ndk** | `cargo install cargo-ndk` | `cargo ndk --version` |

With just the first row, `cargo test` and `cargo run -p makapix-cli -- run …` run the entire
headless Tier-1 loop natively. There is no task runner beyond the root scripts
(`build.ps1` · `build_android.ps1` · `release_android.ps1` · `build_ios.sh`) and no CI besides
`codemagic.yaml` (iOS); the automated gates live in `release_android.ps1` and Codemagic's R2 check.

## Build & run on Windows

```powershell
./build.ps1 -Run        # builds the DLL + tests + Windows app, bundles the DLL, launches it
# or manually:
cargo build -p makapix-ffi --release
cargo test                                          # full Rust suite
cargo run -p makapix-cli -- run examples/showcase.txt "render:0:out.png:6" state assert.roundtrip
cd app && flutter run -d windows                    # interactive UI (debug)
```

The prebuilt release app is at `app/build/windows/x64/runner/Release/makapix_club.exe`.

## Build & install on Android

The Rust engine cross-compiles to an Android `.so` (bundled into the APK via `jniLibs`); the Dart
loader opens `libmakapix_ffi.so` on Android. One-time prereqs: the Android rows of the toolchain
table above (SDK + NDK, the three rustup targets, `cargo-ndk`).

```powershell
./build_android.ps1              # cross-compiles .so (arm64-v8a + armeabi-v7a + x86_64) + builds app-release.apk
./build_android.ps1 -Install     # also installs to a USB-connected phone (USB debugging on)
```

The APK lands at `app/build/app/outputs/flutter-apk/app-release.apk`, app id **`club.makapix.app`**.
**Sideload (no cable):** copy the APK to the phone → tap it → allow "install unknown apps" → Install.
**Over USB:** enable Developer Options + USB debugging on the phone, connect it, then
`adb install -r <apk>`.

## iOS (cloud CI only)

iOS is never built locally: `codemagic.yaml` builds the ipa in Codemagic, with the engine shipped as
a dynamic `MakapixFFI.framework`, and delivers it to TestFlight / the App Store. See
[`docs/ios-release/PLAN.md`](ios-release/PLAN.md).
