# AA edges for round Brush, shape tools, and round Eraser — design

**Status: designed 2026-08-15 (grilling session), NOT implemented.** The decision record is
ADR 0008; vocabulary ("Anti-alias (AA)") is in `CONTEXT.md`. Implementation waits for an
explicit go.

## What

A single **AA toggle** that switches the governed tools from hard pixel-stepped edges to
fractional-coverage ("perfectly anti-aliased") edges:

- **Governed:** round Brush, Line, Rectangle, Ellipse, Triangle, round Eraser.
- **Forever-no list (explicit):** Pencil, Bucket, Gradient, and the Square brush stay hard.
  These are different machinery (Pencil is the precision instrument; Bucket/Gradient edges are
  separate features that were considered and declined).
- **One shared engine flag**, not per-tool: a new `SetAA(bool)` DSL verb and one session
  setting consumed by every governed tool. Default **OFF**; the Flutter shell persists the
  choice across restarts like other tool options. The UI is an "AA" chip in each governed
  tool's options row, hidden while the Brush is in Square mode.

## Coverage model

Fixed supersampling, chosen over analytic exact coverage (one code path for all primitives,
trivially integer-deterministic; visually identical at 8-bit):

- Every candidate pixel in the **edge band** of a primitive tests a **16×16 integer subgrid**
  (257 coverage levels — effectively exact at 8-bit) against a per-primitive **inside-test
  predicate**; interior pixels skip straight to full coverage. Predicates are closed forms:
  disc `dx²+dy² ≤ r²`, thick line = squared distance to segment, rect = bounds, ellipse =
  implicit equation — each composed with the existing inverse-rotation transform for rotated
  shapes.
- **All arithmetic is integer/fixed-point** (the det_* doctrine). The rotated
  Rectangle/Ellipse/Triangle path is the one place this needs real work — the current rotation
  path is float-based, and AA subsampling through it must not fork goldens per platform.
  Rotated shapes are **in scope for v1**: an AA toggle that dies on rotation would feel broken,
  and rotated edges are where AA pays off most.
- Coverage multiplies into the color's alpha (`coverage ⊗ color.a`); there is no separate
  opacity knob.
- **Size-1 round Brush is an AA no-op** — it stays one hard pixel. Softening the precision
  dot (a 1px disc covers ~78% of its own pixel) was rejected.
- **Selection edges hard-clip.** The mask is 1-bit and applies at write time; an AA gradient
  crossing the marquee cuts off exactly at the mask edge. Fractional (8-bit) masks were
  declined as a separate, much larger project. Selections stay pixel-exact by design.

## How strokes land

- **Brush:** AA rides the single-coat model (ADR 0007) as its natural completion. Rim pixels
  write fractional coverage into the per-stroke coat instead of 255; **max**-combine along the
  path yields drag-speed-independent edges, and preview/commit stay bit-identical for free.
- **Eraser joins the coat unconditionally** (AA on or off) — see ADR 0008. Today's erase is an
  idempotent `set(x, y, TRANSPARENT)`, so moving hard erase onto a max-coverage coat is
  **pixel-identical**; the new work is (a) an erase resolve arm in `StrokeCoat::resolve` and
  (b) an **erase-aware coat preview** — the display-time overlay must punch the coat's coverage
  *out of* the layer (before its blend mode/opacity) rather than compositing paint over it.
  With this, Pencil becomes the only direct-write paint tool.
- **Shape tools:** the shared preview/commit rasterizer path gains coverage-aware plots
  (`plot(x, y, cover)`), blending `color ⊗ cover` in both `render_shape_preview` and the
  commit. Axis-aligned un-rotated Rect edges are naturally unaffected (their coverage is
  binary) — that is correct behavior, not a bug.

## What does not change

`.mkpx` format (AA only changes pixel values), the FFI seam, the server contract, and Club
publish — Post-to-Club always exports lossless WebP/PNG, never GIF (note: the CLAUDE.md line
saying "animated→GIF" is stale and should be corrected).

Known texture costs, accepted: AA introduces off-palette rim shades, so palette extraction and
Select Color / Bucket thresholds behave less predictably on AA edges, and INDEXED/RLE tile
encodings compress worse (bigger `.mkpx`, less tile-dict dedup). The toggle defaulting OFF is
the mitigation.

## Companion fixes (ship with or before AA)

1. **GIF export: threshold + tell.** The `gif` crate promotes **any alpha 1–254 to fully
   opaque** (no 128-threshold, no matte) — already a silent, shipped bug for Soft/Mist
   airbrush; AA would widen it. Fix per the decision already written in
   `docs/animator/01-features-landscape.md`: threshold alpha at 128 in the GIF export path and
   notify the artist that semi-transparent pixels were flattened. (Matting over a background
   via the existing `flatten_over_bg` was declined: it needs "over what color" UI and destroys
   intended transparency.)
2. **Journal replay line-skip.** An unknown verb currently aborts the **entire remainder of
   its up-to-2000-action replay batch** (`run_script` stops at the bad line;
   `replay_host.dart` only logs). Change replay batching so an unknown verb drops **only its
   own line**. Keep the `#mkpxj 1` header — a bump would make old apps reject whole journals
   including AA-free ones — and document that forward replay (old app, newer journal) was
   never guaranteed; with the fix it degrades to divergence (edges replay hard) instead of
   mass truncation. This helps every future verb, not just `SetAA`.

## Risks and sequencing

- **Coat regression risk:** Mist/Dots were feel-tuned 2026-08-15 and that device feel pass
  gates a release. Threading coverage and an erase mode through `resolve` touches the same
  machinery — **sequence AA after the Mist feel pass closes**, and lean on the golden suite.
- **Determinism risk** concentrates in the rotated-shape subsample transform (fixed-point,
  never libm/float).
- **Feel risk at small canvases:** on 16–32px art AA reads as blur; default-OFF and artist
  judgment are the mitigation.
- **Scope-creep pressure:** AA Pencil/Bucket/Gradient/fractional selections will be asked
  for; the forever-no list above is the pre-agreed answer.

## Cost estimate

Engine: predicates for disc/thick-line/rect/ellipse/triangle (× rotated variants),
coverage-aware plots, fractional coat writes, the erase resolve + erase-aware preview,
`SetAA` parsing, goldens/probes — roughly the size of the airbrush-modes feature (8–15
focused commits). Flutter: one persisted toggle chip + sending `SetAA` (small). Runtime and
memory costs are negligible (edge-band-only subgrid tests; one canvas-sized u8 coat per live
Eraser stroke, inside the Android budgets).
