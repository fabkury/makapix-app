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

/// Rectangle outline of the given thickness (inclusive corners).
pub fn rect_outline(a: Point, b: Point, thickness: i32, mut plot: impl FnMut(i32, i32)) {
    let t = thickness.max(1);
    let (x0, x1) = (a.x.min(b.x), a.x.max(b.x));
    let (y0, y1) = (a.y.min(b.y), a.y.max(b.y));
    for y in y0..=y1 {
        for x in x0..=x1 {
            let near = (x - x0) < t || (x1 - x) < t || (y - y0) < t || (y1 - y) < t;
            if near {
                plot(x, y);
            }
        }
    }
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

/// Ellipse outline (filled minus inner-eroded fill, thickness in pixels).
pub fn ellipse_outline(a: Point, b: Point, thickness: i32, mut plot: impl FnMut(i32, i32)) {
    let t = thickness.max(1) as f32;
    let (x0, x1) = (a.x.min(b.x), a.x.max(b.x));
    let (y0, y1) = (a.y.min(b.y), a.y.max(b.y));
    let cx = (x0 + x1) as f32 / 2.0;
    let cy = (y0 + y1) as f32 / 2.0;
    let rx = ((x1 - x0) as f32 / 2.0).max(0.5);
    let ry = ((y1 - y0) as f32 / 2.0).max(0.5);
    let irx = (rx - t).max(0.0);
    let iry = (ry - t).max(0.0);
    for y in y0..=y1 {
        for x in x0..=x1 {
            let nx = (x as f32 - cx) / rx;
            let ny = (y as f32 - cy) / ry;
            let inside_outer = nx * nx + ny * ny <= 1.0;
            let inside_inner = if irx <= 0.0 || iry <= 0.0 {
                false
            } else {
                let ix = (x as f32 - cx) / irx;
                let iy = (y as f32 - cy) / iry;
                ix * ix + iy * iy <= 1.0
            };
            if inside_outer && !inside_inner {
                plot(x, y);
            }
        }
    }
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

/// Triangle outline (its three edges drawn as thick lines).
pub fn triangle_outline(a: Point, b: Point, thickness: i32, mut plot: impl FnMut(i32, i32)) {
    let v = triangle_verts(a, b);
    thick_line(v[0], v[1], thickness, &mut plot);
    thick_line(v[1], v[2], thickness, &mut plot);
    thick_line(v[2], v[0], thickness, &mut plot);
}

/// Draw a ROTATED shape (`kind`: 0=Rectangle, 1=Ellipse, 2=Triangle) by inverse-rotating every
/// candidate pixel into the shape's local frame and testing the exact predicate there — so rotation
/// is mathematically perfect, never a post-hoc rotation of already-drawn pixels. `a`,`b` are the two
/// (already-rotated) opposite corners; `rot` is the box rotation in radians; `thickness` is the
/// outline width when `!fill`.
pub fn rotated_shape(
    a: Point,
    b: Point,
    rot: f32,
    kind: u8,
    fill: bool,
    thickness: i32,
    mut plot: impl FnMut(i32, i32),
) {
    let cx = (a.x + b.x) as f32 / 2.0;
    let cy = (a.y + b.y) as f32 / 2.0;
    let (sn, cs) = rot.sin_cos();
    // Local half-extents = the un-rotated vector from the centre to corner `b`.
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
            let hit = match kind {
                0 => rect_hit(lx, ly, hw, hh, fill, lw),
                1 => ellipse_hit(lx, ly, hw, hh, fill, lw),
                _ => triangle_hit(lx, ly, hw, hh, fill, lw),
            };
            if hit {
                plot(x, y);
            }
        }
    }
}

fn rect_hit(lx: f32, ly: f32, hw: f32, hh: f32, fill: bool, lw: f32) -> bool {
    if lx.abs() > hw || ly.abs() > hh {
        return false;
    }
    fill || (hw - lx.abs()) < lw || (hh - ly.abs()) < lw
}

fn ellipse_hit(lx: f32, ly: f32, hw: f32, hh: f32, fill: bool, lw: f32) -> bool {
    if (lx / hw).powi(2) + (ly / hh).powi(2) > 1.0 {
        return false;
    }
    if fill {
        return true;
    }
    let (irx, iry) = (hw - lw, hh - lw);
    if irx <= 0.0 || iry <= 0.0 {
        return true;
    }
    (lx / irx).powi(2) + (ly / iry).powi(2) > 1.0 // outer but not inner = the ring
}

fn triangle_hit(lx: f32, ly: f32, hw: f32, hh: f32, fill: bool, lw: f32) -> bool {
    // Local verts: apex top-centre, base along the bottom.
    let v = [(0.0, -hh), (-hw, hh), (hw, hh)];
    let cross = |i: usize, j: usize| (v[j].0 - v[i].0) * (ly - v[i].1) - (v[j].1 - v[i].1) * (lx - v[i].0);
    let (e0, e1, e2) = (cross(0, 1), cross(1, 2), cross(2, 0));
    let inside = (e0 >= 0.0 && e1 >= 0.0 && e2 >= 0.0) || (e0 <= 0.0 && e1 <= 0.0 && e2 <= 0.0);
    if !inside {
        return false;
    }
    if fill {
        return true;
    }
    let dist = |i: usize, j: usize| {
        let (ex, ey) = (v[j].0 - v[i].0, v[j].1 - v[i].1);
        let len = (ex * ex + ey * ey).sqrt().max(1e-6);
        (ex * (ly - v[i].1) - ey * (lx - v[i].0)).abs() / len
    };
    dist(0, 1).min(dist(1, 2)).min(dist(2, 0)) < lw
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
    fn polygon_triangle_fills() {
        let tri = [Point::new(0, 0), Point::new(4, 0), Point::new(0, 4)];
        let mut n = 0;
        polygon_filled(&tri, |_, _| n += 1);
        assert!(n > 5);
    }
}
