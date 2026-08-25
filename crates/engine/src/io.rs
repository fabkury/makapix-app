//! `.mkpx` **v10** container: typed-chunk, little-endian, content-addressed tile dictionary +
//! per-layer RLE tile-ref grids, per-tile codec menu (`RAW`/`RLE`/`INDEXED`) with a RAW floor,
//! whole-file CRC-32C + a verified `content_hash`. Byte-deterministic; lossless; dependency-free.
//! `load(save(doc))` is a round-trip invariant (by `content_hash`). This is the **`plain`** profile;
//! the optional DEFLATE **`compact`** envelope lives at the periphery (see `docs/mkpx-format/`).

use crate::buffer::{RgbaBuffer, Tile};
use crate::document::{AnimSettings, BlendMode, Document, Frame, Layer, LoopMode, Palette};
use crate::geom::Size;
use crate::selection::Mask;
use crate::util::IdGen;
use std::collections::HashMap;
use std::sync::Arc;

/// The `plain`-profile file signature (8 bytes, PNG-style hardened): high bit, `MKPX`, CR, LF, EOF.
pub const SIGNATURE: [u8; 8] = [0x89, b'M', b'K', b'P', b'X', 0x0D, 0x0A, 0x1A];
pub const FORMAT_VERSION: u16 = 10;

const TILE_BYTES: usize = 32 * 32 * 4; // 4096
const CELL_PX: usize = 1024;
const MAX_DICT_TILES: usize = 1 << 24;
const MAX_STR: usize = 4096;
/// Largest legal packed selection: a 768×768 storage plane = 589824 bits = 73728 bytes.
const MAX_SEL_BYTES: usize = (768 * 768) / 8;
/// The fixed `INTG` trailer size: fourcc(4) + flags(1) + length(4) + crc32c payload(4).
const INTG_LEN: usize = 13;

#[derive(Debug)]
pub enum IoError {
    BadMagic,
    UnsupportedVersion(u16),
    Incomplete,
    Corrupt(&'static str),
    TooLarge(&'static str),
    UnsupportedChunk([u8; 4]),
    /// Well-formed file whose unique tile payload exceeds the session's document memory budget
    /// (SPEC §8.2b) — refused before any tile is materialized. Distinct from `TooLarge` (the
    /// crafted-input caps) so shells can tell "too big for this device" from corruption.
    OverBudget,
}

impl std::fmt::Display for IoError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            IoError::BadMagic => write!(f, "not a .mkpx file (bad magic)"),
            IoError::UnsupportedVersion(v) => write!(f, "unsupported .mkpx version {}", v),
            IoError::Incomplete => write!(f, "file truncated/incomplete"),
            IoError::Corrupt(s) => write!(f, "corrupt .mkpx: {}", s),
            IoError::TooLarge(s) => write!(f, "corrupt .mkpx: {} too large", s),
            IoError::UnsupportedChunk(c) => {
                write!(f, "unsupported critical chunk {:?}", String::from_utf8_lossy(c))
            }
            IoError::OverBudget => write!(f, "refused: .mkpx exceeds the document memory budget"),
        }
    }
}

/// Non-fatal findings from a tolerant load (format spec §12.2, verification stance).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LoadWarning {
    /// The rebuilt document hashes differently from `HEAD.content_hash`. The bytes survived the
    /// channel (the CRC passed) and every structural bound held — most likely the file was
    /// written by a build with a different hash rule (e.g. a newer semantic field), not corrupted.
    ContentHashMismatch { stored: crate::util::Hash, computed: crate::util::Hash },
}

/// A tolerantly loaded document plus any non-fatal warnings.
pub struct Loaded {
    pub doc: Document,
    pub warnings: Vec<LoadWarning>,
}

// ---- CRC-32C (Castagnoli, reflected poly 0x82F63B78), pure-Rust const table ----

const fn crc32c_table() -> [u32; 256] {
    let mut table = [0u32; 256];
    let mut i = 0usize;
    while i < 256 {
        let mut crc = i as u32;
        let mut j = 0;
        while j < 8 {
            crc = if crc & 1 != 0 { (crc >> 1) ^  0x82F6_3B78 } else { crc >> 1 };
            j += 1;
        }
        table[i] = crc;
        i += 1;
    }
    table
}
static CRC32C_TABLE: [u32; 256] = crc32c_table();

fn crc32c(bytes: &[u8]) -> u32 {
    let mut crc = 0xFFFF_FFFFu32;
    for &b in bytes {
        crc = (crc >> 8) ^ CRC32C_TABLE[((crc ^ b as u32) & 0xFF) as usize];
    }
    crc ^ 0xFFFF_FFFF
}

