# Replay pacing: how Journal ticks become Replay and Timelapse time

Status: **as built, 2026-09-06** (ADR 0029; proposed and implemented the same day). Companion to
`ANALYSIS.md` (the replay appraisal) and ADRs 0003/0004. Vocabulary per `CONTEXT.md` ("Journal",
"Chapter", "Replay", "Timelapse", and since this work "Tick" and "Working time"). §3 keeps the
alternatives as weighed; §4 describes the design as it ships, with the as-built notes in §6.

## 1. The problem, stated against what ships

What ships is not "every journal line gets the same time". Both the Replay viewer's sweep/slider
(`replay_page.dart`) and the Timelapse planner (`timelapse_plan.dart`) step through the
**visible-change index** (`visible_index.dart`): the positions whose transition can change the
composited active frame. Draft fiddling (`ShapeSet`, `PasteMove`, `MoveDraftMove`), adjustment
previews (`SetHsvShift`, `SetLevels`), settings bursts, palette work, and selection-mask edits
already cost zero time. The two consumers share `FlatJournal` + `visiblePositions` so they can
never disagree about what a position means.

What *is* uniform is time per **visible tick**. That produces the imbalance the request describes,
in a narrower form:

| Gesture | Journal lines | Visible ticks | Video time at 30 s / 5,000 ticks |
|---|---|---|---|
| Pencil stroke across 80 distinct cells | ~80 `PointerMove` | 80 | 0.48 s |
| Airbrush pass, 2 s of contact at 90 Hz | ~180 lines (not deduped) | 180 | 1.08 s |
| Levels: 40 s of slider tuning, then Apply | ~1,000 `SetLevels` + 1 `ApplyLevels` | 1 | **0.006 s (one frame)** |
| Bucket fill of a whole background | 1 `Tap` | 1 | one frame |
| Shape: 15 s of handle dragging, then commit | ~2,700 lines (3 per event) + 1 | 1 | one frame |
| Paste, move around, commit | ~200 lines + 1 | 1 | one frame |
| 24 arrow-key nudges of a layer | 24 `NudgeMove` | 24 | 0.14 s |

So: single-line impactful events flash by in one 33 ms frame, and stroke-heavy passages own the
budget. Pure wall clock is not the answer either: the two journals in this workstation's drawing
store (desktop test drawings, treated only as illustration) carry gaps of 9 minutes and 17 hours
between consecutive lines; on both, the sum of gaps exceeds the sum of hands-on time by 8× to
300×.

Every input needed for a better axis is already on disk. Each journal line carries `+<delta-ms>`
since the previous line of its chapter (`journal_format.dart`), the visible index already tracks the
active tool and pen state per statement, and the format is additive. No recording change, no epoch
bump, no engine or FFI surface is required by the recommendation below (§4), which is why it can
apply to every journal ever recorded, including those behind already-published timelapses.

Decisions taken in the 2026-09-06 design conversation, which the alternatives below are ranked
against:

- one shared axis for the viewer and the exporter (the existing doctrine);
- the recorded wall clock is a legitimate input once pauses are neutralized by clamping;
- shell-only (Dart over the journal text); engine changes are not wanted for this;
- single-line events get a floor **and** a ceiling; strokes follow working time like everything
  else; Undo/Redo is paced like any other event; the per-gap clamp is a fixed constant of ~2 s.

## 2. Vocabulary

- **Tick** — a visible position (as today): the transition into position *p* can change what the
  viewer shows. A tick is either a **stream tick** (a `PointerDown`/`PointerMove` under a stamp
  tool, or a held-pen `MoveCursor`: one of many near-identical steps of one gesture) or an **event
  tick** (everything else visible: commits, applies, structural edits, undo/redo, frame hops,
  chapter-base pops, shape/gradient `PointerUp`, bucket `Tap`). The classification needs no new
  table: it falls out of the triage `visible_index.dart` already performs (`_kStampTools`,
  `penHeld`, `_kAlwaysVisible`).
