//! cleanEdge — pixel-art rotation sampling (the Rotate tool's "cleanEdge" toggle).
//!
//! A faithful Rust port of torcado's cleanEdge shader (<https://torcado.com/cleanEdge/>,
//! reference build: the Shadertoy variant of gist `torcado194/e2794f5a4b22049ac0a41f972d14c329`).
//! cleanEdge treats the pixel grid as a continuous reconstruction: for any continuous sample
//! point it inspects a ~5×5 neighborhood of the containing pixel, detects 45° and 2:1 slope
//! edges via color-similarity rules (`slice_dist`, evaluated three times with mirrored
//! neighborhoods for the corner/back/up quadrant slices), and redraws those edges as straight
//! lines. Rotating pixel art = point-sampling this reconstruction at inverse-rotated
//! destination pixel centres (`session/canvas.rs::rotate_resample`).
//!
//! Configuration baked into this port (the rotation use-case):
//! - `similarThreshold = 0` — similarity is exact RGBA equality (integer-exact, the right
//!   default for palette-disciplined pixel art).
//! - `highestColor` = white — overlap priority prefers the color closest to white.
//! - SLOPE branches on (the reference always enables 2:1 slopes for rotation).
//! - CLEANUP omitted (upstream comment: "if only using for rotation, CLEANUP has negligible
//!   effect and should be disabled for speed").
//!
//! Determinism: every float operation here is IEEE `+ − × ÷ sqrt` (exactly specified,
//! bit-reproducible across platforms; rustc applies no FP contraction). All *ordering*
//! comparisons (`higher`, the final slice-color picks) use integer squared distances — sqrt is
//! monotonic, so results are identical to the float form but exact. The output is always a
//! color already present in the neighborhood (or transparent): cleanEdge never blends, so it
//! never introduces new palette entries.
//!
//! ```text
//! MIT LICENSE
//! Copyright (c) 2022 torcado
//!
//! Permission is hereby granted, free of charge, to any person obtaining a copy of this
//! software and associated documentation files (the "Software"), to deal in the Software
//! without restriction, including without limitation the rights to use, copy, modify, merge,
//! publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons
//! to whom the Software is furnished to do so, subject to the following conditions:
//!
//! The above copyright notice and this permission notice shall be included in all copies or
//! substantial portions of the Software.
//!
//! THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
//! INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
//! PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
//! FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
//! OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
//! DEALINGS IN THE SOFTWARE.
//! ```

use crate::buffer::RgbaBuffer;
use crate::color::Rgba8;

/// The reference shader's SLOPE-mode *internal* clamp on `lineWidth` ("clamped range prevents
/// inaccurate identity (no change) result"). The user-facing range is 0–2 (matching the
/// reference site's slider); values outside this band saturate here, exactly as upstream.
/// The clamp is what guarantees `sample` at exact pixel centres is the identity — the property
/// the angle-0 and quarter-turn losslessness of the Rotate tool rest on.
pub const MIN_LINE_WIDTH: f32 = 0.45;
pub const MAX_LINE_WIDTH: f32 = 1.142;

/// One quadrant's view of the neighborhood, fields named exactly as the shader's `sliceDist`
/// parameters: u_p / d_own rows × b_ack / f_orward columns, doubled letters = two steps out.
struct Window {
    ub: Rgba8,
    u: Rgba8,
    uf: Rgba8,
    uff: Rgba8,
    b: Rgba8,
    c: Rgba8,
    f: Rgba8,
    ff: Rgba8,
    db: Rgba8,
    d: Rgba8,
    df: Rgba8,
    dff: Rgba8,
    ddb: Rgba8,
    dd: Rgba8,
    ddf: Rgba8,
}

/// `similarThreshold = 0`: two colors are similar iff byte-equal, or both fully transparent
/// (the shader's `col1.a == 0 && col2.a == 0` clause — transparent is one color regardless of
/// its stored RGB).
fn similar(a: Rgba8, b: Rgba8) -> bool {
    (a.a == 0 && b.a == 0) || a == b
}
fn similar3(a: Rgba8, b: Rgba8, c: Rgba8) -> bool {
    similar(a, b) && similar(b, c)
}
fn similar4(a: Rgba8, b: Rgba8, c: Rgba8, d: Rgba8) -> bool {
    similar(a, b) && similar(b, c) && similar(c, d)
}

