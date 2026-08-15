//! Deterministic rasterization primitives shared by shape-drawing tools and selection
//! tools (SPEC §11.6, §12, §28.1). Everything is expressed as integer plotting into a
//! `plot(x, y)` callback so the same code rasterizes pixels, masks, and previews.

use crate::geom::Point;

/// Bresenham line from `a` to `b`, inclusive of both endpoints.
pub fn line(a: Point, b: Point, mut plot: impl FnMut(i32, i32)) {
    let (mut x0, mut y0) = (a.x, a.y);
    let (x1, y1) = (b.x, b.y);
    let dx = (x1 - x0).abs();
    let dy = -(y1 - y0).abs();
    let sx = if x0 < x1 { 1 } else { -1 };
    let sy = if y0 < y1 { 1 } else { -1 };
    let mut err = dx + dy;
    loop {
        plot(x0, y0);
        if x0 == x1 && y0 == y1 {
            break;
        }
        let e2 = 2 * err;
        if e2 >= dy {
            err += dy;
            x0 += sx;
        }
        if e2 <= dx {
            err += dx;
            y0 += sy;
        }
    }
}

/// A line of the given pixel `thickness`: a `thickness × thickness` block swept along the Bresenham
/// line (thickness 1 = a plain hairline). Used by the Line tool's Width and the outline stroker.
/// The block is sized to the *exact* thickness so every unit adds one pixel of width — a centered
/// odd-radius stamp (side `2r+1`) would instead collapse each even thickness onto the odd below it.
/// Even widths bias half a pixel toward +x/+y, the closest the integer grid allows to centered.
pub fn thick_line(a: Point, b: Point, thickness: i32, mut plot: impl FnMut(i32, i32)) {
    let t = thickness.max(1);
    if t == 1 {
        line(a, b, plot);
        return;
    }
    let lo = -(t - 1) / 2;
    let hi = t / 2;
    let mut pts = Vec::new();
    line(a, b, |x, y| pts.push(Point::new(x, y)));
    for p in pts {
        for dy in lo..=hi {
            for dx in lo..=hi {
                plot(p.x + dx, p.y + dy);
            }
        }
    }
}

/// Stroke a closed polyline: each consecutive pair of points (wrapping last→first) is drawn as a
/// `thick_line`, so the union is a single connected curve. The building block of **Approach A** —
/// an outline is traced as a polyline then rasterised with Bresenham, giving uniform `thickness`-px
/// lines with no gaps or doubled pixels (unlike a per-pixel distance-band test).
fn stroke_polyline(pts: &[Point], thickness: i32, mut plot: impl FnMut(i32, i32)) {
    match pts.len() {
        0 => {}
        1 => plot(pts[0].x, pts[0].y),
        n => {
            for i in 0..n {
                thick_line(pts[i], pts[(i + 1) % n], thickness, &mut plot);
            }
        }
    }
}

/// Outline of a Rectangle (`kind` 0) or Ellipse (`kind` 1), axis-aligned or rotated by `rot`
/// radians, drawn with **Approach A**: trace the exact boundary in the shape's local frame,
/// rotate the boundary points into place, then stroke the connected polyline. `a`,`b` are the two
/// (already-rotated) opposite corners of the box; `thickness` is the outline width. Because the
/// curve is rasterised as Bresenham segments — not by testing each pixel's distance to the boundary
/// — the result is a continuous `thickness`-px line with no gaps or doubled pixels.
pub fn shape_outline(a: Point, b: Point, rot: f32, kind: u8, thickness: i32, plot: impl FnMut(i32, i32)) {
    let cx = (a.x + b.x) as f32 / 2.0;
    let cy = (a.y + b.y) as f32 / 2.0;
    let (sn, cs) = rot.sin_cos();
    // Local half-extents = the un-rotated vector from the center to corner `b`.
    let (vbx, vby) = (b.x as f32 - cx, b.y as f32 - cy);
    let hw = (cs * vbx + sn * vby).abs().max(0.5);
    let hh = (-sn * vbx + cs * vby).abs().max(0.5);
    // Map a local (lx,ly) to a world pixel, applying R(rot) about the center.
    let to_world = |lx: f32, ly: f32| {
        Point::new(
            (cx + cs * lx - sn * ly).round() as i32,
            (cy + sn * lx + cs * ly).round() as i32,
        )
    };
    let mut pts: Vec<Point> = Vec::new();
    match kind {
        0 => {
            pts.push(to_world(-hw, -hh));
            pts.push(to_world(hw, -hh));
            pts.push(to_world(hw, hh));
            pts.push(to_world(-hw, hh));
        }
        _ => {
            // Sample the parametric ellipse densely enough (~1px between samples) that the Bresenham
            // segments join into a smooth curve; skip a sample that repeats the previous pixel.
            let n = (std::f32::consts::TAU * hw.max(hh)).ceil().clamp(24.0, 8192.0) as usize;
            pts.reserve(n);
            for i in 0..n {
                let t = std::f32::consts::TAU * i as f32 / n as f32;
                let (st, ct) = t.sin_cos();
                let p = to_world(hw * ct, hh * st);
                if pts.last() != Some(&p) {
                    pts.push(p);
                }
            }
            if pts.len() > 1 && pts.first() == pts.last() {
                pts.pop();
            }
            // A 1px ellipse outline is the one case where sampling+Bresenham leaves staircase
            // "doubles"; trace it as a single ordered loop and drop those redundant corners.
            if thickness <= 1 {
                stroke_thin_loop(&pts, plot);
                return;
            }
        }
    }
    stroke_polyline(&pts, thickness, plot);
}

