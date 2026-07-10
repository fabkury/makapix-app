//! `Session` — the single stateful entry point driven by both the CLI harness and the
//! Flutter shell (SPEC §9, §19). Owns the document + editor state, runs the action-script
//! DSL, routes pointer input to tools, wraps each change in one undo record, and exposes
//! probes.

use crate::buffer::RgbaBuffer;
use crate::color::Rgba8;
use crate::document::{Document, Frame, LoopMode};
use crate::geom::{IRect, Point, PointF};
use crate::io;
use crate::render;
use crate::selection::{CombineMode, Mask};
use crate::tool::{self, GradientKind, PaintMode, Stop, ToolKind, ToolSettings};
use crate::util::{hash_hex, Hash, SeededRng, VirtualClock};
use std::sync::Arc;

mod canvas; // flip/rotate/resize/crop — extracted impl Session block [audit F-17]
mod parse;
pub use parse::Action;

/// A captured pre-edit pixel snapshot of one layer's tiles.
type TileSnapshot = Vec<Option<std::sync::Arc<crate::buffer::Tile>>>;

/// A pre-edit snapshot pinned to the exact (frame id, layer id) it was taken from. The matching
/// commit/cancel resolves that target *by id* rather than acting on "whatever is active now", so a
/// DSL that changes the active frame/layer mid-stroke can no longer record (or restore) a patch
/// against the wrong layer. [audit F-29]
struct EditScope {
    fid: u32,
    lid: u32,
    before: TileSnapshot,
    /// Selection at the moment the edit began. Recorded as the "before" side so an op that moves
    /// pixels *and* the mask together (Move drag) undoes/redoes both as one step. [F-29]
    sel_before: Option<Arc<Mask>>,
}

/// In-progress gesture state.
struct Stroke {
    before: EditScope,
    start: Point,
    last: Point,
    path: Vec<Point>,
    floating: Option<RgbaBuffer>, // for Move
    /// Pencil pixel-perfect: the tail of recently painted pixels (with their captured pre-stroke
    /// colours), used to detect and undo the L-shaped "corner double" as the stroke is drawn. Only
    /// populated for a 1px Pencil with `pixel_perfect` on; empty otherwise. See [`pp_corner`].
    pp: Vec<(Point, Rgba8)>,
}

/// One layer's lifted content within a [`MoveDraft`], re-blitted at `anchor + offset`.
struct MoveFloat {
    lid: u32,
    pixels: RgbaBuffer, // the lifted content (a bbox for a selection move, the whole layer otherwise)
    anchor: Point,      // top-left at offset (0,0): the selection bbox origin, or (0,0) for a layer
}

/// An in-progress, relocatable "move draft" (the Move tool's draw→adjust→commit flow, like the shape
/// and paste drafts). **Non-destructive**: the document is never touched while the draft is open —
/// the moved content is lifted into `floats` and shown only as a *display-time* preview (origin
/// lifted, floating blitted at `offset`, washed soft cyan). **Only `move_draft_commit` materializes
/// the move** (one undo step); cancelling, leaving the editor, or a crash all leave the document
/// exactly as it was. Covers the selected-pixels move (`is_selection` — the marquee follows) and the
/// no-selection layer / move-group move.
struct MoveDraft {
    fid: u32,
    sel_before: Option<Arc<Mask>>,
    floats: Vec<MoveFloat>,
    is_selection: bool,
    bbox: Option<crate::geom::IRect>, // union opaque bbox at offset 0 (Protect-clamp + draft rect)
    offset: Point,
}

/// An in-progress free-angle rotation — the Rotate tool's "Angle" mode, in either scope: the
/// active layer (or the selected pixels within it), or every layer of the active frame
/// (`frame_scope`). Like [`MoveDraft`] it is **non-destructive**: the document is never touched
/// while the draft is open (the rotation shows only as a *display-time* preview, nearest-
/// neighbour resampled about `pivot`); only `rotate_draft_commit` materializes it as one undo step.
/// The lifted sources (`layers`) are captured at begin so the preview, the commit, and the instant
/// quarter-turn buttons all rotate the exact same pixels. See `session/canvas.rs`.
struct RotateDraft {
    fid: u32,
    is_selection: bool,
    /// Frame scope: every layer of the frame was lifted. Mirrors `rotate_frame`'s quarter-turn
    /// policy — acts on everything, and commit clears the selection.
    frame_scope: bool,
    /// Selection at begin: drives clearing the origin pixels on commit and the undo `sel_before`.
    sel_before: Option<Arc<Mask>>,
    /// The lifted sources, one per involved layer (exactly one except in frame scope): a
    /// bbox-sized lift (selection) or the whole layer.
    layers: Vec<RotateDraftLayer>,
    sw: i32,
    sh: i32,
    src_origin: Point, // where src(0,0) sits in canvas coords: bbox top-left, or (0,0) for a layer
    src_mask: Option<Mask>, // bbox-sized mask of the lifted pixels (selection only; None = whole layer)
    pivot: PointF, // continuous canvas coords to rotate about: bbox centre, or canvas centre
    angle: f32,    // radians, clockwise (matches the Shape rotate handle's convention)
}

/// One lifted layer of a [`RotateDraft`].
struct RotateDraftLayer {
    lid: u32,
    src: RgbaBuffer,
}

/// Stamp positions along `a`→`b`, one every `step` px of arc length. `acc` is the distance already
/// travelled toward the next stamp (carried across calls so spacing stays even across a stroke that
/// arrives as many short segments); it is updated in place. The segment's own endpoints are not
/// implicitly stamped — the caller stamps the stroke's first point on press.
fn spaced_points(a: Point, b: Point, step: f32, acc: &mut f32) -> Vec<Point> {
    let mut out = Vec::new();
    let (ax, ay) = (a.x as f32, a.y as f32);
    let (dx, dy) = ((b.x - a.x) as f32, (b.y - a.y) as f32);
    let len = (dx * dx + dy * dy).sqrt();
    if len <= 0.0 {
        return out;
    }
    let (ux, uy) = (dx / len, dy / len);
    let step = step.max(1.0);
    let mut traveled = 0.0_f32;
    loop {
        let need = step - *acc; // distance from here to the next stamp
        if traveled + need > len {
            *acc += len - traveled; // ran out of segment; keep the partial distance
            break;
        }
        traveled += need;
        *acc = 0.0;
        out.push(Point::new((ax + ux * traveled).round() as i32, (ay + uy * traveled).round() as i32));
    }
    out
}

/// Apply a move draft's lift+move to `frame` in place: clear the origin (the selected pixels, or the
/// whole layer for a layer move) and blit the lifted content at the current offset, honouring Wrap.
/// Shared by the display preview (on a throwaway clone) and `move_draft_commit` (on the real frame),
/// so both render identically. Returns the translated selection mask for a selection move (for the
/// marquee + commit), else `None`.
fn move_draft_paint(d: &MoveDraft, frame: &mut crate::document::Frame, wrap: bool, canvas: IRect) -> Option<Mask> {
    if d.is_selection {
        let sel = d.sel_before.as_deref()?;
        let bb = sel.bounds()?;
        if let Some(f) = d.floats.first() {
            if let Some(li) = frame.layer_index_by_id(f.lid) {
                let buf = &mut frame.layers[li].pixels;
                for j in 0..bb.h as i32 {
                    for i in 0..bb.w as i32 {
                        if sel.get(bb.x + i, bb.y + j) {
                            buf.set(bb.x + i, bb.y + j, Rgba8::TRANSPARENT);
                        }
                    }
                }
                let dest = Point::new(f.anchor.x + d.offset.x, f.anchor.y + d.offset.y);
                if wrap {
                    buf.blit_wrapped(&f.pixels, dest.x, dest.y, canvas);
                } else {
                    buf.blit_over(&f.pixels, dest);
                }
            }
        }
        Some(if wrap {
            sel.translated_wrapped(d.offset.x, d.offset.y, canvas)
        } else {
            sel.translated(d.offset.x, d.offset.y)
        })
    } else {
        for f in &d.floats {
            if let Some(li) = frame.layer_index_by_id(f.lid) {
                let buf = &mut frame.layers[li].pixels;
                buf.clear();
                if wrap {
                    buf.blit_wrapped(&f.pixels, d.offset.x, d.offset.y, canvas);
                } else {
                    buf.blit_over(&f.pixels, Point::new(d.offset.x, d.offset.y));
                }
            }
        }
        None
    }
}

/// Whether two COW selection snapshots represent the same selection. Fast path: identical `Arc`
/// (the common case for a pixel-only edit, which reuses one snapshot for before+after) short-
/// circuits before any bit comparison.
fn sel_eq(a: &Option<Arc<Mask>>, b: &Option<Arc<Mask>>) -> bool {
    match (a, b) {
        (None, None) => true,
        (Some(x), Some(y)) => Arc::ptr_eq(x, y) || x == y,
        _ => false,
    }
}

/// Smallest rectangle covering both `a` and `b`.
/// Pixel-perfect corner test: is `b` the redundant middle of an L-shaped elbow `a → b → c`?
/// True when `a` and `c` are diagonal neighbours (one step apart on both axes) and `b` is the
/// orthogonal pixel wedged between them — the "corner double" a hand would never place.
fn pp_corner(a: Point, b: Point, c: Point) -> bool {
    (a.x == b.x || a.y == b.y)
        && (c.x == b.x || c.y == b.y)
        && (a.x - c.x).abs() == 1
        && (a.y - c.y).abs() == 1
}

fn union_irect(a: crate::geom::IRect, b: crate::geom::IRect) -> crate::geom::IRect {
    let x = a.x.min(b.x);
    let y = a.y.min(b.y);
    let right = a.right().max(b.right());
    let bottom = a.bottom().max(b.bottom());
    crate::geom::IRect::new(x, y, (right - x) as u32, (bottom - y) as u32)
}

pub struct Session {
    pub doc: Document,
    pub tool: ToolKind,
    pub settings: ToolSettings,
    /// How the next selection-tool gesture composes with the current selection (Replace/Add/…).
    /// Transient tool setting — like brush size, it is neither undone nor persisted. The mask
    /// itself now lives on [`Document`] (`doc.selection`) so it is undoable and serialized.
    pub selection_mode: CombineMode,
    /// Layers (within the active frame) selected to move/transform together (SPEC §15).
    pub layer_sel: Vec<usize>,
    /// Precision-pencil reticle position + active pen stroke (draw-by-button, off-finger).
    cursor: Point,
    precision_before: Option<EditScope>,
    /// Precision "Hold": the pen is logically down (drag segments paint). Each segment opens and
    /// commits its own `precision_before` edit (`cursor_stroke_begin`/`cursor_stroke_end`), so
    /// Undo mid-Hold reverts the LAST drag, not everything since Hold began.
    pen_held: bool,
    /// Pixel-perfect corner-filter tail for the precision pen line: the reticle path has no
    /// [`Stroke`], so its tail lives here (see `Stroke::pp` for the pointer-stroke twin).
    pen_pp: Vec<(Point, Rgba8)>,
    clipboard: Option<(RgbaBuffer, Point)>,
    // A pending paste: the clipboard pixels floating at a top-left position, previewed semi-
    // transparently and movable until committed (Copy & Paste tool). Editor state, not undoable
    // until commit.
    paste_draft: Option<(RgbaBuffer, Point)>,
    rng: SeededRng,
    clock: VirtualClock,
    playing: bool,
    stroke: Option<Stroke>,
    /// Distance (canvas px) travelled since the last spaced Brush/Airbrush/Dodge/Burn stamp in the current
    /// stroke. Carried across pointer/reticle moves so stamps stay evenly spaced regardless of how
    /// the path is chopped into events. Reset to 0 when a stroke begins.
    paint_acc: f32,
    /// Uncommitted figure (Line/Rectangle/Ellipse) being previewed and fine-tuned: its two
    /// defining endpoints in canvas pixels. The active tool decides how it renders. `None` when
    /// no draft is pending. Committed (rasterized) only on an explicit `shape_commit()`.
    shape_draft: Option<(Point, Point)>,
    /// Rotation of the pending shape draft (radians, around the box centre). Only the figure shapes
    /// (Rectangle/Ellipse/Triangle) honour it; Line/Gradient ignore it. Reset on commit/cancel.
    shape_rotation: f32,
    /// Horizontal skew of the pending Triangle draft's apex along its top edge, in [-1, 1] (0 = a
    /// centred isosceles triangle; ±1 = apex over a base corner = a right triangle). Triangle-only;
    /// reset on commit/cancel.
    triangle_tip: f32,
    last_gradient: Option<(GradientKind, Vec<Stop>, Point, Point, bool, u32, u32)>,
    /// Move-layer drag state: pre-drag pixel snapshots of each moved layer, plus the pre-drag
    /// frame (and its id) for a single grouped undo. Set on pointer_down, cleared on pointer_up.
    move_layers: Vec<(usize, RgbaBuffer)>,
    move_before: Option<(u32, crate::document::Frame)>,
    /// Union opaque bounding box of the moved layers at drag start (for "protect pixels" clamping).
    move_bbox: Option<crate::geom::IRect>,
    /// The pending move draft (relocatable, semi-transparently washed, committed on demand). The
    /// shell drives it via `MoveDraftBegin`/`MoveDraftMove`/`MoveDraftCommit`/`MoveDraftCancel`.
    move_draft: Option<MoveDraft>,
    /// The pending free-angle rotation draft (Rotate tool's "Angle" mode). Non-destructive, washed
    /// like a move draft, committed on demand. Driven via `RotateDraftBegin`/`RotateDraftSetAngle`/
    /// `RotateDraftCommit`/`RotateDraftCancel`; see `session/canvas.rs`.
    rotate_draft: Option<RotateDraft>,
    /// While a selection-mask drag is in progress (`MoveSelectionBegin`→`MoveSelectionCommit`), the
    /// selection at drag start. Set ⇒ the per-step `MoveSelection`s update the mask in place without
    /// recording, and the commit records a single undo step for the whole drag. `None` ⇒ a one-shot
    /// `MoveSelection` (DSL/nudge) records its own step immediately.
    move_sel_before: Option<Option<Arc<Mask>>>,
}

impl Session {
    pub fn new(w: u16, h: u16) -> Self {
        Session {
            doc: Document::new(w, h),
            tool: ToolKind::Pencil,
            settings: ToolSettings::default(),
            selection_mode: CombineMode::Replace,
            layer_sel: vec![0],
            cursor: Point::new(w as i32 / 2, h as i32 / 2),
            precision_before: None,
            pen_held: false,
            pen_pp: Vec::new(),
            clipboard: None,
            paste_draft: None,
            rng: SeededRng::default(),
            clock: VirtualClock::default(),
            playing: false,
            stroke: None,
            paint_acc: 0.0,
            shape_draft: None,
            shape_rotation: 0.0,
            triangle_tip: 0.0,
            last_gradient: None,
            move_layers: Vec::new(),
            move_before: None,
            move_bbox: None,
            move_draft: None,
            rotate_draft: None,
            move_sel_before: None,
        }
    }

    pub fn empty() -> Self {
        Session::new(64, 64)
    }

    /// Replace the selection and record the change as one undo step. Used by the *standalone*
    /// selection ops (marquee, invert, select-all/none, move-mask, select-by-alpha). Records nothing
    /// when the mask is unchanged. Changes that ride along with a pixel/structural edit (Move drag,
    /// nudge, crop/resize/rotate clear) instead assign `self.doc.selection` directly and let that
    /// edit's record capture the transition.
    fn set_selection(&mut self, new: Option<Mask>) {
        let before = self.doc.selection.clone();
        // Empty ⇒ None (Document::selection invariant): a combine that leaves zero pixels selected
        // (e.g. Subtract covering the whole selection) clears it, so drawing is free again.
        self.doc.selection = new.and_then(Mask::nonempty).map(Arc::new);
        if !sel_eq(&before, &self.doc.selection) {
            self.doc.record_selection(before);
        }
    }

    /// Current selection as an owned mask for read-only use (clip regions, bounds), cloning out of
    /// the COW `Arc`. `None` when there is no selection.
    fn selection_clone(&self) -> Option<Mask> {
        self.doc.selection.as_deref().cloned()
    }

    /// Compose `shape` into the current selection per `mode` and record it as one undo step (the
    /// shared body of the marquee tools and select-by-alpha).
    fn combine_selection(&mut self, shape: &Mask, mode: CombineMode) {
        let s = self.doc.storage();
        let (w, h) = (s.w as u32, s.h as u32);
        // Hold the incoming shape inside the selectable window (canvas, or storage under overscan) so
        // a gesture that strays into the gutter can't select off-canvas pixels unless allowed.
        let mut shape = shape.clone();
        shape.intersect_rect(self.selection_clip());
        let mut m = self.selection_clone().unwrap_or_else(|| Mask::new(w, h));
        m.combine(&shape, mode);
        self.set_selection(Some(m));
    }

    // ---- read API used by FFI / tests / probes ----

    pub fn size(&self) -> (u16, u16) {
        (self.doc.size.w, self.doc.size.h)
    }

    /// The dimensions of the buffer `display_bytes` returns and the coverage `outline_mask_bytes`
    /// writes: the whole storage (canvas + gutter) when the overscan view is on, else the canvas.
    pub fn display_size(&self) -> (u32, u32) {
        if self.settings.overscan_view {
            let s = self.doc.storage();
            (s.w as u32, s.h as u32)
        } else {
            (self.doc.size.w as u32, self.doc.size.h as u32)
        }
    }

    pub fn composite_active_bytes(&self) -> Vec<u8> {
        render::composite_active(&self.doc).to_rgba_bytes()
    }

    pub fn composite_frame_bytes(&self, frame: usize) -> Vec<u8> {
        let f = &self.doc.frames[frame.min(self.doc.frames.len() - 1)];
        // Export/publish path: always the canvas window, never the gutter.
        render::composite_frame(f, self.doc.canvas_rect()).to_rgba_bytes()
    }

    /// Content hash of a frame (low 64 bits) — used by the shell to cache thumbnails.
    pub fn frame_hash(&self, frame: usize) -> u64 {
        let i = frame.min(self.doc.frames.len() - 1);
        self.doc.frames[i].content_hash() as u64
    }

    /// A small nearest-downscaled composite of `frame` (`tw`×`th` straight RGBA) for the
    /// film-roll thumbnails — keeps shell memory bounded for big animations.
    pub fn frame_thumb_bytes(&self, frame: usize, tw: u32, th: u32) -> Vec<u8> {
        let i = frame.min(self.doc.frames.len() - 1);
        let (w, h) = (self.doc.size.w as u32, self.doc.size.h as u32);
        let flat = render::composite_frame(&self.doc.frames[i], self.doc.canvas_rect());
        let (tw, th) = (tw.max(1), th.max(1));
        let mut out = vec![0u8; (tw * th * 4) as usize];
        for ty in 0..th {
            for tx in 0..tw {
                let sx = (tx * w / tw) as i32;
                let sy = (ty * h / th) as i32;
                let c = flat.get(sx, sy);
                let o = ((ty * tw + tx) * 4) as usize;
                out[o] = c.r;
                out[o + 1] = c.g;
                out[o + 2] = c.b;
                out[o + 3] = c.a;
            }
        }
        out
    }

    /// A `tw`×`th` nearest-downscaled thumbnail of a single layer's raw pixels (straight RGBA,
    /// transparent where empty) — for the layers film-strip, which shows each layer alone.
    pub fn layer_thumb_bytes(&self, frame: usize, layer: usize, tw: u32, th: u32) -> Vec<u8> {
        let fi = frame.min(self.doc.frames.len().saturating_sub(1));
        let f = &self.doc.frames[fi];
        if f.layers.is_empty() {
            return Vec::new();
        }
        let li = layer.min(f.layers.len() - 1);
        let src = &f.layers[li].pixels;
        let (w, h) = (self.doc.size.w as u32, self.doc.size.h as u32);
        let org = self.doc.origin(); // sample the canvas window of the storage-sized layer buffer
        let (tw, th) = (tw.max(1), th.max(1));
        let mut out = vec![0u8; (tw * th * 4) as usize];
        for ty in 0..th {
            for tx in 0..tw {
                let sx = org.x + (tx * w / tw) as i32;
                let sy = org.y + (ty * h / th) as i32;
                let c = src.get(sx, sy);
                let o = ((ty * tw + tx) * 4) as usize;
                out[o] = c.r;
                out[o + 1] = c.g;
                out[o + 2] = c.b;
                out[o + 3] = c.a;
            }
        }
        out
    }

    /// The full-resolution raw pixels of a single layer's canvas window (w×h straight RGBA, the
    /// layer alone — not the composite) — for the layer PNG export. Bounds-safe: stale indices
    /// clamp, so a bad index can never panic across the FFI boundary; empty when the frame has
    /// no layers.
    pub fn layer_rgba_bytes(&self, frame: usize, layer: usize) -> Vec<u8> {
        let fi = frame.min(self.doc.frames.len().saturating_sub(1));
        let f = &self.doc.frames[fi];
        if f.layers.is_empty() {
            return Vec::new();
        }
        let li = layer.min(f.layers.len() - 1);
        let src = &f.layers[li].pixels;
        let (w, h) = (self.doc.size.w as u32, self.doc.size.h as u32);
        let org = self.doc.origin(); // the canvas window of the storage-sized layer buffer
        let mut out = vec![0u8; (w * h * 4) as usize];
        for y in 0..h {
            for x in 0..w {
                let c = src.get(org.x + x as i32, org.y + y as i32);
                let o = ((y * w + x) * 4) as usize;
                out[o] = c.r;
                out[o + 1] = c.g;
                out[o + 2] = c.b;
                out[o + 3] = c.a;
            }
        }
        out
    }

    /// Content hash (low 64 bits) of a single layer — for caching layer film-strip thumbnails.
    /// Bounds-safe (clamps indices) so it is safe to call across the FFI with possibly stale
    /// indices, unlike the unchecked `layer_hash` used by the CLI probe.
    pub fn layer_thumb_hash(&self, frame: usize, layer: usize) -> u64 {
        let fi = frame.min(self.doc.frames.len().saturating_sub(1));
        let f = &self.doc.frames[fi];
        if f.layers.is_empty() {
            return 0;
        }
        let li = layer.min(f.layers.len() - 1);
        f.layers[li].content_hash() as u64
    }

    pub fn display_bytes(&self, onion: bool, grid: bool, checker: bool) -> Vec<u8> {
        let af = self.doc.active_frame;
        let n = self.doc.frames.len();
        let ov = render::Overlays {
            // Onion neighbours wrap around the ends — all animations are loops, so frame 0's
            // "previous" is the last frame and the last frame's "next" is frame 0. A single frame
            // has no neighbour; with two frames prev and next are the same frame, which is shown
            // once (as prev) rather than blitted twice with both tints.
            onion_prev: if onion && n > 1 { Some(&self.doc.frames[(af + n - 1) % n]) } else { None },
            onion_next: if onion && n > 2 { Some(&self.doc.frames[(af + 1) % n]) } else { None },
            grid,
            checker_bg: checker,
            // The reticle is now drawn by the UI as a thin, screen-space, marching-ants overlay
            // (not baked into canvas pixels), so the engine no longer renders it.
            cursor: None,
        };
        // A move/rotate draft or a pending HSV / brightness-contrast adjustment renders as a
        // display-only preview: composite a clone of the active frame with it applied (the
        // document is untouched until Commit).
        let preview = self
            .move_draft_preview_frame()
            .or_else(|| self.rotate_draft_preview_frame())
            .or_else(|| self.hsv_preview_frame())
            .or_else(|| self.bc_preview_frame());
        let frame = preview.as_ref().unwrap_or_else(|| self.doc.active_frame());
        // Render the whole storage area so the tool previews (which draw in storage coordinates) need
        // no offset; then crop to the canvas for the normal view, or emit the whole thing (gutter
        // dimmed) for the overscan view. [perf: storage-sized checker fill — optimise if it bites]
        let mut buf = render::render_display(frame, self.doc.storage_rect(), &ov);
        self.draw_tool_preview(&mut buf);
        if self.settings.overscan_view {
            self.dim_gutter(&mut buf); // darken the off-canvas gutter so the canvas stands out
            buf.to_rgba_bytes()
        } else {
            buf.to_rgba_bytes_rect(self.doc.canvas_rect())
        }
    }

    /// Darken every pixel of the storage-sized display buffer that lies outside the canvas rect — the
    /// off-canvas gutter — so the overscan view reads clearly as "beyond the canvas". Buffer coords
    /// are storage coords (the display was rendered over `storage_rect`).
    fn dim_gutter(&self, buf: &mut RgbaBuffer) {
        let cr = self.doc.canvas_rect();
        let st = self.doc.storage();
        let wash = Rgba8::new(0, 0, 0, 130);
        for y in 0..st.h as i32 {
            for x in 0..st.w as i32 {
                if !cr.contains(Point::new(x, y)) {
                    buf.blend_over(x, y, wash);
                }
            }
        }
    }

    /// Live preview of a drag-in-progress for shape/selection/gradient/move tools, drawn on
    /// top of the display so the user can fine-tune before releasing.
    /// Blend a figure (Line/Rectangle/Ellipse) between `a` and `b` into `buf`, honouring the
    /// fill/outline + line-width settings. Used both for the live preview and the draft preview.
    fn render_shape_preview(&self, buf: &mut RgbaBuffer, a: Point, b: Point) {
        let color = self.settings.primary;
        let lw = self.settings.line_width.max(1) as i32;
        let fill = self.settings.shape_fill;
        let rot = self.shape_rotation;
        // The Triangle carries its own rotation + apex skew through one path.
        if self.tool == ToolKind::Triangle {
            if fill {
                crate::raster::triangle_filled(a, b, rot, self.triangle_tip, |x, y| buf.blend_over(x, y, color));
            } else {
                crate::raster::triangle_outline(a, b, rot, self.triangle_tip, lw, |x, y| buf.blend_over(x, y, color));
            }
            return;
        }
        // A rotated Rectangle/Ellipse previews through the exact inverse-rotation rasteriser.
        if rot.abs() > 1e-4 {
            let k = match self.tool {
                ToolKind::Rectangle => Some(0u8),
                ToolKind::Ellipse => Some(1),
                _ => None,
            };
            if let Some(k) = k {
                crate::raster::rotated_shape(a, b, rot, k, fill, lw, |x, y| buf.blend_over(x, y, color));
                return;
            }
        }
        match self.tool {
            ToolKind::Line => crate::raster::thick_line(a, b, lw, |x, y| buf.blend_over(x, y, color)),
            ToolKind::Rectangle => {
                if fill {
                    crate::raster::rect_filled(a, b, |x, y| buf.blend_over(x, y, color));
                } else {
                    crate::raster::rect_outline(a, b, lw, |x, y| buf.blend_over(x, y, color));
                }
            }
            ToolKind::Ellipse => {
                if fill {
                    crate::raster::ellipse_filled(a, b, |x, y| buf.blend_over(x, y, color));
                } else {
                    crate::raster::ellipse_outline(a, b, lw, |x, y| buf.blend_over(x, y, color));
                }
            }
            _ => {}
        }
    }

