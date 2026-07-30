//! `.mkpx` **v10** container: typed-chunk, little-endian, content-addressed tile dictionary +
//! per-layer RLE tile-ref grids, per-tile codec menu (`RAW`/`RLE`/`INDEXED`) with a RAW floor,
//! whole-file CRC-32C + a verified `content_hash`. Byte-deterministic; lossless; dependency-free.
//! `load(save(doc))` is a round-trip invariant (by `content_hash`). This is the **`plain`** profile;
//! the optional DEFLATE **`compact`** envelope lives at the periphery (see `docs/mkpx-format/`).

pub mod container;

use crate::buffer::RgbaBuffer;
use crate::document::{AnimSettings, BlendMode, Document, Frame, Layer, LoopMode, Palette};
use crate::geom::Size;
use crate::selection::Mask;
use crate::util::IdGen;
use container::{
    finish_intg, read_ref_grid, read_tile_dict, verify_intg, write_chunk, Reader, TileDict, Writer,
};
pub use container::IoError;
use std::sync::Arc;

/// The `plain`-profile file signature (8 bytes, PNG-style hardened): high bit, `MKPX`, CR, LF, EOF.
pub const SIGNATURE: [u8; 8] = [0x89, b'M', b'K', b'P', b'X', 0x0D, 0x0A, 0x1A];
pub const FORMAT_VERSION: u16 = 10;

const MAX_DICT_TILES: usize = 1 << 24;
/// Largest legal packed selection: a 768×768 storage plane = 589824 bits = 73728 bytes.
const MAX_SEL_BYTES: usize = (768 * 768) / 8;

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

// ---- selection (bbox-packed) ----

fn encode_selection(mask: &Mask) -> Vec<u8> {
    let mut w = Writer::new();
    match mask.bounds() {
        None => w.u8(2), // EMPTY
        Some(bb) => {
            let (bx, by, bw, bh) = (bb.x, bb.y, bb.w, bb.h);
            let mut full = true;
            'scan: for dy in 0..bh as i32 {
                for dx in 0..bw as i32 {
                    if !mask.get(bx + dx, by + dy) {
                        full = false;
                        break 'scan;
                    }
                }
            }
            w.u8(if full { 0 } else { 1 });
            w.u16(bx as u16);
            w.u16(by as u16);
            w.u16(bw as u16);
            w.u16(bh as u16);
            if !full {
                let total = (bw * bh) as usize;
                let mut bits = vec![0u8; total.div_ceil(8)];
                for k in 0..total {
                    let dx = (k as u32 % bw) as i32;
                    let dy = (k as u32 / bw) as i32;
                    if mask.get(bx + dx, by + dy) {
                        bits[k / 8] |= 1 << (k % 8);
                    }
                }
                w.bytes(&bits);
            }
        }
    }
    w.into_bytes()
}

/// Decode `SELC`; a bbox outside the storage area (stale/crafted) drops the selection (not fatal).
fn decode_selection(pl: &[u8], storage: Size) -> Result<Option<Arc<Mask>>, IoError> {
    let mut r = Reader::new(pl);
    let (sw, sh) = (storage.w as u32, storage.h as u32);
    match r.u8()? {
        // EMPTY (legacy files): zero pixels selected == no selection (Document::selection invariant).
        2 => Ok(None),
        tag @ (0 | 1) => {
            let bx = r.u16()? as u32;
            let by = r.u16()? as u32;
            let bw = r.u16()? as u32;
            let bh = r.u16()? as u32;
            if bx + bw > sw || by + bh > sh {
                return Ok(None); // stale/out-of-range → drop, keep the document
            }
            let mut m = Mask::new(sw, sh);
            if tag == 0 {
                for dy in 0..bh as i32 {
                    for dx in 0..bw as i32 {
                        m.set(bx as i32 + dx, by as i32 + dy, true);
                    }
                }
            } else {
                let total = (bw * bh) as usize;
                let nbytes = total.div_ceil(8);
                if nbytes > MAX_SEL_BYTES {
                    return Err(IoError::TooLarge("selection"));
                }
                let data = r.take(nbytes)?;
                for k in 0..total {
                    if data[k / 8] & (1 << (k % 8)) != 0 {
                        let dx = (k as u32 % bw) as i32;
                        let dy = (k as u32 / bw) as i32;
                        m.set(bx as i32 + dx, by as i32 + dy, true);
                    }
                }
            }
            Ok(m.nonempty().map(Arc::new)) // a crafted all-zero BITS payload is "no selection" too
        }
        _ => Err(IoError::Corrupt("selection tag")),
    }
}