/// Trace a closed 1px curve through the ordered boundary `samples` and remove "doubles". First build
/// one ordered, de-duplicated, 8-connected pixel chain (a single Bresenham walk, not independent
/// segments). Then drop any pixel whose two chain-neighbors are themselves 8-adjacent: the curve can
/// step diagonally straight between them, so that pixel is a redundant orthogonal corner — exactly a
/// pixel-art "double". Removing it keeps the loop connected (the neighbors were already adjacent) and
/// leaves clean diagonal runs (whose neighbors are 2+ apart) untouched. Used for the 1px ellipse
/// outline, where a rotated thin ring otherwise looks locally 2px-thick at every staircase corner.
fn stroke_thin_loop(samples: &[Point], mut plot: impl FnMut(i32, i32)) {
    let n = samples.len();
    if n == 0 {
        return;
    }
    let mut chain: Vec<Point> = Vec::new();
    for i in 0..n {
        line(samples[i], samples[(i + 1) % n], |x, y| {
            let p = Point::new(x, y);
            if chain.last() != Some(&p) {
                chain.push(p);
            }
        });
    }
    if chain.len() > 1 && chain.first() == chain.last() {
        chain.pop();
    }
    let adj = |a: &Point, b: &Point| (a.x - b.x).abs() <= 1 && (a.y - b.y).abs() <= 1;
    // Iterate to convergence: removing one corner can expose the next along the loop.
    let mut changed = true;
    while changed && chain.len() >= 4 {
        changed = false;
        let mut i = 0;
        while i < chain.len() && chain.len() >= 4 {
            let len = chain.len();
            let prev = chain[(i + len - 1) % len];
            let next = chain[(i + 1) % len];
            if adj(&prev, &next) {
                chain.remove(i); // recheck the pixel that shifted into i (don't advance)
                changed = true;
            } else {
                i += 1;
            }
        }
    }
    for p in &chain {
        plot(p.x, p.y);
    }
}

/// A filled disc of `radius` (in pixels) centered at `c` — the round brush/eraser stamp.
pub fn disc(c: Point, radius: i32, mut plot: impl FnMut(i32, i32)) {
    if radius <= 0 {
        plot(c.x, c.y);
        return;
    }
    let r2 = radius * radius;
    for dy in -radius..=radius {
        for dx in -radius..=radius {
            if dx * dx + dy * dy <= r2 {
                plot(c.x + dx, c.y + dy);
            }
        }
    }
}

/// A filled square of half-extent `radius` centered at `c` — the square brush/eraser stamp.
pub fn square(c: Point, radius: i32, mut plot: impl FnMut(i32, i32)) {
    for dy in -radius..=radius {
        for dx in -radius..=radius {
            plot(c.x + dx, c.y + dy);
        }
    }
}

/// Filled axis-aligned rectangle covering the two corner points (inclusive).
pub fn rect_filled(a: Point, b: Point, mut plot: impl FnMut(i32, i32)) {
    let (x0, x1) = (a.x.min(b.x), a.x.max(b.x));
    let (y0, y1) = (a.y.min(b.y), a.y.max(b.y));
    for y in y0..=y1 {
        for x in x0..=x1 {
            plot(x, y);
        }
    }
}

/// Rectangle outline. 1px → Approach A (a clean traced 1px loop); thicker → an inward distance band
/// (`rotated_shape`) so the frame grows inward instead of bulging out.
pub fn rect_outline(a: Point, b: Point, thickness: i32, plot: impl FnMut(i32, i32)) {
    rotated_shape(a, b, 0.0, 0, false, thickness, plot);
}

/// Filled ellipse inscribed in the bounding box of the two corner points.
pub fn ellipse_filled(a: Point, b: Point, mut plot: impl FnMut(i32, i32)) {
    let (x0, x1) = (a.x.min(b.x), a.x.max(b.x));
    let (y0, y1) = (a.y.min(b.y), a.y.max(b.y));
    let cx = (x0 + x1) as f32 / 2.0;
    let cy = (y0 + y1) as f32 / 2.0;
    let rx = ((x1 - x0) as f32 / 2.0).max(0.5);
    let ry = ((y1 - y0) as f32 / 2.0).max(0.5);
    for y in y0..=y1 {
        for x in x0..=x1 {
            let nx = (x as f32 - cx) / rx;
            let ny = (y as f32 - cy) / ry;
            if nx * nx + ny * ny <= 1.0 {
                plot(x, y);
            }
        }
    }
}

/// Ellipse outline. 1px → Approach A (a clean traced 1px curve); thicker → an inward distance band
/// (`rotated_shape`) so the ring follows the silhouette instead of bulging out.
pub fn ellipse_outline(a: Point, b: Point, thickness: i32, plot: impl FnMut(i32, i32)) {
    rotated_shape(a, b, 0.0, 1, false, thickness, plot);
}

/// The three world-space vertices of the triangle inscribed in the box of `a`,`b`, rotated by `rot`
/// radians and with its apex skewed horizontally by `tip` ∈ [-1, 1] along the top edge (0 = centered
/// isosceles; ±1 = apex over a base corner = a right triangle). Base runs along the bottom edge.
fn triangle_vertices(a: Point, b: Point, rot: f32, tip: f32) -> [Point; 3] {
    let cx = (a.x + b.x) as f32 / 2.0;
    let cy = (a.y + b.y) as f32 / 2.0;
    let (sn, cs) = rot.sin_cos();
    // Local half-extents = the un-rotated vector from the center to corner `b`.
    let (vbx, vby) = (b.x as f32 - cx, b.y as f32 - cy);
    let hw = (cs * vbx + sn * vby).abs().max(0.5);
    let hh = (-sn * vbx + cs * vby).abs().max(0.5);
    let to_world = |lx: f32, ly: f32| {
        Point::new(
            (cx + cs * lx - sn * ly).round() as i32,
            (cy + sn * lx + cs * ly).round() as i32,
        )
    };
    let t = tip.clamp(-1.0, 1.0);
    [
        to_world(t * hw, -hh), // apex (skewable along the top edge)
        to_world(-hw, hh),     // bottom-left
        to_world(hw, hh),      // bottom-right
    ]
}

