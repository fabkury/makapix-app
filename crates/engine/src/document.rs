//! The document model: `Document` → `Frame` → `Layer`, plus palettes and animation
//! settings (SPEC §7, §14, §15). Frames are **pure content** (history lives at the
//! document level, §10) so structural snapshots are copy-on-write cheap.

use crate::buffer::RgbaBuffer;
use crate::color::Rgba8;
use crate::geom::{IRect, Point, Size};
use crate::history::History;
use crate::selection::Mask;
use crate::util::{Hash, Hasher, IdGen};
use std::sync::Arc;

pub const MAX_FRAMES: usize = 1024;
pub const MAX_LAYERS: usize = 64;
pub const MIN_DURATION_US: u32 = 16_667; // ≈ 1/60 s
pub const MAX_DURATION_US: u32 = 1_000_000; // 1000 ms
pub const DEFAULT_DURATION_US: u32 = 100_000; // 100 ms

#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum BlendMode {
    #[default]
    Normal,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum LoopMode {
    #[default]
    Loop,
    Once,
    PingPong,
}

#[derive(Clone, Copy, Debug, Default)]
pub struct AnimSettings {
    pub loop_mode: LoopMode,
}

#[derive(Clone)]
pub struct Layer {
    pub id: u32,
    pub name: String,
    pub visible: bool,
    pub locked: bool,
    pub opacity: u8,
    pub blend: BlendMode,
    pub pixels: RgbaBuffer,
}

impl Layer {
    pub fn new(id: u32, size: Size, name: impl Into<String>) -> Self {
        Layer {
            id,
            name: name.into(),
            visible: true,
            locked: false,
            opacity: 255,
            blend: BlendMode::Normal,
            pixels: RgbaBuffer::from_size(size),
        }
    }
    pub fn content_hash(&self) -> Hash {
        let mut h = Hasher::new();
        h.write(self.name.as_bytes());
        h.write(&[self.visible as u8, self.locked as u8, self.opacity]);
        let ph = self.pixels.content_hash();
        h.write(&ph.to_le_bytes());
        h.finish()
    }
}

#[derive(Clone)]
pub struct Frame {
    pub id: u32,
    pub duration_us: u32,
    pub layers: Vec<Layer>,
    pub active_layer: usize,
}

impl Frame {
    pub fn content_hash(&self) -> Hash {
        let mut h = Hasher::new();
        h.write_u32(self.duration_us);
        for l in &self.layers {
            h.write(&l.content_hash().to_le_bytes());
        }
        h.finish()
    }
    pub fn active_layer(&self) -> &Layer {
        &self.layers[self.active_layer]
    }
    pub fn active_layer_mut(&mut self) -> &mut Layer {
        &mut self.layers[self.active_layer]
    }
    pub fn layer(&self, i: usize) -> &Layer {
        &self.layers[i]
    }
    pub fn layer_mut(&mut self, i: usize) -> &mut Layer {
        &mut self.layers[i]
    }
    pub fn layer_index_by_id(&self, id: u32) -> Option<usize> {
        self.layers.iter().position(|l| l.id == id)
    }
}

#[derive(Clone)]
pub struct Palette {
    pub name: String,
    pub colors: Vec<Rgba8>,
}

impl Palette {
    pub fn default_palette() -> Palette {
        // A compact, useful default ramp (DawnBringer-ish 16).
        let hex = [
            "#140c1c", "#442434", "#30346d", "#4e4a4e", "#854c30", "#346524", "#d04648", "#757161",
            "#597dce", "#d27d2c", "#8595a1", "#6daa2c", "#d2aa99", "#6dc2ca", "#dad45e", "#deeed6",
        ];
        Palette {
            name: "Default".into(),
            colors: hex.iter().filter_map(|h| Rgba8::from_hex(h)).collect(),
        }
    }
}

pub struct Document {
    /// The **canvas**: the editable, exported, user-facing dimensions (1..=256). This is what
    /// almost every site means by "size". Distinct from [`storage`](Self::storage), which also
    /// includes the off-canvas **gutter** where moved pixels are preserved (SPEC §8, §15).
    pub size: Size,
    pub frames: Vec<Frame>,
    pub active_frame: usize,
    pub palettes: Vec<Palette>,
    pub active_palette: usize,
    pub anim: AnimSettings,
    pub history: History,
    pub frame_ids: IdGen,
    pub layer_ids: IdGen,
    /// The current selection mask, document-sized (its `w/h` always match `size`). `None` means
    /// "no selection" (ops act on the whole layer). Invariant: `Some` always holds a **non-empty**
    /// mask — writers normalize an all-clear result to `None` via [`Mask::nonempty`], so "zero
    /// pixels selected" and "no selection" are one state. Promoted from editor state into the document so
    /// it participates in undo/redo (each [`History`] record carries the mask transition) and in
    /// `.mkpx` serialization (crash safety). COW-shared via `Arc`: a pixel-only edit reuses the same
    /// `Arc` for its before/after snapshot, so recording it costs only a pointer clone. The combine
    /// *mode* (Replace/Add/…) stays on `Session` as a transient tool setting — not persisted/undone.
    pub selection: Option<Arc<Mask>>,
}

