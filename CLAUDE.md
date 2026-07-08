# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

This is the **Makapix Club app**: a native (Rust + Flutter) client for the Makapix Club pixel-art social
network. It is one of two independent, coexisting clients of the same `makapix.club` server — the other is the
Next.js + FastAPI website (a separate repo). This app does **not** depend on the website.

The app has **two pillars** that share one Flutter binary:

1. **Makapix Editor** — the built-in animated pixel-art editor. A deterministic, headless **Rust engine**
   (`crates/`) under a thin **Flutter** shell. Specified in `SPEC.md`.
2. **The Club social layer** — feeds, reactions, comments, follows, profiles, search, notifications, publish,
   edit/remix. Lives **entirely in Dart** (`app/lib/club/`). Specified in `SPEC-CLUB.md`.

Terminology, kept strict in the docs: *Makapix Club* = the product (website **and** this app);
*Makapix Editor* = the editor feature **inside** this app, not a separate product. Don't conflate them.

**Doc map:** `README.md` (product hub) · `PLAN.md` (editor build plan) · `STATUS.md` (honest feature
coverage) · `docs/plans/C{0..3}-*.md` (per-phase implementation plans). The detailed design specs — `SPEC.md`
(editor engine: data model, FFI, DSL, `.mkpx`, UI) and `SPEC-CLUB.md` (social layer + server contract; §28 the
phase plan, §29 the website→app parity matrix) — are **internal design docs kept out of the public repo**;
they live on the maintainer's machine, so references to them below won't resolve in a public checkout.

## Build, test, run

All dev happens on **Windows** (engine + desktop + Android device). **iOS is deferred** to a future cloud
macOS CI — it cannot be built here, so don't try.

```powershell
# Windows app: builds the FFI DLL, runs cargo test, builds the Flutter app, bundles the DLL, launches it.
./build.ps1 -Run

# Android APK: cross-compiles the engine .so (arm64 + arm32) into jniLibs, builds a release APK.
./build_android.ps1            # build only
./build_android.ps1 -Install   # also `adb install -r` to a USB-connected phone (USB debugging on)

# Google Play release (internal testing): gates → next versionCode from the Play API → signed prod
# AAB → upload + rollout → commit/tag/push. One-time service-account setup: docs/play-release.md.
# Releases run locally on this workstation by decision (2026-07-02).
./release_android.ps1          # -DryRun to rehearse; -VersionName X.Y.Z to bump the visible version
```

The Windows exe is `app/build/windows/x64/runner/Release/makapix_club.exe`. The APK is
`app/build/app/outputs/flutter-apk/app-release.apk`. The Android **app id is `club.makapix.app`** (migrated
2026-06-30 from the legacy `club.makapix.editor`, in lockstep with the server OAuth allowlist + the hosted
`assetlinks.json` `package_name`). It must match the server OAuth allowlist byte-for-byte. The GitHub OAuth
return now uses a **verified HTTPS App Link** on a dedicated host (`app[-dev].makapix.club/oauth/github`); the
custom scheme `club.makapix.app://oauth/github` is a kept fallback — see `ClubConfig`.

### The fast editor dev loop (no GUI, no device)

The engine is driven headlessly by the `mkpx` CLI harness. This is the primary loop for editor work:
**edit Rust → run a DSL script + probes → read the ASCII/PNG/JSON output → repeat.**

```powershell
cargo build -p makapix-ffi --release    # the DLL the Flutter app loads
cargo test                              # full Rust suite (engine + codec + ffi + scenarios + perf)
cargo run -p makapix-cli -- run examples/showcase.txt "render:0:out.png:6" state assert.roundtrip
```

`mkpx`'s **exit code is the CI gate**: `0` all probes passed · `1` an oracle/assert probe failed ·
`2` script or IO error. Probes are colon-separated specs evaluated after the script runs:
`ascii:F:L`, `hash:F:L`, `stats:F:L`, `pixel:F:L:X:Y`, `render:F:OUT.png[:S]`, `state`,
`assert.undo`, `assert.gradient:TOL`, `assert.roundtrip` (see `crates/cli/src/main.rs`).

