# Q5 — Feasibility: building the Animator on this codebase

*The technical companion to 01–04. Fixed by prior decision: the Animator core is **Rust behind
the FFI seam**, in a **new crate** (`crates/scene`, package `makapix-scene`) depending on
`makapix-engine` and `makapix-codec`; animated **WEBP export is a hard v0.1 requirement**;
scope is **full stack** (Rust core + Flutter shell). All repo invariants are inherited:
hand-written C ABI, dependency-free engine core, `panic = "abort"` + no-unwind FFI, Android
memory budgets, Dart tests run without the engine binary. Sizing is phase-level, anchored to
shipped features. File:line references are from the working tree at the time of writing
(2026-07-30).*

## 0. Verdict

**Feasible, with unusually high reuse.** The audit below found that the two scariest-sounding
requirements are already solved in the codebase:

- **Animated WEBP export exists today.** `crates/codec` hand-muxes the RIFF animation
  container (`VP8X`/`ANIM`/`ANMF`) in pure Rust around `image-webp` lossless VP8L frames —
  `encode_animated_webp_streaming` (`crates/codec/src/lib.rs:236`), `extract_vp8l` (`:306`) —
  and the FFI already exposes it with streaming, progress, and cancel (`mkpx_export_webp`,
  `crates/ffi/src/lib.rs:543`). The hard v0.1 requirement is met by *calling existing code
  with Scene-composited frames*. (The CLAUDE.md line "export PNG/sprite-sheet/GIF" is stale.)
- **Pixel-native transforms exist and are deterministic.** cleanEdge is a public point
  sampler (`cleanedge::sample`, `crates/engine/src/cleanedge.rs:321`) with the exact
  properties the design needs (never invents colors, identity at pixel centers, exact
  quarter-turns). The rotate/scale inverse-mapping that drives it is already written —
  `rotate_resample` / `scale_resample` (`crates/engine/src/session/canvas.rs:905`, `:1047`) —
  it just needs extraction from private session code into a public engine module.

The genuinely new work concentrates in three places, in ascending order of risk:

1. A **scene document + compositor** in Rust — new code, but sitting entirely on public,
   document-free engine primitives (`RgbaBuffer`, `cleanedge::sample`, `color::over_opacity`,
   `geom`, `util`).
2. The **`.mkps` codec** — new chunks over the `.mkpx` v10 container machinery, which is
   exactly right for the job but currently all-private inside `io.rs`.
3. The **Flutter Stage + timeline UI** — the largest single block of work and the least
   derisked; this is where the design docs already located the product risk, and the
   feasibility answer is "buildable with the app's existing patterns, but it is the long
   pole."

Overall scale: **the largest feature since the editor itself** — roughly the memlab
enforcement + palette page + tablet support efforts combined, dominated by the Flutter UI
phase. No blocker was found. Two small prerequisite refactors (Phase 0) unlock most of the
reuse.

## 1. Reuse map — Rust side

What exists, where, and its reuse verdict:

| Asset | Where | Verdict for the Animator |
|---|---|---|
| `RgbaBuffer` — 32×32 sparse tiled, two-level COW (`Arc` table + `Arc` tiles), lazy alloc, `snapshot()/diff_from()/TilePatch` | `crates/engine/src/buffer.rs` | **Use as-is** for Prop frame storage. Fully document-free. Memory accounting hooks (`memory_bytes`, `visit_tile_arcs`, `table_ptr`) feed the budget census directly. |
| `cleanedge::sample(src, x, y, line_width)` | `cleanedge.rs:321` | **Use as-is** — public, operates on any `RgbaBuffer`. The per-Prop cleanEdge/nearest style toggle from the design maps to "call it or call `src.get`". |
| `rotate_resample` / `scale_resample` (arbitrary angle about arbitrary pivot, X/Y scale, cleanEdge or NN, quarter-turn snap) | `session/canvas.rs:905/:1047` | **Extract** (Phase 0): private free functions bound to private draft structs. The math is exactly the Actor transform; it needs to become a public `engine::transform` module taking plain parameters instead of drafts. |
| `color::over_opacity(src, dst, opacity)` — integer-exact alpha-over with per-layer opacity | `color.rs:126` | **Use as-is** — this *is* Actor opacity compositing. |
| `raster.rs`, `geom.rs`, `util.rs` (`Hash`, `Hasher`, `SeededRng`, `VirtualClock`), `selection::Mask` | engine | **Use as-is**; all public, document-free. |
| `.mkpx` v10 container machinery: CRC-32C, chunk framing with critical/ancillary semantics, canonical LEB128 `Writer`/`Reader`, `walk_chunks`, per-tile codec menu (RAW/RLE/INDEXED), content-addressed tile dictionary with pointer+hash dedup, `INTG` whole-file integrity | `io.rs` (all **private**) | **Extract** (Phase 0) into a public `io::container` submodule. The extraction is small and mechanical — none of these touch `Document` except the two top-level save/load functions. This is the `.mkps` foundation. |
| History model: absolute before/after records, per-frame cap, byte budget with weight function, compaction | `history.rs` | **Pattern-copy, not reuse** — scene undo records are tiny (Keys and Actor fields, not tile patches), so the Scene crate wants the same *shape* (absolute records, byte-weighted, capped) with its own `Edit` enum. Far simpler than the editor's. |
| DSL template: `Action` enum → `parse_line` (`name(args)`, typed accessors, non-finite rejection) → `exec` dispatch → chokepointed mutation | `session/parse.rs` | **Pattern-copy.** A clean, proven template; the Scene crate writes its own `SceneAction` set (`AddProp`, `PlaceActor`, `SetKey`, `SetTween`, `SetPlayhead`, `SetActorMode`, …). |
| Budget protocol: soft/hard budgets, slack + exact recalibration, refusal with label, rollback at three chokepoints, loader refusal *before* materialization | `session.rs:1020–1161`, `io.rs:763` | **Pattern-copy** with scene-appropriate numbers (§6). The strict never-over-hard invariant and the refusal-not-degradation stance carry over unchanged. |
| Codec decode: GIF/WebP/APNG/PNG/JPEG/BMP → `Vec<DecodedFrame>` with dimension/frame/byte caps | `codec/src/lib.rs:63` | **Use as-is** for Prop import. The 1024/side Prop cap (design decision) is *stricter* than codec's 4096 limit — enforced at the Scene chokepoint. |
| Codec encode: GIF streaming, animated-WEBP streaming, PNG, NN upscale, progress/cancel | `codec/src/lib.rs:189–393` | **Use as-is.** Both animation encoders take a `next()` closure producing frames on demand — the Scene compositor plugs in directly, exactly as `mkpx_export_gif` does (`ffi/src/lib.rs:523–531`). |
| FFI conventions: opaque `Box::into_raw` session pointers, null-check helper, caller-provides-buffer for fixed-size RGBA, `bytes_out`/`mkpx_free_bytes` for variable payloads, sentinel returns, never-panic (no `catch_unwind` — `panic=abort` makes unwinding impossible; safety = not panicking) | `ffi/src/lib.rs` | **Pattern-copy** for a parallel `mkps_*` function family (§5). |
| CLI harness: colon-separated probes, exit-code contract (0/1/2), ascii/hash/stats/render/state/mem probes, `assert.roundtrip` | `cli/src/main.rs` | **Extend** with a `scene` entry point sharing the probe evaluator (§8). |

**The one structural gap, stated plainly:** the engine has no concept of a transform. A layer's
position *is* its pixel position; `BlendMode` has one variant; `render::composite_frame` emits
flattened RGBA per frame and nothing else. The Scene compositor — "for each scene frame, for
each Actor: resolve Cycle/Pose frame, apply pivot/rotation/scale/flip via the transform
module, alpha-over at position with opacity" — is genuinely new Rust. It is also well-bounded:
~the size of `render.rs` plus a cache (§4).

## 2. Reuse map — Flutter side