    /// Fill the gradient (p0=a → p1=b) into `buf`, clipped to the selection. Used for both the live
    /// pointer-drag preview and the draft preview.
    fn render_gradient_preview(&self, buf: &mut RgbaBuffer, a: Point, b: Point) {
        let spec = &self.settings.gradient;
        // The gradient is canvas-only; bound the preview fill to the canvas window (storage coords).
        let cr = self.doc.canvas_rect();
        // Sort stops once (not per pixel); a selection bounds the fill to its bbox. [audit F-14/F-15]
        let mut stops = spec.stops.clone();
        stops.sort_by(|p, q| p.t.total_cmp(&q.t));
        let (x0, y0, x1, y1) = match self.doc.selection.as_ref().and_then(|m| m.bounds()) {
            Some(bb) => (
                bb.x.max(cr.x),
                bb.y.max(cr.y),
                (bb.x + bb.w as i32).min(cr.right()),
                (bb.y + bb.h as i32).min(cr.bottom()),
            ),
            None => (cr.x, cr.y, cr.right(), cr.bottom()),
        };
        for y in y0..y1 {
            for x in x0..x1 {
                if let Some(m) = &self.doc.selection {
                    if !m.get(x, y) {
                        continue;
                    }
                }
                buf.set(x, y, tool::gradient_eval_sorted(spec.kind, &stops, a, b, x, y, spec.smoothstep));
            }
        }
    }

    /// Preview a paste draft: the clip's pixels dimmed (alpha ~60%) and washed with a cyan tint so
    /// it reads as a temporary, not-yet-committed overlay. Cropped to the canvas via `blend_over`.
    fn render_paste_preview(&self, buf: &mut RgbaBuffer, clip: &RgbaBuffer, pos: Point) {
        let tint = Rgba8::new(0, 200, 255, 70); // "this is a draft" wash
        for j in 0..clip.height() as i32 {
            for i in 0..clip.width() as i32 {
                let c = clip.get(i, j);
                if c.a == 0 {
                    continue;
                }
                let (x, y) = (pos.x + i, pos.y + j);
                buf.blend_over(x, y, Rgba8::new(c.r, c.g, c.b, (c.a as u16 * 3 / 5) as u8));
                buf.blend_over(x, y, tint);
            }
        }
    }

    fn draw_tool_preview(&self, buf: &mut RgbaBuffer) {
        // A pending rotate draft: the preview frame already shows the rotated pixels, so just wash
        // their footprint with the soft "draft" tint so they read as not-yet-committed.
        if self.rotate_draft.as_ref().filter(|d| d.fid == self.doc.active_frame().id).is_some() {
            self.rotate_draft_wash_into(buf);
            return;
        }
        // A pending move draft: the moved pixels are already in the layer (crash-safe), so just wash
        // them with a soft semi-transparent tint to mark "pending until Commit". Only wash when the
        // draft's own frame is the one being displayed (the user may have switched frames).
        if let Some(d) = self.move_draft.as_ref().filter(|d| d.fid == self.doc.active_frame().id) {
            let wash = Rgba8::new(0, 200, 255, 60); // soft cyan "draft" wash (matches the paste hue)
            let (w, h) = (self.doc.size.w as i32, self.doc.size.h as i32);
            for f in &d.floats {
                for j in 0..f.pixels.height() as i32 {
                    for i in 0..f.pixels.width() as i32 {
                        if f.pixels.get(i, j).a == 0 {
                            continue;
                        }
                        let (mut x, mut y) = (f.anchor.x + d.offset.x + i, f.anchor.y + d.offset.y + j);
                        if self.settings.wrap {
                            x = x.rem_euclid(w);
                            y = y.rem_euclid(h);
                        }
                        buf.blend_over(x, y, wash);
                    }
                }
            }
            return;
        }
        // A pending paste floats above everything as a dimmed, cyan-washed draft until committed.
        if let Some((clip, pos)) = &self.paste_draft {
            self.render_paste_preview(buf, clip, *pos);
            return;
        }
        // Select-Layer: tint exactly the pixels the alpha cutoff would select (active layer's
        // alpha > cutoff — the opaque/drawn pixels), so the user sees pixel-perfectly what an
        // action will use. Shown whenever the tool is active — no stroke needed.
        if self.tool == ToolKind::SelectLayer {
            let cutoff = self.settings.alpha_cutoff;
            let overlay = Rgba8::new(0, 229, 255, 120); // semi-transparent cyan
            let layer = self.doc.active_frame().active_layer();
            // Only pixels with alpha > cutoff (≥0) are tinted, and those are all opaque, so the
            // opaque bounding box is an exact, much smaller scan window than the full canvas. [F-15]
            if let Some(bb) = layer.pixels.opaque_bounds() {
                for y in bb.y..bb.y + bb.h as i32 {
                    for x in bb.x..bb.x + bb.w as i32 {
                        if layer.pixels.get(x, y).a > cutoff {
                            buf.blend_over(x, y, overlay);
                        }
                    }
                }
            }
            return;
        }
        // A pending draft (the forgiving draw → adjust → commit flow) renders on its own,
        // independent of any pointer stroke. Shared by the figure tools and the gradient.
        if let Some((a, b)) = self.shape_draft {
            match self.tool {
                ToolKind::Line | ToolKind::Rectangle | ToolKind::Ellipse | ToolKind::Triangle => {
                    self.render_shape_preview(buf, a, b);
                    return;
                }
                ToolKind::Gradient => {
                    self.render_gradient_preview(buf, a, b);
                    return;
                }
                _ => {}
            }
        }
        let stroke = match &self.stroke {
            Some(s) => s,
            None => return,
        };
        let (a, b) = (stroke.start, stroke.last);
        match self.tool {
            // Legacy immediate-draw previews (CLI / DSL pointer drags); the shell uses the draft
            // path above. Selection-tool outlines are not baked in (the shell draws marching ants).
            ToolKind::Line | ToolKind::Rectangle | ToolKind::Ellipse | ToolKind::Triangle => self.render_shape_preview(buf, a, b),
            ToolKind::Gradient => self.render_gradient_preview(buf, a, b),
            ToolKind::Move => {
                if let (Some(float), Some(sel)) = (&stroke.floating, &self.doc.selection) {
                    if let Some(bb) = sel.bounds() {
                        let (dx, dy) = (b.x - a.x, b.y - a.y);
                        if self.settings.wrap {
                            buf.blit_wrapped(float, bb.x + dx, bb.y + dy, self.doc.canvas_rect());
                        } else {
                            buf.blit_over(float, Point::new(bb.x + dx, bb.y + dy));
                        }
                    }
                }
            }
            _ => {}
        }
    }

    /// The selection mask the shell should outline: the committed selection, or — while a
    /// selection tool is being dragged — a live preview of (current selection ∘ drag shape).
    pub fn outline_mask(&self) -> Option<Mask> {
        let s = self.doc.storage();
        let (w, h) = (s.w as u32, s.h as u32);
        // While a selection rotate draft is open the marquee follows the (preview) rotated mask,
        // even though the document's selection isn't touched until Commit.
        if let Some(m) = self.rotate_draft_outline() {
            return Some(m);
        }
        // While a selection move draft is open the marquee follows the (preview) move, even though
        // the document's selection isn't touched until Commit.
        if let Some(d) = self.move_draft.as_ref().filter(|d| d.is_selection) {
            if let Some(sel) = d.sel_before.as_deref() {
                return Some(if self.settings.wrap {
                    sel.translated_wrapped(d.offset.x, d.offset.y, self.doc.canvas_rect())
                } else {
                    sel.translated(d.offset.x, d.offset.y)
                });
            }
        }
        if let Some(stroke) = &self.stroke {
            let (a, b) = (stroke.start, stroke.last);
            let shape = match self.tool {
                ToolKind::SelectRect => Some(Mask::from_plot(w, h, |p| crate::raster::rect_filled(a, b, p))),
                ToolKind::SelectEllipse => Some(Mask::from_plot(w, h, |p| crate::raster::ellipse_filled(a, b, p))),
                ToolKind::SelectCircle => Some(Mask::from_plot(w, h, |p| crate::raster::circle_filled(a, b, p))),
                ToolKind::SelectPoly | ToolKind::SelectFree => {
                    let path = stroke.path.clone();
                    Some(Mask::from_plot(w, h, |p| crate::raster::polygon_filled(&path, p)))
                }
                _ => None,
            };
            if let Some(mut shape) = shape {
                shape.intersect_rect(self.selection_clip());
                let mut m = self.selection_clone().unwrap_or_else(|| Mask::new(w, h));
                m.combine(&shape, self.selection_mode);
                return Some(m);
            }
        }
        self.selection_clone()
    }

    /// Fill `out` with 1-byte-per-pixel selection coverage (1=selected). Returns the number
    /// of bytes written, or 0 when there is nothing to outline.
    pub fn outline_mask_bytes(&self, out: &mut [u8]) -> usize {
        let m = match self.outline_mask() {
            Some(m) if !m.is_empty() => m,
            _ => return 0,
        };
        // Overscan on → emit the whole storage-sized mask (the shell traces gutter edges too);
        // otherwise emit just the canvas window, offset by the gutter origin so a canvas coordinate
        // maps to the right storage cell.
        let (w, h, org) = if self.settings.overscan_view {
            let st = self.doc.storage();
            (st.w as usize, st.h as usize, Point::new(0, 0))
        } else {
            (self.doc.size.w as usize, self.doc.size.h as usize, self.doc.origin())
        };
        let n = (w * h).min(out.len());
        for (i, slot) in out.iter_mut().enumerate().take(n) {
            let x = org.x + (i % w) as i32;
            let y = org.y + (i / w) as i32;
            *slot = m.get(x, y) as u8;
        }
        n
    }

    /// Bounds-safe pixel read for FFI/CLI probes: clamps a stale frame/layer index (and
    /// `RgbaBuffer::get` already returns transparent out of bounds), so a bad index can never panic
    /// across the boundary. [audit F-28]
    pub fn pixel(&self, f: usize, l: usize, x: i32, y: i32) -> Rgba8 {
        // `x,y` are canvas-relative (gutter reachable via negative / ≥ canvas coords); map to storage.
        let o = self.doc.origin();
        let (x, y) = (x + o.x, y + o.y);
        let frame = match self.doc.frames.get(f.min(self.doc.frames.len().saturating_sub(1))) {
            Some(fr) => fr,
            None => return Rgba8::TRANSPARENT,
        };
        match frame.layers.get(l.min(frame.layers.len().saturating_sub(1))) {
            Some(layer) => layer.pixels.get(x, y),
            None => Rgba8::TRANSPARENT,
        }
    }

    /// Bounds-safe layer content hash (clamps stale indices) — safe to call across the FFI. [F-28]
    pub fn layer_hash(&self, f: usize, l: usize) -> Hash {
        let fi = f.min(self.doc.frames.len().saturating_sub(1));
        let frame = match self.doc.frames.get(fi) {
            Some(fr) => fr,
            None => return 0,
        };
        match frame.layers.get(l.min(frame.layers.len().saturating_sub(1))) {
            Some(layer) => layer.pixels.content_hash(),
            None => 0,
        }
    }

    pub fn state_json(&self) -> String {
        // Session-level fields (the clipboard + a pending paste draft live on Session, not Document)
        // are appended to the document state JSON before its closing brace.
        let mut s = crate::probe::state_json(&self.doc);
        let rect = |r: Option<IRect>| match r {
            Some(r) => format!("[{},{},{},{}]", r.x, r.y, r.w, r.h),
            None => "null".to_string(),
        };
        // The rotate draft carries its pre-rotation region bbox + the live angle so the shell can
        // place the rotate handle (centre = bbox centre, arm reaches a corner) and show the angle.
        let rotate_draft = match self.rotate_draft_rect() {
            Some(r) => format!(
                "{{\"x\":{},\"y\":{},\"w\":{},\"h\":{},\"angle_mrad\":{}}}",
                r.x,
                r.y,
                r.w,
                r.h,
                self.rotate_draft_angle_mrad().unwrap_or(0)
            ),
            None => "null".to_string(),
        };
        // Gutter geometry for the shell: `storage` is the full off-canvas area, `origin` the canvas
        // top-left within it, `overscan` whether the display is currently the whole storage.
        let st = self.doc.storage();
        let og = self.doc.origin();
        let extra = format!(
            ",\"has_clipboard\":{},\"paste\":{},\"move_draft\":{},\"rotate_draft\":{},\"storage\":[{},{}],\"origin\":[{},{}],\"overscan\":{}",
            self.clipboard.is_some(),
            rect(self.paste_draft_rect()),
            rect(self.move_draft_rect()),
            rotate_draft,
            st.w,
            st.h,
            og.x,
            og.y,
            self.settings.overscan_view,
        );
        s.insert_str(s.len() - 1, &extra); // before the final '}'
        s
    }

    pub fn current_play_frame(&self) -> usize {
        if self.doc.frames.len() <= 1 {
            return 0;
        }
        let total: u64 = self.doc.frames.iter().map(|f| f.duration_us as u64).sum();
        if total == 0 {
            return self.doc.active_frame;
        }
        let mut t = self.clock.now_us % total.max(1);
        // ping-pong handled at a higher level; here use linear loop ordering.
        if self.doc.anim.loop_mode == LoopMode::PingPong {
            let cycle = total * 2;
            t = self.clock.now_us % cycle;
            if t >= total {
                t = cycle - t;
            }
        }
        let mut acc = 0u64;
        for (i, f) in self.doc.frames.iter().enumerate() {
            acc += f.duration_us as u64;
            if t < acc {
                return i;
            }
        }
        self.doc.frames.len() - 1
    }

    // ---- undo-recording helpers ----

    fn begin_edit(&self) -> EditScope {
        let f = self.doc.active_frame();
        let l = f.active_layer();
        EditScope {
            fid: f.id,
            lid: l.id,
            before: l.pixels.snapshot(),
            sel_before: self.doc.selection.clone(),
        }
    }

    fn commit_edit(&mut self, scope: EditScope) {
        // Resolve the snapshot's OWN frame/layer by id — not the current active one, which the DSL
        // may have changed mid-stroke — so the recorded patch always matches `before`. [audit F-29]
        let EditScope { fid, lid, before, sel_before } = scope;
        let patch = match self
            .doc
            .frame_index_by_id(fid)
            .and_then(|fi| self.doc.frames[fi].layer_index_by_id(lid).map(|li| (fi, li)))
        {
            Some((fi, li)) => self.doc.frames[fi].layers[li].pixels.diff_from(&before),
            None => return, // the target frame/layer was deleted mid-edit; nothing to record
        };
        if patch.is_empty() {
            // No pixels changed, but the mask may have (e.g. a Move/nudge of a selection that covers
            // only transparent pixels). Record the selection move alone so it's still undoable.
            if !sel_eq(&sel_before, &self.doc.selection) {
                self.doc.record_selection(sel_before);
            }
            return;
        }
        self.doc.record_pixels(fid, lid, patch, sel_before);
    }

    /// Restore a captured snapshot to the exact frame/layer it came from (mirrors `commit_edit`'s
    /// id resolution), used when a stroke is cancelled. [audit F-29]
    fn restore_edit(&mut self, scope: &EditScope) {
        if let Some(fi) = self.doc.frame_index_by_id(scope.fid) {
            if let Some(li) = self.doc.frames[fi].layer_index_by_id(scope.lid) {
                self.doc.frames[fi].layers[li].pixels.restore_snapshot(&scope.before);
            }
        }
    }

    fn edit_frame<R>(&mut self, f: impl FnOnce(&mut Session) -> R) -> R {
        let fi = self.doc.active_frame;
        let before = self.doc.frames[fi].clone();
        let fid = self.doc.frames[fi].id;
        let sel_before = self.doc.selection.clone();
        let r = f(self);
        let after = self.doc.frames[fi].clone();
        self.doc.record_frame_content(fid, before, after, sel_before);
        r
    }

    fn edit_doc<R>(&mut self, label: &str, f: impl FnOnce(&mut Session) -> R) -> R {
        let before = self.doc.frames.clone();
        let before_active = self.doc.active_frame;
        let before_size = self.doc.size;
        let sel_before = self.doc.selection.clone();
        let r = f(self);
        self.doc.record_doc_structure(label, before, before_active, before_size, sel_before);
        r
    }

    fn active_editable(&self) -> bool {
        let l = self.doc.active_frame().active_layer();
        l.visible && !l.locked
    }

    /// The window (storage coords) that **paint** tools may write into: always the canvas — tools
    /// never draw into the off-canvas gutter (SPEC §8, §15). The gutter is reached only by Move,
    /// paste and the canvas transforms.
    fn paint_clip(&self) -> IRect {
        self.doc.canvas_rect()
    }

    /// The window (storage coords) a **selection** gesture may cover. Canvas-only today; the overscan
    /// view (Phase 3) widens this to the whole storage so parked pixels can be selected.
    fn selection_clip(&self) -> IRect {
        if self.settings.overscan_view {
            self.doc.storage_rect()
        } else {
            self.doc.canvas_rect()
        }
    }

    // ---- pointer routing ----

    pub fn pointer_down(&mut self, x: i32, y: i32) {
        // Defense-in-depth: never start a stroke on top of an unfinished one. A malformed event
        // sequence (e.g. a dropped pointer_up) must not orphan the undo baseline, so finalize the
        // previous stroke first — this keeps every begin_edit paired with a commit.
        if self.stroke.is_some() {
            self.pointer_up();
        }
        // Likewise never leave a precision-pen line open beneath a new pointer stroke — two open
        // edits would both diff the same layer and double-record the overlapping pixels. [F-29]
        if self.precision_before.is_some() {
            self.cursor_pen_up();
        }
        let p = self.clamp_pointer(Point::new(x, y)); // bound off-canvas input [F-6]
        // Tools that act once on press.
        match self.tool {
            ToolKind::Eyedropper => {
                let c = render::composite_active(&self.doc).get(x, y);
                if c.a != 0 {
                    self.settings.primary = c;
                }
                return;
            }
            _ => {}
        }
        let before = self.begin_edit();
        self.paint_acc = 0.0; // fresh stroke → reset Brush/Airbrush spacing
        let mut floating = None;
        // Pixel-perfect Pencil: seeds the corner-double filter with the first painted pixel (captured
        // with its pre-stroke colour so a later removal restores it). Empty for every other case.
        let mut pp = Vec::new();
        // The single Move tool moves the selected pixels when there's a selection, else the layer.
        let has_sel = self.doc.selection.as_ref().and_then(|s| s.bounds()).is_some();
        // Paint-immediately tools.
        if self.active_editable() {
            match self.tool {
                ToolKind::Pencil if self.pixel_perfect_active() => {
                    // Plot the first pixel ourselves so we can record its pre-stroke colour as the
                    // seed of the pixel-perfect sequence (see `pencil_perfect_step`).
                    let color = self.settings.primary;
                    let clip = self.paint_clip();
                    let sel = self.selection_clone();
                    let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
                    let orig = buf.get(p.x, p.y);
                    tool::plot(buf, sel.as_ref(), clip, p.x, p.y, color, PaintMode::Replace);
                    pp.push((p, orig));
                }
                ToolKind::Pencil => self.stamp_active(p, PaintMode::Replace, self.settings.primary),
                ToolKind::Brush => self.stamp_active(p, PaintMode::Over, self.settings.primary),
                ToolKind::Eraser => self.stamp_active(p, PaintMode::Erase, Rgba8::TRANSPARENT),
                ToolKind::Airbrush => self.airbrush_active(p),
                ToolKind::Dodge => self.dodge_burn_active(p, self.dodge_dv(true)),
                ToolKind::Burn => self.dodge_burn_active(p, self.dodge_dv(false)),
                ToolKind::Bucket => self.flood_fill_at(p),
                ToolKind::Move => {
                    // lift selected pixels into a floating buffer
                    if let Some(sel) = self.selection_clone() {
                        if let Some(bb) = sel.bounds() {
                            let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
                            let mut float = RgbaBuffer::new(bb.w, bb.h);
                            for j in 0..bb.h as i32 {
                                for i in 0..bb.w as i32 {
                                    if sel.get(bb.x + i, bb.y + j) {
                                        float.set(i, j, buf.get(bb.x + i, bb.y + j));
                                    }
                                }
                            }
                            floating = Some(float);
                        }
                    }
                }
                _ => {}
            }
        }
        // Move tool with NO selection → move the layer(s): snapshot every selected, editable layer
        // (the move-group, or just the active layer when none is grouped) plus the pre-drag frame,
        // so pointer_move can re-blit them at the live offset and pointer_up records one grouped undo.
        if self.tool == ToolKind::Move && !has_sel {
            let fi = self.doc.active_frame;
            let editable = |li: usize, f: &crate::document::Frame| {
                li < f.layers.len() && f.layers[li].visible && !f.layers[li].locked
            };
            let mut sel: Vec<usize> = self
                .layer_sel
                .iter()
                .copied()
                .filter(|&li| editable(li, &self.doc.frames[fi]))
                .collect();
            sel.sort_unstable();
            sel.dedup();
            if sel.is_empty() {
                let al = self.doc.frames[fi].active_layer;
                if editable(al, &self.doc.frames[fi]) {
                    sel.push(al);
                }
            }
            self.move_layers = sel
                .iter()
                .map(|&li| (li, self.doc.frames[fi].layers[li].pixels.clone()))
                .collect();
            self.move_before = Some((self.doc.frames[fi].id, self.doc.frames[fi].clone()));
            // Union opaque bbox at drag start, for "protect pixels" offset clamping.
            self.move_bbox = self.move_layers.iter().fold(None, |acc, (_li, snap)| {
                match (acc, snap.opaque_bounds()) {
                    (Some(a), Some(b)) => Some(union_irect(a, b)),
                    (a, b) => a.or(b),
                }
            });
        }
        self.stroke = Some(Stroke { before, start: p, last: p, path: vec![p], floating, pp });
    }

    pub fn pointer_move(&mut self, x: i32, y: i32) {
        let p = self.clamp_pointer(Point::new(x, y)); // bound off-canvas input [F-6]
        let last = match &self.stroke {
            Some(s) => s.last,
            None => return,
        };
        // Move tool in layer-move mode (no selection at drag start → move_before is set): re-blit
        // each snapshotted layer of the move-group at the live offset from the drag start (single
        // grouped undo, committed on pointer_up). move_layers and doc are disjoint fields, so the
        // index-based borrow is sound.
        if self.move_before.is_some() {
            let start = match self.stroke.as_ref() {
                Some(s) => s.start,
                None => return,
            };
            let (mut dx, mut dy) = (p.x - start.x, p.y - start.y);
            let wrap = self.settings.wrap;
            // Protect pixels: clamp the offset so opaque content never leaves the canvas — the
            // layer simply stops at the edge instead of being shown in an illegal position.
            if self.settings.protect_pixels {
                if let Some(bb) = self.move_bbox {
                    let (cx, cy) = self.clamp_move_to_canvas(bb, dx, dy);
                    dx = cx;
                    dy = cy;
                }
            }
            let fi = self.doc.active_frame;
            let cr = self.doc.canvas_rect();
            for idx in 0..self.move_layers.len() {
                let li = self.move_layers[idx].0;
                if li < self.doc.frames[fi].layers.len() {
                    let snap = &self.move_layers[idx].1;
                    let buf = &mut self.doc.frames[fi].layers[li].pixels;
                    buf.clear();
                    // Wrap: pixels leaving one edge re-enter the opposite one. Regular: clip them.
                    if wrap {
                        buf.blit_wrapped(snap, dx, dy, cr);
                    } else {
                        buf.blit_over(snap, Point::new(dx, dy));
                    }
                }
            }
            if let Some(s) = self.stroke.as_mut() {
                s.last = p;
                s.path.push(p);
            }
            return;
        }
        if self.active_editable() {
            match self.tool {
                ToolKind::Pencil if self.pixel_perfect_active() => self.pencil_perfect_step(last, p),
                ToolKind::Pencil => self.stroke_active(last, p, PaintMode::Replace, self.settings.primary),
                ToolKind::Brush => self.brush_stroke_spaced(last, p, PaintMode::Over, self.settings.primary),
                ToolKind::Eraser => self.stroke_active(last, p, PaintMode::Erase, Rgba8::TRANSPARENT),
                ToolKind::Airbrush => self.airbrush_stroke_spaced(last, p),
                ToolKind::Dodge => self.dodge_burn_stroke_spaced(last, p, self.dodge_dv(true)),
                ToolKind::Burn => self.dodge_burn_stroke_spaced(last, p, self.dodge_dv(false)),
                _ => {}
            }
        }
        if let Some(s) = &mut self.stroke {
            s.last = p;
            s.path.push(p);
        }
    }

