//! `RgbaBuffer` — tiled, copy-on-write, lazily-allocated pixel container (SPEC §8).
//!
//! Pixels are stored **straight** `Rgba8` (losslessness-first; compositing premultiplies
//! transiently). A buffer is a grid of 32×32 tiles; an untouched tile is `None` (fully
//! transparent) and costs nothing. Writes copy-on-write only the touched tile, so a small
//! edit never rewrites a 256 KiB buffer, duplicating a layer/frame is `Arc`-cheap, and the
//! dirty set is recovered by comparing tile `Arc` pointers (powers undo, SPEC §10.2).

use crate::color::Rgba8;
use crate::geom::{IRect, Point, Size};
use crate::util::{Hash, Hasher};
use std::sync::Arc;

pub const TILE: u32 = 32;
const TILE_AREA: usize = (TILE * TILE) as usize;

#[derive(Clone, PartialEq, Eq)]
pub struct Tile(pub [Rgba8; TILE_AREA]);

impl Tile {
    fn transparent() -> Tile {
        Tile([Rgba8::TRANSPARENT; TILE_AREA])
    }
    fn is_all_transparent(&self) -> bool {
        self.0.iter().all(|p| p.a == 0)
    }
}

#[derive(Clone)]
pub struct RgbaBuffer {
    w: u32,
    h: u32,
    tiles_x: u32,
    tiles_y: u32,
    tiles: Vec<Option<Arc<Tile>>>,
}

/// A reversible change to a buffer expressed as changed tiles (COW snapshots). Cheap to
/// store and apply; the basis of one undo record (SPEC §10.2).
#[derive(Clone)]
pub struct TilePatch {
    changed: Vec<(usize, Option<Arc<Tile>>, Option<Arc<Tile>>)>, // (idx, before, after)
    pub dirty: IRect,
}

impl TilePatch {
    pub fn is_empty(&self) -> bool {
        self.changed.is_empty()
    }
}

impl RgbaBuffer {
    pub fn new(w: u32, h: u32) -> Self {
        let tiles_x = w.div_ceil(TILE);
        let tiles_y = h.div_ceil(TILE);
        RgbaBuffer {
            w,
            h,
            tiles_x,
            tiles_y,
            tiles: vec![None; (tiles_x * tiles_y) as usize],
        }
    }

    pub fn from_size(s: Size) -> Self {
        RgbaBuffer::new(s.w as u32, s.h as u32)
    }

    pub fn width(&self) -> u32 {
        self.w
    }
    pub fn height(&self) -> u32 {
        self.h
    }
    pub fn size(&self) -> Size {
        Size::new(self.w as u16, self.h as u16)
    }

    #[inline]
    fn in_bounds(&self, x: i32, y: i32) -> bool {
        x >= 0 && y >= 0 && (x as u32) < self.w && (y as u32) < self.h
    }

    #[inline]
    fn tile_index(&self, x: u32, y: u32) -> (usize, usize) {
        let tx = x / TILE;
        let ty = y / TILE;
        let local = (y % TILE) * TILE + (x % TILE);
        ((ty * self.tiles_x + tx) as usize, local as usize)
    }

    /// Out-of-bounds reads return transparent (the canvas is unbounded transparency).
    #[inline]
    pub fn get(&self, x: i32, y: i32) -> Rgba8 {
        if !self.in_bounds(x, y) {
            return Rgba8::TRANSPARENT;
        }
        let (ti, li) = self.tile_index(x as u32, y as u32);
        match &self.tiles[ti] {
            Some(t) => t.0[li],
            None => Rgba8::TRANSPARENT,
        }
    }

    /// Out-of-bounds writes are ignored. Writing transparent into an absent tile is a no-op
    /// (keeps sparsity).
    #[inline]
    pub fn set(&mut self, x: i32, y: i32, c: Rgba8) {
        if !self.in_bounds(x, y) {
            return;
        }
        let (ti, li) = self.tile_index(x as u32, y as u32);
        if self.tiles[ti].is_none() {
            if c.a == 0 {
                return;
            }
            self.tiles[ti] = Some(Arc::new(Tile::transparent()));
        }
        let tile = Arc::make_mut(self.tiles[ti].as_mut().unwrap());
        tile.0[li] = c;
    }