/// Filled triangle (rotated by `rot`, apex skewed by `tip`).
pub fn triangle_filled(a: Point, b: Point, rot: f32, tip: f32, plot: impl FnMut(i32, i32)) {
    polygon_filled(&triangle_vertices(a, b, rot, tip), plot);
}

/// Triangle outline (rotated by `rot`, apex skewed by `tip`). 1px → the three edges stroked as a
/// clean Bresenham polyline; thicker → an **inward distance band**: pixels inside the triangle and
/// within `thickness` of one of the three edges, so the ring follows the silhouette and grows inward
/// (a fat-brushed centerline would instead bulge out and round the corners off into a blob).
pub fn triangle_outline(a: Point, b: Point, rot: f32, tip: f32, thickness: i32, mut plot: impl FnMut(i32, i32)) {
    let v = triangle_vertices(a, b, rot, tip);
    if thickness <= 1 {
        stroke_polyline(&v, thickness, plot);
        return;
    }
    let lw = thickness.max(1) as f32;
    let vf = [
        (v[0].x as f32, v[0].y as f32),
        (v[1].x as f32, v[1].y as f32),
        (v[2].x as f32, v[2].y as f32),
    ];
    let len = |i: usize, j: usize| ((vf[j].0 - vf[i].0).powi(2) + (vf[j].1 - vf[i].1).powi(2)).sqrt().max(1e-6);
    let (l01, l12, l20) = (len(0, 1), len(1, 2), len(2, 0));
    let (x0, x1) = (v.iter().map(|p| p.x).min().unwrap(), v.iter().map(|p| p.x).max().unwrap());
    let (y0, y1) = (v.iter().map(|p| p.y).min().unwrap(), v.iter().map(|p| p.y).max().unwrap());
    for y in y0..=y1 {
        for x in x0..=x1 {
            let (px, py) = (x as f32, y as f32);
            // Signed edge functions: |value| / edge_length = perpendicular distance to that edge.
            let cross = |i: usize, j: usize| (vf[j].0 - vf[i].0) * (py - vf[i].1) - (vf[j].1 - vf[i].1) * (px - vf[i].0);
            let (e0, e1, e2) = (cross(0, 1), cross(1, 2), cross(2, 0));
            let inside = (e0 >= 0.0 && e1 >= 0.0 && e2 >= 0.0) || (e0 <= 0.0 && e1 <= 0.0 && e2 <= 0.0);
            if inside && (e0.abs() / l01).min(e1.abs() / l12).min(e2.abs() / l20) < lw {
                plot(x, y);
            }
        }
    }
}

/// Draw a Rectangle (`kind` 0) or Ellipse (`kind` 1), axis-aligned or rotated by `rot` (Triangle has
/// its own rot+tip path). `a`,`b` are the two (already-rotated) opposite corners.
///
/// - **1px outline** (`!fill && thickness <= 1`): traced as a Bresenham polyline (`shape_outline`,
///   Approach A) — a pixel-perfect, gap- and double-free 1px curve.
/// - **fill** / **thick outline**: inverse-rotate every candidate pixel into the shape's local frame
///   and test the exact predicate there (so rotation is mathematically perfect, never a post-hoc
///   rotation of drawn pixels). A thick outline is the **inward distance band** — pixels inside the
///   shape and within `thickness` of the boundary — so the ring follows the true silhouette, keeps a
///   uniform width, grows inward, and degrades to a clean fill once `thickness` exceeds the inset
///   (instead of a fat-brushed centerline bulging out into a blocky blob).
pub fn rotated_shape(
    a: Point,
    b: Point,
    rot: f32,
    kind: u8,
    fill: bool,
    thickness: i32,
    mut plot: impl FnMut(i32, i32),
) {
    if !fill && thickness <= 1 {
        shape_outline(a, b, rot, kind, thickness, plot);
        return;
    }
    let cx = (a.x + b.x) as f32 / 2.0;
    let cy = (a.y + b.y) as f32 / 2.0;
    let (sn, cs) = rot.sin_cos();
    // Local half-extents = the un-rotated vector from the center to corner `b`.
    let (vbx, vby) = (b.x as f32 - cx, b.y as f32 - cy);
    let hw = (cs * vbx + sn * vby).abs().max(0.5);
    let hh = (-sn * vbx + cs * vby).abs().max(0.5);
    let lw = thickness.max(1) as f32;
    // World AABB of the rotated box.
    let ax = cs.abs() * hw + sn.abs() * hh;
    let ay = sn.abs() * hw + cs.abs() * hh;
    let (x0, x1) = ((cx - ax).floor() as i32, (cx + ax).ceil() as i32);
    let (y0, y1) = ((cy - ay).floor() as i32, (cy + ay).ceil() as i32);
    for y in y0..=y1 {
        for x in x0..=x1 {
            let (dx, dy) = (x as f32 - cx, y as f32 - cy);
            let lx = cs * dx + sn * dy; // R(-rot)·(P - C)
            let ly = -sn * dx + cs * dy;
            let hit = if kind == 0 {
                let inside = lx.abs() <= hw && ly.abs() <= hh;
                // Inward distance to the nearest box edge = min(hw-|lx|, hh-|ly|) — exact, uniform.
                inside && (fill || (hw - lx.abs()).min(hh - ly.abs()) < lw)
            } else {
                let q = (lx / hw).powi(2) + (ly / hh).powi(2);
                if q > 1.0 {
                    false
                } else if fill {
                    true
                } else {
                    // Gradient-normalized distance to the ellipse boundary |f|/|∇f|, with f = q-1:
                    // a near-uniform perpendicular inward distance, no closed form needed. |∇f| is
                    // floored so the deep interior reports a finite distance (no center pinhole at
                    // huge thickness) while the near-boundary band — where the floor never binds —
                    // stays uniform. Degrades to a clean fill once thickness exceeds the radius.
                    let (gx, gy) = (lx / (hw * hw), ly / (hh * hh));
                    let grad = (2.0 * (gx * gx + gy * gy).sqrt()).max(1.0 / hw.max(hh));
                    (1.0 - q) / grad < lw
                }
            };
            if hit {
                plot(x, y);
            }
        }
    }
}