    pub fn pointer_up(&mut self) {
        let stroke = match self.stroke.take() {
            Some(s) => s,
            None => return,
        };
        // Move tool in layer-move mode: commit the grouped translation as one frame-content undo
        // (or discard it if nothing actually moved, e.g. a tap).
        if self.move_before.is_some() {
            if let Some((fid, before)) = self.move_before.take() {
                if stroke.start != stroke.last {
                    let fi = self.doc.active_frame;
                    let after = self.doc.frames[fi].clone();
                    // A layer move leaves the selection untouched, so before == after (free record).
                    let sel_before = self.doc.selection.clone();
                    self.doc.record_frame_content(fid, before, after, sel_before);
                }
            }
            self.move_layers.clear();
            self.move_bbox = None;
            return;
        }
        let (start, last) = (stroke.start, stroke.last);

        if self.active_editable() {
            match self.tool {
                ToolKind::Gradient => {
                    let spec = self.settings.gradient.clone();
                    let clip = self.paint_clip();
                    let sel = self.selection_clone();
                    let (fi, li) = (self.doc.active_frame, self.doc.active_frame().active_layer);
                    {
                        let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
                        tool::apply_gradient(buf, sel.as_ref(), clip, &spec, start, last);
                    }
                    let (fid, lid) = (self.doc.frames[fi].id, self.doc.frames[fi].layers[li].id);
                    self.last_gradient =
                        Some((spec.kind, spec.stops.clone(), start, last, spec.smoothstep, fid, lid));
                }
                ToolKind::Line | ToolKind::Rectangle | ToolKind::Ellipse | ToolKind::Triangle => {
                    let color = self.settings.primary;
                    let (fill, lw, kind) = (self.settings.shape_fill, self.settings.line_width, self.tool);
                    let clip = self.paint_clip();
                    let sel = self.selection_clone();
                    let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
                    tool::draw_shape(buf, sel.as_ref(), clip, kind, start, last, 0.0, 0.0, color, fill, lw, PaintMode::Over);
                }
                ToolKind::Move => {
                    if let (Some(float), Some(sel)) = (stroke.floating, self.selection_clone()) {
                        let (dx, dy) = (last.x - start.x, last.y - start.y);
                        let wrap = self.settings.wrap;
                        let cr = self.doc.canvas_rect();
                        if let Some(bb) = sel.bounds() {
                            let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
                            // erase originals
                            for j in 0..bb.h as i32 {
                                for i in 0..bb.w as i32 {
                                    if sel.get(bb.x + i, bb.y + j) {
                                        buf.set(bb.x + i, bb.y + j, Rgba8::TRANSPARENT);
                                    }
                                }
                            }
                            // Wrap: pixels leaving an edge re-enter the opposite one. Regular: clip.
                            if wrap {
                                buf.blit_wrapped(&float, bb.x + dx, bb.y + dy, cr);
                            } else {
                                buf.blit_over(&float, Point::new(bb.x + dx, bb.y + dy));
                            }
                        }
                        // Assign directly (no separate record): the mask transition is captured by
                        // the commit_edit() below, so the pixel move and its mask move undo as one.
                        // (Fully off-canvas without wrap ⇒ the clipped mask is empty ⇒ None.)
                        self.doc.selection =
                            (if wrap { sel.translated_wrapped(dx, dy, cr) } else { sel.translated(dx, dy) })
                                .nonempty()
                                .map(Arc::new);
                    }
                }
                _ => {}
            }
        }

        // Selection tools: build the shape mask and combine it into the selection as one undo step
        // (selection changes are now undoable + serialized; see Document::selection).
        let (sw, sh) = { let s = self.doc.storage(); (s.w as u32, s.h as u32) };
        match self.tool {
            ToolKind::SelectRect | ToolKind::SelectEllipse | ToolKind::SelectCircle => {
                let kind = self.tool;
                let shape = Mask::from_plot(sw, sh, |plot| match kind {
                    ToolKind::SelectRect => crate::raster::rect_filled(start, last, plot),
                    ToolKind::SelectEllipse => crate::raster::ellipse_filled(start, last, plot),
                    _ => crate::raster::circle_filled(start, last, plot),
                });
                self.combine_selection(&shape, self.selection_mode);
            }
            ToolKind::SelectPoly | ToolKind::SelectFree => {
                let path = stroke.path.clone();
                let shape = Mask::from_plot(sw, sh, |plot| crate::raster::polygon_filled(&path, plot));
                self.combine_selection(&shape, self.selection_mode);
            }
            ToolKind::SelectByColor => {
                let buf = self.doc.active_frame().active_layer().pixels.clone();
                let shape = Mask::from_color(sw, sh, &buf, start, self.settings.threshold, self.settings.contiguous);
                self.combine_selection(&shape, self.selection_mode);
            }
            _ => {}
        }

        // Commit pixel changes as one undo record (single source of truth). [audit F-20]
        if self.tool.commits_stroke() {
            self.commit_edit(stroke.before);
        }
    }

    /// Abort the in-progress stroke/drag, discarding its changes WITHOUT recording an undo step.
    /// Used when a multi-finger gesture interrupts a nascent single-finger stroke, so the gesture
    /// leaves no stray marks behind.
    pub fn cancel_stroke(&mut self) {
        // Move-layer drag: restore the whole pre-drag frame snapshot.
        if let Some((_fid, before)) = self.move_before.take() {
            let fi = self.doc.active_frame;
            self.doc.frames[fi] = before;
            self.move_layers.clear();
            self.move_bbox = None;
            self.stroke = None;
            return;
        }
        // Normal stroke: restore the pre-stroke pixels of the stroke's OWN layer (by id). [F-29]
        if let Some(stroke) = self.stroke.take() {
            self.restore_edit(&stroke.before);
        }
        // Precision pen line in progress.
        if let Some(scope) = self.precision_before.take() {
            self.restore_edit(&scope);
            self.pen_pp.clear(); // the painted pixels were reverted; the tail is stale
        }
    }

    // ---- figure drafts (Line/Rectangle/Ellipse: draw → adjust → commit) ----
    //
    // A draft is an uncommitted figure the shell previews and lets the user fine-tune by dragging
    // either endpoint, committing only on demand. The shell owns the interaction (hit-testing
    // handles, deciding which endpoint moves); the engine just stores the two endpoints, renders
    // the preview, and rasterizes on commit.

    /// Set/replace the pending figure draft's endpoints (canvas pixels, clamped to the canvas).
    /// Creates a draft if none is pending.
    pub fn shape_set(&mut self, ax: i32, ay: i32, bx: i32, by: i32) {
        // Endpoints may sit OFF the canvas (so a shape/gradient can extend past an edge and be
        // cropped, not capped). `clamp_pointer` allows one canvas-span of margin — enough to drag an
        // end outside — while bounding rasterization work. The raster itself clips to the canvas.
        let a = self.clamp_pointer(Point::new(ax, ay));
        let b = self.clamp_pointer(Point::new(bx, by));
        self.shape_draft = Some((a, b));
    }

    /// The pending figure draft's endpoints (canvas-relative), if any (for the shell to draw handles).
    pub fn shape_draft(&self) -> Option<(Point, Point)> {
        let o = self.doc.origin();
        self.shape_draft
            .map(|(a, b)| (Point::new(a.x - o.x, a.y - o.y), Point::new(b.x - o.x, b.y - o.y)))
    }

    /// Rasterize the pending draft into the active layer as one undo edit, then clear the draft.
    /// No-op (draft preserved) if the active layer isn't editable or the active tool isn't a draft
    /// tool (Line/Rectangle/Ellipse or Gradient).
    pub fn shape_commit(&mut self) {
        if !matches!(
            self.tool,
            ToolKind::Line | ToolKind::Rectangle | ToolKind::Ellipse | ToolKind::Triangle | ToolKind::Gradient
        ) {
            return;
        }
        if !self.active_editable() {
            return;
        }
        let (a, b) = match self.shape_draft {
            Some(ab) => ab,
            None => return,
        };
        let before = self.begin_edit();
        let clip = self.paint_clip();
        let sel = self.selection_clone();
        if self.tool == ToolKind::Gradient {
            let spec = self.settings.gradient.clone();
            let (fi, li) = (self.doc.active_frame, self.doc.active_frame().active_layer);
            {
                let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
                tool::apply_gradient(buf, sel.as_ref(), clip, &spec, a, b);
            }
            let (fid, lid) = (self.doc.frames[fi].id, self.doc.frames[fi].layers[li].id);
            self.last_gradient = Some((spec.kind, spec.stops.clone(), a, b, spec.smoothstep, fid, lid));
        } else {
            let color = self.settings.primary;
            let (fill, lw, kind) = (self.settings.shape_fill, self.settings.line_width, self.tool);
            let (rot, tip) = (self.shape_rotation, self.triangle_tip);
            let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
            tool::draw_shape(buf, sel.as_ref(), clip, kind, a, b, rot, tip, color, fill, lw, PaintMode::Over);
        }
        self.commit_edit(before);
        self.shape_draft = None;
        self.shape_rotation = 0.0;
        self.triangle_tip = 0.0;
    }

    /// Discard the pending figure draft without drawing anything.
    pub fn shape_cancel(&mut self) {
        self.shape_draft = None;
        self.shape_rotation = 0.0;
        self.triangle_tip = 0.0;
    }

    /// Set the pending shape draft's rotation (milliradians, around the box centre).
    pub fn set_shape_rotation(&mut self, milliradians: i32) {
        self.shape_rotation = milliradians as f32 / 1000.0;
    }

    /// Set the pending Triangle draft's apex skew (thousandths; -1000..=1000 maps to -1.0..=1.0).
    pub fn set_triangle_tip(&mut self, thousandths: i32) {
        self.triangle_tip = (thousandths as f32 / 1000.0).clamp(-1.0, 1.0);
    }

    pub fn tap(&mut self, x: i32, y: i32) {
        self.pointer_down(x, y);
        self.pointer_up();
    }

    pub fn stroke_path(&mut self, pts: &[(i32, i32)]) {
        if let Some(&(x, y)) = pts.first() {
            self.pointer_down(x, y);
            for &(x, y) in &pts[1..] {
                self.pointer_move(x, y);
            }
            self.pointer_up();
        }
    }

    // ---- tool helpers operating on the active layer ----

    fn stamp_active(&mut self, p: Point, mode: PaintMode, color: Rgba8) {
        let (size, shape) = (self.settings.brush_size, self.settings.brush_shape);
        let clip = self.paint_clip();
        let sel = self.selection_clone();
        let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
        tool::stamp(buf, sel.as_ref(), clip, p, size, shape, color, mode);
    }
    fn stroke_active(&mut self, a: Point, b: Point, mode: PaintMode, color: Rgba8) {
        let (size, shape) = (self.settings.brush_size, self.settings.brush_shape);
        let clip = self.paint_clip();
        let sel = self.selection_clone();
        let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
        tool::stroke_segment(buf, sel.as_ref(), clip, a, b, size, shape, color, mode);
    }

    /// True when the Pencil should draw in pixel-perfect mode: the toggle is on and the brush is a
    /// single pixel (the only width where "corner doubles" are well-defined).
    fn pixel_perfect_active(&self) -> bool {
        self.settings.pixel_perfect && self.settings.brush_size == 1
    }

    /// Paint a 1px Pencil segment in pixel-perfect mode along the pointer stroke. The running tail
    /// lives in `stroke.pp` so detection continues across successive `pointer_move` segments.
    fn pencil_perfect_step(&mut self, a: Point, b: Point) {
        // Move the running tail out of the stroke so `self.doc` and `self.stroke` aren't both
        // borrowed at once; put it back at the end.
        let mut pp = match self.stroke.as_mut() {
            Some(s) => std::mem::take(&mut s.pp),
            None => return,
        };
        self.pencil_perfect_segment(a, b, &mut pp);
        if let Some(s) = self.stroke.as_mut() {
            s.pp = pp;
        }
    }

    /// The pixel-perfect Pencil core, shared by the pointer stroke and the precision pen line:
    /// stamp each interpolated pixel from `a` to `b`, then drop the redundant "corner double"
    /// (the L-elbow) as soon as a turn completes, restoring the removed pixel to its captured
    /// pre-stroke colour. `pp` is the running tail of recently painted pixels (with their
    /// pre-stroke colours); the caller carries it across segments. See [`pp_corner`].
    fn pencil_perfect_segment(&mut self, a: Point, b: Point, pp: &mut Vec<(Point, Rgba8)>) {
        let color = self.settings.primary;
        let clip = self.paint_clip();
        let sel = self.selection_clone();
        let mut pts = Vec::new();
        crate::raster::line(a, b, |x, y| pts.push(Point::new(x, y)));
        {
            let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
            for c in pts {
                // Successive segments share an endpoint (`line(a,b)` then `line(b,c)` both yield `b`);
                // skip a repeat so it isn't mistaken for a step.
                if pp.last().map(|&(q, _)| q == c).unwrap_or(false) {
                    continue;
                }
                let orig = buf.get(c.x, c.y); // pre-stroke colour (stroke hasn't touched `c` yet)
                tool::plot(buf, sel.as_ref(), clip, c.x, c.y, color, PaintMode::Replace);
                pp.push((c, orig));
                let n = pp.len();
                if n >= 3 && pp_corner(pp[n - 3].0, pp[n - 2].0, pp[n - 1].0) {
                    // The middle pixel is the corner double: restore it and drop it from the tail so
                    // its neighbours become adjacent and the filter continues cleanly.
                    let (mid, mid_orig) = pp[n - 2];
                    buf.set(mid.x, mid.y, mid_orig);
                    pp.remove(n - 2);
                }
            }
        }
        // Only the last two pixels are needed as anchors for the next segment; keep the tail bounded.
        let keep = pp.len().saturating_sub(2);
        if keep > 0 {
            pp.drain(0..keep);
        }
    }
    fn airbrush_active(&mut self, p: Point) {
        let (size, intensity, color) = (self.settings.brush_size, self.settings.intensity, self.settings.primary);
        let clip = self.paint_clip();
        let sel = self.selection_clone();
        let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
        tool::airbrush_dab(buf, sel.as_ref(), clip, p, size, intensity, color, &mut self.rng);
    }

    /// Distance (canvas px) between successive Brush/Airbrush/Dodge/Burn stamps: spacing% of the
    /// brush size, never below 1px.
    fn brush_step(&self) -> f32 {
        (self.settings.spacing as f32 / 100.0 * self.settings.brush_size as f32).max(1.0)
    }

    /// Stamp the brush along `a`→`b` at the configured spacing, carrying `paint_acc` so the spacing
    /// is even across the whole stroke (not reset per segment/event).
    fn brush_stroke_spaced(&mut self, a: Point, b: Point, mode: PaintMode, color: Rgba8) {
        let pts = spaced_points(a, b, self.brush_step(), &mut self.paint_acc);
        if pts.is_empty() {
            return;
        }
        let (size, shape) = (self.settings.brush_size, self.settings.brush_shape);
        let clip = self.paint_clip();
        let sel = self.selection_clone();
        let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
        for p in pts {
            tool::stamp(buf, sel.as_ref(), clip, p, size, shape, color, mode);
        }
    }

    /// Spray airbrush dabs along `a`→`b` at the configured spacing (interpolated, carrying
    /// `paint_acc`), so a fast drag still lays an even trail of dabs.
    fn airbrush_stroke_spaced(&mut self, a: Point, b: Point) {
        let pts = spaced_points(a, b, self.brush_step(), &mut self.paint_acc);
        for p in pts {
            self.airbrush_active(p);
        }
    }

    /// Dodge/burn a stamp at each spaced point along `a`→`b` (interpolated, carrying `paint_acc`),
    /// so a fast drag lightens/darkens an even trail instead of leaving gaps.
    fn dodge_burn_stroke_spaced(&mut self, a: Point, b: Point, dv: f32) {
        let pts = spaced_points(a, b, self.brush_step(), &mut self.paint_acc);
        for p in pts {
            self.dodge_burn_active(p, dv);
        }
    }
    fn dodge_dv(&self, lighten: bool) -> f32 {
        let mag = self.settings.intensity as f32 / 255.0 * 0.25;
        if lighten {
            mag
        } else {
            -mag
        }
    }
    fn dodge_burn_active(&mut self, p: Point, dv: f32) {
        let (size, shape) = (self.settings.brush_size, self.settings.brush_shape);
        let clip = self.paint_clip();
        let sel = self.selection_clone();
        let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
        tool::dodge_burn_stamp(buf, sel.as_ref(), clip, p, size, shape, dv);
    }

    // ---- precision mode (draw-by-button, reticle off the finger) ----
    //
    // Precision is a per-tool *mode* (toggled in the shell), not a tool of its own. The reticle
    // path below honours whichever paint tool is active: Pencil replaces, Brush blends, Eraser
    // clears, Airbrush sprays, Dodge/Burn lighten/darken. `cursor_paint()` returns the stamp params
    // for the stamp-style tools, or `None` for the others (Airbrush dabs; Dodge/Burn adjust value).

    fn clamp_cursor(&self, p: Point) -> Point {
        Point::new(
            p.x.clamp(0, self.doc.size.w as i32 - 1),
            p.y.clamp(0, self.doc.size.h as i32 - 1),
        )
    }

    /// The reticle position in storage coordinates (canvas coords + gutter origin) — the precision
    /// cursor is stored canvas-relative, but the paint helpers write in storage coordinates.
    fn cursor_storage(&self) -> Point {
        let o = self.doc.origin();
        Point::new(self.cursor.x + o.x, self.cursor.y + o.y)
    }

    /// Clamp an incoming pointer coordinate to a generous margin around the canvas. Off-canvas
    /// input is legitimate (a freehand stroke can run past the edge and be clipped), so this is NOT
    /// `clamp_cursor`'s canvas-tight clamp — but an unbounded coordinate from a malformed event would
    /// make `spaced_points`/`raster::line` iterate billions of times (a multi-second hang / OOM).
    /// One canvas span of margin preserves every real stroke while bounding the work. [audit F-6]
    fn clamp_pointer(&self, p: Point) -> Point {
        // Pointer/DSL input is canvas-relative (gutter = negative / ≥ canvas). Clamp to the reachable
        // range — one canvas of margin on each side, matching the gutter — then map to the storage
        // coordinates the layer buffers are indexed by, by adding the gutter origin. [SPEC §8]
        let (w, h) = (self.doc.size.w as i32, self.doc.size.h as i32);
        let o = self.doc.origin();
        Point::new(p.x.clamp(-w, 2 * w) + o.x, p.y.clamp(-h, 2 * h) + o.y)
    }

    /// Stamp (mode, color) for the active stamp-style paint tool, or `None` if the active tool
    /// sprays (Airbrush) or doesn't paint through the reticle path at all.
    fn cursor_paint(&self) -> Option<(PaintMode, Rgba8)> {
        // Mode comes from the single ToolKind table; only the color is settings-dependent. [F-20]
        self.tool.paint_mode().map(|mode| {
            let color = if matches!(mode, PaintMode::Erase) { Rgba8::TRANSPARENT } else { self.settings.primary };
            (mode, color)
        })
    }

    pub fn cursor(&self) -> Point {
        self.cursor
    }

    /// Place the reticle at an absolute canvas pixel (clamped).
    pub fn set_cursor(&mut self, x: i32, y: i32) {
        self.cursor = self.clamp_cursor(Point::new(x, y));
    }

    /// Move the reticle by (dx, dy). While the pen is down, paints from the old position to
    /// the new one (so dragging draws a visible line offset from the finger), using the active
    /// tool's paint mode — or sprays a dab at the new spot for the Airbrush.
    pub fn move_cursor(&mut self, dx: i32, dy: i32) {
        let old = self.cursor;
        self.cursor = self.clamp_cursor(Point::new(old.x + dx, old.y + dy));
        if self.precision_before.is_some() && self.active_editable() && self.cursor != old {
            // Translate the reticle path to storage coordinates for the paint helpers.
            let o = self.doc.origin();
            let os = Point::new(old.x + o.x, old.y + o.y);
            let cs = self.cursor_storage();
            match self.tool {
                // Pixel-perfect 1px Pencil: run the corner-double filter along the reticle path,
                // carrying its tail in `pen_pp` (the pen line has no `Stroke` to hold it).
                ToolKind::Pencil if self.pixel_perfect_active() => {
                    let mut pp = std::mem::take(&mut self.pen_pp);
                    self.pencil_perfect_segment(os, cs, &mut pp);
                    self.pen_pp = pp;
                }
                // Brush/Airbrush/Dodge/Burn honour the spacing setting; Pencil/Eraser stay continuous.
                ToolKind::Brush => self.brush_stroke_spaced(os, cs, PaintMode::Over, self.settings.primary),
                ToolKind::Airbrush => self.airbrush_stroke_spaced(os, cs),
                // Dodge/Burn lighten/darken a stamp at each spaced step (as on the pointer path).
                ToolKind::Dodge | ToolKind::Burn => {
                    self.dodge_burn_stroke_spaced(os, cs, self.dodge_dv(self.tool == ToolKind::Dodge));
                }
                _ => match self.cursor_paint() {
                    Some((mode, color)) => self.stroke_active(os, cs, mode, color),
                    None => {}
                },
            }
        }
    }

    /// Press the pen down at the reticle: enter Hold. Stamps/sprays the first point and commits
    /// that dab as its own undo step IMMEDIATELY — subsequent drag segments each record their own
    /// step (`cursor_stroke_begin`/`cursor_stroke_end`), so Undo mid-Hold reverts the last drag.
    pub fn cursor_pen_down(&mut self) {
        if self.pen_held || self.precision_before.is_some() || !self.active_editable() {
            return;
        }
        self.pen_held = true;
        let before = self.begin_edit();
        self.paint_acc = 0.0; // fresh pen line → reset Brush/Airbrush spacing
        self.pen_pp.clear(); // fresh pen line → reset the pixel-perfect corner-filter tail
        let p = self.cursor_storage();
        if self.tool == ToolKind::Pencil && self.pixel_perfect_active() {
            let color = self.settings.primary;
            let clip = self.paint_clip();
            let sel = self.selection_clone();
            let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
            tool::plot(buf, sel.as_ref(), clip, p.x, p.y, color, PaintMode::Replace);
        } else {
            match self.cursor_paint() {
                Some((mode, color)) => self.stamp_active(p, mode, color),
                None if self.tool == ToolKind::Airbrush => self.airbrush_active(p),
                None if matches!(self.tool, ToolKind::Dodge | ToolKind::Burn) => {
                    self.dodge_burn_active(p, self.dodge_dv(self.tool == ToolKind::Dodge));
                }
                None => {}
            }
        }
        self.commit_edit(before);
    }

    /// One drag segment of a held pen begins (finger down while Hold is on): open the undo edit
    /// the segment's `move_cursor` calls paint into; `cursor_stroke_end` commits it as ONE step.
    /// No-op unless the pen is held (a plain reticle drag paints nothing).
    pub fn cursor_stroke_begin(&mut self) {
        if !self.pen_held || self.precision_before.is_some() || !self.active_editable() {
            return;
        }
        self.precision_before = Some(self.begin_edit());
        self.paint_acc = 0.0; // fresh segment → reset Brush/Airbrush spacing
        self.pen_pp.clear();
        if self.tool == ToolKind::Pencil && self.pixel_perfect_active() {
            // Seed the corner filter with the reticle pixel — already painted by the Hold dab or
            // the previous segment, so seeding with its current colour is visually a no-op.
            let p = self.cursor_storage();
            let c = self.doc.active_frame().active_layer().pixels.get(p.x, p.y);
            self.pen_pp.push((p, c));
        }
    }

    /// The drag segment ends (finger up, Hold still on): commit its pixels as ONE undo step.
    pub fn cursor_stroke_end(&mut self) {
        if let Some(before) = self.precision_before.take() {
            self.commit_edit(before);
        }
        self.pen_pp.clear();
    }

    /// Lift the pen: exit Hold. Adds NO undo step of its own — the entering dab and every drag
    /// segment already committed theirs; a segment still open (finger down as Hold flips off)
    /// commits here as its final step.
    pub fn cursor_pen_up(&mut self) {
        if let Some(before) = self.precision_before.take() {
            self.commit_edit(before);
        }
        self.pen_held = false;
        self.pen_pp.clear();
    }

    /// Plot a single dot at the reticle (pen down + up).
    pub fn plot_cursor(&mut self) {
        self.cursor_pen_down();
        self.cursor_pen_up();
    }

    /// Apply a single airbrush dab at the reticle, committed as one undo edit. This is the
    /// "one go at a time" airbrush, driven off-finger by the Airbrush's precision mode.
    pub fn airbrush_cursor(&mut self) {
        if !self.active_editable() {
            return;
        }
        let before = self.begin_edit();
        let p = self.cursor_storage();
        self.airbrush_active(p);
        self.commit_edit(before);
    }

    /// Pick the colour under the reticle (off-finger eyedropper, Pick button) and set it as the
    /// primary colour. No-op on a transparent pixel (mirrors the pointer eyedropper). Not an edit.
    pub fn eyedrop_cursor(&mut self) {
        let c = render::composite_active(&self.doc).get(self.cursor.x, self.cursor.y);
        if c.a != 0 {
            self.settings.primary = c;
        }
    }

    /// Apply the colour selection at the reticle (off-finger Select-by-Color, Select button):
    /// the same mask a tap would build — threshold + contiguous honoured — combined into the
    /// current selection per the selection mode. One undo step (via `set_selection`).
    pub fn select_color_cursor(&mut self) {
        let s = self.doc.storage();
        let (sw, sh) = (s.w as u32, s.h as u32);
        let buf = self.doc.active_frame().active_layer().pixels.clone();
        let p = self.cursor_storage();
        let shape = Mask::from_color(sw, sh, &buf, p, self.settings.threshold, self.settings.contiguous);
        self.combine_selection(&shape, self.selection_mode);
    }

    /// Flood-fill seeded at `p` (storage coords) into the active layer, honouring the threshold,
    /// contiguous and "All layers" settings plus the selection. Shared by the Bucket pointer tap
    /// and `fill_cursor`; the caller owns the undo edit.
    fn flood_fill_at(&mut self, p: Point) {
        let color = self.settings.primary;
        let (th, cont) = (self.settings.threshold, self.settings.contiguous);
        let sel = self.selection_clone();
        // "All layers": decide the region from the composited frame (computed before the
        // mutable layer borrow), while the fill still lands in the active layer only. The
        // reference is composited over the whole **storage** area so its coordinates line
        // up with the storage-indexed layer buffer the flood reads. [risk: bucket ref]
        let reference = self
            .settings
            .fill_all_layers
            .then(|| render::composite_frame(self.doc.active_frame(), self.doc.storage_rect()));
        let clip = self.paint_clip();
        let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
        tool::flood_fill(buf, reference.as_ref(), sel.as_ref(), clip, p, color, th, cont, PaintMode::Replace);
    }

    /// Flood-fill at the reticle (off-finger Bucket, Fill button): the same fill a tap would do —
    /// threshold, contiguous, "All layers" and the selection honoured. One undo step per press.
    pub fn fill_cursor(&mut self) {
        if !self.active_editable() {
            return;
        }
        let before = self.begin_edit();
        let p = self.cursor_storage();
        self.flood_fill_at(p);
        self.commit_edit(before);
    }

    // ---- selection / clipboard ops ----

    /// Build a selection from the active layer's alpha (pixels with alpha > the alpha cutoff — the
    /// opaque/drawn pixels) and combine it with the current selection using `mode`. Undoable +
    /// serialized (one undo step).
    pub fn select_by_alpha(&mut self, mode: CombineMode) {
        let s = self.doc.storage();
        let (w, h) = (s.w as u32, s.h as u32);
        let cutoff = self.settings.alpha_cutoff;
        let buf = self.doc.active_frame().active_layer().pixels.clone();
        let shape = Mask::from_plot(w, h, |plot| {
            for y in 0..h as i32 {
                for x in 0..w as i32 {
                    if buf.get(x, y).a > cutoff {
                        plot(x, y);
                    }
                }
            }
        });
        self.combine_selection(&shape, mode);
    }

