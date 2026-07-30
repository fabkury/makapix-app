//! Format-agnostic container machinery shared by the typed-chunk file formats (`.mkpx` v10 and
//! the Animator's `.mkps`): CRC-32C, the little-endian + canonical-LEB128 writer/reader, chunk
//! framing with critical/ancillary semantics, the fixed `INTG` whole-file integrity trailer,
//! the per-tile codec menu (`RAW`/`RLE`/`INDEXED` with a RAW floor), the content-addressed tile
//! dictionary, and the RLE tile-ref grids. Extracted verbatim from the `.mkpx` codec (2026-07-30);
//! every output byte and error string is unchanged. Dependency-free and byte-deterministic.

use crate::buffer::{RgbaBuffer, Tile};
use std::collections::HashMap;
use std::sync::Arc;

pub const TILE_BYTES: usize = 32 * 32 * 4; // 4096
pub const CELL_PX: usize = 1024;
pub const MAX_STR: usize = 4096;
/// The fixed `INTG` trailer size: fourcc(4) + flags(1) + length(4) + crc32c payload(4).
pub const INTG_LEN: usize = 13;

/// Container/codec error. The `Display` wording is the `.mkpx` codec's (this type predates the
/// extraction and its messages are pinned by tests and shell copy); a second format wraps this
/// type and words its own messages.
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
            crc = if crc & 1 != 0 { (crc >> 1) ^ 0x82F6_3B78 } else { crc >> 1 };
            j += 1;
        }
        table[i] = crc;
        i += 1;
    }
    table
}
static CRC32C_TABLE: [u32; 256] = crc32c_table();

pub fn crc32c(bytes: &[u8]) -> u32 {
    let mut crc = 0xFFFF_FFFFu32;
    for &b in bytes {
        crc = (crc >> 8) ^ CRC32C_TABLE[((crc ^ b as u32) & 0xFF) as usize];
    }
    crc ^ 0xFFFF_FFFF
}

// ---- little-endian + varint writer/reader ----

pub struct Writer {
    buf: Vec<u8>,
}
impl Writer {
    pub fn new() -> Self {
        Writer { buf: Vec::new() }
    }
    pub fn u8(&mut self, v: u8) {
        self.buf.push(v);
    }
    pub fn u16(&mut self, v: u16) {
        self.buf.extend_from_slice(&v.to_le_bytes());
    }
    pub fn u32(&mut self, v: u32) {
        self.buf.extend_from_slice(&v.to_le_bytes());
    }
    pub fn u128(&mut self, v: u128) {
        self.buf.extend_from_slice(&v.to_le_bytes());
    }
    pub fn bytes(&mut self, b: &[u8]) {
        self.buf.extend_from_slice(b);
    }
    /// Canonical unsigned LEB128 (minimal length).
    pub fn varint(&mut self, v: u32) {
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
    pub fn str(&mut self, s: &str) {
        let b = s.as_bytes();
        let n = b.len().min(MAX_STR);
        self.varint(n as u32);
        self.bytes(&b[..n]);
    }
    pub fn len(&self) -> usize {
        self.buf.len()
    }
    pub fn is_empty(&self) -> bool {
        self.buf.is_empty()
    }
    /// Pre-size the buffer exactly (so big writes never overshoot by doubling — memlab M5).
    pub fn reserve_exact(&mut self, n: usize) {
        self.buf.reserve_exact(n);
    }
    pub fn as_bytes(&self) -> &[u8] {
        &self.buf
    }
    pub fn into_bytes(self) -> Vec<u8> {
        self.buf
    }
}

impl Default for Writer {
    fn default() -> Self {
        Self::new()
    }
}

pub struct Reader<'a> {
    buf: &'a [u8],
    pos: usize,
}
impl<'a> Reader<'a> {
    pub fn new(buf: &'a [u8]) -> Self {
        Reader { buf, pos: 0 }
    }
    pub fn remaining(&self) -> usize {
        self.buf.len().saturating_sub(self.pos)
    }
    pub fn take(&mut self, n: usize) -> Result<&'a [u8], IoError> {
        let end = self.pos.checked_add(n).ok_or(IoError::Incomplete)?;
        let s = self.buf.get(self.pos..end).ok_or(IoError::Incomplete)?;
        self.pos = end;
        Ok(s)
    }
    pub fn u8(&mut self) -> Result<u8, IoError> {
        Ok(self.take(1)?[0])
    }
    pub fn u16(&mut self) -> Result<u16, IoError> {
        let s = self.take(2)?;
        Ok(u16::from_le_bytes([s[0], s[1]]))
    }
    pub fn u32(&mut self) -> Result<u32, IoError> {
        let s = self.take(4)?;
        Ok(u32::from_le_bytes([s[0], s[1], s[2], s[3]]))
    }
    pub fn u128(&mut self) -> Result<u128, IoError> {
        let s = self.take(16)?;
        let mut a = [0u8; 16];
        a.copy_from_slice(s);
        Ok(u128::from_le_bytes(a))
    }
    /// Canonical unsigned LEB128 into a `u32`: ≤5 bytes, minimal, non-overflowing.
    pub fn varint(&mut self) -> Result<u32, IoError> {
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
    pub fn str(&mut self) -> Result<String, IoError> {
        let n = self.varint()? as usize;
        if n > MAX_STR {
            return Err(IoError::TooLarge("string"));
        }
        Ok(String::from_utf8_lossy(self.take(n)?).into_owned())
    }
}

