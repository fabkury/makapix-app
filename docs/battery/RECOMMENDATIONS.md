# Makapix Editor — Battery Discipline: Recommendations

**Date:** 2026-08-12 · **Status:** plan only — nothing implemented.
**Companion:** `ASSESSMENT.md` (same folder) holds all evidence, file:line references, and
magnitude reasoning. This document is only the decisions: what to do, what not to do, and in
what order. Item numbers (F1-F20, R1-R6, §4.x) refer to the assessment.

**Decisions baked in** (user-confirmed 2026-08-12): full phased program with explicit decision
gates for R3/R4 · lightweight embedded measurement (no upfront full matrix) · server-side items
included but flagged.

---

## 1. The verdict at a glance

| Verdict | Items |
|---|---|
| **DO — Phase 1** (cheap sweep) | F1, F2, F4, F5, F7, F8, F9, F11-lite, F12, F13, F14, F20 |
| **DO — Phase 2** | R1 central redraw scheduler (absorbs F3, F16) |
| **DO — Phase 3** | R2 engine dirty/hash + revision counter; full F11; F6; F17 |
| **DO — Phase 4** | R6 radio-discipline layer (generalizes F8-F10); F10, F18, F19 |
| **DO — anytime** (independent) | F15 (playFrame O(1) — prerequisite for Gate A) |
| **GATED on numbers** | R3 demand-driven playback clock (Gate A) · R4 engine composite cache (Gate B) |
| **SERVER REPO (flagged)** | SSE keepalive 15 s → 45-60 s; stream lifetime 300 s → 15-30 min |
| **DON'T** | R5 texture presentation · upfront full measurement matrix · SSE disconnect during editing · engine off the UI isolate · Impeller/Vulkan work now · wakelocks · more per-call-site redraw opt-outs after Phase 1 |

---

## 2. Phase plan

### Phase 0 — Baseline (one evening, before any fix)

Not the full matrix. Exactly this:

1. Add **debug-only counters** (log line every 5 s): frames produced/s, `display()` calls/s,
   `decodeImageFromPixels`/s, FFI crossings/s, HTTP requests. This is the tool every later
   phase re-uses; it pays for itself immediately.
2. One Pixel **ODPM session** (`dumpsys android.hardware.power.stats` deltas) on three
   scenarios, ~10 min each: **A** idle-no-selection, **B** idle-with-selection, **D** playback
   of a 2 fps animation.

Purpose: a before-number for the two biggest claims (ants, playback), and calibration for the
Gate A / Gate B decisions. If B ≈ A and D ≈ A, the assessment's Tier-1 ranking is wrong and we
stop and rethink before writing code.

### Phase 1 — The cheap sweep (one or two small patches, ship in the next release)

All trivial-to-small, low-risk, independently revertible. Order within the phase is free.

| Item | One-liner |
|---|---|
| **F1** | `RepaintBoundary` around the overlay stack + around `GridPainter` |
| **F2** | Ants repaint only on `phase` change (~6 Hz); fix the three `shouldRepaint => true` painters |
| **F4** | Same-cell dedupe guard on the freehand paint path (match the paste/move paths) |
| **F5** | HSV/BC sliders → the Levels pattern (`full:false` + settling redraw on release) |
| **F7** | `WidgetsBindingObserver` on ReplayPage → pause the 30 Hz sweep on background |
| **F8** | Player poll: pause while editor pillar active or backgrounded; one refresh on pillar return; raise `HttpClient.idleTimeout` above the poll period |
| **F9** | Lifecycle-gate the 60 s unread poll (no polling while backgrounded) |
| **F11-lite** | `flushNow()`: skip the write when `_lastHash` matches; flush at most once per lifecycle-transition burst |
| **F12** | Autosave: cancel the 5 s timer on background, rearm on resume (or switch to rearm-on-activity one-shot) |
| **F13** | Skip the `outlineMask` malloc/copy when no selection exists |
| **F14** | Journal: check `_isPlaybackVerb` before allocating; skip `AdvanceClock` send when `ms == 0` |
| **F20** | Use the already-cached canvas/display dimensions in `_redraw`/`_toCanvas` instead of scalar FFI reads |

**Checkpoint 1** (counters + one ODPM re-run of A/B/D): scenario B within ~10 % of A;
scenario A shows zero player/notification HTTP in 10 min. If met, Tier-1 idle drain is closed.

### Phase 2 — R1: central redraw scheduler (days)

