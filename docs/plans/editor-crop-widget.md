# Editor — Enhanced crop widget for image import

Status legend: `[ ]` todo · `[~]` in progress · `[x]` done. Update this file as work lands.

## Goal

Replace the small drag-a-box `CropDialog` with a **large, dedicated crop editor** for imported rasters
(static **and** animated), and change the crop *placement* semantics from "stretch the region to fill the
canvas" to **"place the region 1:1, centered — downscaling to fit only when it is larger than the canvas."**

User-facing behavior (locked with the user):

1. Choosing **Crop** in the import dialog opens a large, full-screen crop editor.
2. A **very large preview** of the incoming raster. Animations get a **Play/Pause** button, a **current
   frame indicator**, and a **frame count**. Static rasters show the Play/Pause control **disabled**.
3. The crop rectangle **defaults to the current canvas size, centered** on the incoming raster (clamped to
   the source bounds — see Decision D3).
4. **Drag anywhere inside** the rectangle to move the whole crop area.
5. **Large, easy-to-tap corner reticles**; dragging a reticle moves that corner independently.
6. The crop rectangle's **X, Y, Width, Height** are shown below the preview.
7. The preview shows the **entire** incoming raster; the **cropped-out area is shaded** to show it will be
   excluded.
8. **Tapping any of X / Y / W / H** opens direct **text entry** for precise values.
9. A crop **smaller than the canvas** is placed **centered, not upscaled** (transparent padding around it).

Decisions locked with the user (this session):

- **D1 — Oversize crop:** when the rectangle is larger than the canvas, the region is **downscaled to fit**
  the canvas (nearest-neighbor, aspect-ratio preserved, centered/letterboxed). It is never stretched.
- **D2 — Existing modes:** the import dialog keeps **Fit** and **Stretch** as quick one-tap whole-image
  options; only the **Crop** path is replaced by the new widget, and "Crop" now means 1:1-or-downscale
  centered.
- **D3 — Aspect lock:** the rectangle is **free-form by default**, with an **optional toggle** to lock it to
  the **canvas aspect ratio** while dragging/typing.
- **D4 — Numeric entry:** **all four** fields (X, Y, W, H) are tap-to-edit.

## The unifying insight (why this is one formula, not two)

"Smaller → centered 1:1" (req 9) and "larger → downscale to fit" (D1) are the **same** operation:

```
scale = min(W/cropW, H/cropH, 1.0)     // ≤1 always → never upscales
```

- Region ≤ canvas on both axes → `scale == 1` → placed 1:1, centered, transparent padding.
- Region larger on either axis → `scale < 1` → downscaled to fit, aspect preserved, centered.

Implemented with **integer** math (see engine section) to stay byte-deterministic per the engine invariants
(SPEC §25). This replaces the current stretch-to-canvas behavior of `crop_rect`.

## Current state (as found)

- **Interactive crop lives only in image import.** `_importImage` (`app/lib/editor/editor_page.fileio.dart`)
  is the single caller; the import dialog's **Crop** toggle reveals a "Select crop area…" button that opens
  `CropDialog` (`app/lib/editor/dialogs/crop_dialog.dart`) and stores a source-pixel `Rect`, then passes it
  to `engine.importImage(..., cropX/Y/W/H)`.
- **Club edit/remix (`_consumeClubEdit`) does NOT use crop** — it imports with `mode: 1` (Stretch), whole
  image, no `crop_rect`. Out of scope here; left untouched.
- **Only the first frame is decoded** for the current crop UI: `_importImage` calls `_decodeBytes`
  (`editor_page.engine.dart:288`, `codec.getNextFrame()` once) and hands the resulting `ui.Image` to
  `CropDialog`. The dialog draws the whole image dimmed with the selected sub-region redrawn bright + an amber
  outline; drag paints a new box from scratch (no move, no per-corner handles, no numeric entry, no
  animation).
- **Engine crop today STRETCHES.** `frame_to_buffer` (`crates/engine/src/import.rs:76`): when `crop_rect` is
  set, it samples `sx = cr.x + x*rw/cw`, i.e. the region is stretched to exactly fill the canvas. Test
  `crop_rect_stretches_region_to_canvas` (import.rs:226) asserts this.
- **FFI already carries the crop rect.** `mkpx_import(..., crop_x, crop_y, crop_w, crop_h)`
  (`crates/ffi/src/lib.rs:325`) builds `crop_rect: Some(IRect)` when `crop_w>0 && crop_h>0`. Dart side:
  `Engine.importImage({... cropX, cropY, cropW, cropH})` (`app/lib/engine_ffi.dart:275`).
  **➜ No FFI signature change is needed** — only the *interpretation* of `crop_rect` inside the engine
  changes, plus a brand-new Dart widget. Small, contained blast radius.

