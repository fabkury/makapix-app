# Makapix Editor memory-discipline audit

*2026-07-29 · scope: the Rust engine (`crates/`) + the Dart editor shell (`app/lib/editor/`,
`app/lib/engine_ffi.dart`) and the Club paths that drive the engine (publish export, edit/remix
intake). Method: full code inspection of the memory-relevant paths, three parallel deep-read
sweeps, targeted headless `mkpx` measurements on Windows, and — see the **device addendum at the
end** — on-device confirmation (Pixel 10 Pro XL) of the import/export/crash findings, added the
same day. No product code was changed; the addendum's `mkpx import` subcommand and
`tools/memlab/make_gif.py` are non-shipping lab tooling. Baseline numbers and the enforcement
already in force: `docs/memlab/REPORT.md`.*

## Verdict, in one paragraph per question

**Is the app being wasteful of memory in any meaningful way?** Not where it matters most. The
*retained* memory model — the thing that decides whether a session survives on Android — is in
genuinely good shape: COW tiles, patch-based undo, Arc-shared tables and masks, and the
2026-07-16 budget enforcement (96 MiB history, 256/320 MiB document, loader refusal) all hold up
under inspection, and nothing in the engine grows unboundedly over a session. But the audit
found **one genuine hole in that enforcement — image import bypasses the document-budget
chokepoint entirely (P-0), now confirmed on-device: an import drove the engine to 512 MiB, 60%
past the 320 MiB hard cap, with zero refusals, and the resulting file is refused by its own
loader on reload** — plus meaningful waste in three places: (1) **transient churn on
the interactive path** — every pointer move composites 9× the pixels it needs and copies the
result three times, and several tools deep-copy a 9×-oversized selection mask per stamp;
(2) **a small set of Dart-side defects** — an unbounded `ui.Image` leak in image import, an
O(frames×layers) state-JSON tree rebuilt on every action, missing `try`/`finally` + nullptr
checks around the FFI `save()`; and (3) **peak multiplication during import/export/publish** —
a second full engine document in the encode isolate, an all-frames-up-front decode with no
aggregate cap, and a still-export path that can transiently hold ~512 MiB for one 32× PNG.

**Would refactoring yield meaningful gains?** Yes — but the wins are correctness, churn and
peak headroom, not resident-footprint. Three changes are near-free and should come first:
routing import through the existing `edit_doc` budget gate (closes the invariant hole), the
Dart hygiene batch (leak, FFI guards, cache clears), and a running-bytes cap in the animated
decoder (closes a crash-from-a-small-file hole). The two highest-ratio churn changes are
rendering the display at `canvas_rect` instead of `storage_rect` when overscan is off (a
one-site change that removes 8/9 of the per-pointer-event tile churn, onion included) and
reusing the display transfer buffers end-to-end (removes two of three full-buffer copies per
pointer move plus ~15–30 MB/s of Dart old-space churn during strokes). The deeper refactors —
canvas-sized masks, streaming animated export, slimming `state_json` — carry real gains at
scale but touch serialization, golden determinism or shell coupling, and are worth doing
deliberately, not casually. Full ranked table with costs and risks below.

**Other considerations?** Two budget blind spots worth knowing about (tile-slot tables and
decoded-import accumulation are both invisible to the 320 MiB budget), the Windows/Android
asymmetry that makes churn invisible on the workstation, and iOS still unmeasured.

---

## What is already disciplined (and must be preserved)

Credit where due — these were verified, not assumed:

- **The tiled COW core** (`crates/engine/src/buffer.rs`): `Arc<TileTable>` +
  `Arc::make_mut`, sparse absent-tile representation, `compact()` that reads before cloning.
  Duplicating a frame or layer is a pointer bump; the normal animation workflow is near-free.
- **Patch-based undo** (`buffer.rs:354`, `history.rs:30`): a stroke retains only changed tiles
  (~4–66 KiB per record for normal drawing at 256², table below); no whole-table
  retention since memlab M1. A pixel-only record's selection snapshot shares one `Arc` for
  before+after — free.
- **The budget chokepoints** (`session.rs:1053` `commit_edit`, `:1101` `edit_frame`, `:1121`
  `edit_doc`): the `mem_slack` bound keeps the exact census off the hot pixel path; structural
  ops census exactly and roll back wholesale. The strict "never over 320 MiB unique payload"
  invariant holds at every mutation edge and at `.mkpx` load (`io.rs:763`).
- **History is fully bounded**: per-frame 128 cap, global 8192 cap, 96 MiB byte budget with
  deliberate over-counting in `weight_of` (`history.rs:98`) — the effective retention is ~half
  the nominal budget. Redo bytes are settled before clearing. Nothing in the engine (stroke
  paths, pp tails, counts map, `layer_sel`) grows unboundedly over a session.
- **The `.mkpx` save path post-M4/M5** (`io.rs:466`): dictionary entries are live `Arc`s (no
  byte clones), one 4096-B temp per entry, `reserve_exact`-sized output. Measured this audit:
  a 16.8 MiB noise document's full save+load round trip peaks at +36 MB over resting — ~2.2×
  payload of transient, matching the memlab post-fix numbers.
- **Codec decode limits** (`crates/codec/src/lib.rs:39-52`, audit F-3): per-frame 4096×4096 and
  512 MiB single-allocation limits are installed *before* decoding, animated decode is lazy
  (never `collect_frames`) with a 1024-frame cap. Multi-frame *encoders* upscale one frame at a
  time and accumulate only compressed output; GIF export quantizes and LZW-writes one frame at a
  time straight into the output (the correct streaming shape).
