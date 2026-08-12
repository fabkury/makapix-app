# Makapix Editor — Battery Discipline Assessment

**Date:** 2026-08-12 · **Status:** assessment only — nothing implemented, no code changed.
**Scope:** the editor pillar plus everything that stays alive alongside it during an editing
session (SSE, Club providers, pollers). Android-first; iOS divergences called out where they
matter. Windows is out of scope (wall power).
**Method:** static code study (four parallel deep reads: rendering pipeline, timers/persistence,
FFI seam + engine costs, Club-side machinery). All magnitudes below are **engineering estimates
from code reading** — the measurement plan in §7 exists to confirm or demote them before any
refactor is committed.

---

## 1. Executive summary

The editor's battery story is a classic incremental-growth profile: the *disciplined* parts are
genuinely disciplined (single-pillar mounting, image disposal on every path, an activity-gated
autosave, the Club feed's exemplary `SyncFrameClock`), while a handful of hot loops that grew
one feature at a time never acquired frame-rate or lifecycle discipline. Five findings dominate;
everything else is a long tail.

| # | Finding | When it burns | Est. severity |
|---|---------|--------------|----------|
| 1 | Marching-ants/precision-cursor loop repaints **essentially the whole page at 60 Hz**, indefinitely, on an *idle* canvas | Any time a selection exists or a precision tool is active | **Very high** — dominates idle time |
| 2 | Playback preview: vsync `Ticker` forces **full-refresh-rate frame production + per-tick FFI** regardless of animation fps (×2 on 120 Hz) | Whole playback preview | **High** |
| 3 | Stroke pipeline runs the **full composite→premultiply→decode→GPU-upload chain once per raw pointer event**, uncoalesced, with several per-tool amplifiers | While drawing | **High** (bursty) |
| 4 | Radio never rests: 15 s player poll (pillar-blind, likely re-handshaking TLS), SSE keepalives every ~15 s + ~5 min reconnects, 60 s unread poll — on uncorrelated schedules | Whole session; polls continue **backgrounded** | **Medium-high** (high on cellular) |
| 5 | Replay viewer: 30 Hz engine-replay + decode + full-page `setState` loop with **zero lifecycle gating** — keeps running backgrounded | Replay page open | **High while open**; bug-grade when backgrounded |

The cheapest big wins (§5) are small and low-risk: two `RepaintBoundary`s plus a ~6 Hz ants
clock kill finding 1; per-frame redraw coalescing kills most of finding 3; a lifecycle observer
on the replay page and pillar/lifecycle gates on the pollers kill 5 and most of 4. The larger
refactorings worth doing (§6) are a central redraw scheduler, engine-side dirty/hash
bookkeeping, and a demand-driven playback clock; texture-based presentation is examined and
**not** recommended.

---

## 2. Scope and method

Battery drain while editing = **screen + SoC (CPU/GPU) + radio + storage**. The screen is fixed
cost (no dark-mode/OLED work is proposed here). This assessment therefore focuses on:

- how many frames per second the app *produces* (SoC+GPU) and how expensive each is;
- how much CPU each user interaction triggers, and whether any of it is redundant;
- how often the radio is woken and by what;
- disk sync frequency;
- what keeps running when the user is idle, or the app is backgrounded.

Findings are cross-corroborated: every Tier-1 item below was found independently by at least
two of the four code reads.

### Platform context

- **Impeller is fully disabled on Android** (`app/android/app/src/main/AndroidManifest.xml:47-49`)
  as the PowerVR fixed-rate-compression stopgap — the app rasters via Skia/GLES. This
  forecloses the (usually more power-efficient) Vulkan path on modern devices. Not actionable
  until the pinned Flutter carries flutter/flutter#187586, but it should be **re-measured** when
  that lands (§7).
- **No wakelocks anywhere** (verified across Dart/Kotlin/Swift/manifests) — nothing holds the
  CPU or screen awake. Good for battery; note the flip side that long timelapse exports can be
  interrupted by screen sleep (a product question, not a battery one).
- Haptics are negligible (two `selectionClick`s on discrete gestures).

---

## 3. What is already good

Credit where due — these patterns are the house style to extend, not rework:

- **Single-pillar mounting** (`app/lib/shell/app_shell.dart:82`): the Club subtree is fully
  unmounted while editing, so every `autoDispose` Club provider is released and no Club widget
  ticks. The editor likewise fully unmounts on switch-out.
- **`SyncFrameClock`** (`app/lib/club/state/animation_clock.dart:46-69`): one shared ticker,
  gated on *registrants > 0 AND foreground*. This is the reference implementation the editor's
  own tickers should copy.
- **Playback decode gating** (`editor_page.engine.dart:867-869`): composite+decode fires only on
  animation-frame *change* — decode count equals animation fps, not display fps. The waste in
  playback is elsewhere (§4.2).
- **Playback auto-pause on background** (`editor_page.dart:527-544`) and on menu/sheet open.
- **`ui.Image` lifecycle hygiene**: disposal handled on every publish path
  (`editor_page.engine.dart:254-288`).
- **Autosave activity gate + content-hash short-circuit** (`persistence/autosave_controller.dart:68-79`):
  idle cycles are near-free.
- **Canvas checkerboard** built once into a `static final` `ImageShader` paint
  (`widgets/painters.dart:26-41`) — one `drawRect` regardless of zoom/pan.
- **Undo is cheap**: `begin_edit` is an Arc bump; `commit_edit` diffs tile tables by pointer
  (`crates/engine/src/session.rs:1078-1125`, `buffer.rs:371-396`). History is not a battery
  problem.
- **Marching ants are already *conditionally* run** (`editor_page.dart:475-483`) — the old
  always-on loop from the memory audit was fixed. The remaining problem is *how much* each tick
  costs and *how often* it ticks, not whether it runs at all.

---

## 4. Drain sources, ranked

Severity is per typical editing session on a phone. "Est. cost" is an order-of-magnitude power
guess to be validated in §7 — treat rankings as hypotheses with strong code evidence.

### Tier 1 — sustained, structural

#### 4.1 The 60 Hz ants/cursor loop repaints the whole page while the editor is idle

**Mechanism.** `_antCtrl` (`editor_page.dart:454`, `.repeat()` at `:475-483`) runs at vsync
whenever `_outlineEdges.isNotEmpty || _isCursorTool || (selection draft)`. Three painters take
it as `repaint: anim` and declare `shouldRepaint => true` (`widgets/painters.dart:98,133,170`).
Two compounding problems:

1. **The animation has ~5.7 Hz of visual content but ticks at 60 Hz.** `OutlinePainter` derives
   `phase = (anim.value * 4).floor()` (`painters.dart:73`) — 4 distinct states per 700 ms
   period. ≈90 % of repaints produce byte-identical pixels.
2. **Each tick repaints far more than the ants.** There is exactly **one** `RepaintBoundary` in
   the whole app (`editor_page.canvas.dart:213`, around the canvas image only). The overlay
   painters are not boundaries, so their `markNeedsPaint` walks up to the *route's* boundary:
   every non-boundary widget on the page is re-recorded and the page layer re-rasterized —
   grid painter (fresh `List<Offset>` of up to ~1 000 points per call, `painters.dart:606-624`),
   dividers, tooltip band, pinned Undo/Redo tiles including their `Opacity(0.4)` → implicit
   `saveLayer` per disabled tile (`toolgrid.dart:36`), etc. Only the scrollables and the canvas
   image survive via their own layers.

**When.** A committed selection, or simply having a precision-mode tool active, keeps this
running **indefinitely with zero input**. Idle time dominates real editing sessions (thinking,
looking), so this is likely the single largest real-world drain: it converts an idle editor
into a sustained ~60 fps game. On a 120 Hz panel the controller ticks at 120 Hz.

**Est. cost.** Sustained frame production on a phone ≈ several hundred mW to ~1 W above true
idle (SoC + GPU + no panel self-refresh). Continuous for minutes at a time.

#### 4.2 Playback preview: vsync ticker + per-tick FFI regardless of animation fps

**Mechanism.** `_onPlayTick` (`editor_page.engine.dart:856-871`) is correct about decode gating
but the ticker itself has three costs on every vsync, even for a 2 fps animation:

1. **An active `Ticker` forces Flutter to produce a frame every vsync** — full
   `drawFrame` → scene submission → GPU composition, 60–120×/s, ~58 of which change nothing.
2. **Per-tick FFI + allocations**: `'AdvanceClock($ms)'` string build → `_send` →
   `JournalRecorder.record` does `split('\n').where().toList()` *before* discarding the line as
   a filtered playback verb (`replay/journal_recorder.dart:215,231-234`) → `utf8` encode +
   `malloc` + copy + `mkpx_run` parse.
3. **`engine.playFrame` is O(frameCount), polled 2-3× per tick.** The comment at
   `editor_page.engine.dart:866` says "cheap scalar FFI", but `current_play_frame`
   (`crates/engine/src/session.rs:1004-1029`) sums all frame durations then linearly scans —
   twice — per call. A 1024-frame doc ≈ ~180 k iterations/s at 60 Hz; double at 120 Hz.

**When.** Any time the user previews their animation — a core, extended activity.

**Est. cost.** Comparable to §4.1 while active (same sustained frame production) plus CPU.
ProMotion iPhones and 120 Hz Androids pay double; there is no refresh-rate cap anywhere.

#### 4.3 The stroke pipeline: one full render chain per raw pointer event

**Mechanism.** `_continueDraw` (`editor_page.canvas.dart:400-493`) runs per pointer event with
**no coalescing to vsync and no same-cell dedupe** on the paint path (paste/move/precision
paths *do* guard on whole-pixel deltas; freehand paint does not — `canvas.dart:480-492`):

`_send(PointerMove)` [journal record + malloc + FFI + parse] → optional `outlineMask` fetch →
**full `mkpx_display`** → **Dart-loop premultiply over every byte**
(`engine_ffi.dart:16-30`) → **`decodeImageFromPixels`** (new GPU texture per event) → overlay
bump.

On a 120–240 Hz digitizer against a 60 Hz display that is **2–4 full chains per displayed
frame**, the surplus decoded images discarded by the `_imageGen` staleness stamp
(`editor_page.engine.dart:261-265`) — after the engine and decode work was already paid. At
zoom > 1, multiple events land in the same canvas cell and still pay everything for zero visual
change.

**Engine-side amplifiers** (all per pointer event where applicable):

- **No composite caching, no dirty rects** — every `mkpx_display` re-blends every visible layer
  from scratch (`crates/engine/src/render.rs:40-126`). 256²×64 layers ≈ 4.2 M pixel composites
  per call; non-Normal blend modes cost ~an order of magnitude more per pixel
  (`color.rs:111-125`).
- **Overscan renders 9× the area**: display is storage-sized (3W×3H), then cropped and
  gutter-dimmed — 589 824 iterations of dim pass on a 256² doc
  (`session.rs:563-617`, flagged in-code at `:590-592`).
- **Onion skin triples the composite** (two extra full `composite_frame`s, `render.rs:149-156`).
- **Selection tools / Move**: `outline_mask` per event = deep 72 KiB mask clone + up to 3
  storage-sized mask allocs + a per-pixel byte write pass + Dart-side `Uint8List.fromList`
  copy + O(w·h) scan allocating a small `List` per boundary segment
  (`session.rs:820-888`, `editor_page.engine.dart:99-121`). The Dart wrapper mallocs the full
  mask buffer even when there is **no selection** (`engine_ffi.dart:477-485`).
- **Rotate/Resize handle drags**: 3 full cleanEdge resamples per lifted layer per event
  (preview + wash + outline each call `rotate_resample`; ~21 source taps per destination pixel
  — `session/canvas.rs:531-589`, `cleanedge.rs:321-365`).
- **HSV / Brightness-Contrast sliders**: each tick calls **full** `_redraw()` (setState +
  outline refetch) and the preview builders iterate **full 768×768 storage per layer** with no
  tile skipping (`controls.dart:492,513`; `session.rs:2350-2483`; `tool.rs:530-565`). Frame
  scope × 64 layers ≈ 37.7 M `get()` calls per slider tick — the heaviest per-event path found.
  Levels already does it right (`_redraw(full:false)` + settling redraw on release,
  `controls.dart:537,572`); HSV/BC predate that pattern.
- **Eyedropper**: full-page `setState` per move on color change (`editor_page.engine.dart:412-415`),
  which re-pays §4.6's per-tile hashes.

**When.** Bursty — only while the finger moves — but drawing *is* the product. Sustained
stroking at 240 Hz digitizer rates can exceed a full core on big documents (jank + heat + drain).

**Est. cost.** High while stroking; scales with layer count, blend modes, overscan, canvas size.

### Tier 2 — sustained, session-long

#### 4.4 The radio never rests (and inverts when backgrounded)

Three independent, unaligned schedules run for the whole editing session:

- **`PlayerController` polls `GET /players` every 15 s, forever** —
  (`app/lib/club/state/player_providers.dart:155-158`), non-autoDispose by design ("kept warm
  for the app lifetime"), no pillar check, no lifecycle check, polls even for users with zero
  registered players. Worse: `dart:io`'s default `HttpClient.idleTimeout` is 15 s and is never
  raised, so a 15 s poll sits exactly on the connection-reap boundary — many polls likely pay a
  **fresh TCP+TLS handshake**. Highest recurring radio cost in the app, lowest value while
  drawing.
- **SSE stream** (`notifications_sse.dart`): stays connected while editing (by design — badge
  updates), with server keepalive comments ~every 15 s and a full reconnect + TLS handshake
  every ~5 min (server-side ~300 s lifetime). Client-side there is **no jitter and no rate
  limit on the `timeout`-close reconnect path** (`:96-98`; `_attempts` resets on every
  successful connect at `:71`) — a greet-then-close server produces an unbounded hot loop. On
  the *error* path it gives up after 5 attempts and never retries until foregrounding — at
  which point the 60 s poll becomes the live path.
- **Unread-count poll every 60 s** (`notifications_providers.dart:21-24`) — skipped while SSE is
  up, but with **no lifecycle gate**.

**The background inversion:** on `paused`, SSE tears down correctly — which flips
`notificationsSseProvider` to false — so the 60 s poll *starts actually hitting the network*,
and the 15 s player poll never stopped. A backgrounded app makes **~5 HTTP requests/minute**
until Android freezes the process (increasingly quickly on 14/15; iOS suspends in seconds, so
this is mostly an Android cost). The passive stream is replaced by active polling — exactly
inverted from what battery wants.

**Est. cost.** On Wi-Fi: modest (tens of mW average). On cellular: each radio wake costs
~1-3 s of elevated radio power; at 4-5 wakes/min this can rival the rendering findings.
Session-long, so the integral is large.

#### 4.5 Replay viewer: a 30 Hz engine loop with no lifecycle gating

`ReplayPage._sweep` (`replay/replay_page.dart:100-113`): `Timer.periodic(33 ms)` →
`host.seek()` (journal DSL through a **second full `Engine`**, with checkpoint restores) →
`compositeFrame` → premultiply → `decodeImageFromPixels` → full-page `setState`. Autoplays on
open. The file has **no `WidgetsBindingObserver`** — backgrounding the app leaves the whole
30 Hz replay+decode loop running until the process is frozen. Heavy while open (by design — it
is a video scrubber), bug-grade when backgrounded.

### Tier 3 — episodic, amplification, and carried-over work

#### 4.6 setState amplification × uncached content hashes

Every full-tree rebuild re-runs `engine.frameHash(i)` / `engine.layerHash(f,i)` **inside the
`itemBuilder`s** for every visible film-roll and layer tile (`editor_page.timeline.dart:57,431`).
These are not memoized anywhere: each call streams **every byte of every resident tile** through
a byte-at-a-time two-lane FNV (`buffer.rs:270-287`, `util.rs:46-54`) — up to ~16.8 MB hashed
per `frameHash` on a full 256²×64 doc, order 10-20 ms, synchronous on the UI thread.

Rebuild triggers that pay this: every `_act` (which does `_redraw()` **plus** a second
`setState` — a double rebuild, `editor_page.engine.dart:436-441`, pattern repeated at ~8 call
sites), every eyedropper move that changes color, every HSV/BC slider tick, and **every
thumbnail-generation completion** (`timeline.dart:31,388` each `setState` → rebuild → re-hash →
possibly more thumb regens — an N×M amplification after any global operation). The
`full: false` redraw path exists precisely to dodge this (comments at `canvas.dart:489-491`)
— but the dodge is per-call-site opt-in, and several sites don't.

Related: `_refreshState` (`editor_page.engine.dart:328-403`) serializes the **whole document
state to JSON** in Rust and `json.decode`s it in Dart after every action/stroke — including
`memory_bytes()` + `present_tiles()` walks over all frames×layers and a per-tile `HashSet`
insert (`probe.rs:52-158`, `session.rs:920-1002`). Fine per action; expensive because §4.3's
amplifiers invoke action-grade paths per event.

#### 4.7 Autosave and flush pattern

- The 5 s `Timer.periodic` never stops — idle cycles are cheap no-ops but the isolate wakes
  12×/min for the editor's whole lifetime, **including backgrounded** (never cancelled on
  lifecycle, `autosave_controller.dart:62`).
- Active cycles do: full `engine.save()` (plain, uncompressed, non-incremental — includes a
  full-document content hash + per-tile hashing + CRC32 in Rust, `io.rs:486-641`) + a **Dart**
  byte-loop FNV over the whole output (`autosave_controller.dart:140-147`) + **≈3 fsyncs** and
  ~10 syscalls (doc tmp-write-rename + meta + journal `preWrite` fsync,
  `drawing_store.dart:43-67`, `journal_recorder.dart:292-319`).
- **`flushNow()` has no change check** (`autosave_controller.dart:85-92`) and is called on
  **every `inactive`/`paused`/`hidden` transition** (`editor_page.dart:539-543`). Android walks
  `resumed→inactive→hidden→paused` on a single backgrounding → up to **three full synchronous
  serializes + Dart FNV loops** per app-switch; `inactive` also fires on notification-shade
  pulls and permission dialogs. `_pause()` on the same transition also runs a full `_redraw()`
  composite+decode *while going to background* (`editor_page.engine.dart:886-891`).

#### 4.8 Gallery thumbnails: full document load per tile, no persisted cache

Each gallery tile synchronously reads the whole `.mkpx` from disk, constructs an `Engine`,
loads/materializes the full document, renders a 220 px thumb, disposes
(`gallery/drawing_library_grid.dart:89-130`) — on the UI isolate, per tile, every gallery open
(in-memory FIFO of 60, dropped on page dispose). `DrawingStore.writeThumb`/`thumbFile`
(`drawing_store.dart:70-79`) exist but have **no production caller** — the documented
`thumb.png` slot is never written. Episodic, but a heavy CPU+I/O burst every visit.

#### 4.9 Club work carried into (and past) the editor

- **Un-cancellable prefetch**: `precacheArtworks` fires per feed page, unawaited, no cancel
  token (`artwork_cache.dart:33-38`) — scroll a feed, tap Contribute, and a page of downloads
  completes inside the editor.
- **Un-cancellable decodes**: by documented design, an in-flight animation decode continues
  (network + serialized codec walk on the UI isolate) after its tile is gone
  (`animation_decoder.dart:51-52,101-123`).
- **96 MiB decoded-frame cache retained across the pillar switch** (`frame_cache.dart:9,98`)
  with **no `didHaveMemoryPressure` handler anywhere in `app/lib`** — alongside the editor's
  engine document this raises memory pressure (GC/LMK churn = indirect battery, and directly
  risky against the Android ~1 GiB scudo wall documented in `docs/memlab/REPORT.md`).
- Minor FFI chatter: ~11 scalar crossings per redraw + ~4 per `_toCanvas` for values already
  cached Dart-side (`editor_page.engine.dart:775-799`); `_pushToolSettings` sends 10 separate
  DSL lines per tool switch (`engine.dart:534-545`).

---

## 5. Targeted fixes (small, low-risk, high value) — Q2

Ordered by expected battery return per unit of risk. None changes engine output bytes; none
touches the FFI contract except where noted.

| # | Fix | Addresses | Effort | Risk |
|---|-----|-----------|--------|------|
| F1 | `RepaintBoundary` around the overlay `Stack` (`editor_page.canvas.dart:229`) and around `GridPainter` | §4.1 | Trivial | Low |
| F2 | Drive ants at content rate: fire a repaint notifier only when `phase` (already computed) changes — ~5.7 Hz instead of 60/120 Hz; fix the three `shouldRepaint => true` painters to compare phase/fields | §4.1 | Small | Low |
| F3 | Coalesce redraws to ≤1 per frame during drags: per-event work = send DSL + mark dirty; one scheduled callback performs outline fetch + display + decode | §4.3 | Small-medium | Medium (ordering; see R1 which subsumes it) |
| F4 | Same-cell dedupe on the freehand paint path (`if (cx!=lastCx || cy!=lastCy)` guard, matching the paste/move/precision paths) | §4.3 | Trivial | Low |
| F5 | HSV/BC sliders → `_redraw(full:false, …)` + settling full redraw on release, copying Levels (`controls.dart:537,572`) | §4.3, §4.6 | Trivial | Low |
| F6 | Bound the adjustment previews: tile-skip / bbox `map_region`/`hsv_shift_region` instead of full-storage walks | §4.3 | Small (engine) | Low-medium (golden-verify) |
| F7 | `ReplayPage`: add `WidgetsBindingObserver` → pause sweep on background; consider pausing when the route is obscured | §4.5 | Trivial | Low |
| F8 | Pillar- and lifecycle-gate the player poll (pause while editor active or backgrounded; refresh once on pillar return — the bar still "reappears instantly"); raise `HttpClient.idleTimeout` above the poll period or send `Connection: keep-alive`-friendly cadence | §4.4 | Small | Low |
| F9 | Lifecycle-gate the 60 s unread poll (no polling while backgrounded) | §4.4 | Trivial | Low |
| F10 | SSE `timeout`-reconnect: add jitter + a minimum-interval rate limit; don't reset `_attempts` until the stream has stayed up for N seconds | §4.4 | Small | Low |
| F11 | `flushNow()`: reuse `_runCycle`'s hash short-circuit; debounce the lifecycle trigger (flush at most once per transition burst; skip `inactive`-only blips) | §4.7 | Small | Low (keep the dispose-path unconditional write) |
| F12 | Cancel/pause the autosave timer on background; rearm on resume (or switch to a rearm-on-`markActivity` one-shot, which also ends the idle 5 s wakeups) | §4.7 | Small | Low |
| F13 | Skip the `outlineMask` malloc/copy when no selection exists (scalar `hasSelection` check first, or a count-returning variant) | §4.3 | Trivial | Low |
| F14 | Journal: check `_isPlaybackVerb` *before* the `split/where/toList` allocations; skip the `AdvanceClock` string+FFI when `ms == 0` | §4.2 | Trivial | Low |
| F15 | Cache `current_play_frame`: precompute cumulative durations on play start (invalidate on timing edits) → O(log n) or O(1) per poll | §4.2 | Small (engine) | Low |
| F16 | Kill the double rebuilds: `_act` and friends should rely on `_redraw`'s own `setState` (audit the ~8 double-`setState` sites) | §4.6 | Small | Low |
| F17 | Wire up the existing `writeThumb`/`thumbFile` as a persisted gallery thumbnail cache (invalidate by doc mtime/hash) | §4.8 | Small | Low |
| F18 | Cancel tokens for feed prefetch on pillar switch; drain/abandon queued decodes when the Club pillar unmounts | §4.9 | Small | Low |
| F19 | On editor pillar switch-in (or `didHaveMemoryPressure`): trim the 96 MiB frame cache | §4.9 | Small | Low |
| F20 | Cache scalar FFI getters (`displayWidth/Height`, `width/height`) in `_refreshState` and use the cached values in `_redraw`/`_toCanvas` | §4.9 | Trivial | Low |

Also worth a server-side conversation (out of this repo): lengthen the SSE keepalive comment
interval (15 s → 45-60 s) and the stream lifetime (300 s → 15-30 min) — the client can't fix
those from its side, and together they set the floor on radio rest while editing.

**Expected combined effect of F1+F2 alone:** the idle-with-selection editor drops from
sustained 60-120 fps full-page rasterization to ~6 fps of a small overlay layer — this is the
single largest lever in the whole assessment, for roughly a dozen lines of diff.

---

## 6. Larger refactorings — Q3

### R1. Central redraw scheduler ("one frame, one fetch") — **recommended**

**What.** Replace the ~20 scattered `_redraw`/`setState` call sites with a dirty-flag model:
interactions mark `needsDisplay` / `needsOutline` / `needsStateRefresh` / `needsChrome`; a
single per-frame scheduler (post-frame or scheduled-frame callback) performs at most one
engine fetch + premultiply + decode + publish per vsync, and nothing when clean. Subsumes F3,
F4 (naturally — same cell ⇒ nothing marked), F5, F16, and the eyedropper amplifier; the
`_imageGen` staleness stamp mostly dissolves (one in-flight decode at a time by construction).

**Pros.** Fixes the whole class instead of per-call-site opt-ins (the codebase already shows
the opt-in approach decaying: `full:false` exists but isn't used everywhere). Makes battery
discipline structural; new tools inherit it. Caps stroke-time cost at display rate regardless
of digitizer rate. Reduces jank on big documents (less discarded work).

**Cons / risks.** Touches the editor's hottest paths (`editor_page.engine.dart` +
`canvas` part file); subtle ordering regressions possible (e.g., outline must reflect the
*last* pointer event of the frame; replay/journal ordering must not change — journal records at
`_send` time, which is unaffected). One-frame latency for chrome updates (imperceptible).
Needs a device pass on stroke feel (the *engine* still receives every pointer event — input
fidelity is unchanged; only presentation coalesces).

**Cost.** Days, not weeks. Test surface: existing Dart tests + manual stroke/tool pass.

### R2. Engine-side dirty/hash bookkeeping — **recommended**

**What.** Maintain memoized `content_hash` per layer/frame with dirty flags set by the edit
paths (all mutations already funnel through `Session`), plus a monotonically increasing
document **revision counter** exposed over FFI. Then: `frameHash`/`layerHash` become O(1) when
clean (fixes §4.6); autosave's change detection becomes "revision changed?" — skipping the
full serialize *and* both hash passes when clean (fixes most of §4.7); thumbnail invalidation
gets exact and cheap; `flushNow()` gets its change check for free (F11).

**Pros.** Removes the largest hidden CPU multiplier in the UI (per-tile hashing in
`itemBuilder`). Enables cheap correctness everywhere ("did anything change?" becomes free).
No FFI-shape change — same functions, cached results, plus one new scalar getter.

**Cons / risks.** Invalidation bugs are the classic failure mode — a missed dirty-mark makes a
stale thumbnail or a skipped autosave (data-loss adjacent, so autosave should keep a
belt-and-suspenders periodic unconditional save, e.g. hourly). Must be conservative:
over-invalidation is always safe. Hash *values* must not change (only when they're computed) —
goldens and `assert.roundtrip` cover this. Undo/redo/load must dirty correctly.

**Cost.** Days. The engine's layering makes this clean: dirty flags live beside the tile tables
that already do COW pointer-diffing.

### R3. Demand-driven playback clock — **recommended, with care**

**What.** For animations whose next frame change is further away than ~2 display frames,
replace the continuous `Ticker` with a one-shot timer scheduled to the next frame boundary
(same wall-clock µs-carry math in `PlaybackClock`); re-enter ticker mode for fast content
(≥~30 fps) where vsync alignment matters. Zero frame production between animation frames.

**Pros.** A 2 fps animation costs 2 wakeups+frames/s instead of 60-120 — the full §4.2 win,
including on ProMotion. Also fixes the 120 Hz doubling without any refresh-rate capping.

**Cons / risks.** This deliberately revisits the *just-shipped* vsync playback feature
(87295c9), whose point was wall-clock accuracy up to 60 fps — the hybrid must provably keep
that accuracy (the µs-carry logic is reusable as-is; timer jitter is absorbed by clamping to
the next vsync via a scheduled frame). Also interacts with the TEMPORARY `_sendSeq`
edits-during-playback guard — coordinate with the planned removal. Needs the same
blinker-aliasing regression checks the vsync work introduced.

**Cost.** 1-2 days + the existing playback verification playbook. **Do it after F14/F15**, and
only if measurement (§7) confirms playback is a top-3 real-world drain — the targeted fixes may
already take it below the noise floor for typical short previews.

### R4. Composite caching / dirty rects in the engine — **worth designing, second wave**

**What.** Cache the last composited frame; edits invalidate dirty tiles (the COW tile tables
already know exactly what changed — `diff_from` proves it); `display_bytes` re-blends only
dirty tiles into the cached composite. Optionally return a dirty rect over FFI so Dart can skip
premultiply/upload of unchanged regions (full skip requires R5's presentation change; without
it, the byte-out/premultiply/decode still runs full-size — the win is confined to the blend
cost, which §4.3 shows is the dominant engine cost on layer-heavy docs).

**Pros.** Turns per-stroke engine cost from O(canvas×layers) to O(brush footprint×layers).
Biggest CPU lever for large multi-layer documents; also helps thumbnails (`frame_thumb` does a
full composite for a 64 px output today).

**Cons / risks.** Cache invalidation across 60+ DSL verbs (selection previews, tool washes,
onion, overscan gutter dimming all draw *over* the composite — the preview/wash layer must stay
outside the cache or invalidate per-event, which is exactly the per-event cost being removed —
design needed). Determinism is non-negotiable: the cached path must be byte-identical to the
recompute path (goldens + a debug both-paths-compare mode). Memory: +1 storage-sized buffer per
open frame (fine within budgets, but account against the 1 GiB wall).

**Cost.** A week+ including verification. Prerequisite thinking: do R1 first — coalescing
alone may reduce composite frequency enough (display-rate, not digitizer-rate) that per-frame
full composites are acceptable except on 64-layer docs.

### R5. Texture-based canvas presentation (external texture / `Texture` widget) — **not recommended now**

**What.** Replace decode-per-update `ui.Image` churn with a persistent GPU texture updated in
place via platform code.

**Why not.** The buffers are small (≤256 KiB canvas, 2.25 MB worst-case overscan) — upload cost
is real but not dominant once R1 caps it at display rate. The price is per-platform native code
on Android/iOS/Windows, divergent Skia-vs-Impeller interop (while the app is *temporarily*
Skia-only — a moving target), and a breach of the "pure Dart shell over a strings-and-bytes
C ABI" simplicity that the repo explicitly protects. Revisit only if measurement shows GPU
upload/decode dominating after R1+R4, or if canvas sizes ever grow past 256².

### R6. A "radio discipline" layer — **recommended**

**What.** One app-level service owning lifecycle + pillar awareness, which all periodic network
consumers register with: the player poll, unread poll, and SSE supervision get a single policy
(foreground-only, pillar-aware cadences, aligned/coalesced wake schedule, jittered backoff).
Essentially: promote `SyncFrameClock`'s registrant+foreground pattern to the network domain.

**Pros.** Fixes §4.4 structurally, including the background inversion, and gives every future
feature (C5/C6 will add more real-time) a place to plug in instead of a new bespoke timer.
Small, pure-Dart, testable.

**Cons / risks.** Low. Careful sequencing with SSE reconnect semantics; keep the
account-switch teardown behavior identical.

**Cost.** 1-2 days.

### Sequencing recommendation

1. **Measure baseline** (§7, one session).
2. **F1+F2** (ants), **F7** (replay lifecycle), **F8/F9** (pollers) — the trivial tier, ship in
   one patch, re-measure.
3. **R1** (redraw scheduler), absorbing F3-F5, F16; re-measure strokes.
4. **R2** (dirty/hash bookkeeping) + F11/F12 autosave changes; **R6** radio layer + F10.
5. **F14/F15**, then decide **R3** on playback numbers.
6. **R4** only if layer-heavy-document strokes still measure hot.

---

## 7. Measurement and validation plan

Precedent: the memlab work (`docs/memlab/REPORT.md`) measured before designing. Same doctrine.

**Scenarios** (10 min each, screen at fixed brightness, same document — suggest a 128²,
8-layer, 12-frame doc, plus a 256²/64-layer stress doc):

| S | Scenario | Isolates |
|---|----------|----------|
| A | Editor idle, no selection, non-precision tool | true baseline |
| B | Editor idle, committed selection (or precision tool) | §4.1 (B−A = ants cost) |
| C | Scripted stroke loop (repeatable gesture, e.g. adb `input swipe` loop or a replay) | §4.3 |
| D | Playback preview, 2 fps animation / 30 fps animation | §4.2 |
| E | Replay viewer sweeping | §4.5 |
| F | Scenario A in airplane mode vs normal (Wi-Fi vs cellular) | §4.4 (radio share) |
| G | App backgrounded 10 min after editing | background inversion, §4.4/4.7 |

**Instruments (Android, in order of effort):**

1. **In-app debug counters** (cheapest, most direct for verifying fixes): frames produced
   (`addPersistentFrameCallback` count/s), `display()` calls/s, `decodeImageFromPixels`/s, FFI
   crossings/s, journal/autosave flushes, HTTP requests. A debug overlay or periodic log line.
   These turn every fix into a before/after number without lab gear.
2. **Perfetto** (`adb shell perfetto` with sched + gfx + power categories): CPU time by
   thread (UI vs raster), frame production rate, wakeups, CPU frequency residency.
3. **Battery Historian** (`adb bugreport` after `dumpsys batterystats --reset`): per-uid power
   estimate, `mobile_radio_active` spans (directly shows the poll/SSE radio duty cycle),
   partial wakelock check (should stay empty).
4. **Pixel ODPM power rails** (user's test device is a Pixel): `dumpsys android.hardware.power.stats`
   before/after each scenario gives per-rail (CPU/GPU/display/modem) energy — the gold
   standard here, no external meter needed.
5. **Network**: `dumpsys netstats detail` per-uid bytes/packets; or a one-session mitmproxy
   count of requests during scenario A.

**iOS spot-checks:** Xcode Energy gauge + MetricKit `MXMetricPayload` (CPU time,
display-average-pixel-luminance is irrelevant, but cumulative CPU and GPU time per session are
reported). Priority: scenario B and D on a ProMotion device (120 Hz doubling).

**Acceptance targets (proposed):**

- Scenario B within ~10 % of scenario A's power after F1+F2 (today's B is expected to be a
  multiple of A).
- Scenario C: `display()` calls/s ≤ display refresh rate after R1 (today: digitizer rate).
- Scenario D (2 fps): frames produced ≤ ~6/s after R3 (today: 60-120/s).
- Scenario A: zero HTTP requests attributable to players/notifications in a 10-min window
  after F8/F9 (today: ~40+ player polls).
- Scenario G: zero network requests and zero timer wakeups from the app after F7/F9/F12.

**Regression guards:** the engine's byte-determinism gates (goldens, `assert.roundtrip`,
`mkpx` exit codes) must pass unchanged for every engine-side item (F6, F15, R2, R4). None of
the proposed work may alter composite output bytes.

---

## Appendix A — Timer/ticker inventory (editor pillar + cross-cutting)

| Site | Kind | Interval | Idle? | Backgrounded? |
|------|------|----------|-------|---------------|
| `editor_page.dart:454` `_antCtrl` | AnimationController.repeat | vsync | **runs** (selection/precision) | framework-muted only |
| `editor_page.engine.dart:880` `_playTicker` | Ticker | vsync | stopped | auto-paused ✔ |
| `persistence/autosave_controller.dart:62` | Timer.periodic | 5 s | no-op cycles | **keeps firing** |
| `replay/replay_page.dart:100` | Timer.periodic | 33 ms | n/a (autoplays) | **keeps running** |
| `dialogs/crop_dialog.dart:163` | Ticker | vsync | only while playing | framework-muted only |
| `share/image_share.dart:198` | Timer.periodic | 100 ms | dialog-scoped | dialog-scoped |
| `club/state/player_providers.dart:157` | Timer.periodic | **15 s HTTP** | **runs** | **keeps polling** |
| `club/state/notifications_providers.dart:21` | Timer.periodic | **60 s HTTP** | skipped while SSE up | **actually polls** (SSE down) |
| `club/state/animation_clock.dart:52` | Ticker (shared) | vsync | gated ✔ | gated ✔ (reference impl.) |
| `club/state/notifications_sse.dart` | stream + reconnect | ~15 s keepalive / ~5 min recycle | connected | torn down ✔ |

## Appendix B — Per-pointer-event cost sheet (freehand paint, worst case 256²/64-layer, overscan, non-Normal blends)

1. Journal record (string split/alloc) + `malloc`+copy+`mkpx_run`+parse.
2. Full re-composite: ~4.2 M pixel blends ×3 with onion; 9× area passes under overscan;
   allocations ≈ 768 KiB churned.
3. Byte-out pass (65 k `get()`s) + copy to scratch.
4. Dart premultiply loop over every byte.
5. `decodeImageFromPixels`: buffer copy + new GPU texture upload; predecessor disposed.
6. Overlay bump → (absent F1) page-layer re-record + rasterization.
7. ×2-4 per displayed frame on high-Hz digitizers; duplicates discarded post-hoc.

Selection/Move adds: 72 KiB mask clone + up to 3 storage-sized mask allocs + full-buffer byte
write + Dart copy + O(w·h) scan. Rotate/Resize adds: 3 cleanEdge resamples per lifted layer.
HSV/BC adds: full-storage per-layer walks (up to ~37.7 M `get()`s) + full-tree rebuild + per-tile
content hashes.