/// Circle inscribed centered at `center` with `radius` to `edge` point.
pub fn circle_filled(center: Point, edge: Point, mut plot: impl FnMut(i32, i32)) {
    let r = (((edge.x - center.x).pow(2) + (edge.y - center.y).pow(2)) as f32).sqrt();
    let r2 = r * r;
    let ri = r.ceil() as i32;
    for dy in -ri..=ri {
        for dx in -ri..=ri {
            if (dx * dx + dy * dy) as f32 <= r2 {
                plot(center.x + dx, center.y + dy);
            }
        }
    }
}

/// Scanline polygon fill (even-odd rule) over a closed polygon given by `pts`.
pub fn polygon_filled(pts: &[Point], mut plot: impl FnMut(i32, i32)) {
    if pts.len() < 3 {
        return;
    }
    let miny = pts.iter().map(|p| p.y).min().unwrap();
    let maxy = pts.iter().map(|p| p.y).max().unwrap();
    for y in miny..=maxy {
        let yf = y as f32 + 0.5;
        let mut xs: Vec<f32> = Vec::new();
        for i in 0..pts.len() {
            let p0 = pts[i];
            let p1 = pts[(i + 1) % pts.len()];
            let (y0, y1) = (p0.y as f32, p1.y as f32);
            if (y0 <= yf && y1 > yf) || (y1 <= yf && y0 > yf) {
                let t = (yf - y0) / (y1 - y0);
                xs.push(p0.x as f32 + t * (p1.x as f32 - p0.x as f32));
            }
        }
        xs.sort_by(|a, b| a.partial_cmp(b).unwrap());
        let mut i = 0;
        while i + 1 < xs.len() {
            let xa = xs[i].ceil() as i32;
            let xb = xs[i + 1].floor() as i32;
            for x in xa..=xb {
                plot(x, y);
            }
            i += 2;
        }
    }
}

// ---------------------------------------------------------------------------------------------
// AA (coverage) rasterizers — ADR 0008 / docs/aa-brush/DESIGN.md. Additive twins of the binary
// rasterizers above with a `plot(x, y, cover)` convention (`cover` 0..=255); the binary
// `FnMut(i32, i32)` functions stay untouched because they also build 1-bit selection masks.
//
// Model: each shape is a CONTINUOUS region in pixel-center space (the binary rasterizers sample
// pixel indices against centers at integer midpoints, so the continuous twin shifts by +0.5 and
// pads its extents by +0.5 — which makes an axis-aligned shape's full-coverage silhouette equal
// the binary one). Coverage = the fraction of a pixel's 16×16 subsample grid (centers at
// p + (2k+1)/32) inside the region — 257 levels, effectively exact at 8-bit. Thick outlines are
// coverage DIFFERENCES of two nested convex regions (outer minus inner), so a ring never
// double-counts and needs no non-convex predicate.
//
// Determinism: predicates are fixed-order f64 arithmetic over dyadic-rational sample points —
// only IEEE-exact ops (+ − × ÷, sqrt, floor, comparisons; never `mul_add`), with rotation from
// `util::det_sincos`, never libm `sin_cos` (the det_log2 doctrine, util.rs).

/// Subsample count of pixel `(x, y)` inside a CONVEX `inside` region (0..=256). Fast path: a
/// convex region containing all four pixel corners contains every interior subsample.
fn cover_convex(x: i32, y: i32, inside: &dyn Fn(f64, f64) -> bool) -> u32 {
    let (xf, yf) = (x as f64, y as f64);
    if inside(xf, yf) && inside(xf + 1.0, yf) && inside(xf, yf + 1.0) && inside(xf + 1.0, yf + 1.0) {
        return 256;
    }
    let mut cnt = 0u32;
    for j in 0..16 {
        let sy = yf + (2 * j + 1) as f64 / 32.0;
        for i in 0..16 {
            let sx = xf + (2 * i + 1) as f64 / 32.0;
            if inside(sx, sy) {
                cnt += 1;
            }
        }
    }
    cnt
}

/// Subsample count → 8-bit coverage: 0 → 0, 256 → 255, linear (rounded) between.
fn cover_to_alpha(cnt: u32) -> u8 {
    ((cnt * 255 + 128) >> 8) as u8
}

/// Plot the coverage of `outer` (minus `inner`, when given — `inner` MUST be a subset of
/// `outer`, as every ring here is a shrunk copy) over the pixel AABB.
fn plot_aa(
    (x0, y0, x1, y1): (i32, i32, i32, i32),
    outer: &dyn Fn(f64, f64) -> bool,
    inner: Option<&dyn Fn(f64, f64) -> bool>,
    plot: &mut dyn FnMut(i32, i32, u8),
) {
    for y in y0..=y1 {
        for x in x0..=x1 {
            let mut cnt = cover_convex(x, y, outer);
            if cnt > 0 {
                if let Some(inn) = inner {
                    cnt = cnt.saturating_sub(cover_convex(x, y, inn));
                }
            }
            let a = cover_to_alpha(cnt);
            if a > 0 {
                plot(x, y, a);
            }
        }
    }
}

/// AA disc: the coverage twin of [`disc`] — continuous radius `radius + 0.5` around the pixel
/// center of `c`, so its axial full-coverage extent matches the binary disc.
pub fn disc_aa(c: Point, radius: i32, mut plot: impl FnMut(i32, i32, u8)) {
    let r = radius.max(1) as f64 + 0.5;
    let (cx, cy) = (c.x as f64 + 0.5, c.y as f64 + 0.5);
    let r2 = r * r;
    let inside = move |sx: f64, sy: f64| {
        let (dx, dy) = (sx - cx, sy - cy);
        dx * dx + dy * dy <= r2
    };
    let bb = (
        (cx - r).floor() as i32,
        (cy - r).floor() as i32,
        (cx + r).ceil() as i32,
        (cy + r).ceil() as i32,
    );
    plot_aa(bb, &inside, None, &mut plot);
}

