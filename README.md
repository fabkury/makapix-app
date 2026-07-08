# Makapix Club

**Makapix Club** is a pixel-art social network. It exists as two independent, coexisting products that do
**not** depend on each other:

- the **website** — [makapix.club](https://makapix.club) (the existing Next.js + FastAPI app);
- **this app** — a **native (Rust + Flutter)** Makapix Club client, a full counterpart to the website.

This repository is **the app**. It has two pillars:

1. **Makapix Editor** — the built-in **animated pixel-art editor**: a deterministic, headless **Rust engine**
   with a thin **Flutter** shell. It is the in-app successor to the website's embedded Piskel/Pixelc editors —
   draw, edit, and remix artwork natively. Specified in **`SPEC.md`** (an internal design doc — see *Documents*).
2. **The full Makapix Club social experience** — feeds, reactions, comments, follows, profiles, playlists,
   notifications, players, and publishing — a native alternative to the website's social features. Specified
   in **`SPEC-CLUB.md`** (an internal design doc — see *Documents*).

> **Terminology** (so the docs stay unambiguous):
> - **Makapix Club** — the product/community. It has two faces: the **website** and **this app**.
> - **Makapix Editor** — the pixel-art editor *feature inside this app*. Not a separate product, not the app.
> - **This app** — the native Makapix Club client = *Makapix Editor* (the editor pillar) **+** the social
>   experience (the Club pillar).

## Documents
> **`SPEC.md`** and **`SPEC-CLUB.md`** are detailed internal design specifications and are **not included in
> this public repository**. The summaries below describe what each covers.
- **`SPEC.md`** — the **Makapix Editor** specification (the editor pillar): the deterministic Rust
  engine, data model, memory/tiling/COW, the action-script DSL + verification harness, color/compositing, the
  `.mkpx` format, every tool/feature, undo + compaction, the FFI boundary, and the three-row editor UI.
- **`SPEC-CLUB.md`** — the **social-networking** specification (the Club pillar): accounts &
  auth, artwork conformance, publish, edit/remix, feeds & discovery, reactions, comments, profiles &
  following, search, notifications, playlists, analytics, players, and a website→app feature-parity matrix.
  It speaks to the live Makapix Club server (`makapix.club`).
- **[`PLAN.md`](PLAN.md)** — the build plan & Windows dev environment for the **Editor** pillar. (The social
  pillar's rollout is phased separately in `SPEC-CLUB.md` §28.)
- **[`STATUS.md`](STATUS.md)** — honest implementation coverage.

## Core decisions
- Rust core, first-class & up front; Flutter shell over a hand-written C-ABI FFI (`dart:ffi`).
- Deterministic, headless engine is the source of truth; CPU reference compositor is canonical.
- 8-bit RGBA sRGB; premultiplied internal; integer-exact (goldens never fork per platform).
- Canvas 8×8–256×256; frames 1–1024; layers 1–64; per-frame 128-state undo with auto-compaction.
- Tiling (32×32) + copy-on-write + lazy alloc + inactive-frame compression are mandatory.
- Lossless, chunked, versioned `.mkpx`; first-class palettes; full import (GIF/WebP/PNG/APNG/JPEG/BMP).
- The **social layer lives entirely in Dart** (`lib/club`); the Rust engine stays network-free &
  dependency-free (SPEC-CLUB §4). The engine only produces conformant artwork bytes and conformance verdicts.
- Dev/test on **Windows** (engine + desktop harness + Android device/emulator); **iOS deferred** to cloud
  macOS CI.

## The editor dev loop, in one line
`edit Rust → cargo test / mkpx run … (oracles, ASCII dumps, PNG diffs) → read results → edit Rust` —
all on this Windows 11 workstation, no device or emulator in the common case.

## Status

**Editor pillar — implemented & runnable (2026-06-25).** A working Rust engine + `mkpx` harness + FFI +
**Flutter Windows app** are built and tested on this workstation. See [`STATUS.md`](STATUS.md) for the full
matrix.

- **Engine** (`crates/engine`, dependency-free): tiled copy-on-write buffers, sRGB+HSV color, document/
  frames/layers/palettes, global undo timeline with per-frame 128-state compaction, the reference
  compositor, ~20 tools (pencil/brush/airbrush/eraser/bucket/gradient/line/rect/ellipse/dodge/burn/
  eyedropper/move/HSV-shift + selections rect/ellipse/circle/lasso/by-color with Replace/Add/Subtract/
  Intersect), copy/cut/paste, flip/invert, multi-layer group move, palette management, lossless `.mkpx`
  save/load (RLE-compressed), canvas ops (flip/rotate/resize/crop-to-selection), the action-script DSL, and
  the probe/oracle set. **77 tests green.**
- **Codec** (`crates/codec`): import GIF/PNG/APNG/JPEG/BMP/WebP (animated → frames); export PNG / sprite
  sheet / animated GIF.
- **CLI** (`crates/cli`): `mkpx run <script> <probes…>` — drives the engine and emits ASCII/JSON/PNG/oracle
  reports; exit code is the CI gate.
- **App** (`app/`): the three-row editor UI (tool options · palette · tools) + canvas + timeline (reorder,
  per-frame duration) + layers (opacity/lock/reorder/duplicate-to-frames/multi-select group move) +
  multi-palette manager (`.gpl`/JSON) + RGB/HSV picker + import dialog + export + Club upload, over the engine
  via a C-ABI DLL (`dart:ffi`). Responsive: wide viewports get a right side panel.
- **Performance:** 500 frames × 20 layers (10,000 layers) composite at 0.064 ms/frame, **48 MiB** resident,
  exact round-trip — no crash.

**Club (social) pillar — specification & server contract.** The full social layer is specified in
`SPEC-CLUB.md` (an internal design doc; see *Documents*). The native GitHub sign-in flow is live on staging;
building the `lib/club` client (auth first) is the next phase.

### Build & run on Windows
```powershell
./build.ps1 -Run        # builds the DLL + tests + Windows app, bundles the DLL, launches it
# or manually:
cargo build -p makapix-ffi --release
cargo test                                          # full Tier-1 suite
cargo run -p makapix-cli -- run examples/showcase.txt "render:0:out.png:6" state assert.roundtrip
cd app && flutter run -d windows                    # interactive UI (debug)
```
The prebuilt release app is at `app/build/windows/x64/runner/Release/makapix_club.exe`. *(The Android app id
and OAuth custom scheme are **`club.makapix.app`** — migrated 2026-06-30 from the legacy `club.makapix.editor`,
in lockstep with the server OAuth allowlist and the hosted `assetlinks.json`.)*

### Build & install on Android
The Rust engine cross-compiles to an Android `.so` (bundled into the APK via `jniLibs`); the Dart loader
opens `libmakapix_ffi.so` on Android. One-time prereqs: Android SDK + NDK, `rustup target add
aarch64-linux-android armv7-linux-androideabi`, `cargo install cargo-ndk`.
```powershell
./build_android.ps1              # cross-compiles .so (arm64+arm32) + builds app-release.apk
./build_android.ps1 -Install     # also installs to a USB-connected phone (USB debugging on)
```
The APK lands at `app/build/app/outputs/flutter-apk/app-release.apk`, app id **`club.makapix.app`**.
**Sideload (no cable):** copy that APK to the phone → tap it → allow "install unknown apps" → Install.
**Over USB:** enable Developer Options + USB debugging on the phone, connect it, then `adb install -r <apk>`.
