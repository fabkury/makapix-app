//! `.mkpx` container: state-based, chunked, versioned, little-endian, sparse tiles
//! (SPEC §17). Dependency-free; lossless. `load(save(doc))` is a round-trip invariant.

use crate::buffer::RgbaBuffer;
use crate::document::{AnimSettings, BlendMode, Document, Frame, Layer, LoopMode, Palette};
use crate::geom::Size;
use crate::util::IdGen;

pub const MAGIC: &[u8; 4] = b"MKPX";
/// v1 = raw tiles; v2 = per-tile RLE-compressed tiles (SPEC §17.1, §28.8). We write v2 and
/// still read v1 for forward/backward compatibility.
pub const FORMAT_VERSION: u16 = 2;
const TILE_BYTES: usize = 32 * 32 * 4;

/// RLE-encode one 4096-byte tile as `(run:u16, pixel:[u8;4])*` over its 1024 pixels.
fn rle_encode_tile(bytes: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    let px = |i: usize| &bytes[i * 4..i * 4 + 4];
    let mut i = 0usize;
    while i < 1024 {
        let start = i;
        while i + 1 < 1024 && px(i + 1) == px(start) && (i - start) < 65534 {
            i += 1;
        }
        let run = (i - start + 1) as u16;
        out.extend_from_slice(&run.to_le_bytes());
        out.extend_from_slice(px(start));
        i += 1;
    }
    out
}

#[derive(Debug)]
pub enum IoError {
    BadMagic,
    UnsupportedVersion(u16),
    Truncated,
    Corrupt(&'static str),
}

impl std::fmt::Display for IoError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            IoError::BadMagic => write!(f, "not a .mkpx file (bad magic)"),
            IoError::UnsupportedVersion(v) => write!(f, "unsupported .mkpx version {}", v),
            IoError::Truncated => write!(f, "file truncated"),
            IoError::Corrupt(s) => write!(f, "corrupt .mkpx: {}", s),
        }
    }
}

struct Writer {
    buf: Vec<u8>,
}
impl Writer {
    fn new() -> Self {
        Writer { buf: Vec::new() }
    }
    fn u8(&mut self, v: u8) {
        self.buf.push(v);
    }
    fn u16(&mut self, v: u16) {
        self.buf.extend_from_slice(&v.to_le_bytes());
    }
    fn u32(&mut self, v: u32) {
        self.buf.extend_from_slice(&v.to_le_bytes());
    }
    fn bytes(&mut self, b: &[u8]) {
        self.buf.extend_from_slice(b);
    }
    fn string(&mut self, s: &str) {
        let b = s.as_bytes();
        self.u16(b.len().min(u16::MAX as usize) as u16);
        self.bytes(&b[..b.len().min(u16::MAX as usize)]);
    }
}

struct Reader<'a> {
    buf: &'a [u8],
    pos: usize,
}
impl<'a> Reader<'a> {
    fn new(buf: &'a [u8]) -> Self {
        Reader { buf, pos: 0 }
    }
    fn u8(&mut self) -> Result<u8, IoError> {
        let v = *self.buf.get(self.pos).ok_or(IoError::Truncated)?;
        self.pos += 1;
        Ok(v)
    }
    fn u16(&mut self) -> Result<u16, IoError> {
        let s = self.buf.get(self.pos..self.pos + 2).ok_or(IoError::Truncated)?;
        self.pos += 2;
        Ok(u16::from_le_bytes([s[0], s[1]]))
    }
    fn u32(&mut self) -> Result<u32, IoError> {
        let s = self.buf.get(self.pos..self.pos + 4).ok_or(IoError::Truncated)?;
        self.pos += 4;
        Ok(u32::from_le_bytes([s[0], s[1], s[2], s[3]]))
    }
    fn take(&mut self, n: usize) -> Result<&'a [u8], IoError> {
        let s = self.buf.get(self.pos..self.pos + n).ok_or(IoError::Truncated)?;
        self.pos += n;
        Ok(s)
    }
    fn string(&mut self) -> Result<String, IoError> {
        let n = self.u16()? as usize;
        let s = self.take(n)?;
        Ok(String::from_utf8_lossy(s).into_owned())
    }
    /// Decode one RLE-compressed tile, consuming exactly its bytes (terminates at 1024 px).
    fn rle_tile(&mut self) -> Result<Vec<u8>, IoError> {
        let mut out = Vec::with_capacity(TILE_BYTES);
        let mut pixels = 0usize;
        while pixels < 1024 {
            let run = self.u16()? as usize;
            let p = self.take(4)?.to_vec();
            if run == 0 || pixels + run > 1024 {
                return Err(IoError::Corrupt("bad RLE run"));
            }
            for _ in 0..run {
                out.extend_from_slice(&p);
            }
            pixels += run;
        }
        Ok(out)
    }
}

