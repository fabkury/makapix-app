# Non-accumulating ("one-pass") Brush — feasibility analysis

**Status: analyzed, NOT committed.** No implementation exists or is scheduled; this document
records the proposal, the measurements taken during analysis, and the pros/cons/costs/risks so the
work can be picked up (or declined) later without redoing the investigation. Analyzed 2026-08-15
against the code as of commit `f748367`; the `file:line` references below are from that revision.

## The proposal

A Brush whose translucent paint **does not build up within a single stroke**. Passing the brush
over the same pixel twice without lifting the finger leaves it at the same tone as one pass; to go
darker you must release and stroke again. This is the "opacity-not-flow" brush familiar from
Photoshop (Opacity with Airbrush/build-up off), Krita ("Wash"/alpha-locked-per-stroke), Clip Studio
Paint, and Procreate.

The current Brush is the opposite (build-up / flow): every stamp composites `Over` onto whatever is
already there, including paint laid down microseconds earlier by the same stroke.

## Current behavior, measured

Runs against `mkpx` at `f748367`, canvas 32×32, `SetPrimaryColor(#FF000080)` — a **50 % alpha**
red — round Brush, size 8, default `SetSpacing(25)`. Scripts in the analysis scratch; each is a
handful of `PointerDown/Move/Up` lines.

| Gesture (one stroke, finger never lifted) | Alpha the user asked for | Alpha actually painted |
|---|---|---|
| Single tap | 128 (`0x80`) | **128** (`0x80`) ✔ |
| Straight drag, pixel at the middle of the trail | 128 | **224** (`0xE0`) |
| Straight drag, pixel under the first/last stamp | 128 | **192** (`0xC0`) |
| Three passes back and forth over the same span | 128 | **255** (`0xFF`) — fully opaque |
| Same, one pixel off the trail center | 128 | **252** (`0xFC`) |

Two things fall out of the table:

1. **A translucent tone is unreachable by any stroke longer than a tap.** With `spacing` at its
   25 % default a size-8 brush stamps every 2 px, so consecutive discs overlap by ~70 % and each
   pixel is composited 3–4× on a straight pass. Scrubbing saturates to opaque within about three
   passes. This is exactly the complaint the proposal addresses.
2. **A single "flat" pass is not flat.** 224 in the middle vs 192 at the ends (the ends get fewer
   overlapping stamps) — a translucent stroke has darker seams and lighter ends today.

The same over-plot exists in a **single-shot** tool: a translucent `Line` at `SetLineWidth(4)`
lands at alpha **240** instead of 128, because `raster::thick_line` (`crates/engine/src/raster.rs:38`)
sweeps a `t×t` block along every Bresenham step and re-plots each pixel several times. Outline
shapes and triangle corners (`stroke_polyline`, `raster.rs:61`) have the same property. Whatever
mechanism fixes the Brush fixes these for free if it is wired to them.

Pencil and Eraser are unaffected: `Replace` and `Erase` are idempotent by construction
(`tool::plot`, `crates/engine/src/tool.rs:269-283`).

## Why it's cheaper than it sounds

**The pre-stroke state of the layer is already captured, for free, at the start of every stroke.**
`Session::pointer_down` calls `begin_edit()` (`crates/engine/src/session.rs:1178`), which stores
`l.pixels.snapshot()` in the `Stroke` — and `RgbaBuffer::snapshot()` is a single `Arc` clone of the
tile table (`crates/engine/src/buffer.rs:357`). The COW tile divergence it forces already happens
today. The precision-pen path has the same thing in `precision_before`.

So "composite this stamp over the layer **as it was when the finger went down**" needs no new
buffer, no new snapshot, and no extra copy — only a way to *read* the snapshot from the paint path.

**For the Brush as it exists, base-compositing is exactly equivalent to non-accumulation.** Every
pixel of a Brush stamp receives the identical `(color, alpha)` — the disc/square footprint is
hard-edged, no antialiasing (`tool::stamp`, `tool.rs:286`). When every deposit at a pixel has the
same alpha, "keep the maximum coverage" and "let the last deposit win over the pre-stroke value"
produce the same bytes. The distinction only matters for soft-edged dabs (see Option B).

## Design options

### Option A — composite against the pre-stroke snapshot (recommended)