    pub fn select_all(&mut self) {
        let s = self.doc.storage();
        let mut m = Mask::new(s.w as u32, s.h as u32);
        m.select_all();
        m.intersect_rect(self.selection_clip()); // Select-All covers the canvas (or storage on overscan)
        self.set_selection(Some(m));
    }
    pub fn select_none(&mut self) {
        self.set_selection(None);
    }
    pub fn invert_selection(&mut self) {
        let s = self.doc.storage();
        let mut m = self.selection_clone().unwrap_or_else(|| Mask::new(s.w as u32, s.h as u32));
        m.invert();
        m.intersect_rect(self.selection_clip()); // invert within the selectable window, not the gutter
        self.set_selection(Some(m));
    }
    /// Translate the selection MASK (not the pixels) by (dx, dy), honouring the same off-canvas edge
    /// modes as a pixel move: Wrap (cells re-enter the opposite edge), Protect (clamp so the whole
    /// selection stays on-canvas), or Regular (clip cells that leave the canvas). One undo step.
    /// Begin a coalesced selection-mask drag: snapshot the selection so the whole drag becomes one
    /// undo step. No-op if already in a drag or there is no selection. [audit: one drag = one undo]
    pub fn move_selection_begin(&mut self) {
        if self.move_sel_before.is_none() && self.doc.selection.is_some() {
            self.move_sel_before = Some(self.doc.selection.clone());
        }
    }

    /// Finalise a coalesced selection-mask drag: record a single undo step (drag-start → final) iff
    /// the mask actually moved. No-op when no drag is open. [audit: one drag = one undo]
    pub fn move_selection_commit(&mut self) {
        if let Some(before) = self.move_sel_before.take() {
            if !sel_eq(&before, &self.doc.selection) {
                self.doc.record_selection(before);
            }
        }
    }

    pub fn move_selection(&mut self, dx: i32, dy: i32) {
        let m = match self.selection_clone() {
            Some(m) => m,
            None => return,
        };
        let moved = if self.settings.wrap {
            m.translated_wrapped(dx, dy, self.doc.canvas_rect())
        } else if self.settings.protect_pixels {
            match m.bounds() {
                Some(bb) => {
                    // Clamp so the selection stays within the canvas window (storage coords).
                    let cr = self.doc.canvas_rect();
                    let cdx = dx.clamp(cr.x - bb.x, cr.right() - (bb.x + bb.w as i32));
                    let cdy = dy.clamp(cr.y - bb.y, cr.bottom() - (bb.y + bb.h as i32));
                    m.translated(cdx, cdy)
                }
                None => m,
            }
        } else {
            m.translated(dx, dy)
        };
        if self.move_sel_before.is_some() {
            // Inside a coalesced drag: update the mask in place; the single undo step is recorded by
            // `move_selection_commit` on finger-up. (Without this, every drag step pushed a record.)
            self.doc.selection = moved.nonempty().map(Arc::new); // dragged fully off-canvas ⇒ None
        } else {
            self.set_selection(Some(moved)); // one-shot (DSL/nudge): records its own step
        }
    }

    pub fn copy(&mut self) {
        if let Some(sel) = &self.doc.selection {
            if let Some(bb) = sel.bounds() {
                let buf = &self.doc.active_frame().active_layer().pixels;
                let mut clip = RgbaBuffer::new(bb.w, bb.h);
                for j in 0..bb.h as i32 {
                    for i in 0..bb.w as i32 {
                        if sel.get(bb.x + i, bb.y + j) {
                            clip.set(i, j, buf.get(bb.x + i, bb.y + j));
                        }
                    }
                }
                self.clipboard = Some((clip, Point::new(bb.x, bb.y)));
            }
        }
    }

    pub fn cut(&mut self) {
        self.copy();
        if !self.active_editable() {
            return;
        }
        let before = self.begin_edit();
        if let Some(sel) = self.selection_clone() {
            let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
            for y in 0..buf.height() as i32 {
                for x in 0..buf.width() as i32 {
                    if sel.get(x, y) {
                        buf.set(x, y, Rgba8::TRANSPARENT);
                    }
                }
            }
        }
        self.commit_edit(before);
    }

    pub fn paste(&mut self) {
        self.paste_to_frame(self.doc.active_frame);
    }

    pub fn paste_to_frame(&mut self, frame: usize) {
        let frame = frame.min(self.doc.frames.len() - 1);
        let (clip, origin) = match &self.clipboard {
            Some((c, o)) => (c.clone(), *o),
            None => return,
        };
        let prev_active = self.doc.active_frame;
        self.doc.active_frame = frame;
        if !self.active_editable() {
            self.doc.active_frame = prev_active;
            return;
        }
        let before = self.begin_edit();
        {
            let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
            buf.blit_over(&clip, origin);
        }
        self.commit_edit(before);
        self.doc.active_frame = prev_active;
    }

    // ---- paste draft (movable, semi-transparent preview committed on demand) ----

    /// Begin a paste draft from the clipboard, floating at the position it was copied from. No-op if
    /// the clipboard is empty. Replaces any existing draft.
    pub fn paste_begin(&mut self) {
        if let Some((clip, origin)) = &self.clipboard {
            self.paste_draft = Some((clip.clone(), *origin));
        }
    }

    /// Translate the pending paste draft by (dx, dy) canvas pixels. No-op if none is pending.
    pub fn paste_move(&mut self, dx: i32, dy: i32) {
        if let Some((_, pos)) = &mut self.paste_draft {
            pos.x += dx;
            pos.y += dy;
        }
    }

    /// The pending paste draft's rect (top-left + clip size), if any — for the shell.
    pub fn paste_draft_rect(&self) -> Option<IRect> {
        let o = self.doc.origin();
        self.paste_draft
            .as_ref()
            .map(|(clip, pos)| IRect::new(pos.x - o.x, pos.y - o.y, clip.width(), clip.height()))
    }

    /// Stamp the pending paste draft into the active layer (alpha-over, cropped to the canvas) as one
    /// undo edit, then clear it. No-op if no draft or the layer isn't editable.
    pub fn paste_commit(&mut self) {
        let (clip, pos) = match self.paste_draft.take() {
            Some(d) => d,
            None => return,
        };
        if !self.active_editable() {
            return;
        }
        let before = self.begin_edit();
        {
            let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
            buf.blit_over(&clip, pos);
        }
        self.commit_edit(before);
    }

    /// Discard the pending paste draft without drawing anything.
    pub fn paste_cancel(&mut self) {
        self.paste_draft = None;
    }

    pub fn fill_selection(&mut self) {
        if !self.active_editable() {
            return;
        }
        let before = self.begin_edit();
        let color = self.settings.primary;
        let clip = self.selection_clip();
        let sel = self.selection_clone();
        let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
        tool::fill_region(buf, sel.as_ref(), clip, color);
        self.commit_edit(before);
    }

    pub fn clear_selection_pixels(&mut self) {
        // No selection → no-op (clearing "the selection" must not wipe the whole layer).
        if self.doc.selection.is_none() || !self.active_editable() {
            return;
        }
        let before = self.begin_edit();
        let clip = self.selection_clip();
        let sel = self.selection_clone();
        let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
        tool::clear_region(buf, sel.as_ref(), clip);
        self.commit_edit(before);
    }

    pub fn apply_hsv_shift(&mut self) {
        let (dh, ds, dv) = self.settings.hsv;
        // "Frame" scope: shift every layer of the active frame, ignoring the selection — frame
        // mode acts on everything, like flip_frame/rotate_frame/map_frame. One undo step.
        if self.settings.hsv_frame {
            self.edit_doc("hsv_frame", |s| {
                for l in &mut s.doc.active_frame_mut().layers {
                    tool::hsv_shift_region(&mut l.pixels, None, dh, ds, dv);
                }
            });
            return;
        }
        if !self.active_editable() {
            return;
        }
        let before = self.begin_edit();
        let sel = self.selection_clone();
        let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
        tool::hsv_shift_region(buf, sel.as_ref(), dh, ds, dv);
        self.commit_edit(before);
    }

    /// Live HSV preview: while the HSV tool is active with a non-zero shift pending, the display
    /// composites a clone of the active frame with the shift applied per the scope — the active
    /// layer (selection-clipped, or whole with no selection), or every layer in "Frame" scope.
    /// The document itself is untouched until `ApplyHsvShift` commits.
    fn hsv_preview_frame(&self) -> Option<Frame> {
        if self.tool != ToolKind::HsvShift {
            return None;
        }
        let (dh, ds, dv) = self.settings.hsv;
        if dh == 0.0 && ds == 0.0 && dv == 0.0 {
            return None;
        }
        let mut frame = self.doc.active_frame().clone();
        if self.settings.hsv_frame {
            for l in &mut frame.layers {
                tool::hsv_shift_region(&mut l.pixels, None, dh, ds, dv);
            }
        } else {
            if !self.active_editable() {
                return None;
            }
            let li = frame.active_layer;
            let sel = self.selection_clone();
            tool::hsv_shift_region(&mut frame.layers[li].pixels, sel.as_ref(), dh, ds, dv);
        }
        Some(frame)
    }

    /// Bake the pending Brightness/Contrast adjustment (`settings.bc`) into the document — the
    /// active layer (selection-clipped), or every layer of the active frame in "Frame" scope
    /// (ignoring the selection, like `apply_hsv_shift`). One undo step.
    pub fn apply_brightness_contrast(&mut self) {
        let (db, cf) = self.settings.bc;
        if self.settings.bc_frame {
            self.edit_doc("bc_frame", |s| {
                for l in &mut s.doc.active_frame_mut().layers {
                    tool::map_region(&mut l.pixels, None, |c| crate::color::brightness_contrast(c, db, cf));
                }
            });
            return;
        }
        if !self.active_editable() {
            return;
        }
        let before = self.begin_edit();
        let sel = self.selection_clone();
        let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
        tool::map_region(buf, sel.as_ref(), |c| crate::color::brightness_contrast(c, db, cf));
        self.commit_edit(before);
    }

    /// Live Brightness/Contrast preview (the HSV preview's twin): while the tool is active with a
    /// non-identity adjustment pending, the display composites a clone of the active frame with it
    /// applied per the scope. The document is untouched until `ApplyBrightnessContrast` commits.
    fn bc_preview_frame(&self) -> Option<Frame> {
        if self.tool != ToolKind::BrightnessContrast {
            return None;
        }
        let (db, cf) = self.settings.bc;
        if db == 0 && cf == 1.0 {
            return None;
        }
        let mut frame = self.doc.active_frame().clone();
        if self.settings.bc_frame {
            for l in &mut frame.layers {
                tool::map_region(&mut l.pixels, None, |c| crate::color::brightness_contrast(c, db, cf));
            }
        } else {
            if !self.active_editable() {
                return None;
            }
            let li = frame.active_layer;
            let sel = self.selection_clone();
            tool::map_region(&mut frame.layers[li].pixels, sel.as_ref(), |c| {
                crate::color::brightness_contrast(c, db, cf)
            });
        }
        Some(frame)
    }

    pub fn map_active(&mut self, f: impl Fn(Rgba8) -> Rgba8) {
        if !self.active_editable() {
            return;
        }
        let before = self.begin_edit();
        let sel = self.selection_clone();
        let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
        tool::map_region(buf, sel.as_ref(), f);
        self.commit_edit(before);
    }

    /// Apply a per-pixel colour transform to every layer of the ACTIVE frame (the Invert tool's
    /// "Frame" scope), ignoring the selection — frame mode acts on everything, like
    /// `flip_frame`/`rotate_frame`. One undo step.
    pub fn map_frame(&mut self, f: impl Fn(Rgba8) -> Rgba8) {
        self.edit_doc("map_frame", |s| {
            for l in &mut s.doc.active_frame_mut().layers {
                tool::map_region(&mut l.pixels, None, &f);
            }
        });
    }

    // ---- frame & layer ops ----

    pub fn add_frame(&mut self) {
        if self.doc.frames.len() >= crate::document::MAX_FRAMES {
            return;
        }
        self.edit_doc("add_frame", |s| {
            let id = s.doc.new_frame_id();
            let layers = vec![s.doc.new_layer("Layer 1")];
            let dur = crate::document::DEFAULT_DURATION_US;
            s.doc.frames.push(Frame { id, duration_us: dur, layers, active_layer: 0 });
            s.doc.active_frame = s.doc.frames.len() - 1;
        });
    }

    pub fn duplicate_frame(&mut self, i: usize) {
        if self.doc.frames.len() >= crate::document::MAX_FRAMES || i >= self.doc.frames.len() {
            return;
        }
        self.edit_doc("duplicate_frame", |s| {
            let mut copy = s.doc.frames[i].clone();
            copy.id = s.doc.new_frame_id();
            for l in &mut copy.layers {
                l.id = s.doc.layer_ids.alloc();
            }
            s.doc.frames.insert(i + 1, copy);
            s.doc.active_frame = i + 1;
        });
    }

    /// Insert a fresh blank frame at index `at` (clamped to the end), making it active. Used by the
    /// frame menu's "Add new frame here" (caller passes `i + 1` to insert just right of frame `i`).
    pub fn add_frame_at(&mut self, at: usize) {
        if self.doc.frames.len() >= crate::document::MAX_FRAMES {
            return;
        }
        let at = at.min(self.doc.frames.len());
        self.edit_doc("add_frame", |s| {
            let id = s.doc.new_frame_id();
            let layers = vec![s.doc.new_layer("Layer 1")];
            let dur = crate::document::DEFAULT_DURATION_US;
            s.doc.frames.insert(at, Frame { id, duration_us: dur, layers, active_layer: 0 });
            s.doc.active_frame = at;
        });
    }

    pub fn remove_frame(&mut self, i: usize) {
        if self.doc.frames.len() <= 1 || i >= self.doc.frames.len() {
            return;
        }
        self.edit_doc("remove_frame", |s| {
            s.doc.frames.remove(i);
            s.doc.active_frame = s.doc.active_frame.min(s.doc.frames.len() - 1);
        });
    }

    pub fn reorder_frame(&mut self, from: usize, to: usize) {
        let n = self.doc.frames.len();
        if from >= n || to >= n || from == to {
            return;
        }
        self.edit_doc("reorder_frame", |s| {
            let f = s.doc.frames.remove(from);
            s.doc.frames.insert(to, f);
            s.doc.active_frame = to;
        });
    }

    pub fn set_active_frame(&mut self, i: usize) {
        if i < self.doc.frames.len() {
            self.doc.active_frame = i;
        }
    }

    pub fn set_frame_duration(&mut self, i: usize, us: u32) {
        if i < self.doc.frames.len() {
            self.edit_doc("set_duration", |s| {
                s.doc.frames[i].duration_us = Document::clamp_duration(us);
            });
        }
    }

    pub fn set_all_durations(&mut self, us: u32) {
        self.edit_doc("set_all_durations", |s| {
            let d = Document::clamp_duration(us);
            for f in &mut s.doc.frames {
                f.duration_us = d;
            }
        });
    }

    pub fn set_loop_mode(&mut self, m: LoopMode) {
        self.doc.anim.loop_mode = m;
    }

    pub fn add_layer(&mut self) {
        if self.doc.active_frame().layers.len() >= crate::document::MAX_LAYERS {
            return;
        }
        let name = format!("Layer {}", self.doc.active_frame().layers.len() + 1);
        let layer = self.doc.new_layer(name);
        self.edit_frame(|s| {
            s.doc.active_frame_mut().layers.push(layer);
            let n = s.doc.active_frame().layers.len();
            s.doc.active_frame_mut().active_layer = n - 1;
        });
    }

    /// Insert a fresh blank layer at index `at` (clamped) in the active frame, making it active. Used
    /// by the layer menu's "Add new layer here" (caller passes `i + 1` to insert just above layer `i`).
    pub fn add_layer_at(&mut self, at: usize) {
        let len = self.doc.active_frame().layers.len();
        if len >= crate::document::MAX_LAYERS {
            return;
        }
        let name = format!("Layer {}", len + 1);
        let layer = self.doc.new_layer(name);
        let at = at.min(len);
        self.edit_frame(|s| {
            s.doc.active_frame_mut().layers.insert(at, layer);
            s.doc.active_frame_mut().active_layer = at;
        });
    }

    pub fn remove_layer(&mut self, i: usize) {
        if self.doc.active_frame().layers.len() <= 1 || i >= self.doc.active_frame().layers.len() {
            return;
        }
        self.edit_frame(|s| {
            s.doc.active_frame_mut().layers.remove(i);
            let n = s.doc.active_frame().layers.len();
            let a = s.doc.active_frame().active_layer.min(n - 1);
            s.doc.active_frame_mut().active_layer = a;
        });
    }

    pub fn duplicate_layer(&mut self, i: usize) {
        if self.doc.active_frame().layers.len() >= crate::document::MAX_LAYERS
            || i >= self.doc.active_frame().layers.len()
        {
            return;
        }
        let new_id = self.doc.layer_ids.alloc();
        self.edit_frame(|s| {
            let mut copy = s.doc.active_frame().layers[i].clone();
            copy.id = new_id;
            copy.name = format!("{} copy", copy.name);
            s.doc.active_frame_mut().layers.insert(i + 1, copy);
            s.doc.active_frame_mut().active_layer = i + 1;
        });
    }

    /// Merge layer `i` down onto the layer below it: composite `i`'s pixels — with its opacity,
    /// via the compositor's own `over_opacity` blend — over layer `i-1`'s pixels, then remove
    /// layer `i`. The merged layer keeps the below layer's identity and settings (name, opacity,
    /// visibility, lock). An invisible or zero-opacity source contributes nothing (the compositor
    /// would have shown none of it), so the merge degenerates to a plain remove. One undo step.
    /// No-op on the bottom layer, an out-of-range index, or a locked layer below (its pixels are
    /// protected, like painting).
    pub fn merge_down(&mut self, i: usize) {
        let layers = &self.doc.active_frame().layers;
        if i == 0 || i >= layers.len() || layers[i - 1].locked {
            return;
        }
        let st = self.doc.storage();
        let (w, h) = (st.w as i32, st.h as i32);
        self.edit_frame(|s| {
            let f = s.doc.active_frame_mut();
            let src = f.layers.remove(i);
            if src.visible && src.opacity > 0 {
                let dst = &mut f.layers[i - 1].pixels;
                for y in 0..h {
                    for x in 0..w {
                        let p = src.pixels.get(x, y);
                        if p.a != 0 {
                            let d = dst.get(x, y);
                            dst.set(x, y, crate::color::over_opacity(p, d, src.opacity));
                        }
                    }
                }
            }
            f.active_layer = i - 1;
        });
    }

    pub fn reorder_layer(&mut self, from: usize, to: usize) {
        let n = self.doc.active_frame().layers.len();
        if from >= n || to >= n || from == to {
            return;
        }
        self.edit_frame(|s| {
            let l = s.doc.active_frame_mut().layers.remove(from);
            s.doc.active_frame_mut().layers.insert(to, l);
            s.doc.active_frame_mut().active_layer = to;
        });
    }

    pub fn set_active_layer(&mut self, i: usize) {
        if i < self.doc.active_frame().layers.len() {
            self.doc.active_frame_mut().active_layer = i;
            self.layer_sel = vec![i];
        }
    }

    /// Select a set of layers to move together as one (SPEC §15). The first becomes active.
    pub fn set_active_layers(&mut self, idxs: &[usize]) {
        let n = self.doc.active_frame().layers.len();
        let mut v: Vec<usize> = idxs.iter().copied().filter(|&i| i < n).collect();
        v.dedup();
        if v.is_empty() {
            v.push(self.doc.active_frame().active_layer.min(n - 1));
        }
        self.doc.active_frame_mut().active_layer = v[0];
        self.layer_sel = v;
    }

    /// Set the move-group (layers that translate together) WITHOUT changing which layer is active,
    /// so the active layer stays put while grouped. Falls back to the active layer if empty.
    pub fn set_move_group(&mut self, idxs: &[usize]) {
        let n = self.doc.active_frame().layers.len();
        let mut v: Vec<usize> = idxs.iter().copied().filter(|&i| i < n).collect();
        v.sort_unstable();
        v.dedup();
        if v.is_empty() {
            v.push(self.doc.active_frame().active_layer.min(n.saturating_sub(1)));
        }
        self.layer_sel = v;
    }

    /// Union of the opaque bounding boxes of the given layers (in the active frame), or `None` if
    /// they are all empty.
    fn union_opaque_bounds(&self, layers: &[usize]) -> Option<crate::geom::IRect> {
        let f = self.doc.active_frame();
        let mut acc: Option<crate::geom::IRect> = None;
        for &li in layers {
            if li < f.layers.len() {
                if let Some(b) = f.layers[li].pixels.opaque_bounds() {
                    acc = Some(match acc {
                        Some(a) => union_irect(a, b),
                        None => b,
                    });
                }
            }
        }
        acc
    }

    /// Clamp a translation so an opaque bounding box `bbox` (storage coords) stays fully inside the
    /// canvas window — Protect-pixels never pushes opaque content off the canvas into the gutter.
    fn clamp_move_to_canvas(&self, bbox: crate::geom::IRect, dx: i32, dy: i32) -> (i32, i32) {
        let cr = self.doc.canvas_rect();
        (dx.clamp(cr.x - bbox.x, cr.right() - bbox.right()), dy.clamp(cr.y - bbox.y, cr.bottom() - bbox.bottom()))
    }

    /// Translate the content of all selected layers by (dx,dy), together, as one undoable
    /// frame edit (SPEC §15 "move multiple layers as one").
    pub fn nudge_layers(&mut self, dx: i32, dy: i32) {
        let layers: Vec<usize> = self
            .layer_sel
            .iter()
            .copied()
            .filter(|&i| i < self.doc.active_frame().layers.len() && !self.doc.active_frame().layers[i].locked)
            .collect();
        if layers.is_empty() {
            return;
        }
        // Protect pixels: never push opaque content off-canvas (clamp the requested delta).
        let (dx, dy) = if self.settings.protect_pixels {
            match self.union_opaque_bounds(&layers) {
                Some(bb) => self.clamp_move_to_canvas(bb, dx, dy),
                None => (dx, dy),
            }
        } else {
            (dx, dy)
        };
        if dx == 0 && dy == 0 {
            return;
        }
        let wrap = self.settings.wrap;
        self.edit_frame(|s| {
            let cr = s.doc.canvas_rect();
            for &li in &layers {
                let src = s.doc.active_frame().layers[li].pixels.clone();
                let buf = &mut s.doc.active_frame_mut().layers[li].pixels;
                buf.clear();
                if wrap {
                    buf.blit_wrapped(&src, dx, dy, cr);
                } else {
                    for y in 0..src.height() as i32 {
                        for x in 0..src.width() as i32 {
                            let c = src.get(x, y);
                            if c.a != 0 {
                                buf.set(x + dx, y + dy, c);
                            }
                        }
                    }
                }
            }
        });
    }
    /// Move the selected pixels by (dx,dy) as one undoable edit (the arrow-key equivalent of a Move
    /// drag); the selection mask moves with them. No-op without an editable selection.
    pub fn nudge_selection(&mut self, dx: i32, dy: i32) {
        if (dx == 0 && dy == 0) || !self.active_editable() {
            return;
        }
        let sel = match self.selection_clone() {
            Some(s) => s,
            None => return,
        };
        let bb = match sel.bounds() {
            Some(b) => b,
            None => return,
        };
        let wrap = self.settings.wrap;
        let cr = self.doc.canvas_rect();
        let before = self.begin_edit();
        {
            let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
            let mut float = RgbaBuffer::new(bb.w, bb.h);
            for j in 0..bb.h as i32 {
                for i in 0..bb.w as i32 {
                    if sel.get(bb.x + i, bb.y + j) {
                        float.set(i, j, buf.get(bb.x + i, bb.y + j));
                        buf.set(bb.x + i, bb.y + j, Rgba8::TRANSPARENT);
                    }
                }
            }
            if wrap {
                buf.blit_wrapped(&float, bb.x + dx, bb.y + dy, cr);
            } else {
                buf.blit_over(&float, Point::new(bb.x + dx, bb.y + dy));
            }
        }
        // Move the mask BEFORE committing so the pixel record captures the translated mask as its
        // "after": undo restores both the pixels and the mask to their pre-nudge positions, redo
        // re-applies both. (Assign directly — not via set_selection — so it isn't a separate step.
        // Fully off-canvas without wrap ⇒ the clipped mask is empty ⇒ None.)
        self.doc.selection =
            (if wrap { sel.translated_wrapped(dx, dy, cr) } else { sel.translated(dx, dy) })
                .nonempty()
                .map(Arc::new);
        self.commit_edit(before);
    }

    /// Nudge whatever the Move tool would drag: the selected pixels if a selection exists, else the
    /// active layer / move-group.
    pub fn nudge_move(&mut self, dx: i32, dy: i32) {
        if self.doc.selection.as_ref().and_then(|s| s.bounds()).is_some() {
            self.nudge_selection(dx, dy);
        } else {
            self.nudge_layers(dx, dy);
        }
    }

    // ---- move draft (drag → relocate → commit, like the shape/paste drafts) ----
    //
    // The Move tool's draw→adjust→commit flow. Begin lifts the moved content (selected pixels, or
    // the move-group layers when there's no selection) into floating buffer(s); each MoveDraftMove
    // re-applies it from the pre-lift frame at the accumulated offset; the content lives in the
    // layer(s) the whole time (so a crash autosave recovers the in-progress move), washed soft cyan
    // to read as "pending". Commit records one undo step; cancel restores the pre-lift frame.

    /// Begin a move draft from the current selection (the selected pixels) or, with no selection,
    /// the move-group layers. No-op if a draft is already open, the active layer isn't editable, or
    /// (selection case) the selection is empty. The shell calls this on the first drag movement.
    pub fn move_draft_begin(&mut self) {
        if self.move_draft.is_some() || !self.active_editable() {
            return;
        }
        let fi = self.doc.active_frame;
        let fid = self.doc.frames[fi].id;
        let sel_before = self.doc.selection.clone();

        // Selection case: lift a COPY of the selected pixels (the document is NOT touched).
        if let Some(sel) = self.selection_clone() {
            if let Some(bb) = sel.bounds() {
                let lid = self.doc.frames[fi].active_layer().id;
                let src = &self.doc.frames[fi].active_layer().pixels;
                let mut floating = RgbaBuffer::new(bb.w, bb.h);
                for j in 0..bb.h as i32 {
                    for i in 0..bb.w as i32 {
                        if sel.get(bb.x + i, bb.y + j) {
                            floating.set(i, j, src.get(bb.x + i, bb.y + j));
                        }
                    }
                }
                self.move_draft = Some(MoveDraft {
                    fid,
                    sel_before,
                    floats: vec![MoveFloat { lid, pixels: floating, anchor: Point::new(bb.x, bb.y) }],
                    is_selection: true,
                    bbox: Some(bb),
                    offset: Point::new(0, 0),
                });
                return;
            }
        }

        // Layer case (no selection): copy the editable move-group (or the active layer).
        let editable = |li: usize, f: &crate::document::Frame| {
            li < f.layers.len() && f.layers[li].visible && !f.layers[li].locked
        };
        let mut idxs: Vec<usize> =
            self.layer_sel.iter().copied().filter(|&li| editable(li, &self.doc.frames[fi])).collect();
        idxs.sort_unstable();
        idxs.dedup();
        if idxs.is_empty() {
            let al = self.doc.frames[fi].active_layer;
            if editable(al, &self.doc.frames[fi]) {
                idxs.push(al);
            }
        }
        if idxs.is_empty() {
            return;
        }
        let floats: Vec<MoveFloat> = idxs
            .iter()
            .map(|&li| MoveFloat {
                lid: self.doc.frames[fi].layers[li].id,
                pixels: self.doc.frames[fi].layers[li].pixels.clone(),
                anchor: Point::new(0, 0),
            })
            .collect();
        let bbox = floats.iter().fold(None, |acc, f| match (acc, f.pixels.opaque_bounds()) {
            (Some(a), Some(b)) => Some(union_irect(a, b)),
            (a, b) => a.or(b),
        });
        self.move_draft = Some(MoveDraft { fid, sel_before, floats, is_selection: false, bbox, offset: Point::new(0, 0) });
    }