pub fn save_to_bytes(doc: &Document) -> Vec<u8> {
    let canvas = doc.size;
    let margin = Document::gutter_for(canvas);

    // Dictionary: distinct present tiles, first-appearance order (frames→layers→cells), via the
    // shared `container::TileDict` (two-level Arc-pointer + verified-hash lookup — see there).
    // Per-layer reference grids are computed in the same pass so FRMS below reuses them instead
    // of re-cloning every tile for a map lookup (the second former full-clone pass).
    let mut dict = TileDict::new();
    let mut grids: Vec<Vec<u32>> = Vec::new();
    for f in &doc.frames {
        for l in &f.layers {
            grids.push(dict.grid_for(&l.pixels));
        }
    }

    // HEAD
    let mut head = Writer::new();
    head.u16(FORMAT_VERSION);
    head.u16(canvas.w);
    head.u16(canvas.h);
    head.u16(margin.w); // gutter left/top/right/bottom (full runtime gutter)
    head.u16(margin.h);
    head.u16(margin.w);
    head.u16(margin.h);
    head.u32(doc.frames.len() as u32);
    head.u16(doc.active_frame as u16);
    head.u16(if doc.palettes.is_empty() { 0xFFFF } else { doc.active_palette as u16 });
    head.u8(loop_mode_to_u8(doc.anim.loop_mode));
    head.u8(doc.selection.is_some() as u8); // head_flags bit0 = has SELC
    head.u128(doc.content_hash());

    // TILE — one 4096-byte temp per entry, encoded and dropped; never the whole set at once.
    // Pre-sized inside `TileDict::write` (memlab M5) — under the document budget the
    // reservation is ≤ ~340 MiB and effectively infallible.
    let mut tile = Writer::new();
    dict.write(&mut tile);

    // FRMS — ref-grids precomputed during the dictionary pass, same frames→layers order.
    let mut frms = Writer::new();
    frms.varint(doc.frames.len() as u32);
    let mut grid_iter = grids.iter();
    for f in &doc.frames {
        frms.u32(f.id);
        frms.u32(f.duration_us);
        frms.u16(f.active_layer as u16);
        frms.u16(f.layers.len() as u16);
        for l in &f.layers {
            frms.u32(l.id);
            frms.str(&l.name);
            frms.u8((l.visible as u8) | ((l.locked as u8) << 1));
            frms.u8(l.opacity);
            frms.u8(0); // blend = Normal
            let grid = grid_iter.next().expect("one grid per layer");
            container::write_ref_grid(&mut frms, grid);
        }
    }

    // Assemble: signature, critical chunks, optional chunks, then INTG (whole-file CRC).
    // Pre-sized to the known chunk payloads so the final buffer never doubles past the file size.
    let mut w = Writer::new();
    w.reserve_exact(head.len() + tile.len() + frms.len() + 64 * 1024);
    w.bytes(&SIGNATURE);
    write_chunk(&mut w, b"HEAD", true, head.as_bytes());
    write_chunk(&mut w, b"TILE", true, tile.as_bytes());
    write_chunk(&mut w, b"FRMS", true, frms.as_bytes());

    if !doc.palettes.is_empty() {
        let mut upal = Writer::new();
        upal.varint(doc.palettes.len() as u32);
        for p in &doc.palettes {
            upal.str(&p.name);
            upal.u16(p.colors.len() as u16);
            for c in &p.colors {
                upal.bytes(&[c.r, c.g, c.b, c.a]);
            }
        }
        write_chunk(&mut w, b"UPAL", false, upal.as_bytes());
        // UPCN: optional per-entry color names, mirroring UPAL's shape (palette count, then per
        // palette a u16 entry count + one string per entry, "" = unnamed). A separate
        // non-critical chunk — not folded into UPAL — so older builds keep opening new files
        // (they skip unknown ancillary chunks); only written when at least one name exists.
        if doc.palettes.iter().any(|p| p.color_names.iter().any(|n| n.is_some())) {
            let mut upcn = Writer::new();
            upcn.varint(doc.palettes.len() as u32);
            for p in &doc.palettes {
                upcn.u16(p.color_names.len() as u16);
                for n in &p.color_names {
                    upcn.str(n.as_deref().unwrap_or(""));
                }
            }
            write_chunk(&mut w, b"UPCN", false, upcn.as_bytes());
        }
    }
    if let Some(mask) = &doc.selection {
        write_chunk(&mut w, b"SELC", false, &encode_selection(mask));
    }

    finish_intg(&mut w);
    w.into_bytes()
}

