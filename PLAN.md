# Makapix Editor — Development Plan (PLAN)

> Companion to [`SPEC.md`](SPEC.md): the build plan for the **Makapix Editor** pillar of the **Makapix Club**
> app — **how we build it, in what order, on this Windows 11 workstation**. The SPEC is the stable *what*; this
> PLAN sequences the work, defines the dev/test environment, and sets acceptance gates per phase. The
> social-networking pillar has its own phased rollout in [`SPEC-CLUB.md`](SPEC-CLUB.md) §28. See
> [`README.md`](README.md) for the product model.
> **Last updated:** 2026-06-26.

---

## 0.1 Amendment (2026-06-25, v1.1) — finalized SPEC & build push

The SPEC's deferred questions are now **resolved** (SPEC §26) and a **production-hardening** section was added
(SPEC §28: canvas ops, shape/line tools, eyedropper, color adjustments, autosave/recovery, typed error model,
project browser, settings, mirror/onion aids, Club provisional contract, versioning, expanded CI). Shape tools
and `.gpl` import were pulled into v1; iOS and the *real* Club endpoint remain deferred to later phases.

This amendment does **not** reorder the phases — the phase structure below still holds. The current effort
compresses **Phases 0–6 (engine + harness + Windows shell + perf)** into an accelerated build so the app is
runnable and exercisable on the Windows workstation, with Phases 7 (real Club), 8 (iOS) and final 9 (store)
following once their external prerequisites land. Engine completeness and Tier-1 test coverage are prioritized
over UI polish where a trade-off is forced.

## 0. Strategy

**Loop-first, then the MVP, then breadth.** Build the deterministic engine and the `mkpx` Tier-1 harness
*before* any feature breadth, so the develop→test→inspect loop exists from the first week and every later
feature is developed against it. Then deliver the chosen MVP — a **layered, animated editor with core tools**
(your decision this session) — wired to a Flutter shell that runs as a **Windows desktop harness app** and on
the **Android emulator**. iOS comes late, via cloud macOS CI. Each feature lands with its harness tests and
acceptance gate; nothing is "done" until its Tier-1 gates are green.

Guiding rules:
- **All correctness logic in Rust**, none in Dart (the determinism guarantee). Reject PRs that leak pixel
  logic into the shell.
- **Every feature ships with oracle/structural tests**; gates are CI exit codes, not eyeballing.
- **Keep the engine a pure crate** buildable/testable without the mobile toolchain, so the loop never depends
  on Flutter/Android/iOS being set up.
- **Keep all shared code iOS-clean** from day one even though iOS builds come last.

---

## 1. Environment Setup (Windows 11)

The engine loop needs only the Rust toolchain. The Flutter desktop/Android tiers need more. Set up in this
order; each step has a verification command.

### 1.1 Core (engine loop) — required first
| Tool | Install | Verify |
|------|---------|--------|
| **Rust (MSVC)** | `winget install Rustlang.Rustup` → `rustup default stable-x86_64-pc-windows-msvc` | `rustc --version` (≥ 1.96), `cargo --version` |
| **VS Build Tools (C++)** | "Desktop development with C++" workload (MSVC linker; also needed by Flutter Windows) | `cl.exe` resolves in a dev shell |
| **Git** | `winget install Git.Git` | `git --version` |
| **just** (task runner, optional) | `winget install Casey.Just` | `just --version` |
| **cargo extras** | `cargo install cargo-nextest cargo-criterion` (faster tests, benches) | `cargo nextest --version` |

> With just this, `cargo test` / `cargo run -p makapix-cli -- run …` runs the **entire Tier-1 AI loop**
> natively. This is the day-one milestone; everything below is for the visual/interactive tiers.

### 1.2 Flutter + Windows desktop harness
| Tool | Install | Verify |
|------|---------|--------|
| **Flutter SDK** | Download stable; add to `PATH` | `flutter --version` |
| **Windows desktop support** | `flutter config --enable-windows-desktop` | `flutter devices` lists **Windows** |
| **flutter_rust_bridge codegen** | `cargo install flutter_rust_bridge_codegen`; add `flutter_rust_bridge` to `app` deps | `flutter_rust_bridge_codegen --version` |
| **doctor** | — | `flutter doctor` (Windows + Android sections OK) |

> The **Windows desktop build is the fast interactive harness** — `flutter run -d windows` launches the real
> UI on this workstation in seconds, no emulator. It is a dev tool, not a shipped product.