impl Document {
    pub fn new(w: u16, h: u16) -> Document {
        let size = Size::new(w, h);
        let margin = Document::gutter_for(size);
        let storage = Size::new(size.w + 2 * margin.w, size.h + 2 * margin.h);
        let mut frame_ids = IdGen::default();
        let mut layer_ids = IdGen::default();
        let l0 = Layer::new(layer_ids.alloc(), storage, "Layer 1");
        let f0 = Frame {
            id: frame_ids.alloc(),
            duration_us: DEFAULT_DURATION_US,
            layers: vec![l0],
            active_layer: 0,
        };
        Document {
            size,
            frames: vec![f0],
            active_frame: 0,
            palettes: vec![Palette::default_palette()],
            active_palette: 0,
            anim: AnimSettings::default(),
            history: History::new(),
            frame_ids,
            layer_ids,
            selection: None,
        }
    }

    // ---- canvas ↔ storage geometry (SPEC §8) ----

    /// The gutter kept on each side of a canvas of the given size: a **full canvas** on every side,
    /// giving a `3w × 3h` storage area. Pixels moved off the canvas are preserved anywhere in this
    /// area (SPEC §8, §15). Centralised here so the whole engine derives the gutter one way — set it
    /// back to `(0,0)` to disable the feature everywhere.
    pub fn gutter_for(size: Size) -> Size {
        size
    }

    /// The gutter kept on each side of the current canvas. **Derived** from the canvas size (never
    /// stored), so it can never desync — undo/redo restore only `size` and the gutter follows. [F: undo]
    pub fn margin(&self) -> Size {
        Document::gutter_for(self.size)
    }

    /// Canvas top-left within the storage buffers (= the per-side gutter). Add this to a canvas
    /// coordinate to reach the storage/tile coordinate a layer buffer is indexed by.
    pub fn origin(&self) -> Point {
        let m = self.margin();
        Point::new(m.w as i32, m.h as i32)
    }

    /// Full storage dimensions of every layer buffer: `canvas + 2·gutter`.
    pub fn storage(&self) -> Size {
        let m = self.margin();
        Size::new(self.size.w + 2 * m.w, self.size.h + 2 * m.h)
    }

    /// The canvas window expressed in storage/tile coordinates — the region tools may edit and the
    /// default source rect for compositing, display, thumbnails and export.
    pub fn canvas_rect(&self) -> IRect {
        IRect::new(self.origin().x, self.origin().y, self.size.w as u32, self.size.h as u32)
    }

    /// The whole storage area (canvas + gutter) in storage coordinates — the source rect for the
    /// overscan display.
    pub fn storage_rect(&self) -> IRect {
        IRect::from_size(self.storage())
    }

    /// Change the canvas size and re-derive the gutter/storage from it (the canvas transforms call
    /// this, then rebuild every layer buffer at the new [`storage`](Self::storage) size).
    pub fn set_canvas_size(&mut self, new_size: Size) {
        self.size = new_size; // the gutter/storage is derived from `size`, so nothing else to update
    }

    // ---- accessors ----

    pub fn frame(&self, i: usize) -> &Frame {
        &self.frames[i]
    }
    pub fn frame_mut(&mut self, i: usize) -> &mut Frame {
        &mut self.frames[i]
    }
    pub fn active_frame(&self) -> &Frame {
        &self.frames[self.active_frame]
    }
    pub fn active_frame_mut(&mut self) -> &mut Frame {
        let i = self.active_frame;
        &mut self.frames[i]
    }
    pub fn frame_index_by_id(&self, id: u32) -> Option<usize> {
        self.frames.iter().position(|f| f.id == id)
    }
    pub fn palette(&self) -> &Palette {
        &self.palettes[self.active_palette]
    }
    pub fn palette_mut(&mut self) -> &mut Palette {
        let i = self.active_palette;
        &mut self.palettes[i]
    }

    pub fn content_hash(&self) -> Hash {
        let mut h = Hasher::new();
        h.write_u32(self.size.w as u32);
        h.write_u32(self.size.h as u32);
        for f in &self.frames {
            h.write(&f.content_hash().to_le_bytes());
        }
        h.finish()
    }

    /// Total resident bytes of all layer buffers (SPEC §8.2 accounting).
    pub fn memory_bytes(&self) -> usize {
        self.frames
            .iter()
            .flat_map(|f| f.layers.iter())
            .map(|l| l.pixels.memory_bytes())
            .sum()
    }

    pub fn new_layer(&mut self, name: impl Into<String>) -> Layer {
        Layer::new(self.layer_ids.alloc(), self.storage(), name)
    }

    pub fn new_frame_id(&mut self) -> u32 {
        self.frame_ids.alloc()
    }

    pub fn clamp_duration(us: u32) -> u32 {
        us.clamp(MIN_DURATION_US, MAX_DURATION_US)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn new_document_has_one_frame_one_layer() {
        let d = Document::new(32, 32);
        assert_eq!(d.frames.len(), 1);
        assert_eq!(d.active_frame().layers.len(), 1);
        assert_eq!(d.active_frame().duration_us, DEFAULT_DURATION_US);
        assert!(!d.palette().colors.is_empty());
    }

    #[test]
    fn ids_are_unique() {
        let mut d = Document::new(16, 16);
        let a = d.new_layer("a").id;
        let b = d.new_layer("b").id;
        assert_ne!(a, b);
    }
}
