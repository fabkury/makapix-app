# Deterministic session replay ("making-of") — memory & performance appraisal

**Date:** 2026-08-11 · **Status:** appraisal — measured costs and constraints only. This document
draws **no go/no-go conclusion** and contains no design or implementation commitment. It appraises
the three-stage concept chosen in the 2026-08-11 brainstorm: **record** the DSL action stream
alongside the autosave · **replay/scrub** a drawing's creation in-app · **export** a shareable
upscaled timelapse.

**Scope, as decided for this appraisal:** recording is assumed **always-on** for every editor
session (the bar is therefore "unconditionally negligible"); the log is **local-only** (the exported
video is the only artifact that leaves the device); the export envelope is **1080-class, 30 fps,
15–60 s**. Measurements were taken on the Windows workstation and on the real Pixel 10 Pro XL
(the memlab reference device) against the current tree; Windows CPU numbers transferred to the
device at roughly **1.5–2×** slower throughout this study — unlike memory behavior, which per
`docs/memlab/REPORT.md` does not transfer at all and was measured under the device's rules.

---

## 0. How the numbers were produced

No production code was touched. Three harnesses, kept in `tools/replaylab/` (usage + verbatim
reproduction commands in its README):

1. **Synthetic-but-representative DSL scripts** (`gen_replay_script.py`), generated to mirror exactly what
   `editor_page.canvas.dart` emits (per-event `PointerDown/Move/Up` strokes averaging ~45 moves,
   the ~17-line settings burst `_selectTool` sends on every tool switch, color changes, `Undo()`
   after ~7% of strokes, `DuplicateFrame`/`AddLayer`/`SetActiveFrame` structure, selection + HSV
   applies). Validated against the parser via `mkpx run` before use.

   | Corpus | Canvas | Frames | Layers | Lines | Pointer lines | Models |
   |---|---|---|---|---|---|---|
   | small | 64×64 | 1 | 4 | 15,016 | 94% | a casual finished piece |
   | medium | 128×128 | 8 | 4 | 60,042 | 93% | a serious animation |
   | large | 256×256 | 16 | 4 | 150,048 | 94% | a long-lived epic (~1.5–2.5 h of *active* drawing) |
   | cheap | 64×64 | 1 | 1 | 100,001 | 0% (`SetCursor` only) | the parse/dispatch floor |

2. **The `mkpx` CLI harness** for replay throughput, memory census (`mem`/`mem.os` probes) and
   save/load (`assert.roundtrip`) deltas — on Windows and pushed to `/data/local/tmp` on the
   Pixel per the `tools/memlab/run_matrix_device.ps1` pattern (`cargo ndk -t arm64-v8a`).

3. **A one-off bench crate** (`tools/replaylab/replaybench/`, path-dependencies on `crates/codec`
   and `crates/engine`, deliberately not a workspace member) that (a) times the *shipped* streaming encoders
   `encode_gif_streaming` / `encode_animated_webp_streaming` and `upscale_nearest` on
   timelapse-shaped content (progressive limited-palette drawing, cumulative frames), (b) replays
   the corpus scripts in chunks taking COW frame-vector snapshots at each checkpoint and censuses
   retained memory by tile pointer, and (c) times `render::composite_frame`. Built for Windows and
   aarch64 Android; content is LCG-deterministic so both platforms ran identical inputs.

Cross-check worth recording: the engine memory census after the 150k-line replay and the encoder
outputs were **byte-identical between Windows and the Pixel** — the determinism story the feature
rests on held exactly in these runs.

Caveat: the corpus is synthetic. Lines-per-minute of real human drawing (§2.1) is estimated from
input-event rates, not measured from a live session; a debug counter at the `_send` seam would
settle it cheaply in a future session.

---

## 1. Load-bearing facts (verified against the tree)

1. **Every document mutation already flows through one Dart function as DSL text.**
   `_send(String dsl)` (`app/lib/editor/editor_page.engine.dart:213`) → `mkpx_run`. Freehand tools
   send one `PointerMove(x,y)` per **raw pointer event** with no coalescing
   (`editor_page.canvas.dart:485`); shape-handle drags send **3 lines per event**
   (`ShapeSet` + `SetShapeRotation` + `SetTriangleTip`, `canvas.dart:1035`); playback preview sends
   `AdvanceClock(33)` at ~30 Hz (`engine.dart:272`). Recording is therefore a Dart-side string tap —
   the engine needs no `Action → DSL` serializer (none exists; `Action` has no `Display`).
