# Makapix Club

**Makapix Club** is a pixel-art social network: draw animated pixel art, publish it, react, comment,
follow, and remix. It exists as two independent, coexisting clients of the same `makapix.club` server:

- the **website** — [makapix.club](https://makapix.club) (a Next.js + FastAPI app, separate repo);
- **this app** — a **native (Rust + Flutter)** Makapix Club client for iOS, Android, and Windows.

**Get the app:**

- **iOS** — [Makapix Club on the App Store](https://apps.apple.com/us/app/makapix-club/id6788845118).
- **Android** — in Google Play closed testing; the public production release is pending. (Or build and
  sideload from source — see below.)
- **Windows** — build from source (see below).

This repository is **the app**. It has two pillars sharing one binary:

1. **Makapix Editor** — the built-in **animated pixel-art editor**: a deterministic, headless **Rust
   engine** with a thin **Flutter** shell. Draw, edit, and remix artwork natively — no account needed.
2. **The Club social layer** — feeds, reactions, comments, follows, profiles, search, notifications,
   players, and publishing — the full native counterpart to the website's social features.

> **Terminology** (so the docs stay unambiguous):
> - **Makapix Club** — the product/community. It has two faces: the **website** and **this app**.
> - **Makapix Editor** — the pixel-art editor *feature inside this app*. Not a separate product, not the app.
> - **This app** — the native Makapix Club client = *Makapix Editor* (the editor pillar) **+** the social
>   experience (the Club pillar).

## Documents

> **`SPEC.md`** and **`SPEC-CLUB.md`** are detailed internal design specifications (the editor engine and
> the social layer + server contract, respectively) and are **not included in this public repository**.

- **[`STATUS.md`](STATUS.md)** — honest implementation coverage; the status document.
- **[`PLAN.md`](PLAN.md)** — the build plan & Windows dev environment for the Editor pillar.
- **[`CLAUDE.md`](CLAUDE.md)** — the working repo guide (build commands, architecture, platform gotchas).
- **`docs/`** — deep dives: [`docs/mkpx-format/`](docs/mkpx-format/) (the `.mkpx` container spec),
  [`docs/memlab/REPORT.md`](docs/memlab/REPORT.md) (measured memory limits on real devices),
  [`docs/play-release.md`](docs/play-release.md) + [`docs/ios-release/PLAN.md`](docs/ios-release/PLAN.md)
  (store release pipelines).

## Core decisions

- Rust core, first-class & up front; Flutter shell over a hand-written C-ABI FFI (`dart:ffi`).
- Deterministic, headless engine is the source of truth; CPU reference compositor is canonical.
- 8-bit RGBA sRGB; premultiplied internal; integer-exact (goldens never fork per platform).
- Canvas 1×1–256×256; frames 1–1024; layers 1–64; per-frame 128-state undo with auto-compaction.
- Tiling (32×32) + copy-on-write + lazy alloc are mandatory; enforced memory budgets keep worst-case
  documents inside real device limits (`docs/memlab/REPORT.md`).
- Lossless, chunked, versioned `.mkpx` (v10: content-addressed tile dictionary, byte-deterministic);
  first-class palettes; full import (GIF/WebP/PNG/APNG/JPEG/BMP).
- The **social layer lives entirely in Dart** (`app/lib/club`); the Rust engine stays network-free &
  dependency-free. Dart fetches, Rust computes.
- Dev/test on **Windows** (engine + desktop + Android device); **iOS builds in Codemagic cloud CI**.

## The editor dev loop, in one line

`edit Rust → cargo test / mkpx run … (oracles, ASCII dumps, PNG diffs) → read results → edit Rust` —
all on a Windows workstation, no device or emulator in the common case.

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

The Rust engine cross-compiles to an Android `.so` (bundled into the APK via `jniLibs`); the Dart loader
opens `libmakapix_ffi.so` on Android. One-time prereqs: Android SDK + NDK, `rustup target add
aarch64-linux-android armv7-linux-androideabi`, `cargo install cargo-ndk`.

```powershell
./build_android.ps1              # cross-compiles .so (arm64+arm32) + builds app-release.apk
./build_android.ps1 -Install     # also installs to a USB-connected phone (USB debugging on)
```

The APK lands at `app/build/app/outputs/flutter-apk/app-release.apk`, app id **`club.makapix.app`**.
**Sideload (no cable):** copy the APK to the phone → tap it → allow "install unknown apps" → Install.
**Over USB:** enable Developer Options + USB debugging on the phone, connect it, then `adb install -r <apk>`.

## iOS (cloud CI only)

iOS is never built locally: `codemagic.yaml` builds the ipa in Codemagic, with the engine shipped as a
dynamic `MakapixFFI.framework`, and delivers it to TestFlight / the App Store. See
[`docs/ios-release/PLAN.md`](docs/ios-release/PLAN.md).