## Design

### 1. Engine — new crop placement (`crates/engine/src/import.rs`)

Change the `crop_rect` branch of `frame_to_buffer` from stretch → **fit-no-upscale, centered**, using
integer arithmetic (matches the existing integer sampling style; no new float determinism surface):

```rust
if let Some(cr) = cfg.crop_rect {
    let (rw, rh) = (cr.w.max(1), cr.h.max(1));       // region size, source px
    let (dw, dh) = fit_no_upscale(rw, rh, cw, ch);   // dest size on canvas
    let (ox, oy) = ((cw as i32 - dw as i32) / 2, (ch as i32 - dh as i32) / 2); // centered
    for y in 0..dh as i32 {
        for x in 0..dw as i32 {
            let sx = cr.x + (x as u64 * rw as u64 / dw as u64) as i32;
            let sy = cr.y + (y as u64 * rh as u64 / dh as u64) as i32;
            let c = src_get(&df.rgba, df.w, df.h, sx, sy);
            if c.a != 0 { out.set(ox + x, oy + y, c); }
        }
    }
    return out;
}
```

```rust
/// Fit `(rw,rh)` inside `(cw,ch)` preserving aspect ratio, never upscaling. Integer-exact.
fn fit_no_upscale(rw: u32, rh: u32, cw: u32, ch: u32) -> (u32, u32) {
    if rw <= cw && rh <= ch { return (rw, rh); }          // 1:1 case
    // downscale: pick the binding axis (cross-multiply to avoid float)
    if (rw as u64) * (ch as u64) >= (rh as u64) * (cw as u64) {
        (cw, ((rh as u64 * cw as u64) / rw as u64).max(1) as u32) // width-bound
    } else {
        (((rw as u64 * ch as u64) / rh as u64).max(1) as u32, ch) // height-bound
    }
}
```

Update the `crop_rect` doc comment (import.rs:43-45) to describe fit-center instead of stretch.

**Rust tests** (`crates/engine/src/import.rs` `#[cfg(test)]`):
- Replace `crop_rect_stretches_region_to_canvas` → `crop_rect_places_region_1to1_centered`: crop a 4×8
  region into a 16×16 canvas → the region occupies the centered 4×8 block (ox=6, oy=4), pixels there match
  the source, everything else transparent.
- Add `crop_rect_downscales_when_larger_than_canvas`: crop a 32×16 region into a 16×16 canvas → dest 16×8,
  centered (oy=4), aspect preserved, no out-of-bounds writes.
- Add `crop_rect_equal_to_canvas_is_identity`: crop W×H == canvas → exact 1:1, ox=oy=0.

### 2. FFI / doc comments

- **No signature change.** Update the `mkpx_import` doc comment (`crates/ffi/src/lib.rs:321-322`) and
  `Engine.importImage` doc (`app/lib/engine_ffi.dart:273-274`) to say the crop region is placed
  1:1/downscale-centered (no longer "stretched to the canvas").

### 3. Dart — the crop editor widget (`app/lib/editor/dialogs/crop_dialog.dart`, rewritten)

Rewrite the file to export a full-screen **`CropPage`** (pushed via `MaterialPageRoute`, returns
`Rect?` in **source pixels**), plus a **plain, Flutter-free geometry class `CropGeometry`** that holds all
the math so it is unit-testable without a golden.

