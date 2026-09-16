# Brush stamps are exactly Size pixels wide; even sizes lean +x/+y and mirror by leaning the other way

**Decided and implemented 2026-09-16.** Engine: `raster::Span` (the per-axis stamp window) with
`stamp_disc` / `stamp_square` / `stamp_disc_aa` (`crates/engine/src/raster.rs`),
`tool::Footprint` and `Mirror::stamps` (`crates/engine/src/tool.rs`), the stamp families' dab in
`coat.rs` and the Pencil's `stamp_active` / `stroke_active` in `session.rs`. Shell: the eraser and
cursor footprint outline in `editor_page.engine.dart`; the Journal epoch is 4
(`replay/journal_format.dart`). Pins: `aa_off_pins.rs` `brush_square4` and `symmetry.rs`
`brush_aa_both` re-pinned — the only two goldens that moved, both even sizes.

**The defect.** The Pencil, Brush, Eraser, Dodge, and Burn stamp turned the Size setting into a
radius, `r = (N − 1) / 2` in integer math, and painted the centered window `−r ..= r`, which is
always odd. Every even size therefore collapsed onto the odd size below it (the Round shape also
clamped `r` to at least 1, so size 2 joined 3 and 4), the slider's 32 sizes produced 17 distinct
footprints, and a 32-px brush was unreachable. The Line tool's Width and the outline stroker had
the same collapse and were fixed on 2026-06-29 (`thick_line`, commit 1be4bf34) by stamping an
exact `t × t` block; the brush stamp was left on the odd-only rule, so the engine carried two
conventions for the same word.

**The rule.** A stamp of Size `N` covers, along each axis, the window `lo = −(N − 1) / 2 ..= hi =
N / 2` around the anchor pixel — `Span::of(N)` — so every unit of Size adds exactly one pixel.
Odd `N` is the centered window as before. Even `N` has no center pixel: the anchor (the pixel
under the finger or reticle) is the top-left of the central 2×2, and the extra column and row
land toward +x/+y, the `thick_line` convention.

- **Square:** the full window.
- **Round, odd `N`:** pixel centers within `r = (N − 1) / 2` of the anchor, `dx² + dy² ≤ r²` — byte-
  identical to every pre-ADR stamp, which is why no odd-size golden moved.
- **Round, even `N`:** measured from the window's center, which sits on a pixel corner. In doubled
  units `u = 2dx − (lo + hi)`, `v = 2dy − (lo + hi)` (odd integers): `u² + v² ≤ N² − N`, i.e. centers
  within `N/2 − 1/4` of the corner. The quarter-pixel tightening keeps the even discs as "pointy" as
  the odd ones (a loose `N/2` would make size 8 cover more pixels than size 9); areas grow
  monotonically: 1, 4, 5, 12, 13, 24, 29, 44, 49, …
- **Round with AA (ADR 0008):** the continuous disc of diameter `N` around the window center — a
  pixel center for odd `N` (the pre-ADR `disc_aa`, byte for byte), a pixel corner for even `N` —
  so the silhouette is exactly `N` wide.
- **Size 1** stays the single hard pixel, AA or not (ADR 0008's explicit no); pixel-perfect Pencil
  is still defined only there.

**Symmetry (ADR 0026).** An even stamp is not symmetric about its anchor, so a mirrored copy that
kept the +x/+y lean would land one pixel off a true reflection. `Footprint::reflected` flips the
window along every axis the reflection flips (`lo, hi → −hi, −lo`), and `Mirror::stamps` pairs
each image of the anchor with the footprint leaning the same way, deduplicated by the pixel window
it covers. On an axis through a pixel column the two leaning stamps union into the symmetric
result (a size-2 tap on the axis paints 3×2); on an axis between two columns the reflection covers
the same pixels and is written once. Odd sizes reduce to the plain images. The shell's ghost
outline needs nothing new: it reflects the primary's cells, which is exactly the flipped footprint.

**Replay.** Pre-fix Journals with even-size strokes replay one pixel narrower than they were
recorded. Per ADR 0015 nothing branches on the epoch; the `#mkpxj` marker bumps 3 → 4 so the
boundary is recorded, and every past epoch stays readable (the header-recognition test covers 1–4).
The user base was small enough to take the fork rather than gate the engine.

**Rejected.** *Offering only odd sizes, or relabeling the slider as a radius*: honest, but it takes
2-px and 4-px brushes away from pixel artists. *Biasing even stamps toward −x/−y*: an equal
choice on its own, but it would diverge from the Line tool's Width. *Loose even discs (`N/2`
from the corner)*: the natural continuous rule, but at the pixel level it fills more than the next
odd size. *Keeping the +x/+y lean under every reflection*: simplest, and visibly wrong on an axis.
*Epoch-gated stamp geometry in the engine*: ADR 0015 already declined that shape of fix.

**What did not change.** Odd sizes, the airbrush family (its footprint was already `radius =
size`), the figure tools (Line Width was fixed in 1be4bf34), the Size slider's 1–32 range, the
`SetBrushSize` verb, and the `.mkpx` format.