    /// Alpha-over a straight color onto a pixel (respects existing content).
    #[inline]
    pub fn blend_over(&mut self, x: i32, y: i32, c: Rgba8) {
        if c.a == 0 {
            return;
        }
        if c.a == 255 {
            self.set(x, y, c);
            return;
        }
        let dst = self.get(x, y);
        self.set(x, y, crate::color::over(c, dst));
    }

    pub fn fill_rect(&mut self, r: IRect, c: Rgba8) {
        let r = r.clamp_to(self.w, self.h);
        for y in r.y..r.bottom() {
            for x in r.x..r.right() {
                self.set(x, y, c);
            }
        }
    }

    pub fn fill_all(&mut self, c: Rgba8) {
        self.fill_rect(IRect::new(0, 0, self.w, self.h), c);
    }

    pub fn clear(&mut self) {
        for t in &mut self.tiles {
            *t = None;
        }
    }

    /// Drop tiles that became fully transparent (sparsity maintenance after erases).
    pub fn compact(&mut self) {
        for t in &mut self.tiles {
            if let Some(tile) = t {
                if tile.is_all_transparent() {
                    *t = None;
                }
            }
        }
    }

    /// Deterministic content hash over present tiles (and their grid positions).
    pub fn content_hash(&self) -> Hash {
        let mut h = Hasher::new();
        h.write_u32(self.w);
        h.write_u32(self.h);
        for (i, t) in self.tiles.iter().enumerate() {
            match t {
                None => h.write(&[0]),
                Some(tile) => {
                    h.write(&[1]);
                    h.write_u32(i as u32);
                    for p in &tile.0 {
                        h.write(&[p.r, p.g, p.b, p.a]);
                    }
                }
            }
        }
        h.finish()
    }

    /// Approximate resident bytes: 4 bytes per pixel of each *present* tile (SPEC §8 stats).
    pub fn memory_bytes(&self) -> usize {
        self.tiles.iter().filter(|t| t.is_some()).count() * TILE_AREA * 4
    }

    pub fn present_tiles(&self) -> usize {
        self.tiles.iter().filter(|t| t.is_some()).count()
    }

    pub fn is_empty(&self) -> bool {
        self.tiles.iter().all(|t| t.is_none())
    }

    /// Bounding box of all non-transparent pixels, or `None` if fully transparent. Used to keep
    /// opaque content on-canvas when "protect pixels" is on (SPEC §15 / §28.1).
    pub fn opaque_bounds(&self) -> Option<IRect> {
        let (mut minx, mut miny, mut maxx, mut maxy) = (i32::MAX, i32::MAX, i32::MIN, i32::MIN);
        for ty in 0..self.tiles_y {
            for tx in 0..self.tiles_x {
                let ti = (ty * self.tiles_x + tx) as usize;
                if let Some(tile) = &self.tiles[ti] {
                    for ly in 0..TILE {
                        for lx in 0..TILE {
                            if tile.0[(ly * TILE + lx) as usize].a != 0 {
                                let x = (tx * TILE + lx) as i32;
                                let y = (ty * TILE + ly) as i32;
                                minx = minx.min(x);
                                miny = miny.min(y);
                                maxx = maxx.max(x);
                                maxy = maxy.max(y);
                            }
                        }
                    }
                }
            }
        }
        if maxx < minx {
            None
        } else {
            Some(IRect::new(minx, miny, (maxx - minx + 1) as u32, (maxy - miny + 1) as u32))
        }
    }

    // ---- COW undo support ----

    /// Cheap snapshot of the tile table (Arc clones only). Used as the "before" state.
    pub fn snapshot(&self) -> Vec<Option<Arc<Tile>>> {
        self.tiles.clone()
    }

    /// Revert the buffer to a previously taken [`snapshot`](Self::snapshot), discarding any changes
    /// made since (used to abort an in-progress stroke without recording undo). No-op on a size
    /// mismatch.
    pub fn restore_snapshot(&mut self, snap: &[Option<Arc<Tile>>]) {
        if snap.len() == self.tiles.len() {
            self.tiles.clear();
            self.tiles.extend(snap.iter().cloned());
        }
    }

