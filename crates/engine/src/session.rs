//! `Session` — the single stateful entry point driven by both the CLI harness and the
//! Flutter shell (SPEC §9, §19). Owns the document + editor state, runs the action-script
//! DSL, routes pointer input to tools, wraps each change in one undo record, and exposes
//! probes.

use crate::buffer::RgbaBuffer;
use crate::color::Rgba8;
use crate::document::{Document, Frame, LoopMode};
use crate::geom::{IRect, Point, Size};
use crate::io;
use crate::render;
use crate::selection::{CombineMode, Mask};
use crate::tool::{self, GradientKind, PaintMode, Stop, ToolKind, ToolSettings};
use crate::util::{hash_hex, Hash, SeededRng, VirtualClock};

mod parse;
pub use parse::Action;

/// In-progress gesture state.
struct Stroke {
    before: Vec<Option<std::sync::Arc<crate::buffer::Tile>>>,
    start: Point,
    last: Point,
    path: Vec<Point>,
    floating: Option<RgbaBuffer>, // for Move
}

pub struct Session {
    pub doc: Document,
    pub tool: ToolKind,
    pub settings: ToolSettings,
    pub selection: Option<Mask>,
    pub selection_mode: CombineMode,
    /// Layers (within the active frame) selected to move/transform together (SPEC §15).
    pub layer_sel: Vec<usize>,
    /// Precision-pencil reticle position + active pen stroke (draw-by-button, off-finger).
    cursor: Point,
    precision_before: Option<Vec<Option<std::sync::Arc<crate::buffer::Tile>>>>,
    clipboard: Option<(RgbaBuffer, Point)>,
    rng: SeededRng,
    clock: VirtualClock,
    playing: bool,
    stroke: Option<Stroke>,
    last_gradient: Option<(GradientKind, Vec<Stop>, Point, Point, u32, u32)>,
    /// Move-layer drag state: pre-drag pixel snapshots of each moved layer, plus the pre-drag
    /// frame (and its id) for a single grouped undo. Set on pointer_down, cleared on pointer_up.
    move_layers: Vec<(usize, RgbaBuffer)>,
    move_before: Option<(u32, crate::document::Frame)>,
}

impl Session {
    pub fn new(w: u16, h: u16) -> Self {
        Session {
            doc: Document::new(w, h),
            tool: ToolKind::Pencil,
            settings: ToolSettings::default(),
            selection: None,
            selection_mode: CombineMode::Replace,
            layer_sel: vec![0],
            cursor: Point::new(w as i32 / 2, h as i32 / 2),
            precision_before: None,
            clipboard: None,
            rng: SeededRng::default(),
            clock: VirtualClock::default(),
            playing: false,
            stroke: None,
            last_gradient: None,
            move_layers: Vec::new(),
            move_before: None,
        }
    }

    pub fn empty() -> Self {
        Session::new(64, 64)
    }

