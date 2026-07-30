//! Pixel-exact rotate/scale resampling of a lifted RGBA region — the engine's transform
//! primitives, extracted from `session/canvas.rs` so they are callable outside the editor's
//! draft machinery (the Animator's compositor is the second consumer). Sampling is
//! nearest-neighbor or the cleanEdge reconstruction (`crate::cleanedge`); both paths are
//! integer-exact at identity and quarter turns and byte-deterministic across platforms.

use crate::buffer::RgbaBuffer;
use crate::geom::{Point, PointF};
use crate::selection::Mask;

/// One lifted `sw`×`sh` source region: pixel (0,0) of the source buffer sits at `src_origin`
/// in destination coords, optionally restricted by a source-sized 1-bit `src_mask`. The op
/// runs about `pivot` (continuous destination coords), then shifts by the whole-pixel `off`
/// (integer, applied after the op, so it never disturbs identity/quarter-turn exactness).
/// `clean_edge`/`clean_edge_width` select the sampler; scale additionally gates cleanEdge to
/// upscaling (see [`Resample::scale`]).
#[derive(Clone, Debug)]
pub struct Resample<'a> {
    pub sw: i32,
    pub sh: i32,
    pub src_origin: Point,
    pub src_mask: Option<&'a Mask>,
    pub pivot: PointF,
    pub off: Point,
    pub clean_edge: bool,
    pub clean_edge_width: f32,
}

impl<'a> Resample<'a> {
    /// Rotation of the lifted source by `angle` radians clockwise about `pivot`, into a
    /// `cw`×`ch` buffer, clipped. Samples nearest-neighbor, or the cleanEdge reconstruction
    /// when `clean_edge` is on (same inverse mapping — cleanEdge only changes which
    /// neighborhood color a sample point takes). Returns the placed pixels and a matching
    /// 1-bit mask of where they landed. Integer-exact and deterministic: at multiples of 90°
    /// on a square region it reproduces the lossless quarter-turn (the snap below makes that
    /// exact for both sampling modes).
    pub fn rotate(&self, src: &RgbaBuffer, angle: f32, cw: i32, ch: i32) -> (RgbaBuffer, Mask) {
        let (sw, sh, src_origin, src_mask, pivot) =
            (self.sw, self.sh, self.src_origin, self.src_mask, self.pivot);
        // Whole-pixel drag-to-move offset, applied AFTER the rotation (integer, so it never
        // disturbs the identity/quarter-turn exactness — it only shifts which cell receives what).
        let (offx, offy) = (self.off.x as f32, self.off.y as f32);
        let mut out = RgbaBuffer::new(cw as u32, ch as u32);
        let mut out_mask = Mask::new(cw as u32, ch as u32);
        // Quarter-turn snap: quarter turns arrive as rounded milliradians (1570/1571, 3141/3142, …),
        // never exact multiples of π/2, so cos/sin carry ~1e-4 of drift that walks sample points off
        // pixel centers on large canvases. Snapping inside a ±2 mrad window makes 90° multiples
        // literally exact — for NN (which only relied on floor absorbing the drift) and for
        // cleanEdge (whose identity margin at minimum line width is thinner than that drift).
        let quarter = (angle / std::f32::consts::FRAC_PI_2).round();
        let (cos, sin) = if (angle - quarter * std::f32::consts::FRAC_PI_2).abs() < 2e-3 {
            match (quarter as i32).rem_euclid(4) {
                0 => (1.0, 0.0),
                1 => (0.0, 1.0),
                2 => (-1.0, 0.0),
                _ => (0.0, -1.0),
            }
        } else {
            (angle.cos(), angle.sin())
        };

        // Destination scan window = the clipped bounding box of the rotated source corners, so we
        // touch only pixels that can possibly receive content.
        let fwd = |px: f32, py: f32| {
            let (dx, dy) = (px - pivot.x, py - pivot.y);
            (pivot.x + cos * dx - sin * dy + offx, pivot.y + sin * dx + cos * dy + offy)
        };
        let (mut minx, mut miny, mut maxx, mut maxy) = (f32::MAX, f32::MAX, f32::MIN, f32::MIN);
        for (px, py) in [
            (src_origin.x as f32, src_origin.y as f32),
            ((src_origin.x + sw) as f32, src_origin.y as f32),
            (src_origin.x as f32, (src_origin.y + sh) as f32),
            ((src_origin.x + sw) as f32, (src_origin.y + sh) as f32),
        ] {
            let (fx, fy) = fwd(px, py);
            minx = minx.min(fx);
            miny = miny.min(fy);
            maxx = maxx.max(fx);
            maxy = maxy.max(fy);
        }
        let x0 = (minx.floor() as i32).max(0);
        let y0 = (miny.floor() as i32).max(0);
        let x1 = (maxx.ceil() as i32).min(cw);
        let y1 = (maxy.ceil() as i32).min(ch);

        for dy in y0..y1 {
            for dx in x0..x1 {
                // Inverse-rotate the destination pixel center back into source space (undo the move
                // offset first, then R(-angle)).
                let (ddx, ddy) =
                    (dx as f32 + 0.5 - offx - pivot.x, dy as f32 + 0.5 - offy - pivot.y);
                let sxf = pivot.x + cos * ddx + sin * ddy;
                let syf = pivot.y - sin * ddx + cos * ddy;
                let lx = (sxf - src_origin.x as f32).floor() as i32;
                let ly = (syf - src_origin.y as f32).floor() as i32;
                if lx < 0 || ly < 0 || lx >= sw || ly >= sh {
                    continue;
                }
                // The mask follows the rotated *region* (every masked source cell), independent of pixel
                // opacity — so a selection's marquee rotates as a whole, not just its opaque pixels.
                if let Some(m) = src_mask {
                    if !m.get(lx, ly) {
                        continue;
                    }
                }
                out_mask.set(dx, dy, true);
                // The pixel buffer only carries opaque content (transparent source leaves a hole).
                let c = if self.clean_edge {
                    // cleanEdge: sample the edge-aware reconstruction at the continuous source
                    // point (it reduces to the same cell as NN wherever no edge slice fires).
                    crate::cleanedge::sample(
                        src,
                        sxf - src_origin.x as f32,
                        syf - src_origin.y as f32,
                        self.clean_edge_width,
                    )
                } else {
                    src.get(lx, ly)
                };
                if c.a != 0 {
                    out.set(dx, dy, c);
                }
            }
        }
        (out, out_mask)
    }

