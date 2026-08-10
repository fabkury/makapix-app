# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

The **Makapix Club app**: a native (Rust + Flutter) client for the `makapix.club` pixel-art social
network. The Next.js + FastAPI website (a separate repo) is an independent, coexisting client of the same
server; this app does not depend on it. Two pillars share one Flutter binary:

1. **Makapix Editor** — the built-in animated pixel-art editor: a deterministic, headless **Rust engine**
   (`crates/`) under a thin **Flutter** shell.
2. **The Club social layer** — feeds, reactions, comments, follows, profiles, search, notifications,
   publish, edit/remix. Entirely Dart (`app/lib/club/`).

Terminology, kept strict: *Makapix Club* = the product (website **and** this app); *Makapix Editor* = the
editor feature **inside** this app, not a separate product. Don't conflate them.

**Doc map:** `README.md` (end-user landing page; its images live in `docs/media/`) ·
`docs/BUILDING.md` (build-from-source guide + developer doc map) · `STATUS.md` (feature coverage; with the git log, the live
frontier) · `docs/memlab/REPORT.md` (measured memory
limits — the numbers to design against) · `docs/play-release.md` + `docs/ios-release/PLAN.md` (store
pipelines). The detailed design specs — `SPEC.md` (editor engine) and `SPEC-CLUB.md` (social layer +
server contract; §28 the phase plan) — are internal docs kept out of the public repo; references to them
won't resolve in a public checkout.

**Conventions:** all new text — code comments, UI strings, docs, commits — is **American English** (repo
standardized 2026-07-25). Club commits are phase-tagged (`feat(club/C4): …`); the phases (SPEC-CLUB §28)
are C0 auth · C1 read & discover · C2 create & publish · C3 edit & remix · C4 curate/manage · C5
real-time & players · C6 moderation & extras. C0–C3 are complete, C4 mostly is, and pieces of C5 (player
control) and C6 (mod-hashtags) have shipped — `STATUS.md` and the git log hold the live frontier.

## Build, test, run

Dev happens on **Windows** (engine + desktop + Android device). **iOS builds only in Codemagic cloud CI —
never locally.**

```powershell
./build.ps1 -Run              # Windows: FFI DLL → cargo test → Flutter build → bundle DLL → launch
./build_android.ps1           # Android APK: engine .so (arm64+arm32) → jniLibs → release APK
                              #   -Install: adb install -r · -Bundle: build an .aab instead
./release_android.ps1         # Play release: gates → versionCode from the Play API → signed prod AAB →
                              #   upload+rollout → commit/tag/push. -Track (default production; alpha =
                              #   closed testing, internal = review-free smoke test) · -DryRun · -VersionName X.Y.Z.
                              #   Setup: docs/play-release.md
```

Every build defaults to the **prod** backend (`makapix.club`); only an explicit `-Dev` flag
(→ `--dart-define=CLUB_ENV=dev`) targets `development.makapix.club`. Artifacts:
`app/build/windows/x64/runner/Release/makapix_club.exe` · `app/build/app/outputs/flutter-apk/app-release.apk`.

