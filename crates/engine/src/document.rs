//! The document model: `Document` → `Frame` → `Layer`, plus palettes and animation
//! settings (SPEC §7, §14, §15). Frames are **pure content** (history lives at the
//! document level, §10) so structural snapshots are copy-on-write cheap.

use crate::buffer::RgbaBuffer;
use crate::color::Rgba8;
use crate::geom::Size;
use crate::history::History;
use crate::util::{Hash, Hasher, IdGen};

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
    pub size: Size,
    pub frames: Vec<Frame>,
    pub active_frame: usize,
    pub palettes: Vec<Palette>,
    pub active_palette: usize,
    pub anim: AnimSettings,
    pub history: History,
    pub frame_ids: IdGen,
    pub layer_ids: IdGen,
}

impl Document {
    pub fn new(w: u16, h: u16) -> Document {
        let size = Size::new(w, h);
        let mut frame_ids = IdGen::default();
        let mut layer_ids = IdGen::default();
        let l0 = Layer::new(layer_ids.alloc(), size, "Layer 1");
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
        }
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
        Layer::new(self.layer_ids.alloc(), self.size, name)
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