/// Bits needed to index `n` distinct colors: `0` for a solid tile, else `ceil(log2(n))` (≤8).
pub fn bits_needed(n: usize) -> u32 {
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

pub fn rle_encode(b: &[u8]) -> Vec<u8> {
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
pub fn indexed_encode(b: &[u8]) -> Option<Vec<u8>> {
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
pub fn encode_tile(b: &[u8]) -> (u8, Vec<u8>) {
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

pub fn decode_tile(r: &mut Reader, codec: u8) -> Result<Vec<u8>, IoError> {
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

// ---- chunk framing ----

pub fn write_chunk(w: &mut Writer, fourcc: &[u8; 4], critical: bool, payload: &[u8]) {
    w.bytes(fourcc);
    w.u8(critical as u8); // bit0 = critical
    w.u32(payload.len() as u32);
    w.bytes(payload);
}

/// Append the `INTG` trailer chunk: the CRC-32C of everything already written to `w`
/// (signature + all chunks so far).
pub fn finish_intg(w: &mut Writer) {
    let crc = crc32c(&w.buf);
    let mut intg = Writer::new();
    intg.u32(crc);
    write_chunk(w, b"INTG", true, &intg.buf);
}

/// Verify `signature` and the fixed 13-byte `INTG` trailer, including the whole-file CRC —
/// **before** any body byte is trusted. Returns `body_end` (the offset where the trailer starts).
pub fn verify_intg(data: &[u8], signature: &[u8; 8]) -> Result<usize, IoError> {
    if data.len() < 8 + INTG_LEN {
        return Err(IoError::Incomplete);
    }
    if data[..8] != signature[..] {
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
    Ok(body_end)
}

/// Single forward walk of `data[8..body_end]`, enforcing the framing (header fits, length fits,
/// no trailing bytes) and that the first chunk's fourcc is `first` (failing with `first_err`, so
/// each format keeps its own wording). `visit(fourcc, critical, payload)` performs the
/// format-specific dispatch: slot filling, duplicate detection, known-ancillary skips, and
/// unknown-critical rejection all live in the visitor.
pub fn walk_chunks<'a>(
    data: &'a [u8],
    body_end: usize,
    first: &[u8; 4],
    first_err: &'static str,
    mut visit: impl FnMut(&[u8; 4], bool, &'a [u8]) -> Result<(), IoError>,
) -> Result<(), IoError> {
    let mut pos = 8usize;
    let mut is_first = true;
    while pos < body_end {
        if pos + 9 > body_end {
            return Err(IoError::Corrupt("chunk header"));
        }
        let fourcc: [u8; 4] = match data[pos..pos + 4].try_into() {
            Ok(a) => a,
            Err(_) => return Err(IoError::Corrupt("fourcc")),
        };
        let critical = data[pos + 4] & 1 != 0;
        let len =
            u32::from_le_bytes([data[pos + 5], data[pos + 6], data[pos + 7], data[pos + 8]]) as usize;
        let start = pos + 9;
        let end = start.checked_add(len).ok_or(IoError::Corrupt("chunk length"))?;
        if end > body_end {
            return Err(IoError::Corrupt("chunk length"));
        }
        if is_first && &fourcc != first {
            return Err(IoError::Corrupt(first_err));
        }
        is_first = false;
        visit(&fourcc, critical, &data[start..end])?;
        pos = end;
    }
    if pos != body_end {
        return Err(IoError::Corrupt("trailing bytes"));
    }
    Ok(())
}

// ---- content-addressed tile dictionary + ref grids ----

/// The content-addressed tile dictionary builder: distinct present tiles in **first-appearance
/// order**. Entries are the live `Arc<Tile>`s — no byte clones. Lookup is two-level: an
/// `Arc`-pointer cache catches COW-shared repeats without touching pixels, then a content-hash
/// map (u128, byte-equality verified on hit so a hash collision can only cost a compare, never
/// corrupt the file). Invariant: the dictionary holds every interned `Arc` alive for the
/// builder's lifetime, so a raw-pointer cache entry can never alias a reused address.
pub struct TileDict {
    order: Vec<Arc<Tile>>,
    by_ptr: HashMap<*const Tile, u32>,
    by_hash: HashMap<u128, Vec<u32>>, // 1-based candidate ids
}

impl TileDict {
    pub fn new() -> Self {
        TileDict { order: Vec::new(), by_ptr: HashMap::new(), by_hash: HashMap::new() }
    }

    /// Intern every cell of `buf` (row-major tile order) and return its per-cell reference grid
    /// (0 = absent tile; ids are 1-based, in first-appearance order across all `grid_for` calls).
    pub fn grid_for(&mut self, buf: &RgbaBuffer) -> Vec<u32> {
        let nt = buf.num_tiles();
        let mut grid = Vec::with_capacity(nt);
        for i in 0..nt {
            let id = match buf.tile_arc(i) {
                None => 0u32,
                Some(t) => {
                    let ptr = Arc::as_ptr(t);
                    match self.by_ptr.get(&ptr) {
                        Some(&id) => id,
                        None => {
                            let h = t.content_hash();
                            let cands = self.by_hash.entry(h).or_default();
                            let id = match cands
                                .iter()
                                .copied()
                                .find(|&id| *self.order[(id - 1) as usize] == **t)
                            {
                                Some(id) => id,
                                None => {
                                    self.order.push(t.clone());
                                    let id = self.order.len() as u32;
                                    cands.push(id);
                                    id
                                }
                            };
                            self.by_ptr.insert(ptr, id);
                            id
                        }
                    }
                }
            };
            grid.push(id);
        }
        grid
    }

    pub fn len(&self) -> usize {
        self.order.len()
    }

    pub fn is_empty(&self) -> bool {
        self.order.is_empty()
    }

    /// Write the dictionary payload: varint count, then per tile a u8 codec + payload — one
    /// 4096-byte temp per entry, encoded and dropped; never the whole set at once. Pre-sized
    /// (worst case ≈ RAW cells) so the Vec never overshoots by doubling (memlab M5).
    pub fn write(&self, w: &mut Writer) {
        w.reserve_exact(self.order.len() * (TILE_BYTES + 8) + 16);
        w.varint(self.order.len() as u32);
        for t in &self.order {
            let b = t.to_bytes();
            let (codec, payload) = encode_tile(&b);
            w.u8(codec);
            w.bytes(&payload);
        }
    }
}

impl Default for TileDict {
    fn default() -> Self {
        Self::new()
    }
}

/// Read a tile dictionary: refuses `count > max_tiles` (`TooLarge("tile dictionary")`) and
/// `count × 4096 > hard_budget` (`TooLarge("memory budget")`) **before** materializing a single
/// tile — the dictionary IS the document's unique tile payload (SPEC §8.2b).
pub fn read_tile_dict(
    r: &mut Reader,
    max_tiles: usize,
    hard_budget: usize,
) -> Result<Vec<Arc<Tile>>, IoError> {
    let tile_count = r.varint()? as usize;
    if tile_count > max_tiles {
        return Err(IoError::TooLarge("tile dictionary"));
    }
    if tile_count.saturating_mul(4096) > hard_budget {
        return Err(IoError::TooLarge("memory budget"));
    }
    let mut dict: Vec<Arc<Tile>> = Vec::with_capacity(tile_count.min(r.remaining() / 2 + 1));
    for _ in 0..tile_count {
        let codec = r.u8()?;
        let bytes = decode_tile(r, codec)?;
        dict.push(Arc::new(Tile::from_bytes(&bytes).ok_or(IoError::Corrupt("tile"))?));
    }
    Ok(dict)
}

/// Write a reference grid as `(run, id)` varint pairs covering the whole grid.
pub fn write_ref_grid(w: &mut Writer, grid: &[u32]) {
    let nt = grid.len();
    let mut i = 0usize;
    while i < nt {
        let idx = grid[i];
        let mut run = 1usize;
        while i + run < nt && grid[i + run] == idx {
            run += 1;
        }
        w.varint(run as u32);
        w.varint(idx);
        i += run;
    }
}

/// Read a reference grid, installing dictionary tiles cell-by-cell into `pixels` (one shared
/// `Arc` per distinct tile — this is what restores COW sharing on load).
pub fn read_ref_grid(
    r: &mut Reader,
    dict: &[Arc<Tile>],
    pixels: &mut RgbaBuffer,
) -> Result<(), IoError> {
    let cells = pixels.num_tiles();
    let mut filled = 0usize;
    while filled < cells {
        let run = r.varint()? as usize;
        let idx = r.varint()? as usize;
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
    Ok(())
}