The Android **app id is `club.makapix.app`** — it must match the server OAuth allowlist and the hosted
`assetlinks.json` byte-for-byte. The GitHub OAuth return leg differs per environment: **dev** = verified
HTTPS App Link (`app-dev.makapix.club`), **prod** = the `club.makapix.app://` custom scheme (Chrome's
same-site handling makes prod App Links undeliverable — `app/lib/club/config/club_config.dart` documents
why; don't "fix" it back).

**Distribution:** Android — **live on Google Play** (production track; alpha remains the testing
track) via `release_android.ps1`. iOS — **live on the App Store**, built by Codemagic → TestFlight →
release.

### iOS (cloud CI only)

`codemagic.yaml` drives the build: `build_ios.sh` compiles the engine into a **dynamic
`MakapixFFI.framework`** (vendored via `app/ios/makapix_ffi.podspec`), and the **R2 gate** verifies the
ipa embeds the framework with `_mkpx_*` symbols exported — **never remove that gate**. Static linking +
`DynamicLibrary.process()` is dead (Xcode 26 dead-strips the symbols; see `engine_ffi.dart` — don't go
back). Flow and release history: `docs/ios-release/PLAN.md`.

### The fast editor dev loop (no GUI, no device)

The engine is driven headlessly by the `mkpx` CLI harness — the primary loop for editor work:
**edit Rust → run a DSL script + probes → read the ASCII/PNG/JSON output → repeat.**

```powershell
cargo build -p makapix-ffi --release    # the DLL the Flutter app loads
cargo run -p makapix-cli -- run examples/showcase.txt "render:0:out.png:6" state assert.roundtrip
```

`mkpx`'s **exit code is the CI gate**: `0` all probes passed · `1` a probe failed · `2` script or IO
error. Probes are colon-separated specs evaluated after the script runs: `ascii:F:L`, `hash:F:L`,
`stats:F:L`, `pixel:F:L:X:Y`, `render:F:OUT.png[:S]`, `state`, `assert.undo`, `assert.gradient:TOL`,
`assert.roundtrip` (see `crates/cli/src/main.rs`).

### Tests and lint

```powershell
cargo test                              # full Rust suite; -p makapix-engine for one crate;
cargo test selection                    #   a bare substring filters by test name
cargo test --test scenarios             # one integration-test file (crates/engine/tests/*.rs)
cargo clippy --workspace

cd app
flutter test                            # all Dart tests; append a file path to run one
flutter analyze
```

Rust unit tests are inline `#[cfg(test)]` modules; cross-cutting tests live in `crates/engine/tests/`
(`scenarios.rs`, `perf.rs`, `fuzz_inputs.rs`). Dart tests (unit + widget, `app/test/`) run **without the
engine binary or network** — keep it that way.

## Architecture

### The FFI seam (the one boundary that matters)

Engine and shell talk over a **hand-written C ABI** — deliberately **not `flutter_rust_bridge`** (reliable
Windows/Android/iOS builds, zero codegen; don't "upgrade" it). The contract is narrow, strings-and-bytes
only:

- **Dart → Rust:** UTF-8 **DSL command strings** (`mkpx_run`) plus a few scalar getters/setters.
- **Rust → Dart:** composited **RGBA bytes** (`mkpx_display`, `mkpx_composite`), thumbnails, frame/layer
  hashes, the selection outline, and saved `.mkpx` / exported PNG/GIF byte buffers.
- A `Session` lives behind an opaque pointer; **no panic ever crosses the boundary** (errors come back as
  C strings / status codes).

Rust side: `crates/ffi/src/lib.rs`. Dart side: `app/lib/engine_ffi.dart` — the `_open()` loader finds
`makapix_ffi.dll` next to the exe (Windows), `libmakapix_ffi.so` via jniLibs (Android), and
`MakapixFFI.framework/MakapixFFI` via `DynamicLibrary.open` (iOS).

### The action-script DSL is the universal driver

One DSL (`name(args)` lines, parsed in `crates/engine/src/session/parse.rs`) drives everything: the CLI
harness, unit tests, recorded sessions, and the Flutter shell (via `mkpx_run`). A new editor capability =
a new `Action` variant + its execution, immediately usable from tests, the CLI, and the UI. `Session`
(`crates/engine/src/session.rs`) is the single stateful entry point: it owns the document + editor state,
runs the DSL, routes pointer input to tools, wraps each change in one undo record, and exposes probes.

### The engine is layered and dependency-free on purpose

`crates/engine` layering (low→high): `util · geom · color · buffer/raster/selection/cleanedge · document ·
history · tool · render · probe · io/import · session`. It has **zero dependencies** — its own hash, PRNG,
sparse tiled copy-on-write buffer, and `.mkpx` codec (v10 typed-chunk container: content-addressed tile
dictionary, RAW/RLE/INDEXED tile encodings, byte-deterministic — `docs/mkpx-format/`). It is
`#![forbid(unsafe_code)]`; the workspace ships `panic = "abort"` in release. **Don't add runtime
dependencies to `crates/engine`** — the ban guards cross-compilation (never a native/`-sys` crate in the
core), determinism (byte-identical goldens), and memory safety on untrusted `.mkpx` input. Pure-Rust deps
are fine at the periphery (the `image` crate is quarantined in `crates/codec` — the model to follow);
non-shipping dev-deps (fuzzers, benches) are unconstrained and encouraged.

Invariants to preserve (SPEC §25): 8-bit RGBA sRGB, premultiplied internally, **integer-exact** so goldens
never fork per platform; canvas 1×1–256×256; frames ≤1024; layers ≤64; 32×32 tiling + COW + lazy alloc
mandatory; per-frame 128-state undo with auto-compaction.

Crates: `engine` (core) · `codec` (import GIF/PNG/APNG/JPEG/BMP/WebP; export PNG/sprite-sheet/GIF/
animated lossless WebP — the animation container is hand-muxed in pure Rust) ·
`ffi` (the cdylib) · `cli` (the `mkpx` harness).

### The Flutter shell

Two co-equal pillars under a neutral shell. `lib/main.dart` → `lib/app.dart` (root `MaterialApp`) →
**`lib/shell/app_shell.dart`**, which mounts **only the active pillar** (see gotchas) and switches on the
`openEditorProvider` / `openClubProvider` signals. The app opens on Club; the editor stays reachable
without login (via Contribute). There is no persistent pillar-switching chrome.

- **Editor UI** (`app/lib/editor/`): `editor_page.dart` + its part files
  (`editor_page.{canvas,controls,engine,fileio,persistence,sheets,timeline,toolgrid}.dart`) — the
  three-row UI (tool options · palette · tools) over canvas/timeline/layers · `tools.dart` (tool catalog) ·
  `palette_page.dart` + `palette_io.dart` · `gallery/` (local drawings) · `persistence/` (autosave +
  drawing store) · `dialogs/` · `widgets/painters.dart` · generated icon painters (`makapix_icons.g.dart`;
  pipeline in `tools/icons/`).
- **Club** (`app/lib/club/`): `api/` (typed REST per domain) · `auth/` (session, OAuth, PKCE, token
  store) · `models/` · `state/` (Riverpod providers/controllers) · `publish/` · `edit/` · `ui/` · `anim/`
  (feed animation decode/playback) · `cache/` (artwork disk cache) · `config/`.
- **State:** Riverpod (`ProviderScope` in `main()`). HTTP is Dio with a single-flight 401→refresh→retry
  interceptor (`api/club_api_client.dart`); the REST base is `{baseUrl}/api/v1` from
  `config/club_config.dart`. Tokens at rest: `flutter_secure_storage`; the OAuth return leg uses
  `flutter_web_auth_2` (see the OAuth note under Build).

The engine⇄Club rule is a **dependency direction, not a language ban**: Rust never knows about Club (no
networking, no async I/O, no social concepts); Club **may consume** engine/codec services through the
bytes-only FFI seam when there's a concrete reason (conformance + export for publish, decode for
edit/remix and feed animation). Dart fetches, Rust computes. Club unit tests must keep running without
the engine binary.

### The Editor ↔ Club seam

One Riverpod `StateProvider`, `pendingClubEditProvider` (`app/lib/club/state/edit_bridge.dart`):

- **Edit/remix (Club → editor):** the detail page sets a `ClubEditRequest`; `AppShell` switches pillars
  while `EditorPage` downloads the artwork, loads it as a fresh document, and records a `ClubEditSource`
  for **Replace** vs **Post as new**. (Both listeners fire on the same dispatch — race-free.)
- **Publish (editor → Club):** "Post to Club" exports bytes (static→PNG, animated→GIF) and opens the
  publish flow; `lib/club` does conformance, metadata, license, visibility, and the upload.

## Platform gotchas (Windows / Android)

- **Android has a ~1 GiB allocator wall the workstation doesn't.** scudo caps its ~4 KiB size class —
  where pixel tiles and undo tile-tables live — at ~1.0 GiB per process; past it allocation fails and
  `panic = "abort"` turns that into a SIGABRT crash (not an LMK kill), regardless of device RAM. The
  shipped budget enforcement (2026-07-16: COW tile tables, 96 MiB history budget, 256/320 MiB document
  budget, loader refusal) keeps sessions under the wall — **preserve those budgets**. Windows runs the
  same workloads to multi-GB, so a "works on the workstation" memory test proves nothing for devices.
  Numbers and harnesses: `docs/memlab/REPORT.md` + `tools/memlab/`.
- **Windows needs the VS "C++ ATL" component.** `flutter_secure_storage_windows` includes `<atlstr.h>`,
  so the build fails with `C1083: Cannot open include file: 'atlstr.h'` unless ATL is installed (VS
  Installer → "C++ ATL for latest build tools"). Every plugin version needs it.
- **App shell mounts ONE pillar at a time — don't reintroduce `IndexedStack`.** Both pillar `Scaffold`s
  mounted at once crashes Windows on resize (accessibility bridge: `Failed to update ui::AXTree`, exit
  `0xC000041D`). The editor survives switches via its on-disk autosave (a synchronous
  `flushNow()` in `dispose`, reload from the drawing store in `initState`); Club state lives in
  long-lived providers. Don't "optimize" this back.
- **Android Gradle pinning:** the Flutter template's AGP 9 / Gradle 9 / Kotlin 2.3 breaks `file_picker`;
  the repo pins AGP 8.11.1 / Gradle 8.14 / Kotlin 2.2.20 (`app/android/settings.gradle.kts` + wrapper)
  and disables lint in `app/android/build.gradle.kts`. Don't unpin without a reason.
- **JDK on PATH:** a bare `./gradlew` fails fast (the PATH JDK is too new for Gradle 8.14);
  `flutter build` / `build_android.ps1` use Android Studio's bundled JBR 21. For direct gradle, pass
  `-Dorg.gradle.java.home="C:/Program Files/Android/Android Studio/jbr"`.
- **Release signing** reads the git-ignored `app/android/key.properties` (see `key.properties.example`)
  and falls back to debug signing when absent.
- **Club upload mock:** `python tools/mock_club_server.py` listens on `http://localhost:8080` (artifacts
  land in `tools/uploads/`).

## Development and interaction style

Feel free to ask questions to the user, but if you do so, prefer to give alternatives, include your recommendations, and use the "question asking tool" for convenience.