- **Working time** of a tick — the sum of the recorded deltas of every line since the previous tick
  (inclusive of this one), each delta clamped to a ceiling. Invisible lines have no tick of their
  own, so their time flows forward into the next tick: the 40 s of Levels tuning land on the
  `ApplyLevels` tick; the handle dragging lands on the shape's commit.
- **Dwell** — the video time a tick is shown for. The pacing policy is the function from working
  time (and tick class) to dwell, under a fixed total (the 15/30/60 s preset).

## 3. Alternatives

Each is scored on balance (does it fix the table in §1), fidelity (does it reflect what the artist
did), cost (build time, memory, code surface), and reach (does it work on existing journals).

### A. Static verb weights (the seed idea)

A hardcoded table maps each verb to a weight; a tick's dwell is proportional to its weight; the
axis is the prefix sum of weights over the visible positions.

- Balance: fixes "one frame per Levels apply" by fiat (e.g., `ApplyLevels` = 30 pencil moves). Does
  not fix scribble domination unless stroke verbs get fractional weights, which then punishes a
  deliberate 80-cell line the same as a 2-second scribble of 80 cells.
- Fidelity: blind to magnitude. A Levels apply on an empty layer weighs the same as one over a full
  canvas; a bucket fill of 3 pixels the same as the background; 40 s of tuning the same as 1 s.
- Cost: trivial (O(ticks), one `Int32List` prefix sum). But a **second per-verb table** next to the
  visible index's triage: every new verb must be classified twice, and the weights are opinions
  with nothing to validate them against (the visible index at least has a composite-hash oracle).
- Reach: every journal.

Verdict: cheapest, least faithful. Its one durable idea, "tick classes differ", survives in §4 as a
two-class distinction (stream vs event) that the existing triage already yields.

### B. Clamped working time, pure proportionality

Dwell ∝ working time (§2) with the per-gap clamp as the only rule. Total = preset.

- Balance: mostly fixes both directions. Tuning time accrues to the apply; a scribble takes the
  seconds it took; a bucket fill takes the pause before it (choosing the tool, picking the color),
  which is usually 0.5–2 s of working time.
- Fidelity: the best single signal available without engine help. It is the artist's own effort
  distribution, which is also what a "making-of" is about.
- Failure modes: (1) a fast tap after a fast previous action can still land under one frame (no
  floor); (2) a 3-minute tuning session, even clamped per gap, sums to minutes and can freeze the
  video on one apply (no ceiling); (3) bursts of tiny events (24 arrow nudges, an undo storm) each
  get their real ~100 ms, which is fine here but interacts badly with floors in C; (4) journals with
  all-zero deltas (CLI scripts, synthetic corpora) collapse to zero working time and need a
  fallback to uniform ticks.
- Cost: one pass over the lines (already made for the visible index) plus a clamped running sum;
  storage = one cumulative value per tick. O(L) build, O(ticks) memory.
- Reach: every journal (deltas have been recorded since epoch 1).

Verdict: the right signal; needs guardrails.

### C. Working time with floors and ceilings on event ticks (**recommended**, detailed in §4)

B, plus: an event tick's dwell is clamped into `[floor, ceiling]` expressed in **video** time, and
the remaining budget is distributed over the rest in proportion to working time (water-filling
with a fixed total). Stream ticks have no floor (a pencil move is one of many) and no ceiling
beyond the per-gap clamp. A **burst rule** keeps floors from multiplying across runs of identical
events (§4.4).

- Balance: fixes the whole table in §1: every apply/fill/commit/pop is on screen long enough to
  register; nothing can freeze the video; strokes breathe or compress with the hand.
- Fidelity: B's, bounded.
- Cost: B's build plus a per-preset water-filling over the *event* ticks only (hundreds to low
  thousands; stream ticks scale linearly in closed form), microseconds. Memory: two typed arrays per
  tick.
- Reach: every journal.

### D. Measured visual impact (engine-assisted) — deferred

