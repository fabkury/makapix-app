# An oversize crop region lands 1:1 by default, with the downscale as the other choice

**Decided and implemented 2026-09-15.** Engine: the explicit-crop path of `frame_to_storage`
(`crates/engine/src/import.rs`) skips `fit_no_upscale` when the mode is `ScaleMode::Native`; no
FFI signature change (mode code `3` and the crop rect already travel separately). Shell: the
`1:1 · Fit to canvas` control and the nudge arrows in the crop editor (`crop_dialog.dart`:
`CropChoice`, `NudgeArrows`, `nudgeKeyHandler`), `importPlacedSize` under the Native code
(`place_dialog.dart`), the `cropNative` state and the Crop summary in the import flow
(`editor_page.fileio.dart`).

ADR 0030 made the gutter the landing zone for everything an import places off the canvas, and
gave a large source a **1:1** choice — but left the interactive Crop path alone: a crop region
larger than the canvas was still downscaled to fit, "to keep *Crop places the region on the
canvas* readable". In use that exception was the surprise. The crop editor is where an artist
frames a wide backdrop or a sprite-sheet strip precisely, and the framed region then arrived
shrunk, while the same pixels imported whole (1:1) kept their size. The one path built for
precision was the one path that could not land pixel for pixel.

**An oversize crop region lands 1:1 by default.** The region keeps its size; the part beyond the
canvas is parked in the gutter, exactly like a 1:1 whole-source import, and only the storage
boundary clips. The Place page (ADR 0019) follows: it shows what is parked and what falls beyond
storage, and Import is refused only when nothing at all would land. A region wider than even the
storage area is allowed — the crop editor's result line turns amber and says the far part is
dropped, the Place page shows which part, and the final placement decides what survives. There is
no gate on the storage size for crops, unlike the whole-source 1:1 (which is only offered when
the source fits within storage): the region is the user's own framing, and losing its far edge
at a chosen position is a decision, not an accident.

**The downscale stays, as the other choice.** A two-option control, `1:1 · Fit to canvas`, on
the crop editor's W/H row — visible only while the rect exceeds the canvas, but kept in the
layout at its size otherwise, so a corner drag across the canvas size never reflows the panel
(the no-reflow rule of ADRs 0027 and 0030: the panel's height feeds the preview's fit scale).
**Every import starts at 1:1** (user decision: the choice is never remembered across imports;
Back and *edit…* keep it within one import). The choice rides back to the import dialog inside
`CropChoice` (rect + `native`), the Crop summary reads `1:1` or `→ W×H`, and the engine receives
mode `3` with the crop rect for 1:1, mode `2` for the downscale — `mode` in the dialog remains
the chooser's selection.

**Nudge arrows.** The crop editor gains the Place page's four ±1 px arrows, on the X/Y row (the
coordinates they move); W/H sit on a second row with what sets a size (this control in import
mode, the presets in canvas mode). A tap nudges once; **holding an arrow repeats** it after the
long-press delay (~15 px/s); **keyboard arrows** nudge one px, ten with Shift, through a
page-level `Focus` — on both pages, through one shared `NudgeArrows` / `nudgeKeyHandler` pair.
A nudge ends any live corner drag first ([G-45]), as the aspect-lock and reset buttons do.

**Consequences.** ADR 0030's "the interactive Crop path is deliberately unchanged" paragraph is
superseded by this one. `importPlacedSize` mirrors the engine: a crop under the Native code is its
own size, so `placementApplies` sends every oversize 1:1 crop through Place. A crop-rect import
under mode 3 is a new engine behavior; journals never carry imports, so nothing replays
differently. The memory note of ADR 0030 applies unchanged: an animated 1:1 crop can cross the
hard budget with fewer frames than a canvas-sized one, and the engine's gate stays the authority.