/// AA thick line: an oriented rectangle around the segment's pixel centers — perpendicular
/// half-widths carry [`thick_line`]'s asymmetric `lo = -(t-1)/2, hi = t/2` convention (+0.5
/// pad each side), ends extended 0.5 past the endpoint centers (square caps, matching the
/// binary silhouette's reach). `a == b` degenerates to the binary point-block's box.
pub fn thick_line_aa(a: Point, b: Point, thickness: i32, mut plot: impl FnMut(i32, i32, u8)) {
    let t = thickness.max(1);
    let (wl, wr) = (((t - 1) / 2) as f64 + 0.5, (t / 2) as f64 + 0.5);
    let (ax, ay) = (a.x as f64 + 0.5, a.y as f64 + 0.5);
    let (dxw, dyw) = ((b.x - a.x) as f64, (b.y - a.y) as f64);
    let d2 = dxw * dxw + dyw * dyw;
    if d2 == 0.0 {
        // The binary point stamp is the block a+lo ..= a+hi in both axes.
        let (lo, hi) = (-((t - 1) / 2) as f64, (t / 2) as f64);
        let inside = move |sx: f64, sy: f64| {
            sx - ax >= lo - 0.5 && sx - ax <= hi + 0.5 && sy - ay >= lo - 0.5 && sy - ay <= hi + 0.5
        };
        let bb = (
            (ax + lo - 0.5).floor() as i32,
            (ay + lo - 0.5).floor() as i32,
            (ax + hi + 0.5).ceil() as i32,
            (ay + hi + 0.5).ceil() as i32,
        );
        plot_aa(bb, &inside, None, &mut plot);
        return;
    }
    let len = d2.sqrt();
    let inside = move |sx: f64, sy: f64| {
        let (px, py) = (sx - ax, sy - ay);
        let along = px * dxw + py * dyw; // ∈ [0, d2] between the endpoint centers
        if along < -0.5 * len || along > d2 + 0.5 * len {
            return false;
        }
        let cross = px * dyw - py * dxw; // signed: + toward one perpendicular, − the other
        cross <= wl * len && cross >= -wr * len
    };
    let w = wl.max(wr) + 0.5;
    let bb = (
        (ax.min(ax + dxw) - w - 1.0).floor() as i32,
        (ay.min(ay + dyw) - w - 1.0).floor() as i32,
        (ax.max(ax + dxw) + w + 1.0).ceil() as i32,
        (ay.max(ay + dyw) + w + 1.0).ceil() as i32,
    );
    plot_aa(bb, &inside, None, &mut plot);
}

/// Shared geometry of the AA Rectangle/Ellipse: continuous center (pixel centers), det-rotated
/// local frame, half-extents padded +0.5, and the world AABB. Mirrors [`rotated_shape`]'s
/// derivation (including the 0.5 floor) with `det_sincos` in place of libm.
struct AaBox {
    cx: f64,
    cy: f64,
    sn: f64,
    cs: f64,
    hw: f64,
    hh: f64,
    bb: (i32, i32, i32, i32),
}

fn aa_box(a: Point, b: Point, rot: f32) -> AaBox {
    let cx0 = (a.x + b.x) as f64 / 2.0;
    let cy0 = (a.y + b.y) as f64 / 2.0;
    let (sn, cs) = crate::util::det_sincos(rot as f64);
    let (vbx, vby) = (b.x as f64 - cx0, b.y as f64 - cy0);
    let hw0 = (cs * vbx + sn * vby).abs().max(0.5);
    let hh0 = (-sn * vbx + cs * vby).abs().max(0.5);
    let (hw, hh) = (hw0 + 0.5, hh0 + 0.5);
    let (cx, cy) = (cx0 + 0.5, cy0 + 0.5);
    let ax = cs.abs() * hw + sn.abs() * hh;
    let ay = sn.abs() * hw + cs.abs() * hh;
    AaBox {
        cx,
        cy,
        sn,
        cs,
        hw,
        hh,
        bb: (
            (cx - ax - 1.0).floor() as i32,
            (cy - ay - 1.0).floor() as i32,
            (cx + ax + 1.0).ceil() as i32,
            (cy + ay + 1.0).ceil() as i32,
        ),
    }
}

/// AA Rectangle (axis-aligned or rotated): fill, or a `thickness`-wide inward ring (coverage of
/// the box minus the box shrunk by `thickness` — the binary inward-band convention).
pub fn rect_aa(a: Point, b: Point, rot: f32, fill: bool, thickness: i32, mut plot: impl FnMut(i32, i32, u8)) {
    let g = aa_box(a, b, rot);
    let (cx, cy, sn, cs, bb) = (g.cx, g.cy, g.sn, g.cs, g.bb);
    let box_inside = move |hw: f64, hh: f64| {
        move |sx: f64, sy: f64| {
            let (dx, dy) = (sx - cx, sy - cy);
            let lx = cs * dx + sn * dy;
            let ly = -sn * dx + cs * dy;
            lx.abs() <= hw && ly.abs() <= hh
        }
    };
    let outer = box_inside(g.hw, g.hh);
    let lw = thickness.max(1) as f64;
    let (ihw, ihh) = (g.hw - lw, g.hh - lw);
    if fill || ihw <= 0.0 || ihh <= 0.0 {
        plot_aa(bb, &outer, None, &mut plot);
    } else {
        let inner = box_inside(ihw, ihh);
        plot_aa(bb, &outer, Some(&inner), &mut plot);
    }
}

