//! Pixel-exact rotate/scale resampling of a lifted RGBA region — the engine's transform
//! primitives, extracted from `session/canvas.rs` so they are callable outside the editor's
//! draft machinery (the Animator's compositor is the second consumer). Sampling is
//! nearest-neighbor or the cleanEdge reconstruction (`crate::cleanedge`); both paths are
//! integer-exact at identity and quarter turns and byte-deterministic across platforms.

use crate::buffer::RgbaBuffer;
use crate::geom::{Point, PointF};
use crate::selection::Mask;

/// cos/sin for integer millidegrees, CLOCKWISE. EXACT at multiples of 90 000 (an integer
/// equality check — no epsilon needed, unlike the editor draft's ±2 mrad snap, because the
/// Animator's rotations arrive as integer millidegrees); f32 trig otherwise. The single trig
/// gateway for all Animator transforms — if cross-platform goldens ever fork, the kill-switch
/// is swapping this one body for a fixed-point sine table.
pub fn rot_cos_sin(rot_md: i32) -> (f32, f32) {
    let m = rot_md.rem_euclid(360_000);
    if m % 90_000 == 0 {
        return match m / 90_000 {
            0 => (1.0, 0.0),
            1 => (0.0, 1.0),
            2 => (-1.0, 0.0),
            _ => (0.0, -1.0),
        };
    }
    let rad = m as f32 * (std::f32::consts::PI / 180_000.0);
    (rad.cos(), rad.sin())
}

/// A net actor similarity, fully fixed-point (the Animator compositor's transform):
/// `dst = T(t)·R(rot)·S(scale)·F(flips)·T(-pivot/1000)` with `t = (tx_q8/256, ty_q8/256)`.
/// Uniform scale in millionths; rotation in millidegrees clockwise (callers normalize to
/// `0..360_000`); pivot in prop-local milli-pixels.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub struct ActorXf {
    pub tx_q8: i32,
    pub ty_q8: i32,
    pub rot_md: i32,
    pub scale_micro: i64,
    pub flip_h: bool,
    pub flip_v: bool,
    pub pivot_x_milli: i32,
    pub pivot_y_milli: i32,
}

#[derive(Clone, Copy, PartialEq, Debug)]
pub enum SampleStyle {
    Nearest,
    CleanEdge { line_width: f32 },
}