    fn ensure_selection(&mut self) -> &mut Mask {
        if self.selection.is_none() {
            self.selection = Some(Mask::new(self.doc.size.w as u32, self.doc.size.h as u32));
        }
        self.selection.as_mut().unwrap()
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
    fn draw_tool_preview(&self, buf: &mut RgbaBuffer) {
        let stroke = match &self.stroke {
            Some(s) => s,
            None => return,
        };
        let (a, b) = (stroke.start, stroke.last);
        let (w, h) = (self.doc.size.w as u32, self.doc.size.h as u32);
        let color = self.settings.primary;
        match self.tool {
            ToolKind::Line => crate::raster::line(a, b, |x, y| buf.blend_over(x, y, color)),
            ToolKind::Rectangle => {
                if self.settings.shape_fill {
                    crate::raster::rect_filled(a, b, |x, y| buf.blend_over(x, y, color));
                } else {
                    crate::raster::rect_outline(a, b, self.settings.line_width.max(1) as i32, |x, y| buf.blend_over(x, y, color));
                }
            }
            ToolKind::Ellipse => {
                if self.settings.shape_fill {
                    crate::raster::ellipse_filled(a, b, |x, y| buf.blend_over(x, y, color));
                } else {
                    crate::raster::ellipse_outline(a, b, self.settings.line_width.max(1) as i32, |x, y| buf.blend_over(x, y, color));
                }
            }
            // Selection-tool outlines are NOT baked into the pixel buffer (they would be as
            // thick as a canvas pixel). The shell draws them as a thin animated screen-space
            // outline using `outline_mask()` below.
            ToolKind::Gradient => {
                let spec = &self.settings.gradient;
                for y in 0..h as i32 {
                    for x in 0..w as i32 {
                        if let Some(m) = &self.selection {
                            if !m.get(x, y) {
                                continue;
                            }
                        }
                        buf.set(x, y, tool::gradient_eval(spec.kind, &spec.stops, a, b, x, y));
                    }
                }
            }
            ToolKind::Move => {
                if let (Some(float), Some(sel)) = (&stroke.floating, &self.selection) {
                    if let Some(bb) = sel.bounds() {
                        let (dx, dy) = (b.x - a.x, b.y - a.y);
                        buf.blit_over(float, Point::new(bb.x + dx, bb.y + dy));
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
                let mut m = self.selection.clone().unwrap_or_else(|| Mask::new(w, h));
                m.combine(&shape, self.selection_mode);
                return Some(m);
            }
        }
        self.selection.clone()
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

    pub fn pixel(&self, f: usize, l: usize, x: i32, y: i32) -> Rgba8 {
        self.doc.frames[f].layers[l].pixels.get(x, y)
    }

    pub fn layer_hash(&self, f: usize, l: usize) -> Hash {
        self.doc.frames[f].layers[l].pixels.content_hash()
    }

    pub fn state_json(&self) -> String {
        crate::probe::state_json(&self.doc)
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

    fn begin_edit(&self) -> Vec<Option<std::sync::Arc<crate::buffer::Tile>>> {
        self.doc.active_frame().active_layer().pixels.snapshot()
    }

    fn commit_edit(&mut self, before: Vec<Option<std::sync::Arc<crate::buffer::Tile>>>) {
        let (fid, lid, patch) = {
            let f = self.doc.active_frame();
            let l = f.active_layer();
            (f.id, l.id, l.pixels.diff_from(&before))
        };
        self.doc.record_pixels(fid, lid, patch);
    }

    fn edit_frame<R>(&mut self, f: impl FnOnce(&mut Session) -> R) -> R {
        let fi = self.doc.active_frame;
        let before = self.doc.frames[fi].clone();
        let fid = self.doc.frames[fi].id;
        let r = f(self);
        let after = self.doc.frames[fi].clone();
        self.doc.record_frame_content(fid, before, after);
        r
    }

    fn edit_doc<R>(&mut self, label: &str, f: impl FnOnce(&mut Session) -> R) -> R {
        let before = self.doc.frames.clone();
        let before_active = self.doc.active_frame;
        let before_size = self.doc.size;
        let r = f(self);
        self.doc.record_doc_structure(label, before, before_active, before_size);
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
        let p = Point::new(x, y);
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
        let mut floating = None;
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
                    let sel = self.selection.clone();
                    let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
                    tool::flood_fill(buf, sel.as_ref(), p, color, th, cont, PaintMode::Replace);
                }
                ToolKind::Move => {
                    // lift selected pixels into a floating buffer
                    if let Some(sel) = self.selection.clone() {
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
        // Move-layer: snapshot every selected, editable layer (the move-group, or just the active
        // layer when none is grouped) plus the pre-drag frame, so pointer_move can re-blit them at
        // the live offset and pointer_up records one grouped undo.
        if self.tool == ToolKind::MoveLayer {
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
        }
        self.stroke = Some(Stroke { before, start: p, last: p, path: vec![p], floating });
    }

    pub fn pointer_move(&mut self, x: i32, y: i32) {
        let p = Point::new(x, y);
        let last = match &self.stroke {
            Some(s) => s.last,
            None => return,
        };
        // Move-layer: re-blit each snapshotted layer of the move-group at the live offset from the
        // drag start (single grouped undo, committed on pointer_up). move_layers and doc are
        // disjoint fields, so the index-based borrow is sound.
        if self.tool == ToolKind::MoveLayer {
            let start = match self.stroke.as_ref() {
                Some(s) => s.start,
                None => return,
            };
            let (dx, dy) = (p.x - start.x, p.y - start.y);
            let fi = self.doc.active_frame;
            for idx in 0..self.move_layers.len() {
                let li = self.move_layers[idx].0;
                if li < self.doc.frames[fi].layers.len() {
                    let snap = &self.move_layers[idx].1;
                    let buf = &mut self.doc.frames[fi].layers[li].pixels;
                    buf.clear();
                    buf.blit_over(snap, Point::new(dx, dy));
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
                ToolKind::Brush => self.stroke_active(last, p, PaintMode::Over, self.settings.primary),
                ToolKind::Eraser => self.stroke_active(last, p, PaintMode::Erase, Rgba8::TRANSPARENT),
                ToolKind::Airbrush => self.airbrush_active(p),
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
        // Move-layer: commit the grouped translation as one frame-content undo (or discard it if
        // nothing actually moved, e.g. a tap).
        if self.tool == ToolKind::MoveLayer {
            if let Some((fid, before)) = self.move_before.take() {
                if stroke.start != stroke.last {
                    let fi = self.doc.active_frame;
                    let after = self.doc.frames[fi].clone();
                    self.doc.record_frame_content(fid, before, after);
                }
            }
            self.move_layers.clear();
            return;
        }
        let (start, last) = (stroke.start, stroke.last);
        let is_pixel_tool = matches!(
            self.tool,
            ToolKind::Pencil
                | ToolKind::Brush
                | ToolKind::Eraser
                | ToolKind::Airbrush
                | ToolKind::Bucket
                | ToolKind::Dodge
                | ToolKind::Burn
        );

        if self.active_editable() {
            match self.tool {
                ToolKind::Gradient => {
                    let spec = self.settings.gradient.clone();
                    let sel = self.selection.clone();
                    let (fi, li) = (self.doc.active_frame, self.doc.active_frame().active_layer);
                    {
                        let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
                        tool::apply_gradient(buf, sel.as_ref(), &spec, start, last, &mut self.rng);
                    }
                    let (fid, lid) = (self.doc.frames[fi].id, self.doc.frames[fi].layers[li].id);
                    self.last_gradient =
                        Some((spec.kind, spec.stops.clone(), start, last, fid, lid));
                }
                ToolKind::Line | ToolKind::Rectangle | ToolKind::Ellipse => {
                    let color = self.settings.primary;
                    let (fill, lw, kind) = (self.settings.shape_fill, self.settings.line_width, self.tool);
                    let sel = self.selection.clone();
                    let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
                    tool::draw_shape(buf, sel.as_ref(), kind, start, last, color, fill, lw, PaintMode::Over);
                }
                ToolKind::Move => {
                    if let (Some(float), Some(sel)) = (stroke.floating, self.selection.clone()) {
                        let (dx, dy) = (last.x - start.x, last.y - start.y);
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
                            buf.blit_over(&float, Point::new(bb.x + dx, bb.y + dy));
                        }
                        self.selection = Some(sel.translated(dx, dy));
                    }
                }
                _ => {}
            }
        }

        // Selection tools: build the shape mask and combine (no undo — selection is editor state).
        match self.tool {
            ToolKind::SelectRect | ToolKind::SelectEllipse | ToolKind::SelectCircle => {
                let (w, h) = (self.doc.size.w as u32, self.doc.size.h as u32);
                let kind = self.tool;
                let shape = Mask::from_plot(w, h, |plot| match kind {
                    ToolKind::SelectRect => crate::raster::rect_filled(start, last, plot),
                    ToolKind::SelectEllipse => crate::raster::ellipse_filled(start, last, plot),
                    _ => crate::raster::circle_filled(start, last, plot),
                });
                let mode = self.selection_mode;
                self.ensure_selection().combine(&shape, mode);
            }
            ToolKind::SelectPoly | ToolKind::SelectFree => {
                let (w, h) = (self.doc.size.w as u32, self.doc.size.h as u32);
                let path = stroke.path.clone();
                let shape = Mask::from_plot(w, h, |plot| crate::raster::polygon_filled(&path, plot));
                let mode = self.selection_mode;
                self.ensure_selection().combine(&shape, mode);
            }
            ToolKind::SelectByColor => {
                let (w, h) = (self.doc.size.w as u32, self.doc.size.h as u32);
                let buf = self.doc.active_frame().active_layer().pixels.clone();
                let shape = Mask::from_color(w, h, &buf, start, self.settings.threshold, self.settings.contiguous);
                let mode = self.selection_mode;
                self.ensure_selection().combine(&shape, mode);
            }
            _ => {}
        }

        // Commit pixel changes as one undo record.
        if is_pixel_tool
            || matches!(self.tool, ToolKind::Gradient | ToolKind::Line | ToolKind::Rectangle | ToolKind::Ellipse | ToolKind::Move)
        {
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
            self.stroke = None;
            return;
        }
        // Normal stroke: restore the active layer's pre-stroke pixels.
        if let Some(stroke) = self.stroke.take() {
            self.doc
                .active_frame_mut()
                .active_layer_mut()
                .pixels
                .restore_snapshot(&stroke.before);
        }
        // Precision pen line in progress.
        if let Some(before) = self.precision_before.take() {
            self.doc
                .active_frame_mut()
                .active_layer_mut()
                .pixels
                .restore_snapshot(&before);
        }
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
        let sel = self.selection.clone();
        let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
        tool::stamp(buf, sel.as_ref(), p, size, shape, color, mode);
    }
    fn stroke_active(&mut self, a: Point, b: Point, mode: PaintMode, color: Rgba8) {
        let (size, shape) = (self.settings.brush_size, self.settings.brush_shape);
        let sel = self.selection.clone();
        let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
        tool::stroke_segment(buf, sel.as_ref(), a, b, size, shape, color, mode);
    }
    fn airbrush_active(&mut self, p: Point) {
        let (size, intensity, color) = (self.settings.brush_size, self.settings.intensity, self.settings.primary);
        let sel = self.selection.clone();
        let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
        tool::airbrush_dab(buf, sel.as_ref(), p, size, intensity, color, &mut self.rng);
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
        let sel = self.selection.clone();
        let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
        tool::dodge_burn_stamp(buf, sel.as_ref(), p, size, shape, dv);
    }

    // ---- precision pencil (draw-by-button, reticle off the finger) ----

    fn clamp_cursor(&self, p: Point) -> Point {
        Point::new(
            p.x.clamp(0, self.doc.size.w as i32 - 1),
            p.y.clamp(0, self.doc.size.h as i32 - 1),
        )
    }

    pub fn cursor(&self) -> Point {
        self.cursor
    }

    /// Place the reticle at an absolute canvas pixel (clamped).
    pub fn set_cursor(&mut self, x: i32, y: i32) {
        self.cursor = self.clamp_cursor(Point::new(x, y));
    }

    /// Move the reticle by (dx, dy). While the pen is down, paints from the old position to
    /// the new one (so dragging draws a visible line offset from the finger).
    pub fn move_cursor(&mut self, dx: i32, dy: i32) {
        let old = self.cursor;
        self.cursor = self.clamp_cursor(Point::new(old.x + dx, old.y + dy));
        if self.precision_before.is_some() && self.active_editable() && self.cursor != old {
            self.stroke_active(old, self.cursor, PaintMode::Replace, self.settings.primary);
        }
    }

    /// Press the pen down at the reticle (begins a stroke and stamps the first pixel).
    pub fn cursor_pen_down(&mut self) {
        if self.precision_before.is_some() || !self.active_editable() {
            return;
        }
        self.precision_before = Some(self.begin_edit());
        let p = self.cursor;
        self.stamp_active(p, PaintMode::Replace, self.settings.primary);
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
    /// "one go at a time" airbrush, driven off-finger like the precision pencil.
    pub fn airbrush_cursor(&mut self) {
        if !self.active_editable() {
            return;
        }
        let before = self.begin_edit();
        let p = self.cursor;
        self.airbrush_active(p);
        self.commit_edit(before);
    }

    // ---- selection / clipboard ops ----

    pub fn select_all(&mut self) {
        self.ensure_selection().select_all();
    }
    pub fn select_none(&mut self) {
        self.selection = None;
    }
    pub fn invert_selection(&mut self) {
        let (w, h) = (self.doc.size.w as u32, self.doc.size.h as u32);
        let m = self.selection.get_or_insert_with(|| Mask::new(w, h));
        m.invert();
    }
    pub fn move_selection(&mut self, dx: i32, dy: i32) {
        if let Some(m) = &self.selection {
            self.selection = Some(m.translated(dx, dy));
        }
    }

    pub fn copy(&mut self) {
        if let Some(sel) = &self.selection {
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
        if let Some(sel) = self.selection.clone() {
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

    pub fn fill_selection(&mut self) {
        if !self.active_editable() {
            return;
        }
        let before = self.begin_edit();
        let color = self.settings.primary;
        let sel = self.selection.clone();
        let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
        tool::fill_region(buf, sel.as_ref(), color);
        self.commit_edit(before);
    }

    pub fn clear_selection_pixels(&mut self) {
        if !self.active_editable() {
            return;
        }
        let before = self.begin_edit();
        let sel = self.selection.clone();
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
        let sel = self.selection.clone();
        let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
        tool::hsv_shift_region(buf, sel.as_ref(), dh, ds, dv);
        self.commit_edit(before);
    }

    pub fn map_active(&mut self, f: impl Fn(Rgba8) -> Rgba8) {
        if !self.active_editable() {
            return;
        }
        let before = self.begin_edit();
        let sel = self.selection.clone();
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

    /// Translate the content of all selected layers by (dx,dy), together, as one undoable
    /// frame edit (SPEC §15 "move multiple layers as one").
    pub fn nudge_layers(&mut self, dx: i32, dy: i32) {
        let layers: Vec<usize> = self
            .layer_sel
            .iter()
            .copied()
            .filter(|&i| i < self.doc.active_frame().layers.len() && !self.doc.active_frame().layers[i].locked)
            .collect();
        if layers.is_empty() || (dx == 0 && dy == 0) {
            return;
        }
        self.edit_frame(|s| {
            for &li in &layers {
                let src = s.doc.active_frame().layers[li].pixels.clone();
                let buf = &mut s.doc.active_frame_mut().layers[li].pixels;
                buf.clear();
                for y in 0..src.height() as i32 {
                    for x in 0..src.width() as i32 {
                        let c = src.get(x, y);
                        if c.a != 0 {
                            buf.set(x + dx, y + dy, c);
                        }
                    }
                }
            }
        });
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

    // ---- canvas ops (SPEC §28.1) ----

    pub fn flip_horizontal(&mut self) {
        if !self.active_editable() {
            return;
        }
        let before = self.begin_edit();
        let w = self.doc.size.w as i32;
        let h = self.doc.size.h as i32;
        let src = self.doc.active_frame().active_layer().pixels.clone();
        let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
        buf.clear();
        for y in 0..h {
            for x in 0..w {
                let c = src.get(w - 1 - x, y);
                if c.a != 0 {
                    buf.set(x, y, c);
                }
            }
        }
        self.commit_edit(before);
    }

    pub fn flip_vertical(&mut self) {
        if !self.active_editable() {
            return;
        }
        let before = self.begin_edit();
        let w = self.doc.size.w as i32;
        let h = self.doc.size.h as i32;
        let src = self.doc.active_frame().active_layer().pixels.clone();
        let buf = &mut self.doc.active_frame_mut().active_layer_mut().pixels;
        buf.clear();
        for y in 0..h {
            for x in 0..w {
                let c = src.get(x, h - 1 - y);
                if c.a != 0 {
                    buf.set(x, y, c);
                }
            }
        }
        self.commit_edit(before);
    }

    /// Rotate the whole document by `quarter_turns` × 90° clockwise (SPEC §28.1). 90°/270°
    /// swap the canvas dimensions. Undoable (size travels with the edit).
    pub fn rotate(&mut self, quarter_turns: u8) {
        let q = quarter_turns % 4;
        if q == 0 {
            return;
        }
        let old = self.doc.size;
        let new_size = if q == 2 { old } else { Size::new(old.h, old.w) };
        let (ow, oh) = (old.w as i32, old.h as i32);
        self.edit_doc("rotate", |s| {
            for f in &mut s.doc.frames {
                for l in &mut f.layers {
                    let src = l.pixels.clone();
                    let mut dst = RgbaBuffer::from_size(new_size);
                    for y in 0..oh {
                        for x in 0..ow {
                            let c = src.get(x, y);
                            if c.a == 0 {
                                continue;
                            }
                            let (nx, ny) = match q {
                                1 => (oh - 1 - y, x),
                                2 => (ow - 1 - x, oh - 1 - y),
                                _ => (y, ow - 1 - x),
                            };
                            dst.set(nx, ny, c);
                        }
                    }
                    l.pixels = dst;
                }
            }
            s.doc.size = new_size;
        });
        self.selection = None;
    }

    /// Resize the canvas, placing existing content at top-left or centered (SPEC §28.1).
    pub fn resize_canvas(&mut self, nw: u16, nh: u16, center: bool) {
        let new_size = Size::new(nw.clamp(8, 256), nh.clamp(8, 256));
        if new_size == self.doc.size {
            return;
        }
        let old = self.doc.size;
        let (ox, oy) = if center {
            ((new_size.w as i32 - old.w as i32) / 2, (new_size.h as i32 - old.h as i32) / 2)
        } else {
            (0, 0)
        };
        self.edit_doc("resize", |s| {
            for f in &mut s.doc.frames {
                for l in &mut f.layers {
                    let src = l.pixels.clone();
                    let mut dst = RgbaBuffer::from_size(new_size);
                    for y in 0..old.h as i32 {
                        for x in 0..old.w as i32 {
                            let c = src.get(x, y);
                            if c.a != 0 {
                                dst.set(x + ox, y + oy, c);
                            }
                        }
                    }
                    l.pixels = dst;
                }
            }
            s.doc.size = new_size;
        });
        self.selection = None;
    }

    /// Crop the canvas to the current selection's bounding box (SPEC §28.1). No-op without
    /// a selection.
    pub fn crop_to_selection(&mut self) {
        let bounds = match self.selection.as_ref().and_then(|m| m.bounds()) {
            Some(b) => b,
            None => return,
        };
        let nw = (bounds.w as u16).clamp(8, 256);
        let nh = (bounds.h as u16).clamp(8, 256);
        let new_size = Size::new(nw, nh);
        let (ox, oy) = (bounds.x, bounds.y);
        self.edit_doc("crop", |s| {
            for f in &mut s.doc.frames {
                for l in &mut f.layers {
                    let src = l.pixels.clone();
                    let mut dst = RgbaBuffer::from_size(new_size);
                    for y in 0..nh as i32 {
                        for x in 0..nw as i32 {
                            let c = src.get(ox + x, oy + y);
                            if c.a != 0 {
                                dst.set(x, y, c);
                            }
                        }
                    }
                    l.pixels = dst;
                }
            }
            s.doc.size = new_size;
        });
        self.selection = None;
    }

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
        self.doc = io::load_from_bytes(data)?;
        self.selection = None;
        self.clipboard = None;
        Ok(())
    }

    // ---- gradient oracle access ----

    pub fn assert_last_gradient(&self, tol: u8) -> Option<crate::probe::GradientOracle> {
        let (kind, stops, p0, p1, fid, lid) = self.last_gradient.as_ref()?;
        let fi = self.doc.frame_index_by_id(*fid)?;
        let li = self.doc.frames[fi].layer_index_by_id(*lid)?;
        Some(crate::probe::gradient_oracle(
            &self.doc.frames[fi].layers[li].pixels,
            *kind,
            stops,
            *p0,
            *p1,
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
        self.selection.as_ref().and_then(|m| m.bounds())
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
        s.tool = ToolKind::PrecisionPencil;
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
        s.tool = ToolKind::PrecisionPencil;
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
}
