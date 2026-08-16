# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

The **Makapix Club app**: a native (Rust + Flutter) client for the `makapix.club` pixel-art social
network. The Next.js + FastAPI website (a separate repo) is an independent, coexisting client of the same
server; this app does not depend on it. Two pillars share one Flutter binary:

1. **Makapix Editor** — the built-in animated pixel-art editor: a deterministic, headless **Rust engine**
   (`crates/`) under a thin **Flutter** shell.
2. **The Club social layer** — feeds, reactions, comments, follows, profiles, search, notifications,
   publish, edit/remix with lineage. Entirely Dart (`app/lib/club/`).

**`CONTEXT.md` is the terminology authority** — read it before writing docs or user-facing text. Short
version: *Makapix Club* = the product (website **and** this app); *Makapix Editor* = the editor feature
**inside** this app, not a separate product; a third pillar, *Makapix Animator*, lives on the unmerged
`animator` branch. Don't conflate them.

**Doc map:** `README.md` (end-user landing; images in `docs/media/`) · `CONTEXT.md` (domain model +
terminology) · `docs/BUILDING.md` (build-from-source + developer doc map) · `STATUS.md` (feature
coverage; with the git log, the live frontier) · `SPEC.md` / `SPEC-CLUB.md` (internal current-state
references for the two pillars — git-ignored, absent from public checkouts; rewritten 2026-08-16 to
describe the system as built) · `docs/adr/` (the ADR series — 0007 single-coat strokes and 0008 AA define
*current* engine behavior) · `docs/memlab/REPORT.md` (measured memory limits — the numbers to design
against) · `docs/play-release.md` + `docs/ios-release/PLAN.md` (store pipelines). (The original
2026-06 build plan, `PLAN.md`, was retired 2026-08-16 — git history holds it; its toolchain-setup
content lives on in `docs/BUILDING.md`.)

**Conventions:** all new text — code comments, UI strings, docs, commits — is **American English** (repo
standardized 2026-07-25). Club commits are phase-tagged (`feat(club/C4): …`); phases C0–C3 are complete,
C4 is complete except highlights-management + categories, C5 shipped player control/registration and live
SSE notifications (soft-player kiosk is the one open item; the MQTT plan is retired), and C6 shipped
mod-hashtags, the in-app moderation suite, and remix lineage — `STATUS.md` holds the live frontier.

## Build, test, run

Dev happens on **Windows** (engine + desktop + Android device). **iOS builds only in Codemagic cloud CI —
never locally.**

```powershell
./build.ps1 -Run              # Windows: FFI DLL → cargo test (non-gating) → Flutter build → run
./build_android.ps1           # Android APK: engine .so (arm64-v8a + armeabi-v7a + x86_64) → jniLibs →
                              #   release APK. -Install: adb install -r · -Bundle: build an .aab
./release_android.ps1         # Play release: gates (cargo test · flutter analyze --no-fatal-infos ·
                              #   flutter test) → versionCode from the Play API → signed prod AAB →
                              #   upload+rollout → commit/tag/push. -Track (default production; alpha =
                              #   closed testing, internal = review-free smoke test) · -DryRun ·
                              #   -VersionName X.Y.Z · -NotesFile · -SkipGates. Setup: docs/play-release.md
```

Every build defaults to the **prod** backend (`makapix.club`); only an explicit `-Dev` flag
(→ `--dart-define=CLUB_ENV=dev`) targets `development.makapix.club`. Artifacts:
`app/build/windows/x64/runner/Release/makapix_club.exe` · `app/build/app/outputs/flutter-apk/app-release.apk`.

**There is no CI.** No `.github/`; `codemagic.yaml` (iOS) runs no tests. The automated gates are
`release_android.ps1`'s pre-upload gates and Codemagic's R2 symbol gate. Dev convention: keep
`flutter analyze --fatal-infos` clean (the release gate relaxes to `--no-fatal-infos`).

