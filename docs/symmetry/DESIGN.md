# Symmetry (mirror drawing) + Replace color + Outline — design

**Decided 2026-09-04** in a grilled design interview (every decision below is the user's; the
assumptions are marked). **Not implemented.** Doctrine: ADR 0026. Source list: A1, A4, A5 of
`docs/editor-gaps/INVENTORY.md`. This is the headline of the next editor release after 1.9.0
(Patterns); Replace color and Outline ride along as two small tools.

Terminology used throughout: **"H" mirrors left ↔ right**, so its axis is a *vertical* line at
`x = A/2`; **"V" mirrors top ↔ bottom** across a *horizontal* line at `y = A/2`; **"Both"** is H
and V together and yields **four** copies of every write (the fourth is the point reflection).

## What it is

**Symmetry** is an editor setting that makes every drawing write land twice (H or V) or four
times (Both), reflected through a movable axis. It applies to Pencil · Brush · Eraser · Airbrush
×3 · Dodge/Burn · Bucket · Line · Shape and to nothing else. A row-1 **Mirror** chip cycles the
mode; a dashed axis line shows on the canvas; a transient **Move axis** mode drags the axis in
half-pixel steps. One journal verb, no `.mkpx` change, no FFI change.

**Replace color** recolors every pixel within a tolerance of one color to another, over the layer,
the frame, or all frames. It lives in the row-2 swatch's long-press sheet as "Replace in artwork…".

**Outline** draws a 1–4 px ring outside or inside the opaque pixels of the active layer in the
primary color. It is a tool tile with row-1 chips and an **Apply** button.

## Decisions (2026-09-04)

### Symmetry

| Question | Decision |
|---|---|
| Which tools | **Pencil, Brush, Eraser, Airbrush ×3, Dodge/Burn, Bucket, Line, Shape.** Not Gradient, Move/Paste drafts, Select tools, Eyedropper, Ruler, adjustments, Flip/Rotate/Resize, Outline |
| Where the setting lives | **Session setting** in `Settings`, like AA and Pattern: journaled, never in `.mkpx`, **Off when the editor opens**; the axis is session-only too |
| Modes | Off · H · V · Both. Both = four copies (assumption) |
| Axis model | One integer `A` per direction in **half-pixel units**; reflection `x' = A − x`. Center = `w − 1` (exact for odd and even canvases). Clamped to `0 … 2(w − 1)` |
| Axis and resizes | `None` = **centered**, follows every Resize/Crop/Trim; explicit only after a drag, clamped when the canvas shrinks |
| Pattern gate | Mirrored pixels pass the gate **at their own coordinate** (the dither is not mirrored; ADR 0025 canvas anchoring stands) |
| Airbrush specks | **Pixel-exact mirror**: the speck hash uses the canonical coordinate (the lexicographically smallest image) while symmetry is on |
| Selection | The mask **clips every write and is never mirrored** |
| Figures (Line, Shape) | Reflect endpoints, negate the rotation, reflect the Triangle tip; commit both figures through **one coverage map** (max-combined at the axis, never double-blended); the draft preview shows both; ratio lock and Shift-constrain apply to the primary figure only |
| Bucket | A flood from **every image of the seed**, regions decided against the pre-fill buffer, written once. **Repeat re-reads the live symmetry** (it does not snapshot mode or axis) |
| Undo | **One record** per stroke, figure, or fill including its mirror |
| Journal | One additive verb **`SetSymmetry(mode, ax, ay)`**, a settings verb hidden from the visible step index like `SetPattern`; axis drags record **on release only** |
| Control | Shared **row-1 "Mirror" chip** on every honoring tool. **Tap cycles Off → H → V → Both → Off.** Label: "Mirror" · "Mirror H ✔" · "Mirror V ✔" · "Mirror H+V ✔" in the row's green chip while on |
| Long-press menu | Off · H · V · Both (direct picks) · **Move axis…** · **Recenter axis**; the two axis items enabled only while a mode is on, Recenter also disabled while centered |
| Axis overlay | **Dashed 1 dp line** in a hue no other overlay uses, only the active axes, **hidden during playback** |
| Move axis | Transient mode: **one finger anywhere drags the axis by the delta**, half-pixel snap, the **Slow** chip gears it, two-finger view gestures kept, a fingertip handle at the axis midpoint (intersection for Both) with **tap-to-type** in canvas pixels ("15.5"), arrow keys nudge ½ px (assumption); exit via the chip or a tool switch |
| Cursor | **Mirrored ghost cursor** (dimmer) on all stroke tools, a second crosshair in Precision mode; act-by-button still fires one stroke |
| Keyboard | **J** = a "Mirror" Command that cycles like the chip; on a tool without the chip it still cycles and shows a toast with the new mode |
| Pencil | Mirror applied **after** the pixel-perfect filter to every plotted or restored pixel (assumption); pre-stroke colors captured on first touch per pixel across all images |