/// Squared Euclidean distance over all four channels (≤ 4·255², exact in u32).
fn dist2(a: Rgba8, b: Rgba8) -> u32 {
    let d = |x: u8, y: u8| {
        let v = x as i32 - y as i32;
        (v * v) as u32
    };
    d(a.r, b.r) + d(a.g, b.g) + d(a.b, b.b) + d(a.a, b.a)
}

/// Squared RGB distance to the fixed `highestColor` (white) — `higher`'s equal-alpha tiebreak.
fn white_dist2(c: Rgba8) -> u32 {
    let d = |x: u8| {
        let v = 255 - x as i32;
        (v * v) as u32
    };
    d(c.r) + d(c.g) + d(c.b)
}

/// Overlap priority: dissimilar colors compare by alpha, ties by closeness to white.
/// Integer-exact (sqrt is monotonic, so squared distances order identically).
fn higher(this: Rgba8, other: Rgba8) -> bool {
    if similar(this, other) {
        return false;
    }
    if this.a == other.a {
        white_dist2(this) < white_dist2(other)
    } else {
        this.a > other.a
    }
}

/// Color distance on the shader's [0,1] vec4 scale — only used where the shader compares
/// against the absolute `0.001` epsilon (edge detection); everything else orders via `dist2`.
/// `dist2 < 2²⁴` so the u32→f32 conversion is exact; sqrt is correctly rounded.
fn cd(a: Rgba8, b: Rgba8) -> f32 {
    (dist2(a, b) as f32).sqrt() / 255.0
}

/// Signed distance from `test` to the line through `pt1`→`pt2`, sign chosen so `dir` points
/// positive. Port of the shader's `distToLine` (dot-then-divide instead of normalize-then-dot —
/// algebraically identical, still fully deterministic).
fn dist_to_line(test: (f32, f32), pt1: (f32, f32), pt2: (f32, f32), dir: (f32, f32)) -> f32 {
    let line_dir = (pt2.0 - pt1.0, pt2.1 - pt1.1);
    let perp = (line_dir.1, -line_dir.0);
    let to_pt1 = (pt1.0 - test.0, pt1.1 - test.1);
    let sign = if perp.0 * dir.0 + perp.1 * dir.1 > 0.0 { 1.0 } else { -1.0 };
    let len = (perp.0 * perp.0 + perp.1 * perp.1).sqrt();
    sign * (perp.0 * to_pt1.0 + perp.1 * to_pt1.1) / len
}