- **The `.mkpx` loader** walks chunks zero-copy (borrowed slices), enforces the budget before
  allocating any tile, bounds every pre-allocation by the actual payload length, and restores
  COW sharing on install (one `Arc` per dictionary tile) — so a loaded document's unique payload
  is exactly the dictionary, which is what makes the up-front refusal sound.
- **Dart display-image lifecycle** (`editor_page.engine.dart:240-267`): every `ui.Image` swap
  disposes the predecessor on both mounted and unmounted branches (the audit-F-10 fixes are
  complete); `dispose()` tears down timers, thumb caches, notifiers and the engine in the right
  order. Timeline thumbnail generation disposes on every path and de-duplicates in-flight work.
- **The repaint scoping** (audit F-9/F-11): freehand strokes repaint canvas+overlays only (the
  per-tile-FFI film strips don't rebuild per move); the selection mask is re-pulled only when it
  can have changed; `CanvasPainter` draws one retained `ui.Image` via `drawImageRect` with a
  single static checker `ImageShader`.
- **Pillar switching retains zero bytes**: `AppShell` holds only an index; editor persistence
  is the on-disk autosave (`editor_page.dart:433` documents the removal of the old in-memory
  snapshot). `AutosaveController` is single-flight, latest-wins, and holds at most one snapshot
  during a write. Riverpod bridges (`edit_bridge.dart`) carry no pixel data and are consumed
  once.
- **Exports run off the UI isolate** with a throwaway engine disposed in `finally`, progress and
  cancel via process-wide atomics, and an upfront flatten-size guard (`ffi/src/lib.rs:510`).

Undo retention for normal drawing, for reference (per frame at the 128-record cap):

| Canvas | Typical stroke | Retained at cap |
|---|---|---|
| 64×64 | 1 tile | ~0.5 MiB |
| 256×256, short strokes | 2–4 tiles | 1–2 MiB |
| 256×256, long strokes | 8–16 tiles | 4–8 MiB |
| 256×256, full-canvas repaints (adversarial) | 64 tiles | 33.7 MiB — what the 96 MiB budget exists for |

---

## Findings — peak and retained memory (the Android-wall axis)

Scale anchors: canvas ≤256×256; storage = 3w×3h = 768×768 (the Move-gutter design); a tile is
4096 B payload / 4112 B allocated; a 256×256 layer's tile-slot table is 576 slots = **4608 B**
— both land in the ~4 KiB scudo size class that aborts near 1 GiB on Android.

### P-0 · Image import bypasses the document memory budget — the one broken invariant

`Session::import_decoded` (`crates/engine/src/import.rs:160-209`) hand-rolls the structural-edit
protocol (`frames.clone()` → mutate → `record_doc_structure("import", …)`) instead of going
through `edit_doc` (`session.rs:1121`), whose own comment names *import* among the mutations it
guards — and so did the shipped memory-budget-enforcement plan (M3; retired to git history). Verified
first-hand: no post-import census, no rollback, no refusal telemetry, and `mem_exact`/`mem_slack`
are left stale (subsequent pixel edits trust a too-small cached census until the slack bound
trips). With `as_layer=true` an import is purely additive on an existing document, so unique
payload can be pushed past the 320 MiB hard cap — the "a session is never over budget"
invariant does not hold across this one edge. No test catches it: there is no `Import` DSL
action, so the path is reachable only via `mkpx_import`, and the import tests use 16×16
canvases. The fix is exactly the one every sibling op already uses: run the body inside
`edit_doc("import", …)`.

### P-1 · Export/publish materializes the document twice (by design, but unbudgeted jointly)

`Engine.encodeInBackground` (`app/lib/engine_ffi.dart:451`) serializes the live document, copies
the bytes into the isolate (`Isolate.run` copies captured buffers), `malloc`-copies them again
for `mkpx_load`, and rebuilds a **second full engine document** there. At peak a publish holds:
the live document (≤320 MiB of tiles in the fatal class) + up to three copies of the `.mkpx`
bytes + the isolate's document (≤320 MiB more in the same class) + the flatten for the animated
encoder (≤256 MiB, large-class) + the encoded output. The isolation design is correct (opaque
session pointers must not cross isolates — audit F-12) and realistic documents are far smaller,
but these overlap into a large total-RSS peak with no joint guard. **Measured on the Pixel
(addendum): publishing a legal, under-budget 256 MiB document peaked at 2.45 GiB resident —
~9.6× the document** (the source-only pass estimated ~640 MiB in the fatal class; the true peak
is much larger and dominated by total RSS). The 16 GB device absorbed it; a mid-range phone
would not. Two aggravators found on review of the encode side:
the flatten guard (`ffi/src/lib.rs:510`) **ignores `scale`**, and the share UI offers up to 32×
(`app/lib/share/image_share.dart:32`, warn-only at 64 MP, never refuse) — a single 256×256 still
at 32× is an 8192×8192 = 256 MiB raster that the PNG path then holds **twice** (`still_out`
upscales into one buffer, `encode_png` at `codec/lib.rs:163` copies it again via
`rgba.to_vec()`; the WebP still encoder is already zero-copy, the model to follow). The animated
WebP muxer additionally holds the *compressed* animation ~3× at peak (per-frame VP8L chunks +
`body` + `out`, `codec/lib.rs:216-256`) — compressed, so rarely large. `_postToClub`
(`editor_page.fileio.dart:170-206`) additionally keeps `docBytes` alive across the whole flow
and then retains **both** the exported WebP and a second `saveCompact()` serialization inside
`PublishDraft` for the entire publish page's lifetime.

### P-2 · Tile-slot tables are invisible to the memory budget — measured

The budget counts **unique tile payload only** (`document.rs:302`). Every independently created
layer buffer owns a 4608 B table (at 256×256) in the fatal class. Measured this audit with the
`mem` probe: 128 frames × 16 blank layers → `tile_table_bytes` 9,437,184 (exactly 2048 × 4608 B)
with **zero** budgeted payload; growth is linear in layer count. Extrapolations:

| frames × layers (256×256, all layers touched/created independently) | Table bytes in the ~4 KiB class |
|---|---|
| 1024 × 1 | 4.5 MiB |
| 1024 × 4 | 18 MiB |
| 1024 × 16 | 72 MiB |
| 1024 × 64 (legal maximum) | **288 MiB** |

Duplicated-then-unedited frames share tables (COW — also verified: the same script's history
snapshots added zero `history_table_bytes`), so realistic documents sit near the top rows. But a
max-axes document near the payload budget could carry ~600 MiB in the fatal class *before*
export doubles it (P-1) — the two findings compound. The census already computes
`tile_table_bytes` deduped by pointer (`probe.rs:306`); the budget just doesn't read it.

### P-3 · Animated import: per-frame caps but no *sum* cap, and all-frames-up-front

`decode_animated` (`crates/codec/src/lib.rs:107`) enforces ≤4096×4096 per frame and ≤1024
frames — but never their **product**, and accumulates every decoded RGBA frame in one Vec
before the engine sees anything (`mkpx_import` at `ffi/src/lib.rs:371` then holds the full
decoded set alive across the entire tiling loop). Three consequences, in increasing severity:

- **Legitimate worst case**: importing a 1024-frame 256×256 GIF peaks at ≈2× the final
  document (256 MiB decoded + 256 MiB tiles, simultaneously) — RSS-heavy but mostly outside
  the fatal ~4 KiB class (decoded frames are 256 KiB allocations). A streaming
  decode→tile→drop path would make this 1× + one frame.
- **The multiplier scales with source/canvas area**, up to 256× for a 4096×4096 source.
- **A crafted GIF bomb is cheap**: the `image` crate composites every sub-frame to the full
  logical screen, so 1024 one-pixel sub-frames on a 4096×4096 screen — a file of a few MB —
  each yield a 64 MiB frame; 16 frames in, the accumulation passes 1 GiB and the infallible
  allocator aborts (Android) or swap-storms (Windows). The codec's `max_alloc = 512 MiB` limit
  cannot help: `image` deliberately resets it per frame, and it has no visibility into the
  caller's accumulating Vec. (The cap check also runs after the iterator yields, so frame
  #1025 is fully decoded before being rejected.)

The whole decode also runs synchronously on the UI isolate. A running-bytes cap in
`decode_animated` is a ~5-line fix that closes the bomb; streaming import closes the 2×.

### P-3b · `.mkpx` load holds old + new document simultaneously, unchecked jointly

`Session::load_bytes` fully materializes the incoming document **before** dropping the old one
(the source of the measured 2.1–2.2× load transient — old doc + new doc are the 2×; file
copies and scratch are the fraction). The loader's up-front budget check (`io.rs:763`, clean in
itself) compares the *file* against the hard budget but ignores the still-resident old
document: loading a 320 MiB file over a 320 MiB session is accepted and transiently holds
~640 MiB of tiles (plus up to 96 MiB of old history) in the fatal class. The loader already
validates signature/CRC/geometry/budget before allocating any tile, so a "validate first, drop
the old document to a placeholder, then materialize" sequence would halve the transient while
keeping the corrupt-file-leaves-current-drawing-intact guarantee the shell relies on.