/// Single-pass inverse-mapped resample of a `sw`×`sh` source through `xf`.
///
/// - `clip = None`: the output covers the transformed bounding box; returns `(buffer, origin)`
///   with `origin` the integer top-left of that box in destination space.
/// - `clip = Some(rect)`: the output is restricted to bbox ∩ rect (the compositor's uncached
///   path for oversized entries) — memory stays bounded by the clip rect.
///
/// cleanEdge is gated off when `scale_micro < 1_000_000` (the Resize tool's upscale-only
/// rule; rotation alone keeps cleanEdge, as the editor's rotate does). Per destination pixel
/// center: invert `xf` (undo t, R(−rot), S(1/scale), unflip, +pivot), then nearest-floor or
/// `cleanedge::sample` at the continuous source point; transparent source leaves a hole.
pub fn actor_resample(
    src: &RgbaBuffer,
    sw: u32,
    sh: u32,
    xf: &ActorXf,
    style: SampleStyle,
    clip: Option<crate::geom::IRect>,
) -> (RgbaBuffer, Point) {
    let (cos, sin) = rot_cos_sin(xf.rot_md);
    let s = (xf.scale_micro.max(1)) as f32 / 1_000_000.0;
    let (px, py) = (xf.pivot_x_milli as f32 / 1000.0, xf.pivot_y_milli as f32 / 1000.0);
    let (tx, ty) = (xf.tx_q8 as f32 / 256.0, xf.ty_q8 as f32 / 256.0);
    let fx = if xf.flip_h { -1.0f32 } else { 1.0 };
    let fy = if xf.flip_v { -1.0f32 } else { 1.0 };

    // Forward corners → destination bbox.
    let fwd = |cx: f32, cy: f32| {
        let lx = (cx - px) * fx * s;
        let ly = (cy - py) * fy * s;
        (tx + cos * lx - sin * ly, ty + sin * lx + cos * ly)
    };
    let (mut minx, mut miny, mut maxx, mut maxy) = (f32::MAX, f32::MAX, f32::MIN, f32::MIN);
    for (cx, cy) in [(0.0, 0.0), (sw as f32, 0.0), (0.0, sh as f32), (sw as f32, sh as f32)] {
        let (gx, gy) = fwd(cx, cy);
        minx = minx.min(gx);
        miny = miny.min(gy);
        maxx = maxx.max(gx);
        maxy = maxy.max(gy);
    }
    let (mut x0, mut y0) = (minx.floor() as i32, miny.floor() as i32);
    let (mut x1, mut y1) = (maxx.ceil() as i32, maxy.ceil() as i32);
    if let Some(r) = clip {
        x0 = x0.max(r.x);
        y0 = y0.max(r.y);
        x1 = x1.min(r.right());
        y1 = y1.min(r.bottom());
    }
    if x1 <= x0 || y1 <= y0 {
        return (RgbaBuffer::new(1, 1), Point::new(x0, y0));
    }
    let (ow, oh) = ((x1 - x0) as u32, (y1 - y0) as u32);
    let mut out = RgbaBuffer::new(ow, oh);
    let origin = Point::new(x0, y0);

    // Identity detection: unit scale, zero rotation, no flips, whole-pixel translation → the
    // inverse map lands exactly on pixel centers, so NN reproduces the source and cleanEdge
    // would too (identity-at-centers) — sampling NN here keeps both styles trivially equal.
    let identity = xf.scale_micro == 1_000_000
        && xf.rot_md.rem_euclid(360_000) == 0
        && !xf.flip_h
        && !xf.flip_v
        && xf.tx_q8.rem_euclid(256) == 0
        && xf.ty_q8.rem_euclid(256) == 0;

    let use_clean = match style {
        SampleStyle::CleanEdge { .. } if !identity && xf.scale_micro >= 1_000_000 => true,
        _ => false,
    };
    let lw = match style {
        SampleStyle::CleanEdge { line_width } => line_width,
        SampleStyle::Nearest => 0.0,
    };

    for dy in 0..oh as i32 {
        for dx in 0..ow as i32 {
            let gx = (x0 + dx) as f32 + 0.5 - tx;
            let gy = (y0 + dy) as f32 + 0.5 - ty;
            // R(-rot), then S(1/s), then unflip, then +pivot.
            let rx = (cos * gx + sin * gy) / s * fx + px;
            let ry = (-sin * gx + cos * gy) / s * fy + py;
            let lx = rx.floor() as i32;
            let ly = ry.floor() as i32;
            if lx < 0 || ly < 0 || lx >= sw as i32 || ly >= sh as i32 {
                continue;
            }
            let c = if use_clean {
                crate::cleanedge::sample(src, rx, ry, lw)
            } else {
                src.get(lx, ly)
            };
            if c.a != 0 {
                out.set(dx, dy, c);
            }
        }
    }
    (out, origin)
}

#[cfg(test)]
mod actor_tests {
    use super::*;
    use crate::color::Rgba8;
    use crate::geom::IRect;

    fn pattern(w: u32, h: u32) -> RgbaBuffer {
        let mut b = RgbaBuffer::new(w, h);
        for y in 0..h as i32 {
            for x in 0..w as i32 {
                if (x + y) % 3 != 0 {
                    b.set(x, y, Rgba8::new((x * 40) as u8, (y * 40) as u8, 128, 255));
                }
            }
        }
        b
    }

    #[test]
    fn rot_cos_sin_exact_quarters() {
        assert_eq!(rot_cos_sin(0), (1.0, 0.0));
        assert_eq!(rot_cos_sin(90_000), (0.0, 1.0));
        assert_eq!(rot_cos_sin(180_000), (-1.0, 0.0));
        assert_eq!(rot_cos_sin(270_000), (0.0, -1.0));
        assert_eq!(rot_cos_sin(360_000), (1.0, 0.0));
        assert_eq!(rot_cos_sin(-90_000), (0.0, -1.0)); // rem_euclid normalization
    }

    /// The oracle equivalences are asserted at integer-exact configurations (identity, quarter
    /// turns, integer scale) where both code paths are bit-deterministic by construction —
    /// arbitrary angles would compare two independently-rounded radian conversions (1-ulp
    /// hazards) without adding coverage; assert.det guards arbitrary angles end-to-end.
    #[test]
    fn actor_resample_identity_reproduces_source() {
        let src = pattern(7, 5);
        let xf = ActorXf {
            tx_q8: 3 * 256,
            ty_q8: 2 * 256,
            rot_md: 0,
            scale_micro: 1_000_000,
            flip_h: false,
            flip_v: false,
            pivot_x_milli: 0,
            pivot_y_milli: 0,
        };
        let (out, origin) = actor_resample(&src, 7, 5, &xf, SampleStyle::Nearest, None);
        assert_eq!(origin, Point::new(3, 2));
        for y in 0..5 {
            for x in 0..7 {
                assert_eq!(out.get(x, y), src.get(x, y));
            }
        }
    }