fn loop_mode_to_u8(m: LoopMode) -> u8 {
    match m {
        LoopMode::Loop => 0,
        LoopMode::Once => 1,
        LoopMode::PingPong => 2,
    }
}
fn loop_mode_from_u8(v: u8) -> LoopMode {
    match v {
        1 => LoopMode::Once,
        2 => LoopMode::PingPong,
        _ => LoopMode::Loop,
    }
}

pub fn save_to_bytes(doc: &Document) -> Vec<u8> {
    let mut w = Writer::new();
    w.bytes(MAGIC);
    w.u16(FORMAT_VERSION);
    w.u16(0); // flags
    w.u16(doc.size.w);
    w.u16(doc.size.h);
    w.u32(doc.active_frame as u32);
    w.u8(loop_mode_to_u8(doc.anim.loop_mode));

    // palettes
    w.u16(doc.palettes.len() as u16);
    w.u16(doc.active_palette as u16);
    for p in &doc.palettes {
        w.string(&p.name);
        w.u16(p.colors.len() as u16);
        for c in &p.colors {
            w.bytes(&[c.r, c.g, c.b, c.a]);
        }
    }

    // frames
    w.u32(doc.frames.len() as u32);
    for f in &doc.frames {
        w.u32(f.id);
        w.u32(f.duration_us);
        w.u32(f.active_layer as u32);
        w.u16(f.layers.len() as u16);
        for l in &f.layers {
            w.u32(l.id);
            w.string(&l.name);
            let flags = (l.visible as u8) | ((l.locked as u8) << 1);
            w.u8(flags);
            w.u8(l.opacity);
            w.u8(0); // blend = Normal
            let nt = l.pixels.num_tiles();
            w.u32(nt as u32);
            for i in 0..nt {
                match l.pixels.tile_bytes(i) {
                    None => w.u8(0),
                    Some(b) => {
                        w.u8(1);
                        w.bytes(&rle_encode_tile(&b)); // v2: RLE-compressed
                    }
                }
            }
        }
    }

    // footer: content hash for integrity
    let h = doc.content_hash();
    w.bytes(&h.to_le_bytes());
    w.buf
}