    /// Relocate the move draft by (dx, dy) — updates the offset only; the document is untouched
    /// (the move shows as a display-time preview). Honours Wrap (both kinds) and Protect (layer move
    /// only — pixel moves don't clamp, matching the immediate Move). No-op if no draft is open.
    pub fn move_draft_move(&mut self, dx: i32, dy: i32) {
        let (is_selection, mut off, bbox) = match &self.move_draft {
            Some(d) => (d.is_selection, Point::new(d.offset.x + dx, d.offset.y + dy), d.bbox),
            None => return,
        };
        if !is_selection && self.settings.protect_pixels {
            if let Some(bb) = bbox {
                let (cx, cy) = self.clamp_move_to_canvas(bb, off.x, off.y);
                off = Point::new(cx, cy);
            }
        }
        if let Some(d) = self.move_draft.as_mut() {
            d.offset = off;
        }
    }

    /// A clone of the active frame with the draft's lift+move applied, for the display preview — or
    /// `None` when no draft is open on the active frame. The document itself is never modified.
    fn move_draft_preview_frame(&self) -> Option<Frame> {
        let d = self.move_draft.as_ref()?;
        let fi = self.doc.active_frame;
        if self.doc.frames[fi].id != d.fid {
            return None;
        }
        let mut frame = self.doc.frames[fi].clone();
        move_draft_paint(d, &mut frame, self.settings.wrap, self.doc.canvas_rect());
        Some(frame)
    }

    /// Commit the move draft: materialize the relocation into the document as one undo step (carrying
    /// the selection transition). This is the ONLY path that makes the move permanent. A zero-offset
    /// draft (no movement) commits nothing.
    pub fn move_draft_commit(&mut self) {
        let d = match self.move_draft.take() {
            Some(d) => d,
            None => return,
        };
        if d.offset == Point::new(0, 0) {
            return; // nothing moved → no document change, no undo step
        }
        let fi = match self.doc.frame_index_by_id(d.fid) {
            Some(fi) => fi,
            None => return,
        };
        let cr = self.doc.canvas_rect();
        let before = self.doc.frames[fi].clone();
        let translated = move_draft_paint(&d, &mut self.doc.frames[fi], self.settings.wrap, cr);
        if let Some(m) = translated {
            // The marquee moves with the committed pixels; fully off-canvas ⇒ empty ⇒ None.
            self.doc.selection = m.nonempty().map(Arc::new);
        }
        let after = self.doc.frames[fi].clone();
        self.doc.record_frame_content(d.fid, before, after, d.sel_before);
    }

    /// Discard the move draft. The document was never touched while it was open, so this just drops
    /// the draft — no restore, no undo step. (Leaving the editor / a crash do the same implicitly.)
    pub fn move_draft_cancel(&mut self) {
        self.move_draft = None;
    }

    /// The move draft's bounding rect at its current offset (top-left + size), if one is open — for
    /// the shell to show Commit/Cancel and know a draft is active.
    pub fn move_draft_rect(&self) -> Option<IRect> {
        let d = self.move_draft.as_ref()?;
        let bb = d.bbox?;
        let o = self.doc.origin();
        Some(IRect::new(bb.x + d.offset.x - o.x, bb.y + d.offset.y - o.y, bb.w, bb.h))
    }

    pub fn set_layer_opacity(&mut self, i: usize, o: u8) {
        if i < self.doc.active_frame().layers.len() {
            self.edit_frame(|s| s.doc.active_frame_mut().layers[i].opacity = o);
        }
    }
    pub fn set_layer_visible(&mut self, i: usize, v: bool) {
        if i < self.doc.active_frame().layers.len() {
            self.edit_frame(|s| s.doc.active_frame_mut().layers[i].visible = v);
        }
    }
    pub fn set_layer_locked(&mut self, i: usize, v: bool) {
        if i < self.doc.active_frame().layers.len() {
            self.doc.active_frame_mut().layers[i].locked = v;
        }
    }
    pub fn rename_layer(&mut self, i: usize, name: impl Into<String>) {
        if i < self.doc.active_frame().layers.len() {
            let name = name.into();
            self.edit_frame(move |s| s.doc.active_frame_mut().layers[i].name = name);
        }
    }

    /// Copy/duplicate the active layer into N target frames (SPEC §15 cross-frame).
    pub fn duplicate_layer_to_frames(&mut self, targets: &[usize]) {
        let src = self.doc.active_frame().active_layer().clone();
        self.edit_doc("layer_to_frames", |s| {
            for &t in targets {
                if t < s.doc.frames.len() && s.doc.frames[t].layers.len() < crate::document::MAX_LAYERS {
                    let mut copy = src.clone();
                    copy.id = s.doc.layer_ids.alloc();
                    s.doc.frames[t].layers.push(copy);
                }
            }
        });
    }

    // ---- canvas ops (flip/rotate/resize/crop) live in session/canvas.rs (SPEC §28.1) [F-17] ----

    // ---- palettes ----

    pub fn add_palette_color(&mut self, c: Rgba8) {
        self.doc.palette_mut().colors.push(c);
    }
    pub fn remove_palette_color(&mut self, i: usize) {
        let p = self.doc.palette_mut();
        if i < p.colors.len() {
            p.colors.remove(i);
        }
    }
    pub fn set_palette_color(&mut self, i: usize, c: Rgba8) {
        let p = self.doc.palette_mut();
        if i < p.colors.len() {
            p.colors[i] = c;
        }
    }
    pub fn duplicate_palette_color(&mut self, i: usize) {
        let p = self.doc.palette_mut();
        if i < p.colors.len() {
            let c = p.colors[i];
            p.colors.insert(i + 1, c);
        }
    }
    /// Swap two palette entries (used by the shell to move a swatch left/right/up/down in the grid).
    pub fn swap_palette_colors(&mut self, i: usize, j: usize) {
        let p = self.doc.palette_mut();
        if i != j && i < p.colors.len() && j < p.colors.len() {
            p.colors.swap(i, j);
        }
    }
    pub fn new_palette(&mut self, name: impl Into<String>) {
        self.doc.palettes.push(crate::document::Palette { name: name.into(), colors: Vec::new() });
        self.doc.active_palette = self.doc.palettes.len() - 1;
    }
    pub fn set_active_palette(&mut self, i: usize) {
        if i < self.doc.palettes.len() {
            self.doc.active_palette = i;
        }
    }
    pub fn rename_palette(&mut self, name: impl Into<String>) {
        self.doc.palette_mut().name = name.into();
    }
    pub fn clear_palette(&mut self) {
        self.doc.palette_mut().colors.clear();
    }

    // ---- animation / rng ----

    pub fn play(&mut self) {
        // Begin playback from the CURRENT active frame (the one being edited), not always frame 0:
        // align the virtual clock to that frame's start offset in the timeline. Because playback
        // loops, every frame is still shown once the animation wraps around.
        self.clock.now_us = self.frame_start_us(self.doc.active_frame);
        self.playing = true;
    }
    /// Start time (µs) of frame `index` in the linear timeline — the sum of all earlier frames'
    /// durations (an out-of-range index simply sums them all). Used to seed the play clock.
    fn frame_start_us(&self, index: usize) -> u64 {
        self.doc.frames.iter().take(index).map(|f| f.duration_us as u64).sum()
    }
    pub fn pause(&mut self) {
        self.playing = false;
    }
    pub fn is_playing(&self) -> bool {
        self.playing
    }
    pub fn advance_clock_ms(&mut self, ms: u64) {
        self.clock.advance_ms(ms);
    }
    pub fn set_seed(&mut self, seed: u64) {
        self.rng = SeededRng::new(seed);
    }

    // ---- io ----

    pub fn save_bytes(&self) -> Vec<u8> {
        io::save_to_bytes(&self.doc)
    }
    pub fn load_bytes(&mut self, data: &[u8]) -> Result<(), io::IoError> {
        // The selection now travels inside the document (deserialized by `io`), so it is NOT cleared
        // here — a crash-recovery load restores the user's selection. The clipboard / paste draft are
        // genuine session state and are reset.
        self.doc = io::load_from_bytes(data)?;
        self.clipboard = None;
        self.paste_draft = None;
        self.move_draft = None; // a stale draft would reference the previous document's frame [F-29]
        self.move_sel_before = None; // drop any half-open selection-move drag
        Ok(())
    }

    // ---- gradient oracle access ----

    pub fn assert_last_gradient(&self, tol: u8) -> Option<crate::probe::GradientOracle> {
        let (kind, stops, p0, p1, smooth, fid, lid) = self.last_gradient.as_ref()?;
        let fi = self.doc.frame_index_by_id(*fid)?;
        let li = self.doc.frames[fi].layer_index_by_id(*lid)?;
        Some(crate::probe::gradient_oracle(
            &self.doc.frames[fi].layers[li].pixels,
            *kind,
            stops,
            *p0,
            *p1,
            *smooth,
            tol,
        ))
    }

    /// The undo invariant (SPEC §10): the last edit, do→undo→redo, returns the document to
    /// an identical content hash; undo must actually change something.
    pub fn assert_undo_restores(&mut self) -> bool {
        let after = self.doc.content_hash();
        if !self.doc.undo() {
            return false;
        }
        let undone = self.doc.content_hash();
        if !self.doc.redo() {
            return false;
        }
        let redone = self.doc.content_hash();
        redone == after && undone != after
    }

    pub fn hash_hex_active_layer(&self) -> String {
        hash_hex(self.doc.active_frame().active_layer().pixels.content_hash())
    }

