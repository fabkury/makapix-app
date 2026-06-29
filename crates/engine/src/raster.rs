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

/// A line of the given pixel `thickness`: a square stamp of side `thickness` swept along the
/// Bresenham line (thickness 1 = a plain hairline). Used by the Line tool's Width.
pub fn thick_line(a: Point, b: Point, thickness: i32, mut plot: impl FnMut(i32, i32)) {
    let r = (thickness.max(1) - 1) / 2;
    if r <= 0 {
        line(a, b, plot);
        return;
    }
    let mut pts = Vec::new();
    line(a, b, |x, y| pts.push(Point::new(x, y)));
    for p in pts {
        square(p, r, &mut plot);
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

/// Outline of a shape (`kind`: 0=Rectangle, 1=Ellipse, 2=Triangle), axis-aligned or rotated by
/// `rot` radians, drawn with **Approach A**: trace the exact boundary in the shape's local frame,
/// rotate the boundary points into place, then stroke the connected polyline. `a`,`b` are the two
/// (already-rotated) opposite corners of the box; `thickness` is the outline width. Because the
/// curve is rasterised as Bresenham segments — not by testing each pixel's distance to the boundary
/// — the result is a continuous `thickness`-px line with no gaps or doubled pixels.
pub fn shape_outline(a: Point, b: Point, rot: f32, kind: u8, thickness: i32, plot: impl FnMut(i32, i32)) {
    let cx = (a.x + b.x) as f32 / 2.0;
    let cy = (a.y + b.y) as f32 / 2.0;
    let (sn, cs) = rot.sin_cos();
    // Local half-extents = the un-rotated vector from the centre to corner `b`.
    let (vbx, vby) = (b.x as f32 - cx, b.y as f32 - cy);
    let hw = (cs * vbx + sn * vby).abs().max(0.5);
    let hh = (-sn * vbx + cs * vby).abs().max(0.5);
    // Map a local (lx,ly) to a world pixel, applying R(rot) about the centre.
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
        2 => {
            pts.push(to_world(0.0, -hh)); // apex (top centre)
            pts.push(to_world(-hw, hh)); // bottom-left
            pts.push(to_world(hw, hh)); // bottom-right
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
        }
    }
    stroke_polyline(&pts, thickness, plot);
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

/// Rectangle outline of the given thickness (Approach A: the four edges stroked as a polyline).
pub fn rect_outline(a: Point, b: Point, thickness: i32, plot: impl FnMut(i32, i32)) {
    shape_outline(a, b, 0.0, 0, thickness, plot);
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

/// Ellipse outline (Approach A: the parametric boundary traced and stroked as a polyline, so the
/// line is continuous and uniform-width — no gaps at the high-curvature ends, no doubled pixels).
pub fn ellipse_outline(a: Point, b: Point, thickness: i32, plot: impl FnMut(i32, i32)) {
    shape_outline(a, b, 0.0, 1, thickness, plot);
}

/// The three vertices of the triangle inscribed in the box of `a`,`b`: apex at top-centre, base
/// along the bottom edge (an upward-pointing isosceles triangle).
fn triangle_verts(a: Point, b: Point) -> [Point; 3] {
    let (x0, x1) = (a.x.min(b.x), a.x.max(b.x));
    let (y0, y1) = (a.y.min(b.y), a.y.max(b.y));
    [
        Point::new((x0 + x1) / 2, y0), // apex (top centre)
        Point::new(x0, y1),            // bottom-left
        Point::new(x1, y1),            // bottom-right
    ]
}

/// Filled triangle inscribed in the bounding box of the two corner points.
pub fn triangle_filled(a: Point, b: Point, plot: impl FnMut(i32, i32)) {
    polygon_filled(&triangle_verts(a, b), plot);
}

/// Triangle outline (Approach A: its three edges stroked as a closed polyline).
pub fn triangle_outline(a: Point, b: Point, thickness: i32, plot: impl FnMut(i32, i32)) {
    shape_outline(a, b, 0.0, 2, thickness, plot);
}

/// Draw a ROTATED shape (`kind`: 0=Rectangle, 1=Ellipse, 2=Triangle), `a`,`b` being the two
/// (already-rotated) opposite corners and `rot` the box rotation in radians. Outlines are traced as
/// a Bresenham polyline (`shape_outline`, Approach A); a fill inverse-rotates every candidate pixel
/// into the shape's local frame and tests the exact inside predicate there — so rotation is
/// mathematically perfect, never a post-hoc rotation of already-drawn pixels.
pub fn rotated_shape(
    a: Point,
    b: Point,
    rot: f32,
    kind: u8,
    fill: bool,
    thickness: i32,
    mut plot: impl FnMut(i32, i32),
) {
    if !fill {
        shape_outline(a, b, rot, kind, thickness, plot);
        return;
    }
    let cx = (a.x + b.x) as f32 / 2.0;
    let cy = (a.y + b.y) as f32 / 2.0;
    let (sn, cs) = rot.sin_cos();
    // Local half-extents = the un-rotated vector from the centre to corner `b`.
    let (vbx, vby) = (b.x as f32 - cx, b.y as f32 - cy);
    let hw = (cs * vbx + sn * vby).abs().max(0.5);
    let hh = (-sn * vbx + cs * vby).abs().max(0.5);
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
            let inside = match kind {
                0 => lx.abs() <= hw && ly.abs() <= hh,
                1 => (lx / hw).powi(2) + (ly / hh).powi(2) <= 1.0,
                _ => triangle_inside(lx, ly, hw, hh),
            };
            if inside {
                plot(x, y);
            }
        }
    }
}

fn triangle_inside(lx: f32, ly: f32, hw: f32, hh: f32) -> bool {
    // Local verts: apex top-centre, base along the bottom.
    let v = [(0.0, -hh), (-hw, hh), (hw, hh)];
    let cross = |i: usize, j: usize| (v[j].0 - v[i].0) * (ly - v[i].1) - (v[j].1 - v[i].1) * (lx - v[i].0);
    let (e0, e1, e2) = (cross(0, 1), cross(1, 2), cross(2, 0));
    (e0 >= 0.0 && e1 >= 0.0 && e2 >= 0.0) || (e0 <= 0.0 && e1 <= 0.0 && e2 <= 0.0)
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
    fn rotated_thin_ellipse_outline_is_8_connected() {
        // A steep ~4:1 ellipse rotated ~30° — the exact case that left gaps under the old band test.
        // Approach A traces it as a Bresenham polyline, so every outline pixel must touch a neighbour
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
    fn ellipse_outline_is_hollow() {
        use std::collections::HashSet;
        let mut set: HashSet<(i32, i32)> = HashSet::new();
        ellipse_outline(Point::new(0, 0), Point::new(20, 12), 1, |x, y| {
            set.insert((x, y));
        });
        assert!(!set.contains(&(10, 6)), "interior centre should be hollow");
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