    /// Compute the patch that turns `before` into the current state (changed tiles only).
    pub fn diff_from(&self, before: &[Option<Arc<Tile>>]) -> TilePatch {
        let mut changed = Vec::new();
        let (mut minx, mut miny, mut maxx, mut maxy) = (i32::MAX, i32::MAX, i32::MIN, i32::MIN);
        for (i, (b, a)) in before.iter().zip(self.tiles.iter()).enumerate() {
            let same = match (b, a) {
                (None, None) => true,
                (Some(x), Some(y)) => Arc::ptr_eq(x, y) || x == y,
                _ => false,
            };
            if !same {
                changed.push((i, b.clone(), a.clone()));
                let tx = (i as u32 % self.tiles_x) as i32;
                let ty = (i as u32 / self.tiles_x) as i32;
                minx = minx.min(tx * TILE as i32);
                miny = miny.min(ty * TILE as i32);
                maxx = maxx.max((tx + 1) * TILE as i32);
                maxy = maxy.max((ty + 1) * TILE as i32);
            }
        }
        let dirty = if maxx < minx {
            IRect::new(0, 0, 0, 0)
        } else {
            IRect::new(minx, miny, (maxx - minx) as u32, (maxy - miny) as u32).clamp_to(self.w, self.h)
        };
        TilePatch { changed, dirty }
    }

    pub fn apply_before(&mut self, patch: &TilePatch) {
        for (i, b, _a) in &patch.changed {
            self.tiles[*i] = b.clone();
        }
    }

    pub fn apply_after(&mut self, patch: &TilePatch) {
        for (i, _b, a) in &patch.changed {
            self.tiles[*i] = a.clone();
        }
    }

    /// Copy a sub-rect out as a new compact buffer (for clipboard/move/import).
    pub fn subimage(&self, r: IRect) -> RgbaBuffer {
        let mut out = RgbaBuffer::new(r.w, r.h);
        for j in 0..r.h as i32 {
            for i in 0..r.w as i32 {
                let c = self.get(r.x + i, r.y + j);
                if c.a != 0 {
                    out.set(i, j, c);
                }
            }
        }
        out
    }

    /// Overwrite-blit `src` with its top-left at `at` (used by paste/move/import).
    pub fn blit(&mut self, src: &RgbaBuffer, at: Point) {
        for j in 0..src.h as i32 {
            for i in 0..src.w as i32 {
                self.set(at.x + i, at.y + j, src.get(i, j));
            }
        }
    }

    /// Alpha-over blit `src` with its top-left at `at`.
    pub fn blit_over(&mut self, src: &RgbaBuffer, at: Point) {
        for j in 0..src.h as i32 {
            for i in 0..src.w as i32 {
                let c = src.get(i, j);
                if c.a != 0 {
                    self.blend_over(at.x + i, at.y + j, c);
                }
            }
        }
    }

    /// Blit `src` shifted by (dx,dy) with toroidal wrap-around: a source pixel at (x,y) lands at
    /// ((x+dx) mod w, (y+dy) mod h), so nothing falls off the canvas (the Move tool's Wrap mode).
    /// Only non-transparent source pixels are written, so clear `self` first.
    pub fn blit_wrapped(&mut self, src: &RgbaBuffer, dx: i32, dy: i32) {
        let (w, h) = (self.w as i32, self.h as i32);
        if w <= 0 || h <= 0 {
            return;
        }
        for j in 0..src.h as i32 {
            for i in 0..src.w as i32 {
                let c = src.get(i, j);
                if c.a != 0 {
                    self.set((i + dx).rem_euclid(w), (j + dy).rem_euclid(h), c);
                }
            }
        }
    }

    // ---- sparse tile serialization (for .mkpx; SPEC §17) ----

    pub fn num_tiles(&self) -> usize {
        self.tiles.len()
    }

    /// Raw 4096-byte RGBA of tile `i`, or `None` if the tile is absent (transparent).
    pub fn tile_bytes(&self, i: usize) -> Option<Vec<u8>> {
        self.tiles[i].as_ref().map(|t| {
            let mut v = Vec::with_capacity(TILE_AREA * 4);
            for p in &t.0 {
                v.extend_from_slice(&[p.r, p.g, p.b, p.a]);
            }
            v
        })
    }