**`CropGeometry`** (pure Dart, no `dart:ui`/widgets):
- Fields are **all `int`**: `int srcW, srcH, canvasW, canvasH; int x, y, w, h; bool aspectLocked;`. The rect
  is stored as integer source pixels internally — **not** a `Rect` (double) — so aspect-lock rounding and
  corner drags never introduce fractional values that `importImage`'s `.toInt()` would later truncate and
  silently drift (e.g. `x+w` slipping past `srcW`). Expose a `Rect toRect()` only at the widget boundary for
  the return value. This also makes the unit tests exact. *(Review fix #1.)*
- `moveBy(dx, dy)` — translate, **clamp** so the rect stays fully within `[0,srcW]×[0,srcH]` (Decision D3:
  the rect cannot select non-existent source pixels).
- `dragCorner(corner, x, y)` — move one corner, opposite corner fixed, enforce **min 1×1**, clamp to source
  bounds; if `aspectLocked`, constrain the free axis to the canvas aspect ratio.
- `setField(field, value)` — for numeric entry; validate/clamp (`W,H ≥ 1`, `X ≥ 0`, `X+W ≤ srcW`, etc.); if
  `aspectLocked` and W (or H) changes, recompute the other axis.
- `toggleAspectLock()` — on enable, snap H to `round(W * canvasH / canvasW)` (clamp; if it overflows source,
  shrink W to fit).
- `resultDims()` — mirror of the engine's `fit_no_upscale` so the UI can show the outcome
  ("Result: 32×32, placed 1:1" / "Result: 16×8, downscaled").
- `defaultRect()` — canvas-size rect centered on the source, **clamped to source bounds** (so when the
  source is smaller than the canvas the default is the whole source; the engine then centers it 1:1).

**Frame decode helper** — decode frames for animated preview, **with a soft cap** *(Review fix #2 —
Android is a first-class target and imports allow sources > 256², so 1,024 full-res `ui.Image` GPU textures
can OOM a phone, e.g. 800×600×1024 ≈ 2 GB)*:
```dart
// returns (List<ui.Image> frames, List<Duration> durations, bool truncated)
Future<(List<ui.Image>, List<Duration>, bool)> _decodeFramesForPreview(Uint8List bytes)
```
Iterate `codec.getNextFrame()` **sequentially** (the codec is stateful) up to `codec.frameCount`, collecting
each `FrameInfo.image` + `.duration`, but **stop early** once either a frame cap (**≤ 120 frames**) or a
total-pixel budget (**≤ ~64 M preview pixels**, i.e. `srcW*srcH*decodedCount`) is reached — whichever comes
first. When stopped early, set `truncated = true` and show a small "preview truncated — full animation still
imports" note (the crop rect is spatial, so a truncated preview does not affect the actual import, which the
engine decodes independently). Static images yield a single frame. Reuses `ui.instantiateImageCodec` — the
same decoder `_decodeBytes` already uses for the title.

**`CropPage` widget** (`StatefulWidget`, `SingleTickerProviderStateMixin`):
- Inputs: `Uint8List bytes`, `int srcW, srcH`, `int canvasW, canvasH`.
- State: decoded `frames`/`durations`, `int currentFrame`, `bool playing`, `Ticker` for playback,
  `CropGeometry geo`, active drag target (none / whole-rect / one of 4 corners).
- Layout — `Scaffold`:
  - **AppBar:** title "Crop", action = aspect-lock **IconButton** (`lock`/`lock_open`, D3), and a reset button.
  - **Preview (`Expanded` + `LayoutBuilder`):** `displayScale = min(availW/srcW, availH/srcH)` with a small
    margin so the source fits fully. A `CustomPaint`:
    - draws the **current frame** image scaled by `displayScale` (`FilterQuality.none` — pixel-art crisp),
    - draws a **shade** (`0x99000000`) over the whole image **minus** the crop rect (even-odd path, so the
      inside stays bright),
    - draws the crop rect **outline** + **4 large corner reticles** (~44 dp circles — comfortable touch
      targets).
    - A `GestureDetector`/`Listener` maps screen↔source coords via `displayScale`; on pan-start it
      **hit-tests corners first** (generous radius), else inside-rect → move, else no-op. Updates `geo`.
  - **Below the preview:**
    - **Animation row:** Play/Pause `IconButton` (disabled when `frames.length == 1`), and
      "Frame `currentFrame+1` / `frames.length`" (shows "Static" for a single frame).
    - **Coordinates row:** four tappable `X / Y / W / H` chips → tapping opens a small text-entry dialog
      (numeric, validated) that calls `geo.setField(...)` (D4).
    - **Result line:** `geo.resultDims()` outcome text.
  - **Bottom bar:** **Cancel** (pop `null`) · **Use crop** (pop `geo.rect`).
- **Playback:** the `Ticker` accumulates elapsed time; advance `currentFrame` when it passes the current
  frame's duration; loop. `setState` only on frame change, and **only when `mounted`**.
- **Lifecycle (Review fix #3 — the codebase is meticulous about GPU-image leaks, cf. the `img.dispose()` /
  F-10 notes at `editor_page.engine.dart:207-233`):** in `dispose()`, stop + dispose the `Ticker` **and**
  `dispose()` **every** decoded `ui.Image` (not just the current one). Guard every async continuation
  (decode completion, ticker callback) with `if (!mounted) return;` so nothing ticks or `setState`s after the
  route is popped. A single widget test that pumps the route and then disposes it is worthwhile to catch a
  tick-after-dispose regression.

