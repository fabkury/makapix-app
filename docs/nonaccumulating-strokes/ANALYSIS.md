# Non-Accumulating Strokes — Removing the Spacing Parameter

**Status: analysis only — nothing here is implemented.** Written 2026-08-15. Neutral survey in the
style of `docs/hdr/ANALYSIS.md`; no go/no-go verdict is taken here.

> **2026-08-15, later the same day:** the design was grilled decision-by-decision and settled —
> the outcome is **ADR 0007** (`docs/adr/0007-single-coat-strokes.md`), which supersedes this
> doc's open questions (§8) and adjusts one row of §2.2 (Dots gained distance falloff). The
> canonical term is **single-coat strokes**; vocabulary is in `CONTEXT.md`.

Decisions fixed by the product owner before this analysis (they scope everything below):

- **Scope:** all four spacing tool families go non-accumulating — Brush, the Airbrush family
  (Dots / Soft / Mist), and Dodge/Burn. The Spacing parameter disappears entirely: settings, DSL
  surface, row-1 slider. Not pinned — removed, with an engine that has no use for it.
- **Model:** purely geometric. A stroke's final pixels are a function of the stroke path polyline
  and the settings — never of speed, wall-clock time, or pointer-event rate. Hovering in place adds
  nothing.
- **Compatibility:** breaking change, announced as such. Replay divergence on pre-change Journals
  is accepted (the user base is small and cooperative).

---

## 1. What Spacing is today, and why it exists

`ToolSettings::spacing` (`crates/engine/src/tool.rs`, default 25, clamp 1–1000) is the stamp
distance as a percent of brush size. `Session::brush_step()` converts it to pixels;
`spaced_points()` interpolates stamp centers along each pointer segment, carrying the fractional
remainder in `paint_acc` so stamping stays even across segments. Four consumers:
`brush_stroke_spaced`, `airbrush_stroke_spaced`, `dodge_burn_stroke_spaced`, plus the precision
(reticle) path, which reuses all three. Pencil and Eraser are continuous and have no spacing.

Spacing exists because the stroke engine is **stamp-accumulative**: each stamp composites `Over`
(or value-shifts) on top of what earlier stamps in the same stroke already deposited. Without a
minimum stamp distance, a translucent Brush would saturate instantly and Dodge/Burn would blow out
along the path. Spacing is the metering valve for that accumulation — which is exactly why it
confuses users: it is a parameter of the *implementation* (stamp density), not of any artistic
intent, and its visible effects (dotted trails at high values, darkening on scrub-back, results
that depend on how the slider interacts with brush size) all read as bugs.

## 2. The target model: max-coverage stroke buffer

**Definition of non-accumulating:** within one stroke (pointer-down to pointer-up), repainting a
pixel never deepens it. The stroke as a whole applies to the layer *once*, as if it were a single
shaped stamp. Buildup remains available by lifting and stroking again.

### 2.1 Core mechanism

Per stroke, the engine keeps a scratch **coverage buffer** `C` — one `u8` alpha per pixel over the
storage extent (canvas + gutter). Every stamp/dab writes into it with **max**, not blend:

```
C[p] = max(C[p], dab_coverage(p))
```

Max-composition is the key move: it makes over-stamping *visually free*. Dabs can be laid at every
path pixel (1 px steps) with no over-deposit, so the spacing knob has nothing left to control and
simply ceases to exist. Dense max-stamping of a radial falloff profile converges to the exact
distance-to-path envelope — `max over centers of f(|p − c|)` = `f(dist(p, path))` — so "stamp
densely into a max buffer" and "compute distance to the polyline" are the same result; the former
is the trivial implementation.

The layer receives the stroke by compositing `color ⊗ C` **once**, at pointer-up. Until then the
document layer stays pristine, and live preview is a **display-time overlay**: renderers
composite `color ⊗ C` into the layer stack at the stroke's layer position — before that layer's
blend mode and opacity apply. Every pixel-reading surface (display, thumbnails, probes, Watch
replay scrubbing, Timelapse sampling) must include the live overlay, or in-progress strokes
vanish from it; that audit is the up-front price of the cleaner model (decided in the grilling —
see ADR 0007, which also records the rejected in-place-recompose alternative that would have
reused the undo snapshot as a preview baseline). Undo is untouched: `commit_edit` diffs against
the `begin_edit` snapshot as always, and that snapshot stays single-purpose.

### 2.2 Per-tool semantics after the change

