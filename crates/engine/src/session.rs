//! `Session` — the single stateful entry point driven by both the CLI harness and the
//! Flutter shell (SPEC §9, §19). Owns the document + editor state, runs the action-script
//! DSL, routes pointer input to tools, wraps each change in one undo record, and exposes
//! probes.

use crate::buffer::RgbaBuffer;
use crate::color::Rgba8;
use crate::document::{Document, Frame, LoopMode};
use crate::geom::{IRect, Point};
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
    clipboard: Option<(RgbaBuffer, Point)>,
    // A pending paste: the clipboard pixels floating at a top-left position, previewed semi-
    // transparently and movable until committed (Copy & Paste tool). Editor state, not undoable
    // until commit.
    paste_draft: Option<(RgbaBuffer, Point)>,
    rng: SeededRng,
    clock: VirtualClock,
    playing: bool,
    stroke: Option<Stroke>,
    /// Distance (canvas px) travelled since the last spaced Brush/Airbrush stamp in the current
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
        self.doc.selection = new.map(Arc::new);
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
        let (w, h) = (self.doc.size.w as u32, self.doc.size.h as u32);
        let mut m = self.selection_clone().unwrap_or_else(|| Mask::new(w, h));
        m.combine(shape, mode);
        self.set_selection(Some(m));
    }

    // ---- read API used by FFI / tests / probes ----

    pub fn size(&self) -> (u16, u16) {
        (self.doc.size.w, self.doc.size.h)
    }

    pub fn composite_active_bytes(&self) -> Vec<u8> {
        render::composite_active(&self.doc).to_rgba_bytes()
    }

    pub fn composite_frame_bytes(&self, frame: usize) -> Vec<u8> {
        let f = &self.doc.frames[frame.min(self.doc.frames.len() - 1)];
        render::composite_frame(f, self.doc.size.w as u32, self.doc.size.h as u32).to_rgba_bytes()
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
        let flat = render::composite_frame(&self.doc.frames[i], w, h);
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
        let (tw, th) = (tw.max(1), th.max(1));
        let mut out = vec![0u8; (tw * th * 4) as usize];
        for ty in 0..th {
            for tx in 0..tw {
                let sx = (tx * w / tw) as i32;
                let sy = (ty * h / th) as i32;
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
        let ov = render::Overlays {
            onion_prev: if onion && af > 0 { Some(&self.doc.frames[af - 1]) } else { None },
            onion_next: if onion && af + 1 < self.doc.frames.len() {
                Some(&self.doc.frames[af + 1])
            } else {
                None
            },
            grid,
            checker_bg: checker,
            // The reticle is now drawn by the UI as a thin, screen-space, marching-ants overlay
            // (not baked into canvas pixels), so the engine no longer renders it.
            cursor: None,
        };
        let mut buf = render::render_display(&self.doc, self.doc.active_frame(), &ov);
        self.draw_tool_preview(&mut buf);
        buf.to_rgba_bytes()
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
        let (w, h) = (self.doc.size.w as u32, self.doc.size.h as u32);
        // Sort stops once (not per pixel); a selection bounds the fill to its bbox. [audit F-14/F-15]
        let mut stops = spec.stops.clone();
        stops.sort_by(|p, q| p.t.total_cmp(&q.t));
        let (x0, y0, x1, y1) = match self.doc.selection.as_ref().and_then(|m| m.bounds()) {
            Some(bb) => (
                bb.x.max(0),
                bb.y.max(0),
                (bb.x + bb.w as i32).min(w as i32),
                (bb.y + bb.h as i32).min(h as i32),
            ),
            None => (0, 0, w as i32, h as i32),
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
                            buf.blit_wrapped(float, bb.x + dx, bb.y + dy);
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
        let (w, h) = (self.doc.size.w as u32, self.doc.size.h as u32);
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
            if let Some(shape) = shape {
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
        let (w, h) = (self.doc.size.w as usize, self.doc.size.h as usize);
        let n = (w * h).min(out.len());
        for (i, slot) in out.iter_mut().enumerate().take(n) {
            let x = (i % w) as i32;
            let y = (i / w) as i32;
            *slot = m.get(x, y) as u8;
        }
        n
    }

    /// Bounds-safe pixel read for FFI/CLI probes: clamps a stale frame/layer index (and
    /// `RgbaBuffer::get` already returns transparent out of bounds), so a bad index can never panic
    /// across the boundary. [audit F-28]
    pub fn pixel(&self, f: usize, l: usize, x: i32, y: i32) -> Rgba8 {
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
        let paste = match self.paste_draft_rect() {
            Some(r) => format!("[{},{},{},{}]", r.x, r.y, r.w, r.h),
            None => "null".to_string(),
        };
        let extra = format!(",\"has_clipboard\":{},\"paste\":{}", self.clipboard.is_some(), paste);
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
        // The single Move tool moves the selected pixels when there's a selection, else the layer.
        let has_sel = self.doc.selection.as_ref().and_then(|s| s.bounds()).is_some();
        // Paint-immediately tools.
        if self.active_editable() {
            match self.tool {
                ToolKind::Pencil => self.stamp_active(p, PaintMode::Replace, self.settings.primary),
                ToolKind::Brush => self.stamp_active(p, PaintMode::Over, self.settings.primary),
                ToolKind::Eraser => self.stamp_active(p, PaintMode::Erase, Rgba8::TRANSPARENT),
                ToolKind::Airbrush => self.airbrush_active(p),
                ToolKind::Dodge => self.dodge_burn_active(p, self.dodge_dv(true)),
                ToolKind::Burn => self.dodge_burn_active(p, self.dodge_dv(false)),
                ToolKind::Bucket => {
                    let color = self.settings.primary;
                    let (th, cont) = (self.settings.threshold, self.settings.contiguous);
                    let sel = self.selection_clone();
                    // "All layers": decide the region from the composited frame (computed before the
                    // mutable layer borrow), while the fill still lands in the active layer only.
                    let reference = self
                        .settings
                        .fill_all_layers
                        .then(|| render::composite_active(&self.doc));
                    let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
                    tool::flood_fill(buf, reference.as_ref(), sel.as_ref(), p, color, th, cont, PaintMode::Replace);
                }
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
        self.stroke = Some(Stroke { before, start: p, last: p, path: vec![p], floating });
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
            for idx in 0..self.move_layers.len() {
                let li = self.move_layers[idx].0;
                if li < self.doc.frames[fi].layers.len() {
                    let snap = &self.move_layers[idx].1;
                    let buf = &mut self.doc.frames[fi].layers[li].pixels;
                    buf.clear();
                    // Wrap: pixels leaving one edge re-enter the opposite one. Regular: clip them.
                    if wrap {
                        buf.blit_wrapped(snap, dx, dy);
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
                ToolKind::Pencil => self.stroke_active(last, p, PaintMode::Replace, self.settings.primary),
                ToolKind::Brush => self.brush_stroke_spaced(last, p, PaintMode::Over, self.settings.primary),
                ToolKind::Eraser => self.stroke_active(last, p, PaintMode::Erase, Rgba8::TRANSPARENT),
                ToolKind::Airbrush => self.airbrush_stroke_spaced(last, p),
                ToolKind::Dodge => self.dodge_burn_active(p, self.dodge_dv(true)),
                ToolKind::Burn => self.dodge_burn_active(p, self.dodge_dv(false)),
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
                    let sel = self.selection_clone();
                    let (fi, li) = (self.doc.active_frame, self.doc.active_frame().active_layer);
                    {
                        let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
                        tool::apply_gradient(buf, sel.as_ref(), &spec, start, last, &mut self.rng);
                    }
                    let (fid, lid) = (self.doc.frames[fi].id, self.doc.frames[fi].layers[li].id);
                    self.last_gradient =
                        Some((spec.kind, spec.stops.clone(), start, last, spec.smoothstep, fid, lid));
                }
                ToolKind::Line | ToolKind::Rectangle | ToolKind::Ellipse | ToolKind::Triangle => {
                    let color = self.settings.primary;
                    let (fill, lw, kind) = (self.settings.shape_fill, self.settings.line_width, self.tool);
                    let sel = self.selection_clone();
                    let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
                    tool::draw_shape(buf, sel.as_ref(), kind, start, last, 0.0, 0.0, color, fill, lw, PaintMode::Over);
                }
                ToolKind::Move => {
                    if let (Some(float), Some(sel)) = (stroke.floating, self.selection_clone()) {
                        let (dx, dy) = (last.x - start.x, last.y - start.y);
                        let wrap = self.settings.wrap;
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
                                buf.blit_wrapped(&float, bb.x + dx, bb.y + dy);
                            } else {
                                buf.blit_over(&float, Point::new(bb.x + dx, bb.y + dy));
                            }
                        }
                        // Assign directly (no separate record): the mask transition is captured by
                        // the commit_edit() below, so the pixel move and its mask move undo as one.
                        self.doc.selection = Some(Arc::new(
                            if wrap { sel.translated_wrapped(dx, dy) } else { sel.translated(dx, dy) },
                        ));
                    }
                }
                _ => {}
            }
        }

        // Selection tools: build the shape mask and combine it into the selection as one undo step
        // (selection changes are now undoable + serialized; see Document::selection).
        match self.tool {
            ToolKind::SelectRect | ToolKind::SelectEllipse | ToolKind::SelectCircle => {
                let (w, h) = (self.doc.size.w as u32, self.doc.size.h as u32);
                let kind = self.tool;
                let shape = Mask::from_plot(w, h, |plot| match kind {
                    ToolKind::SelectRect => crate::raster::rect_filled(start, last, plot),
                    ToolKind::SelectEllipse => crate::raster::ellipse_filled(start, last, plot),
                    _ => crate::raster::circle_filled(start, last, plot),
                });
                self.combine_selection(&shape, self.selection_mode);
            }
            ToolKind::SelectPoly | ToolKind::SelectFree => {
                let (w, h) = (self.doc.size.w as u32, self.doc.size.h as u32);
                let path = stroke.path.clone();
                let shape = Mask::from_plot(w, h, |plot| crate::raster::polygon_filled(&path, plot));
                self.combine_selection(&shape, self.selection_mode);
            }
            ToolKind::SelectByColor => {
                let (w, h) = (self.doc.size.w as u32, self.doc.size.h as u32);
                let buf = self.doc.active_frame().active_layer().pixels.clone();
                let shape = Mask::from_color(w, h, &buf, start, self.settings.threshold, self.settings.contiguous);
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

    /// The pending figure draft's endpoints, if any (for the shell to draw handles).
    pub fn shape_draft(&self) -> Option<(Point, Point)> {
        self.shape_draft
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
        let sel = self.selection_clone();
        if self.tool == ToolKind::Gradient {
            let spec = self.settings.gradient.clone();
            let (fi, li) = (self.doc.active_frame, self.doc.active_frame().active_layer);
            {
                let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
                tool::apply_gradient(buf, sel.as_ref(), &spec, a, b, &mut self.rng);
            }
            let (fid, lid) = (self.doc.frames[fi].id, self.doc.frames[fi].layers[li].id);
            self.last_gradient = Some((spec.kind, spec.stops.clone(), a, b, spec.smoothstep, fid, lid));
        } else {
            let color = self.settings.primary;
            let (fill, lw, kind) = (self.settings.shape_fill, self.settings.line_width, self.tool);
            let (rot, tip) = (self.shape_rotation, self.triangle_tip);
            let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
            tool::draw_shape(buf, sel.as_ref(), kind, a, b, rot, tip, color, fill, lw, PaintMode::Over);
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
        let sel = self.selection_clone();
        let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
        tool::stamp(buf, sel.as_ref(), p, size, shape, color, mode);
    }
    fn stroke_active(&mut self, a: Point, b: Point, mode: PaintMode, color: Rgba8) {
        let (size, shape) = (self.settings.brush_size, self.settings.brush_shape);
        let sel = self.selection_clone();
        let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
        tool::stroke_segment(buf, sel.as_ref(), a, b, size, shape, color, mode);
    }
    fn airbrush_active(&mut self, p: Point) {
        let (size, intensity, color) = (self.settings.brush_size, self.settings.intensity, self.settings.primary);
        let sel = self.selection_clone();
        let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
        tool::airbrush_dab(buf, sel.as_ref(), p, size, intensity, color, &mut self.rng);
    }

    /// Distance (canvas px) between successive Brush/Airbrush stamps: spacing% of the brush size,
    /// never below 1px.
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
        let sel = self.selection_clone();
        let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
        for p in pts {
            tool::stamp(buf, sel.as_ref(), p, size, shape, color, mode);
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
        let sel = self.selection_clone();
        let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
        tool::dodge_burn_stamp(buf, sel.as_ref(), p, size, shape, dv);
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

    /// Clamp an incoming pointer coordinate to a generous margin around the canvas. Off-canvas
    /// input is legitimate (a freehand stroke can run past the edge and be clipped), so this is NOT
    /// `clamp_cursor`'s canvas-tight clamp — but an unbounded coordinate from a malformed event would
    /// make `spaced_points`/`raster::line` iterate billions of times (a multi-second hang / OOM).
    /// One canvas span of margin preserves every real stroke while bounding the work. [audit F-6]
    fn clamp_pointer(&self, p: Point) -> Point {
        let (w, h) = (self.doc.size.w as i32, self.doc.size.h as i32);
        Point::new(p.x.clamp(-w, 2 * w), p.y.clamp(-h, 2 * h))
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
            match self.tool {
                // Brush/Airbrush honour the spacing setting; Pencil/Eraser stay continuous.
                ToolKind::Brush => self.brush_stroke_spaced(old, self.cursor, PaintMode::Over, self.settings.primary),
                ToolKind::Airbrush => self.airbrush_stroke_spaced(old, self.cursor),
                // Dodge/Burn lighten/darken a stamp at each reticle step (as on the pointer path).
                ToolKind::Dodge | ToolKind::Burn => {
                    self.dodge_burn_active(self.cursor, self.dodge_dv(self.tool == ToolKind::Dodge));
                }
                _ => match self.cursor_paint() {
                    Some((mode, color)) => self.stroke_active(old, self.cursor, mode, color),
                    None => {}
                },
            }
        }
    }

    /// Press the pen down at the reticle (begins a stroke and stamps/sprays the first point).
    pub fn cursor_pen_down(&mut self) {
        if self.precision_before.is_some() || !self.active_editable() {
            return;
        }
        self.precision_before = Some(self.begin_edit());
        self.paint_acc = 0.0; // fresh pen line → reset Brush/Airbrush spacing
        let p = self.cursor;
        match self.cursor_paint() {
            Some((mode, color)) => self.stamp_active(p, mode, color),
            None if self.tool == ToolKind::Airbrush => self.airbrush_active(p),
            None if matches!(self.tool, ToolKind::Dodge | ToolKind::Burn) => {
                self.dodge_burn_active(p, self.dodge_dv(self.tool == ToolKind::Dodge));
            }
            None => {}
        }
    }

    /// Lift the pen, committing the precision stroke as one undo edit.
    pub fn cursor_pen_up(&mut self) {
        if let Some(before) = self.precision_before.take() {
            self.commit_edit(before);
        }
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
        let p = self.cursor;
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

    // ---- selection / clipboard ops ----

    /// Build a selection from the active layer's alpha (pixels with alpha > the alpha cutoff — the
    /// opaque/drawn pixels) and combine it with the current selection using `mode`. Undoable +
    /// serialized (one undo step).
    pub fn select_by_alpha(&mut self, mode: CombineMode) {
        let (w, h) = (self.doc.size.w as u32, self.doc.size.h as u32);
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
        let (w, h) = (self.doc.size.w as u32, self.doc.size.h as u32);
        let mut m = Mask::new(w, h);
        m.select_all();
        self.set_selection(Some(m));
    }
    pub fn select_none(&mut self) {
        self.set_selection(None);
    }
    pub fn invert_selection(&mut self) {
        let (w, h) = (self.doc.size.w as u32, self.doc.size.h as u32);
        let mut m = self.selection_clone().unwrap_or_else(|| Mask::new(w, h));
        m.invert();
        self.set_selection(Some(m));
    }
    /// Translate the selection MASK (not the pixels) by (dx, dy), honouring the same off-canvas edge
    /// modes as a pixel move: Wrap (cells re-enter the opposite edge), Protect (clamp so the whole
    /// selection stays on-canvas), or Regular (clip cells that leave the canvas). One undo step.
    pub fn move_selection(&mut self, dx: i32, dy: i32) {
        let m = match self.selection_clone() {
            Some(m) => m,
            None => return,
        };
        let moved = if self.settings.wrap {
            m.translated_wrapped(dx, dy)
        } else if self.settings.protect_pixels {
            match m.bounds() {
                Some(bb) => {
                    let (w, h) = (self.doc.size.w as i32, self.doc.size.h as i32);
                    let cdx = dx.clamp(-bb.x, w - (bb.x + bb.w as i32));
                    let cdy = dy.clamp(-bb.y, h - (bb.y + bb.h as i32));
                    m.translated(cdx, cdy)
                }
                None => m,
            }
        } else {
            m.translated(dx, dy)
        };
        self.set_selection(Some(moved));
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
        self.paste_draft
            .as_ref()
            .map(|(clip, pos)| IRect::new(pos.x, pos.y, clip.width(), clip.height()))
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
        let sel = self.selection_clone();
        let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
        tool::fill_region(buf, sel.as_ref(), color);
        self.commit_edit(before);
    }

    pub fn clear_selection_pixels(&mut self) {
        // No selection → no-op (clearing "the selection" must not wipe the whole layer).
        if self.doc.selection.is_none() || !self.active_editable() {
            return;
        }
        let before = self.begin_edit();
        let sel = self.selection_clone();
        let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
        tool::clear_region(buf, sel.as_ref());
        self.commit_edit(before);
    }

    pub fn apply_hsv_shift(&mut self) {
        if !self.active_editable() {
            return;
        }
        let before = self.begin_edit();
        let (dh, ds, dv) = self.settings.hsv;
        let sel = self.selection_clone();
        let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
        tool::hsv_shift_region(buf, sel.as_ref(), dh, ds, dv);
        self.commit_edit(before);
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

    /// Clamp a translation so an opaque bounding box `bbox` stays fully on-canvas.
    fn clamp_move_to_canvas(&self, bbox: crate::geom::IRect, dx: i32, dy: i32) -> (i32, i32) {
        let (w, h) = (self.doc.size.w as i32, self.doc.size.h as i32);
        (dx.clamp(-bbox.x, w - bbox.right()), dy.clamp(-bbox.y, h - bbox.bottom()))
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
            for &li in &layers {
                let src = s.doc.active_frame().layers[li].pixels.clone();
                let buf = &mut s.doc.active_frame_mut().layers[li].pixels;
                buf.clear();
                if wrap {
                    buf.blit_wrapped(&src, dx, dy);
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
                buf.blit_wrapped(&float, bb.x + dx, bb.y + dy);
            } else {
                buf.blit_over(&float, Point::new(bb.x + dx, bb.y + dy));
            }
        }
        // Move the mask BEFORE committing so the pixel record captures the translated mask as its
        // "after": undo restores both the pixels and the mask to their pre-nudge positions, redo
        // re-applies both. (Assign directly — not via set_selection — so it isn't a separate step.)
        self.doc.selection = Some(Arc::new(
            if wrap { sel.translated_wrapped(dx, dy) } else { sel.translated(dx, dy) },
        ));
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
        self.playing = true;
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
        self.doc.selection.as_ref().and_then(|m| m.bounds())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

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
        assert!(s.doc.selection.as_ref().unwrap().get(4, 4));
        assert!(!s.doc.selection.as_ref().unwrap().get(2, 2)); // pixels never moved, only the mask

        // Wrap: cells leaving an edge re-enter the opposite one.
        let mut s = Session::new(8, 8);
        s.settings.wrap = true;
        sel_2x2(&mut s, 6, 6);
        s.move_selection(2, 2); // (6,6) -> (8,8) wraps to (0,0)
        assert!(s.doc.selection.as_ref().unwrap().get(0, 0));

        // Protect: clamp so the whole selection stays on-canvas.
        let mut s = Session::new(8, 8);
        s.settings.protect_pixels = true;
        sel_2x2(&mut s, 6, 6);
        s.move_selection(5, 5); // would push off the right/bottom → clamped to no move
        assert!(s.doc.selection.as_ref().unwrap().get(6, 6));
        s.move_selection(-3, -3); // moves freely the other way
        assert!(s.doc.selection.as_ref().unwrap().get(3, 3));
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
    fn precision_pen_draws_line_as_one_edit() {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        s.tool = ToolKind::Pencil;
        s.set_cursor(2, 2);
        s.cursor_pen_down();
        s.move_cursor(5, 0); // drag the reticle → draws a horizontal line
        s.cursor_pen_up();
        assert_eq!(s.pixel(0, 0, 2, 2), Rgba8::WHITE);
        assert_eq!(s.pixel(0, 0, 7, 2), Rgba8::WHITE);
        assert_eq!(s.pixel(0, 0, 4, 2), Rgba8::WHITE); // interpolated
        // entire line is a single undo step
        assert!(s.doc.undo());
        assert_eq!(s.pixel(0, 0, 4, 2), Rgba8::TRANSPARENT);
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
        s.move_cursor(5, 0);
        s.cursor_pen_up();
        // now erase along it in precision mode
        s.tool = ToolKind::Eraser;
        s.set_cursor(2, 2);
        s.cursor_pen_down();
        s.move_cursor(5, 0);
        s.cursor_pen_up();
        assert_eq!(s.pixel(0, 0, 4, 2), Rgba8::TRANSPARENT); // erased back to transparent
        assert!(s.doc.undo()); // erase is its own single undo step
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
        // a continuous precision spray: pen down, drag, pen up — one undo edit
        s.cursor_pen_down();
        s.move_cursor(2, 0);
        s.move_cursor(2, 0);
        s.cursor_pen_up();
        let h = s.doc.active_frame().active_layer().pixels.content_hash();
        assert_ne!(h, RgbaBuffer::new(16, 16).content_hash(), "airbrush should have painted something");
        assert!(s.doc.undo());
        assert!(!s.doc.undo(), "the whole precision spray is a single undo step");
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
    fn bucket_all_layers_bounds_region_by_composite() {
        let mut s = Session::new(8, 8);
        for y in 0..8 {
            s.doc.active_frame_mut().layers[0].pixels.set(4, y, Rgba8::BLACK); // wall on the bottom layer
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
        s.resize_canvas(32, 32, true);
        assert_eq!(s.size(), (32, 32));
        assert_eq!(s.pixel(0, 0, 8, 8), Rgba8::WHITE); // shifted by +8,+8
        assert!(s.doc.undo());
        assert_eq!(s.size(), (16, 16));
        assert_eq!(s.pixel(0, 0, 0, 0), Rgba8::WHITE);
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
            dither: false,
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
        let sel = s.doc.selection.as_ref().expect("selection set");
        assert!(sel.get(0, 0), "the opaque pixel IS selected at cutoff 0");
        assert!(!sel.get(3, 3), "a transparent pixel is NOT selected");
        // A translucent pixel (alpha 128) is selected only while the cutoff is below 128.
        s.settings.primary = Rgba8::new(255, 0, 0, 128);
        s.tap(1, 1);
        s.settings.alpha_cutoff = 128;
        s.run_script("SelectByAlpha(Replace)").unwrap();
        let sel = s.doc.selection.as_ref().unwrap();
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
        let sel = s.doc.selection.as_ref().expect("selection kept");
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
        assert!(s.doc.selection.as_ref().unwrap().get(5, 5), "mask followed the pixel");
        // ONE undo restores both the pixel AND the selection mask to the origin.
        assert!(s.doc.undo());
        assert_eq!(s.pixel(0, 0, 2, 2), Rgba8::WHITE, "pixel moved back");
        assert_eq!(s.pixel(0, 0, 5, 5), Rgba8::TRANSPARENT);
        let sel = s.doc.selection.as_ref().expect("selection restored");
        assert!(sel.get(2, 2), "the mask moved back with the pixel");
        assert!(!sel.get(5, 5), "the mask is no longer at the moved position");
        // redo re-applies both
        assert!(s.doc.redo());
        assert_eq!(s.pixel(0, 0, 5, 5), Rgba8::WHITE);
        assert!(s.doc.selection.as_ref().unwrap().get(5, 5));
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
        assert!(s.doc.selection.as_ref().unwrap().get(4, 3));
        assert!(s.doc.undo());
        assert_eq!(s.pixel(0, 0, 3, 3), Rgba8::WHITE, "pixel back");
        assert!(s.doc.selection.as_ref().unwrap().get(3, 3), "mask back");
        assert!(!s.doc.selection.as_ref().unwrap().get(4, 3));
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
    fn no_selection_survives_save_load_as_none() {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        s.tap(1, 1);
        let bytes = s.save_bytes();
        let mut s2 = Session::new(8, 8);
        s2.load_bytes(&bytes).unwrap();
        assert!(s2.doc.selection.is_none());
    }
}