struct Chunks<'a> {
    head: Option<&'a [u8]>,
    tile: Option<&'a [u8]>,
    frms: Option<&'a [u8]>,
    upal: Option<&'a [u8]>,
    upcn: Option<&'a [u8]>,
    selc: Option<&'a [u8]>,
}

/// Single forward walk of `[8 .. body_end]` (via `container::walk_chunks`, which owns the
/// framing); this visitor enforces `HEAD` first + one-of each critical, skips the known
/// ancillary chunks, and rejects unknown critical ones.
fn mkpx_chunks<'a>(data: &'a [u8], body_end: usize) -> Result<Chunks<'a>, IoError> {
    let mut c = Chunks { head: None, tile: None, frms: None, upal: None, upcn: None, selc: None };
    container::walk_chunks(data, body_end, b"HEAD", "HEAD not first", |fourcc, critical, payload| {
        let slot = match fourcc {
            b"HEAD" => &mut c.head,
            b"TILE" => &mut c.tile,
            b"FRMS" => &mut c.frms,
            b"UPAL" => &mut c.upal,
            b"UPCN" => &mut c.upcn,
            b"SELC" => &mut c.selc,
            b"THMB" | b"META" => return Ok(()), // ancillary, not used by the engine core
            _ => {
                if critical {
                    return Err(IoError::UnsupportedChunk(*fourcc));
                }
                return Ok(()); // unknown ancillary → skip
            }
        };
        if slot.is_some() {
            return Err(IoError::Corrupt("duplicate chunk"));
        }
        *slot = Some(payload);
        Ok(())
    })?;
    Ok(c)
}

pub fn load_from_bytes(data: &[u8]) -> Result<Document, IoError> {
    load_from_bytes_budgeted(data, crate::document::MEM_HARD_BUDGET)
}

