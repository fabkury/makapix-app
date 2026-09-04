# Patterns are a canvas-anchored paint gate, not a brush: ON bits paint, OFF bits are untouched

**Decided 2026-09-03; implemented 2026-09-04** (design and as-built notes: `docs/patterns/DESIGN.md`).
Engine: a `Pattern` bitmask (≤ 16×16 on the wire, the catalog ≤ 8×8) in `Settings`, verbs
`SetPattern(w,h,hexbits)` / `SetPattern(off)` and
`SetGradientDither(n)`, gates in `tool::plot`, `StrokeCoat::raise`, `tool::flood_fill`, and a
threshold branch in `gradient_color_at_sorted`. Shell: a "Pattern" swatch at the end of row-1 on
Pencil/Brush/Eraser/Bucket/Gradient, a Patterns page with a built-in catalog and a recents strip.
No `.mkpx`, FFI, or journal-format change.

Pixel artists dither: two colors interleaved in a Bayer or checker arrangement stand in for a third.
Every surveyed competitor offers it in one of two shapes — a dedicated dither *brush* that paints
two colors, or a *mask* that lets any tool paint only where a repeating tile says so. The two are
not equivalent: a brush can only add, while a mask composes with whatever the tool already does
(erase, fill a region, respect a threshold), and it composes with what is already on the canvas.

**A pattern is a gate.** The engine keeps one global `Option<Pattern>`; at write time a pixel is
painted only if the selection admits it *and* the pattern bit at that canvas coordinate is ON. OFF
bits are never touched — no second color, no transparent write. Two-color dithers are two strokes
with complementary tiles, and the catalog carries every inverse so that costs one extra pick.
The gate is anchored to the **canvas origin**, never to the stroke or to storage space, so
overlapping strokes tile seamlessly and the overscan gutter does not shift the phase. No offset or
scale control exists: a phase mismatch after a resize-canvas or a move is accepted, as in Aseprite.

**Per-tool On/Off lives in the shell; the engine holds only what is in force.** The shell resolves
"this tool has the pattern On" and re-pushes `SetPattern(...)` or `SetPattern(off)` on every tool
switch through the same `_pushToolSettings` block that re-pushes Size and Shape — the block the
replay baseline shares, so live and replayed sessions can never disagree. The journal records the
tile's bits, not a catalog name: the catalog is a UI convenience that may be renamed, reordered, or
extended, and a future custom pattern needs no new verb.

**Three rules keep the gate honest with the tools it composes with.** AA is inert while a pattern
is on (the engine drops it in `open_coat`, the shell greys the chip): fractional coverage through a
dither is meaningless, and a hard edge is what the artist asked for. Pixel-perfect runs first: the
Pencil thins the unmasked line and the mask drops OFF bits at write time, so the corner-double
filter stays purely geometric. The Bucket's region ignores the gate: threshold, contiguity, and the
"All layers" reference decide the region exactly as before, and only the writes inside it are
masked, so a dithered fill still covers the whole shape.

**The Gradient is the one place a pattern is not a gate.** A dithered ramp is not "a gradient
painted through holes" — it is two adjacent stop colors chosen per pixel by comparing the eased
blend fraction against a Bayer threshold. So the Gradient keeps its own `dither ∈ {0, 2, 4, 8}`,
offers only the three Bayer families, and never reads the global pattern. Smoothstep still shapes
the fraction before thresholding; the output is exactly one of the two stop colors, alpha included.

Alternatives rejected:

- **A new "Pattern brush" tool tile.** One more row-3 tile and one more row-1 to keep coherent,
  and it cannot erase, fill, or respect a Bucket threshold — the compositions that make a mask
  worth having.
- **OFF bits paint a second color.** True two-color dithering in one stroke, but useless for
  texturing over existing art, and it would need a second color slot the UI does not have.
- **Stroke-anchored phase** (the first pixel always paints). Friendlier for a size-1 tap, but
  overlapping strokes stop tiling, which defeats the purpose of a pattern.
- **Recording a catalog id in the journal.** Shorter lines, but the catalog would become a frozen
  replay contract.
- **Fully global On/Off**, or **fully per-tool pattern memory.** The first forces a toggle every
  time the artist reaches for the Eraser to clean up; the second multiplies persisted state and
  makes the page's "current" ambiguous. One global pattern with per-tool On/Off is the Aseprite
  convention and the smallest state that avoids both.

Consequences: `tool::plot`, `StrokeCoat::raise`, and `tool::flood_fill` gain a gate argument, and
any *future* write path that paints through the primary color must thread it too (Line/Shape,
Airbrush, Dodge/Burn are explicitly out of v1 and set `ctx.pattern = None`). A size-1 tap that lands
only on OFF pixels paints nothing (and, under the engine's standing empty-edit rule, records no undo
step). New Rust pins (a dithered gradient
hash, a masked pixel-perfect elbow) join `aa_off_pins.rs`'s doctrine: a moved pin is the bug. Old
apps replay a journal with these verbs by dropping the unknown lines — the documented cost of any
additive verb — so no `#mkpxj` bump (ADR 0015 bumps only on a semantics fork).