Dirty-flag model; at most one engine fetch + premultiply + decode + publish per vsync; nothing
when clean. While in there: retire the `_imageGen` staleness stamp (one in-flight decode by
construction) and delete the ~8 double-`setState` sites (**F16**). Do **not** pre-implement F3
as a standalone band-aid — it is this phase.

Guard-rails: the engine still receives every pointer event (input fidelity unchanged — only
presentation coalesces); journal ordering unchanged (records at `_send` time); device pass on
stroke feel required.

**Checkpoint 2:** scenario C (scripted stroke loop): `display()` calls/s ≤ display refresh
rate (today: digitizer rate). Stroke feel signed off on the Pixel.

### Phase 3 — R2: engine dirty/hash bookkeeping (days) + the things it unlocks

Memoized per-layer/frame `content_hash` with conservative dirty flags + a document **revision
counter** over FFI. Then, in the same phase, the dependents:

- **F11 (full):** autosave change detection = "revision changed?" — skips serialize + both
  hash passes entirely when clean. Keep a belt-and-suspenders unconditional save (e.g. hourly).
- **F6:** bbox/tile-skip the HSV/BC/Levels preview walks (engine, golden-verified).
- **F17:** wire the dead `writeThumb`/`thumbFile` into a persisted gallery thumbnail cache,
  invalidated by revision/hash.

