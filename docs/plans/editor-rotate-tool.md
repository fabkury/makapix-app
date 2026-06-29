# Editor — Rotate tool: layer/selection-scoped + free-angle mode

Status legend: `[ ]` todo · `[~]` in progress · `[x]` done. Update this file as work lands.

## Goal

Rework the editor's **Rotate** tool so it transforms **content**, not the document frame:

1. **Acts on the active layer**, not the whole canvas. Whole-canvas rotation moves to the
   timeline **☰ menu → Rotate canvas** (the menu left of the frame film-strip).
2. **Selection-aware:** if pixels are selected, rotate *those* pixels of the active layer; with no
   selection, rotate the whole active layer.
3. **Free-angle ("Angle") mode:** tap **Angle** → involved pixels show a semitransparent draft + a
   draggable rotate handle (mirroring the Shape tool's rotate handle, with a live degree readout) →
   **Commit** finalizes as a single undo step.

Decisions locked with the user:
- **Non-square canvas + 90°/270°:** rotate about the pivot center and **clip** whatever falls outside
  the canvas (lossless on square canvases).
- **Selection fate:** after rotating selected pixels (quarter-turn or Angle commit), **the selection
  mask rotates with the pixels** (the marquee follows the rotated content).

Out of scope (note as possible follow-ups): making **Flip** selection-aware (today it is layer-scoped
but whole-layer); per-frame / all-frames rotation variants.

## Current state (as found)

- `Rotate` is a UI-only transform group (`tools.dart`); selecting it leaves the canvas inert
  (`_isInertCanvasTool`) and shows row-1 buttons that call `Rotate(1/3/2)` →
  `Session::rotate(quarter_turns)` in `crates/engine/src/session/canvas.rs`. That method rotates
  **every frame & layer** and **resizes** the canvas on 90°/270°, clearing the selection — i.e. it is
  already "rotate canvas".
- **Flip is already layer-scoped** (`flip_horizontal/vertical` act on the active frame's active layer),
  so this change makes Rotate consistent with Flip.
- **No arbitrary-angle pixel rotation exists.** `raster::rotated_shape` only rasterizes *new* shapes;
  it does not resample existing pixels. The Shape tool's rotate handle (`SetShapeRotation`,
  `ShapeRotateHandlePainter`) is vector-only. So the Angle mode's pixel resampler is net-new.
- Draft patterns to mirror: **MoveDraft** / **paste draft** / **shape draft** in `session.rs` —
  non-destructive previews surfaced via `display_bytes`/`draw_tool_preview`, committed on demand as one
  undo step, with state exposed in the state JSON (`move_draft`, `paste`) and the marquee following via
  `outline_mask()`.
- ☰ menu lives in `editor_page.timeline.dart` (`_editorMenuButton`/`_onEditorMenu`); has no canvas-
  rotate entry yet.

## Design

### Engine: rotation core (`crates/engine/src/session/canvas.rs` + helpers)

A shared region model covers both the layer case and the selection case:
- **source pixels**: the whole active layer (no selection) — or a bbox-sized lift of just the masked
  pixels (selection), with `src_origin` = bbox top-left.
- **pivot** (continuous canvas coords): canvas center `(W/2, H/2)` for a layer; selection **bbox
  center** for a selection.
- **mask**: `None` for a layer; the selection mask (restricted to the lift) for a selection.

"Selection present" = `doc.selection` is `Some` **and** has bounds (non-empty); otherwise fall back to
whole-layer (matches Move's semantics). All ops gated by `active_editable()` (no-op on locked/hidden).

**Quarter turns** — integer transposition path (exact; preserves the square-canvas 4×=identity
invariant): map source→rotated coords, place the rotated block centered on the pivot, clip to canvas.
- `rotate_layer(quarter_turns: u8)`: lift → integer-rotate → clear source → alpha-over place → if
  selection, set `doc.selection` to the integer-rotated mask. One undo edit (`edit_doc`).

**Arbitrary angle** — nearest-neighbor inverse map (pixel-art standard, deterministic/integer-exact
output): for each destination pixel in the rotated region ∩ canvas, inverse-rotate about the pivot,
`floor` to a source pixel, sample if in-range (and masked, for selections). Build the rotated mask the
same way. Commit snaps exact multiples of 90° through the integer path for crispness.

Rotation convention matches the Shape rotate handle: `R(θ)=[[cosθ,−sinθ],[sinθ,cosθ]]` with screen
y-down, so positive θ reads as clockwise; angles carried as **milliradians** like `SetShapeRotation`.

### Engine: the Angle draft (non-destructive, like MoveDraft)

```
struct RotateDraft {
    fid: u32, lid: u32,
    is_selection: bool,
    sel_before: Option<Arc<Mask>>,   // mask at begin (for mask-follow on commit)
    src: RgbaBuffer,                 // lifted source (whole layer, or bbox region)
    src_origin: Point,               // 0,0 for layer; bbox.xy for selection
    pivot: PointF,                   // continuous canvas coords
    angle: f32,                      // radians
}
```

- Non-destructive: the document is untouched until commit (cancel/crash leave it pristine).
- Preview: `rotate_draft_preview_frame()` clones the active frame, clears the source region in the
  active layer, and blits the NN-rotated result; `display_bytes` composites it; `draw_tool_preview`
  washes the rotated footprint with the "draft" tint (reuse the soft cyan, like move/paste) so the
  involved pixels read as semitransparent draft status.
- `outline_mask()` returns the live NN-rotated mask while a selection rotate draft is open (marquee
  follows), mirroring the move-draft branch.

New `Session` methods: `rotate_draft_begin`, `rotate_draft_set_angle(milliradians)`,
`rotate_draft_commit`, `rotate_draft_cancel`, plus `rotate_draft_rect()`/state for the shell.

### FFI / DSL (`crates/engine/src/session/parse.rs`)

Keep `Rotate(u8)` (now the canvas/menu action). Add `Action` variants + parse + dispatch:
- `RotateLayer(i32)` — selection-aware quarter-turn (instant, one undo).
- `RotateDraftBegin` · `RotateDraftSetAngle(i32 mrad)` · `RotateDraftCommit` · `RotateDraftCancel`.

### State JSON (`session.rs` state block)

Add `"rotate_draft"`: `{ "cx":…, "cy":…, "x":…, "y":…, "w":…, "h":…, "angle_mrad":… }` (pivot +
involved-region bbox + angle), `null` when none — enough for the shell to place the
`ShapeRotateHandlePainter` (center = pivot, corner = bbox far corner) and show the angle.

### Shell UI

- `tools.dart`: update the Rotate tip → "Rotate the layer 90°, 180°, or by a free angle. Acts on the
  selection if any."
- `editor_page.dart`: add `_hasRotateDraft`, `_rotDraftCenter`, `_rotDraftCorner`, `_rotDraftAngle`
  (parsed in `_refreshState` from `rotate_draft`).
- `editor_page.controls.dart` (`if (_tool == 'Rotate')`):
  - When **not** drafting: `Rotate 90° CW/CCW` + `Rotate 180` → now call `RotateLayer(1/3/2)`; plus an
    **Angle** button → `RotateDraftBegin()`.
  - When drafting (`_hasRotateDraft`): show **Commit** (`RotateDraftCommit`) / **Cancel**
    (`RotateDraftCancel`) like the shape draft; quarter buttons hidden.
- `editor_page.canvas.dart`:
  - Overlay the rotate handle when `_tool == 'Rotate' && _hasRotateDraft`
    (`ShapeRotateHandlePainter(center, corner, angle, scale, off)`).
  - Make the canvas interactive for the handle while rotate-drafting (Rotate is normally inert): a
    press near the reticle → drag updates the angle (reuse the `atan2` math from `_continueShape`'s
    `_shapeDrag == 5` branch) → `RotateDraftSetAngle(mrad)`; `_refreshState`/`_redraw` for live wash.
- `editor_page.engine.dart` (`_selectTool`): cancel a pending rotate draft when leaving Rotate (mirror
  the move/paste cancel-on-leave).
- `editor_page.timeline.dart` (`_editorMenuButton`/`_onEditorMenu`): add **Rotate canvas** entries
  (90° CW / 90° CCW / 180°) wired to the existing doc-wide `Rotate(1/3/2)`.

## Tests

Rust (`crates/engine/src/session/canvas.rs` `#[cfg(test)]` + `crates/engine/tests/scenarios.rs`):
- `[ ]` `rotate_layer_90_square_lossless_and_4x_identity`
- `[ ]` `rotate_layer_touches_active_layer_only` (other layers/frames untouched; no canvas resize)
- `[ ]` `rotate_layer_selection_rotates_pixels_and_mask_about_bbox_center`
- `[ ]` `rotate_layer_90_nonsquare_clips_to_canvas` (no panic; centered + clipped)
- `[ ]` `rotate_draft_begin_set_commit_single_undo_rotated_pixels`
- `[ ]` `rotate_draft_pi_matches_rotate_layer_2` (angle π ≈ quarter-turn 180)
- `[ ]` `rotate_draft_cancel_is_nondestructive`
- `[ ]` `rotate_draft_selection_commit_rotates_mask`

Docs:
- `[ ]` SPEC.md §28.1: clarify Flip/Rotate are layer/selection-scoped tools w/ an Angle draft; whole-
  canvas rotate lives in the canvas menu.
- `[ ]` STATUS.md: note layer/selection rotate + free-angle.

Build gates: `cargo test`, `cargo clippy --workspace`, `cd app && flutter analyze` (+ `flutter test`).
Manual smoke: `./build.ps1 -Run`.

## Task checklist

- `[ ]` Engine: `rotate_layer(q)` (selection-aware, center pivot, clip) + integer-rotate helpers
- `[ ]` Engine: NN inverse-map resampler (pixels + mask) shared by draft & angle commit
- `[ ]` Engine: `RotateDraft` + begin/set_angle/commit/cancel + preview frame + `outline_mask` branch
- `[ ]` FFI/DSL: `RotateLayer` + `RotateDraft*` actions (variants, parse, dispatch)
- `[ ]` State JSON: `rotate_draft` field
- `[ ]` Shell: controls (quarter buttons → RotateLayer, Angle button, Commit/Cancel)
- `[ ]` Shell: canvas handle overlay + drag gesture; `_refreshState`/`_selectTool` wiring
- `[ ]` Shell: ☰ menu → Rotate canvas (doc-wide `Rotate`)
- `[ ]` Rust tests
- `[ ]` SPEC.md / STATUS.md updates
- `[ ]` Build gates green (cargo test, clippy, flutter analyze) + manual smoke
