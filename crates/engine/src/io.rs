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
        }
    }
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

/// Bits needed to index `n` distinct colours: `0` for a solid tile, else `ceil(log2(n))` (≤8).
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

/// `INDEXED` payload if the tile uses ≤256 colours, else `None`.
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
    let mut dict_order: Vec<Vec<u8>> = Vec::new();
    let mut dict_index: HashMap<Vec<u8>, u32> = HashMap::new();
    for f in &doc.frames {
        for l in &f.layers {
            let nt = l.pixels.num_tiles();
            for i in 0..nt {
                if let Some(b) = l.pixels.tile_bytes(i) {
                    // First appearance clones the 4096 bytes into the dictionary; a repeat only hashes.
                    if let std::collections::hash_map::Entry::Vacant(e) = dict_index.entry(b) {
                        dict_order.push(e.key().clone());
                        e.insert(dict_order.len() as u32); // 1-based
                    }
                }
            }
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

    // TILE
    let mut tile = Writer::new();
    tile.varint(dict_order.len() as u32);
    for b in &dict_order {
        let (codec, payload) = encode_tile(b);
        tile.u8(codec);
        tile.bytes(&payload);
    }

    // FRMS
    let mut frms = Writer::new();
    frms.varint(doc.frames.len() as u32);
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
            let nt = l.pixels.num_tiles();
            let grid: Vec<u32> = (0..nt)
                .map(|i| match l.pixels.tile_bytes(i) {
                    Some(b) => dict_index[&b],
                    None => 0,
                })
                .collect();
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
    let mut w = Writer::new();
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
    }
    if let Some(mask) = &doc.selection {
        write_chunk(&mut w, b"SELC", false, &encode_selection(mask));
    }

    let crc = crc32c(&w.buf);
    let mut intg = Writer::new();
    intg.u32(crc);
    write_chunk(&mut w, b"INTG", true, &intg.buf);
    w.buf
}

struct Chunks<'a> {
    head: Option<&'a [u8]>,
    tile: Option<&'a [u8]>,
    frms: Option<&'a [u8]>,
    upal: Option<&'a [u8]>,
    selc: Option<&'a [u8]>,
}

/// Single forward walk of `[8 .. body_end]`; enforces `HEAD` first + one-of each critical.
fn walk_chunks<'a>(data: &'a [u8], body_end: usize) -> Result<Chunks<'a>, IoError> {
    let mut c = Chunks { head: None, tile: None, frms: None, upal: None, selc: None };
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
pub fn load_from_bytes_budgeted(data: &[u8], hard_budget: usize) -> Result<Document, IoError> {
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
        return Err(IoError::TooLarge("memory budget"));
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
            let _blend = fr.u8()?;
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
        if pc > 256 {
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
            palettes.push(Palette { name, colors });
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
        // Flat fill (INDEXED-solid dedup) and a 2-colour checkerboard tile (INDEXED) both round-trip.
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