### Tests and lint

```powershell
cargo test                              # everything
cargo test -p makapix-engine            # one crate
cargo test selection                    # filter by test-name substring
cargo test --test scenarios             # one integration-test file (crates/engine/tests/*.rs)
cargo clippy --workspace                # Rust lint

cd app
flutter test                            # all Dart tests (app/test/*.dart)
flutter test test/conformance_test.dart # one Dart test file
flutter analyze                         # Dart/Flutter lint (flutter_lints)
```

Rust unit tests are inline `#[cfg(test)]` modules in each `crates/engine/src/*.rs`; cross-cutting tests live
in `crates/engine/tests/` (`scenarios.rs`, `perf.rs`). Dart tests are pure unit tests (auth/PKCE/models/
conformance/paging) — no engine or network required.

## Architecture

### The FFI seam (the one boundary that matters)

The engine and shell talk over a **hand-written C ABI** — deliberately **not `flutter_rust_bridge`** (chosen
for reliable Windows/Android builds and zero codegen; don't "upgrade" it). The contract is narrow and string-
and-bytes only:

- **Dart → Rust:** UTF-8 **DSL command strings** (`mkpx_run`) plus a few scalar getters/setters.
- **Rust → Dart:** composited **RGBA bytes** (`mkpx_display`, `mkpx_composite`), small thumbnails, frame/layer
  hashes, the selection outline, and saved `.mkpx` / exported PNG/GIF byte buffers.
- A `Session` lives behind an opaque pointer; **no panic ever crosses the boundary** (errors come back as
  C strings / status codes).

Rust side: `crates/ffi/src/lib.rs` (`extern "C"`, `#![allow(clippy::not_unsafe_ptr_arg_deref)]`).
Dart side: `app/lib/engine_ffi.dart` (`dart:ffi`; the `_open()` loader finds `makapix_ffi.dll` next to the
exe on Windows, `libmakapix_ffi.so` via jniLibs on Android, `DynamicLibrary.process()` on iOS).

### The action-script DSL is the universal driver

One DSL (`name(args)` lines, parsed in `crates/engine/src/session/parse.rs`) drives **everything**: the CLI
harness, unit tests, recorded sessions, and the Flutter shell (via `mkpx_run`). When you add an editor
capability, you add an `Action` variant + its execution, and it is immediately usable from tests, the CLI,
and the UI. `Session` (`crates/engine/src/session.rs`, ~1700 lines) is the single stateful entry point: it
owns the document + editor state, runs the DSL, routes pointer input to tools, wraps each change in one undo
record, and exposes probes.

### The Rust engine is layered and dependency-free on purpose

`crates/engine/src/lib.rs` declares the layering (low→high): `util · geom · color · buffer/raster/selection ·
document · history · tool · render · probe · io · session`. The engine has **zero dependencies** — its own
hash, PRNG, sparse tiled copy-on-write buffer, and RLE `.mkpx` codec — so the Tier-1 loop and the FFI lib
build fast and never break on a transitive dep. It is `#![forbid(unsafe_code)]`. **Don't add runtime
dependencies to `crates/engine`.** The ban is *scoped, not dogmatic*: it guards the three properties a dep
most easily breaks here — **cross-compilation** (Windows DLL + Android arm64/arm32, iOS later; never a
native/`-sys` crate in the core), **determinism** (byte-identical goldens; no SIMD/float/intrinsic-fallback
surprises), and **memory safety on untrusted input** (the `.mkpx` loader). **Pure-Rust deps are fine at the
periphery** — image format I/O (the `image` crate) is quarantined in `crates/codec`, the model to follow —
and **non-shipping dev-deps** (fuzzers like `proptest`/`cargo-fuzz`, `criterion` benches) are unconstrained
and encouraged for hardening the loader and codec. The workspace ships `panic = "abort"` in release.

Engine invariants you must preserve (see `SPEC.md` §25): 8-bit RGBA sRGB, premultiplied internally,
**integer-exact** so goldens never fork per platform; canvas 1×1–256×256; frames 1–1024; layers 1–64; tiling
(32×32) + COW + lazy alloc are mandatory; per-frame 128-state undo with auto-compaction.

Crates: `engine` (core) · `codec` (import GIF/PNG/APNG/JPEG/BMP/WebP, export PNG/sprite-sheet/GIF) ·
`ffi` (the `cdylib`) · `cli` (the `mkpx` harness binary).

### The Flutter shell

The app is **two co-equal pillars under a neutral shell**, not "an editor that can reach Club". `lib/main.dart`
is a thin entry point; `lib/app.dart` is the neutral root `MaterialApp`; **`lib/shell/app_shell.dart`** hosts
both pillars (mounting only the active one — see the platform-gotcha on `IndexedStack`). The app **opens on the
Club pillar** (signed-out users land on Club's own welcome/sign-in funnel). There is **no persistent
pillar-switching chrome** (no bottom bar / rail): navigation is in-content — the Club's top-bar **Contribute**
control selects a swipeable **Contribute page** (a peer to the feeds — `lib/club/ui/contribute_page.dart`) that
opens the editor or accepts a direct file upload; the **signed-out welcome page** keeps a Contribute button
that opens the editor straight away, so the **editor stays reachable without login**. The editor's **☰ menu →
Club** returns to the hub. The shell switches pillars via the `openEditorProvider` / `openClubProvider`
signals (and `pendingClubEditProvider` for edit/remix).

- **Editor UI:** `app/lib/editor/`, mirroring `lib/club/` — `editor_page.dart` (the `EditorPage` +
  `_EditorPageState`: the three-row UI of tool options · palette · tools, plus canvas, timeline, layers,
  palette manager, pickers, import/export; holds an `Engine` and renders the RGBA bytes it returns) ·
  `tools.dart` (tool catalogue) · `thumbnail.dart` · `widgets/painters.dart` · `dialogs/` (crop + colour
  picker).
- **Club social layer:** `app/lib/club/`, modular and written in Dart. The engine⇄Club rule is a
  **dependency direction, not a language ban**: the Rust engine never depends on or knows about Club — no
  networking, no async I/O, no social-domain concepts in Rust — while Club **may consume** engine/codec
  services through the existing bytes-only FFI seam when there is a concrete reason (today: conformance +
  export for publish, decode for edit/remix; candidate: animation decode/frame-seek for synced feed
  playback). Dart fetches, Rust computes. Day-to-day Club work (API, auth, state, UI) stays pure Dart, and
  Club unit tests must keep running without the engine binary. Structure: `api/` (typed REST per domain) ·
  `auth/` (session, OAuth, PKCE, token store) · `models/` · `state/` (Riverpod providers/controllers) ·
  `publish/` · `edit/` · `ui/` · `config/`.
- **State:** **Riverpod** (`ProviderScope` wraps the app in `main()`). HTTP is **Dio** with a single-flight
  401→refresh→retry interceptor (`api/club_api_client.dart`). `config/club_config.dart` selects the server:
  `dev` → `https://development.makapix.club`, `prod` → `https://makapix.club` — **`prod` is the
  compile-time default** (any build without `--dart-define=CLUB_ENV=dev` talks to makapix.club; dev
  requires the explicit `-Dev` flag on `build.ps1` / `build_android.ps1`); the REST base is
  `{baseUrl}/api/v1`. Auth tokens at rest use `flutter_secure_storage`; the GitHub OAuth return leg uses
  `flutter_web_auth_2` with a **verified HTTPS App Link** (`https://app[-dev].makapix.club/oauth/github`,
  `callbackUrlScheme: "https"` + an `autoVerify` manifest intent-filter), falling back to the
  `club.makapix.app://oauth/github` custom scheme; both are server-allowlisted byte-for-byte.

### The Editor ↔ Club seam

The two pillars connect through one Riverpod `StateProvider`, `pendingClubEditProvider`
(`app/lib/club/state/edit_bridge.dart`):

- **Edit/remix (Club → editor):** the Club detail page sets a `ClubEditRequest`; on that one provider event
  **`AppShell` switches to the editor pillar** while `EditorPage` (`lib/editor/editor_page.dart`) `ref.listen`s
  it, downloads the artwork, loads it as a fresh document, and records a `ClubEditSource` so the user can later
  **Replace** the original or **Post as new**. (Both listeners fire on the same dispatch — race-free.)
- **Publish (editor → Club):** "Post to Club" exports the document to bytes (static→PNG, animated→GIF) and
  opens the publish flow in `lib/club`. The engine hands over **only bytes**; `lib/club` does conformance,
  metadata, license, visibility, and the upload.

### Phasing

The Club layer rolls out in numbered phases (`SPEC-CLUB.md` §28, plans in `docs/plans/`): **C0** auth
foundation · **C1** read & discover · **C2** create & publish · **C3** edit & remix · C4 curate/manage ·
C5 real-time & players · C6 moderation & extras. Commits and branch work are tagged by phase (e.g.
`feat(club/C3): …`). C0–C3 are code-complete; check `STATUS.md` and recent git log for the live frontier.

## Platform gotchas (Windows / Android)

- **Windows needs the VS "C++ ATL" component.** `flutter_secure_storage_windows` `#include`s `<atlstr.h>`
  (its `CA2W`/`CW2A` string macros), so a Windows build fails with `C1083: Cannot open include file:
  'atlstr.h'` unless ATL is installed. Add it once (elevated): `setup.exe modify --installPath "<VS
  BuildTools>" --add Microsoft.VisualStudio.Component.VC.ATL --quiet`, or via the VS Installer GUI ("C++ ATL
  for latest build tools"). Every plugin version needs it — upgrading the package does **not** remove the dep.
- **App shell mounts ONE pillar at a time — don't reintroduce `IndexedStack`.** Keeping both pillar
  `Scaffold`s mounted simultaneously (Club + editor) crashes the Windows app on resize: the accessibility
  bridge aborts with `Failed to update ui::AXTree: Nodes left pending` (exit `0xC000041D`). `AppShell` mounts
  only the active pillar; the editor preserves its document across switches via `EditorSession` (`.mkpx`
  snapshot in `dispose`/`initState`) and Club state lives in long-lived Riverpod providers. Don't "optimise"
  this back into an always-both keep-alive.
- **Android Gradle pinning:** the Flutter template generates AGP 9 / Gradle 9 / Kotlin 2.3, which
  `file_picker` can't compile against. The repo pins AGP 8.11.1 / Gradle 8.14 / Kotlin 2.2.20 in
  `app/android/settings.gradle.kts` + the wrapper, and disables lint in `app/android/build.gradle.kts`.
  Don't unpin without a reason.
- **JDK on PATH:** a bare `./gradlew` fails fast (prints just a version string) because the PATH JDK
  (OpenJDK 25) is too new for Gradle 8.14. `flutter build` / `build_android.ps1` use Android Studio's bundled
  **JBR 21** and work; for direct gradle, pass
  `-Dorg.gradle.java.home="C:/Program Files/Android/Android Studio/jbr"`.
- **Release signing** reads the git-ignored `app/android/key.properties` (see `key.properties.example`) and
  falls back to debug signing when absent.
- **Club upload mock:** `python tools/mock_club_server.py` listens on `http://localhost:8080` for local
  upload testing (artifacts land in `tools/uploads/`).

## Development and interaction style

Feel free to ask questions to the user, but if you do so, prefer to give alternatives, include your recommendations, and use the "question asking tool" for convenience.
