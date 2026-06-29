//! Canvas-level transforms — flip / rotate / resize / crop (SPEC §28.1). Split out of the
//! `session` god-file along the same `impl Session` seam `mod parse` already uses, so the methods
//! still share `Session`'s private state (begin_edit/commit_edit/edit_doc, doc, selection). [audit F-17]

use super::Session;
use crate::buffer::RgbaBuffer;
use crate::geom::Size;

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
}
