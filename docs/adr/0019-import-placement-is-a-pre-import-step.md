# Import placement is a pre-import step, never an editor Draft

**Decided 2026-09-01.** Engine: `ImportConfig.placement` + `place_origin` / `set_clipped` in
`crates/engine/src/import.rs`, the `(place, place_x, place_y)` tail on `mkpx_import` /
`mkpx_import_decoded`. Shell: `PlacePage` + `PlaceGeometry` + `importPlacedSize` /
`placementApplies` in `app/lib/editor/dialogs/place_dialog.dart`, the shared decoded preview
`RasterPreview` (`raster_preview.dart`), and the flow in `editor_page.fileio.dart`.

Imported rasters used to land centered, always. Artists composing a sprite or an animation
against existing art had to import, then Move — with no way to see the result first. The request
was "drag an import draft around the canvas and see its result before committing".

**The placement happens on a page before the engine imports, and the import commits once, with
an offset.** The engine gained exactly one concept: an explicit top-left, in canvas pixels, that
replaces the centered anchor of the crop-rect and Fit paths (Stretch fills the canvas and ignores
it). Off-canvas placement is allowed — the outside is clipped pixel by pixel. Import stays one
structural op through `edit_doc`: one undo step, the same Journal chapter cut (ADR 0003), no new
draft state anywhere.

**Why not a real on-canvas "Import draft"** (the paste-draft model, dragged on the live canvas
with the Move-tool arrows and a commit pill)? It would be the truest WYSIWYG, and it was rejected
for what it costs the doctrine, not the code:

- It needs a **new, multi-frame Draft family** in the engine (per-frame buffers, durations, a
  start frame, a layer/frames mode) — every other Draft is one buffer on one frame.
- An animated import only makes sense if the artist can step frames while it is open, which
  contradicts **ADR 0011** (every Draft dies on any context change, frame switches included).
  Exempting one Draft family from the lifecycle rule reintroduces the exact divergence ADR 0011
  closed; extending the rule to "Drafts that span frames survive frame switches" is a second
  lifecycle wearing the first one's name.
- The inertness guard, the commit pill, the right-click-pick refusal, the Move-tool arrow
  routing and the replay baseline would all grow a case.

A pre-import page gives ~90% of the value for a small fraction of that surface, and its one
compromise is explicit: the backdrop is the start frame's composite only.

**What the Place page is.** The canvas on a checker with the **start frame's current composite**
under the floating import, which animates (play/pause, the crop page's preview caps — the same
decoded frames, shared through `RasterPreview` so a many-frame GIF decodes once for Crop and
Place). One finger drags the import, snapped to whole canvas pixels; two fingers / trackpad,
wheel, and right- or middle-drag move the view (the crop editor's `CropView`); double-tap toggles
fit ↔ 4×. Exact offsets via tappable X/Y chips and ±1 px arrows; a 9-cell anchor grid was
declined. The off-canvas part is shaded and the caption says it will be dropped; an import placed
entirely off the canvas cannot be committed.

**When it appears.** Automatically, whenever the result leaves canvas uncovered in some dimension
(`placementApplies`: 1:1 small sources, crop results with bars, Fit letterbox). Skipped when the
result fills the canvas exactly (Stretch, exact-size source). In the import dialog the primary
button reads **Next** when the step applies and **Import** when it does not; the Place page carries
**Back** (reopens the dialog with every choice intact) and the real **Import**.

**Preview fidelity.** The page's on-canvas size comes from the same integer `fitNoUpscale` the
crop editor pins against the engine; the Fit letterbox size mirrors the engine's `f32` rounding in
`double` (a ½-ULP disagreement could shift one edge pixel of the preview, never the import).
Default position is the engine's own centering (truncating integer division), so **Next → Import**
with no drag is byte-identical to the pre-placement behavior.