    /// Scaling of the lifted source by the X/Y factors `sx`/`sy` about `pivot`, into a
    /// `cw`×`ch` buffer, clipped. Samples nearest-neighbor, or the cleanEdge reconstruction
    /// when `clean_edge` is on AND both factors upscale (≥ 1, not both exactly 1) — cleanEdge
    /// is a reconstruction sampler, not a minifier, so any shrinking axis forces plain NN.
    /// Factors are milli-exact (1000 → 1.0, 2000 → 2.0 with zero float drift), so identity and
    /// integer scales are integer-exact: 1× is the identity and 2× NN is exact 2×2 block
    /// replication. Returns the placed pixels and a matching 1-bit region mask
    /// ([`Resample::rotate`]'s twin).
    pub fn scale(&self, src: &RgbaBuffer, sx: f32, sy: f32, cw: i32, ch: i32) -> (RgbaBuffer, Mask) {
        let (sw, sh, src_origin, src_mask, pivot) =
            (self.sw, self.sh, self.src_origin, self.src_mask, self.pivot);
        // Whole-pixel drag-to-move offset, applied AFTER the scale (integer — identity and integer
        // factors stay exact under a moved draft).
        let (offx, offy) = (self.off.x as f32, self.off.y as f32);
        let mut out = RgbaBuffer::new(cw as u32, ch as u32);
        let mut out_mask = Mask::new(cw as u32, ch as u32);
        let use_clean = self.clean_edge && sx >= 1.0 && sy >= 1.0 && !(sx == 1.0 && sy == 1.0);

        // Destination scan window = the clipped bbox of the scaled source rect. The map is
        // axis-aligned with positive factors, so the two extreme corners suffice.
        let fwd = |px: f32, py: f32| {
            (pivot.x + (px - pivot.x) * sx + offx, pivot.y + (py - pivot.y) * sy + offy)
        };
        let (minx, miny) = fwd(src_origin.x as f32, src_origin.y as f32);
        let (maxx, maxy) = fwd((src_origin.x + sw) as f32, (src_origin.y + sh) as f32);
        let x0 = (minx.floor() as i32).max(0);
        let y0 = (miny.floor() as i32).max(0);
        let x1 = (maxx.ceil() as i32).min(cw);
        let y1 = (maxy.ceil() as i32).min(ch);

        for dy in y0..y1 {
            for dx in x0..x1 {
                // Inverse-scale the destination pixel center back into source space (undo the move
                // offset first).
                let sxf = pivot.x + (dx as f32 + 0.5 - offx - pivot.x) / sx;
                let syf = pivot.y + (dy as f32 + 0.5 - offy - pivot.y) / sy;
                let lx = (sxf - src_origin.x as f32).floor() as i32;
                let ly = (syf - src_origin.y as f32).floor() as i32;
                if lx < 0 || ly < 0 || lx >= sw || ly >= sh {
                    continue;
                }
                // The mask follows the scaled *region* (every masked source cell), independent of
                // pixel opacity — so a selection's marquee scales as a whole. Inverse mapping keeps
                // the region solid at any factor (membership only, no holes).
                if let Some(m) = src_mask {
                    if !m.get(lx, ly) {
                        continue;
                    }
                }
                out_mask.set(dx, dy, true);
                // The pixel buffer only carries opaque content (transparent source leaves a hole).
                let c = if use_clean {
                    crate::cleanedge::sample(
                        src,
                        sxf - src_origin.x as f32,
                        syf - src_origin.y as f32,
                        self.clean_edge_width,
                    )
                } else {
                    src.get(lx, ly)
                };
                if c.a != 0 {
                    out.set(dx, dy, c);
                }
            }
        }
        (out, out_mask)
    }
}