// ---- little-endian + varint writer/reader ----

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
    fn u128(&mut self, v: u128) {
        self.buf.extend_from_slice(&v.to_le_bytes());
    }
    fn bytes(&mut self, b: &[u8]) {
        self.buf.extend_from_slice(b);
    }
    /// Canonical unsigned LEB128 (minimal length).
    fn varint(&mut self, v: u32) {
        let mut v = v;
        loop {
            let b = (v & 0x7f) as u8;
            v >>= 7;
            if v != 0 {
                self.buf.push(b | 0x80);
            } else {
                self.buf.push(b);
                break;
            }
        }
    }
    fn str(&mut self, s: &str) {
        let b = s.as_bytes();
        let n = b.len().min(MAX_STR);
        self.varint(n as u32);
        self.bytes(&b[..n]);
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
    fn remaining(&self) -> usize {
        self.buf.len().saturating_sub(self.pos)
    }
    fn take(&mut self, n: usize) -> Result<&'a [u8], IoError> {
        let end = self.pos.checked_add(n).ok_or(IoError::Incomplete)?;
        let s = self.buf.get(self.pos..end).ok_or(IoError::Incomplete)?;
        self.pos = end;
        Ok(s)
    }
    fn u8(&mut self) -> Result<u8, IoError> {
        Ok(self.take(1)?[0])
    }
    fn u16(&mut self) -> Result<u16, IoError> {
        let s = self.take(2)?;
        Ok(u16::from_le_bytes([s[0], s[1]]))
    }
    fn u32(&mut self) -> Result<u32, IoError> {
        let s = self.take(4)?;
        Ok(u32::from_le_bytes([s[0], s[1], s[2], s[3]]))
    }
    fn u128(&mut self) -> Result<u128, IoError> {
        let s = self.take(16)?;
        let mut a = [0u8; 16];
        a.copy_from_slice(s);
        Ok(u128::from_le_bytes(a))
    }
    /// Canonical unsigned LEB128 into a `u32`: ≤5 bytes, minimal, non-overflowing.
    fn varint(&mut self) -> Result<u32, IoError> {
        let mut result: u32 = 0;
        for i in 0..5 {
            let b = self.u8()?;
            let val = (b & 0x7f) as u32;
            if i == 4 && val > 0x0f {
                return Err(IoError::Corrupt("varint overflow"));
            }
            result |= val << (7 * i);
            if b & 0x80 == 0 {
                if i > 0 && b == 0 {
                    return Err(IoError::Corrupt("varint non-minimal"));
                }
                return Ok(result);
            }
        }
        Err(IoError::Corrupt("varint too long"))
    }
    fn str(&mut self) -> Result<String, IoError> {
        let n = self.varint()? as usize;
        if n > MAX_STR {
            return Err(IoError::TooLarge("string"));
        }
        Ok(String::from_utf8_lossy(self.take(n)?).into_owned())
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

/// Bits needed to index `n` distinct colors: `0` for a solid tile, else `ceil(log2(n))` (≤8).
fn bits_needed(n: usize) -> u32 {
    if n <= 1 {
        return 0;
    }
    let mut b = 0u32;
    while (1usize << b) < n {
        b += 1;
    }
    b
}

// ---- per-tile codecs (operate on the tile's 4096 row-major straight-RGBA bytes) ----

fn rle_encode(b: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    let px = |i: usize| &b[i * 4..i * 4 + 4];
    let mut i = 0usize;
    while i < CELL_PX {
        let start = i;
        while i + 1 < CELL_PX && px(i + 1) == px(start) {
            i += 1;
        }
        let run = (i - start + 1) as u32;
        // inline canonical varint of `run`
        let mut v = run;
        loop {
            let byte = (v & 0x7f) as u8;
            v >>= 7;
            if v != 0 {
                out.push(byte | 0x80);
            } else {
                out.push(byte);
                break;
            }
        }
        out.extend_from_slice(px(start));
        i += 1;
    }
    out
}

/// `INDEXED` payload if the tile uses ≤256 colors, else `None`.
fn indexed_encode(b: &[u8]) -> Option<Vec<u8>> {
    let mut order: Vec<[u8; 4]> = Vec::new();
    let mut map: HashMap<[u8; 4], u8> = HashMap::new();
    let mut indices = [0u8; CELL_PX];
    for (p, slot) in indices.iter_mut().enumerate() {
        let c = [b[p * 4], b[p * 4 + 1], b[p * 4 + 2], b[p * 4 + 3]];
        let id = match map.get(&c) {
            Some(&id) => id,
            None => {
                if order.len() >= 256 {
                    return None;
                }
                let id = order.len() as u8;
                map.insert(c, id);
                order.push(c);
                id
            }
        };
        *slot = id;
    }
    let n = order.len();
    let k = bits_needed(n);
    let mut out = Vec::with_capacity(1 + 4 * n + (CELL_PX * k as usize).div_ceil(8));
    out.push((n - 1) as u8);
    for c in &order {
        out.extend_from_slice(c);
    }
    if k > 0 {
        let mut acc: u32 = 0;
        let mut nb: u32 = 0;
        for &ix in indices.iter() {
            acc = (acc << k) | ix as u32;
            nb += k;
            while nb >= 8 {
                nb -= 8;
                out.push((acc >> nb) as u8);
            }
        }
        if nb > 0 {
            out.push((acc << (8 - nb)) as u8);
        }
    }
    Some(out)
}

/// Pick the smallest codec for a tile; ties break to the lowest id (RAW < RLE < INDEXED).
fn encode_tile(b: &[u8]) -> (u8, Vec<u8>) {
    let mut best_codec = 0u8; // RAW
    let mut best_len = TILE_BYTES; // RAW payload length
    let mut best: Option<Vec<u8>> = None;
    let rle = rle_encode(b);
    if rle.len() < best_len {
        best_len = rle.len();
        best_codec = 1;
        best = Some(rle);
    }
    if let Some(ix) = indexed_encode(b) {
        if ix.len() < best_len {
            best_codec = 2;
            best = Some(ix);
        }
    }
    match best_codec {
        0 => (0, b.to_vec()),
        c => (c, best.expect("non-RAW codec has payload")),
    }
}

fn decode_tile(r: &mut Reader, codec: u8) -> Result<Vec<u8>, IoError> {
    match codec {
        0 => Ok(r.take(TILE_BYTES)?.to_vec()),
        1 => {
            let mut out = Vec::with_capacity(TILE_BYTES);
            let mut done = 0usize;
            while done < CELL_PX {
                let run = r.varint()? as usize;
                let px = r.take(4)?;
                if run == 0 || done + run > CELL_PX {
                    return Err(IoError::Corrupt("bad rle run"));
                }
                for _ in 0..run {
                    out.extend_from_slice(px);
                }
                done += run;
            }
            Ok(out)
        }
        2 => {
            let n = r.u8()? as usize + 1; // 1..=256
            let mut table = Vec::with_capacity(n);
            for _ in 0..n {
                let c = r.take(4)?;
                table.push([c[0], c[1], c[2], c[3]]);
            }
            let k = bits_needed(n);
            let mut out = Vec::with_capacity(TILE_BYTES);
            if k == 0 {
                let c = table[0];
                for _ in 0..CELL_PX {
                    out.extend_from_slice(&c);
                }
            } else {
                let nbytes = (CELL_PX * k as usize).div_ceil(8);
                let data = r.take(nbytes)?;
                let mut acc: u32 = 0;
                let mut nb: u32 = 0;
                let mut bp = 0usize;
                let mask = (1u32 << k) - 1;
                for _ in 0..CELL_PX {
                    while nb < k {
                        let byte = *data.get(bp).ok_or(IoError::Corrupt("indexed underrun"))?;
                        acc = (acc << 8) | byte as u32;
                        bp += 1;
                        nb += 8;
                    }
                    nb -= k;
                    let ix = ((acc >> nb) & mask) as usize;
                    if ix >= n {
                        return Err(IoError::Corrupt("bad index"));
                    }
                    out.extend_from_slice(&table[ix]);
                }
            }
            Ok(out)
        }
        _ => Err(IoError::Corrupt("bad tile codec")),
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
    w.buf
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

// ---- chunk assembly ----

fn write_chunk(w: &mut Writer, fourcc: &[u8; 4], critical: bool, payload: &[u8]) {
    w.bytes(fourcc);
    w.u8(critical as u8); // bit0 = critical
    w.u32(payload.len() as u32);
    w.bytes(payload);
}

pub fn save_to_bytes(doc: &Document) -> Vec<u8> {
    let canvas = doc.size;
    let margin = Document::gutter_for(canvas);

    // Dictionary: distinct present tiles, first-appearance order (frames→layers→cells).
    // Entries are the live `Arc<Tile>`s — no byte clones. Lookup is two-level: an `Arc`-pointer
    // cache catches COW-shared repeats without touching pixels, then a content-hash map (u128,
    // byte-equality verified on hit so a hash collision can only cost a compare, never corrupt
    // the file). This removed the double clone that made saving peak at 6-7× the document size
    // (memlab M4a); output bytes are unchanged (same first-appearance ids).
    let mut dict_order: Vec<Arc<Tile>> = Vec::new();
    let mut by_ptr: HashMap<*const Tile, u32> = HashMap::new();
    let mut by_hash: HashMap<u128, Vec<u32>> = HashMap::new(); // 1-based candidate ids
    // Per-layer reference grids, computed in the same pass so FRMS below reuses them instead of
    // re-cloning every tile for a map lookup (the second former full-clone pass).
    let mut grids: Vec<Vec<u32>> = Vec::new();
    for f in &doc.frames {
        for l in &f.layers {
            let nt = l.pixels.num_tiles();
            let mut grid = Vec::with_capacity(nt);
            for i in 0..nt {
                let id = match l.pixels.tile_arc(i) {
                    None => 0u32,
                    Some(t) => {
                        let ptr = Arc::as_ptr(t);
                        match by_ptr.get(&ptr) {
                            Some(&id) => id,
                            None => {
                                let h = t.content_hash();
                                let cands = by_hash.entry(h).or_default();
                                let id = match cands
                                    .iter()
                                    .copied()
                                    .find(|&id| *dict_order[(id - 1) as usize] == **t)
                                {
                                    Some(id) => id,
                                    None => {
                                        dict_order.push(t.clone());
                                        let id = dict_order.len() as u32;
                                        cands.push(id);
                                        id
                                    }
                                };
                                by_ptr.insert(ptr, id);
                                id
                            }
                        }
                    }
                };
                grid.push(id);
            }
            grids.push(grid);
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
    // Pre-sized (worst case ≈ RAW cells) so the Vec never overshoots by doubling (memlab M5) —
    // under the document budget this reservation is ≤ ~340 MiB and effectively infallible.
    let mut tile = Writer::new();
    tile.buf.reserve_exact(dict_order.len() * (TILE_BYTES + 8) + 16);
    tile.varint(dict_order.len() as u32);
    for t in &dict_order {
        let b = t.to_bytes();
        let (codec, payload) = encode_tile(&b);
        tile.u8(codec);
        tile.bytes(&payload);
    }

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
            frms.u8(l.blend as u8); // spec §12.2 wire value; readers map unknown → Normal
            let grid = grid_iter.next().expect("one grid per layer");
            let nt = grid.len();
            let mut i = 0usize;
            while i < nt {
                let idx = grid[i];
                let mut run = 1usize;
                while i + run < nt && grid[i + run] == idx {
                    run += 1;
                }
                frms.varint(run as u32);
                frms.varint(idx);
                i += run;
            }
        }
    }

    // Assemble: signature, critical chunks, optional chunks, then INTG (whole-file CRC).
    // Pre-sized to the known chunk payloads so the final buffer never doubles past the file size.
    let mut w = Writer::new();
    w.buf.reserve_exact(head.buf.len() + tile.buf.len() + frms.buf.len() + 64 * 1024);
    w.bytes(&SIGNATURE);
    write_chunk(&mut w, b"HEAD", true, &head.buf);
    write_chunk(&mut w, b"TILE", true, &tile.buf);
    write_chunk(&mut w, b"FRMS", true, &frms.buf);

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
        write_chunk(&mut w, b"UPAL", false, &upal.buf);
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
            write_chunk(&mut w, b"UPCN", false, &upcn.buf);
        }
    }
    if let Some(mask) = &doc.selection {
        // Invariant: the live selection always fits the current storage. A mask left over
        // from a different canvas geometry serializes fine but is DROPPED by
        // `decode_selection`'s out-of-range guard, so save→load→save silently loses the
        // SELC chunk and stops being byte-identical — the byte-determinism promise, and
        // invisible to any content-hash comparison. [fuzz FZ-2, docs/fuzzing/FINDINGS.md]
        debug_assert!(
            {
                let st = doc.storage();
                mask.bounds().is_none_or(|b| {
                    b.x >= 0
                        && b.y >= 0
                        && b.x as u32 + b.w <= st.w as u32
                        && b.y as u32 + b.h <= st.h as u32
                })
            },
            "selection mask outside storage at save time (stale geometry)"
        );
        write_chunk(&mut w, b"SELC", false, &encode_selection(mask));
    }

    let crc = crc32c(&w.buf);
    let mut intg = Writer::new();
    intg.u32(crc);
    write_chunk(&mut w, b"INTG", true, &intg.buf);
    w.buf
}

// ---- META periphery helpers (spec §11) ----
//
// The engine core never emits `THMB`/`META` — `save_to_bytes` above stays byte-deterministic and
// META-free. These helpers serve the periphery (crates/ffi) when the shell wants volatile metadata
// (provenance, authorship) to travel inside a self-contained file: `splice_meta_str` inserts (or
// replaces) the ancillary `META` chunk at its canonical position just before `INTG` and recomputes
// the whole-file CRC; `read_meta_str` extracts the string-typed entries back. The loader is
// unaffected either way — it skips `META` wholesale.

/// Spec cap on META entries (§11).
pub const MAX_META_ENTRIES: usize = 256;

/// Bounds-check the container frame shared by the META helpers: signature, minimum length, a
/// well-formed `INTG` trailer, and a matching whole-file CRC. Returns `body_end` (the INTG offset).
fn meta_frame_check(mkpx: &[u8]) -> Result<usize, IoError> {
    if mkpx.len() < 8 || mkpx[..8] != SIGNATURE {
        return Err(IoError::BadMagic);
    }
    if mkpx.len() < 8 + INTG_LEN {
        return Err(IoError::Incomplete);
    }
    let body_end = mkpx.len() - INTG_LEN;
    let intg = &mkpx[body_end..];
    if &intg[..4] != b"INTG" || intg[4] & 1 == 0 {
        return Err(IoError::Corrupt("missing INTG"));
    }
    let stored = u32::from_le_bytes([intg[9], intg[10], intg[11], intg[12]]);
    if stored != crc32c(&mkpx[..body_end]) {
        return Err(IoError::Corrupt("CRC mismatch"));
    }
    Ok(body_end)
}

/// One forward step through the chunk stream: returns `(fourcc, chunk_start, chunk_end)` for the
/// chunk at `pos` (header included in the range), bounds-checked against `body_end`.
fn meta_chunk_at(mkpx: &[u8], pos: usize, body_end: usize) -> Result<([u8; 4], usize, usize), IoError> {
    if pos + 9 > body_end {
        return Err(IoError::Corrupt("chunk header"));
    }
    let fourcc: [u8; 4] = match mkpx[pos..pos + 4].try_into() {
        Ok(a) => a,
        Err(_) => return Err(IoError::Corrupt("fourcc")),
    };
    let len = u32::from_le_bytes([mkpx[pos + 5], mkpx[pos + 6], mkpx[pos + 7], mkpx[pos + 8]]) as usize;
    let end = (pos + 9).checked_add(len).ok_or(IoError::Corrupt("chunk length"))?;
    if end > body_end {
        return Err(IoError::Corrupt("chunk length"));
    }
    Ok((fourcc, pos, end))
}

/// Rebuild `mkpx` with the given string entries as its `META` chunk (replacing any existing one;
/// an empty `entries` strips META), re-signing with a fresh whole-file CRC. Entry count and string
/// lengths are enforced against the spec caps — oversized input is an error, never a silent
/// truncation (a truncated provenance list would lie).
pub fn splice_meta_str(mkpx: &[u8], entries: &[(&str, &str)]) -> Result<Vec<u8>, IoError> {
    if entries.len() > MAX_META_ENTRIES {
        return Err(IoError::TooLarge("meta entries"));
    }
    for (k, v) in entries {
        if k.len() > MAX_STR || v.len() > MAX_STR {
            return Err(IoError::TooLarge("meta string"));
        }
    }
    let body_end = meta_frame_check(mkpx)?;
    let mut w = Writer::new();
    w.buf.reserve_exact(mkpx.len() + 64 + entries.iter().map(|(k, v)| k.len() + v.len() + 12).sum::<usize>());
    w.bytes(&mkpx[..8]);
    let mut pos = 8usize;
    while pos < body_end {
        let (fourcc, start, end) = meta_chunk_at(mkpx, pos, body_end)?;
        if &fourcc != b"META" {
            w.bytes(&mkpx[start..end]);
        }
        pos = end;
    }
    if !entries.is_empty() {
        let mut meta = Writer::new();
        meta.varint(entries.len() as u32);
        for (k, v) in entries {
            meta.str(k);
            meta.u8(0); // value_type 0 = str
            meta.str(v);
        }
        write_chunk(&mut w, b"META", false, &meta.buf);
    }
    let crc = crc32c(&w.buf);
    let mut intg = Writer::new();
    intg.u32(crc);
    write_chunk(&mut w, b"INTG", true, &intg.buf);
    Ok(w.buf)
}

/// Extract the string-typed entries of the `META` chunk from a **plain** container (the compact
/// envelope is the periphery's to open first). Non-string entry types are skipped, preserving the
/// "unknown keys preserved/ignored" stance; a file without META yields an empty list. Hostile
/// input is safe: every read is bounds-checked and the CRC is verified before the walk.
pub fn read_meta_str(mkpx: &[u8]) -> Result<Vec<(String, String)>, IoError> {
    let body_end = meta_frame_check(mkpx)?;
    let mut pos = 8usize;
    while pos < body_end {
        let (fourcc, start, end) = meta_chunk_at(mkpx, pos, body_end)?;
        if &fourcc == b"META" {
            let mut r = Reader::new(&mkpx[start + 9..end]);
            let count = r.varint()? as usize;
            if count > MAX_META_ENTRIES {
                return Err(IoError::TooLarge("meta entries"));
            }
            let mut out = Vec::new();
            for _ in 0..count {
                let key = r.str()?;
                match r.u8()? {
                    0 => out.push((key, r.str()?)),
                    1 | 2 => {
                        r.take(8)?;
                    }
                    3 => {
                        let n = r.varint()? as usize;
                        if n > MAX_STR {
                            return Err(IoError::TooLarge("meta bytes"));
                        }
                        r.take(n)?;
                    }
                    _ => return Err(IoError::Corrupt("meta value type")),
                }
            }
            return Ok(out);
        }
        pos = end;
    }
    Ok(Vec::new())
}

struct Chunks<'a> {
    head: Option<&'a [u8]>,
    tile: Option<&'a [u8]>,
    frms: Option<&'a [u8]>,
    upal: Option<&'a [u8]>,
    upcn: Option<&'a [u8]>,
    selc: Option<&'a [u8]>,
}