pub fn load_from_bytes(data: &[u8]) -> Result<Document, IoError> {
    let mut r = Reader::new(data);
    if r.take(4)? != MAGIC {
        return Err(IoError::BadMagic);
    }
    let version = r.u16()?;
    if version != 1 && version != 2 {
        return Err(IoError::UnsupportedVersion(version));
    }
    let _flags = r.u16()?;
    let w = r.u16()?;
    let h = r.u16()?;
    let size = Size::new(w, h);
    if !size.in_range() {
        return Err(IoError::Corrupt("canvas size out of range"));
    }
    let active_frame = r.u32()? as usize;
    let loop_mode = loop_mode_from_u8(r.u8()?);

    let pal_count = r.u16()? as usize;
    let active_palette = r.u16()? as usize;
    let mut palettes = Vec::with_capacity(pal_count);
    for _ in 0..pal_count {
        let name = r.string()?;
        let cc = r.u16()? as usize;
        let mut colors = Vec::with_capacity(cc);
        for _ in 0..cc {
            let b = r.take(4)?;
            colors.push(crate::Rgba8::new(b[0], b[1], b[2], b[3]));
        }
        palettes.push(Palette { name, colors });
    }
    if palettes.is_empty() {
        palettes.push(Palette::default_palette());
    }

    let frame_count = r.u32()? as usize;
    if frame_count > crate::document::MAX_FRAMES {
        return Err(IoError::Corrupt("too many frames"));
    }
    let mut frames = Vec::with_capacity(frame_count);
    let mut max_frame_id = 0u32;
    let mut max_layer_id = 0u32;
    for _ in 0..frame_count {
        let id = r.u32()?;
        max_frame_id = max_frame_id.max(id);
        let duration_us = Document::clamp_duration(r.u32()?);
        let active_layer = r.u32()? as usize;
        let layer_count = r.u16()? as usize;
        if layer_count == 0 || layer_count > crate::document::MAX_LAYERS {
            return Err(IoError::Corrupt("bad layer count"));
        }
        let mut layers = Vec::with_capacity(layer_count);
        for _ in 0..layer_count {
            let lid = r.u32()?;
            max_layer_id = max_layer_id.max(lid);
            let name = r.string()?;
            let flags = r.u8()?;
            let opacity = r.u8()?;
            let _blend = r.u8()?;
            let mut pixels = RgbaBuffer::from_size(size);
            let nt = r.u32()? as usize;
            if nt != pixels.num_tiles() {
                return Err(IoError::Corrupt("tile count mismatch"));
            }
            for i in 0..nt {
                if r.u8()? == 1 {
                    if version == 1 {
                        let b = r.take(TILE_BYTES)?.to_vec();
                        pixels.put_tile_bytes(i, &b);
                    } else {
                        let b = r.rle_tile()?;
                        pixels.put_tile_bytes(i, &b);
                    }
                }
            }
            layers.push(Layer {
                id: lid,
                name,
                visible: flags & 1 != 0,
                locked: flags & 2 != 0,
                opacity,
                blend: BlendMode::Normal,
                pixels,
            });
        }
        let active_layer = active_layer.min(layers.len() - 1);
        frames.push(Frame { id, duration_us, layers, active_layer });
    }
    if frames.is_empty() {
        return Err(IoError::Corrupt("no frames"));
    }

    // Seed the id generators just past the highest persisted id — directly, never by looping up to
    // it: a crafted id like 0xFFFFFFFF would otherwise hang the loader for billions of allocs. [F-2]
    let frame_ids = IdGen::starting_at(max_frame_id.saturating_add(1));
    let layer_ids = IdGen::starting_at(max_layer_id.saturating_add(1));

    Ok(Document {
        size,
        active_frame: active_frame.min(frames.len() - 1),
        frames,
        palettes,
        active_palette: active_palette.min(pal_count.saturating_sub(1)),
        anim: AnimSettings { loop_mode },
        history: crate::history::History::new(),
        frame_ids,
        layer_ids,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Rgba8;

    #[test]
    fn roundtrip_empty_document() {
        let doc = Document::new(32, 24);
        let bytes = save_to_bytes(&doc);
        let back = load_from_bytes(&bytes).unwrap();
        assert_eq!(doc.content_hash(), back.content_hash());
        assert_eq!(back.size, doc.size);
    }

    #[test]
    fn roundtrip_with_content() {
        let mut doc = Document::new(64, 64);
        doc.active_frame_mut().active_layer_mut().pixels.set(10, 10, Rgba8::WHITE);
        doc.active_frame_mut().active_layer_mut().pixels.set(40, 50, Rgba8::rgb(1, 2, 3));
        let top = doc.new_layer("top");
        doc.active_frame_mut().layers.push(top);
        doc.active_frame_mut().layers[1].opacity = 128;
        doc.active_frame_mut().layers[1].pixels.set(20, 20, Rgba8::rgb(9, 8, 7));
        let f2 = Frame {
            id: doc.new_frame_id(),
            duration_us: 50_000,
            layers: vec![doc.new_layer("f2")],
            active_layer: 0,
        };
        doc.frames.push(f2);

        let bytes = save_to_bytes(&doc);
        let back = load_from_bytes(&bytes).unwrap();
        assert_eq!(doc.content_hash(), back.content_hash());
        assert_eq!(back.frames.len(), 2);
        assert_eq!(back.frames[0].layers[1].opacity, 128);
        assert_eq!(back.frames[1].duration_us, 50_000);
    }

    #[test]
    fn rejects_bad_magic() {
        assert!(matches!(load_from_bytes(b"XXXX...."), Err(IoError::BadMagic)));
    }

    #[test]
    fn rle_compresses_flat_content() {
        // A 256x256 layer flat-filled with one color should compress massively (RLE).
        let mut doc = Document::new(256, 256);
        doc.active_frame_mut().active_layer_mut().pixels.fill_all(Rgba8::rgb(20, 40, 60));
        let bytes = save_to_bytes(&doc);
        let raw = 256 * 256 * 4; // one full uncompressed layer
        assert!(bytes.len() < raw / 10, "compressed {} vs raw {}", bytes.len(), raw);
        // and it still round-trips exactly
        let back = load_from_bytes(&bytes).unwrap();
        assert_eq!(back.content_hash(), doc.content_hash());
    }
}
