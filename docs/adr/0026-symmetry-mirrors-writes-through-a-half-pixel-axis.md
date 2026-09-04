# Symmetry mirrors each write through a half-pixel axis; the mask, the gate, and the undo step are never mirrored

**Decided 2026-09-04; not yet implemented** (design: `docs/symmetry/DESIGN.md`). Engine: a
`Symmetry { mode, ax, ay }` in `Settings`, one additive verb `SetSymmetry(mode, ax, ay)`, a fan-out
over the images of every write in the stroke coat, the Pencil path, the figure rasterizers, and the
flood fill. Shell: a row-1 "Mirror" chip, a dashed axis overlay, a transient Move-axis mode, a
mirrored ghost cursor, and the J key. No `.mkpx`, FFI, or journal-format change.

Mirror drawing is in every surveyed pixel-art editor and in none of this engine. Sprites are
bilaterally symmetric far more often than not, and drawing one half is half the work. The question
was never *whether* but *what exactly mirrors*, because the engine already composes several
per-write rules — the selection mask, the pattern gate, AA coverage, the pixel-perfect filter — and
each could be mirrored, or not, independently.

**Symmetry is a property of the write, not of the tool or the document.** One global
`Option`-like mode (Off, H, V, Both) lives in `Settings` beside AA and Pattern: journaled, never
saved in `.mkpx`, Off on every editor open. Every drawing write — a coat dab, a Pencil plot, a
figure raster, a flood fill — is issued once per *image* of its point under the mode, and each
image is then treated exactly like an ordinary write at that coordinate. It is not a document
property because a sprite that reopens with mirroring silently on is the recurring complaint in
competitor reviews; it is not a per-tool setting because a mirror axis is a fact about the
drawing being made, not about the brush in hand.

**The axis is an integer in half-pixel units.** Each direction stores `A` with the reflection
`x' = A − x`; `A` even mirrors through pixel column `A/2`, `A` odd mirrors between two columns.
The canvas center is `A = w − 1`, which is even for odd widths and odd for even widths, so the
between-columns axis that even-width sprites need falls out of the same formula with no special
case. `None` means "centered" and follows every canvas resize; only a user drag makes the axis
explicit, and a shrink clamps it. The axis is in canvas coordinates and meets storage space only
through `doc.origin()`, as the pattern gate does, so the overscan gutter never shifts it.

**Three things are deliberately not mirrored.** The **selection mask** clips every image at its
own coordinate and is never reflected: mirroring inside a left-half marquee paints nothing on the
right, and selections keep behaving like they do for every other tool. The **pattern gate** is
consulted at each image's own coordinate: the two halves are both correct dithers of the same
canvas phase rather than pixel mirrors of each other, preserving ADR 0025's canvas anchoring and
avoiding a phase seam against existing dithered pixels. The **undo step** is one record per
stroke, figure, or fill including all of its images; there is never an "undo the mirrored half".

**Overlap at the axis is resolved by coverage, never by blending twice.** Coat writes already
max-combine (ADR 0007), so a stroke that crosses its own mirror never darkens and AA rims stay
exact. Figures, which today blend straight into the layer, gain a coverage map: the primary and
reflected figures raise coverage by max, then one pass composites, and the draft preview uses the
same map so preview equals commit per pixel. The flood fill computes the region of every seed
image against the pre-fill buffer and writes the union once, because a second flood after the
first write would see a half-dithered region and behave erratically. The Airbrush speck hash uses
the canonical image of the pixel while symmetry is on, so its mirror is pixel-exact rather than
merely equal in density. The Pencil applies its pixel-perfect filter to the primary path and
mirrors each resulting plot or restore, capturing pre-stroke colors on first touch across all
images so a restore is always the true pre-stroke color.

**Repeat reads the live symmetry.** Unlike the pattern, which `RepeatOp::Bucket` freezes at the
tap ("same region, same dither"), the mirror mode is read at repeat time (user decision): Repeat
is "fill again, the way I am drawing now".

Alternatives rejected:

- **A document property saved in `.mkpx`.** Reopens with mirroring on; and the axis is a
  drawing-session aid, not part of the artwork.
- **Mirroring the selection mask.** Makes selections behave differently from every other tool
  the moment a mode is on; users who want both halves select both halves.
- **Mirroring the gate coordinate.** A pixel-exact mirrored dither, at the cost of a Bayer phase
  seam against everything already dithered on the far side.
- **Pixel-center-only axes.** Simpler to explain, but an even-width sprite could not be mirrored
  through its true center, which is the common case.
- **A whole-figure second raster blended over the first.** One line of code, and a darker AA
  fringe on the axis where the two figures overlap.
- **Freezing the mode in the Repeat snapshot.** Consistent with the pattern, but the user's
  model of Repeat here is "the same fill under my current settings".
- **A "Symmetry" tool tile or a hamburger entry.** Both hide a mode that is toggled mid-stroke;
  the shared row-1 chip beside AA is where the artist's thumb already is.

Consequences: `PaintCtx` carries the resolved symmetry; `StrokeCoat::dab` fans out; the figure
commit and preview paths share a coverage map; `flood_fill` unions regions from several seeds;
`pencil_perfect_segment` keeps a first-touch color map. Any *future* write path must decide
explicitly whether it mirrors (drafts, Gradient, Outline, and Replace color do not). New Rust pins
cover the odd/even center, an axis pixel written once, the figure overlap, the unioned flood, and
the canonical speck; the 24-hash AA-OFF pin suite must not move. Diagonal and rotational symmetry
extend the mode enum additively when wanted.