/// One quadrant slice: does the (flipped) sample `point` fall on the far side of a detected
/// edge, and if so which neighbor color paints it? `None` = no slice here (the shader's
/// `vec4(-1)` sentinel). Port of `sliceDist` with SLOPE on and CLEANUP omitted. The branch
/// chain is decisive: the first matching slant shape fully decides the outcome (including
/// `None` when the point is on the near side) — it must never fall through to a later branch.
fn slice_dist(
    point: (f32, f32),
    main_dir: (f32, f32),
    pd: (f32, f32),
    w: &Window,
    line_width: f32,
) -> Option<Rgba8> {
    let lw = line_width.clamp(MIN_LINE_WIDTH, MAX_LINE_WIDTH);
    // Flip the point into this quadrant's frame; the neighborhood is already mirrored by the
    // caller and the line geometry below scales by `pd` componentwise — `pd` itself is never
    // flipped (exactly as the shader: only `point` is transformed by `mainDir`).
    let point = (main_dir.0 * (point.0 - 0.5) + 0.5, main_dir.1 * (point.1 - 0.5) + 0.5);

    // Edge detection (term order fixed as in the shader for bit-stable summation).
    let dist_against =
        4.0 * cd(w.f, w.d) + cd(w.uf, w.c) + cd(w.c, w.db) + cd(w.ff, w.df) + cd(w.df, w.dd);
    let dist_towards =
        4.0 * cd(w.c, w.df) + cd(w.u, w.f) + cd(w.f, w.dff) + cd(w.b, w.d) + cd(w.d, w.ddf);
    let mut should_slice = dist_against < dist_towards
        || (dist_against < dist_towards + 0.001 && !higher(w.c, w.f)); // equivalent-edges edge case
    if similar4(w.f, w.d, w.b, w.u) && similar4(w.uf, w.df, w.db, w.ub) && !similar(w.c, w.f) {
        should_slice = false; // checkerboard edge case
    }
    if !should_slice {
        return None;
    }

    // center + vec2(a, b) * pointDir, in the flipped frame.
    let cpt = |a: f32, b: f32| (0.5 + a * pd.0, 0.5 + b * pd.1);
    let npd = (-pd.0, -pd.1);

    if similar3(w.f, w.d, w.db) && !similar3(w.f, w.d, w.b) && !similar(w.uf, w.db) {
        // Lower shallow 2:1 slant.
        let mut flip = false;
        if similar(w.c, w.df) && higher(w.c, w.f) {
            // single pixel wide diagonal, don't flip
        } else {
            if higher(w.c, w.f) {
                flip = true;
            }
            if similar(w.u, w.f) && !similar(w.c, w.df) && !higher(w.c, w.u) {
                flip = true;
            }
        }
        // Midpoints of neighbor two-pixel groupings.
        let mut dist = if flip {
            lw - dist_to_line(point, cpt(1.5, -1.0), cpt(-0.5, 0.0), npd)
        } else {
            dist_to_line(point, cpt(1.5, 0.0), cpt(-0.5, 1.0), pd)
        };
        dist -= lw / 2.0;
        return if dist <= 0.0 {
            Some(if dist2(w.c, w.f) <= dist2(w.c, w.d) { w.f } else { w.d })
        } else {
            None
        };
    } else if similar3(w.uf, w.f, w.d) && !similar3(w.u, w.f, w.d) && !similar(w.uf, w.db) {
        // Forward steep 2:1 slant.
        let mut flip = false;
        if similar(w.c, w.df) && higher(w.c, w.d) {
            // single pixel wide diagonal, don't flip
        } else {
            if higher(w.c, w.d) {
                flip = true;
            }
            if similar(w.b, w.d) && !similar(w.c, w.df) && !higher(w.c, w.d) {
                flip = true;
            }
        }
        let mut dist = if flip {
            lw - dist_to_line(point, cpt(0.0, -0.5), cpt(-1.0, 1.5), npd)
        } else {
            dist_to_line(point, cpt(1.0, -0.5), cpt(0.0, 1.5), pd)
        };
        dist -= lw / 2.0;
        return if dist <= 0.0 {
            Some(if dist2(w.c, w.f) <= dist2(w.c, w.d) { w.f } else { w.d })
        } else {
            None
        };
    } else if similar(w.f, w.d) {
        // 45° diagonal.
        let mut flip = false;
        if similar(w.c, w.df) && higher(w.c, w.f) {
            // single pixel diagonal along neighbors — don't flip, except…
            if !similar(w.c, w.dd) && !similar(w.c, w.ff) {
                flip = true; // line against triple color stripe edge case
            }
        } else {
            if higher(w.c, w.f) {
                flip = true;
            }
            if !similar(w.c, w.b) && similar4(w.b, w.f, w.d, w.u) {
                flip = true;
            }
        }
        // Single pixel 2:1 slope (unconditional, after the block above — as in the shader).
        if ((similar(w.f, w.db) && similar3(w.u, w.f, w.df))
            || (similar(w.uf, w.d) && similar3(w.b, w.d, w.df)))
            && !similar(w.c, w.df)
        {
            flip = true;
        }
        let mut dist = if flip {
            // Midpoints of own diagonal pixels.
            lw - dist_to_line(point, cpt(1.0, -1.0), cpt(-1.0, 1.0), npd)
        } else {
            // Midpoints of corner neighbor pixels.
            dist_to_line(point, cpt(1.0, 0.0), cpt(0.0, 1.0), pd)
        };
        dist -= lw / 2.0;
        return if dist <= 0.0 {
            Some(if dist2(w.c, w.f) <= dist2(w.c, w.d) { w.f } else { w.d })
        } else {
            None
        };
    } else if similar3(w.ff, w.df, w.d) && !similar3(w.ff, w.df, w.c) && !similar(w.uff, w.d) {
        // Far corner of shallow slant.
        let mut flip = false;
        if similar(w.f, w.dff) && higher(w.f, w.ff) {
            // single pixel wide diagonal, don't flip
        } else {
            if higher(w.f, w.ff) {
                flip = true;
            }
            if similar(w.uf, w.ff) && !similar(w.f, w.dff) && !higher(w.f, w.uf) {
                flip = true;
            }
        }
        let mut dist = if flip {
            lw - dist_to_line(point, cpt(2.5, -1.0), cpt(0.5, 0.0), npd)
        } else {
            dist_to_line(point, cpt(2.5, 0.0), cpt(0.5, 1.0), pd)
        };
        dist -= lw / 2.0;
        return if dist <= 0.0 {
            Some(if dist2(w.f, w.ff) <= dist2(w.f, w.df) { w.ff } else { w.df })
        } else {
            None
        };
    } else if similar3(w.f, w.df, w.dd) && !similar3(w.c, w.df, w.dd) && !similar(w.f, w.ddb) {
        // Far corner of steep slant.
        let mut flip = false;
        if similar(w.d, w.ddf) && higher(w.d, w.dd) {
            // single pixel wide diagonal, don't flip
        } else {
            if higher(w.d, w.dd) {
                flip = true;
            }
            if similar(w.db, w.dd) && !similar(w.d, w.ddf) && !higher(w.d, w.dd) {
                flip = true;
            }
        }
        let mut dist = if flip {
            lw - dist_to_line(point, cpt(0.0, 0.5), cpt(-1.0, 2.5), npd)
        } else {
            dist_to_line(point, cpt(1.0, 0.5), cpt(0.0, 2.5), pd)
        };
        dist -= lw / 2.0;
        return if dist <= 0.0 {
            Some(if dist2(w.d, w.df) <= dist2(w.d, w.dd) { w.df } else { w.dd })
        } else {
            None
        };
    }
    None
}