    #[test]
    fn actor_resample_quarter_turn_matches_resample_rotate() {
        let src = pattern(6, 4);
        // Pivot at the source center; quarter turn; no offset. Resample::rotate places into a
        // cw×ch canvas about the same pivot; actor_resample's t must equal that pivot.
        let pivot = PointF { x: 3.0, y: 2.0 };
        let params = Resample {
            sw: 6,
            sh: 4,
            src_origin: Point::new(0, 0),
            src_mask: None,
            pivot,
            off: Point::new(0, 0),
            clean_edge: false,
            clean_edge_width: 1.0,
        };
        let (a, _) = params.rotate(&src, std::f32::consts::FRAC_PI_2, 12, 12);
        let xf = ActorXf {
            tx_q8: (pivot.x * 256.0) as i32,
            ty_q8: (pivot.y * 256.0) as i32,
            rot_md: 90_000,
            scale_micro: 1_000_000,
            flip_h: false,
            flip_v: false,
            pivot_x_milli: 3000,
            pivot_y_milli: 2000,
        };
        let (b, origin) = actor_resample(&src, 6, 4, &xf, SampleStyle::Nearest, None);
        for y in 0..12 {
            for x in 0..12 {
                let lx = x - origin.x;
                let ly = y - origin.y;
                let bp = if lx >= 0 && ly >= 0 { b.get(lx, ly) } else { Rgba8::TRANSPARENT };
                assert_eq!(a.get(x, y), bp, "mismatch at ({x},{y})");
            }
        }
    }

    #[test]
    fn actor_resample_integer_scale_matches_resample_scale() {
        let src = pattern(5, 3);
        let pivot = PointF { x: 0.0, y: 0.0 };
        let params = Resample {
            sw: 5,
            sh: 3,
            src_origin: Point::new(0, 0),
            src_mask: None,
            pivot,
            off: Point::new(0, 0),
            clean_edge: false,
            clean_edge_width: 1.0,
        };
        let (a, _) = params.scale(&src, 2.0, 2.0, 10, 6);
        let xf = ActorXf {
            tx_q8: 0,
            ty_q8: 0,
            rot_md: 0,
            scale_micro: 2_000_000,
            flip_h: false,
            flip_v: false,
            pivot_x_milli: 0,
            pivot_y_milli: 0,
        };
        let (b, origin) = actor_resample(&src, 5, 3, &xf, SampleStyle::Nearest, None);
        assert_eq!(origin, Point::new(0, 0));
        for y in 0..6 {
            for x in 0..10 {
                assert_eq!(a.get(x, y), b.get(x, y), "mismatch at ({x},{y})");
            }
        }
    }

    #[test]
    fn clip_restricts_output() {
        let src = pattern(8, 8);
        let xf = ActorXf {
            tx_q8: 0,
            ty_q8: 0,
            rot_md: 0,
            scale_micro: 4_000_000,
            flip_h: false,
            flip_v: false,
            pivot_x_milli: 0,
            pivot_y_milli: 0,
        };
        let clip = IRect::new(4, 4, 8, 8);
        let (full, fo) = actor_resample(&src, 8, 8, &xf, SampleStyle::Nearest, None);
        let (part, po) = actor_resample(&src, 8, 8, &xf, SampleStyle::Nearest, Some(clip));
        assert_eq!(po, Point::new(4, 4));
        for y in 0..8 {
            for x in 0..8 {
                assert_eq!(
                    part.get(x, y),
                    full.get(x + po.x - fo.x, y + po.y - fo.y),
                    "clipped window must equal the full render's window"
                );
            }
        }
    }

    #[test]
    fn flips_mirror() {
        let src = pattern(4, 3);
        let xf = ActorXf {
            tx_q8: 0,
            ty_q8: 0,
            rot_md: 0,
            scale_micro: 1_000_000,
            flip_h: true,
            flip_v: false,
            pivot_x_milli: 2000, // center x
            pivot_y_milli: 0,
        };
        let (out, origin) = actor_resample(&src, 4, 3, &xf, SampleStyle::Nearest, None);
        assert_eq!(origin.x, -2); // flip about center x=2 → dest spans [-2, 2)
        for y in 0..3 {
            for o in 0..4i32 {
                assert_eq!(out.get(o, y), src.get(3 - o, y), "h-flip mirrors columns at ({o},{y})");
            }
        }
    }
}

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