### 1.3 Android (emulator + on-device)
| Tool | Install | Verify |
|------|---------|--------|
| **Android Studio** | `winget install Google.AndroidStudio` (SDK, platform-tools, an AVD) | `adb --version` |
| **Android NDK** | via SDK Manager (for the Rust cross-compile) | NDK path set |
| **Rust Android targets** | `rustup target add aarch64-linux-android x86_64-linux-android armv7-linux-androideabi` | listed in `rustup target list --installed` |
| **cargo-ndk** | `cargo install cargo-ndk` | `cargo ndk --version` |
| **An AVD** | create a Pixel-class **x86_64** API 33 emulator | `flutter devices` lists the emulator |

> `x86_64` emulator images are the fast path on a Windows x64 host; `aarch64` is for physical devices.

### 1.4 iOS (deferred — not on this workstation)
Not installable on Windows. When iOS is enabled (PLAN Phase 8): a **macOS CI runner** (GitHub Actions
`macos-14`, or Codemagic) builds/tests the iOS target; a Mac (owned/rented/cloud) is used for store
submission. Until then, keep the code iOS-clean and let CI be the iOS conscience.

### 1.5 One-time bootstrap checklist
- [ ] `cargo test` green on an empty workspace scaffold.
- [ ] `flutter run -d windows` shows a blank app.
- [ ] Android emulator boots; `flutter run -d emulator-5554` shows the blank app.
- [ ] `flutter_rust_bridge` round-trips one trivial call (Dart → Rust → Dart).
- [ ] CI runs `cargo test` + `flutter test` on a Windows runner.

---

## 2. Repository Scaffold (Phase 0, week 1)

Create the structure from SPEC §24:

```
Cargo.toml (workspace)
crates/engine  crates/codec  crates/ffi  crates/cli
app/ (flutter)
examples/  goldens/  docs/  .github/workflows/
justfile   .gitignore   README.md
```

- **Workspace deps** kept minimal in `engine`: `serde` (+ compact format), `blake3`, a small PRNG
  (xoshiro), `zstd`, optional `rayon`. `codec` carries the heavy `image`/`gif`/`png`/`webp` crates.
- **`justfile`** targets: `just test` (`cargo nextest`), `just harness <script>`, `just desktop`
  (`flutter run -d windows`), `just android`, `just bench`, `just golden-update`, `just ci`.
- **CI** (`.github/workflows/ci.yml`): on push/PR run `cargo nextest run`, `cargo clippy -D warnings`,
  `mkpx` oracle/golden gates, and `flutter test` on a **Windows** runner; a **Linux** runner mirrors the
  engine tests for speed. (A **macOS** job is added in Phase 8.)

**Phase 0 exit gate:** empty workspace builds; CI green; the bootstrap checklist (§1.5) passes.

---

## 3. Phased Roadmap

Each phase lists scope, the **Tier-1 gates** that define done, and how it's exercised on Windows. Phases are
ordered by dependency, not calendar; sizes are rough relative effort.

### Phase 0 — Foundations & the Loop *(the highest-leverage work)*
**Scope:** `util` (SeededRng, VirtualClock, ids, blake3) · `geom` (transforms, pure & tested) · `color`
(Rgba8/Premul8, sRGB lerp, alpha-over, rgb↔hsv) · `buffer` (tiled COW `RgbaBuffer`, lazy alloc, `Mask`,
content hash) · minimal `document` (one frame, one layer) · `command`/`history` substrate · `session` +
**action-script parser** · **`mkpx` CLI + probe set** (`ascii`, `pixel`, `hash`, `stats`, `state`,
`assert.undo`, `render`) · **Pencil** tool end-to-end.

**Gates (all on Windows, no device):**
- `cargo nextest` green; `clippy -D warnings` clean.
- Pencil stroke → `ascii` matches expected glyph grid; `hash` stable; `assert.undo` PASS (do/undo/redo hash
  equality + other-frames-byte-identical).
- Transform round-trip property test (`screen↔canvas`) green.
- `render --out` writes a PNG the AI can read.

**Why first:** this *is* the AI loop. After Phase 0, every feature is `write → mkpx run … oracle/ascii →
read result → write`.

---

### Phase 1 — MVP: Layers + Animation + Core Tools *(your chosen MVP)*
**Scope:**
- **Data model full:** multi-frame (1–1024) · multi-layer (1–64) · per-frame duration (µs) · palettes
  embedded · `AnimSettings`.
- **Reference compositor:** `composite_frame` (alpha-over, opacity, visibility) + `oracle.composite`.
- **Core tools:** **Pencil**, **Eraser** (square/round, size), **Bucket Fill** (contiguous/discontiguous,
  threshold) + `oracle.fill`.
- **Palette basics:** active palette, add/edit/remove/duplicate color, RGB+HSV picking (engine side).
- **Undo/redo with compaction:** per-frame 128-state history + global structural history + the merged Undo
  timeline; compaction policy + memory-bound property test.