| Asset | Where | Verdict |
|---|---|---|
| `AppShell` third pillar | `app/lib/shell/app_shell.dart` | **Trivial** — the shell is 85 lines; add an index, an injectable `animatorPillar` widget (the test-stub seam), an `openAnimatorProvider` counter, extend the ternary and the `PopScope` rule. One pillar mounted at a time is preserved by construction. |
| Cross-pillar handoff | `club/state/edit_bridge.dart` | **Pattern-copy.** A sealed `AnimatorRequest` (`NewScene` / `OpenScene(id)` / `AnimateDrawing(id)` / later `AnimateClubPost`) behind a one-shot `StateProvider`, consumed on mount with the same two-listener dispatch and mount-time re-read the editor uses (`editor_page.persistence.dart:46`). |
| Persistence | `editor/persistence/` | **Reuse as-is.** `DrawingStore` is an engine-agnostic directory wrapper with a crash-safe 4-step write dance and `.bak` fallback; `AutosaveController` takes injected `serialize`/`buildMeta` closures invoked synchronously before any await (safe to flush in `dispose`). A `SceneStore` is the same classes over `<appSupport>/scenes/<id>/doc.mkps`. **Important stale premise found:** the editor no longer keeps an in-memory session snapshot across pillar switches — it flushes autosave and fully remounts (`editor_page.dart:463–480`). The Animator must ship its own dispose-time flush from day one. |
| FFI-bytes → screen | `engine_ffi.dart` + `editor_page.engine.dart:399` | **Reuse verbatim**: reused native scratch buffer (no per-call malloc), `premultiplyRgbaInPlace` (the engine emits straight alpha; `PixelFormat.rgba8888` wants premultiplied), `ui.decodeImageFromPixels`, `CustomPainter` with `FilterQuality.none`. The Scene FFI must keep the same straight-alpha output contract. |
| Playback model | `club/anim/` | **The right model exists — in the Club, not the editor.** The editor recomposites via FFI every 33 ms tick; the feed pre-decodes frames into a refcounted `DecodedAnimation` under a `ByteBudgetLru` (96 MiB budget) and indexes them off a wall-clock ticker with `select`-memoized rebuilds. Under ADR-0001 (fixed fps), Scene playback is the Club model: composite scene frames once (FFI), cache as `ui.Image`s, index by clock — one array index per tick during the loop-while-editing workflow. `ByteBudgetLru`, refcounting, and `AnimationTimeline` (degenerates to uniform delays) are directly reusable. |
| Stage gestures | `editor_page.canvas.dart:171` | **Reuse the shape**: raw `Listener` + finger-count disambiguation (`_touchPos`/`_drawPointer`/`_pinching`), not gesture-arena recognizers. The Animator's cascade is *shorter* than the editor's (drag Actor / drag pivot / drag path handle / pinch-zoom vs. ~10 draft branches). Auto-key hooks into the same pointer-up commit point the editor uses to end strokes. |
| Timeline thumbnails | `editor_page.timeline.dart:37` | **Reuse the pattern**: `ListView.builder` strip, hash-invalidated `ThumbCache` with in-flight guard and LRU cap, long-press sheets. Track thumbnails hash on (Prop content, Cycle frame). |
| Shared chrome (sliders, toggles, sheet primitives, mini buttons) | `editor_page.toolgrid.dart`, `editor_page.sheets.dart` | **Blocked — extraction needed** (Phase 0): all of it lives in private `extension … on _EditorPageState` and cannot be imported. Lifting the needed subset into `lib/ui/` is a mechanical refactor the Animator should not start without. |
| Layout + tests | `lib/ui/layout.dart`, `app/test/` | **Use as-is**: `editorUsesLandscape` is the single breakpoint source (portrait=posing / landscape=timing from the design maps onto it). All four established test seams apply — and improve: with the document behind `mkps_state_json`, the Animator's Dart side is *thinner* than the editor's, and its pure logic (timeline math, key editing viewmodels) should be written engine-free from the start. |