/// Single forward walk of `[8 .. body_end]`; enforces `HEAD` first + one-of each critical.
fn walk_chunks<'a>(data: &'a [u8], body_end: usize) -> Result<Chunks<'a>, IoError> {
    let mut c = Chunks { head: None, tile: None, frms: None, upal: None, upcn: None, selc: None };
    let mut pos = 8usize;
    let mut first = true;
    while pos < body_end {
        if pos + 9 > body_end {
            return Err(IoError::Corrupt("chunk header"));
        }
        let fourcc: [u8; 4] = match data[pos..pos + 4].try_into() {
            Ok(a) => a,
            Err(_) => return Err(IoError::Corrupt("fourcc")),
        };
        let critical = data[pos + 4] & 1 != 0;
        let len = u32::from_le_bytes([data[pos + 5], data[pos + 6], data[pos + 7], data[pos + 8]]) as usize;
        let start = pos + 9;
        let end = start.checked_add(len).ok_or(IoError::Corrupt("chunk length"))?;
        if end > body_end {
            return Err(IoError::Corrupt("chunk length"));
        }
        let payload = &data[start..end];
        if first && &fourcc != b"HEAD" {
            return Err(IoError::Corrupt("HEAD not first"));
        }
        first = false;
        let slot = match &fourcc {
            b"HEAD" => &mut c.head,
            b"TILE" => &mut c.tile,
            b"FRMS" => &mut c.frms,
            b"UPAL" => &mut c.upal,
            b"UPCN" => &mut c.upcn,
            b"SELC" => &mut c.selc,
            b"THMB" | b"META" => {
                pos = end;
                continue; // ancillary, not used by the engine core
            }
            _ => {
                if critical {
                    return Err(IoError::UnsupportedChunk(fourcc));
                }
                pos = end;
                continue; // unknown ancillary → skip
            }
        };
        if slot.is_some() {
            return Err(IoError::Corrupt("duplicate chunk"));
        }
        *slot = Some(payload);
        pos = end;
    }
    if pos != body_end {
        return Err(IoError::Corrupt("trailing bytes"));
    }
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
///
/// **Strict**: a content-hash mismatch is an error here (tests, the `mkpx` CLI, and the
/// roundtrip probes stay on this path). The production shell loads through
/// [`load_from_bytes_tolerant_budgeted`], which reports the mismatch as a warning instead.
pub fn load_from_bytes_budgeted(data: &[u8], hard_budget: usize) -> Result<Document, IoError> {
    let loaded = load_from_bytes_tolerant_budgeted(data, hard_budget)?;
    match loaded.warnings.first() {
        None => Ok(loaded.doc),
        Some(LoadWarning::ContentHashMismatch { .. }) => Err(IoError::Corrupt("content hash mismatch")),
    }
}

