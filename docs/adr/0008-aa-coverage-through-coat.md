# AA as supersampled coverage through the stroke coat; Eraser unifies onto the coat

**Decided 2026-08-15 during the AA grilling; NOT yet implemented** — the full design is
`docs/aa-brush/DESIGN.md`, and vocabulary ("Anti-alias (AA)") is in `CONTEXT.md`.

An **AA toggle** gives round Brush, Line/Rectangle/Ellipse/Triangle, and round Eraser
fractional-coverage edges. Edge pixels get coverage from a **16×16 integer subgrid** tested
against per-primitive inside predicates — supersampling was chosen over analytic exact area
(one code path for every primitive, trivially integer-deterministic, indistinguishable at
8-bit; 257 levels make "perfectly anti-aliased" literal). All math is integer/fixed-point,
including through the rotated-shape inverse transform (in scope for v1), so goldens never
fork. Decisions that were each their own trade-off:

- **AA lands through the ADR 0007 stroke coat.** Rim pixels write fractional coverage instead
  of 255; max-combine makes edges independent of drag speed and keeps preview == commit
  bit-identical. In-stroke accumulation of AA rims (direct writes) was rejected — edge quality
  would depend on pointer event rate.
- **The Eraser moves onto the coat unconditionally**, AA on or off — chosen over an
  only-when-AA split. Today's hard erase is idempotent (`set TRANSPARENT`), so the unification
  is pixel-identical for existing behavior; the price is an erase resolve arm plus an
  erase-aware display-time preview (the overlay punches coverage out of the layer instead of
  compositing paint over it). Pencil becomes the only direct-write paint tool.
- **One shared `SetAA(bool)` flag**, not per-tool flags: one verb, one journal line, one
  persisted UI state (default OFF). Per-tool memory was rejected as contract surface without a
  demonstrated need.
- **Boundary no-s:** Pencil, Bucket, Gradient, and Square brush stay hard forever; a size-1
  round Brush stays a hard pixel (AA no-op); AA hard-clips at the 1-bit selection mask
  (fractional masks declined as a separate project). Triangle is IN — it shares the shape
  rasterizer path and its absence would read as broken.
- **Two companion fixes ride along** (both pre-existing holes AA would widen): GIF export
  thresholds alpha at 128 **and tells the artist** (today the `gif` crate silently promotes
  alpha 1–254 to opaque — a shipped Soft/Mist bug; Club publish is unaffected, it exports
  WebP); and journal replay skips an unknown verb's **single line** instead of aborting the
  remaining ~2000-action batch (the `#mkpxj 1` header does not bump — forward replay was never
  guaranteed and now degrades to divergence, not truncation).

Sequencing: after the open Mist feel pass closes, since the erase/coverage work touches the
just-tuned coat resolve.