### Replace color

| Question | Decision |
|---|---|
| Verb | **`ReplaceColor(from, to, scope, tolerance)`**, scope ∈ layer · frame · all; tolerance 0–255 with the **Bucket metric** (`color::max_channel_delta` over RGBA, assumption: same metric as Bucket) |
| Entry | The row-2 swatch's long-press sheet: **"Replace in artwork…"**. Not on the palette page, not on Select-by-color, no tool tile (may follow) |
| Dialog | From = the swatch's color · To = the **primary** (action disabled when equal) · **Tolerance slider** · scope segmented **Layer / Frame / All frames**, default Layer |
| Transparency | **Allowed on both sides**: from-transparent fills empty pixels, to-transparent erases a color |
| Selection | **Clips all scopes** (the same mask on every frame) |
| Layers | Frame / All frames touch **editable layers only** (visible and unlocked — the engine's standing rule) |
| Undo | **One record**, even across frames |
| Repeat | **Repeatable**: `RepeatOp::ReplaceColor` with from, to, scope, tolerance frozen |

### Outline

| Question | Decision |
|---|---|
| Verb | **`Outline(color, side, corners, width)`**, side ∈ outside · inside, corners ∈ round (4-connected) · square (8-connected), width 1–4 |
| Surface | **Tool tile** with a **Material icon**, placed **right after Bucket**; a generated painter may replace the icon later |
| Row 1 | **Side** Outside/Inside · **Corners** Round/Square · **Width** stepper `− N +` (1–4) · **Apply** button; the canvas is inert (as under Flip/Invert) |
| Color | The primary |
| Scope | The **current frame's active layer**; a selection **clips the ring** (source alpha = the selected pixels); no All-frames in v1 |
| Gate / mirror | **Not pattern-gated** (like Line/Shape), **not mirrored** |
| Locked or hidden layer | No-op in the engine, the shell toasts (assumption, matching other refused writes) |
| Undo / Repeat | **One record**; **repeatable** with side, corners, width, color frozen |

### Documentation

One design note (this file) for all three; **ADR 0026** for the symmetry doctrine only.

## The model

`Settings.symmetry = Symmetry { mode: SymMode, ax: Option<i32>, ay: Option<i32> }` in canvas
coordinates. Resolution at write time, per direction:

```
A  = ax.unwrap_or(w − 1).clamp(0, 2·(w − 1))        // half-pixel units; None = centered
x' = A − x                                          // H image of column x
```

`A` even ⇒ the axis runs through pixel column `A/2` (that column is its own image); `A` odd ⇒
the axis runs between columns `(A−1)/2` and `(A+1)/2`. The center `A = w − 1` is even for odd
widths (through the middle column) and odd for even widths (between the two middle columns), so
no odd/even special case exists anywhere. `Symmetry::images(p) -> impl Iterator<Point>` yields the
distinct images of `p` under the mode (1, 2, or 4 points; a point on the axis has fewer). Images
outside the canvas are dropped by the existing clip. The **canonical** image is the
lexicographically smallest, used only by the Airbrush speck hash.

Everything is in canvas coordinates and converted to storage through `doc.origin()` at the write
site, exactly as the pattern gate does; the gutter never shifts the axis.

## Engine

**Verb.** `SetSymmetry(mode, ax, ay)` — `mode` ∈ `off | h | v | both`, each axis an integer or `c`
(centered). `SetSymmetry(off)` is accepted as shorthand. Parse in `session/parse.rs`; stored in
`Settings`; joins the settings list in `replay/visible_index.dart` so it is not a visible step.

**Stroke tools (coat).** `open_coat` copies the resolved symmetry into `PaintCtx`.
`StrokeCoat::dab(sel, p)` becomes a fan-out over `images(p)` of today's single-point footprint;
`segment` is unchanged (it calls `dab` per line pixel). Overlap at the axis resolves by the
existing max-coverage rule (ADR 0007), so AA rims stay exact and a stroke crossing its own mirror
never darkens. `speck(x, y, c)` hashes the canonical image while symmetry is on. Dodge/Burn and
the Eraser ride the same coat. The display-time coat overlay previews the mirror for free.

**Pencil.** `pencil_perfect_segment` keeps its geometry on the primary path: the corner filter
decides *which* pixels are plotted or restored, and each decision is then applied to every image
of that pixel, each image passing the pattern gate and the selection at its own coordinate.
Pre-stroke colors are captured **on first touch per pixel across all images** (a small per-stroke
map), because a mirrored path can touch a pixel before the primary path reaches it; a restore
always writes the true pre-stroke color.

**Figures.** `draw_shape` / `shape_cover_aa` already emit `(x, y[, cover])` plots. Both the commit
path and `render_shape_preview` route those plots into one **coverage map** over the union
bounding box: the primary figure and each reflected figure (endpoints reflected, rotation negated
for H or V, kept for the point reflection, Triangle tip reflected) raise coverage by max, then one
pass composites `cover_color` per pixel. Preview == commit per pixel, as ADR 0007 requires, and the
axis overlap is never blended twice.

**Bucket.** `flood_fill_with` computes the region for **every image of the seed against the
pre-fill buffer** (threshold, contiguity, and the "All layers" reference exactly as today), unions
the regions, and writes once through the gate. Computing against the pre-fill buffer matters: a
second flood run *after* the first write would see a half-dithered region and behave erratically.
`RepeatOp::Bucket` is unchanged; `repeat()` reads `settings.symmetry` live.

**Undo.** The coat commit is one record already; the figure coverage map commits as one record;
the unioned fill is one record. The standing empty-edit rule applies unchanged.

**Replace color.** `ReplaceColor(from, to, scope, tol)`: for each targeted frame, for each
*editable* layer (`visible && !locked`; scope `layer` = the active layer only), for each pixel in
the selection (or the canvas), if `max_channel_delta(px, from_premul) <= tol` write `to_premul`.
`from` and `to` are straight palette colors and are premultiplied before the comparison and the
write, since buffers store premultiplied RGBA. One history record for the whole operation.
`RepeatOp::ReplaceColor { from, to, scope, tol }`. A content verb: a visible replay step.

**Outline.** `Outline(color, side, corners, width)` on the active layer of the current frame when
editable: `mask` = alpha > 0 (∩ selection when present); **outside** ring = `dilate^width(mask) \
mask`, **inside** ring = `mask \ erode^width(mask)`, with the 4- or 8-neighborhood chosen by
`corners`; the ring ∩ selection ∩ canvas clip is written with the premultiplied color in Replace
mode. Tile-local, deterministic, no gate, no mirror. One record. `RepeatOp::Outline { color, side,
corners, width }`. A content verb: a visible replay step. Neither rider adds a Rust `ToolKind`
(Flip and Invert set the precedent: shell-named tools driving verbs).

## Shell

**State.** `_symMode`, `_symAx`, `_symAy` on `EditorPage` (`editor_page.controls.dart`), sent as
one `SetSymmetry` on every change and included in the session **baseline push** so a replayed
session starts equal to the live one. Not persisted: Off with a centered axis on every editor open.

**Chip.** `addMirrorChip()` next to `addAaChip()`, shown for the honoring tools only. Tap cycles
Off → H → V → Both → Off; long-press (right-click on desktop) opens a menu: Off · H · V · Both ·
Move axis… · Recenter axis. Label and green ✔ as decided. The chip is also the exit from Move-axis
mode.

**Overlay.** `SymmetryAxisPainter` in `widgets/painters.dart`: dashed 1 dp line(s) at `A/2`
canvas units in a hue unused by the ruler (cyan), selection (marching), and grid; drawn above the
grid and onion, below the cursor; skipped while `_playing`. In Move-axis mode it also draws the
fingertip handle (ADR 0011-style ring, 20–32 px) at the midpoint of a single axis or the
intersection for Both.

**Move-axis mode.** `_movingAxis` in `editor_page.canvas.dart`: a one-finger drag anywhere moves
the axis by the drag delta in half-pixel steps (through the ADR 0020 gearing helper when Slow is
on); two fingers pan/zoom as usual; tapping the handle opens the tap-to-type dialog (the Resize
sliders' pattern) in canvas pixels, e.g. `15.5`; arrow keys nudge by ½ px. `SetSymmetry` is sent
on release (and once per typed value); the journal never sees intermediate drags. Exit: the chip
tap, or any tool switch.

**Ghost cursor.** `CursorOutlinePainter` gains the image offsets and paints the same edges at each
image at reduced opacity (reflected, so a square brush's outline is exact). Precision mode paints
a second crosshair at the image of the reticle; the act button still emits one stroke.

**Keyboard.** A `CommandDef` "Mirror" bound to **J** in `keyboard/default_bindings.dart`
(J and Q were the unbound letters), listed in the cheat sheet and the Keyboard page; when the
current tool has no Mirror chip the command still cycles and a toast names the new mode.

**Replace color.** The swatch long-press sheet gains "Replace in artwork…" opening a dialog: two
`AlphaSwatch`es (from = the swatch, to = the primary), a Tolerance slider (0–255, the Bucket
metric wording), a Layer / Frame / All frames segmented control (default Layer), and a Replace
button disabled while from == to. Sends one `ReplaceColor(...)`.

**Outline.** `ToolDef.custom('Outline', Icons.<stock border icon>, 'Outline')` after Bucket in
`tools.dart` (the hidden-tools sheet picks it up in catalog order). Row 1: Side and Corners as
two-state chips, the Width `− N +` stepper (the Gradient count stepper's pattern), and an **Apply**
`_miniBtn` that sends `Outline(primary, side, corners, width)`. The canvas is inert under Outline,
like Flip and Invert. Refused writes (locked or hidden layer) toast.

## Edge-case policy (all decided; listed so nobody re-litigates them mid-implementation)

- **A pixel on the axis** has fewer images; it is written once. With Both and an even/odd mix the
  center pixel is still written once.
- **Images outside the canvas** are clipped like any write; an axis dragged to the edge makes the
  mirror land mostly off-canvas, which is accepted (clamping keeps the axis itself on the canvas).
- **Selection**: mirroring inside a left-half marquee paints nothing on the right. Never mirror
  the mask.
- **Pattern gate**: the two halves are correct dithers of the same canvas phase; they are not
  pixel mirrors of each other. AA stays inert while a pattern is on (ADR 0025).
- **Airbrush** mirrors pixel-exactly via the canonical coordinate; Intensity and the seed are
  unchanged. Re-seeding still changes both halves together.
- **Bucket "All layers"** builds its reference once; every seed image floods against it.
- **Repeat** after changing the mode fills with the *new* symmetry (user decision, unlike the
  frozen pattern). The Repeat label stays "Fill".
- **Move, Paste, Gradient drafts** never mirror; a mirrored paste is Copy → Flip → Paste.
- **Playback** hides the axis; the chip stays.
- **Precision act-by-button** fires one engine stroke; the engine mirrors it. The reticle and its
  image are both drawn.
- **Replay** of an old journal never encounters `SetSymmetry`, so nothing changes; a new journal
  replays byte-identically because the mode, axis, and every write are in the verb stream.
- **Replace color with from == to** is a no-op and the dialog disables the button; from-transparent
  with tolerance 0 matches exactly `(0,0,0,0)` premultiplied.
- **Outline outside** on content touching the canvas edge is clipped there (no auto-grow).
  **Inside** with a width ≥ the content thickness recolors the whole shape; expected.
- **Outline under a tight selection**: the ring is clipped by the mask, so an Outside ring needs a
  selection with room. Consistent with every other write.

## Out of scope for v1 (documented follow-ups)

- Diagonal and rotational (N-fold) symmetry; a mirrored marquee; mirrored Paste.
- Persisting the axis per drawing (a sidecar) or in `.mkpx`.
- Replace color on the palette page ("edit recolors the artwork"), on Select-by-color, or as a tool
  tile; a Replace-all-frames-of-one-layer scope.
- Outline over all frames; drop shadow (the same op with an offset); a generated icon painter.
- Alpha lock (A3) — offered and declined for this release.

## Effort

Symmetry engine **M** (verb, coat fan-out, canonical speck, Pencil first-touch map, figure coverage
map, unioned flood; new pins) · Symmetry shell **M** (chip + menu, painter, Move-axis mode, ghost
cursor, J) · Replace color **S** · Outline **S**. About a week for the three, plus the marketing
slide and a device pass.