/// Sample the cleanEdge reconstruction of `src` at the continuous point `(x, y)` (source pixel
/// space: pixel `(i, j)` spans `[i, i+1)×[j, j+1)`). Out-of-bounds reads are transparent
/// (`RgbaBuffer::get`'s semantics), which is exactly the shader's edge-against-transparency
/// behavior. Returns a color already present in the neighborhood, or transparent. Callers must
/// treat any `a == 0` result as fully transparent regardless of its RGB bytes (as the rest of
/// the engine already does).
pub fn sample(src: &RgbaBuffer, x: f32, y: f32, line_width: f32) -> Rgba8 {
    let (cx, cy) = (x.floor(), y.floor());
    let (ix, iy) = (cx as i32, cy as i32);
    let local = (x - cx, y - cy);
    // pointDir: which quadrant of the pixel the sample falls in. `>= 0.5 → +1` is the
    // deterministic tie-break (GLSL `round(0.5)` is implementation-defined; we pin half-up).
    let pd = (
        if local.0 >= 0.5 { 1.0f32 } else { -1.0 },
        if local.1 >= 0.5 { 1.0f32 } else { -1.0 },
    );
    let (pdx, pdy) = (pd.0 as i32, pd.1 as i32);
    let at = |ox: i32, oy: i32| src.get(ix + ox * pdx, iy + oy * pdy);

    // The 21 neighborhood taps, offsets exactly as the shader's mainImage.
    let uub = at(-1, -2);
    let uu = at(0, -2);
    let uuf = at(1, -2);
    let ubb = at(-2, -2); // sic — the canonical upstream tap is (-2,-2), not (-2,-1)
    let ub = at(-1, -1);
    let u = at(0, -1);
    let uf = at(1, -1);
    let uff = at(2, -1);
    let bb = at(-2, 0);
    let b = at(-1, 0);
    let c = at(0, 0);
    let f = at(1, 0);
    let ff = at(2, 0);
    let dbb = at(-2, 1);
    let db = at(-1, 1);
    let d = at(0, 1);
    let df = at(1, 1);
    let dff = at(2, 1);
    let ddb = at(-1, 2);
    let dd = at(0, 2);
    let ddf = at(1, 2);

    // Flat-neighborhood fast path (exact at threshold 0): every slice color is drawn from the
    // taps, so a uniform neighborhood can only ever yield `c` (or an equally-transparent hole).
    // Covers the transparent gutter and flat sprite interiors — the dominant case.
    if [uub, uu, uuf, ubb, ub, u, uf, uff, bb, b, f, ff, dbb, db, d, df, dff, ddb, dd, ddf]
        .iter()
        .all(|&t| similar(t, c))
    {
        return c;
    }

    // The three quadrant slices (corner, back, up) — slices from neighbor pixels only ever
    // reach these; a later hit overrides an earlier one, exactly as the shader.
    let w_corner = Window { ub, u, uf, uff, b, c, f, ff, db, d, df, dff, ddb, dd, ddf };
    let w_back = Window {
        ub: uf,
        u,
        uf: ub,
        uff: ubb,
        b: f,
        c,
        f: b,
        ff: bb,
        db: df,
        d,
        df: db,
        dff: dbb,
        ddb: ddf,
        dd,
        ddf: ddb,
    };
    let w_up = Window {
        ub: db,
        u: d,
        uf: df,
        uff: dff,
        b,
        c,
        f,
        ff,
        db: ub,
        d: u,
        df: uf,
        dff: uff,
        ddb: uub,
        dd: uu,
        ddf: uuf,
    };

    let mut col = c;
    if let Some(cc) = slice_dist(local, (1.0, 1.0), pd, &w_corner, line_width) {
        col = cc;
    }
    if let Some(cc) = slice_dist(local, (-1.0, 1.0), pd, &w_back, line_width) {
        col = cc;
    }
    if let Some(cc) = slice_dist(local, (1.0, -1.0), pd, &w_up, line_width) {
        col = cc;
    }
    col
}

