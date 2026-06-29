//! Canvas-level transforms — flip / rotate / resize / crop (SPEC §28.1). Split out of the
//! `session` god-file along the same `impl Session` seam `mod parse` already uses, so the methods
//! still share `Session`'s private state (begin_edit/commit_edit/edit_doc, doc, selection). [audit F-17]

use super::{RotateDraft, Session};
use crate::buffer::RgbaBuffer;
use crate::color::Rgba8;
use crate::document::Frame;
use crate::geom::{IRect, Point, PointF, Size};
use crate::selection::Mask;
use std::sync::Arc;

impl Session {
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
            s.doc.selection = None; // the old mask is wrong-sized now; clearing rides this undo step
        });
    }

    /// Resize the canvas, placing existing content at top-left or centered (SPEC §28.1).
    pub fn resize_canvas(&mut self, nw: u16, nh: u16, center: bool) {
        let new_size = Size::new(nw.clamp(8, 256), nh.clamp(8, 256));
        if new_size == self.doc.size {
            return;
        }
        self.shape_draft = None; // endpoints reference the old dimensions
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
            s.doc.selection = None; // the old mask is wrong-sized now; clearing rides this undo step
        });
    }

    /// Crop the canvas to the current selection's bounding box (SPEC §28.1). No-op without
    /// a selection.
    pub fn crop_to_selection(&mut self) {
        let bounds = match self.doc.selection.as_ref().and_then(|m| m.bounds()) {
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
            s.doc.selection = None; // crop consumes the selection; clearing rides this undo step
        });
    }

    // ---- layer / selection rotation (the Rotate tool — distinct from the whole-document `rotate`
    //      above, which is now reached from the timeline ☰ menu's "Rotate canvas") ----

    /// Rotate the active layer (or the selected pixels within it) by `quarter_turns` × 90° clockwise,
    /// about the layer/canvas centre — or the selection's bounding-box centre when pixels are
    /// selected. Content that would leave the canvas is clipped; lossless on a square canvas. When a
    /// selection drives it, the selection mask rotates with the pixels. One undo step.
    ///
    /// Implemented by lifting → rotating → committing through the same draft machinery the "Angle"
    /// mode uses, so the instant buttons, the live preview, and the commit all rotate identically.
    pub fn rotate_layer(&mut self, quarter_turns: u8) {
        let q = quarter_turns % 4;
        if q == 0 {
            return;
        }
        self.rotate_draft = None; // never stack on a half-open Angle draft
        self.rotate_draft_begin();
        if self.rotate_draft.is_some() {
            self.rotate_draft_set_angle((q as f32 * std::f32::consts::FRAC_PI_2 * 1000.0).round() as i32);
            self.rotate_draft_commit();
        }
    }

    /// Begin the Rotate tool's "Angle" draft: lift the active layer (or the selected pixels) so they
    /// can be previewed rotating non-destructively about the pivot. No-op if a draft is already open
    /// or the active layer isn't editable. The shell then drives `rotate_draft_set_angle` from the
    /// handle and finishes with `rotate_draft_commit`/`rotate_draft_cancel`.
    pub fn rotate_draft_begin(&mut self) {
        if self.rotate_draft.is_some() || !self.active_editable() {
            return;
        }
        let fi = self.doc.active_frame;
        let fid = self.doc.frames[fi].id;
        let lid = self.doc.frames[fi].active_layer().id;
        let (cw, ch) = (self.doc.size.w as i32, self.doc.size.h as i32);
        let sel_before = self.doc.selection.clone();

        // Selection present (and non-empty) → lift just the masked pixels, pivot on the bbox centre.
        if let Some(sel) = self.selection_clone() {
            if let Some(bb) = sel.bounds() {
                let layer = &self.doc.frames[fi].active_layer().pixels;
                let mut src = RgbaBuffer::new(bb.w, bb.h);
                let mut src_mask = Mask::new(bb.w, bb.h);
                for j in 0..bb.h as i32 {
                    for i in 0..bb.w as i32 {
                        if sel.get(bb.x + i, bb.y + j) {
                            src.set(i, j, layer.get(bb.x + i, bb.y + j));
                            src_mask.set(i, j, true);
                        }
                    }
                }
                self.rotate_draft = Some(RotateDraft {
                    fid,
                    lid,
                    is_selection: true,
                    sel_before,
                    src,
                    sw: bb.w as i32,
                    sh: bb.h as i32,
                    src_origin: Point::new(bb.x, bb.y),
                    src_mask: Some(src_mask),
                    pivot: PointF::new(bb.x as f32 + bb.w as f32 / 2.0, bb.y as f32 + bb.h as f32 / 2.0),
                    angle: 0.0,
                });
                return;
            }
        }

        // No selection → lift the whole active layer, pivot on the canvas centre.
        let src = self.doc.frames[fi].active_layer().pixels.clone();
        self.rotate_draft = Some(RotateDraft {
            fid,
            lid,
            is_selection: false,
            sel_before,
            src,
            sw: cw,
            sh: ch,
            src_origin: Point::new(0, 0),
            src_mask: None,
            pivot: PointF::new(cw as f32 / 2.0, ch as f32 / 2.0),
            angle: 0.0,
        });
    }

    /// Set the open rotate draft's angle (milliradians, clockwise — matching `SetShapeRotation`).
    /// No-op if no draft is open.
    pub fn rotate_draft_set_angle(&mut self, milliradians: i32) {
        if let Some(d) = self.rotate_draft.as_mut() {
            d.angle = milliradians as f32 / 1000.0;
        }
    }

    /// Commit the rotate draft into the document as one undo step (the selection mask rides along for
    /// a selection rotation). The ONLY path that makes the rotation permanent. A draft whose angle is
    /// effectively a no-op (0 / full turn) commits nothing.
    pub fn rotate_draft_commit(&mut self) {
        let d = match self.rotate_draft.take() {
            Some(d) => d,
            None => return,
        };
        let snapped = d.angle.rem_euclid(std::f32::consts::TAU);
        if snapped < 1e-4 || (std::f32::consts::TAU - snapped) < 1e-4 {
            return; // no rotation → no document change, no undo step
        }
        let fi = match self.doc.frame_index_by_id(d.fid) {
            Some(fi) => fi,
            None => return,
        };
        let (cw, ch) = (self.doc.size.w as i32, self.doc.size.h as i32);
        let before = self.doc.frames[fi].clone();
        let rotated_mask = apply_rotation_to_frame(&d, &mut self.doc.frames[fi], cw, ch);
        if let Some(m) = rotated_mask {
            self.doc.selection = Some(Arc::new(m)); // the marquee follows the rotated pixels
        }
        let after = self.doc.frames[fi].clone();
        self.doc.record_frame_content(d.fid, before, after, d.sel_before);
    }

    /// Discard the rotate draft. The document was never touched while it was open, so this just drops
    /// the draft — no restore, no undo step. (Leaving the editor / a crash do the same implicitly.)
    pub fn rotate_draft_cancel(&mut self) {
        self.rotate_draft = None;
    }

    /// A clone of the active frame with the rotate draft applied, for the display preview — or `None`
    /// when no draft is open on the active frame. The document itself is never modified.
    pub(super) fn rotate_draft_preview_frame(&self) -> Option<Frame> {
        let d = self.rotate_draft.as_ref()?;
        let fi = self.doc.active_frame;
        if self.doc.frames[fi].id != d.fid {
            return None;
        }
        let mut frame = self.doc.frames[fi].clone();
        let (cw, ch) = (self.doc.size.w as i32, self.doc.size.h as i32);
        apply_rotation_to_frame(d, &mut frame, cw, ch);
        Some(frame)
    }

    /// Wash the rotated footprint of an open draft with the soft "draft" tint (the preview frame
    /// already carries the rotated pixels at full colour). Used by `draw_tool_preview`.
    pub(super) fn rotate_draft_wash_into(&self, buf: &mut RgbaBuffer) {
        let d = match self.rotate_draft.as_ref().filter(|d| d.fid == self.doc.active_frame().id) {
            Some(d) => d,
            None => return,
        };
        let (cw, ch) = (self.doc.size.w as i32, self.doc.size.h as i32);
        let (out, _mask) = rotate_resample(d, cw, ch);
        let wash = Rgba8::new(0, 200, 255, 60); // soft cyan "draft" wash (matches move/paste)
        for y in 0..ch {
            for x in 0..cw {
                if out.get(x, y).a != 0 {
                    buf.blend_over(x, y, wash);
                }
            }
        }
    }

    /// The rotated selection mask while a selection rotate draft is open (so the marquee follows the
    /// preview), else `None`. Used by `outline_mask`.
    pub(super) fn rotate_draft_outline(&self) -> Option<Mask> {
        let d = self.rotate_draft.as_ref().filter(|d| d.is_selection && d.fid == self.doc.active_frame().id)?;
        let (cw, ch) = (self.doc.size.w as i32, self.doc.size.h as i32);
        let (_out, mask) = rotate_resample(d, cw, ch);
        Some(mask)
    }

    /// The rotate draft's pre-rotation region (top-left + size), if one is open — for the shell to
    /// place the rotate handle and know a draft is active.
    pub(super) fn rotate_draft_rect(&self) -> Option<IRect> {
        let d = self.rotate_draft.as_ref()?;
        Some(IRect::new(d.src_origin.x, d.src_origin.y, d.sw as u32, d.sh as u32))
    }

    /// The rotate draft's current angle in milliradians, if one is open — for the shell's readout.
    pub(super) fn rotate_draft_angle_mrad(&self) -> Option<i32> {
        self.rotate_draft.as_ref().map(|d| (d.angle * 1000.0).round() as i32)
    }
}