The Android **app id is `club.makapix.app`** — it must match the server OAuth allowlist and the hosted
`assetlinks.json` byte-for-byte. The GitHub OAuth return leg differs per environment: **dev** = verified
HTTPS App Link (`app-dev.makapix.club`), **prod** = the `club.makapix.app://` custom scheme (Chrome's
same-site handling makes prod App Links undeliverable — `app/lib/club/config/club_config.dart` documents
why; don't "fix" it back).

**Distribution:** Android — **live on Google Play** (production track) via `release_android.ps1`. iOS —
**live on the App Store**, built by Codemagic → TestFlight → release.

### iOS (cloud CI only)

`codemagic.yaml` drives the build: `build_ios.sh` compiles the engine into a **dynamic
`MakapixFFI.framework`** (vendored via `app/ios/makapix_ffi.podspec`), and the **R2 gate** verifies the
ipa exports `_mkpx_*` symbols — **never remove that gate** (static linking + `DynamicLibrary.process()`
is dead; Xcode 26 dead-strips the symbols). Flow and release history: `docs/ios-release/PLAN.md`.

### The fast editor dev loop (no GUI, no device)

The engine is driven headlessly by the `mkpx` CLI harness — the primary loop for editor work:
**edit Rust → run a DSL script + probes → read the ASCII/PNG/JSON output → repeat.**

```powershell
cargo build -p makapix-ffi --release    # the DLL the Flutter app loads
cargo run -p makapix-cli -- run examples/showcase.txt "render:0:out.png:6" state assert.roundtrip
```

`mkpx`'s **exit code is the scriptable gate**: `0` all probes passed · `1` a probe failed (also unknown
probe / PNG-write failure) · `2` script or IO error. Subcommands: `run` · `new` · `gen` (synthesize a
noise document) · `load [--run <script|->]` · `import`. Probes are colon-separated specs evaluated after
the script: `state` · `usedcolors` · `mem` · `mem.os` · `ascii:F:L` · `hash:F:L` · `hash.doc` ·
`stats:F:L` · `pixel:F:L:X:Y` · `ramp:x0:y0:x1:y1:N` · `thumb:F:L:W:H` ·
`render|composite|display:F:OUT.png[:S]` · gates `assert.undo` / `assert.gradient:TOL` /
`assert.roundtrip` (authoritative usage: `crates/cli/src/main.rs` header). `gen` + `load --run` +
`mem`/`mem.os` reproduce the memlab numbers.

### Tests and lint

```powershell
cargo test                              # full Rust suite; -p makapix-engine for one crate;
cargo test selection                    #   a bare substring filters by test name
cargo test --test scenarios             # one integration-test file (crates/engine/tests/*.rs)
cargo clippy --workspace

cd app
flutter test                            # all Dart tests; append a file path to run one
flutter analyze                         # keep --fatal-infos clean
```

Rust unit tests are inline `#[cfg(test)]` modules; cross-cutting tests live in `crates/engine/tests/`
(`scenarios.rs`, `perf.rs`, `fuzz_inputs.rs`, `aa_off_pins.rs` — literal hash pins, a changed pin IS the
bug — and `replay_checkpoint.rs`). Dart tests (unit + widget, `app/test/`) run **without the engine
binary or network** — keep it that way.

## Architecture

### The FFI seam (the one boundary that matters)

Engine and shell talk over a **hand-written C ABI** — deliberately **not `flutter_rust_bridge`** (reliable
Windows/Android/iOS builds, zero codegen; don't "upgrade" it). The contract is narrow, strings-and-bytes
only, **synchronous on the caller's thread** (no engine thread; heavy encode/decode runs on Dart isolates
that build their own engine from `.mkpx` bytes — the session pointer never crosses isolates):

- **Dart → Rust:** UTF-8 **DSL command strings** (`mkpx_run`) plus a few scalar getters/setters.
- **Rust → Dart:** composited **RGBA bytes** (`mkpx_display`, `mkpx_composite_frame`), thumbnails,
  frame/layer hashes, the selection outline, saved `.mkpx` / exported PNG/GIF/WebP byte buffers, and the
  replay **checkpoint/timelapse** families (`mkpx_checkpoint_*`, `mkpx_tl_*`).
- A `Session` lives behind an opaque pointer; **no panic ever crosses the boundary** (errors come back as
  C strings / status codes; the workspace aborts on panic).

Rust side: `crates/ffi/src/lib.rs` (~56 exports — the authoritative list). Dart side:
`app/lib/engine_ffi.dart` — the `_open()` loader finds `makapix_ffi.dll` next to the exe (Windows),
`libmakapix_ffi.so` via jniLibs (Android), and `MakapixFFI.framework/MakapixFFI` (iOS).

### The action-script DSL is the universal driver