/// [`load_from_bytes`] with an explicit memory budget: files whose unique tile payload
/// (dictionary tiles × 4096 B — exactly what materializes in RAM, since the loader shares one
/// `Arc` per dictionary tile) exceeds `hard_budget` are refused before any tile is allocated.
/// Decision 2026-07-16: refuse rather than load-and-lock — with uniform budgets no compliant
/// build can produce such a file, so this only rejects crafted/corrupt input.
pub fn load_from_bytes_budgeted(data: &[u8], hard_budget: usize) -> Result<Document, IoError> {
    // Signature + fixed INTG trailer, then verify the whole-file CRC before trusting any body.
    let body_end = verify_intg(data, &SIGNATURE)?;

    let chunks = mkpx_chunks(data, body_end)?;
    let head_pl = chunks.head.ok_or(IoError::Corrupt("no HEAD"))?;
    let tile_pl = chunks.tile.ok_or(IoError::Corrupt("no TILE"))?;
    let frms_pl = chunks.frms.ok_or(IoError::Corrupt("no FRMS"))?;

    // --- HEAD ---
    let mut hr = Reader::new(head_pl);
    let version = hr.u16()?;
    if version != FORMAT_VERSION {
        return Err(IoError::UnsupportedVersion(version));
    }
    let canvas = Size::new(hr.u16()?, hr.u16()?);
    if !canvas.in_range() {
        return Err(IoError::Corrupt("canvas size out of range"));
    }
    let (gl, gt, gr, gb) = (hr.u16()?, hr.u16()?, hr.u16()?, hr.u16()?);
    let margin = Document::gutter_for(canvas);
    if gl != margin.w || gr != margin.w || gt != margin.h || gb != margin.h {
        return Err(IoError::Corrupt("gutter geometry"));
    }
    let storage = Size::new(canvas.w + 2 * margin.w, canvas.h + 2 * margin.h);
    let frame_count = hr.u32()? as usize;
    if frame_count == 0 || frame_count > crate::document::MAX_FRAMES {
        return Err(IoError::Corrupt("frame count"));
    }
    let active_frame = hr.u16()? as usize;
    let active_palette_raw = hr.u16()?;
    let loop_mode = loop_mode_from_u8(hr.u8()?);
    let _head_flags = hr.u8()?;
    let stored_hash = hr.u128()?;

    // --- TILE dictionary → Vec<Arc<Tile>> (one Arc per distinct tile; shared on install).
    // Memory budget (SPEC §8.2b): the dictionary IS the document's unique tile payload —
    // `read_tile_dict` refuses over-budget files up front, before materializing a single tile.
    let mut tr = Reader::new(tile_pl);
    let dict = read_tile_dict(&mut tr, MAX_DICT_TILES, hard_budget)?;

    // --- FRMS ---
    let mut fr = Reader::new(frms_pl);
    if fr.varint()? as usize != frame_count {
        return Err(IoError::Corrupt("frame count mismatch"));
    }
    let mut frames = Vec::with_capacity(frame_count);
    let mut max_frame_id = 0u32;
    let mut max_layer_id = 0u32;
    for _ in 0..frame_count {
        let id = fr.u32()?;
        max_frame_id = max_frame_id.max(id);
        let duration_us = Document::clamp_duration(fr.u32()?);
        let active_layer = fr.u16()? as usize;
        let layer_count = fr.u16()? as usize;
        if layer_count == 0 || layer_count > crate::document::MAX_LAYERS {
            return Err(IoError::Corrupt("layer count"));
        }
        let mut layers = Vec::with_capacity(layer_count);
        for _ in 0..layer_count {
            let lid = fr.u32()?;
            max_layer_id = max_layer_id.max(lid);
            let name = fr.str()?;
            let flags = fr.u8()?;
            let opacity = fr.u8()?;
            let _blend = fr.u8()?;
            let mut pixels = RgbaBuffer::from_size(storage);
            read_ref_grid(&mut fr, &dict, &mut pixels)?;
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

    // --- UPAL (or default ramp) ---
    let mut palettes = Vec::new();
    if let Some(pl) = chunks.upal {
        let mut pr = Reader::new(pl);
        let pc = pr.varint()? as usize;
        if pc > crate::document::MAX_PALETTES {
            return Err(IoError::TooLarge("palettes"));
        }
        for _ in 0..pc {
            let name = pr.str()?;
            let cc = pr.u16()? as usize;
            let mut colors = Vec::with_capacity(cc.min(pr.remaining() / 4 + 1));
            for _ in 0..cc {
                let b = pr.take(4)?;
                colors.push(crate::Rgba8::new(b[0], b[1], b[2], b[3]));
            }
            palettes.push(Palette::new(name, colors));
        }
    }
    // --- UPCN (optional per-entry color names; tolerant of any mismatch with UPAL) ---
    if let Some(nl) = chunks.upcn {
        let mut nr = Reader::new(nl);
        let pc = (nr.varint()? as usize).min(palettes.len());
        for p in palettes.iter_mut().take(pc) {
            let cc = nr.u16()? as usize;
            for j in 0..cc {
                let name = nr.str()?;
                // Entries beyond the palette's actual colors are read (to stay in sync) but dropped.
                if j < p.color_names.len() && !name.is_empty() {
                    p.color_names[j] = Some(name);
                }
            }
        }
    }
    if palettes.is_empty() {
        palettes.push(Palette::default_palette());
    }
    let active_palette = if active_palette_raw == 0xFFFF {
        0
    } else {
        (active_palette_raw as usize).min(palettes.len() - 1)
    };

    // --- SELC (dropped if its dims don't match storage) ---
    let selection = match chunks.selc {
        Some(pl) => decode_selection(pl, storage)?,
        None => None,
    };

    let doc = Document {
        size: canvas,
        active_frame: active_frame.min(frames.len() - 1),
        frames,
        palettes,
        active_palette,
        anim: AnimSettings { loop_mode },
        history: crate::history::History::new(),
        frame_ids: IdGen::starting_at(max_frame_id.saturating_add(1)),
        layer_ids: IdGen::starting_at(max_layer_id.saturating_add(1)),
        selection,
    };

    // Semantic integrity: the reconstruction must hash to the stored artwork hash.
    if doc.content_hash() != stored_hash {
        return Err(IoError::Corrupt("content hash mismatch"));
    }
    Ok(doc)
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
    fn roundtrips_palette_color_names() {
        let mut doc = Document::new(16, 16);
        doc.palettes[0].color_names[0] = Some("Ink".into());
        doc.palettes[0].color_names[3] = Some("Slate, cool".into());
        let mut two = Palette::new("Two", vec![Rgba8::rgb(255, 0, 0), Rgba8::rgb(0, 255, 0)]);
        two.color_names[1] = Some("Leaf".into());
        doc.palettes.push(two);

        let bytes = save_to_bytes(&doc);
        let back = load_from_bytes(&bytes).unwrap();
        assert_eq!(back.palettes[0].color_names, doc.palettes[0].color_names);
        assert_eq!(back.palettes[1].color_names, doc.palettes[1].color_names);
        // Save→load→save is byte-stable with names present.
        assert_eq!(save_to_bytes(&back), bytes);
    }

    #[test]
    fn unnamed_palettes_write_no_upcn_and_old_files_load_unnamed() {
        // No names anywhere → the file must not grow a UPCN chunk (bytes identical to the
        // pre-names format, so older builds see exactly what they always did).
        let doc = Document::new(16, 16);
        let bytes = save_to_bytes(&doc);
        assert!(!bytes.windows(4).any(|w| w == b"UPCN"), "UPCN must be omitted when no name exists");
        let back = load_from_bytes(&bytes).unwrap();
        assert!(back.palettes[0].color_names.iter().all(|n| n.is_none()));
        assert_eq!(back.palettes[0].color_names.len(), back.palettes[0].colors.len());
    }

    #[test]
    fn deterministic_bytes() {
        let mut doc = Document::new(48, 32);
        doc.active_frame_mut().active_layer_mut().pixels.set(5, 5, Rgba8::WHITE);
        assert_eq!(save_to_bytes(&doc), save_to_bytes(&doc), "same document ⇒ identical bytes");
    }

    #[test]
    fn rejects_bad_magic() {
        assert!(matches!(load_from_bytes(&[0u8; 24]), Err(IoError::BadMagic)));
    }

    #[test]
    fn rejects_corrupt_crc() {
        let doc = Document::new(16, 16);
        let mut bytes = save_to_bytes(&doc);
        let i = 10; // flip a byte inside HEAD → CRC must catch it
        bytes[i] ^= 0xFF;
        assert!(load_from_bytes(&bytes).is_err());
    }

    #[test]
    fn roundtrips_a_rect_selection() {
        let mut doc = Document::new(40, 24);
        let st = doc.storage();
        let shape = Mask::from_plot(st.w as u32, st.h as u32, |p| {
            crate::raster::rect_filled(crate::geom::Point::new(3, 4), crate::geom::Point::new(20, 18), p)
        });
        doc.selection = Some(Arc::new(shape));
        let back = load_from_bytes(&save_to_bytes(&doc)).unwrap();
        assert_eq!(back.selection.as_deref(), doc.selection.as_deref(), "mask round-trips");
        assert_eq!(back.content_hash(), doc.content_hash());
    }

    #[test]
    fn roundtrips_an_irregular_selection() {
        let mut doc = Document::new(40, 24);
        let st = doc.storage();
        let mut m = Mask::new(st.w as u32, st.h as u32);
        m.set(3, 3, true);
        m.set(9, 3, true);
        m.set(4, 8, true); // not a filled rect → BITS
        doc.selection = Some(Arc::new(m));
        let back = load_from_bytes(&save_to_bytes(&doc)).unwrap();
        assert_eq!(back.selection.as_deref(), doc.selection.as_deref());
    }

    #[test]
    fn roundtrips_no_selection_as_none() {
        let doc = Document::new(32, 24);
        let back = load_from_bytes(&save_to_bytes(&doc)).unwrap();
        assert!(back.selection.is_none());
    }

    #[test]
    fn an_empty_selection_mask_loads_as_none() {
        // A Session never stores Some(empty) (Document::selection invariant), but a legacy or
        // hand-built file can carry an EMPTY SELC chunk — it must decode to "no selection".
        let mut doc = Document::new(32, 24);
        let st = doc.storage();
        doc.selection = Some(Arc::new(Mask::new(st.w as u32, st.h as u32)));
        let back = load_from_bytes(&save_to_bytes(&doc)).unwrap();
        assert!(back.selection.is_none());
    }

    #[test]
    fn dedup_shares_tiles_across_frames() {
        // A background layer identical across two frames dedups to one dictionary tile.
        let mut doc = Document::new(64, 64);
        doc.active_frame_mut().active_layer_mut().pixels.fill_all(Rgba8::rgb(10, 20, 30));
        let f2 = Frame {
            id: doc.new_frame_id(),
            duration_us: 100_000,
            layers: vec![{
                let mut l = doc.new_layer("bg2");
                l.pixels.fill_all(Rgba8::rgb(10, 20, 30));
                l
            }],
            active_layer: 0,
        };
        doc.frames.push(f2);
        let bytes = save_to_bytes(&doc);
        let back = load_from_bytes(&bytes).unwrap();
        assert_eq!(back.content_hash(), doc.content_hash());
        // The whole two-frame flat fill stays far under one raw layer.
        assert!(bytes.len() < 64 * 64 * 4 / 10, "dedup+codec kept it small: {}", bytes.len());
    }

    #[test]
    fn rle_and_indexed_compress_and_roundtrip() {
        // Flat fill (INDEXED-solid dedup) and a 2-color checkerboard tile (INDEXED) both round-trip.
        let mut doc = Document::new(256, 256);
        doc.active_frame_mut().active_layer_mut().pixels.fill_all(Rgba8::rgb(20, 40, 60));
        let bytes = save_to_bytes(&doc);
        assert!(bytes.len() < 256 * 256 * 4 / 10, "compressed {} vs raw", bytes.len());
        assert_eq!(load_from_bytes(&bytes).unwrap().content_hash(), doc.content_hash());

        let mut doc2 = Document::new(32, 32);
        {
            let px = &mut doc2.active_frame_mut().active_layer_mut().pixels;
            for y in 0..32 {
                for x in 0..32 {
                    let c = if (x + y) % 2 == 0 { Rgba8::BLACK } else { Rgba8::WHITE };
                    px.set(x, y, c);
                }
            }
        }
        assert_eq!(load_from_bytes(&save_to_bytes(&doc2)).unwrap().content_hash(), doc2.content_hash());
    }
}