    /// Install tile `i` from 4096 raw RGBA bytes.
    pub fn put_tile_bytes(&mut self, i: usize, bytes: &[u8]) {
        if bytes.len() < TILE_AREA * 4 || i >= self.tiles.len() {
            return;
        }
        let mut arr = [Rgba8::TRANSPARENT; TILE_AREA];
        for (k, slot) in arr.iter_mut().enumerate() {
            let o = k * 4;
            *slot = Rgba8::new(bytes[o], bytes[o + 1], bytes[o + 2], bytes[o + 3]);
        }
        self.tiles[i] = Some(Arc::new(Tile(arr)));
    }

    /// Flatten to a tightly-packed row-major straight-RGBA byte buffer (for FFI/display/io).
    pub fn to_rgba_bytes(&self) -> Vec<u8> {
        let mut out = vec![0u8; (self.w * self.h * 4) as usize];
        for y in 0..self.h as i32 {
            for x in 0..self.w as i32 {
                let c = self.get(x, y);
                let i = ((y as u32 * self.w + x as u32) * 4) as usize;
                out[i] = c.r;
                out[i + 1] = c.g;
                out[i + 2] = c.b;
                out[i + 3] = c.a;
            }
        }
        out
    }

    /// Build from packed row-major straight RGBA bytes.
    pub fn from_rgba_bytes(w: u32, h: u32, bytes: &[u8]) -> RgbaBuffer {
        let mut buf = RgbaBuffer::new(w, h);
        for y in 0..h as i32 {
            for x in 0..w as i32 {
                let i = ((y as u32 * w + x as u32) * 4) as usize;
                if i + 3 < bytes.len() {
                    let c = Rgba8::new(bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3]);
                    if c.a != 0 {
                        buf.set(x, y, c);
                    }
                }
            }
        }
        buf
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn set_get_and_sparsity() {
        let mut b = RgbaBuffer::new(64, 64);
        assert_eq!(b.present_tiles(), 0);
        b.set(10, 10, Rgba8::rgb(1, 2, 3));
        assert_eq!(b.get(10, 10), Rgba8::rgb(1, 2, 3));
        assert_eq!(b.present_tiles(), 1); // only one 32×32 tile materialized
        // transparent write into absent tile stays sparse
        b.set(60, 60, Rgba8::TRANSPARENT);
        assert_eq!(b.present_tiles(), 1);
    }

    #[test]
    fn oob_is_transparent_and_ignored() {
        let mut b = RgbaBuffer::new(16, 16);
        b.set(-1, 5, Rgba8::WHITE);
        b.set(100, 5, Rgba8::WHITE);
        assert!(b.is_empty());
        assert_eq!(b.get(-5, -5), Rgba8::TRANSPARENT);
    }

    #[test]
    fn cow_diff_detects_only_changed_tiles() {
        let mut b = RgbaBuffer::new(96, 96); // 3×3 tiles
        b.set(0, 0, Rgba8::WHITE);
        let before = b.snapshot();
        b.set(70, 70, Rgba8::BLACK); // touch a different tile
        let patch = b.diff_from(&before);
        assert_eq!(patch.changed.len(), 1);
        // undo
        b.apply_before(&patch);
        assert_eq!(b.get(70, 70), Rgba8::TRANSPARENT);
        b.apply_after(&patch);
        assert_eq!(b.get(70, 70), Rgba8::BLACK);
    }

    #[test]
    fn hash_changes_with_content() {
        let mut b = RgbaBuffer::new(32, 32);
        let h0 = b.content_hash();
        b.set(1, 1, Rgba8::WHITE);
        assert_ne!(h0, b.content_hash());
        b.set(1, 1, Rgba8::TRANSPARENT);
        b.compact();
        assert_eq!(h0, b.content_hash()); // back to empty
    }

    #[test]
    fn bytes_roundtrip() {
        let mut b = RgbaBuffer::new(40, 24);
        b.set(5, 5, Rgba8::new(9, 8, 7, 6));
        b.set(39, 23, Rgba8::WHITE);
        let bytes = b.to_rgba_bytes();
        let b2 = RgbaBuffer::from_rgba_bytes(40, 24, &bytes);
        assert_eq!(b.content_hash(), b2.content_hash());
    }

    #[test]
    fn opaque_bounds_correct() {
        let mut b = RgbaBuffer::new(64, 64);
        b.set(10, 12, Rgba8::WHITE);
        b.set(20, 30, Rgba8::WHITE);
        assert_eq!(b.opaque_bounds(), Some(IRect::new(10, 12, 11, 19)));
    }
}
