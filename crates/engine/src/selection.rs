//! `Mask` — a 1-bit, document-sized selection (SPEC §12). Editor state, not persisted.
//! Selection geometry reuses `raster`. Combine modes compose a freshly-rasterized shape
//! with the existing selection.

use crate::buffer::RgbaBuffer;
use crate::color::max_channel_delta;
use crate::geom::{IRect, Point};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CombineMode {
    Replace,
    Add,
    Subtract,
    Intersect,
}

#[derive(Clone, PartialEq, Eq)]
pub struct Mask {
    w: u32,
    h: u32,
    bits: Vec<u64>, // packed, 1 bit per pixel, row-major
}

impl std::fmt::Debug for Mask {
    // Compact: dims + set-bit count + bounds — never dump the whole bitset (huge on a failure).
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Mask")
            .field("w", &self.w)
            .field("h", &self.h)
            .field("count", &self.count())
            .field("bounds", &self.bounds())
            .finish()
    }
}

impl Mask {
    pub fn new(w: u32, h: u32) -> Self {
        let words = ((w * h) as usize).div_ceil(64);
        Mask { w, h, bits: vec![0u64; words] }
    }

    pub fn width(&self) -> u32 {
        self.w
    }
    pub fn height(&self) -> u32 {
        self.h
    }

    /// Packed bit words (row-major, 1 bit/pixel), for serialization (`io`). The slice length is
    /// always `(w*h).div_ceil(64)`.
    pub fn as_words(&self) -> &[u64] {
        &self.bits
    }

    /// Approximate resident bytes of this mask (the packed bit words; the struct header is
    /// negligible). Used by `probe::mem_report` to account masks retained by undo records.
    pub fn memory_bytes(&self) -> usize {
        self.bits.len() * 8
    }

    /// Rebuild a mask from serialized `w`×`h` dimensions and its packed bit words. Returns `None`
    /// when the word count doesn't match the dimensions (corrupt input), so the loader can reject
    /// or drop a bad selection rather than trust mismatched data.
    pub fn from_words(w: u32, h: u32, words: Vec<u64>) -> Option<Mask> {
        if words.len() != ((w as usize) * (h as usize)).div_ceil(64) {
            return None;
        }
        let mut m = Mask { w, h, bits: words };
        m.trim_tail(); // defensively clear any out-of-range tail bits a crafted file might set
        Some(m)
    }

    #[inline]
    fn idx(&self, x: i32, y: i32) -> Option<usize> {
        if x < 0 || y < 0 || x as u32 >= self.w || y as u32 >= self.h {
            None
        } else {
            Some((y as u32 * self.w + x as u32) as usize)
        }
    }

    #[inline]
    pub fn get(&self, x: i32, y: i32) -> bool {
        match self.idx(x, y) {
            Some(i) => (self.bits[i / 64] >> (i % 64)) & 1 == 1,
            None => false,
        }
    }

    #[inline]
    pub fn set(&mut self, x: i32, y: i32, v: bool) {
        if let Some(i) = self.idx(x, y) {
            let word = i / 64;
            let bit = i % 64;
            if v {
                self.bits[word] |= 1u64 << bit;
            } else {
                self.bits[word] &= !(1u64 << bit);
            }
        }
    }

    pub fn clear(&mut self) {
        for w in &mut self.bits {
            *w = 0;
        }
    }

    pub fn select_all(&mut self) {
        for w in &mut self.bits {
            *w = u64::MAX;
        }
        self.trim_tail();
    }

    /// Mask out bits beyond w*h in the final word.
    fn trim_tail(&mut self) {
        let total = (self.w * self.h) as usize;
        let rem = total % 64;
        if rem != 0 {
            let last = self.bits.len() - 1;
            self.bits[last] &= (1u64 << rem) - 1;
        }
    }

    pub fn invert(&mut self) {
        for w in &mut self.bits {
            *w = !*w;
        }
        self.trim_tail();
    }