One DSL (`name(args)` lines, parsed in `crates/engine/src/session/parse.rs` — ~160 verbs, the
authoritative catalog) drives everything: the CLI harness, unit tests, the session **journal** (recorded
sessions), and the Flutter shell (via `mkpx_run`). A new editor capability = a new `Action` variant,
immediately usable from tests, the CLI, and the UI. `Session` (`crates/engine/src/session.rs`) is the
single stateful entry point. Retired verbs must parse forever (journals replay): `SetSpacing` is
accepted-and-ignored; `PrecisionPencil`/`MoveLayer` are permanent aliases.

### The engine is layered and dependency-free on purpose

`crates/engine` has 16 modules (authoritative list + layering note: `crates/engine/src/lib.rs`), low→high:
`util · geom · color · buffer/raster/selection/cleanedge/coat · document · history · tool · render ·
probe · io/import · session`. It has **zero dependencies** — its own hash (128-bit FNV, on the `.mkpx`
wire), PRNG, sparse tiled copy-on-write buffer, and `.mkpx` codec (v10 typed-chunk container:
content-addressed tile dictionary, RAW/RLE/INDEXED tile encodings, byte-deterministic —
`docs/mkpx-format/`). It is `#![forbid(unsafe_code)]`; the workspace ships `panic = "abort"` in release.
**Don't add runtime dependencies to `crates/engine`** — the ban guards cross-compilation (never a
native/`-sys` crate in the core), determinism (byte-identical goldens), and memory safety on untrusted
`.mkpx` input. Pure-Rust deps are fine at the periphery (`crates/codec` quarantines `image`, `image-webp`,
`miniz_oxide`, and owns the `.mkpx` compact/DEFLATE envelope — the model to follow); non-shipping
dev-deps are unconstrained.

Invariants to preserve: 8-bit RGBA sRGB, premultiplied internally, **integer-exact** (deterministic
`util::det_*` transcendentals, never libm) so goldens never fork per platform; canvas 1×1–256×256; frames
≤1024; layers ≤64; 32×32 tiling + COW + lazy alloc mandatory; per-frame 128-state undo with
auto-compaction.

Crates: `engine` (core) · `codec` (import GIF/PNG/APNG/JPEG/BMP/WebP; export PNG/GIF/animated lossless
WebP — the animation container is hand-muxed in pure Rust; no APNG encoder) · `ffi` (cdylib + staticlib) ·
`cli` (the `mkpx` harness).

### The Flutter shell

Two co-equal pillars under a neutral shell. `lib/main.dart` → `lib/app.dart` (root `MaterialApp`) →
**`lib/shell/app_shell.dart`**, which mounts **only the active pillar** (see gotchas) and switches on the
`openEditorProvider` / `openClubProvider` signals (plus `pendingLocalLibraryProvider` /
`activePillarProvider` in the same file family). The app opens on Club; the editor stays reachable
without login (via Contribute). There is no persistent pillar-switching chrome.

- **Editor UI** (`app/lib/editor/`): `editor_page.dart` + its **nine** part files
  (`editor_page.{canvas,controls,engine,fileio,persistence,replay,sheets,timeline,toolgrid}.dart`) — the
  three-row UI (tool options · palette · tools) over canvas/timeline/layers · `tools.dart` (tool catalog) ·
  `palette_page.dart` + `palette_io.dart` · `gallery/` (local drawings) · `persistence/` (autosave +
  drawing store) · **`replay/`** (the journal/Watch-replay/timelapse subsystem — append-only action
  journal with torn-line repair, MP4/GIF/WebP timelapse export; it rides the engine checkpoint FFI) ·
  `dialogs/` · `widgets/painters.dart` · generated icon painters (`makapix_icons.g.dart`; pipeline in
  `tools/icons/`).
- **Club** (`app/lib/club/`): `api/` (typed REST per domain + the SSE parser) · `auth/` (session, the
  `/auth/token` grants, PKCE, Apple, token store) · `models/` · `state/` (Riverpod
  providers/controllers + the SSE connection) · `publish/` · `edit/` · `ui/` · `anim/` (feed animation
  decode/playback, pure Dart) · `cache/` (artwork disk cache) · `config/`.
- **State:** Riverpod (`ProviderScope` in `main()`). HTTP is Dio with a single-flight 401→refresh→retry
  interceptor (`api/club_api_client.dart`); the versioned REST base is `{baseUrl}/api/v1`, plus a second
  Dio (`dioRoot`) on the unversioned `{baseUrl}/api` for the PMD/UMD/player routers. Tokens at rest
  (access **and body-delivered refresh** — there is no cookie jar): `flutter_secure_storage`; the OAuth
  return leg uses `flutter_web_auth_2`.