2. **The undo history cannot power replay — confirmed.** Records store *absolute* before/after
   content (`crates/engine/src/history.rs:3-6`): `Edit::Pixels` carries literal before/after tile
   `Arc`s (`TilePatch`, `buffer.rs:81-84`), `DocStructure` whole frame vectors. Compaction
   deliberately punches holes mid-stack (`history.rs:192-198`), and the stack is a bounded suffix
   (128/frame, 8,192 total, 96 MiB byte budget, `history.rs:15-22`). Replay must be its own stream;
   this closes the question the repeat-redo analysis raised.
3. **The determinism machinery is already in place.** The engine has no wall clock; RNG
   (`SeededRng`, xoshiro256**) and the `VirtualClock` are DSL-addressable (`SetSeed`,
   `AdvanceClock`), transcendentals are the bit-exact `det_*` family. The parser deliberately keeps
   legacy aliases so that *"old recorded scripts still parse"* (`session/parse.rs:404`) — the
   format-stability property a persisted log needs already has precedent.
4. **Not every mutation is DSL.** Three FFI entry points mutate the document as bytes, outside
   `mkpx_run`: `mkpx_load` (open/autosave-resume), `mkpx_import`, `mkpx_import_decoded`
   (image import, Club edit/remix). A log replayed from an empty document cannot reproduce any
   drawing whose lineage includes one of these. This is a **stage-1 recording-format constraint**,
   not an export detail — see §5.1.
5. **Snapshot primitives:** `RgbaBuffer::snapshot()` is a single `Arc` bump (`buffer.rs:355-359`);
   `Frame`/`Layer` derive `Clone` (O(layers) Arc bumps + one `String` each); `Document` itself does
   **not** derive `Clone` (`document.rs:229`) — a frame-vector snapshot is hand-assembled.
   `.mkpx` save is ≥2 full pixel passes + per-tile hashing with a measured **3.2×** in-class
   transient (memlab addendum); load transient ≈ 2.2×.
6. **The export machinery is closer than expected.** Streaming, pull-based encoders exist for both
   GIF and animated WebP (`codec/lib.rs:491`, `:289`) — only compressed output accumulates — and
   `upscale_nearest` (`lib.rs:174`, scale clamped 1..=32) is applied per frame *inside* them. The
   WebP muxer already encodes only the changed rect per frame (diffed at source resolution); the
   GIF encoder re-emits and re-quantizes **full frames at output resolution** (its dominant cost).
   All FFI is synchronous on the calling thread; the shell already runs exports in an isolate by
   rebuilding an engine from `.mkpx` bytes (`engine_ffi.dart:625`) — the identical pattern fits a
   replay-driven export.
7. **The budgets this must live under** (`docs/memlab/REPORT.md`): 256 MiB soft / 320 MiB hard
   document budget, 96 MiB history budget, and the Android scudo ~4 KiB size-class ceiling of
   ~1.0 GiB where pixel tiles (4,112 B) and tile tables (4,608 B) both live. Frame budget
   1024/document (`document.rs:13`) — irrelevant to export, which streams frames without ever
   materializing them as a document.

---

## 2. Recording cost

### 2.1 Volume: what real interactive use generates

The recording rate is input-event-rate-bound, not action-bound. Estimated bounds (Flutter delivers
moves at the display/input rate on Android; 90 Hz assumed typical, 120 Hz worst):

| Activity | DSL lines/s | Notes |
|---|---|---|
| Finger resting / thinking | 0 | nothing is sent |
| Freehand stroking (contact) | 60–120 | one `PointerMove` per event |
| Shape/gradient handle drag | 180–360 | 3 lines per event (`_pushShape`) |
| Playback preview running | ~30 | `AdvanceClock(33)` ticks |
| Tool switch | ~18 burst | `SelectTool` + settings re-push |

At a 25–50% stroke duty cycle, **1,500–3,500 lines per minute of active drawing** is the realistic
band (worst-case continuous contact at 120 Hz: 7,200/min). The 150k-line "large" corpus therefore
represents roughly 1.5–2.5 hours of solid active drawing — a many-session piece.

**Bytes.** Measured on the corpus: raw DSL averages **19.7–21.1 B/line**; with a `+<delta-ms> `
timestamp prefix (the natural recording format), **23.6–25.0 B/line**. Growth scenarios, measured
compressibility applied (gzip level 6 achieved **5.6–6.8×** on the timestamped logs; even
fastest-level deflate gives 3.4–4.0×):