Non-negotiable: hash *values* unchanged (only when they're computed changes); goldens +
`assert.roundtrip` + `mkpx` exit-code gates must pass untouched. Over-invalidation is always
the safe failure direction.

**Checkpoint 3:** counters show zero `frameHash`/`layerHash` full-recomputes during a
stroke-plus-rebuild session on the stress doc; autosave cycles on an idle doc do no serialize.

### Phase 4 — R6: radio-discipline layer (1-2 days)

Promote `SyncFrameClock`'s registrant + foreground pattern to networking: one app-level
service owning lifecycle + pillar awareness; the player poll, unread poll, and SSE supervision
register with it (single policy: foreground-only, pillar-aware cadence, aligned wake schedule,
jittered backoff). F8/F9 from Phase 1 become the first two registrants rather than bespoke
gates. Include **F10** (SSE reconnect jitter + rate limit; don't reset `_attempts` until the
stream has stayed up N seconds), **F18** (cancel tokens for feed prefetch on pillar switch;
abandon queued decodes on unmount), **F19** (trim the 96 MiB frame cache on editor switch-in
and add a `didHaveMemoryPressure` handler).

**Server repo (flagged — separate conversation, tracked here because it sets the floor):**
lengthen the SSE keepalive comment interval (15 s → 45-60 s) and the stream lifetime
(300 s → 15-30 min). Until then, radio rest while editing is capped no matter what the app does.

**Checkpoint 4:** scenario G (backgrounded 10 min): zero app network requests, zero timer
wakeups. Scenario A on cellular: `mobile_radio_active` duty cycle visibly reduced vs Phase 0.

---

## 3. The two gates

### Gate A — R3: demand-driven playback clock

**Decide after Checkpoint 1, using the Phase 0/1 scenario-D numbers.** Prerequisites first
(cheap, do regardless): **F14** (Phase 1) and **F15** (cumulative-duration cache making
`current_play_frame` O(1) — "anytime" bucket).

- **Proceed if** scenario D still measures within reach of scenario B's *pre-fix* cost — i.e.
  playback remains a top-3 drain after the cheap fixes.
- **Skip if** F14/F15 plus typical short preview durations take it below the noise floor.

If proceeding: hybrid design — one-shot timers to the next frame boundary for slow content,
ticker mode for ≥~30 fps content; reuse the µs-carry math as-is. This deliberately revisits the
just-shipped vsync playback feature (87295c9), so it carries that feature's verification
playbook (wall-clock accuracy, the 60 fps blinker anti-aliasing check) and must coordinate with
the planned removal of the temporary `_sendSeq` edit guard. Target: a 2 fps animation produces
≤ ~6 frames/s (today: 60-120).

### Gate B — R4: engine composite cache / dirty rects

**Decide after Checkpoint 2/3, using scenario C on the 256²/64-layer stress doc.**

- **Proceed if** display-rate-coalesced strokes still saturate a core (or measurably heat) on
  layer-heavy documents.
- **Skip if** R1's coalescing already keeps stroke cost acceptable — for typical documents it
  likely will; this cache mainly serves the 64-layer extreme.

If proceeding: cached composite invalidated via the COW tile tables' pointer diffs; previews/
washes/onion stay outside the cache; a debug both-paths-compare mode plus goldens enforce
byte-identity; memory accounted against the Android ~1 GiB wall (`docs/memlab/REPORT.md`).
A week+ including verification — the only item in this program at that scale, which is why it
must earn its slot with numbers.

---

## 4. What NOT to do

1. **R5 — texture-based canvas presentation.** Buffers are small; after R1 the upload rate is
   capped at display rate. The price would be per-platform native code, Skia-vs-Impeller
   interop against a moving target (Impeller is temporarily disabled), and a breach of the
   deliberately simple strings-and-bytes FFI seam. Revisit only if post-R1/R4 measurement shows
   GPU upload/decode dominating, or if canvas sizes ever exceed 256².
2. **The full measurement matrix upfront.** Phase 0's three scenarios + counters are enough to
   steer. Run the full A-G matrix only if a checkpoint produces a surprise.
3. **Disconnecting SSE while editing.** The badge has real value during sessions; the fix is
   cadence (server-side) + reconnect hygiene (F10/R6), not disconnection. The 15 s *player
   poll* is the thing to gate, not the stream.
4. **Moving the engine off the UI isolate.** `Session` is single-threaded by design; a
   cross-isolate FFI story would buy little after R1/R2 (the heavy synchronous work left is
   autosave serialize, which R2 mostly eliminates) at high determinism/complexity risk.
5. **Impeller/Vulkan work now.** The disable is a pinned-Flutter stopgap for the PowerVR crash.
   When the Flutter pin advances past flutter/flutter#187586, re-enable and **re-measure**
   scenarios A-D — nothing more until then.
6. **Wakelocks.** None exist; keep it that way. (If long timelapse exports ever need
   keep-awake, that's a product decision, not a battery fix.)
7. **More per-call-site redraw opt-outs after Phase 1.** F4/F5 are worth shipping early, but
   the pattern (each call site opting into `full:false`-style discipline) is exactly what
   decayed. After Phase 1, redraw-path fixes go through R1's scheduler, not new special cases.
8. **Removing battery-costing *features*.** Ants, precision cursor, onion skin, overscan stay;
   every fix here preserves behavior and output bytes. Any engine-side change (F6, F15, R2,
   R4) ships only with the determinism gates green.

---

## 5. Sequencing rationale (why this order)

- **Phase 1 before everything:** the two biggest drains (idle ants loop, background/poll
  behavior) fall to trivial diffs. Shipping them first banks most of the win while the
  refactorings are still on the drawing board — and Checkpoint 1 validates the assessment's
  ranking before structural work begins.
- **R1 before R2:** the scheduler changes *when* engine calls happen; the dirty/hash work
  changes *what they cost*. Doing R1 first means R2 is measured against the real
  (display-rate) call pattern, and Gate B's numbers are honest.
- **R2 before Gate B:** composite caching (R4) would sit on the same dirty-tracking
  foundations R2 builds; if R4 is ever approved, R2 has already paid half its design cost.
- **R6 last of the committed phases:** F8/F9 already capture most of the radio win in Phase 1;
  R6 is the structural home so C5/C6 real-time features don't regrow bespoke timers. No reason
  to block rendering wins on it.
- **Gates stay gates:** R3 touches a feature shipped days ago and R4 is the only week-scale
  item; both must earn their slot with Phase-0/1/2 numbers, not code-reading conviction.

---

## 6. Effort summary

| Phase | Content | Rough effort | Ships |
|---|---|---|---|
| 0 | Counters + 3-scenario ODPM baseline | 1 evening | debug-only |
| 1 | 12 small fixes (F1-F14 subset, F20) | 1-2 days | next release |
| 2 | R1 scheduler (+F3, F16 absorbed) | ~3-5 days | own release, device pass |
| 3 | R2 dirty/hash + F11/F6/F17 | ~3-5 days | own release, goldens green |
| 4 | R6 radio layer + F10/F18/F19 (+server ask) | 1-2 days | any release |
| Gate A | R3 playback clock (if numbers say so) | 1-2 days + playback playbook | own release |
| Gate B | R4 composite cache (if numbers say so) | 1-2 weeks | own release, stress pass |

Committed path (0-4): roughly **two working weeks** spread across releases, front-loaded so
the largest battery wins land in the first couple of days.