#[cfg(test)]
mod tests {
    use super::*;

    const A: Rgba8 = Rgba8::new(200, 40, 40, 255); // sprite color
    const L: Rgba8 = Rgba8::new(40, 200, 40, 255); // line color
    const T: Rgba8 = Rgba8::TRANSPARENT;

    fn buf(w: u32, h: u32, at: impl Fn(i32, i32) -> Rgba8) -> RgbaBuffer {
        let mut b = RgbaBuffer::new(w, h);
        for y in 0..h as i32 {
            for x in 0..w as i32 {
                b.set(x, y, at(x, y));
            }
        }
        b
    }

    /// The 45° staircase used across tests: opaque `A` iff `y >= x` (edge runs on `y = x`).
    fn staircase() -> RgbaBuffer {
        buf(8, 8, |x, y| if y >= x { A } else { T })
    }

    const WIDTHS: [f32; 6] = [0.0, 0.45, 0.707, 1.0, 1.142, 2.0];

    #[test]
    fn flat_input_is_identity() {
        // Interior points only: at the buffer border the out-of-bounds taps are transparent,
        // so the border is a real silhouette edge and cleanEdge legitimately reshapes it.
        let src = buf(8, 8, |_, _| A);
        for lw in WIDTHS {
            for (x, y) in [(3.5, 3.5), (3.1, 3.9), (4.999, 4.001), (2.25, 5.75)] {
                assert_eq!(sample(&src, x, y, lw), A, "lw={lw} at ({x},{y})");
            }
        }
    }

    #[test]
    fn identity_at_pixel_centres() {
        // Mix of every edge shape: 45° staircase, 2:1 slope, checkerboard, 1px diagonal.
        let src = buf(16, 16, |x, y| {
            if x < 8 && y < 8 {
                if y >= x { A } else { T } // 45° staircase
            } else if x >= 8 && y < 8 {
                if 2 * y >= x - 8 { L } else { T } // 2:1 slope
            } else if x < 8 {
                if (x + y) % 2 == 0 { A } else { L } // checkerboard
            } else if x - 8 == y - 8 {
                L // 1px diagonal on transparent
            } else {
                T
            }
        });
        // The internal clamp guarantees identity at exact cell centres across the whole
        // user-facing 0–2 range (extremes saturate to [0.45, 1.142]).
        for lw in WIDTHS {
            for y in 0..16 {
                for x in 0..16 {
                    let got = sample(&src, x as f32 + 0.5, y as f32 + 0.5, lw);
                    let want = src.get(x, y);
                    let same = got == want || (got.a == 0 && want.a == 0);
                    assert!(same, "lw={lw} at ({x},{y}): got {got:?}, want {want:?}");
                }
            }
        }
    }

    #[test]
    fn staircase_45_corner_cut() {
        // Derived by hand from the shader logic (see plan): at lw = 1.0 the convex corner of
        // the step cell (3,3) is cut to transparent, and the concave notch of the transparent
        // cell (4,3) (between the opaque (3,3) and (4,4)) is filled with A.
        let src = staircase();
        let cut = sample(&src, 3.9, 3.1, 1.0);
        assert_eq!(cut.a, 0, "convex corner should be cut, got {cut:?}");
        assert_eq!(sample(&src, 4.1, 3.9, 1.0), A, "concave corner should be filled");
        // And nearest-neighbour would disagree on both — the whole point of the algorithm.
        assert_eq!(src.get(3, 3), A);
        assert_eq!(src.get(4, 3), T);
    }