    /// Clear every set bit outside `r`, keeping only the selection within that window (storage
    /// coordinates). Holds a selection gesture inside the editable region — the canvas, or the whole
    /// storage area when the overscan view is on (SPEC §8, §12).
    pub fn intersect_rect(&mut self, r: IRect) {
        for y in 0..self.h as i32 {
            for x in 0..self.w as i32 {
                if !r.contains(Point::new(x, y)) {
                    self.set(x, y, false);
                }
            }
        }
    }

    pub fn is_empty(&self) -> bool {
        self.bits.iter().all(|&w| w == 0)
    }

    /// `Some(self)` when at least one pixel is selected, else `None`. A mask with zero set bits
    /// means "no selection" — every writer of `Document::selection` normalizes through this, so a
    /// selection op that ends with nothing selected (e.g. Subtract covering the whole selection)
    /// frees the canvas instead of leaving an invisible mask that blocks every edit.
    pub fn nonempty(self) -> Option<Mask> {
        if self.is_empty() { None } else { Some(self) }
    }

    pub fn count(&self) -> u64 {
        self.bits.iter().map(|w| w.count_ones() as u64).sum()
    }

    pub fn bounds(&self) -> Option<IRect> {
        let (mut minx, mut miny, mut maxx, mut maxy) = (i32::MAX, i32::MAX, i32::MIN, i32::MIN);
        for y in 0..self.h as i32 {
            for x in 0..self.w as i32 {
                if self.get(x, y) {
                    minx = minx.min(x);
                    miny = miny.min(y);
                    maxx = maxx.max(x);
                    maxy = maxy.max(y);
                }
            }
        }
        if maxx < minx {
            None
        } else {
            Some(IRect::new(minx, miny, (maxx - minx + 1) as u32, (maxy - miny + 1) as u32))
        }
    }

    /// Combine a temporary single-shape mask (`shape`) into `self` per `mode`.
    pub fn combine(&mut self, shape: &Mask, mode: CombineMode) {
        debug_assert!(self.w == shape.w && self.h == shape.h);
        match mode {
            CombineMode::Replace => self.bits.copy_from_slice(&shape.bits),
            CombineMode::Add => {
                for (a, b) in self.bits.iter_mut().zip(&shape.bits) {
                    *a |= *b;
                }
            }
            CombineMode::Subtract => {
                for (a, b) in self.bits.iter_mut().zip(&shape.bits) {
                    *a &= !*b;
                }
            }
            CombineMode::Intersect => {
                for (a, b) in self.bits.iter_mut().zip(&shape.bits) {
                    *a &= *b;
                }
            }
        }
        self.trim_tail();
    }

    /// Translate the selection by (dx, dy), dropping bits that fall off-canvas.
    pub fn translated(&self, dx: i32, dy: i32) -> Mask {
        let mut out = Mask::new(self.w, self.h);
        for y in 0..self.h as i32 {
            for x in 0..self.w as i32 {
                if self.get(x, y) {
                    out.set(x + dx, y + dy, true);
                }
            }
        }
        out
    }

    /// Like [`translated`], but set bits leaving a `canvas` edge re-enter the opposite edge
    /// (toroidal, wrapping around the canvas rect — not the larger storage grid) — so a wrapped pixel
    /// move's selection follows the pixels.
    pub fn translated_wrapped(&self, dx: i32, dy: i32, canvas: IRect) -> Mask {
        let mut out = Mask::new(self.w, self.h);
        let (cw, ch) = (canvas.w as i32, canvas.h as i32);
        if cw <= 0 || ch <= 0 {
            return out;
        }
        for y in 0..self.h as i32 {
            for x in 0..self.w as i32 {
                if self.get(x, y) {
                    let nx = canvas.x + (x + dx - canvas.x).rem_euclid(cw);
                    let ny = canvas.y + (y + dy - canvas.y).rem_euclid(ch);
                    out.set(nx, ny, true);
                }
            }
        }
        out
    }

    // ---- shape constructors (a temporary mask to combine) ----