/// AA Ellipse (axis-aligned or rotated): fill, or a `thickness`-wide inward ring (outer ellipse
/// minus the ellipse with both semi-axes shrunk by `thickness`).
pub fn ellipse_aa(a: Point, b: Point, rot: f32, fill: bool, thickness: i32, mut plot: impl FnMut(i32, i32, u8)) {
    let g = aa_box(a, b, rot);
    let (cx, cy, sn, cs, bb) = (g.cx, g.cy, g.sn, g.cs, g.bb);
    let ell_inside = move |hw: f64, hh: f64| {
        move |sx: f64, sy: f64| {
            let (dx, dy) = (sx - cx, sy - cy);
            let lx = cs * dx + sn * dy;
            let ly = -sn * dx + cs * dy;
            (lx / hw) * (lx / hw) + (ly / hh) * (ly / hh) <= 1.0
        }
    };
    let outer = ell_inside(g.hw, g.hh);
    let lw = thickness.max(1) as f64;
    let (ihw, ihh) = (g.hw - lw, g.hh - lw);
    if fill || ihw <= 0.0 || ihh <= 0.0 {
        plot_aa(bb, &outer, None, &mut plot);
    } else {
        let inner = ell_inside(ihw, ihh);
        plot_aa(bb, &outer, Some(&inner), &mut plot);
    }
}

