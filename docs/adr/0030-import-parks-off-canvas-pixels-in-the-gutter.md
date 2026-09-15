# Import parks off-canvas pixels in the gutter, with a 1:1 size choice

**Decided and implemented 2026-09-09.** Engine: `ScaleMode::Native` + `frame_to_storage` in
`crates/engine/src/import.rs` (the storage-sized rasterizer `import_decoded` now fills directly),
`Session::composite_frame_storage_bytes`; FFI: mode code `3`, `mkpx_storage_width/height`,
`mkpx_composite_frame_storage`; CLI: `--mode native`. Shell: the fourth **1:1** toggle in the import
dialog (`editor_page.fileio.dart`), `CropView` overscan band + `minZoom`/`isHome`
(`crop_dialog.dart`), the gutter-aware `PlaceGeometry`, storage-sized backdrop, memory estimate and
fixed-height status block in `place_dialog.dart`.

Every layer buffer is a 3×3-canvas storage area (SPEC §6): a full canvas of off-canvas gutter on
each side, where Move, paste and the canvas transforms park pixels so they can be brought back.
Import was the one path that brought pixels in and threw the overhang away: `frame_to_buffer`
rasterized into a canvas-sized buffer, `set_clipped` dropped everything off the canvas, and the
Place page (ADR 0019) shaded that part with "dropped at import" and refused a fully off-canvas
placement. Framing an import was therefore a one-shot decision on the Place page; reframing meant
re-importing. A wide backdrop for a panning animation, or a sprite sheet to pull pieces from,
could only come in downscaled to the canvas.

**The import rasterizes straight into the storage-sized layer buffer, and only the storage
boundary clips.** Whatever part of the placed image hangs off the canvas is parked in the gutter,
exactly like a moved or pasted pixel: recoverable with the Move tool, visible under the Overscan
view, invisible to export, thumbnails and publish (all canvas-cropped, unchanged), written to the
`.mkpx` like any gutter content, and gone with the layer on undo. `Stretch` and the anchored `Crop`
still fill exactly the canvas. This is always on: there is no mode or setting, because the gutter
is the document's own storage and an import is a paste from a file.

**A fourth size choice, 1:1.** A source larger than the canvas but no larger than the storage area
(`≤ 3× per side`) gets **Fit / Stretch / Crop / 1:1**, and 1:1 is preselected: a whole source at
its own size, centered by the same truncating division as every other placement, its overhang
symmetric in the gutter. Fit is one tap away and unchanged. A source larger than storage keeps
the three modes (the CLI still accepts `native` for it; the storage boundary clips). ~~The
interactive Crop path is deliberately unchanged: a crop region larger than the canvas is still
downscaled to the canvas. It is the one path that cannot land 1:1 into the gutter, and widening it
was declined to keep "Crop places the region on the canvas" readable.~~ *Superseded by ADR 0034
(2026-09-15): an oversize crop region lands 1:1 by default, the downscale is the other choice.*

**Place anywhere in storage.** The Place page shows the dimmed gutter around the canvas — with the
start frame's existing parked pixels, through a storage-sized composite — and the import may go
anywhere in it. Fit still frames the canvas alone, as before; the gutter overflows the edges and is
reached by panning (allowed at fit now that there is something to see) or zooming out to the new
floor, storage-fit. The part of an import beyond the storage boundary is the only part still
shaded and dropped; Import is refused only when nothing at all would land.

**The memory note.** A full gutter is 9× the canvas payload per layer per frame, so an animated
1:1 import can cross the 320 MiB hard budget with a fraction of the frames a canvas-sized one
needs; the engine gate then rolls the whole import back and reports a refusal — after the decode.
The Place page therefore shows an upper-bound estimate (source frames × kept placed area × 4 B)
against the budget headroom, amber when it would cross. It is a warning only: the engine's gate is
the authority, the estimate ignores lazily allocated transparent tiles and tile dedup, and the
user decided against blocking Import on it. By the same decision there is **no publish-time gutter
strip**: the layers attachment ships what the document holds, as it does for Move-parked pixels.

**No reflow.** The status block under the Place view keeps one height in every state: the panel's
height feeds the preview's fit scale, and a note that appears mid-drag moves the image under the
finger (the Crop canvas page's constant-height Club-size status established the rule). The
off-canvas and memory notes each own a fixed 20 px slot that changes only text and color.

Consequences: `placement_moves_and_clips_at_every_edge` keeps its meaning for the no-gutter twin
`frame_to_buffer`; the gutter semantics have their own tests. Trim to content still ignores the
gutter (ADR 0027), and Resize / Crop canvas keep only the gutter that still fits — an import parked
wide can lose its far part to a later canvas change, as any parked pixel can. The transient peak
of a refused import (old document + the built frames + the decode blob) is 9× more reachable than
before and belongs on the memlab list for the next device pass.