The engine⇄Club rule is a **dependency direction, not a language ban**: Rust never knows about Club (no
networking, no async I/O, no social concepts); Club **may consume** engine/codec services through the
bytes-only FFI seam when there's a concrete reason (export for publish, decode for edit/remix, META
provenance). Feed-animation decode is pure Dart by decision. Club unit tests must keep running without
the engine binary.

### The Editor ↔ Club seam

One Riverpod `StateProvider`, `pendingClubEditProvider` (`app/lib/club/state/edit_bridge.dart`):

- **Edit/remix (Club → editor):** the detail page sets a `ClubEditRequest` (downloaded bytes + source
  post + `isMkpx`); `AppShell` switches pillars while `EditorPage` loads it and records a
  `ClubEditSource` for **Replace** vs **Post as new**. (Both listeners fire on the same dispatch —
  race-free.)
- **Publish (editor → Club):** "Post to Club" exports bytes (lossless WebP — static or animated;
  never GIF) plus provenance and the optional `.mkpx` layers attachment, and opens the publish flow;
  `lib/club` does conformance, metadata, license, visibility, and the upload.

## Platform gotchas (Windows / Android)

- **Android has a ~1 GiB allocator wall the workstation doesn't.** scudo caps its ~4 KiB size class —
  where pixel tiles and undo tile-tables live — at ~1.0 GiB per process; past it allocation fails and
  `panic = "abort"` turns that into a SIGABRT crash (not an LMK kill), regardless of device RAM. The
  shipped budgets (96 MiB history · 256/320 MiB document · 48 MiB replay checkpoints · loader refusal)
  keep sessions under the wall — **preserve all four**. Windows runs the same workloads to multi-GB, so a
  "works on the workstation" memory test proves nothing for devices. Numbers and harnesses:
  `docs/memlab/REPORT.md` + `tools/memlab/`.
- **Impeller is disabled on Android (stopgap).** `AndroidManifest.xml` sets `EnableImpeller=false` for a
  PowerVR/Tensor fixed-rate-compression raster crash; remove only once the pinned Flutter carries
  flutter/flutter#187586. Companion rule (`app/lib/app.dart`): Android overscroll stays the glow
  indicator, and **don't add new backdrop consumers** (`BackdropFilter`, advanced blend modes).
- **Windows needs the VS "C++ ATL" component.** `flutter_secure_storage_windows` includes `<atlstr.h>`,
  so the build fails with `C1083: Cannot open include file: 'atlstr.h'` unless ATL is installed (VS
  Installer → "C++ ATL for latest build tools").
- **App shell mounts ONE pillar at a time — don't reintroduce `IndexedStack`.** Both pillar `Scaffold`s
  mounted at once crashes Windows on resize (accessibility bridge: `Failed to update ui::AXTree`, exit
  `0xC000041D`). The editor survives switches via its on-disk autosave (a synchronous `flushNow()` in
  `dispose`, reload from the drawing store in `initState`); Club state lives in long-lived providers.
- **Android Gradle pinning:** the Flutter template's AGP 9 / Gradle 9 / Kotlin 2.3 breaks `file_picker`;
  the repo pins AGP 8.11.1 / Gradle 8.14 / Kotlin 2.2.20 (`app/android/settings.gradle.kts` + wrapper)
  and disables lint in `app/android/build.gradle.kts` (also dodges OneDrive file-lock flakes). Don't
  unpin without a reason.
- **JDK on PATH:** a bare `./gradlew` fails fast (the PATH JDK is too new for Gradle 8.14);
  `flutter build` / `build_android.ps1` use Android Studio's bundled JBR 21. For direct gradle, pass
  `-Dorg.gradle.java.home="C:/Program Files/Android/Android Studio/jbr"`.
- **Release signing** reads the git-ignored `app/android/key.properties` (see `key.properties.example`)
  and falls back to debug signing when absent.
- **Club upload mock is contract-obsolete:** `python tools/mock_club_server.py` (`http://localhost:8080`,
  artifacts in `tools/uploads/`) still serves the dead provisional contract (`POST /api/v1/artifacts`) —
  it cannot exercise the real `/post/upload` path. Treat as a rewrite candidate, not a harness.

## Development and interaction style

Feel free to ask questions to the user, but if you do so, prefer to give alternatives, include your recommendations, and use the "question asking tool" for convenience.