### 4. Wiring (`app/lib/editor/editor_page.fileio.dart`)

- In `_importImage`, the **Crop** branch's "Select crop area…" button now does:
  ```dart
  final r = await Navigator.of(context).push<Rect>(MaterialPageRoute(
    builder: (_) => CropPage(bytes: bytes, srcW: srcImg.width, srcH: srcImg.height,
                             canvasW: engine.width, canvasH: engine.height)));
  if (r != null) setS(() => cropRect = r);
  ```
  Use the **outer `_importImage` `context`** here (as the existing `showDialog` call already does), not the
  dialog builder's `ctx` — the full-screen route simply stacks above the still-open import dialog and returns
  to it on pop, so `setS` runs normally.
- The label still shows `Crop: {W}×{H}` from the returned rect. The `engine.importImage(... cropX/Y/W/H)`
  call is **unchanged** (engine now fit-centers). `srcImg` is still decoded once for the dialog title.
- Fit / Stretch toggles unchanged (D2).

### 5. Tests (`app/test/crop_widget_test.dart`, new — pure Dart)

Unit-test `CropGeometry` (no Flutter binding needed):
- `defaultRect` centers a canvas-size rect and clamps to source (incl. source-smaller-than-canvas → whole
  source).
- `moveBy` clamps at all four edges.
- `dragCorner` enforces min 1×1, keeps the opposite corner fixed, clamps to bounds.
- aspect-lock: enabling snaps H to canvas ratio; editing W recomputes H; drags stay locked.
- `setField` validation/clamping for each of X/Y/W/H.
- `resultDims` matches the engine formula for: equal-to-canvas (1:1), smaller (1:1 centered), larger
  (downscaled, aspect preserved).

Plus one lightweight **widget test**: pump `CropPage` on a tiny decoded raster, then pop/dispose the route,
asserting no exception (guards the tick-after-dispose / image-leak lifecycle — Review fix #3).

### 6. Docs

- **SPEC.md §16.1** "Size handling": note that the interactive **Crop** places the selected region **1:1,
  centered (no upscale), downscaling to fit only when the region exceeds the canvas** — replacing the old
  stretch-to-canvas behavior.
- **STATUS.md**: update the import line to mention the new crop editor (animated preview, per-corner handles,
  numeric entry, 1:1/downscale-centered placement).

## Files touched

| File | Change |
|------|--------|
| `crates/engine/src/import.rs` | crop_rect branch → fit-no-upscale-centered; `fit_no_upscale` helper; 3 tests; doc comment |
| `crates/ffi/src/lib.rs` | doc comment only |
| `app/lib/engine_ffi.dart` | doc comment only |
| `app/lib/editor/dialogs/crop_dialog.dart` | **rewrite** → `CropPage` + `CropGeometry` + all-frames decode |
| `app/lib/editor/editor_page.fileio.dart` | Crop button opens `CropPage` (full-screen route) |
| `app/test/crop_widget_test.dart` | **new** — `CropGeometry` unit tests |
| `SPEC.md`, `STATUS.md` | doc updates |

## Validation

- `cargo test -p makapix-engine` (new crop tests) and full `cargo test`.
- `cd app && flutter test test/crop_widget_test.dart` + `flutter analyze`.
- `./build.ps1 -Run`: import a **static** PNG larger than the canvas → Crop → verify move/corner/numeric/
  aspect-lock, "Use crop" places it centered & downscaled; import a **GIF** → verify Play/Pause, frame
  counter, and that the crop overlay stays fixed while frames cycle; import a source **smaller** than the
  canvas → verify it lands centered at 1:1.

## Risks / edge cases

- **Large animated sources**: decoding every frame to `ui.Image` for preview costs memory (up to 1,024
  frames). Acceptable for now (same frames the engine decodes on import); note as a follow-up if it bites.
  Consider a soft cap/warning only if needed — out of scope here.
- **Source smaller than canvas**: default crop clamps to the whole source; engine centers it 1:1 (correct,
  no upscale). Covered by a `CropGeometry` test.
- **Tiny rect (1×1)**: corner reticles overlap; hit-test priority (corners before move) keeps it usable.
- **Non-square canvas + aspect lock**: lock uses the canvas W:H ratio, not 1:1.
- **Determinism**: engine placement is integer-only; no new float surface, goldens stay stable per platform.

## Non-goals

- No crop on the Club edit/remix path (`_consumeClubEdit` stays whole-image Stretch).
- No resample-filter choice (Nearest only, as today).
- No change to Fit / Stretch.
- No FFI signature change.