/// Nearest-neighbour rotation of the draft's lifted source (a `sw`×`sh` region whose pixel (0,0) sits
/// at `src_origin` in canvas coords; optionally masked by `src_mask`) by `angle` radians clockwise
/// about `pivot`, into a `cw`×`ch` canvas-sized buffer, clipped to the canvas. Returns the placed
/// pixels and a matching 1-bit mask of where they landed. Integer-exact and deterministic: at exact
/// multiples of 90° on a square region it reproduces the lossless quarter-turn.
fn rotate_resample(d: &RotateDraft, cw: i32, ch: i32) -> (RgbaBuffer, Mask) {
    let (src, sw, sh, src_origin, src_mask, pivot, angle) =
        (&d.src, d.sw, d.sh, d.src_origin, d.src_mask.as_ref(), d.pivot, d.angle);
    let mut out = RgbaBuffer::new(cw as u32, ch as u32);
    let mut out_mask = Mask::new(cw as u32, ch as u32);
    let (cos, sin) = (angle.cos(), angle.sin());

    // Destination scan window = the canvas-clipped bounding box of the rotated source corners, so we
    // touch only pixels that can possibly receive content.
    let fwd = |px: f32, py: f32| {
        let (dx, dy) = (px - pivot.x, py - pivot.y);
        (pivot.x + cos * dx - sin * dy, pivot.y + sin * dx + cos * dy)
    };
    let (mut minx, mut miny, mut maxx, mut maxy) = (f32::MAX, f32::MAX, f32::MIN, f32::MIN);
    for (px, py) in [
        (src_origin.x as f32, src_origin.y as f32),
        ((src_origin.x + sw) as f32, src_origin.y as f32),
        (src_origin.x as f32, (src_origin.y + sh) as f32),
        ((src_origin.x + sw) as f32, (src_origin.y + sh) as f32),
    ] {
        let (fx, fy) = fwd(px, py);
        minx = minx.min(fx);
        miny = miny.min(fy);
        maxx = maxx.max(fx);
        maxy = maxy.max(fy);
    }
    let x0 = (minx.floor() as i32).max(0);
    let y0 = (miny.floor() as i32).max(0);
    let x1 = (maxx.ceil() as i32).min(cw);
    let y1 = (maxy.ceil() as i32).min(ch);

    for dy in y0..y1 {
        for dx in x0..x1 {
            // Inverse-rotate the destination pixel centre back into source space (R(-angle)).
            let (ddx, ddy) = (dx as f32 + 0.5 - pivot.x, dy as f32 + 0.5 - pivot.y);
            let sxf = pivot.x + cos * ddx + sin * ddy;
            let syf = pivot.y - sin * ddx + cos * ddy;
            let lx = (sxf - src_origin.x as f32).floor() as i32;
            let ly = (syf - src_origin.y as f32).floor() as i32;
            if lx < 0 || ly < 0 || lx >= sw || ly >= sh {
                continue;
            }
            // The mask follows the rotated *region* (every masked source cell), independent of pixel
            // opacity — so a selection's marquee rotates as a whole, not just its opaque pixels.
            if let Some(m) = src_mask {
                if !m.get(lx, ly) {
                    continue;
                }
            }
            out_mask.set(dx, dy, true);
            // The pixel buffer only carries opaque content (transparent source leaves a hole).
            let c = src.get(lx, ly);
            if c.a != 0 {
                out.set(dx, dy, c);
            }
        }
    }
    (out, out_mask)
}