- **`.mkpx` save/load:** chunked container + `assert.roundtrip` gate.
- **Frame ops:** add/duplicate/remove/reorder; per-frame duration + **bulk** set; playback on VirtualClock
  (`Play`/`AdvanceClock`) with Loop/Once/PingPong.
- **FFI + Flutter shell:** `flutter_rust_bridge` surface; the **three-row UI** (tool options / palette /
  tools), canvas (engine RGBA → `ui.Image`, nearest), timeline + layers panels; runs on **Windows desktop**
  and **Android emulator**.
- **Golden pipeline (Tier 2):** first reference renders + `golden` gate; a couple of Flutter widget/layout
  goldens.

**Gates:**
- Tier 1: `oracle.composite`, `oracle.fill`, `assert.undo`, `assert.roundtrip` all PASS; multi-layer/
  multi-frame scenario scripts pass.
- Tier 2: golden renders committed; `golden` gate green; Flutter layout goldens green.
- Tier 3 (manual, once): create a small layered animation on **Windows desktop** and the **Android
  emulator** — draw, add layers/frames, set durations, play, save, reload — and confirm it round-trips.
- Memory: typical-project stress test under the §8.2 budget.

**Deliverable:** a genuinely usable layered, animated pixel editor with pencil/eraser/bucket, palettes,
undo, save/load, and playback — runnable on this workstation.

---

### Phase 2 — Selections & Pixel Transforms
**Scope:** selection tools (`Rect`, `Ellipse`, `Circle`, `Poly`, `Free`, `ByColor`) · combine modes
(Replace/Add/Subtract/Intersect) + Invert/All/None · **move/copy/cut/paste** selected pixels ·
**cross-frame paste** · **HSV-shift** on selection · clip-to-selection enforced across all paint ops.
**Gates:** `oracle.select` (set-algebra) · `oracle.hsv` · `mask` dumps · move/copy/paste round-trip
properties (copy→paste-in-place = no-op) · `assert.undo` for each new command.

### Phase 3 — Advanced Paint Tools
**Scope:** **Paintbrush** (shaped stamp, path-interpolated) · **Airbrush** (seeded spray, flow over
VirtualClock) · **Gradient** (linear/radial, 2/3-stop with explicit positions, alpha, optional dither) ·
**Dodge/Burn** (lightener/darkener, intensity).
**Gates:** `oracle.gradient` (+ `ramp`, `thumb`) · airbrush reproducibility under fixed seed · dodge/burn
HSV-V oracle · golden backstops for gradients.

### Phase 4 — Layer & Frame Power Features
**Scope:** duplicate/move/copy a layer **to N frames** · **multi-layer move** (move several layers as one) ·
onion-skin overlay in the renderer · timeline drag-reorder/duplicate UX · bulk frame-duration tools polished.
**Gates:** cross-frame structural ops have `assert.undo`-style structural-history invariants · onion-skin is
overlay-only (never alters saved pixels — property test) · scenario scripts for "duplicate bg into frames
2–50".

### Phase 5 — Import & Export
**Scope:** `makapix-codec` decode GIF/WebP/PNG/APNG/JPEG/BMP · `import_frames` (pure): crop-or-scale
(Nearest default; Box/Triangle/Lanczos), frame-count clamping, **start-frame offset**, **import-as-layer**
when frames exist · raster export: per-frame PNG, sprite-sheet, APNG, GIF, WebP.
**Gates:** decode→import oracle (known fixtures → expected frames/durations) · lossless export round-trips
(PNG/APNG) · GIF palette export golden · import-as-layer scenario scripts.
*(Confirm export must-haves with SPEC §26.4 before locking encoders.)*

### Phase 6 — Palette Management & UI Polish / Responsiveness
**Scope:** full palette save/load (embedded + standalone JSON; `.gpl` import candidate) · RGB/HSV picker UI ·
eyedropper · the three-row UI refined for one-handed smartphone use · **tablet/wide** responsive layouts
(side panels) · accessibility & hit-target pass.
**Gates:** Flutter widget + golden tests across phone/tablet breakpoints · palette ops via `state` probe ·
interaction smoke tests on Windows desktop + Android emulator.

### Phase 7 — Makapix Club Upload (real)
**Scope:** implement the `upload_to_club` interface (SPEC §21) against the **real** API once provided ·
auth flow · progress/retry/cancel · metadata (title/tags/visibility).
**Prereq:** Club API contract (SPEC §26.1).
**Gates:** uploader tested against the **local mock** (success/auth-fail/network-fail/progress/cancel) on
Windows; then a live smoke test against staging.