| Tool | Today | After |
|---|---|---|
| **Brush** | `Over` stamps at spacing steps; translucent color overlaps and darkens at stamp intersections and on scrub-back | Coverage = `color.a` inside the swept footprint (union of discs/squares along the path = a stroked capsule). One stroke = one flat `Over` application of the color across the swept region. Opaque color: visually near-identical to today at low spacing. Translucent color: uniform, no overlap darkening. |
| **Airbrush Soft** | Deterministic radial dab, `Over`-accumulating (flow-style buildup toward opaque, ADR 0006) | Coverage = smoothstep falloff of distance to the path, peak = `Intensity ⊗ color.a`. A stroke is one smooth capsule-shaped gradient — no stamp artifacts, no dotted trails, speed-invariant. A single stroke caps at Intensity; deeper needs another stroke. |
| **Airbrush Dots** | RNG specks per dab, density grows with dab count (motion-driven) | **Position-hashed speckle field**: per stroke, one seed is drawn from the session RNG; pixel `p` is a speck iff `hash(x, y, seed) < density`, where density comes from Intensity and falls off with distance to the path (decided in the grilling — specks stay hard and opaque; only density feathers). The stroke *reveals* the field where its footprint passes. Scrub-back shows the same specks (idempotent); a new stroke re-rolls the field. |
| **Airbrush Mist** | RNG faint center-weighted specks per dab, accumulating | Same speckle-field mechanism with fainter speck alpha and density falling off with distance to the path. |
| **Dodge / Burn** | Value shift per stamp, accumulating along the path and on scrub-back | **Visited mask** (1 bit/pixel): each pixel is shifted at most once per stroke — the classic Photoshop behavior. No coverage math needed; no recompose (shift on first visit, skip after). |

**Intensity's meaning becomes clean:** Soft — the stroke's max alpha; Dots/Mist — speck density;
Dodge/Burn — shift magnitude (unchanged); Brush — unused (color alpha rules), unchanged.

**Precision (reticle) mode:** the pen path commits per drag segment (`cursor_stroke_begin/end`),
so there the non-accumulation unit is the segment — consistent with "lift = new application."

### 2.3 Memory and determinism

- Coverage buffer: `u8` over the 3w×3h storage extent = **576 KiB worst case** (256² canvas +
  gutter); Dodge/Burn visited mask = 72 KiB. Allocated at stroke start, dropped at commit.
  Negligible against the Android budgets (`docs/memlab/REPORT.md`); no COW/tiling needed.
- Determinism: smoothstep is polynomial; distance uses `sqrt` (IEEE-exact, already used by
  `soft_dab`); the speckle hash is integer. No libm transcendentals — the `det_*` doctrine is
  satisfied. The speckle field consumes **one RNG draw per stroke** instead of a draw per speck,
  which is *more* robust under replay (fewer sequencing dependencies), though the stream change is
  itself part of the break with old journals.

## 3. Pros

1. **Kills the least-understood parameter.** Row 1 loses a slider on four tools; nothing replaces
   it. The remaining knobs (Size, Intensity, Shape) each map to visible intent.
2. **Idempotent scrubbing** — the top user surprise today ("why did it get darker?") disappears
   across all four families.
3. **Soft mode becomes genuinely better, not just simpler:** a smooth distance-field gradient with
   clean capsule ends, immune to stamp-overlap artifacts and dotted trails at any speed.
4. **Speed and event-rate invariance.** Output depends on the polyline geometry only. (Today's
   model is also geometric, but sparse stamping amplifies polyline chatter; dense max-stamping is
   insensitive to it.)