The engine already computes, per committed gesture, the changed-tile patch that powers undo
(`RgbaBuffer::diff_from`, `TilePatch::len()`, `dirty: IRect`, Arc-pointer comparison, near free). A
monotonic `changed_pixels` accumulator on `Session` plus one scalar FFI getter, sampled by the
replay host during the forward pass it already makes at init, would give dwell ∝ pixels actually
changed: the background fill dwells like the 30 strokes it is worth; a no-op apply gets nothing.

- Limits: per-gesture, not per-move (single-coat strokes commit their record on pointer-up, ADR
  0007), so strokes would still need B's time signal or a per-move coat-coverage counter; the
  exporter isolate has no host pre-pass, so the weight array must be shipped to it (fine: ≤ 4 B per
  tick) or the host's pass must run first (it does when sharing from the viewer).
- Cost: small Rust surface (accumulator, getter), one FFI read per action during init (~0.1–0.8 µs
  each, tens of ms on a 150k-line journal), a `Uint32List` per tick.
- Verdict: the most principled magnitude signal, and the natural **second step** if C's ceilings
  ever prove wrong for a class of ops (it could scale an event's ceiling by impact). Out of scope
  now by the shell-only decision; noted so the door is marked.

### E. Composite-hash delta as an impact measure — rejected

Hashing the active frame's composite after every visible action during the init pass is O(pixels)
per action (`Frame::content_hash` walks every tile's pixels; nothing is cached): 150k actions ×
65k px at 256² ≈ 10 G pixel visits. Not "highly performant". Rejected.

### F. Hybrid: strokes per cell, events by working time — rejected by decision

Keeps today's cell pacing inside strokes and applies working time only to event ticks. Two rules
instead of one, and it re-creates the scribble problem (a 2 s scribble of 300 cells outweighs a
10 s careful line of 60). Recorded because it is the obvious compromise; rejected in the design
conversation in favor of one rule everywhere.

### G. Dwell-only (minimal change) — fallback

Keep the uniform visible index; after every event tick, repeat the frame for *k* extra frames
(duplicates delta-encode to almost nothing) and subtract the total dwell from the stream budget.
About 40 lines and two constants; fixes "flashes by" only. Does nothing about stroke domination or
scribble compression, and the viewer's slider would still be in tick space. The fallback if C's
water-filling is judged too much machinery.

## 4. Recommended design (C) in detail

### 4.1 Build the axis once per journal

Extend `FlatJournal` to carry the per-line deltas it currently discards: `deltasMs: Int32List`
(4 B per line; 2.4 MB on a 600k-line epic, transient to the build). Then a single pass, the one
`visiblePositions()` already makes, produces the **timeline**:

```
positions : Int32List   // visible positions, ascending, last == actions.length (as today)
isEvent   : Uint8List   // 1 = event tick, 0 = stream tick
workUs    : Uint32List  // working time accrued to each tick (µs, per-gap clamped)
```

Rules of the pass (per line, in order):

1. `delta = min(deltaMs[i], GAP_CAP_MS)`. The clamp neutralizes pauses, resumes days later, and the
   playback-preview periods whose `AdvanceClock` lines the recorder drops (the next line's delta
   spans them).
2. `acc += delta`.
3. If the line is visible (existing triage): emit a tick at `i+1` with `workUs = acc`; `acc = 0`.
   The tick is a stream tick iff every visible statement on the line is a stream statement
   (`PointerDown`/`PointerMove` under a stamp tool, or held-pen `MoveCursor`); otherwise an event.
   A chapter boundary (base-load pop) is an event.
4. The final position is always a tick (as today); if the tail is invisible churn, its accrued time
   lands on that last tick.

Journals with `Σ workUs == 0` (synthetic scripts, `+0` continuation-only content) fall back to
`workUs = 1` per tick, which reproduces today's uniform pacing exactly. Deterministic integer math
throughout, so the plan can be pinned literally in tests.

Memory: 9 B per tick in typed arrays (positions 4, isEvent 1, workUs 4). A 60k-line serious piece
with ~30k ticks: 270 KB. The 600k-line epic worst case: ~5 MB, on the Dart heap, far from the
Android ~4 KiB allocator class the engine budgets guard. Build cost: the existing pass plus one
addition and one comparison per line; the pass is already O(L) string work and lands in the tens of
milliseconds at 150k lines.

### 4.2 Map working time to video time, per preset

Given the preset `T` (15/30/60 s) and the timeline:

- Stream ticks: `dwell = s · workUs` (linear).
- Event ticks: `dwell = clamp(s · workUs, FLOOR, CEIL)`.
- Find the scale `s` such that `Σ dwell = T`. Stream ticks contribute `s · W_stream` in closed form;
  event ticks are piecewise linear in `s`. Bisection on `s` (≈ 32 iterations over the *event* ticks
  only) or a sorted-breakpoint scan; either way microseconds at realistic event counts.
- Degenerate case: `E · FLOOR > ρ · T` (a journal of 800 bucket fills in a 15 s preset). Reduce
  `FLOOR` to `ρ · T / E` before solving, with `ρ` the maximum share floors may claim. Everything
  then fits and stays proportional.

Output: `cumUs: Uint32List` per tick (cumulative video time, ≤ 60 s fits in 32 bits). The
timeline (§4.1) is preset-independent and built once; only this step reruns when a duration chip is
tapped, and it is O(events).

Proposed starting constants, to be tuned in a phone pass with a real drawing:

| Constant | Value | Why |
|---|---|---|
| `GAP_CAP_MS` | 2000 | Longer than any in-gesture interval, shorter than "went to think"; the 2026-09-06 decision |
| `FLOOR` | max(6 frames, T/100) | 0.2 s minimum for the eye; 0.3 s at 30 s, 0.6 s at 60 s so presets scale together |
| `CEIL` | T/12 | 2.5 s at 30 s: an apply never freezes the video, however long it was tuned |
| `ρ` | 0.6 | Floors may claim at most 60 % of the preset; the rest stays proportional |

### 4.3 Sampling frames and driving the slider

- **Timelapse:** `samplePositions` gains the cumulative axis: frame `f` (time `(f+1)·33,333 µs`)
  shows the tick whose `cumUs` first reaches that instant. One merge pass, O(ticks + frames); the
  result keeps every invariant the existing tests pin (monotonic non-decreasing, last == last tick,
  duplicates legal and cheap under delta encoding). The finale planning is untouched.
- **Viewer:** the slider and the sweep move in **video time** (0..T) instead of tick index; the
  position under the thumb is a binary search over `cumUs`, O(log ticks) per 33 ms tick. A useful
  side effect: scrubbing the viewer previews the exported timelapse frame for frame; the 15/30/60 s
  chips retune both identically.

### 4.4 The burst rule

Runs of identical event verbs with short gaps (24 `NudgeMove` from held arrow keys; 42
`SetActiveFrame` from a film-roll scrub; an undo storm) would each claim `FLOOR`, turning 24 nudges
into 7 s of a 30 s video. Rule: an event tick whose verb equals the previous tick's verb **and**
whose working time is below `BURST_MS` (≈ 300 ms) is paced as a stream tick (no floor, still
capped). The first event of the run keeps its floor, so the change is still registered; the run
then flows at the speed it was performed. This is not an Undo special case (Undo/Redo is otherwise
paced like any event, per the decision); it applies to any repeated verb.

### 4.5 What does not change

- The Journal format, the recorder, the epoch, chapter bases, the visible triage and its oracle.
- The engine, the FFI, the exporter isolate protocol (it still receives a list of entries).
- Pixels: pacing only chooses *which* positions are shown *when*. Re-exporting an old drawing yields
  different timing from a timelapse already published, never different pixels; that is not a
  determinism promise the replay ever made (pacing is presentation, ADR 0015's pixel fork is the
  one that mattered).
- Memory classes: no new engine allocations; the exporter's streaming shape (one upscaled frame in
  flight) is unchanged.

## 5. Consequences worth stating

- **Where the balance comes from.** Two signals, no opinions table: the artist's own hands-on time
  (clamped) decides proportions; a two-class floor/ceiling decides visibility bounds. New verbs need
  no pacing entry; they inherit the visible index's safe default (unknown ⇒ visible ⇒ event).
- **Strokes.** A deliberate line dwells; a scribble compresses; an airbrush pass takes the seconds
  it took. This is the decision "working time everywhere", and it is also the truthful one.
- **Adjustments and drafts.** Tuning time accrues to the apply/commit, bounded by `CEIL`. A Levels
  apply after 40 s of tuning gets 2.5 s at the 30 s preset; after a 1 s tweak it gets the 0.3 s
  floor.
- **Long-idle journals** (resumed across days) and playback-heavy sessions are handled by the same
  2 s clamp; nothing special is needed for chapter boundaries beyond treating the pop as an event.
- **Risks.** The constants in §4.2 are guesses until watched on a phone; the plan is deterministic,
  so tuning is a literal-pin change, not a redesign. The viewer's slider changes semantics (video
  time, not tick index), which touches `replay_page_test.dart`'s sweep and slider expectations.