    #[test]
    fn checkerboard_is_untouched() {
        let src = buf(8, 8, |x, y| if (x + y) % 2 == 0 { A } else { L });
        for lw in WIDTHS {
            for y in 2..6 {
                for x in 2..6 {
                    for (fx, fy) in [(0.1, 0.1), (0.9, 0.1), (0.1, 0.9), (0.9, 0.9), (0.7, 0.3)] {
                        let got = sample(&src, x as f32 + fx, y as f32 + fy, lw);
                        assert_eq!(got, src.get(x, y), "lw={lw} at ({x}+{fx},{y}+{fy})");
                    }
                }
            }
        }
    }

    #[test]
    fn single_pixel_diagonal_preserved() {
        // 1px diagonal of L over transparency: along-diagonal interior points keep the line
        // connected (the flip slice only trims the far corner tips beyond the midpoint line).
        let src = buf(8, 8, |x, y| if x == y { L } else { T });
        for (fx, fy) in [(0.5, 0.5), (0.75, 0.25), (0.25, 0.75), (0.6, 0.4)] {
            let got = sample(&src, 3.0 + fx, 3.0 + fy, 1.0);
            assert_eq!(got, L, "diagonal broken at (3+{fx},3+{fy})");
        }
    }

    #[test]
    fn two_one_slope_reconstructed() {
        // 2:1 staircase (two-wide steps): opaque A iff 2*y >= x. cleanEdge redraws the step
        // edge as a straight 2:1 line, so the convex step corners get shaved (NN keeps them)
        // and output never invents colors.
        let src = buf(16, 16, |x, y| if 2 * y >= x { A } else { T });
        let mut changed = 0;
        for y in 1..7 {
            for x in 1..13 {
                for (fx, fy) in [(0.1, 0.1), (0.9, 0.1), (0.1, 0.9), (0.9, 0.9)] {
                    let got = sample(&src, x as f32 + fx, y as f32 + fy, 1.0);
                    assert!(got == A || got.a == 0, "invented color {got:?}");
                    let nn = src.get(x, y);
                    if got != nn && !(got.a == 0 && nn.a == 0) {
                        changed += 1;
                    }
                }
            }
        }
        assert!(changed > 0, "SLOPE branches never fired on a 2:1 staircase");
    }

    #[test]
    fn no_new_colours() {
        let src = buf(12, 12, |x, y| {
            if y >= x {
                if (x / 3 + y / 3) % 2 == 0 { A } else { L }
            } else if x - y == 2 {
                Rgba8::new(30, 30, 220, 255)
            } else {
                T
            }
        });
        let inputs: std::collections::HashSet<Rgba8> =
            (0..12).flat_map(|y| (0..12).map(move |x| (x, y))).map(|(x, y)| src.get(x, y)).collect();
        for lw in WIDTHS {
            for y in 0..12 {
                for x in 0..12 {
                    for sub in 0..16 {
                        let (fx, fy) = ((sub % 4) as f32 / 4.0 + 0.125, (sub / 4) as f32 / 4.0 + 0.125);
                        let got = sample(&src, x as f32 + fx, y as f32 + fy, lw);
                        assert!(
                            got.a == 0 || inputs.contains(&got),
                            "lw={lw}: new color {got:?} at ({x}+{fx},{y}+{fy})"
                        );
                    }
                }
            }
        }
    }

    #[test]
    fn line_width_clamped_inside() {
        // The user range 0–2 saturates to the internal [0.45, 1.142] clamp, matching the
        // reference site's slider extremes.
        let src = staircase();
        for y in 0..8 {
            for x in 0..8 {
                for sub in 0..25 {
                    let (fx, fy) = ((sub % 5) as f32 / 5.0 + 0.1, (sub / 5) as f32 / 5.0 + 0.1);
                    let (px, py) = (x as f32 + fx, y as f32 + fy);
                    assert_eq!(sample(&src, px, py, 0.0), sample(&src, px, py, MIN_LINE_WIDTH));
                    assert_eq!(sample(&src, px, py, 2.0), sample(&src, px, py, MAX_LINE_WIDTH));
                }
            }
        }
    }
}
