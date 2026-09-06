# Crop canvas is the import crop editor pointed at the document, committed by one explicit-rectangle verb

**Decided and implemented 2026-09-06.** Engine: one additive verb `CropCanvas(x, y, w, h)` (canvas px;
clipped to the canvas; whole-canvas or empty = no-op, no undo step), a `Session::content_bounds()`
query, and two string-returning FFI getters (`mkpx_content_bounds`, `mkpx_selection_bounds`). Shell:
`CropPage` gains a `canvas` mode; ☰ → Canvas → **Crop canvas…** opens it over the document's own
composited frames. No `.mkpx`, journal-format, or Club change.

Cropping the canvas to a hand-drawn rectangle is table stakes in every raster editor, and the engine
already did most of it (`CropToSelection`, since the first weeks) behind a UI that never exposed it:
the only way to crop was to draw a marquee first, then find a verb the shell did not offer. Meanwhile
the import flow had grown a **first-class crop editor** (2026-09-01: corner reticles, X/Y/W/H entry,
aspect lock, a zoomable and pannable view, animated preview with play/pause and frame stepping).
A second crop editor for the canvas would have been a second, worse copy of it.

**Decisions.**

- **One page, two modes.** `CropPage(mode: CropPageMode.canvas)` is the same widget the import
  flow pushes: same gestures, zoom buttons, hint, reticles, chips, playback. The canvas mode adds
  what only makes sense for the document — the editor's transparency checker under the preview,
  a **Trim to content** app-bar button, the Resize dialog's **size presets** (16²…512², only those
  that fit some side; a locked aspect a preset violates is released, not enforced), the **Club
  size note** under the result line, and a **Crop** button that stays disabled while the rectangle
  is the whole canvas. The frame source is abstracted (`FramePreview` → `RasterPreview` for files,
  `CanvasPreview` for the document's composites) so the page never knows which it is drawing.
- **The page opens on the selection's bounds when there is one, else the whole canvas.** That
  makes "crop to selection" a two-tap gesture inside the same page instead of a separate menu
  item, and a page opened by mistake closes without change (OK is disabled on the whole canvas).
- **An explicit-rectangle verb, not a selection round-trip.** The shell could have synthesized a
  marquee and issued `CropToSelection`, or two anchored `ResizeCanvas` calls. Both would journal a
  lie about what the user did and cost two undo steps; `CropCanvas(x, y, w, h)` records the
  intent, replays deterministically, and shares the crop routine with `CropToSelection` (both
  consume the selection and crop every frame and layer in one step). Whole-canvas and empty
  rectangles are no-ops so an unchanged page never dirties the history.
- **Trim to content counts only what shows.** `content_bounds()` unions the opaque bounds of every
  layer of every frame, clipped to the canvas; pixels moved into the gutter do not widen it.
  This closes the long-listed "Trim to non-transparent bounds" gap without a separate feature.
- **The preview is capped, the crop is not.** `CanvasPreview` honors the same soft caps as the
  import preview (120 frames / 64 M px of textures) — a phone cannot hold 1,024 composited
  512² textures — while the engine crops the full document regardless.

**Consequences.** A new verb name that must parse forever (`CropCanvas`), listed in the replay
visible index so a crop is a visible step in Watch replays. The Trim scan walks every tile of
every layer on open (bounded by the document budgets; instantaneous at 512² × 64 layers).
`CropToSelection` stays as the selection-mask spelling for scripts and the fuzzer; the UI never
issues it.