A new `PaintMode::OverOnce`. `plot` takes an extra `base: Option<&RgbaBuffer>`; in `OverOnce` the
destination pixel is read from `base` instead of from the live buffer, then written:
`buf.set(x, y, over(color, base.get(x, y)))`. Repeated application is idempotent, so overlap,
scrubbing, and stamp density stop mattering.

- The `base` is built from the stroke's existing snapshot with a new
  `RgbaBuffer::from_snapshot(w, h, Arc<TileTable>)` constructor — an `Arc` clone, no allocation.
- The `Option<&RgbaBuffer>` reference parameter mirrors `tool::flood_fill`'s existing
  `reference: Option<&RgbaBuffer>` for Bucket "All layers" (`tool.rs:335`) — same shape, same
  borrow pattern (the base is a locally owned buffer, disjoint from the `&mut` into `doc`).
- **Memory: zero.** **Extra per-pixel work: one tile lookup.**
- Blast radius is small: `plot` has ~12 call sites inside `tool.rs` and 3 in `session.rs`.

### Option B — a stroke-scoped coverage map

Keep a `Vec<u8>` of per-pixel maximum coverage for the current stroke;
`cov[p] = max(cov[p], dab_alpha)`, then write `over(color·cov[p], base[p])`.

- Needed **only** if the footprint's alpha varies within a dab — i.e. if this is ever extended to
  Airbrush Soft (`tool::soft_dab`, `tool.rs:516`) or to a future antialiased brush. With Option A,
  two overlapping soft dabs give "last dab wins", so a low-alpha rim would visibly erase a
  high-alpha core; the max-coverage rule is what fixes that.
- Cost: one canvas-sized `Vec<u8>` — **64 KiB at the 256×256 maximum** (the paint clip is
  canvas-only, `Session::paint_clip`, `session.rs:1290`, so the gutter needs no coverage).
  Negligible against the Android budgets in `docs/memlab/REPORT.md`, and it can live as a lazily
  allocated, reused `Session` field rather than churning per stroke.

Recommendation: **ship A; keep B in the file** as the upgrade path the day a soft or antialiased
brush wants the same behavior. A is a strict subset of B's semantics for hard-edged stamps, so
moving A → B later does not change any golden.

### Option C — a separate stroke layer composited on top

The classic implementation in layer-based paint programs. **Rejected**: it would duplicate the
active layer per stroke (up to 2.25 MiB at 256×256 storage), require a display-time compositing
path the engine does not currently need (`mkpx_display` today reads the real document), and buy
nothing that A/B don't — the engine already writes directly into the layer and re-composites per
pointer event, so there is no preview machinery to build.

## Where the mode lives: a ToolKind, not a setting

Follow **ADR 0006** (`docs/adr/0006-airbrush-modes-as-toolkinds.md`): a new `ToolKind` — say
`BrushOnce` — grouped under the existing Brush tile by a row-1 chip, exactly as Dots/Soft/Mist are
grouped under the Airbrush tile (`editor_page.controls.dart:216-221`, `_airbrushMode` →
`_engineToolName` in `editor_page.engine.dart:576`).

A `ToolSettings.brush_buildup` flag with a `SetBrushBuildup(bool)` DSL verb is the obvious
alternative and should be rejected for the same reason ADR 0006 rejected it for the airbrush:
`_pushToolSettings()` (`editor_page.engine.dart:557`) re-pushes all 11 settings lines on **every**
tool switch and is deliberately shared with the replay baseline, so a settings flag adds one
journaled line per tool switch of every tool, forever. A ToolKind rides the `SelectTool(...)` line
that is already emitted — zero added journal traffic.

It also keeps a live invariant intact: `ToolKind::paint_mode()` (`tool.rs:57`) is the single,
settings-independent source of the Pencil→Replace / Brush→Over / Eraser→Erase mapping
[audit F-20]. `BrushOnce → OverOnce` extends that table; a settings flag would make it
settings-dependent.

**The DSL name `Brush` must keep meaning build-up.** Names are fossilized by replay — every
recorded journal would re-render differently if `Brush` changed semantics. Non-accumulation has to
arrive under a new name (or, if it is ever made the shell default, the shell picks `BrushOnce` for
new sessions while `Brush` keeps replaying as it always did).

## Pros

- **Delivers a tone the editor currently cannot produce at all.** Today the only way to paint a
  flat 50 % wash wider than one stamp is a sequence of taps, or paint-then-lower-the-layer-opacity.
- **Makes "alpha" mean what the color picker says it means.** The picker's alpha slider
  (`dialogs/color_picker_dialog.dart:320`) currently sets a *rate*, not a *result*, for any stroke
  longer than a tap.
