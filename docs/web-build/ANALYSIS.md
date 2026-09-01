# A browser (WebAssembly) build of the Makapix Club app — analysis

**Date:** 2026-09-01 · **Status: analyzed, NOT implemented.** No web build exists or is scheduled; this
document records the costs and risks of one so the decision can be made (or declined) later without
redoing the investigation. Analyzed against commit `0fd72e39`; the `file:line` references below are
from that revision. Nothing here amends `SPEC.md` / `SPEC-CLUB.md`.

**Question analyzed:** could the Makapix Club app ship as a version that runs directly in the browser,
hosted somewhere under `https://makapix.club/`? What would it cost, and what would it risk?

**Short answer:** yes. The engine side is nearly free — the FFI crate compiles to wasm32 today with
zero source changes (§2). The real cost is in the Flutter shell (a second engine binding, browser
persistence, auth, hosting), and the real risk is product-level: a second web client under the same
domain as the website, with artwork living in evictable browser storage.

---

## 1. Two different things hide inside "a WebAssembly build"

They are separable and behave differently in browsers:

- **The Rust engine as wasm32.** `crates/ffi` compiled for `wasm32-unknown-unknown` is a plain
  WebAssembly module (MVP feature set, no GC, no threads). Every current browser runs it, including
  every browser on iOS.