/// The production load path: identical to [`load_from_bytes_budgeted`] except the content-hash
/// self-check is reported as a [`LoadWarning`] instead of an error — the document still loads.
/// Everything else (CRC, truncation, structural bounds, version, budget) remains fatal, so a
/// warning here means "written under a different hash rule", never "damaged in transit".
pub fn load_from_bytes_tolerant_budgeted(data: &[u8], hard_budget: usize) -> Result<Loaded, IoError> {
    // Signature + fixed INTG trailer, then verify the whole-file CRC before trusting any body.
    if data.len() < 8 + INTG_LEN {
        return Err(IoError::Incomplete);
    }
    if data[..8] != SIGNATURE {
        return Err(IoError::BadMagic);
    }
    let n = data.len();
    let body_end = n - INTG_LEN;
    let intg = &data[body_end..];
    if &intg[..4] != b"INTG" || intg[4] & 1 == 0 {
        return Err(IoError::Corrupt("missing INTG"));
    }
    if u32::from_le_bytes([intg[5], intg[6], intg[7], intg[8]]) != 4 {
        return Err(IoError::Corrupt("bad INTG"));
    }
    let stored = u32::from_le_bytes([intg[9], intg[10], intg[11], intg[12]]);
    if crc32c(&data[..body_end]) != stored {
        return Err(IoError::Corrupt("crc mismatch"));
    }

    let chunks = walk_chunks(data, body_end)?;
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

    // --- TILE dictionary → Vec<Arc<Tile>> (one Arc per distinct tile; shared on install) ---
    let mut tr = Reader::new(tile_pl);
    let tile_count = tr.varint()? as usize;
    if tile_count > MAX_DICT_TILES {
        return Err(IoError::TooLarge("tile dictionary"));
    }
    // Memory budget (SPEC §8.2b): the dictionary IS the document's unique tile payload — refuse
    // over-budget files up front, before materializing a single tile.
    if tile_count.saturating_mul(4096) > hard_budget {
        return Err(IoError::OverBudget);
    }
    let mut dict: Vec<Arc<Tile>> = Vec::with_capacity(tile_count.min(tr.remaining() / 2 + 1));
    for _ in 0..tile_count {
        let codec = tr.u8()?;
        let bytes = decode_tile(&mut tr, codec)?;
        dict.push(Arc::new(Tile::from_bytes(&bytes).ok_or(IoError::Corrupt("tile"))?));
    }

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
            let blend = BlendMode::from_u8(fr.u8()?); // unknown values degrade to Normal (§19)
            let mut pixels = RgbaBuffer::from_size(storage);
            let cells = pixels.num_tiles();
            let mut filled = 0usize;
            while filled < cells {
                let run = fr.varint()? as usize;
                let idx = fr.varint()? as usize;
                if run == 0 || filled + run > cells {
                    return Err(IoError::Corrupt("ref-grid run"));
                }
                if idx > dict.len() {
                    return Err(IoError::Corrupt("tile index"));
                }
                if idx >= 1 {
                    let arc = &dict[idx - 1];
                    for c in filled..filled + run {
                        pixels.set_tile(c, Some(arc.clone()));
                    }
                }
                filled += run;
            }
            layers.push(Layer {
                id: lid,
                name,
                visible: flags & 1 != 0,
                locked: flags & 2 != 0,
                opacity,
                blend,
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

    // Semantic integrity (spec §12.2): the reconstruction should hash to the stored artwork
    // hash. A mismatch is a WARNING here — the strict wrapper above promotes it to an error
    // for tests/CLI, while the production shell loads the document and just logs.
    let mut warnings = Vec::new();
    let computed = doc.content_hash();
    if computed != stored_hash {
        warnings.push(LoadWarning::ContentHashMismatch { stored: stored_hash, computed });
    }
    Ok(Loaded { doc, warnings })
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
    fn meta_splice_read_roundtrip() {
        let mut doc = Document::new(16, 16);
        doc.active_frame_mut().active_layer_mut().pixels.set(3, 3, Rgba8::WHITE);
        let plain = save_to_bytes(&doc);

        let entries = [("club.parents", "aB3xY,qW9zK"), ("club.everImported", "1")];
        let spliced = splice_meta_str(&plain, &entries).unwrap();
        assert_eq!(
            read_meta_str(&spliced).unwrap(),
            entries.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect::<Vec<_>>()
        );
        // The document still loads identically — the loader skips META.
        let back = load_from_bytes(&spliced).unwrap();
        assert_eq!(back.content_hash(), doc.content_hash());
        // A file without META reads as empty, not an error.
        assert_eq!(read_meta_str(&plain).unwrap(), Vec::new());
    }

    #[test]
    fn meta_splice_replaces_and_strips() {
        let doc = Document::new(8, 8);
        let plain = save_to_bytes(&doc);
        let first = splice_meta_str(&plain, &[("k", "old"), ("gone", "x")]).unwrap();
        let second = splice_meta_str(&first, &[("k", "new")]).unwrap();
        assert_eq!(read_meta_str(&second).unwrap(), vec![("k".to_string(), "new".to_string())]);
        // Empty entries strip META entirely, restoring the engine-canonical bytes.
        let stripped = splice_meta_str(&second, &[]).unwrap();
        assert_eq!(stripped, plain);
    }

    #[test]
    fn meta_read_skips_non_string_types_and_rejects_garbage() {
        let doc = Document::new(8, 8);
        let plain = save_to_bytes(&doc);
        // Hand-build a META chunk with a u64 entry between two strings.
        let body_end = plain.len() - INTG_LEN;
        let mut w = Writer::new();
        w.bytes(&plain[..body_end]);
        let mut meta = Writer::new();
        meta.varint(3);
        meta.str("a");
        meta.u8(0);
        meta.str("1");
        meta.str("stamp");
        meta.u8(1); // u64
        meta.bytes(&42u64.to_le_bytes());
        meta.str("z");
        meta.u8(0);
        meta.str("2");
        write_chunk(&mut w, b"META", false, &meta.buf);
        let crc = crc32c(&w.buf);
        let mut intg = Writer::new();
        intg.u32(crc);
        write_chunk(&mut w, b"INTG", true, &intg.buf);
        assert_eq!(
            read_meta_str(&w.buf).unwrap(),
            vec![("a".to_string(), "1".to_string()), ("z".to_string(), "2".to_string())]
        );
        // Corrupt (CRC-broken) input is rejected, not walked.
        let mut bad = w.buf.clone();
        bad[10] ^= 0xFF;
        assert!(read_meta_str(&bad).is_err());
        assert!(splice_meta_str(&bad, &[("k", "v")]).is_err());
        // Oversized entries error rather than truncate.
        let long = "x".repeat(5000);
        assert!(splice_meta_str(&plain, &[("k", long.as_str())]).is_err());
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

    /// Rewrite the INTG trailer's CRC after tampering with the body — without this, a tamper
    /// test exercises the CRC guard (checked first) instead of the guard under test.
    fn reseal_crc(bytes: &mut [u8]) {
        let body_end = bytes.len() - INTG_LEN;
        let crc = crc32c(&bytes[..body_end]).to_le_bytes();
        let n = bytes.len();
        bytes[n - 4..].copy_from_slice(&crc);
    }

    #[test]
    fn tampered_stored_hash_warns_tolerant_rejects_strict() {
        let mut doc = Document::new(48, 32);
        doc.active_frame_mut().active_layer_mut().pixels.set(5, 6, Rgba8::rgb(10, 20, 30));
        let mut bytes = save_to_bytes(&doc);
        // The stored content hash sits in HEAD at signature(8) + chunk header(4+1+4) + the
        // fixed fields before it (version 2 + canvas 4 + gutter 8 + frame_count 4 +
        // active_frame 2 + active_palette 2 + loop_mode 1 + head_flags 1 = 24).
        const HASH_OFF: usize = 8 + 9 + 24;
        bytes[HASH_OFF] ^= 0xFF;
        reseal_crc(&mut bytes);

        assert!(matches!(load_from_bytes(&bytes), Err(IoError::Corrupt("content hash mismatch"))));
        let loaded =
            load_from_bytes_tolerant_budgeted(&bytes, crate::document::MEM_HARD_BUDGET).unwrap();
        assert_eq!(loaded.warnings.len(), 1);
        assert!(matches!(loaded.warnings[0], LoadWarning::ContentHashMismatch { .. }));
        assert_eq!(loaded.doc.content_hash(), doc.content_hash(), "pixels survive intact");
    }

    #[test]
    fn tolerant_load_is_clean_on_a_good_file() {
        let mut doc = Document::new(16, 16);
        doc.active_frame_mut().active_layer_mut().pixels.set(1, 2, Rgba8::WHITE);
        let bytes = save_to_bytes(&doc);
        let loaded =
            load_from_bytes_tolerant_budgeted(&bytes, crate::document::MEM_HARD_BUDGET).unwrap();
        assert!(loaded.warnings.is_empty());
        assert_eq!(loaded.doc.content_hash(), doc.content_hash());
    }

    #[test]
    fn over_budget_is_a_distinct_error() {
        // Two distinct tiles → 8192 B of unique payload against a 4096 B budget.
        let mut doc = Document::new(64, 64);
        doc.active_frame_mut().active_layer_mut().pixels.set(0, 0, Rgba8::rgb(255, 0, 0));
        doc.active_frame_mut().active_layer_mut().pixels.set(40, 40, Rgba8::rgb(0, 0, 255));
        let bytes = save_to_bytes(&doc);
        assert!(matches!(load_from_bytes_budgeted(&bytes, 4096), Err(IoError::OverBudget)));
    }

    #[test]
    fn roundtrip_preserves_blend_mode() {
        // A non-Normal blend participates in the conditional content hash (spec §12.2) on both
        // the writer and the reader — a strict load passing proves the two sides agree.
        let mut doc = Document::new(32, 32);
        doc.active_frame_mut().active_layer_mut().pixels.set(3, 3, Rgba8::rgb(200, 10, 90));
        let mut top = doc.new_layer("glow");
        top.blend = BlendMode::Screen;
        top.opacity = 180;
        doc.active_frame_mut().layers.push(top);

        let bytes = save_to_bytes(&doc);
        let back = load_from_bytes(&bytes).unwrap();
        assert_eq!(back.frames[0].layers[1].blend, BlendMode::Screen);
        assert_eq!(back.content_hash(), doc.content_hash());
        assert_eq!(save_to_bytes(&back), bytes, "save→load→save is byte-stable with blend set");
    }

    #[test]
    fn unknown_blend_byte_loads_as_normal() {
        // A future blend value in a v10 file degrades to Normal (spec §19) — and since the
        // reader then rebuilds an all-Normal document, the stored (all-Normal) hash still
        // matches: the load is CLEAN, not even a warning.
        let doc = Document::new(16, 16);
        let mut bytes = save_to_bytes(&doc);
        // Layer record layout: id(4) · name(str) · flags(1) · opacity(1) · blend(1) — locate
        // the default layer name in the plain stream and step past flags+opacity.
        let name = b"Layer 1";
        let pos = bytes.windows(name.len()).position(|w| w == name).expect("layer name in FRMS");
        let blend_off = pos + name.len() + 2;
        assert_eq!(bytes[blend_off], 0, "sanity: the blend byte of a Normal layer");
        bytes[blend_off] = 200;
        reseal_crc(&mut bytes);

        let back = load_from_bytes(&bytes).expect("unknown blend value must not fail the load");
        assert_eq!(back.frames[0].layers[0].blend, BlendMode::Normal);
        let loaded =
            load_from_bytes_tolerant_budgeted(&bytes, crate::document::MEM_HARD_BUDGET).unwrap();
        assert!(loaded.warnings.is_empty(), "degrading to Normal re-matches the stored hash");
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