| Session | Lines | Log raw | Log gzipped |
|---|---|---|---|
| 20-min casual piece | ~15k | ~350 KB | ~52 KB |
| 2 h serious piece | ~60k | ~1.4 MB | ~240 KB |
| 10 h epic (multi-session) | ~600k | ~14 MB | ~2.5 MB |

For always-on recording across a 100-drawing gallery this lands in the tens of MB worst case —
below the artwork disk cache's own budget class. **On-disk growth is a non-issue.**

### 2.2 IO strategy vs the autosave path

The shipped autosave (`autosave_controller.dart`) serializes the **whole `.mkpx`** every 5 s of
activity (hash-gated, single-flight) and `flushNow()` does a synchronous serialize on
dispose/background. Against that baseline the log is noise: appending at 1,500–3,500 lines/min is
**~0.6–1.4 KB/s** of buffered sequential writes — versus autosave rewriting up to several MB every
cycle while active. An in-memory append buffer flushed on stroke-end or on the same 5 s cadence
costs microseconds; the one structural requirement is a synchronous tail flush mirroring
`flushNow()` on dispose/background so the log never trails the autosaved document (§5.4). Nothing
here approaches the cost of what the editor already does every 5 seconds.

### 2.3 Replay-fidelity taxes on the recording

- **Seed and clock:** `SetSeed` must be recorded at session start (and `AdvanceClock` ticks kept or
  the clock reconstructed) for RNG tools (Airbrush) to replay bit-exact. The machinery exists (§1.3).
- **Preview chatter:** a preview-heavy session adds ~30 `AdvanceClock` lines/s; 5 cumulative
  minutes of preview ≈ 9,000 lines ≈ 220 KB raw. Filterable/compactable later without breaking old
  logs (the legacy-alias precedent) — but even unfiltered it does not change the size class.
- **Display-only lines** (draft `ShapeSet` streams, `SetHsvShift` previews) are needed anyway:
  they are what makes a replay *look like* the session, and the committed result flows through them.
- **Budget refusals replay deterministically:** a mutation the engine rolled back at the hard
  budget during recording rolls back identically on replay — the log does not need to know.

---

## 3. Replay & scrubbing cost

### 3.1 Raw re-execution (measured)

`mkpx run` end-to-end, process baseline subtracted (medians; Windows n=7, device n=3):

| Corpus | Windows | Pixel 10 Pro XL | Device throughput |
|---|---|---|---|
| cheap (100k `SetCursor`) | 15 ms (~6.7M actions/s) | ~80 ms | ~1.25M actions/s |
| small (15k) | ~9 ms | ~50–100 ms | — |
| medium (60k) | ~54 ms | ~140–220 ms | ~0.4M actions/s |
| large (150k) | ~231 ms | **~320–420 ms** | **~0.4M actions/s** |

The parse/dispatch floor is 0.15 µs/action (Windows) / 0.8 µs (device); painting dominates the
rest. **A full from-zero re-execution of a 1.5–2.5-hour drawing session takes under half a second
on the reference phone.** Memory during replay is bounded by the shipped budget machinery: after
the 150k replay the census reads 31 MB history + 4.6 MB unique document, **52 MB process RSS**
(identical census on both platforms).

Two engine-side costs scale unfavorably for *other* session shapes and are worth knowing about:
structural actions (`AddFrame`/`DuplicateFrame`/`AddLayer`/…) each pay an unconditional
full-document census walk — ~1 ms at budget scale (`session.rs:1132`, `document.rs:375-377`) — so
a frame-by-frame animator's log with 500 structural ops adds ~0.5 s; and history-cap eviction is
`Vec::remove` churn (`history.rs:174,193,204`). Both only matter if replay keeps full history
recording on; replaying `Undo()` lines needs *some* live history, so blanket suppression is not
available — but the measured cost of just leaving it on was the 31 MB/on-budget figure above.

### 3.2 Seek strategies and their memory price

**Restart-from-zero** costs are linear in position: a seek to the midpoint of the large corpus is
~180 ms on device — fine for tap-to-seek, a ~5 fps experience for continuous slider dragging.

