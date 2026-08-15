# Single-coat strokes over a max-coverage buffer; Spacing removed

**Decided 2026-08-15 during the non-accumulating-strokes grilling. Not yet implemented** — this
ADR records the decision ahead of the code; the full survey is
`docs/nonaccumulating-strokes/ANALYSIS.md`.

The stamp-accumulative stroke engine (each stamp composites `Over` on top of earlier stamps in
the same stroke, metered by the Spacing setting) is replaced by **single-coat strokes**: per
stroke, dab coverage is combined into a scratch coverage buffer with **max**, not blend, and the
stroke applies to the layer once. Repainting inside one stroke never deepens; lifting and
stroking again lays another coat. Spacing is removed entirely — the setting, the row-1 slider,
and the DSL surface — because max-composition makes over-stamping visually free: dabs land at
every path pixel and there is nothing left for a spacing knob to control. All four spacing
families convert: Brush, Airbrush (Dots/Soft/Mist), Dodge/Burn (visited-once per stroke).
Pencil and Eraser are untouched.

The model is **purely geometric**: a stroke's pixels are a function of its path polyline and the
settings captured at stroke start — never of speed, wall-clock, or event rate. Consequences that
were each their own decision:

- **Settings freeze at stroke start.** The coverage buffer holds one alpha per pixel and
  composites with one color, so mid-stroke `Set*` lines (reachable via multitouch and via
  journals) apply from the next stroke. Alternatives — splitting the stroke per settings change
  (quietly reintroduces accumulation) and retroactive recolor — were rejected.
- **Dots/Mist become a position-hashed speckle field** (integer hash of pixel + a per-stroke
  seed drawn once from the session RNG), revealed where the stroke's footprint passes. Both
  modes get density falloff with distance to the path (Dots' specks stay hard and opaque; only
  density feathers). Linger-density is gone by design; density is controlled by Intensity and by
  repeated strokes, whose fresh seeds union into denser fields. Time-based dab clocks were
  rejected (wall-clock in a deterministic engine breaks replay).
- **Preview is a display-time overlay** (revised later on 2026-08-15, reversing the grilling's
  first pick of in-place recompose): the document layer stays pristine until the stroke commits.
  Renderers composite `color ⊗ coverage` into the layer stack at the stroke's layer position —
  before that layer's blend mode and opacity apply — and **every pixel-reading surface**
  (`mkpx_display`, thumbnails, probes, Watch replay scrubbing, Timelapse sampling) must include
  the live overlay so in-progress strokes remain visible. The in-place-recompose alternative
  (recomputing pixels from the undo snapshot per event) had the smaller audit surface but was
  rejected for its couplings: it made the undo snapshot load-bearing for preview and gave the
  stroke ownership of its footprint (clobbering concurrent mid-stroke journal edits to the same
  layer). The overlay keeps the undo snapshot single-purpose, composes concurrent edits
  naturally, and pays the compositor-injection + cross-surface-audit price up front. The overlay
  stays bound to its frame/layer by id [audit F-29].
- **The stroke is the coat unit**: pointer-down→up; in precision mode, one drag segment of the
  held pen (matching its per-segment undo), with the pen-down Hold dab a one-dab stroke; a tap
  is a degenerate stroke of one full-strength dab. Square brush sweeps as the union of
  axis-aligned squares (the direct analog of stamping).
- **`SetSpacing` is a permanent no-op verb.** Journals fossilize DSL names (the ADR 0006
  doctrine): deleting the verb would hard-fail every pre-change Replay with a parse error. The
  Journal version header does NOT bump — the format is unchanged, and the accepted breakage is
  semantic: pre-change Journals replay with divergent pixels (and a shifted RNG stream), which
  is announced as a breaking change rather than warned about in the viewer.
- This **supersedes the flow-style buildup** noted for Soft in ADR 0006: a Soft stroke now caps
  at Intensity, and buildup toward opaque happens across strokes. Intensity's meaning per mode:
  Soft — the stroke's peak alpha; Dots/Mist — speck density; Dodge/Burn — shift magnitude
  (unchanged).

The Krita/Photoshop opacity+flow dual-knob model was rejected as replacing one confusing knob
with two — but the coverage buffer is exactly the substrate a future Flow control would need, so
this decision opens that door rather than closing it. Build proceeds in one pass across all four
families; the pre-agreed contingency for the Dots/Mist feel risk is to tune on device until
accepted — the release waits on the feel pass, with no architectural retreat.

Vocabulary (Single-coat stroke, Stroke, the Soft/Mist/Dots rewrites, "pass" = whole stroke) is
in `CONTEXT.md`.