    pub fn from_plot(w: u32, h: u32, f: impl FnOnce(&mut dyn FnMut(i32, i32))) -> Mask {
        let mut m = Mask::new(w, h);
        f(&mut |x, y| m.set(x, y, true));
        m
    }

    /// Color-threshold selection: contiguous (4-connected flood) or global.
    pub fn from_color(
        w: u32,
        h: u32,
        buf: &RgbaBuffer,
        seed: Point,
        threshold: u8,
        contiguous: bool,
    ) -> Mask {
        let mut m = Mask::new(w, h);
        let target = buf.get(seed.x, seed.y);
        let matches = |x: i32, y: i32| max_channel_delta(buf.get(x, y), target) <= threshold;
        if contiguous {
            let mut stack = vec![seed];
            while let Some(p) = stack.pop() {
                if p.x < 0 || p.y < 0 || p.x as u32 >= w || p.y as u32 >= h {
                    continue;
                }
                if m.get(p.x, p.y) || !matches(p.x, p.y) {
                    continue;
                }
                m.set(p.x, p.y, true);
                stack.push(Point::new(p.x + 1, p.y));
                stack.push(Point::new(p.x - 1, p.y));
                stack.push(Point::new(p.x, p.y + 1));
                stack.push(Point::new(p.x, p.y - 1));
            }
        } else {
            for y in 0..h as i32 {
                for x in 0..w as i32 {
                    if matches(x, y) {
                        m.set(x, y, true);
                    }
                }
            }
        }
        m
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::raster;

    #[test]
    fn all_and_invert() {
        let mut m = Mask::new(8, 8);
        m.select_all();
        assert_eq!(m.count(), 64);
        m.invert();
        assert_eq!(m.count(), 0);
    }

    #[test]
    fn invert_twice_identity() {
        let mut m = Mask::from_plot(16, 16, |p| raster::rect_filled(Point::new(2, 2), Point::new(5, 5), p));
        let before = m.count();
        m.invert();
        m.invert();
        assert_eq!(m.count(), before);
    }

    #[test]
    fn combine_modes() {
        let a = Mask::from_plot(16, 16, |p| raster::rect_filled(Point::new(0, 0), Point::new(7, 7), p));
        let b = Mask::from_plot(16, 16, |p| raster::rect_filled(Point::new(4, 4), Point::new(11, 11), p));
        let mut u = a.clone();
        u.combine(&b, CombineMode::Add);
        assert_eq!(u.count(), 64 + 64 - 16);
        let mut inter = a.clone();
        inter.combine(&b, CombineMode::Intersect);
        assert_eq!(inter.count(), 16);
        let mut sub = a.clone();
        sub.combine(&b, CombineMode::Subtract);
        assert_eq!(sub.count(), 64 - 16);
    }

    #[test]
    fn words_roundtrip_and_reject_bad_length() {
        let mut m = Mask::from_plot(20, 12, |p| raster::rect_filled(Point::new(2, 1), Point::new(9, 7), p));
        m.set(0, 0, true);
        let words = m.as_words().to_vec();
        let back = Mask::from_words(20, 12, words).expect("valid word count round-trips");
        assert_eq!(back, m);
        // A word count that doesn't match the dimensions is rejected (corrupt input).
        assert!(Mask::from_words(20, 12, vec![0u64; 1]).is_none());
    }

    #[test]
    fn color_select_contiguous_vs_global() {
        let mut buf = RgbaBuffer::new(8, 8);
        buf.fill_rect(IRect::new(0, 0, 3, 3), crate::color::Rgba8::WHITE);
        buf.fill_rect(IRect::new(5, 5, 2, 2), crate::color::Rgba8::WHITE);
        let cont = Mask::from_color(8, 8, &buf, Point::new(0, 0), 0, true);
        assert_eq!(cont.count(), 9);
        let glob = Mask::from_color(8, 8, &buf, Point::new(0, 0), 0, false);
        assert_eq!(glob.count(), 13);
    }
}