## 6. As built (2026-09-06)

Shell only, two commits (`bdbfc904` the timeline, `40c63f36` the pacing and the viewer), no engine,
FFI, format, or epoch change. Where it differs from §4 as proposed:

1. `journal_format.dart`: `FlatJournal.deltasMs` (`Int32List`, saturated at the Int32 maximum so a
   month-long pause cannot wrap).
2. `visible_index.dart` kept its name and grew `ReplayTimeline{positions: Int32List, isEvent:
   Uint8List, workMs: Uint32List}` plus `buildTimeline(flat)`; working time is stored in
   **milliseconds** (µs would overflow 32 bits on adversarial churn). `visiblePositions()` remains as
   the wrapper the oracle harness and the old tests use. Stream verbs as built: stamp-tool
   `PointerDown`/`PointerMove`/`Tap` (the Bucket excepted: its every contact is a fill, an event),
   held-pen `MoveCursor`, `CursorPenDown`, `PlotCursor`, `AirbrushCursor`. A scripted whole `Stroke`
   is an event. The always-kept final position is a stream tick (nothing changes there; its dwell
   only extends the last state by the trailing churn's time). The burst rule lives in the builder,
   so `isEvent` already reflects it.
3. `timelapse_plan.dart`: `progressDurationUs(seconds)`, `paceTimeline(timeline, seconds) →
   Uint32List cumUs` (bisection over the event ticks, 60 halvings; the all-saturated events-only
   case scales up to fill the preset), `tickIndexAt(cumUs, us)`, `samplePositions(positions, cumUs,
   samples)`, and `planTimelapse(timeline: …)`. Constants: `kEventFloorFrames = 6`,
   `kEventFloorDivisor = 100`, `kEventCeilDivisor = 12`, floor share 3/5; the builder's
   `kGapCapMs = 2000`, `kBurstMs = 300`.
4. `replay_host.dart` exposes `timeline`; `replay_page.dart` sweeps `_uiUs` one frame per tick over
   `_cum`, the slider spans `progressDurationUs(preset)`, and a chip tap re-paces in place keeping the
   tick on screen (`_adoptSweepSeconds`). `editor_page.replay.dart` passes `host.timeline` to the plan.
5. Tests: `visible_index_test.dart` (classes, accrual, clamp, burst rule, Int32 saturation),
   `timelapse_plan_test.dart` (proportion, floor, ceiling, floor shrink, events-only fill, zero-work
   ticks, a 5,000-tick property check, `tickIndexAt`, sampler invariants, a paced plan), and
   `replay_page_test.dart` (the sweep ends on the final position after exactly the preset; an event
   holds for its floor while streams flow; a chip switch keeps the tick on screen).

Open: the phone light pass at all three presets, then tune the five constants above.