### P-4 · Dart-side retained memory defects

- **`_importImage` leaks an unbounded `ui.Image` + its codec**
  (`editor_page.fileio.dart:88`): `srcImg` is used only for its dimensions and is never
  disposed on any path; `_decodeBytes` (`editor_page.engine.dart:405`) never disposes the codec
  (which holds a whole animation's decode state for GIF/APNG). A 12 MP photo ≈ 48 MB of
  native/GPU memory retained until a finalizer happens to run; repeated imports stack. The
  source is also decoded a second time by `CropPage`. This is the one genuinely *leaked*
  allocation found in the audit.
- **`_state` retains a fully materialized JSON tree of every frame × layer**
  (`editor_page.engine.dart:310` ← `probe.rs:117` `frame_detail`): rebuilt (Rust string + Dart
  string + decoded map tree, transiently ~2× alive) on every discrete action via
  `_refreshState()` (~38 call sites). The UI consumes only the active frame's layers and the
  per-frame durations. Negligible below ~100 frames; at 1024×64 it's ~10–15 MB retained and
  ~10 MB of per-action transient strings, plus the Rust-side O(frames×layers) string build.
- **Gallery grid** (`gallery/drawing_library_grid.dart:49-99`): eagerly loads **every** library
  drawing through a temp engine (each drawing's *full document* materialized in turn, while the
  editor's live document stays resident — peak = live doc + largest library doc) and holds one
  220×220 `ui.Image` per drawing with no cap (~19 MiB per 100 drawings, for the page's
  lifetime). Rename/Delete re-runs the entire load.
- **Timeline thumb caches are never cleared on document switch**
  (`editor_page.dart:282`, cleared only in `dispose()`): bounded (~2.2 MiB, 80+60 entries of
  64×64), but stale images from the previous document stay resident and are even painted for one
  frame before hash-mismatch regeneration; eviction is insert-order, not LRU, so long film rolls
  thrash.
- **`ClubEditRequest` bytes** are held across two nested modal dialogs awaiting user input
  (`fileio.dart:233`) — transient but user-controlled in duration; provider hygiene itself is
  correct.

### P-5 · FFI wrapper hygiene: the failure paths leak or misbehave exactly at the ceiling

`engine_ffi.dart` has 28 `malloc` sites and no `try`/`finally` around any of them: if
`Uint8List.fromList` throws (Dart-heap OOM copying a large buffer), the native buffer — for
`save()`, the entire serialized document — leaks at the precise moment the process is out of
memory. `save()`/`saveCompact()` (`engine_ffi.dart:274,287`) additionally read `lenPtr.value`
from **uninitialized** `malloc<Uint64>` memory and dereference the result pointer with no
nullptr check (every `export*` sibling checks; these two don't). Not reachable today because
`mkpx_save` cannot fail with a live session — but `save()` is the 5-second autosave path, and
the memlab plan's own recommendation #4 (surface engine allocation failure as an error instead
of SIGABRT) would make these paths reachable the day it lands. Fix the wrapper first.

---

## Findings — interactive churn (per-pointer-event transients)

None of these raise steady-state footprint; they are allocator/GC/CPU churn at 60–120 Hz on the
exact allocator class Android is sensitive to, and they are invisible on the Windows
workstation. Cadence was verified end-to-end: `editor_page.canvas.dart:481-488` sends
`PointerMove` + `_redraw(full:false)` on every move; `_redraw` calls `engine.display(...)`.

### C-1 · The display path renders 9× the needed area and copies the result three times

`display_bytes` (`session.rs:569`) always composites the **full 768×768 storage**, then crops to
the canvas (`:575`) — the code carries its own `[perf: … optimize if it bites]` marker. Per
pointer move that is two fresh storage-sized tiled buffers (a 4608 B table each + one 4112 B
tile per touched cell — ~0.5 MiB sparse, up to ~4.7 MiB dense, in the fatal class), an onion
pass repeats the composite per neighbor, and the result then crosses the boundary as **three
sequential full copies**: Rust `Vec` → memcpy into Dart's `malloc` buffer → `Uint8List.fromList`
Dart-heap copy → `decodeImageFromPixels` GPU copy (`ffi/src/lib.rs:141`,
`engine_ffi.dart:188-195`). At 256 KiB per buffer and pointer rate this is ~15–30 MB/s of Dart
old-space allocation during every stroke, plus a 65k-iteration Dart `premultiplyRgbaInPlace`
loop per move on the UI thread. `mkpx_outline_mask` (`ffi:175`) already demonstrates the right
pattern — write straight into the caller's slice. `_redraw` is also fire-and-forget with no
in-flight coalescing, so slow decodes can pile up (peak, not leak).

### C-2 · Selection masks are storage-sized (9×) and deep-copied per stamp

Every `Mask` is built at 768×768 = **72 KiB** instead of the 8 KiB a canvas-sized mask would be
(all creation sites verified storage-sized; the `document.rs:166` comment claiming canvas-sized
is stale). `selection_clone()` (`session.rs:393`) then deep-copies it on every stamp:
`stamp_active:1594`, `stroke_active:1601`, `pencil_perfect_segment:1635`, and *inside the
per-stamp loop* for airbrush/dodge/burn — N × 72 KiB per pointer move when a selection exists,
purely to satisfy the borrow checker (the tools take `Option<&Mask>`). Selection-tool pointer
moves additionally allocate 2–3 fresh masks each in `outline_mask` (`session.rs:819`), and
`stroke.path.clone()` per refresh makes freehand select O(N²) bytes over a long gesture.

### C-3 · Move drag, transform drafts and adjustment previews rebuild whole layers per event

- **Move-tool layer drag** (`session.rs:1315-1328`): per pointer move, per moved layer:
  `clear()` — which allocates a *fresh* table (`buffer.rs:233`) rather than reusing a uniquely
  owned one — then a full 589k-pixel re-blit rematerializing every touched tile. A 64-layer move
  group multiplies accordingly. The same clear-then-reblit shape appears in five other sites
  (per-action there).
- **Rotate/scale drafts** resample the full storage **2–3× per displayed frame** — once for the
  preview frame, again for the wash, again for the outline — each pass allocating a storage
  buffer + a 72 KiB mask; frame scope multiplies by layer count (`canvas.rs:531-589,822`).
- **HSV/Brightness previews** (`session.rs:2294,2344`) clone the active frame and rewrite every
  present tile of the affected layer(s) per refresh during a slider drag — up to ~150 MB/s of
  4-KiB-class transient on a dense multi-layer frame. All transient, all freed per tick; churn
  and battery, not retention.

### C-4 · Overlay machinery runs at vsync forever and allocates per tick

The marching-ants `AnimationController` (`editor_page.dart:410`) starts in `initState` and
never stops — with no selection, no eraser, app backgrounded, it still schedules repaints at
60 Hz, and each `OutlinePainter.paint` builds two fresh `List<Offset>` (worst case — a
scattered select-by-color selection — ~500k `Offset`s per frame; typical marquees are
perimeter-sized and fine). Edge lists themselves are one boxed `List<int>` per edge (~96 B),
retained while the selection exists (~25 MiB worst case, ~100 KiB typical) and re-spread into a
new list on every eraser move.

### C-5 · Smaller hot-path allocations (listed for completeness)

Flood fill's `vec![false; storage]` = 576 KiB per bucket tap where a bitset/canvas-bounded
visited set would be 8–72 KiB (`tool.rs:334`); `Mask::bounds`/`intersect_rect` scan bit-by-bit
(~590k iterations) on pointer-down paths; a `malloc`/free pair + `utf8Encode` per DSL command at
pointer rate; assorted per-event `Vec<Point>` scratch in stroke/raster helpers; GIF encode
clones each frame at scale 1 (`codec/lib.rs:313`); `edit_doc` clones the full frame vector
twice per structural op (Arc-cheap, but two `String` allocations per layer name — 131k at max
scale, bounded by the history budget).

---

## Findings — recurring background work

### R-1 · Autosave serializes the whole document every 5 s of *any* activity, then decides

`AutosaveController` (`autosave_controller.dart:61-71`) runs `engine.save()` — the full
serialize, with its `reserve_exact` worst-case-payload tile chunk (~payload-sized) and a full
Dart copy — *before* the FNV-1a hash decides nothing changed. `markActivity()` fires on every
`_send` (`editor_page.engine.dart:211`), including non-mutating settings pushes and playback's
30 Hz `AdvanceClock`, so watching a large animation re-serializes and re-hashes the entire
document every 5 s for nothing. The Rust side also recomputes the full-document `content_hash`
(every present tile byte) per save. All of this is synchronous on the UI isolate (a deliberate,
documented engine-lifetime trade-off). Negligible at realistic sizes (ms and a few MB); at
budget scale it is a ~2× payload transient plus a multi-second UI stall every 5 s. A cheap
mutation-counter (undo-stack revision) gate before serializing would remove ~all of the wasted
cycles without touching the write path's good discipline.

### R-2 · `state_json` does more per action than its consumers use

Beyond the P-4 `frame_detail` tree: every call runs a fresh exact unique-payload census
(`session.rs:955` — HashSet over all tile pointers, ~2 MB transient + ~1 ms at budget scale).
Verified off the pointer path (pointer-up and discrete actions only), so this is within its own
documented contract — listed because slimming `state_json` (proposal #9) should carry the
census to a narrower, on-demand probe at the same time.

---

## Refactor proposals, ranked by relief-to-risk

> **Status 2026-07-29:** implemented + on the Pixel: **#1, #2, cap-half of #3, #5, #6** (merged to
> `main`) and **#7, #10** + the `docBytes`-drop half of **#14** (branch `perf/tier2-peak`). P-0
> import refuses at the budget (roundtrip PASS, brick gone); the 24 KB GIF bomb errors instead of
> growing to 6.5 GB; a device draw renders cleanly through the reused-buffer display path; the
> animated export now streams one frame at a time (no all-frames flatten). **Deferred/dropped:**
> **#4** (review found an untested coordinate bug — recipe under the table); **#11** (a plan review
> proved it UNSOUND — the loader's whole-document `content_hash` check makes "validate ⇒ materialize"
> false, so dropping the old doc before materialize would let a crafted `.mkpx` on the Club remix
> path destroy the user's drawing; the 2× load transient is inherent to the crash-safety guarantee).
> The `TransferableTypedData`/lazy-`mkpxBytes` halves of #14 were dropped (no benefit / UX coupling).
>
> **Status 2026-08-04:** the `mkpx_import` off-isolate half of #3 shipped, closing #3 fully — the
> decode runs on a background isolate (`mkpx_decode_image` produces a session-free decoded-frames
> blob; only its native address crosses back, both isolates sharing the engine library's process
> heap) and `mkpx_import_decoded` applies it to the live session on the UI isolate, so imports stay
> undoable and the opaque session pointer still never crosses (F-12). Both shell import paths (file
> import + Club edit intake) now use it under a modal spinner, and a memory-budget refusal is
> reported distinctly (rc −2 / `ImportStatus.refused`) instead of reading as success.

| # | Change | Gain | Cost | Risk |
|---|---|---|---|---|
| 1 ✅ | **Route `import_decoded` through `edit_doc("import", …)`** (`import.rs:160`) | Closes P-0 — restores the "never over budget" invariant, the refusal telemetry and the census recalibration at the one edge that lacks them | Tiny — the before-clone it needs already exists; delete the hand-rolled protocol | **Low**: same rollback semantics as every sibling op; add an FFI-level over-budget import test (none exists today) |
| 2 ✅ | **Dart hygiene batch**: dispose `srcImg`+codec in `_importImage`; nullptr-check + `calloc`/`try-finally` in `save()`/`saveCompact()` (pattern-match the `export*` guards); clear thumb caches on document switch; stop `_antCtrl` when there is nothing animated to draw | Kills the only true leak; makes the OOM-adjacent paths safe; removes idle 60 Hz work | ~half a day | **Minimal** — each fix is local; existing widget tests cover the paths |
| 3 ✅ | **Sum-cap animated decode** in `decode_animated` (running-bytes total, error past e.g. 384 MiB) ✅ + move `mkpx_import`'s decode off the UI isolate ✅ (2026-08-04) | Closes the GIF-bomb abort (P-3); unfreezes import UI | Tiny (cap) + small (isolate) | **None** for the cap; isolate move follows the existing `encodeInBackground` pattern |
| 4 ⏸ | **Render the display at `canvas_rect` when `!overscan_view`** (`session.rs:569`), offsetting tool previews by the gutter origin | Removes fatal-class table allocs per move (payload is unchanged for sparse content — the "8/9" framing overstated it; the real win is 2 tables/move, and only on 64-bit) | Small edit, wide surface (~9 preview draw sites + `canvas.rs` washes) | **DEFERRED** — review found a real, silently-shipping bug (`blit_wrapped`, see recipe below) and only a modest sparse-case payoff. #5 already captures the bigger per-move copy |
| 5 ✅ | **Reuse the display transfer buffer**: persistent native scratch buffer in `Engine.display()`/`compositeFrame()`, return a view (no `fromList` copy, no per-move malloc/free), free in `dispose()` | Removes 1 of 3 full copies per pointer move + the per-move malloc/free; also `compositeFrame` (playback) | ~a day incl. lifetime care | **Low-moderate** — the view is valid only until the next call; safe because `decodeImageFromPixels` copies synchronously (engine source verified). Coupled to that behavior; re-verify on Flutter bumps |
| 6 ✅ | **Stop deep-copying masks on the stamp path**: `selection_arc()` (Arc bump) at the 8 per-event paint sites; `RgbaBuffer::clear_in_place` (reuse table when uniquely owned) for the Move-drag clear | Removes 72 KiB × N per move with a selection; removes a fatal-class table alloc per move-drag event (after the first) | Small | **Low**: behavior-identical; goldens + a COW test confirm. (Review: `move_draft_paint` gets no benefit — a sharer always pins its table — so `clear_in_place` is applied only at the layer-drag site) |
| 7 ✅ | **Count tile tables against the budget**: enforce `unique_payload + live_table_bytes` (`Document::budgeted_bytes`) at the session chokepoints via `mem_recalibrate`; surfaced as `mem_table_bytes`/`mem_budgeted_bytes` in state JSON | Closes the P-2 blind spot | Small | **Low** — applied at the session chokepoints only, **not** at `.mkpx` load (the loader builds unshared tables, so a load-time table check could refuse a legally-saved file; per review). Extreme many-independent-layer docs cap earlier — protective. Device ladder re-run confirms realistic rungs unaffected |
| 8 | **Small codec batch**: `img.into_rgba8()` in `decode_static` (one word, halves static-decode peak); `encode_png` via `PngEncoder::write_image` straight from the slice (matches the WebP still path); inflate compact `.mkpx` into an exactly-`ulen`-sized buffer; write the animated-WebP container into one buffer; make the export flatten guard scale-aware | Each removes a full-raster or full-payload transient on its path; the guard closes the 32×-still hole | ~a day total | **Low** — all output-byte-identical, pinned by existing codec round-trip tests |
| 9 | **Slim `state_json`**: emit `frame_detail` for the active frame only + a flat durations array (or add a `state_lite` used by `_refreshState`) | O(frames×layers)→O(layers) per action: removes the ~15 MB retained tree and per-action string churn at high frame counts | Moderate — Rust probe + 3 Dart decode sites + tests | **Moderate**: the CLI `state` probe output is asserted in tests and may be a compatibility surface; version the probe rather than mutate it |
| 10 ✅ | **Stream the animated export**: `encode_gif_streaming`/`encode_animated_webp_streaming` pull one composited frame at a time (the slice `*_with` fns are thin wrappers, so all callers/tests are unchanged); the FFI composites on demand — no all-frames flatten | Removes the ≤256 MiB flatten from the export (and thus from the isolate's publish peak) | Moderate — encoder cores + FFI export bodies + progress | **Moderate-low** — lossless round-trip tests prove identical content; `&self` composite closure is sound (nothing mutates the session mid-encode) |
| 11 ❌ | ~~Load: validate first, then drop the old document, then materialize~~ | — | — | **DROPPED — UNSOUND.** The loader's final whole-document `content_hash` check (`io.rs:895`), plus FRMS/UPAL/SELC failures, make "validate ⇒ materialize" false: a CRC-valid crafted `.mkpx` (wrong hash / bad ref-grid) passes a cheap validate but fails materialize. Dropping the old doc first would then leave the user with **no document** — data loss on the untrusted Club remix/download path. The 2× transient is inherent to the guarantee (`self.doc = load(...)?` is `Err`-safe today); freeing old history first can't help without holding it or regressing failed-load undo. Left as-is. |
| 12 | **Cache transform-draft resamples** (compute once per state change, reuse across preview/wash/outline) and gate HSV/BC preview recompute on parameter change | Removes 2/3 of draft resample churn and the slider-drag deep-copy storm | Moderate — invalidation discipline in `Session` | **Moderate**: a stale-preview bug class that doesn't exist today; needs targeted tests |
| 13 | **Canvas-sized masks** (store at w×h, translate at the storage boundary) | 9× off every mask alloc, clone, scan — compounding with C-2 | Large — touches selection semantics, `io.rs` SELC serialization, overscan selection | **High**: persisted-format + behavior surface; only worth it if selection-heavy workflows measurably bite after #6 |
| 14 ✅ | Gallery: **lazy per-tile thumb decode ✅** (metadata-only page open; per-decode local engine disposed before the decode await; FIFO-bounded cache) + bound `PublishDraft`: **drop `docBytes` eagerly ✅** | Page open no longer materializes every drawing's full document up front; thumbs decoded only for visible tiles; `_thumbs` bounded instead of O(drawings); zero doc retained while the gallery idles | Small | **Low.** Review killed the other #14 ideas (`TransferableTypedData` copies anyway; lazy `mkpxBytes` fights the build-time size gate) and caught that a *shared* temp engine would race on dispose + regress idle retention — fixed with a per-decode local engine. Persistent thumb *files* on disk remain a possible follow-up |

Not recommended: reverting any of the shipped budget machinery, un-quarantining the `image`
crate, or touching the gutter design itself — the 3×3 storage is load-bearing for Move/overscan
and its cost is now quantified rather than alarming.

### Deferred #4 — implementation recipe (for whoever picks it up)

An adversarial review (2026-07-29) established the correct approach and the trap, so #4 is a known
quantity, just not worth its risk today. If revisited:

1. **The correctness argument is affine equivalence, not "storage coords."** For every single-pixel
   `set`/`blend_over` and for `blit_over`, subtracting `off = origin` from the exact value passed to
   the draw call and letting the bounds-check drop out-of-range writes is **byte-identical** to
   today's "draw at storage coord, then `to_rgba_bytes_rect(canvas_rect)`" — because the crop maps
   `s → s − origin` with the same clip window. This holds regardless of the value's coordinate space,
   so the implementer must offset *the value handed to each draw call*, at all ~9 sites
   (`render_shape_preview`, `render_gradient_preview`, `render_paste_preview`, the move-draft wash,
   the Select-Layer overlay, the legacy stroke previews, and `rotate_draft_wash_into` /
   `scale_draft_wash_into` in `canvas.rs`). Pass `off` = `(0,0)` on the overscan path so it is
   provably unchanged.
2. **The one trap: `blit_wrapped` at `session.rs:783`** (legacy wrapped-Move preview). Its internal
   wrap math references `canvas.x = origin.x`, so offsetting only the dest breaks it. The fix is to
   pass BOTH a dest offset by `−off` AND `canvas = IRect::new(0, 0, w, h)`. **No test covers the
   wrapped-Move preview** — add a golden for it before landing, or it ships silently wrong.
3. `render_display`'s own internals (checker/grid/onion/reticle) are already `src`-relative — no
   change needed there.
4. Honest payoff: ~2 fatal-class table allocs/move for sparse content (the common case), larger for
   dense/gutter-heavy or large-canvas docs; and the "4 KiB class" framing is 64-bit-only (arm32
   ships 4-byte pointers → a different, smaller class). #5 already removed the bigger per-move copy,
   which is why deferring #4 costs little.

## Other considerations

- **The workstation hides all of this.** Windows has no per-size-class ceiling and absorbs
  multi-GB transients silently (the memlab lesson, re-confirmed here: the churn findings are
  invisible in local dev). Any churn work should be validated with the existing
  `tools/memlab/run_ladder.ps1` on-device flow, plus a stroke-scripted variant if #4/#5 land.
- **iOS remains unmeasured** (memlab deferral stands). Its libmalloc has no scudo-style class
  wall, so the Android budgets are almost certainly safe there — but peak-doubling during
  export (P-1) is the finding most worth a one-off Instruments look on an older device.
- **The budgets interact**: document 320 + history 96 + export doubling + tables (P-2) is the
  complete wall arithmetic. Today's worst legal sum flirts with ~1 GiB only when P-1 and P-2
  compound; proposals #7 and #10 each independently restore comfortable margin.
- **`weight_of` over-counting is a feature**: nominal 96 MiB history retains ~45–50 MiB real —
  headroom that should be kept in mind before anyone "fixes" the estimator.
- **Doc fixes**: `document.rs:166` says the selection mask is canvas-sized; every writer builds
  it storage-sized — update the comment (or implement #13, which would make it true). And
  `codec/lib.rs`'s module doc advertises sprite-sheet export, but `encode_sprite_sheet` is dead
  code with the worst allocation shape in the file (full sheet + per-frame clone + per-pixel
  copy loop) — rewrite it before ever wiring it up, or drop it.
- **No import/export memlab rung exists.** All import/export multipliers above are derived from
  source; the memlab harness measures gen/load/edit/churn only. Before sizing fixes #3/#10/#11,
  add an import rung and a bomb-file case to `tools/memlab/` so the numbers are observed, not
  inferred.
- **Autosave cadence** is memory-fine as shipped (single-flight, latest-wins, hash-gated
  writes); only the serialize-before-hash ordering wastes work (R-1) — worth fixing as part of
  any large-document push, and note `flushNow()`'s synchronous serialize is load-bearing for
  the `dispose()` ordering; don't async-ify it casually.

## Measurements run for this audit (Windows, release CLI)

```
# 128 frames × 16 blank layers, 256×256 — tables invisible to the budget (P-2)
mkpx run empty_grid_256.txt mem
  → tile_table_bytes 9,437,184 (= 2048 × 4608 B exactly), doc_unique_bytes 0,
    history_table_bytes 0 (COW sharing confirmed)

# 64-frame full-noise 256×256 (16.8 MiB payload) — save/load transient post-M4
mkpx run noise64.txt mem mem.os assert.roundtrip mem.os
  → resident 24.0 MB before; peak 60.2 MB across save+load+verify (≈ +2.2× payload)
```

Scripts regenerable from the recipes above; the memlab harnesses (`tools/memlab/`) remain the
canonical device-side reproduction path.

---

## Addendum — device + import/export measurements (2026-07-29, same day)

The original report flagged that the import/export findings were *source-derived, not
measured*. A Pixel 10 Pro XL (16 GB, Android 16 — the memlab reference device) was connected, so
the crash-capable claims (P-0, P-3) and the peak claims (P-1) were confirmed empirically. New
lab tooling for this (committed, non-shipping): a `mkpx import` CLI subcommand driving the exact
`codec::decode → import_decoded` path the app's `mkpx_import` uses, and `tools/memlab/make_gif.py`
(synthetic full / content-unique-noise / logical-screen-bomb GIFs). Numbers below are measured,
not inferred; where they correct a source-derived figure the prose above has been updated to
match.

### P-0 confirmed — import drives the document 60% past the hard budget, silently

`mkpx import 256 256 <1024-frame noise GIF> --pre <near-256-MiB base doc> --as-layer`:

| | Windows CLI | Pixel 10 Pro XL CLI |
|---|---|---|
| Unique payload after import | **512 MiB** (536,870,912 B) | **512 MiB** (identical) |
| Hard budget | 320 MiB | 320 MiB |
| **`mem_refusals`** | **0** | **0** |
| `mem_soft_exceeded` | true | true |
| Import-time RSS / peak | 639 MB / 911 MB | 927 MB / **1.20 GB** |

The engine sat at **512 MiB unique tile payload — 192 MiB (60%) over the 320 MiB hard cap —
with its refusal counter still at zero**. Every other structural op would have rolled this back;
import is the one edge that doesn't. This is the report's top finding (P-0), now reproduced on
hardware.

**Corollary — the over-budget document cannot be reloaded (a soft brick).** `assert.roundtrip`
on the over-budget session **FAILS on both platforms**: `save_bytes` happily writes a >320 MiB
`.mkpx`, but `load_from_bytes_budgeted` *refuses* any file whose payload exceeds the hard budget
(`io.rs:763`), so the round trip's `content_hash` never matches. A document created by import can
therefore be saved by autosave and then **rejected by its own loader on the next launch** — the
crash-recovery path silently loses the drawing. The save/reload transient itself was also
measured: **1.24 GB peak (Windows) / 1.68 GB peak (Pixel)** for the 512 MiB document. Fixing P-0
(route import through `edit_doc`) closes both the invariant breach and this brick.

### P-3 confirmed — a 24 KB GIF drives unbounded RSS growth

`mkpx import 4096 4096 bomb.gif` (a 24,334-byte file: 4096×4096 logical screen, 1024 one-pixel
sub-frames) on the Pixel, RSS sampled each second under a 6 GiB watchdog:

```
t=1s 1.75 GB → t=2s 3.69 GB → t=3s 4.90 GB → t=4s 5.17 GB
→ t=6s 5.68 GB → t=7s 6.53 GB  ← WATCHDOG KILL (would have continued)
```

Growth was linear and unbounded, exactly as P-3 predicted — the decoder composites each
sub-frame to the full 4096×4096 logical screen (64 MiB/frame), and nothing caps the accumulating
`Vec<DecodedFrame>`. On the 16 GB Pixel this manifests as runaway RSS (I killed it at 6.5 GB to
protect the device); on a typical 4–8 GB phone the system LMK/OOM killer ends it much sooner. Note
this bomb lives in the **256 KiB allocation class, not the fatal ~4 KiB class** — so it is a
whole-process RSS OOM, distinct from the scudo-class SIGABRT wall, confirming the report's
class-attribution reasoning. A running-bytes cap in `decode_animated` (proposal #3) closes it.

### P-1 confirmed — publishing a legal 256 MiB document peaks at 2.45 GiB

In-app export rung (real publish path: `engine.save()` → `Engine.encodeInBackground(webp)`,
release APK, `VmHWM` from `/proc/self/status`):

| Rung (256 MiB document, **under** the 320 MiB budget) | Export ms | Output | **Peak RSS (VmHWM)** |
|---|---|---|---|
| `edit:1024:1+clear+export` | 5,931 | 260 MB WebP | **2.45 GiB** (2,626,129,920 B) |
| `edit:256:4+clear+export` | 5,244 | 64 MB WebP | **2.45 GiB** |

A publish of a document a user can *legally* create (256 MiB, inside budget) peaked at **~2.45 GiB
resident — ~9.6× the document.** This is materially worse than the source-derived "~640 MiB in
the fatal class" estimate: the second engine document in the isolate + three `.mkpx` copies + the
all-frames flatten + the accumulating WebP output overlap into a multi-gigabyte total-RSS peak.
The Pixel's 16 GB absorbed it; a mid-range device would not. P-1's severity is upgraded
accordingly, and proposals #10 (stream the export) + #14 (bound `PublishDraft`) move from
"headroom" to "prevents OOM on smaller devices."

### Legitimate import peak — matches the ~2× source estimate

`mkpx import 256 256 <legal 1024-frame 256² GIF> --mode stretch` (final document 256 MiB):

| | Windows | Pixel |
|---|---|---|
| Import peak RSS | 592 MB | **607 MB** |
| ÷ final document | 2.2× | 2.3× |

The all-frames-up-front decode holds the 256 MiB decoded set alongside the 256 MiB of tiles — the
predicted ~2×. Confirmed, not a crash risk on its own (it's under the wall), but the reason
streaming import (proposal #10's sibling) is worth doing.

### P-2 confirmed identical across platforms

`mkpx run empty_grid_256.txt mem` (128 frames × 16 blank layers): `tile_table_bytes` =
**9,437,184 B on both Windows and the Pixel** (2048 × 4608, byte-identical), with zero budgeted
payload — the tile-slot tables are real, deterministic, and invisible to the budget as described.

### Net effect on the findings

- **P-0** (import bypasses the budget) and its reload-brick corollary: **confirmed on hardware,
  worse than described** (the brick was not called out in the source-only pass). Still proposal
  #1, still the top priority.
- **P-3** (GIF bomb): **confirmed** — a 24 KB file, unbounded growth, killed at 6.5 GB.
- **P-1** (export peak): **confirmed and upgraded** from ~640 MiB estimate to a measured 2.45 GiB
  total peak on a legal document.
- **P-2** (tables) and the legitimate import 2× multiplier: **confirmed, numbers as estimated.**
- The `mem`-probe census, refusal telemetry, and budget arithmetic all read identically on the
  Pixel and the workstation — the engine's memory behavior is genuinely platform-deterministic,
  which is what makes the Windows CLI a valid proxy for everything except the absolute RSS
  ceiling.

### Reproducing the addendum

```powershell
# Windows
cargo build -p makapix-cli --release
python tools/memlab/make_gif.py noise 256 256 1024 noise1024.gif
# base1024.txt = FillNoise(1) + 1023×(AddFrame();FillNoise(n))
./target/release/mkpx import 256 256 noise1024.gif --pre base1024.txt --as-layer --mode stretch state mem.os assert.roundtrip mem.os

# Device (headless)
cargo ndk -t arm64-v8a build -p makapix-cli --release
adb push target/aarch64-linux-android/release/mkpx *.gif base1024.txt /data/local/tmp/mkpx-audit/
adb shell /data/local/tmp/mkpx-audit/mkpx import 256 256 noise1024.gif --pre base1024.txt --as-layer --mode stretch state mem.os
python tools/memlab/make_gif.py bomb 4096 4096 1024 bomb.gif   # then import under an RSS watchdog

# Device (in-app publish peak) — the +export rung added to lib/dev/memlab.dart
./build_android.ps1 -Install
adb shell am start -n club.makapix.app/.MainActivity -e memlab "edit:1024:1+clear+export"
adb shell run-as club.makapix.app cat files/memlab.json    # vmhwm = peak
```