/// Apply a rotate draft to `frame`: clear the origin pixels (the selected pixels, or the whole layer
/// for a layer rotation) and blit the resampled, rotated content alpha-over. Shared by the display
/// preview (on a throwaway clone) and `rotate_draft_commit` (on the real frame) so both render
/// identically. Returns the rotated selection mask for a selection rotation, else `None`.
fn apply_rotation_to_frame(d: &RotateDraft, frame: &mut Frame, cw: i32, ch: i32) -> Option<Mask> {
    let li = frame.layer_index_by_id(d.lid)?;
    let (out, out_mask) = rotate_resample(d, cw, ch);
    let buf = &mut frame.layers[li].pixels;
    // Clear the origin: the masked pixels for a selection rotation, the whole layer otherwise.
    if d.is_selection {
        if let Some(m) = d.sel_before.as_deref() {
            for y in 0..ch {
                for x in 0..cw {
                    if m.get(x, y) {
                        buf.set(x, y, Rgba8::TRANSPARENT);
                    }
                }
            }
        }
    } else {
        buf.clear();
    }
    // Place the rotated content (alpha-over, so it composites onto any pixels left behind).
    for y in 0..ch {
        for x in 0..cw {
            let c = out.get(x, y);
            if c.a != 0 {
                buf.blend_over(x, y, c);
            }
        }
    }
    if d.is_selection {
        Some(out_mask)
    } else {
        None
    }
}