**Periodic COW snapshots** were measured directly (replay in chunks; snapshot = clone every
layer's `Arc<TileTable>`; retained memory censused by pointer across all checkpoints):

| Corpus | Checkpoints | Snapshot-only retained | Per checkpoint | Snapshot take time |
|---|---|---|---|---|
| large (150k) | 30 | 17.5 MiB | ~0.6 MiB | ~0.4 µs each |
| large | 100 | 24.5 MiB | ~0.25 MiB | — |
| large | **300** | **35.9 MiB** | ~0.12 MiB | 0.12 ms total |
| medium (60k) | 100 | 6.4 MiB | 65 KiB | — |
| small (15k) | 100 | 1.4 MiB | 14 KiB | — |

Sharing does the work: 300 checkpoints retain only 8,755 historical tile versions beyond the live
document because untouched regions are the same `Arc` in every snapshot. With 300 checkpoints the
seek path is *restore nearest snapshot (Arc bumps, ~µs) + replay ≤500 actions (~1.3 ms device) +
composite (~1 ms at 256², measured 0.95 ms/frame)* — **real-time scrubbing at display rate, for
~36 MiB**, which is ~4% of the fatal ~1 GiB allocator class and inside the same size class the
96 MiB history budget already governs. Even 30 checkpoints (17.5 MiB) keep worst-case seek work
at ~6 ms.

Caveats: (a) the corpus is progressive drawing; the adversarial bound is
`checkpoints × doc_unique_bytes` (a noise-refill session could pin `N × ` up to 320 MiB), so a
production scrubber would need a snapshot byte budget with eviction — the exact pattern the
history budget already implements, and the census (`probe::mem_report`) already measures; (b) the
census here excluded selection masks (an `Arc` bump each if kept); (c) `Document` needs a
hand-rolled clone (§1.5). `.mkpx` serialization is the *wrong* dense-snapshot primitive (10–39 ms
per save on these documents plus the 3.2× transient) but the right **chapter/base** primitive
(§5.1) — one-shot, compact, already budget-guarded on load.

### 3.3 Scrub display

The scrub view is the editor's existing composite-and-decode path: composite measured 0.95 ms at
256×256 / 0.14 ms at 64×64, plus the shell's `decodeImageFromPixels` — the same per-frame work the
playback preview already does at 30 fps today. No new memory class.

---

## 4. Timelapse export

### 4.1 Pipeline shape and measured per-frame costs

A 15 s / 30 fps clip is 450 samples over the whole log (large corpus: one sample per ~333
actions); a 60 s clip is 1,800. Per-frame costs, **device** (Windows in parentheses):

| Stage | 256×256 → ×4 (1024px) | Notes |
|---|---|---|
| Replay slice between samples | ~0.8 ms amortized | whole-log replay ÷ 450 |
| Composite at source res | ~1.0 ms (0.95) | `render::composite_frame` |
| Integer NN upscale to 1024² | 1.14 ms (1.35) | `upscale_nearest`, measured standalone |
| Animated-WebP encode | **3.0 ms (2.6)** | streaming, delta rects |
| GIF encode | **18.5 ms (15)** | full-frame re-quantize at output res |

End-to-end measured encodes of 450 frames at 1024×1024 output on the phone: **WebP 1.35 s**
(13.5 MiB out from 256² source; 6.5 MiB from 128²; 2.3 MiB from 64²), **GIF 8.2–8.5 s (33–36 MiB
out)**. With replay+composite+upscale added, a full 15 s export lands at roughly **3 s (WebP) /
10 s (GIF)** on device; 60 s scales ×4. Peak memory is streaming-shaped: one upscaled RGBA frame
(4.0 MiB at 1024², 4.4 MiB at 1080², 8.3 MiB at 1080×1920) + the source-res previous frame + the
compressed accumulator (2–36 MiB above) — **tens of MB, no interaction with the document budgets,
and the big buffers sit far from the fatal ~4 KiB allocator class.** The existing
isolate-with-its-own-engine export pattern applies unchanged.

**Upscale math.** 1080 is not an integer multiple of any legal canvas: the integer-clean outputs
are ×16/×8/×4 → **1024** from 64/128/256 (×17 → 1088 from 64). "1080-class" therefore means either
shipping 1024²/1024-wide as-is (every platform accepts it) or centering the ×N result on a
1080×1080 / 1080×1920 canvas with padding — a memcpy-per-row cost, noise against the table above.
Non-square canvases letterbox the same way. If a platform hardware encoder is the sink, even
dimensions are required (1080×1080 and 1080×1920 are safe standard sizes on MediaCodec /
VideoToolbox / Media Foundation; MediaCodec's `isSizeSupported` is queryable at runtime).

An incidental observation: since sampled frames at source resolution are just frames, a ≤1024-frame
sampled timelapse *document* (450 × 256² ≈ 115 MiB payload) fits inside the existing budgets, so
the shipped `mkpx_export_gif/webp(scale)` FFI could in principle drive stages of this without new
codec surface. Noted as feasibility, not design.

### 4.2 Format & dependency appraisal

**(a) The exporters we ship (zero new dependencies).** Animated WebP is fast (3 ms/frame), small
(2–14 MiB/15 s), lossless, and pure Rust — and essentially unshareable: among the surveyed
platforms only **Discord** animates uploaded WebP (its 2025 media-pipeline change). GIF encodes
5–7× slower here, at 21–36 MiB per 15 s for 1024px output — over X/Twitter's 15 MB GIF cap (the
only major platform that takes GIF and converts it to video); Instagram/TikTok treat GIF as a
static image or reject it. GIF at reduced output resolution shrinks quadratically (~9 MiB at
512px) but that defeats the "crisp 1080-class" goal. **Neither shipped format reaches
Instagram/TikTok/X/Shorts as an auto-playing post.**

**(b) Real video in pure Rust (2026 state).** There is **no production-credible pure-Rust H.264
encoder**: `less-avc` is lossless I_PCM only (a 15 s 1080² clip ≈ ~790 MB); `rusty_h264`
(June 2026, "Remade With Rust" program) claims Constrained Baseline at 24–71 Mpx/s on AVX2 but is
weeks old with no independent validation. AV1 via `rav1e` is Rust-plus-heavy-assembly (NASM/gas at
build time; the no-asm pure build has *no published benchmark* and a multi-× penalty is expected;
mobile encode well below realtime at quality presets) — and AV1 uploads are accepted by YouTube
but **not** by TikTok/Instagram/X. Pure-Rust MP4 *muxing* is solved (`muxide`, young but capable
of H.264/AV1; `mp4e` for H.264-family) — the encoder is the gap, not the container. Doctrine fit:
any of these would quarantine in `crates/codec` like `image`, but rav1e's asm/NASM toolchain
sits awkwardly against the pure-Rust periphery rule, and the payoff (YouTube-only AV1) is thin.

**(c) Platform encoders driven from Dart (Rust stays out).** The post-FFmpegKit (retired
2025-01-06) industry answer: thin platform channels over **MediaCodec** (Android) /
**VideoToolbox** (iOS) / **Media Foundation** (Windows), hardware-encoding H.264 into MP4.
`flutter_quick_video_encoder` proves the exact raw-RGBA-frames→MP4 shape (MediaCodec +
AVFoundation; dormant ~23 months, no Windows); `ffmpeg_kit_flutter_new` is actively maintained and
covers all three desktop/mobile pillars at the cost of multi-MB LGPL FFmpeg binaries and the
patent posture that killed its predecessor. Hardware 1080p30 encode is faster-than-realtime on
any target device (a 15 s clip ≈ seconds), input-side cost is the same composite+upscale already
measured, plus RGBA→YUV conversion (or a Surface input on Android, which sidesteps layout quirks).
Rust's role collapses to what already exists: composite + `upscale_nearest` handing frames across
the existing bytes-only seam.

**(d) What actually posts (survey, August 2026).** Silent **H.264 MP4, yuv420p, even dimensions,
≤30 fps** is accepted and auto-plays on Instagram (feed/Reels/Stories), TikTok, X (≤140 s free
tier), YouTube Shorts (≤3 min), Discord, Reddit, Bluesky (≤3 min/100 MB), Mastodon. No surveyed
platform requires an audio track (a silent AAC track is cheap insurance). Portrait 1080×1920
maximizes Reels/TikTok/Shorts presentation (1:1 gets letterboxed there); square is universally
accepted. The binding size constraint in the envelope is **Discord's 10 MB free-tier cap** —
comfortably met by low-entropy pixel-art H.264 at 1–3 Mbps (15 s ≈ 2–6 MB; 60 s ≈ 8–22 MB, where
60 s clips may need the lower end of that bitrate range). Sharing via the OS share sheet
(`ACTION_SEND` / `UIActivityViewController`) with an MP4 reaches all of these without per-platform
API integrations.

### 4.3 Where the log itself stays

Local-only by the scope decision: the sidecar never uploads, so the Club's 5 MB artwork /
50 MB `.mkpx` caps and the frozen attachments contract are untouched by this feature. (For the
record: even the epic's log gzips to ~0.7 MB, so a future "publish your making-of" would not be
size-blocked — it would be a server-contract question, not a bytes question.)

---

## 5. Constraints that would force design decisions (flagged early, per the brief)

1. **Documents that don't start from `NewDocument` break pure-log replay — a stage-1 format
   decision.** Image imports, Club edit/remix downloads, and every autosave resume enter through
   `mkpx_load`/`mkpx_import*` as bytes, not DSL (§1.4). A recording format that cannot mark
   "chapter starts from these base bytes" (e.g. the compact `.mkpx` the store already writes) can
   only ever replay single-session, born-in-app drawings. Multi-session recording has the same
   need: either the log spans sessions from empty, or each session opens a chapter anchored on the
   autosave. This is the one constraint that must be settled *before* stage 1 ships, because logs
   recorded without it cannot be upgraded later.
2. **Neither shipped export format is shareable where sharing matters.** WebP animates only on
   Discord; 1024px GIF exceeds X's 15 MB conversion cap and is static-or-rejected on
   Instagram/TikTok (§4.2a/d). If "social-media-shareable" is the goal of stage 3, the numbers
   point at H.264 MP4, which pure Rust cannot credibly produce in 2026 (§4.2b) — leaving platform
   encoders via Dart (§4.2c) as the only route that satisfies both the dependency doctrine and the
   platforms. That is a per-OS platform-channel (or plugin/licensing) commitment the team hasn't
   made yet; Windows additionally has no maintained plugin and would need a hand-written Media
   Foundation channel (or falls back to WebP/GIF export there).
3. **Scrubbing needs snapshots for smoothness, and they are measurably cheap.** From-zero seeks
   cost up to ~0.45 s on device (fine for taps, ~5 fps for slider drags); 300 COW checkpoints turn
   scrubbing real-time for **35.9 MiB** on the epic corpus (§3.2). The engine work is small
   (hand-rolled `Document` clone) — but a production scrubber wants a snapshot byte budget with
   eviction to cap the adversarial `checkpoints × doc` case, in the mold of the existing history
   budget.
4. **Always-on recording is affordable but must mirror `flushNow()`.** The steady-state cost
   (≤25 B/action, ~1 KB/s active, gzip 6×, appends dwarfed by the 5 s `.mkpx` autosave) meets the
   "unconditionally negligible" bar (§2). The crash-consistency edge — log tail vs last autosave —
   needs the same synchronous-flush-on-dispose discipline the autosave already established, plus a
   cheap divergence check on load (a trailing frame-hash marker, or a bounded replay-and-compare
   using the measured sub-second full replay).
5. **Replay speed is not the bottleneck anywhere.** 0.4M actions/s on device means even a
   pathological 1M-line log replays in ~2.5 s; the structural-action census walk (~1 ms each) is
   the only per-action cost that could bite atypical (frame-spam) sessions, and a replay-aware
   history mode is an optimization, not a prerequisite (§3.1).

## 6. Not measured / open

- **Real human lines-per-minute** (§2.1 is an input-rate estimate; instrument `_send` to confirm).
- **iOS**: unmeasured, per the memlab precedent; no reason to expect a different order of
  magnitude on A-series CPUs, but the device pass should be repeated there before trusting §3/§4
  numbers beyond Android.
- **MediaCodec/VideoToolbox/Media Foundation encode timings and RGBA→YUV feed cost** on the
  actual devices (research-sourced envelope only: hardware 1080p30 is faster than realtime).
- **H.264 output sizes for real pixel-art timelapses** (the 1–3 Mbps figure is a codec-typical
  band, not a measurement).
- **Long-log tail effects**: logs beyond ~1M lines (years-long pieces), and snapshot retention on
  adversarial content (bounded analytically in §3.2, not measured).
- The corpus under-represents structural-op-heavy sessions (animators) and Move/paste drags
  (coalesced to whole-pixel deltas by the shell, so they record *fewer* lines than freehand).

## Reproducing

The harnesses live in `tools/replaylab/` (corpus generator, DSL-vocabulary check, and the
`replaybench` crate with `gif`/`webp`/`upscale`/`png`/`snap`/`comp` modes); its README carries the
verbatim Windows and on-device command sequences, including the process-baseline subtraction and
the relative-path caveat for the CLI's render probes.