- **The Flutter shell as JavaScript or as WasmGC.** `flutter build web` compiles Dart to JavaScript by
  default; `--wasm` additionally compiles it with `dart2wasm`, which needs WasmGC in the browser. Per the
  [Flutter wasm docs](https://docs.flutter.dev/platform-integration/web/wasm) (read 2026-09-01) the wasm
  target is still opt-in, ships a JS fallback that is selected at runtime, lists open Firefox and
  Safari bugs against the wasm renderer, and **every iOS browser gets the JS fallback** (WebKit). The
  local toolchain is Flutter 3.44.6 / Dart 3.12.

Consequence: whichever shell target runs, the engine is the same wasm module, so goldens and
determinism stay engine-side (§5). The shell target only decides speed and startup on a given browser.

## 2. What was measured (the load-bearing facts)

Verified against the tree on 2026-09-01:

1. **The engine builds for wasm32 unmodified.**
   `cargo build -p makapix-ffi --release --target wasm32-unknown-unknown` succeeds with no source
   change (the `cdylib` crate type, `crates/ffi/Cargo.toml:17`, becomes a `.wasm` on this target):

   | Measurement | Value |
   |---|---|
   | `makapix_ffi.wasm`, raw | 1.5 MB |
   | same, gzipped | 0.54 MB |
   | `mkpx_*` exports present | 58 of 58 |
   | wasm imports required | none (self-contained; no JS shims needed to instantiate) |

   The workspace `panic = "abort"` profile (`Cargo.toml:15`) compiles to a wasm trap (§4.3). No
   `wasm-opt` pass was applied; it typically trims a further 10–20%.

2. **The engine and codec have no host-OS surface.** `crates/engine/src` and `crates/codec/src` contain
   no `std::time`, `std::fs`, `std::thread`, or `std::env` use; the codec's only `std::sync` use is an
   `Arc<Mutex<Vec<u8>>>` scratch buffer (`crates/codec/src/lib.rs:744`), fine single-threaded. This is
   the payoff of the zero-dependency / `forbid(unsafe_code)` doctrine in `CLAUDE.md`.

3. **`dart:ffi` is confined to one file, and cannot be compiled for the web at all.**
   `app/lib/engine_ffi.dart` (987 lines) is the only importer of `dart:ffi` / `package:ffi`; no
   `Pointer`, `DynamicLibrary`, or `NativeFunction` type leaks into any other file. Dart's FFI is
   rejected outright by the web compilers
   ([flutter/flutter#149984](https://github.com/flutter/flutter/issues/149984)), so the web build needs a
   `dart:js_interop` twin of the `Engine` class (`engine_ffi.dart:236`) behind a conditional import —
   mechanical, not research (§3, item 2).

4. **Fourteen files import `dart:io`.** By weight of native calls: `app/lib/share/image_share.dart`,
   `editor/persistence/drawing_store.dart` (the whole store is `File`/`Directory` based,
   `drawing_store.dart:16`), `editor/palette_page.dart`, `club/api/club_api_client.dart` (installs an
   `IOHttpClientAdapter` idle-timeout tweak, `:44-46`), `dev/memlab.dart`, `editor/replay/journal_recorder.dart`
   (open-append-fsync-close per drain, `:34`), `club/ui/widgets/download_sheet.dart`,
   `club/ui/post_management_page.dart`, `club/ui/publish_page.dart`, `editor/keyboard/bindings_store.dart`,
   `club/auth/restore_credential_service.dart`, `club/auth/apple_oauth.dart`, plus 20 `Platform.isX`
   checks across the tree. Any `dart:io` import is a compile error on the web.

5. **Isolates: four sites already fall back, one does not.** `Isolate.run` is used in
   `engine_ffi.dart:434` (used-colors scan), `:885` (image decode), `:921` (raster encode), `:956`
   (export from bytes); each is wrapped in `try { … } catch { synchronous fallback }`, so on the web
   (where `Isolate.run` throws) they degrade to main-thread work. The Timelapse export uses
   `Isolate.spawn` (`editor/replay/timelapse_export.dart:111`) with **no** fallback. The replay
   libraries it drives (`action_runner.dart`, `journal_format.dart`, `timelapse_plan.dart`,
   `visible_index.dart`) import no Flutter, so a Web Worker build is feasible (§3, item 7).

6. **MP4 export is already platform-gated.** `mp4_channel.dart:4-6` — MediaCodec on Android,
   VideoToolbox on iOS, deliberately no Windows host; callers treat `MissingPluginException` as "MP4
   unsupported here". The web inherits the Windows behavior (WebP/GIF only) for free.

7. **The notifications stream needs a different transport.** The app reads
   `GET /realtime/notifications` through Dio with `ResponseType.stream`
   (`club/state/notifications_sse.dart:63-66`). Dio's browser adapter delivers a streamed response
   only when it completes ([cfug/dio#2268](https://github.com/cfug/dio/issues/2268)), so SSE never
   arrives. The server route is bearer-header only (`reference/makapix-club/api/app/routers/realtime.py:50-54`)
   and its own docstring (`:6`) says the website uses fetch streaming because `EventSource` cannot send
   an `Authorization` header. The web build must do the same.

8. **Server-side touch points are configuration, not code.** CORS origins come from the `CORS_ORIGINS`
   env var (`api/app/main.py:246`); the OAuth redirect allowlist lists the two native return legs
   (`api/app/routers/auth.py:80-81`); the Apple identity-token audience is the single
   `APPLE_APP_BUNDLE_ID` (`api/app/services/apple_signin.py:24`) — a web Services ID would be a second
   audience. The reverse proxy is caddy-docker-proxy driven by compose labels
   (`deploy/stack/docker-compose.prod.yml:79-100`), with `/api/*` served same-origin at `makapix.club`.

9. **Plugin web support.** Of the 18 dependencies in `app/pubspec.yaml`: `file_picker`,
   `shared_preferences`, `dio`, `http`, `crypto`, `url_launcher`, `package_info_plus`, `share_plus`,
   `cached_network_image` / `flutter_cache_manager` (memory-backed on the web; no persistent artwork
   cache — the browser HTTP cache takes over), `flutter_secure_storage` (WebCrypto over `localStorage`;
   not tamper-proof against XSS), `flutter_web_auth_2` (needs a callback HTML page on the app's origin
   — [package docs](https://github.com/leancodepl/flutter_web_auth_2)), and `sign_in_with_apple`
   (needs an Apple Services ID) all have web implementations. `path_provider` has none (moot once the
   store moves to IndexedDB), and `ffi` must sit behind a conditional import.

10. **There is no `app/web/` platform folder yet** — `flutter create --platforms web .` generates it.

## 3. Costs

Money is close to nil: the build is static files served by the existing Caddy box next to `/api/*`;
there are no store fees; each first visit downloads ~0.5 MB for the engine plus a typical Flutter web
bundle of a few megabytes compressed, cached thereafter. The cost is engineering time — and then a
**permanent third platform** in every release (`release_android.ps1` gates + Codemagic today; nothing
runs browser tests, and the repo has no CI).

| # | Work item | Person-days |
|---|---|---|
| 1 | Engine packaging: an allocator export pair for input buffers (the C ABI currently has only `mkpx_free_string` / `mkpx_free_bytes`), a build script, loader glue | 1–2 |
| 2 | `Engine` twin via `dart:js_interop`: 58 bindings, `u64` returns/params arrive as JS `BigInt`, bytes copied in and out of wasm linear memory; an interface split with conditional imports so the native file stays untouched | 5–8 |
| 3 | Persistence to IndexedDB: drawing store, autosave, journal (torn-line repair becomes moot; transactions are atomic), bindings store; **redesign the synchronous flush on pillar switch** (`autosave_controller.dart:87`, `editor_page.persistence.dart:199`) since browser storage is async-only; add `pagehide` protection | 5–8 |
| 4 | Purge the remaining `dart:io`: `Platform.isX` → `defaultTargetPlatform` + `kIsWeb`; share / download / publish / palette file paths → browser downloads and the Web Share API; the Dio adapter tweak behind a conditional import; gate off restore-credentials and MP4 | 2–4 |
| 5 | Notifications SSE over fetch streaming (`package:web` `ReadableStream`, or a fetch-backed adapter) | 1–2 |
| 6 | GitHub OAuth web leg: callback page, PKCE unchanged, one allowlist entry on the server; Apple sign-in on the web (Services ID + second audience) only if wanted — Apple guideline 4.8 binds App Store apps, not web pages | 1–2 (+2–3 for Apple) |
| 7 | Timelapse export: disable on the web (v1), **or** a Web Worker pipeline hosting its own engine instance driven by the Flutter-free replay libraries | 0.5 **or** 5–10 |
| 8 | Web scaffold: `index.html`, viewport meta (no page pinch-zoom), `BrowserContextMenu.disableContextMenu()` so right-click keeps meaning long-press, manifest, `--base-href`, loading screen | 1–2 |
| 9 | Hosting: a Caddy static route, `Content-Type` for wasm, precompressed brotli, immutable caching for hashed assets, a deploy script; the subpath-vs-subdomain decision (§4.5) | 1–2 |
| 10 | Determinism check: run the engine test suite under `wasm32-wasip1` with wasmtime as the cargo runner; replay the AA-OFF pin suite and the fuzz corpus | 1–2 |
| 11 | Browser QA matrix (Chrome / Firefox / Safari desktop, iOS Safari on the JS fallback, Android Chrome, *inside the installed website PWA*) and a memlab-style memory re-measurement per browser | 5–10 |
| 12 | Release-gate parity (a `release_web.ps1` mirroring the Android gates) | 1–2 |
| | **Full parity (minus MP4)** | **25–55** |
| | **Editor-only v1: local drawings, import/export, replay viewer; no Club sign-in, no SSE, timelapse disabled** | **20–35** |

The editor-only cut is not much cheaper in code — the Club layer is a small share of the port — but it
removes most of the *risk* (§4.1, §4.4, §4.5). The wide bands are honest: items 2, 3, and 11 depend on
how many browser quirks surface, which no desk analysis predicts.

## 4. Risks, ranked

### 4.1 Product identity (highest)

A second web client under `makapix.club`, with a different feature set from the Next.js website (no
per-post URLs, no SEO, no PWA install of its own; but the editor, replay, and the in-app moderation
suite), confuses users, search engines, and support. Two web clients of one server at one domain need a
clear split: the credible framing is **"the Makapix Editor on the web"**, not a Club clone.

### 4.2 Artwork in evictable storage

Today the local drawing library lives in app-private storage. In a browser it lives in IndexedDB, which
the browser clears under storage pressure, private windows drop on close, and Safari deletes after seven
days without a visit to the site. Artwork becomes losable in ways the native app never allows.
Mitigations: `navigator.storage.persist()`, download-your-`.mkpx` nudges, a visible "this browser may
forget your work" notice. None is a fix.

### 4.3 Memory ceiling and the death mode

wasm32 linear memory can only grow and is never returned to the browser; a failed `memory.grow` surfaces
as a Rust allocation failure, which `panic = "abort"` turns into a wasm trap. The tab survives, but the
engine instance is dead until the page reloads — the Android SIGABRT (`docs/memlab/REPORT.md`) in a new
costume, now with a **per-browser** wall (iOS Safari is the tightest; desktop Chrome allows up to 4 GB
per 32-bit memory — [V8](https://v8.dev/blog/4gb-wasm-memory)). The four shipped budgets (96 MiB history ·
256/320 MiB document · 48 MiB checkpoints · loader refusal) are the right shape but must be re-measured;
autosave is what makes the reload survivable.

### 4.4 Auth on the web

- Refresh tokens would sit in `localStorage` (what `flutter_secure_storage` is on the web), while the
  website keeps them in `HttpOnly` cookies (`auth.py:467`). An XSS anywhere on that origin reads them.
- Hosting at a subpath shares the origin's storage between two applications in both directions.
- Popup-based OAuth (`flutter_web_auth_2`) is blocked by popup blockers, and inside the installed
  website PWA (WebAPK on Android) it meets the same URL-capture class already hit natively
  (`app/lib/club/config/club_config.dart` documents the native case). Must be tested, not assumed.

### 4.5 The website's service worker vs. hosting location

At a subpath (`makapix.club/app/`) the website's service worker (scope `/`) intercepts the app's
navigations and asset fetches; offline-fallback and runtime-caching rules can serve a stale wasm or the
site's fallback page. A subdomain (`app.makapix.club`) sidesteps that entirely at the price of one
`CORS_ORIGINS` entry and cross-origin API calls (the app does not rely on cookies, so nothing else
changes). Recommendation: subdomain.

### 4.6 No isolates

The four synchronous fallbacks work but freeze the UI on big documents during export, decode, and the
used-colors scan. The Timelapse export has no fallback and can run for minutes on long journals — it is
either disabled on the web or moved into a Web Worker (§3, item 7).

### 4.7 Flutter web maturity

The wasm renderer is opt-in with open Firefox and Safari bugs on the docs page; iOS always runs the JS
build (slower startup, ~2× slower Dart code, CanvasKit instead of skwasm); mobile-browser text input,
scrolling, and IME are Flutter web's weakest area. That is exactly where much of a pixel-art social
network's audience is. Desktop browsers are the strong case.

### 4.8 Third-platform maintenance tax

A permanently divergent feature matrix (no MP4 export, no restore credentials, no share sheet, no
haptics, no players registration flow that makes sense) and a browser pass on every release — with no CI
to carry it. Every plugin upgrade must stay web-compatible.

### 4.9 Cross-origin isolation headers

Multithreaded skwasm rendering needs `Cross-Origin-Opener-Policy: same-origin` +
`Cross-Origin-Embedder-Policy`, and `require-corp` blocks cross-origin artwork and avatars that lack
CORP headers. `credentialless` or simply omitting the headers (single-threaded rendering) is the safe
default.

### 4.10 32-bit determinism (low probability, must be verified)

`usize` is 32-bit on wasm32. The engine hashes bytes and `u64`/`u128` values, never `usize`, and all
sizes fit comfortably, so the pins are expected to hold — but "expected" is not a golden. Item 10 in §3
turns it into one before any web build is trusted.

### 4.11 Small, known, cheap

Browser shortcuts (`Ctrl+W`, `Ctrl+T`, `Ctrl+N` cannot be intercepted; `Ctrl+S` can); the browser
context menu on right-click; page pinch-zoom vs. canvas pinch-zoom; a ~4–6 MB compressed first load on
mobile data; the display path copying a 256×256×4 buffer out of wasm memory per frame (trivial at that
size).

## 5. Why the engine is the easy part

Everything the `CLAUDE.md` architecture section defends turns out to be exactly what a wasm port wants:
a bytes-and-strings C ABI with no callbacks, no engine thread, no runtime dependencies, no `unsafe`, no
host-OS calls, integer-exact math with its own transcendentals, and the "session pointer never crosses
isolates — workers build their own engine from `.mkpx` bytes" rule, which maps one-to-one onto Web
Workers holding their own wasm instance. The port adds a second *binding*, not a second *engine*.

## 6. Recommendation, if it is ever taken up

1. **Editor-only v1 on `app.makapix.club`**, positioned as the Makapix Editor on the web; Club sign-in
   is a separate v2 decision, made after §4.1 and §4.4 have answers.
2. Order of work: §3 items 1–2 (engine twin) → 3 (IndexedDB) → 4 → 8–9 → 10 → 11; SSE, OAuth, and the
   Timelapse worker only with v2.
3. Treat the browser as a fourth build target with its own release gate from day one; do not let it ride
   on "it worked in Chrome".

## 7. Facts that would change this analysis

- Flutter making `--wasm` the default with iOS/Safari support — removes most of §4.7.
- Dart shipping a supported FFI-to-wasm path — removes §3 item 2 (currently the largest single item).
- The website moving its service worker scope or dropping its PWA — makes subpath hosting (§4.5) viable.
- A decision to give web users server-side artwork storage (drafts in the Club) — removes §4.2.
- Browser `memory64` on iOS — loosens §4.3 (Chrome, Firefox, and macOS Safari already have it;
  [caniuse](https://caniuse.com/wf-wasm-memory64) shows iOS Safari without it as of this writing).

---

*Method note: the wasm build in §2 was run on the development workstation on 2026-09-01 (the
`wasm32-unknown-unknown` rustup target is now installed there; output in the git-ignored `target/`).
Export/import counts were read from the binary's export and import sections. Browser-tooling claims cite
the sources linked inline, read the same day.*