One deliberate divergence from the Flutter exploration's suggestion: it proposed a Dart-side
`SceneController` document model, reasoning "a Scene has no engine behind it." Under the fixed
Rust-core decision that premise is false — the Scene document lives in `makapix-scene` behind
the seam, and the Dart side follows the *editor's* pattern (local state + `state_json`
hydration + DSL sends), not the Club's. This is the consistent choice: one source-of-truth
model per pillar, and the pillar with an engine keeps the engine as truth.

## 3. The new crate: `crates/scene` (`makapix-scene`)

Workspace impact is one line in `Cargo.toml:3` (nothing else in the workspace anticipates or
resists a fifth member). Same `panic = "abort"`, same no-unwind discipline; `forbid(unsafe_code)`
like the engine. Dependencies: `makapix-engine` (path), `makapix-codec` (path) — no externals.

Module sketch (mirroring the engine's layering discipline, low→high):

- `model` — `Scene { size, fps, frame_count, background, cast: Vec<Prop>, actors: Vec<Actor> }`;
  `Prop { id, name, frames: Vec<RgbaBuffer>, cycle_map: Vec<u16>, style: PixelStyle }`
  (cycle_map = scene-frames-per-prop-frame from the quantize-at-import rule, ADR-0001);
  `Actor { id, prop, mode: Playing|Posing, pin_to: Option<ActorId>, tracks: Tracks }`;
  `Tracks` = per-property sorted `Vec<Key>`; `Key { frame: u32, value, tween: Tween }`.
  Property values are integers or fixed-point (angle in millidegrees, scale in thousandths —
  the engine's existing conventions, `session/canvas.rs:482,725`) so evaluation is
  integer-deterministic and goldens never fork per platform.
- `eval` — pure keyframe evaluation: `(tracks, frame) -> ActorPose`. Easing presets as
  fixed-point curves; hold as a tween variant. Trivially unit-tested against oracle tables.
- `compose` — the compositor: `scene_frame(scene, cache, n) -> RgbaBuffer`. Per Actor
  (respecting `pin_to` parent transforms, one level): resolve the source frame (Cycle via
  `cycle_map`, Pose via the pose track), transform via the extracted `engine::transform`
  (cleanEdge or NN per Prop style), then `over_opacity`-blit in z-order. Plus the render
  cache (§4).
- `history` — scene-shaped absolute-record undo (its own small `Edit` enum; byte-weighted,
  capped; trivial next to pixel history).
- `io` — the `.mkps` codec over the extracted container primitives (§7).
- `session` — `SceneSession`: owns `Scene` + editor state (selection, playhead, auto-key
  flag), `run_script` + `SceneAction` enum + `exec`, budget chokepoints, `state_json`,
  `composite_bytes(frame)`, probes.

Everything above is conventional Rust with proven in-repo templates; no research risk. The
compositor's correctness burden is carried by the same golden/probe discipline as the engine
(§8).

## 4. Performance feasibility: scrub and playback

The design demands flawless scrubbing and loop-while-editing playback. Cost model at the
ceiling (256×256 Scene):

- **Blit-only frame** (no rotation/scale active): per-pixel `over_opacity` over each Actor's
  opaque bounds, tile-sparse. This is `render.rs`-class work the engine already does per
  display refresh on the same hardware — known-fast, not a risk.
- **Transformed Actor**: inverse-map per destination pixel; cleanEdge samples a 5×5
  neighborhood with early-out on flat regions (`cleanedge.rs:360`). The editor already runs
  exactly this cost *interactively* during Rotate/Scale draft preview over full canvases —
  on-device evidence it is acceptable at these resolutions.
- **The structural advantage ADR-0001 hands us**: Keys on the frame grid + integer transforms
  mean a scene frame is a *pure function of the document* — perfectly cacheable.
  - **Transform cache** (Rust): `(prop, source_frame, quantized transform) → RgbaBuffer`,
    LRU by bytes. A 12-frame walk cycle rotated to 3 poses costs 36 transforms *ever*, not
    per scrub.
  - **Frame cache** (Dart): composited scene frames as `ui.Image`s under `ByteBudgetLru`
    (`club/anim/byte_budget_lru.dart`), invalidated by an epoch counter bumped on every
    mutating DSL send. 256×256×4 = 256 KiB/frame → a 64 MiB budget holds 256 frames; playback
    then costs one array index per tick (the Club model), and scrubbing warm frames costs
    zero FFI calls.
- **Scrub miss path** (cold frame): one `mkps_composite` + premultiply + `decodeImageFromPixels`
  — identical in shape and cost to the editor's per-pointer-event `_redraw`, which ships today.

Verdict: no performance blocker at the decided ceilings; the caches are the design, not an
optimization afterthought. The one measurement to take early (Phase 2 exit): worst-case cold
scrub (max Actors, all transformed, cleanEdge) on the Pixel-class device, against a 16 ms
target.

## 5. The FFI seam extension

A parallel `mkps_*` family in the same cdylib (`crates/ffi` grows a `scene` module; one
library, both sessions — the Editor⇄Animator round-trip then never crosses a process or
library boundary):

- Lifecycle/command: `mkps_new(w, h, fps)`, `mkps_free`, `mkps_run` (DSL; null or error
  C-string — same contract as `mkpx_run`).
- State: `mkps_state_json`, `mkps_mem_json`, `mkps_frame_count`, `mkps_playhead`.
- Pixels: `mkps_composite(frame, out, cap)` (caller-provides-buffer, straight alpha),
  `mkps_track_thumb(actor, tw, th, out, cap)`, `mkps_frame_hash(frame)` (cache
  invalidation).
- Documents: `mkps_save(out_len)` / `mkps_load(data, len)` (loader refusal inside);
  `mkps_import_prop(data, len, split_layers) -> id` routes PNG/GIF/WEBP through
  `codec::decode` and `.mkpx` through `engine::io` (layers → separate Props for the
  Whole/Parts card).
- Export: `mkps_export_gif(scale, out_len)` / `mkps_export_webp(scale, out_len)` — the
  Scene compositor as the `next()` closure into the existing streaming encoders; shares the
  process-wide progress/cancel atomics (`ffi/src/lib.rs:24–29`) so the Dart-side progress
  dialog works unchanged.

All conventions inherited: null-guarded session helper, sentinel returns, capacity checked
before copy, no panics. Dart side: `engine_ffi.dart` grows a parallel `SceneEngine` class (or
a sibling file) reusing `_open()`, the scratch-buffer pattern, and `premultiplyRgbaInPlace`.

## 6. Memory feasibility under the 1 GiB wall

The Animator's Scene budget must coexist with the Editor's (both pillars never run
simultaneously — the shell mounts one at a time and the editor frees its session on dispose —
but the *transition* overlaps briefly, and the Club's 96 MiB animation cache is long-lived).
Working allocation sketch, same discipline as memlab (soft short-circuit + exact recalibration
+ hard refusal + rollback):

| Pool | Budget | Notes |
|---|---|---|
| Scene document (Prop art, deduped by tile like the editor: `unique_payload_bytes` pattern) | 192 MiB hard / 160 soft | The dominant pool. Worst legal Prop = 1024×1024×4 = 4 MiB/frame *dense*; tiling + COW means duplicated/transparent regions cost little. Enforced at the three chokepoints + `.mkps` loader refusal before materialization (the `io.rs:763` pattern). |
| Transform cache (Rust) | 32 MiB LRU | Evictable at will; never refuses. |
| Scene undo | 8 MiB | Records are Keys/fields — orders of magnitude below pixel history; 128-step depth costs almost nothing. |
| Frame cache (Dart, `ui.Image`s) | 64 MiB LRU | GPU-side via Impeller but budgeted conservatively as CPU-equivalent; refcounted like `DecodedAnimation`. |
| Export transient | streaming | Both encoders stream frame-at-a-time; nothing accumulates but output (proven shape, `ffi/src/lib.rs:523`). |

Total worst case ≈ 296 MiB Rust-side + 64 MiB Dart cache — comfortably inside the envelope
that memlab validated for the editor (320 + 96 + transients) against the ~1 GiB scudo wall.
Per-Prop import gate: the 1024/side design cap and a per-Prop byte cap enforced at
`mkps_import_prop` *before* decode via codec's existing dimension/byte limits — the P-0
lesson from the memory audit (imports must hit the chokepoint) applied from day one. The
memory ladder harness (`tools/memlab/`) extends naturally: scripted scenes at increasing
Prop counts/sizes, `mem`/`mem.os` probes, SIGABRT watch on device.

## 7. The `.mkps` container

Phase 0 extracts the private v10 machinery (`Writer`/`Reader`/`crc32c`/`write_chunk`/
`walk_chunks`/`encode_tile`/`decode_tile`) into a public `engine::io::container` module —
small and mechanical; none of it touches `Document`. `.mkps` then reuses, unchanged:
signature-style 8-byte magic (own signature, e.g. `\x89MKPS\r\n\x1a`), chunk framing with
critical/ancillary semantics, canonical LEB128, CRC-32C `INTG` trailer, the RAW/RLE/INDEXED
tile codec menu, and the content-addressed tile dictionary (Prop frames dedupe exactly like
`.mkpx` frames — pointer cache first, content hash verified on hit).

New chunk sketch: `SHED` (crit: version, canvas, fps, frame count, background, flags) ·
`TILE` (crit: shared tile dictionary for all embedded Prop art) · `CAST` (crit: Props — name,
dims, per-frame tile-ref grids, cycle_map, style) · `ACTS` (crit: Actors — prop ref, mode,
pin_to, z-order, per-property key lists with tween ids) · `INTG` (crit). Ancillary room for
thumbnails/session state later. Determinism inherits the v10 measures verbatim
(first-appearance dictionary order, codec tie-breaks, exact-size buffers, semantic
content-hash check after reconstruction); `deterministic_bytes`-style goldens from day one.
Self-containment (ADR-0002) is structural: Prop art lives in the file's own dictionary; there
is nothing to reference. The DEFLATE compact envelope (`mkpx_compact`) applies unchanged if
`.mkps` files want it (`MKPZ`-style sibling signature).

## 8. Dev loop and testing

- **CLI**: `mkpx` gains a `scene` subcommand family (`mkpx scene run <script> [probes]`,
  `scene load`, `scene gen`) sharing the probe evaluator and exit-code contract (0/1/2).
  Scene probes: `ascii:F` / `hash:F` / `stats:F` over composited frames (the existing probe
  functions take `RgbaBuffer` — zero new probe code), `render:F:out.png`, `state`, `mem`,
  `assert.roundtrip` (save→load→content-hash), plus a new `assert.eval:actor:frame:prop=val`
  oracle for keyframe evaluation. The fast loop — edit Rust → run a scene DSL script → read
  ASCII/PNG/JSON — carries over intact, which is the whole reason the Rust-core decision
  pays for itself during development.
- **Rust tests**: inline unit tests per module; `crates/scene/tests/` scenarios driving
  `SceneSession` through DSL scripts with hash goldens; determinism suite (same scene ⇒
  identical `.mkps` bytes and identical composite hashes on all platforms).
- **Dart tests**: the four established seams apply (pure-logic extraction, shell-boundary
  pillar stubs, contract harnesses, no `Engine` construction). The Animator adds its pure
  timeline/viewmodel math as engine-free files from the start; `SceneStore`/autosave reuse
  the already-tested persistence classes.

## 9. Export correctness notes

- **GIF timing**: the fps list (10/12.5/20/25/50) yields exact centisecond delays
  (10/8/5/4/2 cs) through `Delay::from_numer_denom_ms` — preview and export agree by
  construction, closing the loop ADR-0001 promised.
- **WEBP timing**: `ANMF` durations are milliseconds; all listed rates are exact.
- **Opacity**: WEBP path is lossless VP8L with alpha — true fades, no work. GIF path adds the
  decided threshold step (alpha ≥ 128 → opaque) applied to composited frames before
  quantization, plus the export-notice UI; both are Scene-side additions, codec untouched.
- **Integer upscale**: `upscale_nearest` reused as-is; the streaming encoders already accept
  a scale parameter.

## 10. Phases and sizing

Anchors from shipped work: **S** ≈ player-registration · **M** ≈ palette page ·
**L** ≈ memlab budget enforcement, tablet/landscape support · **XL** ≈ larger than any
single shipped feature. Order is dependency order; each phase exits green (tests + probes).

| Phase | Contents | Size |
|---|---|---|
| **0. Extractions** | `io::container` pub module; `engine::transform` (rotate/scale resample de-drafted); Flutter chrome lift (sliders/toggles/sheet primitives → `lib/ui/`). Pure refactors, zero behavior change, each verifiable by existing tests/goldens. | **M** |
| **1. Scene core** | `crates/scene`: model, eval, history, `SceneSession`, DSL, budgets. CLI `scene` subcommand + probes + goldens. | **L** |
| **2. Compositor** | `compose` + transform cache + Cycles (quantize-at-import); device measurement of cold-scrub worst case. | **M** |
| **3. `.mkps` codec** | Chunks over the container; determinism suite; loader refusal; compact envelope. | **M** |
| **4. FFI + Dart binding** | `mkps_*` family; `SceneEngine` Dart class; export wiring incl. GIF threshold + notice. | **S–M** |
| **5. Flutter pillar** | Shell slot + bridge + `SceneStore`/autosave (**S**); Stage — painter, Listener state machine, transform gestures, auto-key, pivot (**L**); timeline — Strip/Tracks/Focus, retiming drags, easing chips, playback via frame cache (**L**); import flow (Whole/Parts card) + export flow (**M**). | **XL** (sum) |
| **6. Device validation** | Android memory ladder for scenes; scrub/playback profiling on the Pixel; Windows visual pass. | **M** |

Critical path: 0 → 1 → 2 → 4 → 5; phase 3 can proceed in parallel after 1. The v0.1 slice
(Full Tier 0 + Playing Cycles) is exactly phases 0–6; nothing in the decided scope falls
outside them.

## 11. Risk register

| Risk | Exposure | Mitigation / kill-switch |
|---|---|---|
| Timeline UI feel on phones (the product bet itself) | High — largest phase, least derisked by existing code | Build Stage + Strip first inside Phase 5 and put the three design bets (auto-key feel, layers-become-limbs, small sittings) in front of the user before Tracks/Focus polish; the phase is structured to produce that testable middle early. |
| Cold-scrub latency on low-end Android (cleanEdge, many Actors) | Medium | Measured at Phase 2 exit against 16 ms; fallbacks in order: NN-during-scrub (cleanEdge on settle), tighter transform cache, background pre-warm of neighbor frames. All degrade quality of *preview during motion* only — never export. |
| Scene memory model wrong (Prop-heavy scenes hit refusals in normal use) | Medium | The budgets in §6 are start values, not conclusions; the memlab ladder methodology exists precisely to tune them on device before release. Loader refusal keeps the wall unreachable regardless. |
| Two-session FFI coexistence (Editor + Scene sessions alive during round-trip) | Low | Both are independent opaque pointers in one cdylib; the round-trip design (§5 of 04) serializes through `.mkpx` bytes, no shared state. The brief memory overlap is counted in §6. |
| `image-webp`/`image` upgrades shifting encoded bytes | Low | Golden tests pin encoder outputs; versions are already pinned in `Cargo.lock`; the hand-muxed container is ours. |
| Chrome extraction destabilizes the editor | Low | Phase 0 is mechanical moves with zero logic change, covered by `flutter analyze` + existing widget tests; do it as its own commit before any Animator code. |

## 12. Incidental findings (repo hygiene, not Animator work)

Surfaced by this audit; worth fixing independently:

1. **CLAUDE.md is stale on two points**: codec exports are listed as "PNG/sprite-sheet/GIF"
   (animated WEBP export exists: `codec/src/lib.rs:212–334`), and the shell section still
   describes the editor surviving pillar switches "via `EditorSession` (.mkpx snapshot in
   dispose/initState)" — that mechanism was replaced by the autosave flush
   (`editor_page.dart:463–480`).
2. `test/shell_test.dart:9` comments that it asserts on "the IndexedStack index"; the
   IndexedStack is long gone.