    pub fn bounds_of_selection(&self) -> Option<IRect> {
        // Report bounds in canvas-relative coordinates (gutter → negative), subtracting the origin.
        let o = self.doc.origin();
        self.doc.selection.as_ref().and_then(|m| m.bounds()).map(|b| IRect::new(b.x - o.x, b.y - o.y, b.w, b.h))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Canvas-relative view of the current selection mask: `.get(x, y)` offsets by the gutter origin
    /// so tests can assert selection membership in canvas coordinates. False when there's no selection.
    struct SelCanvas<'a>(&'a Session);
    impl SelCanvas<'_> {
        fn get(&self, x: i32, y: i32) -> bool {
            let o = self.0.doc.origin();
            self.0.doc.selection.as_ref().map(|m| m.get(x + o.x, y + o.y)).unwrap_or(false)
        }
    }

    #[test]
    fn pencil_then_undo_redo() {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        s.tap(5, 5);
        assert_eq!(s.pixel(0, 0, 5, 5), Rgba8::WHITE);
        let after = s.doc.content_hash();
        assert!(s.doc.undo());
        assert_eq!(s.pixel(0, 0, 5, 5), Rgba8::TRANSPARENT);
        assert!(s.doc.redo());
        assert_eq!(s.doc.content_hash(), after);
    }

    #[test]
    fn multi_layer_composite_and_opacity() {
        let mut s = Session::new(8, 8);
        s.settings.primary = Rgba8::rgb(0, 255, 0);
        s.tool = ToolKind::Bucket;
        s.tap(0, 0); // fill layer 0 green
        s.add_layer();
        s.settings.primary = Rgba8::rgb(255, 0, 0);
        s.tap(0, 0); // fill layer 1 red
        let flat = render::composite_active(&s.doc);
        assert_eq!(flat.get(4, 4), Rgba8::rgb(255, 0, 0));
    }

    #[test]
    fn layer_rgba_bytes_exports_the_layer_alone() {
        let mut s = Session::new(8, 8);
        s.settings.primary = Rgba8::WHITE;
        s.tap(1, 1); // layer 0
        s.add_layer();
        s.settings.primary = Rgba8::rgb(255, 0, 0);
        s.tap(2, 2); // layer 1 (active after add)
        let px = |b: &[u8], x: usize, y: usize| {
            let o = (y * 8 + x) * 4;
            [b[o], b[o + 1], b[o + 2], b[o + 3]]
        };
        let l0 = s.layer_rgba_bytes(0, 0);
        let l1 = s.layer_rgba_bytes(0, 1);
        assert_eq!(px(&l0, 1, 1), [255, 255, 255, 255]);
        assert_eq!(px(&l0, 2, 2), [0, 0, 0, 0], "layer 0 lacks layer 1's pixel");
        assert_eq!(px(&l1, 2, 2), [255, 0, 0, 255]);
        assert_eq!(px(&l1, 1, 1), [0, 0, 0, 0], "the layer alone, not the composite");
        assert_eq!(s.layer_rgba_bytes(99, 99).len(), 8 * 8 * 4, "stale indices clamp");
    }

    #[test]
    fn frames_and_durations() {
        let mut s = Session::new(8, 8);
        s.add_frame();
        s.add_frame();
        assert_eq!(s.doc.frames.len(), 3);
        s.set_all_durations(50_000);
        assert!(s.doc.frames.iter().all(|f| f.duration_us == 50_000));
        s.remove_frame(1);
        assert_eq!(s.doc.frames.len(), 2);
        // structural ops are undoable
        assert!(s.doc.undo());
        assert_eq!(s.doc.frames.len(), 3);
    }

    #[test]
    fn selection_and_fill() {
        let mut s = Session::new(16, 16);
        s.tool = ToolKind::SelectRect;
        s.stroke_path(&[(2, 2), (5, 5)]);
        assert_eq!(s.bounds_of_selection(), Some(IRect::new(2, 2, 4, 4)));
        s.settings.primary = Rgba8::WHITE;
        s.fill_selection();
        assert_eq!(s.pixel(0, 0, 3, 3), Rgba8::WHITE);
        assert_eq!(s.pixel(0, 0, 10, 10), Rgba8::TRANSPARENT);
    }

    #[test]
    fn copy_paste_roundtrip() {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        s.tool = ToolKind::Pencil;
        s.tap(1, 1);
        s.tool = ToolKind::SelectRect;
        s.stroke_path(&[(0, 0), (3, 3)]);
        s.copy();
        s.select_none();
        s.paste();
        assert_eq!(s.pixel(0, 0, 1, 1), Rgba8::WHITE);
    }

    #[test]
    fn paste_draft_moves_then_commits() {
        let mut s = Session::new(8, 8);
        s.settings.primary = Rgba8::rgb(255, 0, 0);
        s.tool = ToolKind::Pencil;
        for (x, y) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
            s.tap(x, y);
        }
        s.tool = ToolKind::SelectRect;
        s.stroke_path(&[(0, 0), (1, 1)]); // select the 2x2 red block
        s.copy();
        assert!(s.paste_draft_rect().is_none());
        s.paste_begin(); // floats at the copy origin
        assert_eq!(s.paste_draft_rect(), Some(IRect::new(0, 0, 2, 2)));
        s.paste_move(4, 4);
        assert_eq!(s.paste_draft_rect(), Some(IRect::new(4, 4, 2, 2)));
        s.paste_commit();
        assert!(s.paste_draft_rect().is_none());
        assert_eq!(s.pixel(0, 0, 4, 4), Rgba8::rgb(255, 0, 0));
        assert_eq!(s.pixel(0, 0, 5, 5), Rgba8::rgb(255, 0, 0));
        assert!(s.doc.undo()); // the commit is a single undo step
        assert_eq!(s.pixel(0, 0, 4, 4), Rgba8::TRANSPARENT);
    }

    #[test]
    fn paste_begin_empty_is_noop_and_cancel_discards() {
        let mut s = Session::new(8, 8);
        s.paste_begin();
        assert!(s.paste_draft_rect().is_none(), "no draft from an empty clipboard");
        s.settings.primary = Rgba8::WHITE;
        s.tool = ToolKind::Pencil;
        s.tap(2, 2);
        s.tool = ToolKind::SelectRect;
        s.stroke_path(&[(2, 2), (2, 2)]);
        s.copy();
        s.paste_begin();
        assert!(s.paste_draft_rect().is_some());
        s.paste_cancel();
        assert!(s.paste_draft_rect().is_none());
        assert_eq!(s.pixel(0, 0, 2, 2), Rgba8::WHITE); // cancel drew nothing
    }

    #[test]
    fn move_selection_mask_honours_edge_modes() {
        fn sel_2x2(s: &mut Session, x: i32, y: i32) {
            s.tool = ToolKind::SelectRect;
            s.stroke_path(&[(x, y), (x + 1, y + 1)]);
        }
        // Regular: translate the mask, clipping cells that leave the canvas.
        let mut s = Session::new(8, 8);
        sel_2x2(&mut s, 2, 2);
        s.move_selection(2, 2);
        assert!(SelCanvas(&s).get(4, 4));
        assert!(!SelCanvas(&s).get(2, 2)); // pixels never moved, only the mask

        // Wrap: cells leaving an edge re-enter the opposite one.
        let mut s = Session::new(8, 8);
        s.settings.wrap = true;
        sel_2x2(&mut s, 6, 6);
        s.move_selection(2, 2); // (6,6) -> (8,8) wraps to (0,0)
        assert!(SelCanvas(&s).get(0, 0));

        // Protect: clamp so the whole selection stays on-canvas.
        let mut s = Session::new(8, 8);
        s.settings.protect_pixels = true;
        sel_2x2(&mut s, 6, 6);
        s.move_selection(5, 5); // would push off the right/bottom → clamped to no move
        assert!(SelCanvas(&s).get(6, 6));
        s.move_selection(-3, -3); // moves freely the other way
        assert!(SelCanvas(&s).get(3, 3));
    }

    #[test]
    fn outline_mask_committed_and_drag_preview() {
        let mut s = Session::new(16, 16);
        assert!(s.outline_mask().is_none());
        s.run_script("SelectTool(SelectRect); Stroke([(2,2),(5,5)])").unwrap();
        assert_eq!(s.outline_mask().unwrap().count(), 16); // committed 4x4
        // mid-drag preview (no PointerUp) reflects the in-progress rectangle
        s.run_script("SelectNone(); SelectTool(SelectRect); PointerDown(0,0); PointerMove(3,3)").unwrap();
        let m = s.outline_mask().unwrap();
        assert_eq!(m.count(), 16);
        let mut bytes = vec![0u8; 16 * 16];
        assert_eq!(s.outline_mask_bytes(&mut bytes), 256);
        assert_eq!(bytes[0], 1); // (0,0) inside the preview
        assert_eq!(bytes[15 * 16 + 15], 0); // far corner outside
    }

    #[test]
    fn drag_shows_live_preview_without_committing() {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::rgb(255, 0, 0);
        s.settings.shape_fill = false;
        s.settings.line_width = 1;
        s.tool = ToolKind::Rectangle;
        s.pointer_down(2, 2);
        s.pointer_move(10, 8); // mid-drag, not released
        // nothing committed to the layer yet
        assert_eq!(s.pixel(0, 0, 2, 2), Rgba8::TRANSPARENT);
        assert!(!s.doc.can_undo());
        // but the display shows the preview outline at the corner
        let disp = s.display_bytes(false, false, false);
        let i = (2 * 16 + 2) * 4;
        assert_eq!(&disp[i..i + 4], &[255, 0, 0, 255], "preview pixel should be primary red");
        // releasing commits it for real
        s.pointer_up();
        assert_eq!(s.pixel(0, 0, 2, 2), Rgba8::rgb(255, 0, 0));
        assert!(s.doc.can_undo());
    }

    #[test]
    fn precision_pencil_plots_at_cursor_not_touch() {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        s.tool = ToolKind::Pencil; // precision is now a mode of the Pencil
        s.set_cursor(3, 4);
        s.plot_cursor(); // draws a dot at the reticle, not under any "touch"
        assert_eq!(s.pixel(0, 0, 3, 4), Rgba8::WHITE);
        assert!(s.doc.undo());
        assert_eq!(s.pixel(0, 0, 3, 4), Rgba8::TRANSPARENT);
    }

    #[test]
    fn precision_pen_hold_dab_and_each_drag_are_separate_undo_steps() {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        s.tool = ToolKind::Pencil;
        s.set_cursor(2, 2);
        s.cursor_pen_down(); // entering Hold stamps (2,2) and commits it immediately
        assert_eq!(s.pixel(0, 0, 2, 2), Rgba8::WHITE);
        s.cursor_stroke_begin(); // finger down …
        s.move_cursor(5, 0); // … drag the reticle → draws a horizontal line …
        s.cursor_stroke_end(); // … finger up: the drag is ONE undo step
        assert_eq!(s.pixel(0, 0, 7, 2), Rgba8::WHITE);
        assert_eq!(s.pixel(0, 0, 4, 2), Rgba8::WHITE); // interpolated
        s.cursor_stroke_begin(); // a second drag while still holding
        s.move_cursor(0, 3); // down to (7,5)
        s.cursor_stroke_end();
        assert_eq!(s.pixel(0, 0, 7, 5), Rgba8::WHITE);
        s.cursor_pen_up(); // exiting Hold adds NO step of its own
        // Undo #1: only the second drag.
        assert!(s.doc.undo());
        assert_eq!(s.pixel(0, 0, 7, 5), Rgba8::TRANSPARENT);
        assert_eq!(s.pixel(0, 0, 4, 2), Rgba8::WHITE);
        // Undo #2: the first drag; the Hold dab survives.
        assert!(s.doc.undo());
        assert_eq!(s.pixel(0, 0, 4, 2), Rgba8::TRANSPARENT);
        assert_eq!(s.pixel(0, 0, 2, 2), Rgba8::WHITE);
        // Undo #3: the Hold dab itself.
        assert!(s.doc.undo());
        assert_eq!(s.pixel(0, 0, 2, 2), Rgba8::TRANSPARENT);
        assert!(!s.doc.undo()); // nothing else to undo
    }

    #[test]
    fn precision_eraser_clears_through_reticle() {
        let mut s = Session::new(16, 16);
        // paint a solid row first
        s.settings.primary = Rgba8::WHITE;
        s.tool = ToolKind::Pencil;
        s.set_cursor(2, 2);
        s.cursor_pen_down();
        s.cursor_stroke_begin();
        s.move_cursor(5, 0);
        s.cursor_stroke_end();
        s.cursor_pen_up();
        // now erase along it in precision mode
        s.tool = ToolKind::Eraser;
        s.set_cursor(2, 2);
        s.cursor_pen_down();
        s.cursor_stroke_begin();
        s.move_cursor(5, 0);
        s.cursor_stroke_end();
        s.cursor_pen_up();
        assert_eq!(s.pixel(0, 0, 4, 2), Rgba8::TRANSPARENT); // erased back to transparent
        assert!(s.doc.undo()); // the erase DRAG is its own undo step
        assert_eq!(s.pixel(0, 0, 4, 2), Rgba8::WHITE);
    }

    #[test]
    fn precision_brush_blends_through_reticle() {
        let mut s = Session::new(16, 16);
        // Brush uses alpha-over: a translucent stamp blends, not replaces.
        s.settings.primary = Rgba8::new(255, 0, 0, 128);
        s.tool = ToolKind::Brush;
        s.set_cursor(5, 5);
        s.plot_cursor();
        let px = s.pixel(0, 0, 5, 5);
        assert!(px.a > 0 && px.a < 255, "brush should blend (partial alpha), got {:?}", px);
    }

    #[test]
    fn precision_airbrush_sprays_through_reticle() {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        s.settings.intensity = 255;
        s.settings.brush_size = 4;
        s.tool = ToolKind::Airbrush;
        s.set_cursor(8, 8);
        // a continuous precision spray: Hold (dab step) + one drag segment (drag step)
        s.cursor_pen_down();
        s.cursor_stroke_begin();
        s.move_cursor(2, 0);
        s.move_cursor(2, 0);
        s.cursor_stroke_end();
        s.cursor_pen_up();
        let h = s.doc.active_frame().active_layer().pixels.content_hash();
        assert_ne!(h, RgbaBuffer::new(16, 16).content_hash(), "airbrush should have painted something");
        assert!(s.doc.undo()); // the drag
        assert!(s.doc.undo()); // the Hold dab
        assert!(!s.doc.undo(), "dab + drag are exactly two undo steps");
    }

    #[test]
    fn precision_dodge_lightens_through_reticle() {
        let mut s = Session::new(8, 8);
        s.settings.primary = Rgba8::rgb(100, 100, 100);
        s.tool = ToolKind::Pencil;
        s.tap(3, 3); // a mid-grey pixel to lighten
        let before = s.pixel(0, 0, 3, 3);
        // Dodge in precision mode: aim the reticle and DRAW (plot_cursor) one stamp.
        s.tool = ToolKind::Dodge;
        s.settings.intensity = 255;
        s.set_cursor(3, 3);
        s.plot_cursor();
        let after = s.pixel(0, 0, 3, 3);
        assert!(after.r > before.r, "dodge lightened the pixel ({} -> {})", before.r, after.r);
        assert!(s.doc.undo()); // one undo step
        assert_eq!(s.pixel(0, 0, 3, 3), before);
    }

    #[test]
    fn precision_eyedropper_picks_at_reticle() {
        let mut s = Session::new(8, 8);
        s.settings.primary = Rgba8::rgb(0, 200, 0);
        s.tool = ToolKind::Pencil;
        s.tap(5, 5); // a green pixel to sample
        s.settings.primary = Rgba8::rgb(10, 10, 10);
        s.tool = ToolKind::Eyedropper;
        s.set_cursor(5, 5);
        s.eyedrop_cursor();
        assert_eq!(s.settings.primary, Rgba8::rgb(0, 200, 0));
        // a transparent pixel is a no-op (keeps the current primary)
        s.set_cursor(0, 0);
        s.eyedrop_cursor();
        assert_eq!(s.settings.primary, Rgba8::rgb(0, 200, 0));
    }

    #[test]
    fn precision_select_by_color_selects_at_reticle() {
        let mut s = Session::new(8, 8);
        s.settings.primary = Rgba8::rgb(0, 200, 0);
        s.tool = ToolKind::Pencil;
        s.tap(2, 2);
        s.tap(5, 5); // same colour, NOT contiguous with (2,2)
        s.tool = ToolKind::SelectByColor;
        s.set_cursor(2, 2);
        s.select_color_cursor(); // contiguous default: only the (2,2) region
        let sel = SelCanvas(&s);
        assert!(sel.get(2, 2));
        assert!(!sel.get(5, 5), "contiguous select stops at the gap");
        assert!(!sel.get(3, 3), "background isn't selected");
        // global (non-contiguous) picks up both green pixels — via the DSL to cover the parse path
        s.settings.contiguous = false;
        s.run_script("SelectColorCursor()").unwrap();
        assert!(SelCanvas(&s).get(2, 2) && SelCanvas(&s).get(5, 5));
        // each press was one undo step over the selection
        assert!(s.doc.undo());
        assert!(!SelCanvas(&s).get(5, 5) && SelCanvas(&s).get(2, 2));
        assert!(s.doc.undo());
        assert!(s.doc.selection.is_none());
    }

    #[test]
    fn precision_bucket_fills_at_reticle() {
        let mut s = Session::new(8, 8);
        // a full-height green wall at x=3 splits the canvas into two disconnected regions
        s.settings.primary = Rgba8::rgb(0, 200, 0);
        s.tool = ToolKind::Pencil;
        for y in 0..8 {
            s.tap(3, y);
        }
        s.settings.primary = Rgba8::rgb(200, 0, 0);
        s.tool = ToolKind::Bucket;
        s.set_cursor(1, 1);
        s.run_script("FillCursor()").unwrap(); // via the DSL to cover the parse path
        assert_eq!(s.pixel(0, 0, 1, 1), Rgba8::rgb(200, 0, 0));
        assert_eq!(s.pixel(0, 0, 0, 7), Rgba8::rgb(200, 0, 0), "whole left region filled");
        assert_eq!(s.pixel(0, 0, 3, 4), Rgba8::rgb(0, 200, 0), "wall untouched");
        assert_eq!(s.pixel(0, 0, 5, 5), Rgba8::TRANSPARENT, "contiguous fill stops at the wall");
        // the press was ONE undo step
        assert!(s.doc.undo());
        assert_eq!(s.pixel(0, 0, 1, 1), Rgba8::TRANSPARENT);
        assert_eq!(s.pixel(0, 0, 3, 4), Rgba8::rgb(0, 200, 0), "undo reverts only the fill");
    }

    #[test]
    fn merge_down_composites_and_removes() {
        let mut s = Session::new(8, 8);
        s.settings.primary = Rgba8::rgb(200, 0, 0); // bottom layer: red
        s.tap(1, 1);
        s.tap(2, 2);
        s.run_script("AddLayer()").unwrap();
        s.settings.primary = Rgba8::rgb(0, 200, 0); // top layer: green
        s.tap(2, 2); // covers a red pixel
        s.tap(3, 3); // lands on empty below
        s.run_script("MergeDown(1)").unwrap();
        assert_eq!(s.doc.active_frame().layers.len(), 1);
        assert_eq!(s.doc.active_frame().active_layer, 0);
        assert_eq!(s.pixel(0, 0, 1, 1), Rgba8::rgb(200, 0, 0), "below-only pixel untouched");
        assert_eq!(s.pixel(0, 0, 2, 2), Rgba8::rgb(0, 200, 0), "opaque top wins");
        assert_eq!(s.pixel(0, 0, 3, 3), Rgba8::rgb(0, 200, 0), "top-only pixel lands below");
        // ONE undo restores both layers and the below layer's covered pixel
        assert!(s.doc.undo());
        assert_eq!(s.doc.active_frame().layers.len(), 2);
        assert_eq!(s.pixel(0, 0, 2, 2), Rgba8::rgb(200, 0, 0));
        assert_eq!(s.pixel(0, 1, 2, 2), Rgba8::rgb(0, 200, 0));
    }

    #[test]
    fn merge_down_opacity_visibility_and_guards() {
        let mut s = Session::new(4, 4);
        s.settings.primary = Rgba8::rgb(100, 100, 100);
        s.tap(0, 0);
        s.run_script("AddLayer()").unwrap();
        s.settings.primary = Rgba8::WHITE;
        s.tap(0, 0);
        // the source layer's opacity blends exactly like the compositor
        s.run_script("SetLayerOpacity(1, 128); MergeDown(1)").unwrap();
        let expect = crate::color::over_opacity(Rgba8::WHITE, Rgba8::rgb(100, 100, 100), 128);
        assert_eq!(s.pixel(0, 0, 0, 0), expect);
        assert_eq!(s.doc.active_frame().layers.len(), 1);
        // bottom layer: no-op
        s.merge_down(0);
        assert_eq!(s.doc.active_frame().layers.len(), 1);
        // an invisible source merges as a plain remove (contributes no pixels)
        s.run_script("AddLayer()").unwrap();
        s.settings.primary = Rgba8::rgb(0, 0, 250);
        s.tap(1, 1);
        s.run_script("SetLayerVisible(1, false); MergeDown(1)").unwrap();
        assert_eq!(s.doc.active_frame().layers.len(), 1);
        assert_eq!(s.pixel(0, 0, 1, 1), Rgba8::TRANSPARENT);
        // a locked layer below refuses the merge (its pixels are protected)
        s.run_script("AddLayer()").unwrap();
        s.tap(1, 1);
        s.run_script("SetLayerLocked(0, true); MergeDown(1)").unwrap();
        assert_eq!(s.doc.active_frame().layers.len(), 2);
    }

    #[test]
    fn bucket_all_layers_bounds_region_by_composite() {
        let mut s = Session::new(8, 8);
        let o = s.doc.origin();
        for y in 0..8 {
            s.doc.active_frame_mut().layers[0].pixels.set(o.x + 4, o.y + y, Rgba8::BLACK); // wall (canvas x=4)
        }
        let top = s.doc.new_layer("top");
        s.doc.active_frame_mut().layers.push(top);
        s.doc.active_frame_mut().active_layer = 1; // empty active layer on top

        s.tool = ToolKind::Bucket;
        s.settings.primary = Rgba8::WHITE;

        // All layers ON: the composited wall bounds the fill (region = left of x=4).
        s.settings.fill_all_layers = true;
        s.tap(0, 0);
        assert_eq!(s.pixel(0, 1, 3, 0), Rgba8::WHITE);
        assert_eq!(s.pixel(0, 1, 4, 0), Rgba8::TRANSPARENT, "stops at the composited wall");
        assert_eq!(s.pixel(0, 1, 5, 0), Rgba8::TRANSPARENT, "right of the wall is a separate region");

        // All layers OFF: only the (empty) active layer decides, so the wall is invisible and the
        // fill crosses x=4.
        s.doc.undo();
        s.settings.fill_all_layers = false;
        s.tap(0, 0);
        assert_eq!(s.pixel(0, 1, 4, 0), Rgba8::WHITE, "active layer has no wall, so the fill crosses x=4");
        assert_eq!(s.pixel(0, 1, 5, 0), Rgba8::WHITE);
    }

    #[test]
    fn rotate_90_swaps_dims_and_is_undoable() {
        let mut s = Session::new(16, 8);
        s.settings.primary = Rgba8::WHITE;
        s.tap(15, 0); // top-right of a 16x8 canvas
        let before = s.doc.content_hash();
        s.rotate(1); // 90° CW
        assert_eq!(s.size(), (8, 16));
        // top-right (15,0) → after 90°cw at (oh-1-0, 15)=(7,15)
        assert_eq!(s.pixel(0, 0, 7, 15), Rgba8::WHITE);
        assert!(s.doc.undo());
        assert_eq!(s.size(), (16, 8));
        assert_eq!(s.doc.content_hash(), before);
    }

    #[test]
    fn rotate_four_times_is_identity() {
        let mut s = Session::new(12, 12);
        s.settings.primary = Rgba8::WHITE;
        s.tap(2, 5);
        let h = s.doc.content_hash();
        for _ in 0..4 {
            s.rotate(1);
        }
        assert_eq!(s.size(), (12, 12));
        assert_eq!(s.doc.content_hash(), h);
    }

    #[test]
    fn crop_to_selection_resizes() {
        let mut s = Session::new(32, 32);
        s.settings.primary = Rgba8::WHITE;
        s.tap(10, 10);
        s.tool = ToolKind::SelectRect;
        s.stroke_path(&[(8, 8), (15, 15)]);
        s.crop_to_selection();
        assert_eq!(s.size(), (8, 8));
        assert_eq!(s.pixel(0, 0, 2, 2), Rgba8::WHITE); // (10,10) - (8,8)
        assert!(s.doc.undo());
        assert_eq!(s.size(), (32, 32));
    }

    #[test]
    fn resize_canvas_centered_and_undo() {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        s.tap(0, 0);
        s.resize_canvas(32, 32, 1, 1);
        assert_eq!(s.size(), (32, 32));
        assert_eq!(s.pixel(0, 0, 8, 8), Rgba8::WHITE); // shifted by +8,+8
        assert!(s.doc.undo());
        assert_eq!(s.size(), (16, 16));
        assert_eq!(s.pixel(0, 0, 0, 0), Rgba8::WHITE);
    }

    #[test]
    fn resize_canvas_nine_anchors() {
        // A bottom-right anchor keeps the bottom-right corner pixel at the corner when growing.
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        s.tap(15, 15);
        s.resize_canvas(32, 32, 2, 2);
        assert_eq!(s.size(), (32, 32));
        assert_eq!(s.pixel(0, 0, 31, 31), Rgba8::WHITE);
        assert!(s.doc.undo());

        // A mixed anchor (right edge, vertical centre): x shifts by the full delta, y by half.
        s.resize_canvas(32, 32, 2, 1);
        assert_eq!(s.pixel(0, 0, 31, 23), Rgba8::WHITE); // (15+16, 15+8)
        assert!(s.doc.undo());

        // The DSL direction names map to the same cells; legacy booleans still parse.
        s.run_script("ResizeCanvas(32, 32, BottomRight)").unwrap();
        assert_eq!(s.pixel(0, 0, 31, 31), Rgba8::WHITE);
        assert!(s.doc.undo());
        s.run_script("ResizeCanvas(32, 32, true)").unwrap(); // legacy: true = Center
        assert_eq!(s.pixel(0, 0, 23, 23), Rgba8::WHITE); // (15+8, 15+8)
    }

    #[test]
    fn flip_frame_flips_all_layers_in_one_undo_step() {
        let mut s = Session::new(8, 8);
        s.settings.primary = Rgba8::WHITE;
        s.tap(0, 0); // layer 0
        s.add_layer();
        s.settings.primary = Rgba8::new(255, 0, 0, 255);
        s.tap(1, 0); // layer 1
        s.flip_frame(true);
        assert_eq!(s.pixel(0, 0, 7, 0), Rgba8::WHITE);
        assert_eq!(s.pixel(0, 1, 6, 0), Rgba8::new(255, 0, 0, 255));
        assert!(s.doc.undo()); // ONE step restores both layers
        assert_eq!(s.pixel(0, 0, 0, 0), Rgba8::WHITE);
        assert_eq!(s.pixel(0, 1, 1, 0), Rgba8::new(255, 0, 0, 255));
    }

    #[test]
    fn rotate_frame_rotates_all_layers_in_one_undo_step() {
        let mut s = Session::new(8, 8);
        s.settings.primary = Rgba8::WHITE;
        s.tap(0, 0); // layer 0
        s.add_layer();
        s.settings.primary = Rgba8::new(255, 0, 0, 255);
        s.tap(7, 0); // layer 1
        s.rotate_frame(2); // 180° about the canvas centre
        assert_eq!(s.pixel(0, 0, 7, 7), Rgba8::WHITE);
        assert_eq!(s.pixel(0, 1, 0, 7), Rgba8::new(255, 0, 0, 255));
        assert!(s.doc.undo()); // ONE step restores both layers
        assert_eq!(s.pixel(0, 0, 0, 0), Rgba8::WHITE);
        assert_eq!(s.pixel(0, 1, 7, 0), Rgba8::new(255, 0, 0, 255));
    }

    #[test]
    fn invert_frame_inverts_all_layers_in_one_undo_step() {
        let mut s = Session::new(8, 8);
        s.settings.primary = Rgba8::WHITE;
        s.tap(0, 0); // layer 0
        s.add_layer();
        s.settings.primary = Rgba8::new(255, 0, 0, 255);
        s.tap(1, 0); // layer 1
        s.run_script("InvertFrame()").unwrap();
        assert_eq!(s.pixel(0, 0, 0, 0), Rgba8::new(0, 0, 0, 255)); // white → black
        assert_eq!(s.pixel(0, 1, 1, 0), Rgba8::new(0, 255, 255, 255)); // red → cyan
        assert!(s.doc.undo()); // ONE step restores both layers
        assert_eq!(s.pixel(0, 0, 0, 0), Rgba8::WHITE);
        assert_eq!(s.pixel(0, 1, 1, 0), Rgba8::new(255, 0, 0, 255));
    }

    #[test]
    fn hsv_frame_scope_previews_and_applies_to_all_layers() {
        let mut s = Session::new(8, 8);
        s.settings.primary = Rgba8::new(255, 0, 0, 255);
        s.tap(0, 0); // layer 0
        s.add_layer();
        s.settings.primary = Rgba8::new(0, 255, 0, 255);
        s.tap(1, 0); // layer 1
        s.run_script("SelectTool(HsvShift)\nSetHsvShift(120, 0, 0)\nSetHsvScope(Frame)").unwrap();
        // The display previews BOTH layers shifted; the document still holds the originals.
        let px = s.display_bytes(false, false, false);
        assert_eq!(&px[0..4], &[0, 255, 0, 255]); // layer 0 at (0,0): red → green
        assert_eq!(&px[4..8], &[0, 0, 255, 255]); // layer 1 at (1,0): green → blue
        assert_eq!(s.pixel(0, 0, 0, 0), Rgba8::new(255, 0, 0, 255));
        s.run_script("ApplyHsvShift()").unwrap();
        assert_eq!(s.pixel(0, 0, 0, 0), Rgba8::new(0, 255, 0, 255));
        assert_eq!(s.pixel(0, 1, 1, 0), Rgba8::new(0, 0, 255, 255));
        assert!(s.doc.undo()); // ONE step restores both layers
        assert_eq!(s.pixel(0, 0, 0, 0), Rgba8::new(255, 0, 0, 255));
        assert_eq!(s.pixel(0, 1, 1, 0), Rgba8::new(0, 255, 0, 255));
    }

    #[test]
    fn hsv_preview_is_display_only_until_apply() {
        let mut s = Session::new(8, 8);
        s.settings.primary = Rgba8::new(255, 0, 0, 255);
        s.tap(0, 0);
        s.run_script("SelectTool(HsvShift)\nSetHsvShift(120, 0, 0)").unwrap();
        // The display previews the shift (red → green) while the document still holds red.
        let px = s.display_bytes(false, false, false);
        assert_eq!(&px[0..4], &[0, 255, 0, 255]);
        assert_eq!(s.pixel(0, 0, 0, 0), Rgba8::new(255, 0, 0, 255));
        // Apply commits it; with the shift zeroed again the display matches the document.
        s.run_script("ApplyHsvShift()\nSetHsvShift(0, 0, 0)").unwrap();
        assert_eq!(s.pixel(0, 0, 0, 0), Rgba8::new(0, 255, 0, 255));
        let px = s.display_bytes(false, false, false);
        assert_eq!(&px[0..4], &[0, 255, 0, 255]);
    }

    // ---- Brightness/Contrast tool (the HSV tool's twin; closed-form oracle in color.rs) ----

    #[test]
    fn brightness_contrast_preview_is_display_only_until_apply() {
        let mut s = Session::new(8, 8);
        let orig = Rgba8::new(100, 150, 200, 255);
        s.settings.primary = orig;
        s.tap(0, 0);
        s.run_script("SelectTool(BrightnessContrast)\nSetBrightnessContrast(10, 1.5)").unwrap();
        // The display previews the adjustment while the document still holds the original.
        let want = crate::color::brightness_contrast(orig, 10, 1.5);
        assert_ne!(want, orig);
        let px = s.display_bytes(false, false, false);
        assert_eq!(&px[0..4], &[want.r, want.g, want.b, want.a]);
        assert_eq!(s.pixel(0, 0, 0, 0), orig);
        // Apply commits it (one undo step); with the sliders reset the display matches the document.
        s.run_script("ApplyBrightnessContrast()\nSetBrightnessContrast(0, 1)").unwrap();
        assert_eq!(s.pixel(0, 0, 0, 0), want);
        let px = s.display_bytes(false, false, false);
        assert_eq!(&px[0..4], &[want.r, want.g, want.b, want.a]);
        assert!(s.doc.undo());
        assert_eq!(s.pixel(0, 0, 0, 0), orig);
    }

    #[test]
    fn brightness_contrast_frame_scope_previews_and_applies_to_all_layers() {
        let mut s = Session::new(8, 8);
        let c0 = Rgba8::new(100, 150, 200, 255);
        let c1 = Rgba8::new(30, 60, 90, 255);
        s.settings.primary = c0;
        s.tap(0, 0); // layer 0
        s.add_layer();
        s.settings.primary = c1;
        s.tap(1, 0); // layer 1
        s.run_script("SelectTool(BrightnessContrast)\nSetBrightnessContrast(-20, 0.5)\nSetBcScope(Frame)")
            .unwrap();
        let w0 = crate::color::brightness_contrast(c0, -20, 0.5);
        let w1 = crate::color::brightness_contrast(c1, -20, 0.5);
        // The display previews BOTH layers adjusted; the document still holds the originals.
        let px = s.display_bytes(false, false, false);
        assert_eq!(&px[0..4], &[w0.r, w0.g, w0.b, w0.a]);
        assert_eq!(&px[4..8], &[w1.r, w1.g, w1.b, w1.a]);
        assert_eq!(s.pixel(0, 0, 0, 0), c0);
        s.run_script("ApplyBrightnessContrast()").unwrap();
        assert_eq!(s.pixel(0, 0, 0, 0), w0);
        assert_eq!(s.pixel(0, 1, 1, 0), w1);
        assert!(s.doc.undo()); // ONE step restores both layers
        assert_eq!(s.pixel(0, 0, 0, 0), c0);
        assert_eq!(s.pixel(0, 1, 1, 0), c1);
    }

    // ---- Rotate tool: layer/selection-scoped rotation + free-angle draft (session/canvas.rs) ----

    #[test]
    fn rotate_layer_90_square_lossless_and_4x_identity() {
        let mut s = Session::new(12, 12);
        s.settings.primary = Rgba8::WHITE;
        s.tap(2, 5);
        let h = s.doc.content_hash();
        s.rotate_layer(1); // 90° CW about the canvas centre — NO resize (unlike `rotate`)
        assert_eq!(s.size(), (12, 12));
        assert_eq!(s.pixel(0, 0, 6, 2), Rgba8::WHITE); // (2,5) → (n-1-y, x) = (6,2)
        assert_eq!(s.pixel(0, 0, 2, 5), Rgba8::TRANSPARENT);
        for _ in 0..3 {
            s.rotate_layer(1);
        }
        assert_eq!(s.size(), (12, 12));
        assert_eq!(s.doc.content_hash(), h, "four 90° layer rotations are the identity on a square canvas");
    }

    #[test]
    fn rotate_layer_touches_active_layer_only() {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        s.tap(1, 1); // layer 0 (the default active layer)
        s.add_layer(); // appended and made active (index 1)
        s.tap(3, 3); // layer 1
        s.rotate_layer(2); // 180° about the canvas centre
        assert_eq!(s.size(), (16, 16), "a layer rotation never resizes the canvas");
        assert_eq!(s.pixel(0, 0, 1, 1), Rgba8::WHITE, "the inactive layer is untouched");
        assert_eq!(s.pixel(0, 1, 12, 12), Rgba8::WHITE, "(3,3) → (15-3,15-3)");
        assert_eq!(s.pixel(0, 1, 3, 3), Rgba8::TRANSPARENT);
    }

    #[test]
    fn rotate_layer_selection_rotates_pixels_and_mask_about_bbox_center() {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        s.tap(2, 4); // left end of a wide bar
        s.tool = ToolKind::SelectRect;
        s.stroke_path(&[(2, 4), (7, 5)]); // a 6×2 selection, bbox centre (5,5)
        s.rotate_layer(1); // 90° CW about the bbox centre

        // The pixel rotates with the selection (wide bar → tall bar).
        assert_eq!(s.pixel(0, 0, 5, 2), Rgba8::WHITE);
        assert_eq!(s.pixel(0, 0, 2, 4), Rgba8::TRANSPARENT);

        // The mask rotated too: the 6×2 region became a 2×6 region (x∈[4,6), y∈[2,8)).
        let sel = SelCanvas(&s);
        assert!(sel.get(5, 2) && sel.get(4, 7), "rotated tall-bar cells are selected");
        assert!(!sel.get(2, 4) && !sel.get(7, 4), "original wide-bar-only cells are deselected");
    }

    #[test]
    fn rotate_layer_90_nonsquare_clips_to_canvas() {
        let mut s = Session::new(32, 16); // non-square
        s.settings.primary = Rgba8::WHITE;
        s.tap(16, 8); // near the centre — stays on-canvas
        s.tap(31, 8); // far edge — rotates off the (now taller-than-wide) footprint
        s.rotate_layer(1);
        assert_eq!(s.size(), (32, 16), "rotate about centre + clip never resizes a non-square canvas");
        assert_eq!(s.pixel(0, 0, 15, 8), Rgba8::WHITE, "the central pixel lands back on-canvas");
        assert_eq!(s.pixel(0, 0, 31, 8), Rgba8::TRANSPARENT, "the edge pixel rotated off-canvas (clipped)");
    }

    #[test]
    fn rotate_draft_begin_set_commit_single_undo_rotated_pixels() {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        s.tap(2, 8);
        let h0 = s.doc.content_hash();
        s.rotate_draft_begin();
        assert_eq!(s.doc.content_hash(), h0, "the draft is non-destructive while open");
        s.rotate_draft_set_angle((std::f32::consts::FRAC_PI_2 * 1000.0) as i32); // 90° CW
        s.rotate_draft_commit();
        assert_eq!(s.pixel(0, 0, 7, 2), Rgba8::WHITE); // (2,8) about (8,8) → (7,2)
        assert!(s.doc.undo(), "the commit is one undo step");
        assert_eq!(s.doc.content_hash(), h0, "a single undo restores the pre-rotation document");
    }

    #[test]
    fn rotate_draft_pi_matches_rotate_layer_2() {
        let build = || {
            let mut s = Session::new(20, 12);
            s.settings.primary = Rgba8::WHITE;
            s.tap(3, 4);
            s.tap(15, 9);
            s
        };
        let mut quarter = build();
        quarter.rotate_layer(2);
        let mut draft = build();
        draft.rotate_draft_begin();
        draft.rotate_draft_set_angle((std::f32::consts::PI * 1000.0) as i32);
        draft.rotate_draft_commit();
        assert_eq!(quarter.doc.content_hash(), draft.doc.content_hash(), "180° draft == quarter-turn ×2");
    }

    #[test]
    fn rotate_draft_cancel_is_nondestructive() {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        s.tap(4, 4);
        let h0 = s.doc.content_hash();
        s.rotate_draft_begin();
        s.rotate_draft_set_angle((std::f32::consts::FRAC_PI_4 * 1000.0) as i32); // 45°
        s.rotate_draft_cancel();
        assert_eq!(s.doc.content_hash(), h0, "cancel leaves the document exactly as it was");
        assert!(s.rotate_draft_rect().is_none(), "no draft remains after cancel");
    }

    #[test]
    fn rotate_draft_frame_scope_rotates_all_layers_one_undo() {
        let mut s = Session::new(8, 8);
        s.settings.primary = Rgba8::WHITE;
        s.tap(0, 0); // layer 0
        s.add_layer();
        s.settings.primary = Rgba8::new(255, 0, 0, 255);
        s.tap(7, 0); // layer 1
        let h0 = s.doc.content_hash();
        s.rotate_draft_begin_frame();
        assert_eq!(s.doc.content_hash(), h0, "the draft is non-destructive while open");
        s.rotate_draft_set_angle((std::f32::consts::PI * 1000.0) as i32); // 180°
        s.rotate_draft_commit();
        assert_eq!(s.pixel(0, 0, 7, 7), Rgba8::WHITE);
        assert_eq!(s.pixel(0, 1, 0, 7), Rgba8::new(255, 0, 0, 255));
        assert!(s.doc.undo(), "the commit is one undo step");
        assert_eq!(s.doc.content_hash(), h0, "a single undo restores both layers");
    }

    #[test]
    fn rotate_draft_frame_scope_dsl_ignores_selection_and_clears_it_on_commit() {
        let mut s = Session::new(8, 8);
        s.settings.primary = Rgba8::WHITE;
        s.tap(0, 0);
        s.add_layer();
        s.settings.primary = Rgba8::new(255, 0, 0, 255);
        s.tap(7, 0);
        s.tool = ToolKind::SelectRect;
        s.stroke_path(&[(1, 1), (3, 3)]);
        assert!(s.doc.selection.is_some());
        let h0 = s.doc.content_hash();

        // Cancel is non-destructive and keeps the selection.
        s.run_script("RotateDraftBeginFrame()\nRotateDraftSetAngle(785)\nRotateDraftCancel()").unwrap();
        assert_eq!(s.doc.content_hash(), h0, "cancel leaves the document exactly as it was");
        assert!(s.doc.selection.is_some(), "cancel keeps the selection");

        // Commit rotates ALL layers (not just the selected pixels) and clears the selection,
        // matching the quarter-turn RotateFrame policy. (3141 mrad ≈ 180°.)
        s.run_script("RotateDraftBeginFrame()\nRotateDraftSetAngle(3141)\nRotateDraftCommit()").unwrap();
        assert_eq!(s.pixel(0, 0, 7, 7), Rgba8::WHITE);
        assert_eq!(s.pixel(0, 1, 0, 7), Rgba8::new(255, 0, 0, 255));
        assert!(s.doc.selection.is_none(), "frame-scope commit clears the selection");
        assert!(s.doc.undo(), "one undo step");
        assert!(s.doc.selection.is_some(), "undo restores the pre-commit selection");
    }

    #[test]
    fn rotate_frame_quarter_turn_matches_frame_scope_draft() {
        let build = || {
            let mut s = Session::new(8, 8);
            s.settings.primary = Rgba8::WHITE;
            s.tap(0, 0);
            s.add_layer();
            s.settings.primary = Rgba8::new(255, 0, 0, 255);
            s.tap(7, 0);
            s
        };
        let mut quarter = build();
        quarter.rotate_frame(1);
        let mut draft = build();
        draft.rotate_draft_begin_frame();
        draft.rotate_draft_set_angle((std::f32::consts::FRAC_PI_2 * 1000.0) as i32);
        draft.rotate_draft_commit();
        assert_eq!(quarter.doc.content_hash(), draft.doc.content_hash(), "90° frame draft == RotateFrame(1)");
    }

    #[test]
    fn rotate_draft_selection_outline_follows_then_commit_rotates_mask() {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        s.tap(2, 4);
        s.tool = ToolKind::SelectRect;
        s.stroke_path(&[(2, 4), (7, 5)]); // 6×2 selection, bbox centre (5,5)
        s.rotate_draft_begin();
        s.rotate_draft_set_angle((std::f32::consts::FRAC_PI_2 * 1000.0) as i32); // 90° CW

        // While the draft is open the marquee (outline) follows the rotated mask, but the committed
        // document selection is still the original.
        let outline = s.outline_mask().expect("an open selection rotate draft outlines the rotated mask");
        let og = s.doc.origin();
        assert!(outline.get(og.x + 4, og.y + 2), "the outline shows the rotated tall bar");
        assert!(!outline.get(og.x + 2, og.y + 4), "the outline no longer shows the original wide bar");
        assert!(SelCanvas(&s).get(2, 4), "the document selection is untouched until commit");

        s.rotate_draft_commit();
        let sel = SelCanvas(&s);
        assert!(sel.get(4, 2) && !sel.get(2, 4), "commit rotates the selection mask with the pixels");
    }

    #[test]
    fn flip_horizontal_whole_layer() {
        let mut s = Session::new(8, 8);
        s.settings.primary = Rgba8::WHITE;
        s.tap(1, 2);
        s.flip_horizontal();
        assert_eq!(s.pixel(0, 0, 6, 2), Rgba8::WHITE); // x → w-1-x
        assert_eq!(s.pixel(0, 0, 1, 2), Rgba8::TRANSPARENT);
    }

    #[test]
    fn flip_selection_mirrors_pixels_within_bbox_only() {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        s.tap(4, 4); // inside the selection
        s.tap(1, 1); // outside the selection
        s.tool = ToolKind::SelectRect;
        s.stroke_path(&[(4, 4), (7, 7)]); // 4×4 selection, bbox x∈[4,7]
        let h_before = s.doc.content_hash();
        s.flip_horizontal(); // mirror within the bbox: local i=0 → x=7
        assert_eq!(s.pixel(0, 0, 7, 4), Rgba8::WHITE);
        assert_eq!(s.pixel(0, 0, 4, 4), Rgba8::TRANSPARENT);
        assert_eq!(s.pixel(0, 0, 1, 1), Rgba8::WHITE, "pixels outside the selection are untouched");
        assert!(s.doc.undo(), "the flip is one undo step");
        assert_eq!(s.doc.content_hash(), h_before);
    }

    #[test]
    fn flip_document_flips_all_layers_and_selection() {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        s.tap(1, 2); // layer 0
        s.add_layer();
        s.tap(3, 4); // layer 1 (now active)
        s.tool = ToolKind::SelectRect;
        s.stroke_path(&[(0, 0), (3, 3)]); // a 4×4 selection at the top-left
        let before = s.doc.content_hash();
        s.flip_document(true); // canvas-wide horizontal flip
        assert_eq!(s.size(), (16, 16), "a canvas flip never resizes");
        assert_eq!(s.pixel(0, 0, 14, 2), Rgba8::WHITE, "layer 0 mirrored: (1,2) → (14,2)");
        assert_eq!(s.pixel(0, 1, 12, 4), Rgba8::WHITE, "layer 1 mirrored too: (3,4) → (12,4)");
        assert_eq!(s.pixel(0, 0, 1, 2), Rgba8::TRANSPARENT);
        let sel = SelCanvas(&s);
        assert!(sel.get(15, 0) && sel.get(12, 3), "the mask flipped to the top-right");
        assert!(!sel.get(0, 0));
        assert!(s.doc.undo(), "the canvas flip is one undo step");
        assert_eq!(s.doc.content_hash(), before);
    }

    #[test]
    fn flip_selection_mirrors_an_asymmetric_mask() {
        let mut s = Session::new(16, 16);
        s.tool = ToolKind::SelectRect;
        s.stroke_path(&[(2, 4), (3, 5)]); // a 2×2 block at the left
        s.selection_mode = CombineMode::Add;
        s.stroke_path(&[(6, 4), (6, 4)]); // add a lone cell at the right → bbox x∈[2,6] (w=5)
        s.flip_horizontal(); // within the bbox each local i maps to (4 - i)
        let sel = SelCanvas(&s);
        assert!(sel.get(6, 4) && sel.get(5, 4) && sel.get(2, 4), "left/right cells mirrored");
        assert!(sel.get(6, 5) && sel.get(5, 5), "the second row mirrored too");
        assert!(!sel.get(3, 4), "the original asymmetric cell is cleared by the mirror");
    }

    #[test]
    fn multi_layer_nudge_moves_together() {
        let mut s = Session::new(16, 16);
        // layer 0: pixel at (3,3); layer 1: pixel at (5,5)
        s.settings.primary = Rgba8::WHITE;
        s.tap(3, 3);
        s.add_layer();
        s.tap(5, 5);
        s.set_active_layers(&[0, 1]);
        s.nudge_layers(2, 0);
        assert_eq!(s.pixel(0, 0, 5, 3), Rgba8::WHITE); // layer 0 moved +2x
        assert_eq!(s.pixel(0, 1, 7, 5), Rgba8::WHITE); // layer 1 moved +2x
        assert_eq!(s.pixel(0, 0, 3, 3), Rgba8::TRANSPARENT);
        assert!(s.doc.undo()); // one undoable frame edit
        assert_eq!(s.pixel(0, 0, 3, 3), Rgba8::WHITE);
    }

    #[test]
    fn set_move_group_keeps_active_layer_put() {
        let mut s = Session::new(16, 16);
        s.add_layer();
        s.add_layer(); // layers 0,1,2
        s.set_active_layer(2);
        assert_eq!(s.doc.active_frame().active_layer, 2);
        s.set_move_group(&[0, 1]); // group two other layers
        assert_eq!(s.doc.active_frame().active_layer, 2); // active stays put
        assert_eq!(s.layer_sel, vec![0, 1]); // but the move-group is those two
    }

    #[test]
    fn rename_layer_via_dsl_and_undo() {
        let mut s = Session::new(16, 16);
        // DSL: index, then free-text name (which may itself contain commas).
        s.run_script("RenameLayer(0, Sky, dawn)").unwrap();
        assert_eq!(s.doc.active_frame().layers[0].name, "Sky, dawn");
        // renaming is undoable (the name is part of frame content)
        assert!(s.doc.undo());
        assert_eq!(s.doc.active_frame().layers[0].name, "Layer 1");
    }

    #[test]
    fn rename_layer_ignores_out_of_range_index() {
        let mut s = Session::new(16, 16);
        s.rename_layer(7, "nope");
        assert_eq!(s.doc.active_frame().layers[0].name, "Layer 1");
        assert!(!s.doc.undo()); // nothing recorded
    }

    #[test]
    fn brush_spacing_leaves_gaps_between_stamps() {
        // A 1px brush dragged straight across, with spacing far larger than the brush, should lay
        // discrete dots — not a solid line.
        let mut s = Session::new(32, 1);
        s.settings.primary = Rgba8::WHITE;
        s.settings.brush_size = 1;
        s.tool = ToolKind::Brush;
        s.settings.spacing = 500; // step = 5px (500% of size 1)
        s.pointer_down(0, 0); // first stamp at x=0
        s.pointer_move(31, 0);
        s.pointer_up();
        // stamps at x = 0, 5, 10, 15, 20, 25, 30 …
        assert_eq!(s.pixel(0, 0, 0, 0), Rgba8::WHITE);
        assert_eq!(s.pixel(0, 0, 5, 0), Rgba8::WHITE);
        assert_eq!(s.pixel(0, 0, 10, 0), Rgba8::WHITE);
        // …and gaps between them
        assert_eq!(s.pixel(0, 0, 2, 0), Rgba8::TRANSPARENT);
        assert_eq!(s.pixel(0, 0, 7, 0), Rgba8::TRANSPARENT);
    }

    #[test]
    fn brush_spacing_is_even_across_chopped_segments() {
        // The same straight drag delivered as many tiny moves must produce the same evenly spaced
        // dots as one big move (the accumulator carries across events).
        let stamps = |chop: bool| {
            let mut s = Session::new(32, 1);
            s.settings.primary = Rgba8::WHITE;
            s.settings.brush_size = 1;
            s.tool = ToolKind::Brush;
            s.settings.spacing = 400; // step = 4px
            s.pointer_down(0, 0);
            if chop {
                for x in 1..=31 {
                    s.pointer_move(x, 0);
                }
            } else {
                s.pointer_move(31, 0);
            }
            s.pointer_up();
            (0..32).filter(|&x| s.pixel(0, 0, x, 0) == Rgba8::WHITE).collect::<Vec<_>>()
        };
        assert_eq!(stamps(true), stamps(false));
        assert_eq!(stamps(false), vec![0, 4, 8, 12, 16, 20, 24, 28]);
    }

    #[test]
    fn dense_spacing_paints_a_solid_line() {
        // Tight spacing on a 1px brush fills every pixel (no regression vs. continuous strokes).
        let mut s = Session::new(16, 1);
        s.settings.primary = Rgba8::WHITE;
        s.settings.brush_size = 1;
        s.tool = ToolKind::Brush;
        s.settings.spacing = 25; // step clamps to 1px for size 1
        s.pointer_down(0, 0);
        s.pointer_move(15, 0);
        s.pointer_up();
        for x in 0..16 {
            assert_eq!(s.pixel(0, 0, x, 0), Rgba8::WHITE, "x={}", x);
        }
    }

    #[test]
    fn dodge_spacing_leaves_gaps_between_stamps() {
        // Dodge honours the spacing setting just like the brush: dragged across a solid grey row
        // with a step far larger than the brush, it lightens discrete dots and leaves the gaps.
        let mut s = Session::new(32, 1);
        s.settings.brush_size = 1;
        // Fill the row with mid-grey so there is something to lighten.
        s.settings.primary = Rgba8::rgb(100, 100, 100);
        s.tool = ToolKind::Pencil;
        s.pointer_down(0, 0);
        s.pointer_move(31, 0);
        s.pointer_up();
        // Dodge with a 5px step (500% of a 1px brush).
        s.tool = ToolKind::Dodge;
        s.settings.intensity = 255;
        s.settings.spacing = 500;
        s.pointer_down(0, 0); // first stamp at x=0
        s.pointer_move(31, 0);
        s.pointer_up();
        // Lightened at the spaced stamps…
        assert!(s.pixel(0, 0, 0, 0).r > 100, "x=0 lightened");
        assert!(s.pixel(0, 0, 5, 0).r > 100, "x=5 lightened");
        assert!(s.pixel(0, 0, 10, 0).r > 100, "x=10 lightened");
        // …untouched in the gaps between them.
        assert_eq!(s.pixel(0, 0, 2, 0).r, 100, "x=2 untouched");
        assert_eq!(s.pixel(0, 0, 7, 0).r, 100, "x=7 untouched");
    }

    #[test]
    fn shape_rotation_renders_a_rotated_figure() {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        s.settings.shape_fill = true;
        s.tool = ToolKind::Rectangle;
        // An 8-wide × 2-tall rect rotated 90° → a 2-wide × 8-tall bar centred at (8,6). The corners
        // passed are the already-rotated ones (as the shell sends them).
        s.shape_set(9, 2, 7, 10);
        s.set_shape_rotation(1571); // ≈ 90° (π/2) in milliradians
        s.shape_commit();
        assert_eq!(s.pixel(0, 0, 8, 6), Rgba8::WHITE); // centre
        assert_eq!(s.pixel(0, 0, 8, 4), Rgba8::WHITE); // up the (now) long axis
        assert_eq!(s.pixel(0, 0, 8, 8), Rgba8::WHITE);
        assert_eq!(s.pixel(0, 0, 12, 6), Rgba8::TRANSPARENT); // off the narrow axis
        assert!(s.doc.undo());
    }

    #[test]
    fn add_frame_at_inserts_right_of_the_given_frame() {
        let mut s = Session::new(8, 8);
        s.add_frame(); // 2 frames (0,1)
        s.add_frame(); // 3 frames (0,1,2)
        let id1 = s.doc.frames[1].id;
        s.add_frame_at(1); // insert a blank frame at index 1 (right of frame 0)
        assert_eq!(s.doc.frames.len(), 4);
        assert_eq!(s.doc.active_frame, 1, "the new frame becomes active");
        assert_eq!(s.doc.frames[2].id, id1, "the old frame 1 shifted right to index 2");
        assert!(s.doc.undo(), "one undo removes the inserted frame");
        assert_eq!(s.doc.frames.len(), 3);
    }

    #[test]
    fn play_starts_from_the_active_frame() {
        let mut s = Session::new(8, 8);
        s.add_frame(); // 2 frames
        s.add_frame(); // 3 frames (0,1,2)
        s.set_active_frame(2);
        s.play();
        assert_eq!(s.current_play_frame(), 2, "playback begins at the active frame, not frame 0");
        // Advancing past the last frame wraps back to the start, so every frame is still reached.
        let total: u64 = s.doc.frames.iter().map(|f| f.duration_us as u64).sum();
        s.advance_clock_ms(total / 1000); // one full loop forward
        assert_eq!(s.current_play_frame(), 2, "a full loop returns to the start frame");
    }

    #[test]
    fn add_layer_at_inserts_at_the_given_index() {
        let mut s = Session::new(8, 8);
        s.add_layer(); // 2 layers (0,1)
        let bottom = s.doc.active_frame().layers[0].id;
        s.add_layer_at(1); // insert above layer 0
        let f = s.doc.active_frame();
        assert_eq!(f.layers.len(), 3);
        assert_eq!(f.active_layer, 1, "the new layer becomes active");
        assert_eq!(f.layers[0].id, bottom, "layer 0 stays at the bottom");
        assert!(s.doc.undo());
    }

    #[test]
    fn triangle_tip_skews_the_apex_to_a_right_triangle() {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        s.settings.shape_fill = false;
        s.settings.line_width = 1;
        s.tool = ToolKind::Triangle;
        // Box corners (2,2)-(12,12): apex at top edge (y=2). tip=+1 → apex over the right base
        // corner (x≈12), forming a right triangle whose right edge is the vertical line x=12.
        s.shape_set(2, 2, 12, 12);
        s.set_triangle_tip(1000);
        s.shape_commit();
        // The vertical right edge is drawn down the right side…
        assert_eq!(s.pixel(0, 0, 12, 2), Rgba8::WHITE, "apex at top-right");
        assert_eq!(s.pixel(0, 0, 12, 7), Rgba8::WHITE, "right edge is vertical");
        assert_eq!(s.pixel(0, 0, 12, 12), Rgba8::WHITE, "bottom-right corner");
        // …and the top edge is NOT centred above the base any more (top-left has no apex).
        assert_eq!(s.pixel(0, 0, 7, 2), Rgba8::TRANSPARENT, "no centred apex");
        assert!(s.doc.undo());
    }

    #[test]
    fn shape_draft_endpoints_may_leave_canvas_and_crop() {
        let mut s = Session::new(8, 8);
        s.settings.primary = Rgba8::rgb(0, 200, 0);
        s.settings.shape_fill = true;
        s.tool = ToolKind::Rectangle;
        // A filled rect from (2,2) running off the right/bottom edges.
        s.shape_set(2, 2, 20, 20);
        let (_, b) = s.shape_draft().unwrap();
        assert!(b.x > 7 && b.y > 7, "endpoint is kept off-canvas (not capped to the edge): {b:?}");
        s.shape_commit();
        // The on-canvas portion fills; the rest is cropped (no panic, no out-of-bounds writes).
        assert_eq!(s.pixel(0, 0, 2, 2), Rgba8::rgb(0, 200, 0));
        assert_eq!(s.pixel(0, 0, 7, 7), Rgba8::rgb(0, 200, 0));
        assert_eq!(s.pixel(0, 0, 1, 1), Rgba8::TRANSPARENT); // left of the rect's a=2
    }

    #[test]
    fn gradient_draft_previews_and_commits() {
        let mut s = Session::new(16, 1);
        s.tool = ToolKind::Gradient;
        s.settings.gradient = tool::GradientSpec {
            kind: GradientKind::Linear,
            stops: vec![Stop::new(Rgba8::rgb(255, 0, 0), 0.0), Stop::new(Rgba8::rgb(0, 0, 255), 1.0)],
            smoothstep: false,
        };
        s.shape_set(0, 0, 15, 0); // horizontal red→blue gradient, drafted but not committed

        // Previews in the display buffer…
        let disp = s.display_bytes(false, false, false);
        assert_eq!(&disp[0..4], &[255, 0, 0, 255], "left end is red in the preview");
        // …but writes no pixels and records no undo yet.
        assert_eq!(s.pixel(0, 0, 0, 0), Rgba8::TRANSPARENT);
        assert!(!s.doc.can_undo());

        s.shape_commit();
        assert_eq!(s.pixel(0, 0, 0, 0), Rgba8::rgb(255, 0, 0));
        assert_eq!(s.pixel(0, 0, 15, 0), Rgba8::rgb(0, 0, 255));
        assert!(s.shape_draft().is_none());
        assert!(s.doc.undo()); // a single undo step
        assert_eq!(s.pixel(0, 0, 0, 0), Rgba8::TRANSPARENT);
    }

    #[test]
    fn shape_draft_previews_but_commits_only_on_demand() {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::rgb(255, 0, 0);
        s.tool = ToolKind::Line;
        s.shape_set(0, 0, 0, 5); // a vertical red line, drafted but not committed

        // It previews in the display buffer…
        let disp = s.display_bytes(false, false, false);
        let idx = (3 * 16) * 4; // pixel (0, 3) lies on the line
        assert_eq!(&disp[idx..idx + 4], &[255, 0, 0, 255], "draft should preview in display");
        // …but writes no pixels and records no undo yet.
        assert_eq!(s.pixel(0, 0, 0, 3), Rgba8::TRANSPARENT);
        assert!(!s.doc.can_undo());
        assert_eq!(s.shape_draft(), Some((Point::new(0, 0), Point::new(0, 5))));

        s.shape_commit(); // now it lands as one undo edit
        assert_eq!(s.pixel(0, 0, 0, 3), Rgba8::rgb(255, 0, 0));
        assert!(s.shape_draft().is_none());
        assert!(s.doc.undo());
        assert_eq!(s.pixel(0, 0, 0, 3), Rgba8::TRANSPARENT);
        assert!(!s.doc.undo()); // exactly one step
    }

    #[test]
    fn shape_draft_endpoint_adjust_then_commit() {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        s.tool = ToolKind::Rectangle;
        s.settings.shape_fill = false;
        s.shape_set(2, 2, 6, 6);
        s.shape_set(4, 4, 6, 6); // re-drag the first endpoint to (4,4)
        s.shape_commit();
        assert_eq!(s.pixel(0, 0, 4, 4), Rgba8::WHITE); // new corner drawn
        assert_eq!(s.pixel(0, 0, 2, 2), Rgba8::TRANSPARENT); // old corner abandoned
    }

    #[test]
    fn line_width_thickens_the_line() {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        s.tool = ToolKind::Line;
        s.settings.line_width = 3; // square stamp radius 1 → 3px-thick line
        s.shape_set(2, 8, 12, 8); // horizontal line at y=8
        s.shape_commit();
        // a 3px-thick horizontal line covers y = 7, 8, 9 at the interior
        assert_eq!(s.pixel(0, 0, 6, 7), Rgba8::WHITE);
        assert_eq!(s.pixel(0, 0, 6, 8), Rgba8::WHITE);
        assert_eq!(s.pixel(0, 0, 6, 9), Rgba8::WHITE);
        assert_eq!(s.pixel(0, 0, 6, 5), Rgba8::TRANSPARENT); // not 5px thick
    }

    #[test]
    fn swap_palette_colors_reorders() {
        let mut s = Session::new(16, 16);
        s.run_script("AddPaletteColor(#FF0000FF); AddPaletteColor(#00FF00FF)").unwrap();
        let before = s.doc.palette().colors.clone();
        s.swap_palette_colors(0, 1);
        let after = s.doc.palette().colors.clone();
        assert_eq!(after[0], before[1]);
        assert_eq!(after[1], before[0]);
        s.swap_palette_colors(0, 99); // out of range → no-op
        assert_eq!(s.doc.palette().colors, after);
    }

    #[test]
    fn shape_cancel_discards_without_drawing() {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        s.tool = ToolKind::Line;
        s.shape_set(0, 0, 5, 5);
        s.shape_cancel();
        assert!(s.shape_draft().is_none());
        assert_eq!(s.pixel(0, 0, 3, 3), Rgba8::TRANSPARENT);
        assert!(!s.doc.can_undo());
        // and the discarded draft no longer previews
        let disp = s.display_bytes(false, false, false);
        let idx = (3 * 16 + 3) * 4;
        assert_eq!(&disp[idx..idx + 4], &[0, 0, 0, 0]);
    }

    #[test]
    fn cancel_stroke_discards_changes_without_undo() {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        s.tap(2, 2); // a committed dot (one undo step)
        s.pointer_down(8, 8); // begin a fresh stroke, stamps (8,8)
        assert_eq!(s.pixel(0, 0, 8, 8), Rgba8::WHITE);
        s.cancel_stroke(); // abort: (8,8) reverted, nothing recorded
        assert_eq!(s.pixel(0, 0, 8, 8), Rgba8::TRANSPARENT);
        assert_eq!(s.pixel(0, 0, 2, 2), Rgba8::WHITE); // earlier dot intact
        assert!(s.doc.undo()); // exactly one undo step — the first dot
        assert_eq!(s.pixel(0, 0, 2, 2), Rgba8::TRANSPARENT);
        assert!(!s.doc.undo()); // the aborted stroke left no undo behind
    }

    #[test]
    fn reentrant_pointer_down_does_not_corrupt_undo() {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        // a malformed sequence: a second pointer_down before the first's pointer_up
        s.pointer_down(3, 3);
        s.pointer_down(9, 9); // must finalize the first stroke, not orphan its baseline
        s.pointer_up();
        assert_eq!(s.pixel(0, 0, 3, 3), Rgba8::WHITE);
        assert_eq!(s.pixel(0, 0, 9, 9), Rgba8::WHITE);
        assert!(s.doc.undo());
        assert_eq!(s.pixel(0, 0, 9, 9), Rgba8::TRANSPARENT);
        assert!(s.doc.undo()); // the first dot is still undoable (not orphaned)
        assert_eq!(s.pixel(0, 0, 3, 3), Rgba8::TRANSPARENT);
    }

    #[test]
    fn select_by_alpha_selects_opaque_pixels() {
        let mut s = Session::new(8, 8);
        s.settings.primary = Rgba8::WHITE;
        s.tool = ToolKind::Pencil;
        s.tap(0, 0); // one opaque pixel (alpha 255); the rest are fully transparent
        // cutoff 0 → select all non-transparent pixels (alpha > 0)
        s.settings.alpha_cutoff = 0;
        s.run_script("SelectByAlpha(Replace)").unwrap();
        let sel = SelCanvas(&s);
        assert!(sel.get(0, 0), "the opaque pixel IS selected at cutoff 0");
        assert!(!sel.get(3, 3), "a transparent pixel is NOT selected");
        // A translucent pixel (alpha 128) is selected only while the cutoff is below 128.
        s.settings.primary = Rgba8::new(255, 0, 0, 128);
        s.tap(1, 1);
        s.settings.alpha_cutoff = 128;
        s.run_script("SelectByAlpha(Replace)").unwrap();
        let sel = SelCanvas(&s);
        assert!(!sel.get(1, 1), "alpha 128 is not > cutoff 128 → not selected");
        assert!(sel.get(0, 0), "alpha 255 > cutoff 128 → still selected");
    }

    #[test]
    fn move_tool_moves_layer_when_no_selection_and_pixels_when_selected() {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        s.tool = ToolKind::Pencil;
        s.tap(2, 2);
        s.tap(8, 8);
        s.tool = ToolKind::Move;
        // No selection → drag moves the whole layer by (+3,+3).
        s.pointer_down(0, 0);
        s.pointer_move(3, 3);
        s.pointer_up();
        assert_eq!(s.pixel(0, 0, 5, 5), Rgba8::WHITE); // 2,2 → 5,5
        assert_eq!(s.pixel(0, 0, 11, 11), Rgba8::WHITE); // 8,8 → 11,11
        // Now select just the pixel at (5,5) and drag → only that pixel moves.
        s.tool = ToolKind::SelectRect;
        s.pointer_down(5, 5);
        s.pointer_up(); // 1px selection at (5,5)
        s.tool = ToolKind::Move;
        s.pointer_down(5, 5);
        s.pointer_move(6, 5); // move selected pixel right by 1
        s.pointer_up();
        assert_eq!(s.pixel(0, 0, 6, 5), Rgba8::WHITE); // selected pixel moved
        assert_eq!(s.pixel(0, 0, 5, 5), Rgba8::TRANSPARENT); // its origin cleared
        assert_eq!(s.pixel(0, 0, 11, 11), Rgba8::WHITE); // the other pixel stayed
    }

    #[test]
    fn wrap_mode_wraps_layer_pixels_around_edges() {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        s.tap(1, 1); // opaque pixel near the top-left
        s.tool = ToolKind::Move; // no selection → layer move
        s.set_active_layer(0);
        s.settings.wrap = true;
        // drag left-and-up by 3 → (1,1) would go to (-2,-2); with wrap it lands at (14,14)
        s.pointer_down(8, 8);
        s.pointer_move(5, 5);
        s.pointer_up();
        assert_eq!(s.pixel(0, 0, 14, 14), Rgba8::WHITE, "pixel wrapped to the far corner");
        assert_eq!(s.pixel(0, 0, 1, 1), Rgba8::TRANSPARENT, "origin cleared");
        // nothing was lost: undo restores the original
        assert!(s.doc.undo());
        assert_eq!(s.pixel(0, 0, 1, 1), Rgba8::WHITE);
        assert_eq!(s.pixel(0, 0, 14, 14), Rgba8::TRANSPARENT);
    }

    #[test]
    fn wrap_mode_wraps_selected_pixels_and_mask() {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        s.tool = ToolKind::Pencil;
        s.tap(1, 1);
        // select just that pixel
        s.tool = ToolKind::SelectRect;
        s.pointer_down(1, 1);
        s.pointer_up();
        // move the selection left-and-up by 3 with wrap → (1,1) → (14,14)
        s.tool = ToolKind::Move;
        s.settings.wrap = true;
        s.pointer_down(8, 8);
        s.pointer_move(5, 5);
        s.pointer_up();
        assert_eq!(s.pixel(0, 0, 14, 14), Rgba8::WHITE, "selected pixel wrapped");
        assert_eq!(s.pixel(0, 0, 1, 1), Rgba8::TRANSPARENT, "origin cleared");
        let sel = SelCanvas(&s);
        assert!(sel.get(14, 14), "the selection followed the pixel");
        assert!(!sel.get(1, 1));
    }

    #[test]
    fn protect_pixels_clamps_layer_move_on_canvas() {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        s.tap(0, 0); // opaque pixel at the top-left corner of layer 0
        s.settings.protect_pixels = true;
        s.tool = ToolKind::Move; // no selection → layer move
        s.set_active_layer(0);
        // try to drag up-and-left by 5 → would push the corner pixel off-canvas; must be clamped
        s.pointer_down(8, 8);
        s.pointer_move(3, 3);
        s.pointer_up();
        assert_eq!(s.pixel(0, 0, 0, 0), Rgba8::WHITE); // stayed put
        // moving right by 3 is legal and applies
        s.pointer_down(0, 0);
        s.pointer_move(3, 0);
        s.pointer_up();
        assert_eq!(s.pixel(0, 0, 3, 0), Rgba8::WHITE);
        assert_eq!(s.pixel(0, 0, 0, 0), Rgba8::TRANSPARENT);
    }

    #[test]
    fn palette_management() {
        let mut s = Session::new(8, 8);
        let n0 = s.doc.palette().colors.len();
        s.run_script("AddPaletteColor(#112233FF); DuplicatePaletteColor(0); NewPalette(Greens); AddPaletteColor(#00FF00FF)").unwrap();
        assert_eq!(s.doc.palettes.len(), 2);
        assert_eq!(s.doc.active_palette, 1);
        assert_eq!(s.doc.palette().colors.len(), 1);
        s.run_script("SetActivePalette(0)").unwrap();
        assert_eq!(s.doc.palette().colors.len(), n0 + 2);
    }

    #[test]
    fn save_load_roundtrip_via_session() {
        let mut s = Session::new(32, 32);
        s.settings.primary = Rgba8::rgb(10, 20, 30);
        s.tap(5, 5);
        s.add_frame();
        let bytes = s.save_bytes();
        let mut s2 = Session::new(8, 8);
        s2.load_bytes(&bytes).unwrap();
        assert_eq!(s2.doc.content_hash(), s.doc.content_hash());
    }

    // ---- selection: undoable + serialized (SPEC §12) ----

    #[test]
    fn marquee_selection_is_undoable() {
        let mut s = Session::new(16, 16);
        s.run_script("SelectTool(SelectRect); Stroke([(2,2),(5,5)])").unwrap();
        assert_eq!(s.bounds_of_selection(), Some(IRect::new(2, 2, 4, 4)));
        assert!(s.doc.can_undo(), "a marquee is now its own undo step");
        assert!(s.doc.undo());
        assert_eq!(s.bounds_of_selection(), None, "undo clears the selection back to none");
        assert!(s.doc.redo());
        assert_eq!(s.bounds_of_selection(), Some(IRect::new(2, 2, 4, 4)));
    }

    #[test]
    fn select_none_is_undoable() {
        let mut s = Session::new(16, 16);
        s.run_script("SelectTool(SelectRect); Stroke([(2,2),(5,5)]); SelectNone()").unwrap();
        assert_eq!(s.bounds_of_selection(), None);
        assert!(s.doc.undo(), "undo the SelectNone");
        assert_eq!(s.bounds_of_selection(), Some(IRect::new(2, 2, 4, 4)), "the lost selection comes back");
    }

    #[test]
    fn subtract_that_empties_the_selection_clears_it_entirely() {
        let mut s = Session::new(16, 16);
        // Replace-select a 4×4 rect, then subtract a larger rect that covers all of it.
        s.run_script("SelectTool(SelectRect); Stroke([(4,4),(7,7)])").unwrap();
        assert_eq!(s.bounds_of_selection(), Some(IRect::new(4, 4, 4, 4)));
        s.run_script("SetSelectionMode(Subtract); Stroke([(2,2),(10,10)])").unwrap();
        assert!(s.doc.selection.is_none(), "zero pixels selected == no selection, not an empty mask");
        // With no selection the whole canvas is editable again (an empty mask blocked every edit).
        s.tool = ToolKind::Pencil;
        s.settings.primary = Rgba8::WHITE;
        s.tap(12, 12); // outside the original marquee
        assert_eq!(s.pixel(0, 0, 12, 12), Rgba8::WHITE);
        // The clear is still one undoable step: undo the tap, then the subtract → the rect returns.
        assert!(s.doc.undo() && s.doc.undo());
        assert_eq!(s.bounds_of_selection(), Some(IRect::new(4, 4, 4, 4)));
    }

    #[test]
    fn invert_of_select_all_is_no_selection() {
        let mut s = Session::new(8, 8);
        s.select_all();
        s.invert_selection();
        assert!(s.doc.selection.is_none(), "inverting a full selection leaves nothing == no selection");
    }

    #[test]
    fn move_selection_mask_is_undoable() {
        let mut s = Session::new(16, 16);
        s.run_script("SelectTool(SelectRect); Stroke([(2,2),(3,3)])").unwrap();
        s.move_selection(2, 2);
        assert_eq!(s.bounds_of_selection(), Some(IRect::new(4, 4, 2, 2)));
        assert!(s.doc.undo());
        assert_eq!(s.bounds_of_selection(), Some(IRect::new(2, 2, 2, 2)), "mask move undone");
        assert!(s.doc.redo());
        assert_eq!(s.bounds_of_selection(), Some(IRect::new(4, 4, 2, 2)));
    }

    #[test]
    fn coalesced_selection_move_is_a_single_undo_step() {
        // One drag (begin → many small moves → commit) must collapse to ONE undo step, not many.
        let mut s = Session::new(16, 16);
        s.run_script("SelectTool(SelectRect); Stroke([(2,2),(3,3)])").unwrap();
        assert_eq!(s.bounds_of_selection(), Some(IRect::new(2, 2, 2, 2)));
        s.move_selection_begin();
        for _ in 0..5 {
            s.move_selection(1, 0); // five 1px steps, as a finger drag would emit
        }
        s.move_selection_commit();
        assert_eq!(s.bounds_of_selection(), Some(IRect::new(7, 2, 2, 2)), "moved +5 in x");
        // A SINGLE undo returns the mask to where the drag began (not 5 undos).
        assert!(s.doc.undo());
        assert_eq!(s.bounds_of_selection(), Some(IRect::new(2, 2, 2, 2)), "one undo reverts the whole drag");
        // That was the only move step beyond the marquee itself: the next undo removes the marquee.
        assert!(s.doc.undo());
        assert_eq!(s.bounds_of_selection(), None, "no leftover per-step move records");
    }

    #[test]
    fn coalesced_selection_move_with_no_movement_records_nothing() {
        let mut s = Session::new(16, 16);
        s.run_script("SelectTool(SelectRect); Stroke([(2,2),(3,3)])").unwrap();
        s.move_selection_begin();
        s.move_selection_commit(); // a tap: began and ended with no net move
        assert_eq!(s.bounds_of_selection(), Some(IRect::new(2, 2, 2, 2)));
        assert!(s.doc.undo(), "only the marquee step exists");
        assert_eq!(s.bounds_of_selection(), None);
        assert!(!s.doc.undo(), "no spurious move step was recorded");
    }

    #[test]
    fn move_tool_undo_restores_pixels_and_mask_together() {
        // The bug this work fixes: undoing a Move must move BOTH the pixels and the selection back.
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        s.tool = ToolKind::Pencil;
        s.tap(2, 2);
        // select just that pixel
        s.tool = ToolKind::SelectRect;
        s.pointer_down(2, 2);
        s.pointer_up();
        // drag the selected pixel by (+3,+3)
        s.tool = ToolKind::Move;
        s.pointer_down(2, 2);
        s.pointer_move(5, 5);
        s.pointer_up();
        assert_eq!(s.pixel(0, 0, 5, 5), Rgba8::WHITE);
        assert_eq!(s.pixel(0, 0, 2, 2), Rgba8::TRANSPARENT);
        assert!(SelCanvas(&s).get(5, 5), "mask followed the pixel");
        // ONE undo restores both the pixel AND the selection mask to the origin.
        assert!(s.doc.undo());
        assert_eq!(s.pixel(0, 0, 2, 2), Rgba8::WHITE, "pixel moved back");
        assert_eq!(s.pixel(0, 0, 5, 5), Rgba8::TRANSPARENT);
        let sel = SelCanvas(&s);
        assert!(sel.get(2, 2), "the mask moved back with the pixel");
        assert!(!sel.get(5, 5), "the mask is no longer at the moved position");
        // redo re-applies both
        assert!(s.doc.redo());
        assert_eq!(s.pixel(0, 0, 5, 5), Rgba8::WHITE);
        assert!(SelCanvas(&s).get(5, 5));
    }

    #[test]
    fn nudge_selection_undo_restores_pixels_and_mask() {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        s.tool = ToolKind::Pencil;
        s.tap(3, 3);
        s.tool = ToolKind::SelectRect;
        s.pointer_down(3, 3);
        s.pointer_up();
        s.nudge_selection(1, 0); // arrow-key move of the selected pixel
        assert_eq!(s.pixel(0, 0, 4, 3), Rgba8::WHITE);
        assert!(SelCanvas(&s).get(4, 3));
        assert!(s.doc.undo());
        assert_eq!(s.pixel(0, 0, 3, 3), Rgba8::WHITE, "pixel back");
        assert!(SelCanvas(&s).get(3, 3), "mask back");
        assert!(!SelCanvas(&s).get(4, 3));
    }

    #[test]
    fn crop_undo_restores_the_selection() {
        let mut s = Session::new(32, 32);
        s.settings.primary = Rgba8::WHITE;
        s.tap(10, 10);
        s.tool = ToolKind::SelectRect;
        s.stroke_path(&[(8, 8), (15, 15)]);
        s.crop_to_selection();
        assert_eq!(s.size(), (8, 8));
        assert_eq!(s.bounds_of_selection(), None, "crop consumes the selection");
        // undoing the crop restores BOTH the canvas size and the pre-crop selection (correct dims).
        assert!(s.doc.undo());
        assert_eq!(s.size(), (32, 32));
        assert_eq!(s.bounds_of_selection(), Some(IRect::new(8, 8, 8, 8)));
    }

    #[test]
    fn selection_survives_save_load_for_crash_safety() {
        let mut s = Session::new(24, 24);
        s.run_script("SelectTool(SelectRect); Stroke([(3,4),(9,12)])").unwrap();
        let before = s.bounds_of_selection();
        assert!(before.is_some());
        let bytes = s.save_bytes();
        let mut s2 = Session::new(8, 8);
        s2.load_bytes(&bytes).unwrap();
        assert_eq!(s2.bounds_of_selection(), before, "the selection round-trips through .mkpx");
        assert_eq!(s2.doc.selection.as_deref(), s.doc.selection.as_deref());
    }

    #[test]
    fn moving_a_selection_over_empty_pixels_is_still_undoable() {
        // No pixels change (the region is transparent), but the mask moves — it must still be one
        // undoable step, not silently dropped.
        let mut s = Session::new(16, 16);
        s.tool = ToolKind::SelectRect;
        s.pointer_down(2, 2);
        s.pointer_up(); // 1px selection at (2,2) over a transparent pixel
        s.tool = ToolKind::Move;
        s.pointer_down(2, 2);
        s.pointer_move(7, 7);
        s.pointer_up();
        assert!(SelCanvas(&s).get(7, 7), "mask moved");
        assert!(s.doc.undo());
        assert!(SelCanvas(&s).get(2, 2), "mask move undone");
        assert!(!SelCanvas(&s).get(7, 7));
    }

    #[test]
    fn no_selection_survives_save_load_as_none() {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        s.tap(1, 1);
        let bytes = s.save_bytes();
        let mut s2 = Session::new(8, 8);
        s2.load_bytes(&bytes).unwrap();
        assert!(s2.doc.selection.is_none());
    }

    // ---- move draft (drag → relocate → commit) ----

    // A session with one white pixel at (3,3) selected, and NO undo history (set up directly so the
    // draft's recording can be asserted cleanly).
    fn session_with_selected_pixel() -> Session {
        let mut s = Session::new(16, 16);
        let o = s.doc.origin();
        let st = s.doc.storage();
        s.doc.active_frame_mut().active_layer_mut().pixels.set(o.x + 3, o.y + 3, Rgba8::WHITE);
        let mut m = Mask::new(st.w as u32, st.h as u32);
        m.set(o.x + 3, o.y + 3, true); // canvas (3,3) in storage coords
        s.doc.selection = Some(Arc::new(m));
        s.tool = ToolKind::Move;
        assert!(!s.doc.can_undo());
        s
    }

    // The composited move-draft PREVIEW frame's pixel at (x,y) — what the canvas shows mid-draft,
    // without the wash (the wash is added later, in draw_tool_preview). `None` if no draft is open.
    fn preview_pixel(s: &Session, x: i32, y: i32) -> Option<Rgba8> {
        let f = s.move_draft_preview_frame()?;
        Some(render::composite_frame(&f, s.doc.canvas_rect()).get(x, y))
    }

    #[test]
    fn move_draft_is_non_destructive_until_commit() {
        let mut s = session_with_selected_pixel();
        let before = s.doc.content_hash();
        s.move_draft_begin();
        s.move_draft_move(4, 0); // (3,3) → (7,3)
        // The DOCUMENT is untouched: the pixel is still at the origin, nothing at the destination,
        // the content hash is unchanged, and a save would serialize the original (crash/leave safe).
        assert_eq!(s.pixel(0, 0, 3, 3), Rgba8::WHITE, "document pixel stays at the origin");
        assert_eq!(s.pixel(0, 0, 7, 3), Rgba8::TRANSPARENT, "nothing materialized at the destination");
        assert_eq!(s.doc.content_hash(), before, "the document is unchanged during the draft");
        assert!(!s.doc.can_undo(), "the draft records nothing until commit");
        // The PREVIEW (what the canvas shows) and the marquee follow the move, though.
        assert_eq!(preview_pixel(&s, 7, 3), Some(Rgba8::WHITE), "preview shows the move at the destination");
        assert_eq!(preview_pixel(&s, 3, 3), Some(Rgba8::TRANSPARENT), "preview clears the origin");
        let og = s.doc.origin();
        assert!(s.outline_mask().unwrap().get(og.x + 7, og.y + 3), "marquee follows the draft");
        assert!(s.move_draft_rect().is_some());

        s.move_draft_commit();
        assert!(s.move_draft_rect().is_none(), "draft cleared on commit");
        assert!(s.doc.can_undo(), "commit is one undo step");
        // NOW the document reflects the move (pixel + mask).
        assert_eq!(s.pixel(0, 0, 7, 3), Rgba8::WHITE);
        assert_eq!(s.pixel(0, 0, 3, 3), Rgba8::TRANSPARENT);
        assert!(SelCanvas(&s).get(7, 3));
        // one undo restores both pixel and mask; redo re-applies both
        assert!(s.doc.undo());
        assert_eq!(s.pixel(0, 0, 3, 3), Rgba8::WHITE);
        assert!(SelCanvas(&s).get(3, 3));
        assert!(s.doc.redo());
        assert_eq!(s.pixel(0, 0, 7, 3), Rgba8::WHITE);
        assert!(SelCanvas(&s).get(7, 3));
    }

    #[test]
    fn move_draft_cancel_leaves_the_document_untouched() {
        let mut s = session_with_selected_pixel();
        let before = s.doc.content_hash();
        s.move_draft_begin();
        s.move_draft_move(5, 2);
        s.move_draft_cancel();
        assert_eq!(s.pixel(0, 0, 3, 3), Rgba8::WHITE, "origin intact");
        assert_eq!(s.pixel(0, 0, 8, 5), Rgba8::TRANSPARENT);
        assert!(SelCanvas(&s).get(3, 3), "marquee unchanged");
        assert_eq!(s.doc.content_hash(), before, "nothing was materialized");
        assert!(!s.doc.can_undo(), "cancel records nothing");
        assert!(s.move_draft_rect().is_none());
    }

    #[test]
    fn move_draft_save_during_draft_serializes_the_original() {
        // The crux of "only Commit materializes": a save (autosave / crash snapshot) taken mid-draft
        // round-trips to the ORIGINAL document, not the in-progress move.
        let mut s = session_with_selected_pixel();
        let pristine = s.save_bytes();
        s.move_draft_begin();
        s.move_draft_move(4, 0);
        assert_eq!(s.save_bytes(), pristine, "a mid-draft save equals the pre-draft save");
        // And loading such a save yields the un-moved pixel.
        let mut s2 = Session::new(8, 8);
        s2.load_bytes(&s.save_bytes()).unwrap();
        assert_eq!(s2.pixel(0, 0, 3, 3), Rgba8::WHITE);
        assert_eq!(s2.pixel(0, 0, 7, 3), Rgba8::TRANSPARENT);
        assert!(s2.move_draft_rect().is_none(), "no draft survives a load");
    }

    #[test]
    fn move_draft_preview_relocates_cumulatively_without_drift() {
        let mut s = session_with_selected_pixel();
        s.move_draft_begin();
        s.move_draft_move(2, 0);
        s.move_draft_move(2, 0); // total +4 → (7,3)
        assert_eq!(preview_pixel(&s, 7, 3), Some(Rgba8::WHITE));
        assert_eq!(preview_pixel(&s, 5, 3), Some(Rgba8::TRANSPARENT), "intermediate position left no trail");
        s.move_draft_commit();
        assert_eq!(s.pixel(0, 0, 7, 3), Rgba8::WHITE);
        assert_eq!(s.pixel(0, 0, 5, 3), Rgba8::TRANSPARENT);
    }

    #[test]
    fn move_draft_zero_offset_commit_is_a_noop() {
        let mut s = session_with_selected_pixel();
        s.move_draft_begin();
        s.move_draft_commit(); // never moved
        assert!(!s.doc.can_undo(), "a draft that never moved records no undo step");
        assert_eq!(s.pixel(0, 0, 3, 3), Rgba8::WHITE);
    }

    #[test]
    fn move_draft_layer_move_with_no_selection() {
        let mut s = Session::new(16, 16);
        let o = s.doc.origin();
        s.doc.active_frame_mut().active_layer_mut().pixels.set(o.x + 2, o.y + 2, Rgba8::WHITE);
        assert!(s.doc.selection.is_none());
        s.tool = ToolKind::Move;
        s.move_draft_begin(); // no selection → whole-layer move draft
        s.move_draft_move(3, 3);
        // non-destructive: document unchanged, preview shows the move
        assert_eq!(s.pixel(0, 0, 2, 2), Rgba8::WHITE);
        assert_eq!(preview_pixel(&s, 5, 5), Some(Rgba8::WHITE));
        s.move_draft_commit();
        assert_eq!(s.pixel(0, 0, 5, 5), Rgba8::WHITE);
        assert_eq!(s.pixel(0, 0, 2, 2), Rgba8::TRANSPARENT);
        assert!(s.doc.undo(), "one undo step");
        assert_eq!(s.pixel(0, 0, 2, 2), Rgba8::WHITE);
    }

    #[test]
    fn move_draft_runs_via_dsl() {
        let mut s = session_with_selected_pixel();
        s.run_script("MoveDraftBegin(); MoveDraftMove(4,0); MoveDraftCommit()").unwrap();
        assert_eq!(s.pixel(0, 0, 7, 3), Rgba8::WHITE);
        assert!(s.doc.can_undo());
    }

    // ---- off-canvas gutter (SPEC §8, §15) ----

    #[test]
    fn move_preserves_pixels_in_the_gutter_and_recovers_them() {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        s.tap(0, 0); // one white pixel at canvas (0,0)
        s.select_all();
        s.tool = ToolKind::Move;
        s.nudge_selection(-5, 0); // push it 5px off the left edge into the gutter

        // Preserved off-canvas (a negative canvas coord reaches the gutter), gone from the canvas...
        assert_eq!(s.pixel(0, 0, -5, 0), Rgba8::WHITE, "the moved pixel is preserved in the gutter");
        assert_eq!(s.pixel(0, 0, 0, 0), Rgba8::TRANSPARENT, "its old canvas position is now empty");
        // ...and never appears in the exported (canvas-cropped) image.
        assert!(
            s.composite_frame_bytes(0).iter().all(|&b| b == 0),
            "the gutter pixel is excluded from the exported canvas"
        );
        // Nudging back out of the gutter recovers it — no data was lost.
        s.nudge_selection(5, 0);
        assert_eq!(s.pixel(0, 0, 0, 0), Rgba8::WHITE, "moved back out of the gutter intact");
    }

    #[test]
    fn paint_tools_never_leak_into_the_gutter() {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        // A pencil stroke that runs well past the right edge (clamp_pointer allows the gutter range).
        s.run_script("SelectTool(Pencil); Stroke([(10,8),(25,8)])").unwrap();
        assert_eq!(s.pixel(0, 0, 15, 8), Rgba8::WHITE, "the on-canvas part is drawn");
        assert_eq!(s.pixel(0, 0, 18, 8), Rgba8::TRANSPARENT, "nothing spilled into the gutter");
        // Opaque content is confined to the canvas window.
        let o = s.doc.origin();
        let bb = s.doc.active_frame().active_layer().pixels.opaque_bounds().unwrap();
        assert!(bb.x >= o.x && bb.right() <= o.x + 16, "paint stayed inside the canvas");
    }

    #[test]
    fn mkpx_v4_roundtrips_gutter_pixels() {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        s.tap(0, 0);
        s.select_all();
        s.tool = ToolKind::Move;
        s.nudge_selection(-5, 0); // park a pixel in the gutter
        let back = crate::io::load_from_bytes(&crate::io::save_to_bytes(&s.doc)).unwrap();
        let o = back.origin();
        assert_eq!(
            back.active_frame().active_layer().pixels.get(o.x - 5, o.y),
            Rgba8::WHITE,
            "the gutter pixel survives a .mkpx round-trip"
        );
        assert_eq!(back.content_hash(), s.doc.content_hash());
    }

    #[test]
    fn overscan_view_reveals_the_gutter_and_resizes_the_display() {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        s.tap(0, 0);
        s.select_all();
        s.tool = ToolKind::Move;
        s.nudge_selection(-5, 0); // park a pixel in the gutter
        // Normal view: the display is canvas-sized.
        assert_eq!(s.display_size(), (16, 16));
        assert_eq!(s.display_bytes(false, false, false).len(), 16 * 16 * 4);
        // Overscan on: the display is the whole 3×16 storage, and the gutter pixel is within it.
        s.run_script("SetOverscanView(1)").unwrap();
        assert_eq!(s.display_size(), (48, 48));
        let bytes = s.display_bytes(false, false, false);
        assert_eq!(bytes.len(), 48 * 48 * 4);
        let o = s.doc.origin();
        let idx = (((o.y as usize) * 48 + (o.x as usize - 5)) * 4) + 3; // parked pixel's alpha byte
        assert!(bytes[idx] > 0, "the gutter pixel is visible in the overscan display");
    }

    #[test]
    fn selection_reaches_the_gutter_only_under_overscan() {
        let mut s = Session::new(16, 16);
        let o = s.doc.origin();
        // Overscan OFF: a marquee dragged into the left gutter clips to the canvas.
        s.run_script("SelectTool(SelectRect); Stroke([(-5,2),(5,5)])").unwrap();
        {
            let sel = s.doc.selection.as_ref().unwrap();
            assert!(!sel.get(o.x - 5, o.y + 2), "overscan off: the gutter part is not selected");
            assert!(sel.get(o.x, o.y + 2), "overscan off: the on-canvas part is selected");
        }
        // Overscan ON: the same gesture selects into the gutter.
        s.run_script("SetOverscanView(1); SelectNone(); SelectTool(SelectRect); Stroke([(-5,2),(5,5)])")
            .unwrap();
        {
            let sel = s.doc.selection.as_ref().unwrap();
            assert!(sel.get(o.x - 5, o.y + 2), "overscan on: the gutter part IS selected");
        }
    }

    #[test]
    fn flip_preserves_and_mirrors_gutter_pixels() {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        s.tap(0, 0);
        s.select_all();
        s.tool = ToolKind::Move;
        s.nudge_selection(-5, 0); // pixel at canvas (-5, 0) in the left gutter
        s.select_none();
        s.flip_document(true); // horizontal flip mirrors the whole storage
        // canvas x=-5 mirrors to x = 15 - (-5) = ... reflected across the canvas: (w-1 - x) = 15-(-5)=20.
        assert_eq!(s.pixel(0, 0, 20, 0), Rgba8::WHITE, "the gutter pixel mirrored with the artwork");
    }

    // ---- onion skin (loop-wrapped neighbours) ----

    #[test]
    fn onion_skin_wraps_around_the_loop() {
        // 3 frames, one marker pixel each: frame 0 → (0,0), frame 1 → (1,0), frame 2 → (2,0).
        let mut s = Session::new(4, 4);
        s.settings.primary = Rgba8::WHITE;
        s.tap(0, 0);
        s.run_script("AddFrame()").unwrap();
        s.tap(1, 0);
        s.run_script("AddFrame()").unwrap();
        s.tap(2, 0);
        let at = |px: &[u8], x: usize, y: usize| {
            let i = (y * 4 + x) * 4;
            [px[i], px[i + 1], px[i + 2], px[i + 3]]
        };

        // The middle frame is the undisputed baseline: prev ghost at (0,0), next ghost at (2,0).
        s.run_script("SetActiveFrame(1)").unwrap();
        let px = s.display_bytes(true, false, false);
        let prev_ghost = at(&px, 0, 0);
        let next_ghost = at(&px, 2, 0);
        assert_ne!(prev_ghost, [0, 0, 0, 0]);
        assert_ne!(next_ghost, [0, 0, 0, 0]);
        assert_ne!(prev_ghost, next_ghost, "prev and next carry distinct tints");

        // First frame: "previous" wraps to the LAST frame's marker.
        s.run_script("SetActiveFrame(0)").unwrap();
        let px = s.display_bytes(true, false, false);
        assert_eq!(at(&px, 2, 0), prev_ghost, "frame 0's prev ghost is the last frame");
        assert_eq!(at(&px, 1, 0), next_ghost);

        // Last frame: "next" wraps to the FIRST frame's marker.
        s.run_script("SetActiveFrame(2)").unwrap();
        let px = s.display_bytes(true, false, false);
        assert_eq!(at(&px, 0, 0), next_ghost, "the last frame's next ghost is frame 0");
        assert_eq!(at(&px, 1, 0), prev_ghost);

        // Two frames: the other frame is prev AND next — it is ghosted ONCE (prev tint),
        // not double-blitted with both tints.
        s.run_script("RemoveFrame(2); SetActiveFrame(0)").unwrap();
        let px = s.display_bytes(true, false, false);
        assert_eq!(at(&px, 1, 0), prev_ghost, "two frames: a single prev-tinted ghost");

        // One frame: no neighbour, so onion must not ghost the frame onto itself.
        s.run_script("RemoveFrame(1)").unwrap();
        assert_eq!(s.display_bytes(true, false, false), s.display_bytes(false, false, false));
    }
}