5. **Industry-aligned semantics.** Per-stroke opacity (Photoshop's default brush behavior) and
   once-per-stroke Dodge/Burn are what users arriving from other editors expect.
6. **Deletes real complexity:** `spacing`, `brush_step`, `spaced_points`' accumulator carry,
   `paint_acc` resets in three places, and their test surface.
7. **Future-proof substrate.** A per-stroke coverage buffer is the standard architecture under
   opacity/flow separation (Photoshop, Krita). If a Flow control is ever wanted, it slots in as
   "accumulate into `C` with a cap" — the opposite migration (bolting a stroke buffer onto stamp
   accumulation later) is the expensive direction. This change is not a one-way door; it opens
   the door.
8. **Deterministic mist/dots goldens** become trivial (hash field vs. RNG call sequences).

## 4. Cons

1. **In-stroke buildup dies as an expressive technique.** Lingering the airbrush to deepen a spot,
   layering a translucent Brush against itself, deepening Dodge in one pass — all now require
   lifting the finger between applications. This is the artistic cost, and it is the *point* of
   the change, but some users may miss it.
2. **Dots/Mist change character.** The scatter becomes a revealed fixed field: scrubbing over the
   same area shows the *same* specks ("frozen noise"), and density no longer grows with lingering.
   Matching the current organic feel is a tuning problem with no guarantee of a perfect match.
3. **A new engine subsystem** (per-stroke scratch state + overlay compositing across the render
   surfaces) where today there is fire-and-forget stamping. More invariants to hold (see risks).
4. **Breaking change surface:** Watch-replay and Timelapse of every pre-change Journal render
   differently (accepted up front). The divergence is not limited to the four tools' pixels — the
   changed RNG consumption pattern shifts every later RNG-dependent action in an old journal too.
5. Small permanent memory cost per active stroke (≤ 0.6 MiB, transient).

## 5. Costs (implementation sizing)

| Work item | Size | Notes |
|---|---|---|
| Stroke-buffer infrastructure (scratch `C`, display-time overlay compositing injected at the stroke layer's stack position across every render entry point, lifecycle on both pointer and precision paths) | **M/L** | The core of the change; touches `pointer_down/move/up`, `move_cursor`, `cursor_stroke_begin/end`, and the render/probe surfaces (display, thumbnails, probes, replay/timelapse sampling). |
| Brush + Soft coverage (max-stamp of footprint / falloff profile) | S | Reuses `raster::disc/square`; profile math ≈ current `soft_dab`. |
| Dots + Mist speckle field | **M** | The mechanism is small; **the look is the work** — density curves, speck alpha, falloff tuning until it feels right on device. |
| Dodge/Burn visited mask | S | Strictly simpler than today. |
| Settings/DSL removal; `SetSpacing` kept as a parse-accepted **no-op verb** | S | See R2 — the verb must not be deleted outright. |
| Shell: remove the Spacing slider, `_spacing` state, persistence | S | `editor_page.controls.dart` + settings plumbing. |
| Tests: retire ~6 spacing tests, add coverage/idempotence/determinism goldens, update `tools/replaylab` vocab + generator | M | `session.rs` tests, `fuzz_inputs.rs`, `vocab_check.txt`, `gen_replay_script.py`. |
| Docs: SPEC §11, ADR (next number), What's New breaking-change note | S | |
| QA: feel pass on Android + iPhone + Windows, replay spot-checks | M | Calendar cost more than effort; the Dots/Mist feel loop may iterate. |

Total: roughly **one focused week**; the schedule risk is concentrated in Dots/Mist tuning.

## 6. Risks

- **R1 — Feel regression in Dots/Mist (highest).** The hashed-field texture may read as static or
  synthetic next to today's event-driven scatter. Mitigation: tune density/falloff against
  side-by-side captures; accept that per-stroke reseeding restores variety across strokes; be
  willing to iterate post-release with the small user base.
- **R2 — Old journals must not hard-fail.** Journals contain `SetSpacing(…)` lines; if the verb is
  removed from `parse.rs`, replay of every old journal *errors out* (a far worse outcome than
  pixel divergence). Mitigation: keep `SetSpacing` as an accepted no-op indefinitely. Cheap, and
  distinct from the accepted visual divergence.
- **R3 — Overlay correctness and coverage.** Every pixel-reading path must composite the live
  overlay at the right point in the layer stack (before the layer's blend mode and opacity), or
  in-progress strokes silently vanish from thumbnails, probes, and replay/timelapse renders; the
  selection mask, paint clip, and the mid-stroke frame/layer-switch guard [audit F-29] all apply
  at overlay-composite time. Mitigation: one composite helper shared by every render entry
  point; goldens that sample mid-stroke and stroke across selection edges and the gutter.
- **R4 — Determinism.** New float math (distance, falloff) must stay byte-identical across
  platforms. Mitigation: polynomial + `sqrt` only, integer hash, cross-platform golden hashes in
  CI (the existing `hash:` probe infrastructure).
- **R5 — User expectation of buildup.** Mitigation: What's New explains "lift to layer"; multi-
  stroke buildup still composes exactly as before across strokes.
- **R6 — Perf.** Dense max-stamping is O(path · brush area) byte-max writes into a flat buffer;
  at 256² with the F-6 pointer clamp already bounding path length, this is far below the existing
  per-event work. Low risk.

## 7. Alternatives excluded by the premise

- **Pin Spacing internally, keep accumulation:** hides the slider but keeps every accumulation
  artifact (scrub darkening, overlap patterns). Explicitly out of scope — the premise is an engine
  that does not need spacing to exist.
- **Time-based airbrush (dab clock):** real-airbrush feel, but injects wall-clock into a
  deterministic engine — replay would need dab-tick journaling. Rejected by the "purely geometric"
  decision.
- **Opacity + Flow dual knobs (Krita/PS model):** the stroke buffer with *capped accumulation*
  instead of max. Strictly more expressive, but replaces one confusing knob with two. Noted only
  as the natural future extension the chosen substrate already supports (Pro #7).

## 8. Open questions — RESOLVED (grilling of 2026-08-15; see ADR 0007)

1. Dots/Mist density: Intensity maps to speck density; **both** modes fall off with distance to
   the path (Dots' specks stay hard/opaque, only density feathers). Density workflow = Intensity
   + repeated strokes (fresh seed per stroke; fields union).
2. Square brush: **union of axis-aligned squares** along the path.
3. Speckle seed: drawn from the session RNG at stroke start — sufficient, with the invariant that
   every stroke start consumes exactly one draw on both live and replay paths.
4. Eraser (and Pencil): **no change.**

Also settled there: settings freeze at stroke start; preview = **display-time overlay** (the
document layer stays pristine until commit; every render surface composites the live stroke —
revised from the grilling's first pick of in-place recompose); `SetSpacing` = permanent no-op
verb; no journal version bump; build all four families in one pass, tune Dots/Mist on device
until accepted. Canonical term: **single-coat strokes** (`CONTEXT.md`).