- **Removes the darker-seam/lighter-end artifact** from translucent strokes (224 vs 192 above) —
  a translucent pass becomes genuinely uniform, which is what pixel artists doing shading passes,
  glazes, and soft shadows want.
- **Costs nothing at rest.** No `.mkpx` format change, no new persisted state, no memory growth,
  no new invisible pixel states. Contrast `docs/eraser-unerase/ANALYSIS.md`, whose comparable
  feature carried a format-semantics commitment and a privacy leak.
- **Deterministic and integer-exact.** Both options are pure integer arithmetic over the existing
  `color::over`; goldens stay byte-identical across platforms and replay is unaffected
  (SPEC §25 invariants preserved).
- **Fixes the translucent thick-Line/outline over-plot** (alpha 240 instead of 128, measured
  above) at no extra engineering cost, if `OverOnce` is also offered to the shape tools.
- **Precedent is fresh and load-bearing.** The Airbrush-modes work landed yesterday
  (`64862ee`) and established every pattern this needs: the mode chip, the ToolKind grouping,
  the `_engineToolName` indirection, the ADR.
- **Cheap to make opt-in**, so it forks no existing behavior and no existing test.

## Cons

- **Two brushes that look identical in the tool grid.** Discoverability rests entirely on a row-1
  chip; a user who leaves the chip on One-pass and forgets will find that scrubbing "doesn't get
  darker" and may read that as a broken brush. The Airbrush's Dots/Soft/Mist chip has the same
  exposure and is the mitigation model.
- **It is a mode on the same tool, so it is sticky per session.** Same foot-gun class as the
  eraser Un-erase proposal, though far milder — nothing is destroyed, and the fix is one more
  stroke.
- **The stroke boundary is not one thing in this engine.** Pointer strokes
  (`pointer_down`→`pointer_up`), precision pen lines (`cursor_pen_down`→`cursor_pen_up`), and
  precision **Hold** drags (`cursor_stroke_begin`/`cursor_stroke_end` per drag,
  `session.rs:1996-2013`) are three different scopes. Hold in particular commits *each drag* as
  its own edit while the finger stays down — so under a literal "one edit = one stroke" rule,
  paint would still build up between drags of a single Hold session. Defensible (a drag is the
  gesture), but it needs a decision and a documented answer.
- **Two brush behaviors to explain** in the tool help strings (`editor/tools.dart:100+`), the
  README/STATUS feature table, and any tutorial content.
- **It does not generalize to Dodge/Burn as written.** Those tools scrub-accumulate far more
  aggressively than the Brush (each pass re-shifts the value channel), and users hit it sooner —
  but they mutate rather than composite, so they need the "already touched this stroke" variant
  (a 1-bit `Mask`, which the engine already has) plus a base read. Adjacent, not free.

## Costs

- **Engine (Option A): small — roughly 100–150 lines plus tests.**
  - `PaintMode::OverOnce` + the `base` parameter threaded through `plot` → `stamp` →
    `stroke_segment` (~15 call sites, all mechanical).
  - `RgbaBuffer::from_snapshot` (an `Arc` clone).
  - `ToolKind::BrushOnce` added to `paint_mode()`, `commits_stroke()`, `parse_tool` (`parse.rs:411`),
    and the three `ToolKind::Brush` dispatch arms (`session.rs:1353`, `:1479`, `:1948` — pointer
    press, pointer drag, precision-reticle drag). The precision *pen* path needs nothing: it reads
    the `paint_mode()` table through `cursor_paint()` (`session.rs:1909`).
  - `Session::stamp_active`/`brush_stroke_spaced` gain the base lookup from `stroke.before` /
    `precision_before`.
- **The one non-mechanical engine detail: resolving the base.** `commit_edit` deliberately resolves
  the snapshot's *own* frame/layer by id, not the currently active one, because the DSL may switch
  layers mid-stroke (`session.rs:1190-1200`, [audit F-29]). The base lookup must do the same and
  fall back to the live buffer (i.e. behave like `Over`) when the stroke's layer is no longer the
  active one. Small, but it is the one place a naive implementation is wrong.
- **UI / Dart: routine, ~30 lines.** A row-1 two-way chip on the Brush, one state field, the
  `_engineToolName` mapping (copy of `_airbrushMode`), a tooltip line in `tools.dart`, and the DSL
  name in the replay vocabulary list (`editor/replay/visible_index.dart:116+`).
  **No new icon** — the mode shares the Brush tile, so the `tools/icons/` generation pipeline is
  untouched.