/// AA Triangle (rotated by `rot`, apex skewed by `tip`): fill, or the `thickness`-wide inward
/// ring. Vertices are [`triangle_vertices`]' UNROUNDED continuous positions (det-rotated, in
/// pixel-center space); "inside at margin m" = signed distance ≥ −m from every edge, so the
/// outer region is the triangle padded 0.5 outward (matching the rect/ellipse pad) and the ring
/// inner region is the triangle shrunk by `thickness − 0.5` — both convex.
pub fn triangle_aa(a: Point, b: Point, rot: f32, tip: f32, fill: bool, thickness: i32, mut plot: impl FnMut(i32, i32, u8)) {
    let cx = (a.x + b.x) as f64 / 2.0 + 0.5;
    let cy = (a.y + b.y) as f64 / 2.0 + 0.5;
    let (sn, cs) = crate::util::det_sincos(rot as f64);
    let (vbx, vby) = ((b.x - a.x) as f64 / 2.0, (b.y - a.y) as f64 / 2.0);
    let hw = (cs * vbx + sn * vby).abs().max(0.5);
    let hh = (-sn * vbx + cs * vby).abs().max(0.5);
    let to_world = |lx: f64, ly: f64| (cx + cs * lx - sn * ly, cy + sn * lx + cs * ly);
    let t = (tip as f64).clamp(-1.0, 1.0);
    let v = [to_world(t * hw, -hh), to_world(-hw, hh), to_world(hw, hh)];
    // Per-edge (unit-normalizing) data: cross(p) / len = signed distance; orientation fixed by
    // the triangle's signed area so "inside" is margin-uniform regardless of rotation.
    let edge = |i: usize, j: usize| {
        let (ex, ey) = (v[j].0 - v[i].0, v[j].1 - v[i].1);
        (v[i].0, v[i].1, ex, ey, (ex * ex + ey * ey).sqrt().max(1e-9))
    };
    let edges = [edge(0, 1), edge(1, 2), edge(2, 0)];
    let area2 = edges[0].2 * (v[2].1 - v[0].1) - edges[0].3 * (v[2].0 - v[0].0);
    let orient = if area2 >= 0.0 { 1.0 } else { -1.0 };
    let inside_at = move |margin: f64| {
        move |sx: f64, sy: f64| {
            edges.iter().all(|&(ox, oy, ex, ey, len)| {
                let cross = ex * (sy - oy) - ey * (sx - ox);
                orient * cross >= margin * len
            })
        }
    };
    let xs = [v[0].0, v[1].0, v[2].0];
    let ys = [v[0].1, v[1].1, v[2].1];
    let bb = (
        (xs.iter().cloned().fold(f64::MAX, f64::min) - 2.0).floor() as i32,
        (ys.iter().cloned().fold(f64::MAX, f64::min) - 2.0).floor() as i32,
        (xs.iter().cloned().fold(f64::MIN, f64::max) + 2.0).ceil() as i32,
        (ys.iter().cloned().fold(f64::MIN, f64::max) + 2.0).ceil() as i32,
    );
    let outer = inside_at(-0.5);
    let lw = thickness.max(1) as f64;
    if fill {
        plot_aa(bb, &outer, None, &mut plot);
    } else {
        let inner = inside_at(lw - 0.5);
        plot_aa(bb, &outer, Some(&inner), &mut plot);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn line_hits_endpoints() {
        let mut pts = Vec::new();
        line(Point::new(0, 0), Point::new(3, 3), |x, y| pts.push((x, y)));
        assert_eq!(pts.first(), Some(&(0, 0)));
        assert_eq!(pts.last(), Some(&(3, 3)));
    }

    #[test]
    fn disc_radius_one_is_plus_shape_plus_center() {
        let mut n = 0;
        disc(Point::new(5, 5), 1, |_, _| n += 1);
        assert_eq!(n, 5); // center + 4 orthogonal neighbors
    }

    #[test]
    fn rect_filled_area() {
        let mut n = 0;
        rect_filled(Point::new(0, 0), Point::new(2, 1), |_, _| n += 1);
        assert_eq!(n, 6);
    }

    #[test]
    fn thick_line_width_changes_every_unit() {
        // A horizontal line: its pixel height must equal the requested thickness for every t, so
        // widths 1,2,3,4,… are all distinct (the old centered-stamp made 2≡1, 4≡3, …).
        for t in 1..=8 {
            use std::collections::HashSet;
            let mut ys: HashSet<i32> = HashSet::new();
            thick_line(Point::new(0, 50), Point::new(10, 50), t, |_, y| {
                ys.insert(y);
            });
            assert_eq!(ys.len() as i32, t, "thickness {t} produced height {}", ys.len());
        }
    }

    #[test]
    fn rotated_thin_ellipse_outline_is_8_connected() {
        // A steep ~4:1 ellipse rotated ~30° — the exact case that left gaps under the old band test.
        // Approach A traces it as a Bresenham polyline, so every outline pixel must touch a neighbor
        // (no discontinuities) — and being a single 1px curve, no pixel is isolated.
        use std::collections::HashSet;
        let mut set: HashSet<(i32, i32)> = HashSet::new();
        shape_outline(Point::new(-20, -5), Point::new(20, 5), 0.52, 1, 1, |x, y| {
            set.insert((x, y));
        });
        assert!(set.len() > 30, "outline too sparse: {}", set.len());
        for &(x, y) in &set {
            let connected = (-1..=1).any(|dy| {
                (-1..=1).any(|dx| (dx, dy) != (0, 0) && set.contains(&(x + dx, y + dy)))
            });
            assert!(connected, "outline pixel ({x},{y}) is isolated — a gap");
        }
    }

    #[test]
    fn rotated_1px_ellipse_outline_has_no_doubles() {
        // A "double" = a fully-filled 2×2 block: the 1px ring is locally 2px-thick there. After the
        // chain corner-removal pass, a rotated thin ellipse must contain no such block.
        use std::collections::HashSet;
        let mut set: HashSet<(i32, i32)> = HashSet::new();
        shape_outline(Point::new(-18, -6), Point::new(18, 6), 0.5, 1, 1, |x, y| {
            set.insert((x, y));
        });
        assert!(set.len() > 30);
        for &(x, y) in &set {
            let block = set.contains(&(x + 1, y)) && set.contains(&(x, y + 1)) && set.contains(&(x + 1, y + 1));
            assert!(!block, "doubled (2×2) pixels at ({x},{y})");
        }
    }

    #[test]
    fn thick_ellipse_outline_follows_silhouette() {
        use std::collections::HashSet;
        let (a, b) = (Point::new(0, 0), Point::new(30, 18));
        let mut fill: HashSet<(i32, i32)> = HashSet::new();
        ellipse_filled(a, b, |x, y| {
            fill.insert((x, y));
        });
        let mut ring: HashSet<(i32, i32)> = HashSet::new();
        ellipse_outline(a, b, 5, |x, y| {
            ring.insert((x, y));
        });
        // No outline pixel bulges outside the silhouette, and the outer edge reaches it.
        for p in &ring {
            assert!(fill.contains(p), "thick outline pixel {p:?} bulged outside the ellipse");
        }
        assert!(ring.contains(&(0, 9)), "outer edge reaches the silhouette");
        assert!(!ring.contains(&(15, 9)), "center is hollow at moderate thickness");
    }

    #[test]
    fn over_thick_ellipse_outline_becomes_a_clean_fill() {
        use std::collections::HashSet;
        let (a, b) = (Point::new(0, 0), Point::new(20, 12));
        let mut fill: HashSet<(i32, i32)> = HashSet::new();
        ellipse_filled(a, b, |x, y| {
            fill.insert((x, y));
        });
        let mut ring: HashSet<(i32, i32)> = HashSet::new();
        ellipse_outline(a, b, 99, |x, y| {
            ring.insert((x, y));
        });
        assert_eq!(fill, ring, "a thickness past the radius fills the exact shape (no center pinhole)");
    }

    // ---- AA (coverage) rasterizers ----

    fn covers(f: impl FnOnce(&mut dyn FnMut(i32, i32, u8))) -> std::collections::HashMap<(i32, i32), u8> {
        let mut m = std::collections::HashMap::new();
        f(&mut |x, y, c| {
            assert!(c > 0, "zero-coverage pixels must not be plotted");
            assert!(m.insert((x, y), c).is_none(), "pixel ({x},{y}) plotted twice");
        });
        m
    }

    #[test]
    fn disc_aa_brackets_the_binary_disc() {
        let c = Point::new(10, 10);
        let m = covers(|p| disc_aa(c, 4, |x, y, cv| p(x, y, cv)));
        let mut hard = std::collections::HashSet::new();
        disc(c, 4, |x, y| {
            hard.insert((x, y));
        });
        // Every binary pixel has AA coverage; every FULL AA pixel is a binary pixel.
        for p in &hard {
            assert!(m.contains_key(p), "binary disc pixel {p:?} lost by AA");
        }
        for (p, &cv) in &m {
            if cv == 255 {
                assert!(hard.contains(p), "AA-full pixel {p:?} outside the binary disc");
            }
        }
        // The rim actually anti-aliases: partial coverage exists, and the axial extremes match.
        assert!(m.values().any(|&c| c > 0 && c < 255), "no partial rim coverage");
        assert_eq!(m.get(&(14, 10)).copied(), Some(255), "axial extreme is full");
        assert!(!m.contains_key(&(16, 10)), "coverage ends past the rim");
    }

    #[test]
    fn disc_aa_coverage_decreases_outward() {
        let c = Point::new(12, 12);
        let m = covers(|p| disc_aa(c, 5, |x, y, cv| p(x, y, cv)));
        let row: Vec<u8> = (12..=19).map(|x| m.get(&(x, 12)).copied().unwrap_or(0)).collect();
        for w in row.windows(2) {
            assert!(w[0] >= w[1], "coverage must fall monotonically along the radius: {row:?}");
        }
    }

    #[test]
    fn thick_line_aa_horizontal_matches_the_binary_band() {
        // A horizontal w1 line: the center row is full, the rows above/below empty (the
        // continuous band edge lands exactly on pixel boundaries — no smear on the axis).
        let m = covers(|p| thick_line_aa(Point::new(2, 5), Point::new(9, 5), 1, |x, y, cv| p(x, y, cv)));
        for x in 2..=9 {
            assert_eq!(m.get(&(x, 5)).copied(), Some(255), "center row full at x={x}");
        }
        assert!(m.get(&(5, 4)).is_none() && m.get(&(5, 6)).is_none(), "w1 stays one row on-axis");
        // The diagonal case does anti-alias.
        let d = covers(|p| thick_line_aa(Point::new(0, 0), Point::new(9, 6), 1, |x, y, cv| p(x, y, cv)));
        assert!(d.values().any(|&c| c > 0 && c < 255), "diagonal line has partial rim coverage");
    }

    #[test]
    fn rect_aa_axis_aligned_full_set_is_the_binary_rect() {
        let (a, b) = (Point::new(3, 4), Point::new(12, 9));
        let m = covers(|p| rect_aa(a, b, 0.0, true, 1, |x, y, cv| p(x, y, cv)));
        let mut hard = std::collections::HashSet::new();
        rect_filled(a, b, |x, y| {
            hard.insert((x, y));
        });
        let full: std::collections::HashSet<(i32, i32)> =
            m.iter().filter(|&(_, &c)| c == 255).map(|(&p, _)| p).collect();
        assert_eq!(full, hard, "axis-aligned AA rect's full-coverage silhouette == binary rect");
    }

    #[test]
    fn rect_aa_ring_is_hollow_and_inside_the_fill() {
        let (a, b) = (Point::new(2, 2), Point::new(17, 12));
        let fill = covers(|p| rect_aa(a, b, 0.3, true, 1, |x, y, cv| p(x, y, cv)));
        let ring = covers(|p| rect_aa(a, b, 0.3, false, 2, |x, y, cv| p(x, y, cv)));
        for (p, &c) in &ring {
            let f = fill.get(p).copied().unwrap_or(0);
            assert!(f >= c, "ring coverage exceeds fill coverage at {p:?} ({c} > {f})");
        }
        let (cx, cy) = ((2 + 17) / 2, (2 + 12) / 2);
        assert!(!ring.contains_key(&(cx, cy)), "ring center must be hollow");
        assert_eq!(fill.get(&(cx, cy)).copied(), Some(255), "fill center is full");
    }

    #[test]
    fn ellipse_aa_brackets_the_binary_ellipse() {
        let (a, b) = (Point::new(0, 0), Point::new(18, 10));
        let m = covers(|p| ellipse_aa(a, b, 0.0, true, 1, |x, y, cv| p(x, y, cv)));
        let mut hard = std::collections::HashSet::new();
        ellipse_filled(a, b, |x, y| {
            hard.insert((x, y));
        });
        for p in &hard {
            assert!(m.contains_key(p), "binary ellipse pixel {p:?} lost by AA");
        }
        assert!(m.values().any(|&c| c > 0 && c < 255), "no partial rim coverage");
    }

    #[test]
    fn triangle_aa_fills_solid_and_rings_hollow() {
        let (a, b) = (Point::new(2, 2), Point::new(20, 16));
        let fill = covers(|p| triangle_aa(a, b, 0.0, 0.0, true, 1, |x, y, cv| p(x, y, cv)));
        // The centroid region is fully covered; the rim anti-aliases.
        assert_eq!(fill.get(&(11, 12)).copied(), Some(255), "deep interior is full");
        assert!(fill.values().any(|&c| c > 0 && c < 255), "no partial rim coverage");
        let ring = covers(|p| triangle_aa(a, b, 0.0, 0.0, false, 2, |x, y, cv| p(x, y, cv)));
        assert!(!ring.contains_key(&(11, 12)), "ring interior must be hollow");
        for (p, &c) in &ring {
            let f = fill.get(p).copied().unwrap_or(0);
            assert!(f >= c, "ring coverage exceeds fill coverage at {p:?} ({c} > {f})");
        }
    }

    #[test]
    fn rotated_aa_shapes_are_deterministic_across_runs() {
        // Two evaluations must agree bit-for-bit (det_sincos + fixed-order f64 — no libm).
        let run = || {
            let mut v = Vec::new();
            rect_aa(Point::new(3, 3), Point::new(20, 16), 0.3, false, 2, |x, y, c| v.push((x, y, c)));
            ellipse_aa(Point::new(3, 3), Point::new(20, 16), 0.3, true, 1, |x, y, c| v.push((x, y, c)));
            triangle_aa(Point::new(3, 3), Point::new(20, 18), 0.3, 0.4, true, 1, |x, y, c| v.push((x, y, c)));
            v
        };
        assert_eq!(run(), run());
    }

    #[test]
    fn thick_triangle_outline_stays_inside() {
        use std::collections::HashSet;
        let (a, b) = (Point::new(0, 0), Point::new(24, 20));
        let mut fill: HashSet<(i32, i32)> = HashSet::new();
        triangle_filled(a, b, 0.0, 0.0, |x, y| {
            fill.insert((x, y));
        });
        let mut ring: HashSet<(i32, i32)> = HashSet::new();
        triangle_outline(a, b, 0.0, 0.0, 4, |x, y| {
            ring.insert((x, y));
        });
        assert!(!ring.is_empty());
        // Within 1px of the filled silhouette — tolerant of the boundary-rasterisation difference
        // between polygon_filled and the cross-product test, but still catching a real outward bulge
        // (the old square-stamp stroke pushed pixels t/2 ≈ 2px beyond the edge).
        for &(x, y) in &ring {
            let near = (-1..=1).any(|dy| (-1..=1).any(|dx| fill.contains(&(x + dx, y + dy))));
            assert!(near, "thick triangle outline pixel ({x},{y}) bulged outside the triangle");
        }
    }

    #[test]
    fn ellipse_outline_is_hollow() {
        use std::collections::HashSet;
        let mut set: HashSet<(i32, i32)> = HashSet::new();
        ellipse_outline(Point::new(0, 0), Point::new(20, 12), 1, |x, y| {
            set.insert((x, y));
        });
        assert!(!set.contains(&(10, 6)), "interior center should be hollow");
        assert!(set.contains(&(10, 0)) || set.contains(&(10, 12)), "top/bottom of ring present");
    }

    #[test]
    fn polygon_triangle_fills() {
        let tri = [Point::new(0, 0), Point::new(4, 0), Point::new(0, 4)];
        let mut n = 0;
        polygon_filled(&tri, |_, _| n += 1);
        assert!(n > 5);
    }
}