### Phase 8 — iOS Enablement (cloud macOS CI)
**Scope:** add a **macOS CI runner** building the iOS target · `cargo-lipo`/xcframework packaging of
`makapix-ffi` for `aarch64-apple-ios` (+ simulator) · signing/profiles · iOS-specific UI/gesture/file-picker
checks · confirm byte-identical engine output vs Windows (determinism dividend).
**Prereq:** iOS specifics (SPEC §26.2).
**Gates:** iOS CI build green; `integration_test` smoke on an iOS simulator; goldens identical to Android
(no per-platform fork).

### Phase 9 — Performance Hardening & Release
**Scope:** criterion benches vs the §23 budgets · memory stress at high frame/layer counts ·
inactive-frame compression + optional disk-backing validated · device-tier perf on Android (and iOS) ·
store assets, signing, listings, branding.
**Prereq:** branding + min device tier (SPEC §26.3, §26.5).
**Gates:** all perf budgets met on the agreed min device · no OOM under the stress matrix · release builds
signed; store checklists complete.

---

## 4. Testing Strategy Mapped to Phases

| Tier | Mechanism | Runs on Windows? | Introduced |
|------|-----------|:---------------:|-----------|
| **1 — Data** | `cargo nextest` (unit/property/oracle/scenario) + `mkpx` probes; artifacts to `target/mkpx-artifacts/` | ✅ always | Phase 0 |
| **2 — Golden** | `mkpx golden` (engine PNGs) + Flutter `matchesGoldenFile` (widget/layout) | ✅ | Phase 1 |
| **3 — Device** | Flutter `integration_test` on Android emulator/device (occasional); iOS simulator later | ✅ Android / ❌ iOS-local | Phase 1 (Android), Phase 8 (iOS) |
| **Bench** | `cargo criterion`; numbers tracked for regressions | ✅ | Phase 0 (harness), enforced Phase 9 |

**CI gates per PR:** `cargo nextest`, `clippy -D warnings`, all `oracle.*` / `assert.*` / `golden` probes,
`flutter test`. Golden changes require an explicit `golden --update` + visual review of the diff PNG.

---

## 5. Definition of Done (per feature)

A feature is done only when **all** hold:
1. Logic lives in the **engine** (no Dart correctness logic).
2. It has a **closed-form oracle or structural gate** (not just a snapshot), plus an `assert.undo` for any
   new mutating command.
3. A **scenario script** exercises it through the public DSL/FFI path the UI uses.
4. **Property tests** cover its invariants (round-trip / identity / clip-to-selection / memory bound as
   applicable).
5. CI is green on Windows; if it has a visual surface, a **golden** is committed.
6. SPEC is updated if any decision changed.

---

## 6. Risk Register

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Logic leaks into Dart** → loop blind spots | High | Hard review rule; engine owns the document; Dart holds only view state + a handle. |
| **FFI / dual-toolchain friction** (Windows + Android + later iOS) | High | Keep `engine` a pure crate testable without Flutter; isolate all bridge code in `ffi`; automate with `cargo-ndk`/`flutter_rust_bridge`; budget Phase 1 time for it. |
| **iOS can't be built on Windows** | Med | Android-first; code kept iOS-clean; cloud macOS CI in Phase 8; determinism means engine logic is already proven. |
| **16 GiB worst-case memory** | High | Tiling + COW + lazy alloc + inactive-frame compression are mandatory from Phase 0; memory-bound property tests; hard ceiling with clear UX. |
| **Cross-frame undo semantics** | Med | Per-frame + bounded structural history with a merged timeline (SPEC §10); validate the model in Phase 1 with structural-undo invariants before building on it. |
| **Reference vs GPU render divergence** | Med | Reference CPU compositor is canonical; any GPU fast-path is golden-tested to match (tolerance 0). |
| **Import format edge cases** (APNG/animated WebP) | Med | Lean on mature crates; fixture-driven decode oracles; fuzz the importer. |
| **Club API unknown** | Low (now) | Interface + local mock now; defer real wiring to Phase 7 when the contract lands. |
| **Determinism drift** (RNG/clock/float) | High | Injected seed + virtual clock + integer sRGB math; the determinism contract is itself property-tested. |

---

## 7. Immediate Next Steps (when you say "go")

1. Scaffold the Cargo workspace + Flutter `app` + `justfile` + CI (Phase 0 setup).
2. Implement `util`/`geom`/`color`/`buffer` with unit + property tests.
3. Stand up the `mkpx` harness (parser + `ascii`/`hash`/`stats`/`state`/`assert.undo`/`render`).
4. Land **Pencil** end-to-end and prove the loop (Phase 0 exit gate).
5. Begin Phase 1 (layers + animation + core tools) against the now-live harness.

> Nothing above requires a phone, an emulator, or iOS for the first runnable, testable milestone — it all
> runs on this Windows 11 workstation. The emulator/desktop tiers join at Phase 1; iOS at Phase 8.