- **Tests: light, and almost entirely additive.** Because the mode is opt-in under a new ToolKind,
  no existing golden, scenario, or roundtrip changes. New coverage wanted: idempotence under
  repeated passes, equality of "one tap" vs "scrub" alpha, spacing-independence, interaction with
  a selection clip and with the gutter clip, mid-stroke layer switch fallback, and a CLI example
  script (`examples/`) for the harness. Compare this to the eraser proposal, where test churn was
  the largest single line item — here it is close to zero.
- **Docs:** an ADR recording the ToolKind-vs-setting choice and the fossilized-`Brush`-name rule;
  a `STATUS.md` row; SPEC §11.1 wording for the new paint mode; a README/What's-New line.
- **Option B, if taken:** add ~half a day for the coverage map, its lifecycle (allocate on
  `pointer_down`, clear cheaply, drop or retain on `pointer_up`), and its own memory line in the
  budget accounting.

Rough total for Option A end to end, engine + shell + tests + docs: **about a day**, with the
mid-stroke-layer-switch case and the Hold-mode decision being the only places to slow down.

## Risks

- **Journal fossilization is the one hard rule.** Changing what `Brush` means re-renders every
  recorded session in the replay/timelapse feature (`docs/replay/ANALYSIS.md`). Low risk *if* the
  new behavior arrives under a new DSL name; a silent default change is a data-integrity bug, not
  a preference.
- **Semantic creep toward the airbrush.** If Option A ships and the Soft airbrush later wants
  non-accumulation, "last dab wins" will produce rim-erases-core artifacts and the fix is Option B.
  Cheap to avoid by writing the coverage-map upgrade path down now (this document) rather than
  discovering it from a bug report.
- **Users will ask for it on the other tools.** Eraser (partial-alpha erase does not exist yet),
  Dodge/Burn (the strongest candidate), the shape tools (already measurably wrong at width > 1).
  The proposal is naturally the thin end of a wedge; that is not a reason to decline it, but the
  end state — a general "one pass per stroke" property of the paint layer — should be a conscious
  destination rather than four separate one-offs.
- **"One pass" is not a universal definition.** Photoshop's Opacity-without-Airbrush, Krita's Wash,
  and Procreate's per-stroke alpha lock differ in corner cases (what happens when the stroke
  crosses a *previous* stroke's semi-transparent paint, what a soft rim does over a hard core).
  Picking one and documenting it matters more than which one is picked; the base-snapshot rule
  ("composite once against the layer as it was when the gesture began") is the simplest one to
  explain and the easiest to keep deterministic.
- **No risk found in:** file format, memory budgets, Android's ~1 GiB allocator wall, undo/redo
  (unchanged — one record per stroke), Club publish/export, cross-platform determinism, or
  save/load roundtrip. This proposal touches none of them.

## Open decisions before implementing

1. **Naming.** Engine `ToolKind` (`BrushOnce`? `BrushWash`?) and the shell chip label
   ("Build up / One pass"? "Flow / Opacity"?). The DSL name is permanent once journaled.
2. **Default.** Opt-in (chip defaults to Build up, zero behavior change) vs. shell-default
   One-pass for new sessions. Opt-in is the low-risk start; the second is a UX call.
3. **Hold-mode stroke scope** — does a precision Hold session re-base per drag (proposed) or per
   Hold?
4. **Scope beyond the Brush** — offer `OverOnce` to the shape tools now (fixing the measured
   width-4 line at alpha 240), or keep this strictly a Brush feature?

## Bottom line

This is a cheap, low-risk, well-precedented feature by this repo's standards. It needs no format
change, no memory, no new persisted state, no golden churn, and it lands on top of a mode-grouping
pattern that shipped yesterday. The measurements say the gap it fills is real: a 50 % brush is
unusable as a 50 % brush the moment the stroke is longer than a tap, and three scrubs make it
opaque.

Three things drive the go/no-go, and none of them is a blocker:

1. keep the DSL name `Brush` meaning build-up (**mandatory**, cheap);
2. decide the Hold-mode stroke scope and write it down;
3. accept that Dodge/Burn and the shape tools will be asked for next, and decide whether the
   destination is a general per-stroke idempotence property or a single Brush mode.
