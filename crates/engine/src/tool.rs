//! Tools & operations (SPEC §11, §28.1). Each is a pure mutation of a layer `RgbaBuffer`,
//! optionally clipped to a selection `Mask`. The `Session` (session.rs) drives these from
//! pointer/DSL input and wraps each committed change in one undo record.

use crate::buffer::RgbaBuffer;
use crate::color::{self, Rgba8};
use crate::geom::Point;
use crate::raster;
use crate::selection::Mask;
use crate::util::SeededRng;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ToolKind {
    Pencil,
    PrecisionPencil,
    Brush,
    Airbrush,
    Eraser,
    Bucket,
    Gradient,
    Dodge,
    Burn,
    Move,
    MoveLayer,
    Eyedropper,
    Line,
    Rectangle,
    Ellipse,
    SelectRect,
    SelectEllipse,
    SelectCircle,
    SelectPoly,
    SelectFree,
    SelectByColor,
    HsvShift,
}

impl Default for ToolKind {
    fn default() -> Self {
        ToolKind::Pencil
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum BrushShape {
    #[default]
    Round,
    Square,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PaintMode {
    /// Hard replace (pencil): overwrites the pixel with the color.
    Replace,
    /// Alpha-over (brush): blends the color onto existing content.
    Over,
    /// Erase: forces the pixel transparent.
    Erase,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GradientKind {
    Linear,
    Radial,
}

#[derive(Clone, Copy, Debug)]
pub struct Stop {
    pub color: Rgba8,
    pub t: f32,
}
impl Stop {
    pub fn new(color: Rgba8, t: f32) -> Self {
        Stop { color, t: t.clamp(0.0, 1.0) }
    }
}

#[derive(Clone)]
pub struct GradientSpec {
    pub kind: GradientKind,
    pub stops: Vec<Stop>,
    pub dither: bool,
}
impl Default for GradientSpec {
    fn default() -> Self {
        GradientSpec {
            kind: GradientKind::Linear,
            stops: vec![Stop::new(Rgba8::BLACK, 0.0), Stop::new(Rgba8::WHITE, 1.0)],
            dither: false,
        }
    }
}

#[derive(Clone)]
pub struct ToolSettings {
    pub primary: Rgba8,
    pub secondary: Rgba8,
    pub brush_size: u16,
    pub brush_shape: BrushShape,
    pub intensity: u8,
    pub threshold: u8,
    pub contiguous: bool,
    pub gradient: GradientSpec,
    pub hsv: (f32, f32, f32),
    pub shape_fill: bool,
    pub line_width: u16,
    /// When true, the Move-Layer tool refuses to push any opaque pixel off-canvas (non-destructive).
    pub protect_pixels: bool,
}
impl Default for ToolSettings {
    fn default() -> Self {
        ToolSettings {
            primary: Rgba8::BLACK,
            secondary: Rgba8::WHITE,
            brush_size: 1,
            brush_shape: BrushShape::Round,
            intensity: 128,
            threshold: 0,
            contiguous: true,
            gradient: GradientSpec::default(),
            hsv: (0.0, 0.0, 0.0),
            shape_fill: true,
            line_width: 1,
            protect_pixels: false,
        }
    }
}

/// Write `color` at (x,y) honoring the selection clip and paint mode.
#[inline]
pub fn plot(buf: &mut RgbaBuffer, sel: Option<&Mask>, x: i32, y: i32, color: Rgba8, mode: PaintMode) {
    if let Some(m) = sel {
        if !m.get(x, y) {
            return;
        }
    }
    match mode {
        PaintMode::Replace => buf.set(x, y, color),
        PaintMode::Over => buf.blend_over(x, y, color),
        PaintMode::Erase => buf.set(x, y, Rgba8::TRANSPARENT),
    }
}

/// A single brush stamp of the configured size/shape.
pub fn stamp(
    buf: &mut RgbaBuffer,
    sel: Option<&Mask>,
    center: Point,
    size: u16,
    shape: BrushShape,
    color: Rgba8,
    mode: PaintMode,
) {
    let radius = (size.max(1) as i32 - 1) / 2;
    let mut f = |x: i32, y: i32| plot(buf, sel, x, y, color, mode);
    match shape {
        BrushShape::Round => {
            if size <= 1 {
                f(center.x, center.y);
            } else {
                raster::disc(center, radius.max(1), &mut f);
            }
        }
        BrushShape::Square => raster::square(center, radius, &mut f),
    }
}

/// Interpolated stroke segment from `a` to `b`, stamping along the path (SPEC §11.1).
pub fn stroke_segment(
    buf: &mut RgbaBuffer,
    sel: Option<&Mask>,
    a: Point,
    b: Point,
    size: u16,
    shape: BrushShape,
    color: Rgba8,
    mode: PaintMode,
) {
    let mut centers = Vec::new();
    raster::line(a, b, |x, y| centers.push(Point::new(x, y)));
    for c in centers {
        stamp(buf, sel, c, size, shape, color, mode);
    }
}

/// Flood fill from `seed` (SPEC §11.2). Returns true if any pixel changed.
pub fn flood_fill(
    buf: &mut RgbaBuffer,
    sel: Option<&Mask>,
    seed: Point,
    color: Rgba8,
    threshold: u8,
    contiguous: bool,
    mode: PaintMode,
) {
    let w = buf.width() as i32;
    let h = buf.height() as i32;
    if seed.x < 0 || seed.y < 0 || seed.x >= w || seed.y >= h {
        return;
    }
    let target = buf.get(seed.x, seed.y);
    let in_sel = |x: i32, y: i32| sel.map(|m| m.get(x, y)).unwrap_or(true);
    if contiguous {
        let mut visited = vec![false; (w * h) as usize];
        let mut stack = vec![seed];
        while let Some(p) = stack.pop() {
            if p.x < 0 || p.y < 0 || p.x >= w || p.y >= h {
                continue;
            }
            let idx = (p.y * w + p.x) as usize;
            if visited[idx] {
                continue;
            }
            visited[idx] = true;
            if !in_sel(p.x, p.y) || color::max_channel_delta(buf.get(p.x, p.y), target) > threshold {
                continue;
            }
            plot(buf, sel, p.x, p.y, color, mode);
            stack.push(Point::new(p.x + 1, p.y));
            stack.push(Point::new(p.x - 1, p.y));
            stack.push(Point::new(p.x, p.y + 1));
            stack.push(Point::new(p.x, p.y - 1));
        }
    } else {
        for y in 0..h {
            for x in 0..w {
                if in_sel(x, y) && color::max_channel_delta(buf.get(x, y), target) <= threshold {
                    plot(buf, sel, x, y, color, mode);
                }
            }
        }
    }
}

/// Sample a gradient's color at parameter `t∈[0,1]` over sorted stops.
pub fn gradient_color_at(stops: &[Stop], t: f32) -> Rgba8 {
    if stops.is_empty() {
        return Rgba8::TRANSPARENT;
    }
    let mut s: Vec<Stop> = stops.to_vec();
    s.sort_by(|a, b| a.t.partial_cmp(&b.t).unwrap());
    if t <= s[0].t {
        return s[0].color;
    }
    if t >= s[s.len() - 1].t {
        return s[s.len() - 1].color;
    }
    for i in 0..s.len() - 1 {
        if t >= s[i].t && t <= s[i + 1].t {
            let span = (s[i + 1].t - s[i].t).max(1e-6);
            let local = (t - s[i].t) / span;
            return color::lerp_srgb(s[i].color, s[i + 1].color, local);
        }
    }
    s[s.len() - 1].color
}

/// Parameter `t` for a pixel under a linear/radial gradient defined by p0→p1.
pub fn gradient_t(kind: GradientKind, p0: Point, p1: Point, x: i32, y: i32) -> f32 {
    match kind {
        GradientKind::Linear => {
            let dx = (p1.x - p0.x) as f32;
            let dy = (p1.y - p0.y) as f32;
            let len2 = dx * dx + dy * dy;
            if len2 <= 0.0 {
                return 0.0;
            }
            let px = (x - p0.x) as f32;
            let py = (y - p0.y) as f32;
            ((px * dx + py * dy) / len2).clamp(0.0, 1.0)
        }
        GradientKind::Radial => {
            let r = (((p1.x - p0.x).pow(2) + (p1.y - p0.y).pow(2)) as f32).sqrt();
            if r <= 0.0 {
                return 0.0;
            }
            let d = (((x - p0.x).pow(2) + (y - p0.y).pow(2)) as f32).sqrt();
            (d / r).clamp(0.0, 1.0)
        }
    }
}

/// Evaluate the gradient color for a pixel (closed form; the oracle uses the same path).
pub fn gradient_eval(kind: GradientKind, stops: &[Stop], p0: Point, p1: Point, x: i32, y: i32) -> Rgba8 {
    gradient_color_at(stops, gradient_t(kind, p0, p1, x, y))
}

/// Fill a region with the gradient, clipped to selection (SPEC §11.3).
pub fn apply_gradient(
    buf: &mut RgbaBuffer,
    sel: Option<&Mask>,
    spec: &GradientSpec,
    p0: Point,
    p1: Point,
    rng: &mut SeededRng,
) {
    let w = buf.width() as i32;
    let h = buf.height() as i32;
    for y in 0..h {
        for x in 0..w {
            if let Some(m) = sel {
                if !m.get(x, y) {
                    continue;
                }
            }
            let mut t = gradient_t(spec.kind, p0, p1, x, y);
            if spec.dither {
                // small seeded ordered jitter to break 8-bit banding
                let j = (rng.next_f32() - 0.5) * (1.0 / 255.0);
                t = (t + j).clamp(0.0, 1.0);
            }
            buf.set(x, y, gradient_color_at(&spec.stops, t));
        }
    }
}

/// Airbrush dab: stochastically spray `intensity`-many points within radius (SPEC §11.1).
pub fn airbrush_dab(
    buf: &mut RgbaBuffer,
    sel: Option<&Mask>,
    center: Point,
    size: u16,
    intensity: u8,
    color: Rgba8,
    rng: &mut SeededRng,
) {
    let radius = (size.max(1) as i32).max(1);
    let count = ((intensity as u32 * radius as u32) / 32).max(1);
    let r2 = (radius * radius) as f32;
    for _ in 0..count {
        let dx = (rng.next_f32() * 2.0 - 1.0) * radius as f32;
        let dy = (rng.next_f32() * 2.0 - 1.0) * radius as f32;
        if dx * dx + dy * dy <= r2 {
            plot(buf, sel, center.x + dx as i32, center.y + dy as i32, color, PaintMode::Over);
        }
    }
}

/// Dodge (lighten, dv>0) / Burn (darken, dv<0) the value channel within a stamp.
pub fn dodge_burn_stamp(
    buf: &mut RgbaBuffer,
    sel: Option<&Mask>,
    center: Point,
    size: u16,
    shape: BrushShape,
    dv: f32,
) {
    let radius = (size.max(1) as i32 - 1) / 2;
    let mut apply = |x: i32, y: i32| {
        if let Some(m) = sel {
            if !m.get(x, y) {
                return;
            }
        }
        let c = buf.get(x, y);
        if c.a != 0 {
            buf.set(x, y, color::hsv_shift(c, 0.0, 0.0, dv));
        }
    };
    match shape {
        BrushShape::Round => raster::disc(center, radius.max(1), &mut apply),
        BrushShape::Square => raster::square(center, radius, &mut apply),
    }
}

/// HSV-shift every selected (or all, if no selection) non-transparent pixel (SPEC §11.4).
pub fn hsv_shift_region(buf: &mut RgbaBuffer, sel: Option<&Mask>, dh: f32, ds: f32, dv: f32) {
    let w = buf.width() as i32;
    let h = buf.height() as i32;
    for y in 0..h {
        for x in 0..w {
            if let Some(m) = sel {
                if !m.get(x, y) {
                    continue;
                }
            }
            let c = buf.get(x, y);
            if c.a != 0 {
                buf.set(x, y, color::hsv_shift(c, dh, ds, dv));
            }
        }
    }
}

/// Apply a per-pixel color transform to the selected (or whole) region.
pub fn map_region(buf: &mut RgbaBuffer, sel: Option<&Mask>, f: impl Fn(Rgba8) -> Rgba8) {
    let w = buf.width() as i32;
    let h = buf.height() as i32;
    for y in 0..h {
        for x in 0..w {
            if let Some(m) = sel {
                if !m.get(x, y) {
                    continue;
                }
            }
            let c = buf.get(x, y);
            if c.a != 0 {
                buf.set(x, y, f(c));
            }
        }
    }
}

/// Fill the selection (or whole layer) with a solid color.
pub fn fill_region(buf: &mut RgbaBuffer, sel: Option<&Mask>, color: Rgba8) {
    let w = buf.width() as i32;
    let h = buf.height() as i32;
    for y in 0..h {
        for x in 0..w {
            plot(buf, sel, x, y, color, PaintMode::Replace);
        }
    }
}

/// Clear (erase) the selection (or whole layer).
pub fn clear_region(buf: &mut RgbaBuffer, sel: Option<&Mask>) {
    if sel.is_none() {
        buf.clear();
        return;
    }
    let w = buf.width() as i32;
    let h = buf.height() as i32;
    for y in 0..h {
        for x in 0..w {
            plot(buf, sel, x, y, Rgba8::TRANSPARENT, PaintMode::Erase);
        }
    }
}

/// Draw a shape (Line/Rectangle/Ellipse), outline or filled (SPEC §28.1).
pub fn draw_shape(
    buf: &mut RgbaBuffer,
    sel: Option<&Mask>,
    kind: ToolKind,
    a: Point,
    b: Point,
    color: Rgba8,
    fill: bool,
    line_width: u16,
    mode: PaintMode,
) {
    let mut f = |x: i32, y: i32| plot(buf, sel, x, y, color, mode);
    match kind {
        ToolKind::Line => raster::line(a, b, &mut f),
        ToolKind::Rectangle => {
            if fill {
                raster::rect_filled(a, b, &mut f)
            } else {
                raster::rect_outline(a, b, line_width.max(1) as i32, &mut f)
            }
        }
        ToolKind::Ellipse => {
            if fill {
                raster::ellipse_filled(a, b, &mut f)
            } else {
                raster::ellipse_outline(a, b, line_width.max(1) as i32, &mut f)
            }
        }
        _ => {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::geom::IRect;

    #[test]
    fn pencil_stamp_sets_pixel() {
        let mut b = RgbaBuffer::new(16, 16);
        stamp(&mut b, None, Point::new(5, 5), 1, BrushShape::Square, Rgba8::WHITE, PaintMode::Replace);
        assert_eq!(b.get(5, 5), Rgba8::WHITE);
    }

    #[test]
    fn flood_fill_fills_region() {
        let mut b = RgbaBuffer::new(8, 8);
        flood_fill(&mut b, None, Point::new(0, 0), Rgba8::WHITE, 0, true, PaintMode::Replace);
        // all-transparent target → fills entire canvas
        for y in 0..8 {
            for x in 0..8 {
                assert_eq!(b.get(x, y), Rgba8::WHITE);
            }
        }
    }

    #[test]
    fn flood_fill_respects_boundary() {
        let mut b = RgbaBuffer::new(8, 8);
        // vertical wall at x=4
        for y in 0..8 {
            b.set(4, y, Rgba8::BLACK);
        }
        flood_fill(&mut b, None, Point::new(0, 0), Rgba8::WHITE, 0, true, PaintMode::Replace);
        assert_eq!(b.get(0, 0), Rgba8::WHITE);
        assert_eq!(b.get(3, 3), Rgba8::WHITE);
        assert_eq!(b.get(5, 3), Rgba8::TRANSPARENT); // other side untouched
        assert_eq!(b.get(4, 3), Rgba8::BLACK); // wall intact
    }

    #[test]
    fn gradient_endpoints_exact() {
        let mut b = RgbaBuffer::new(16, 1);
        let spec = GradientSpec {
            kind: GradientKind::Linear,
            stops: vec![Stop::new(Rgba8::rgb(255, 0, 0), 0.0), Stop::new(Rgba8::rgb(0, 0, 255), 1.0)],
            dither: false,
        };
        let mut rng = SeededRng::new(0);
        apply_gradient(&mut b, None, &spec, Point::new(0, 0), Point::new(15, 0), &mut rng);
        assert_eq!(b.get(0, 0), Rgba8::rgb(255, 0, 0));
        assert_eq!(b.get(15, 0), Rgba8::rgb(0, 0, 255));
    }

    #[test]
    fn gradient_oracle_matches_apply() {
        let mut b = RgbaBuffer::new(32, 32);
        let spec = GradientSpec {
            kind: GradientKind::Radial,
            stops: vec![
                Stop::new(Rgba8::rgb(255, 0, 0), 0.0),
                Stop::new(Rgba8::WHITE, 0.5),
                Stop::new(Rgba8::rgb(0, 0, 255), 1.0),
            ],
            dither: false,
        };
        let (p0, p1) = (Point::new(16, 16), Point::new(16, 0));
        let mut rng = SeededRng::new(0);
        apply_gradient(&mut b, None, &spec, p0, p1, &mut rng);
        for y in 0..32 {
            for x in 0..32 {
                let expected = gradient_eval(spec.kind, &spec.stops, p0, p1, x, y);
                assert_eq!(b.get(x, y), expected);
            }
        }
    }

    #[test]
    fn airbrush_is_reproducible_under_seed() {
        let dab = |seed| {
            let mut b = RgbaBuffer::new(32, 32);
            let mut rng = SeededRng::new(seed);
            for _ in 0..5 {
                airbrush_dab(&mut b, None, Point::new(16, 16), 6, 200, Rgba8::WHITE, &mut rng);
            }
            b.content_hash()
        };
        assert_eq!(dab(7), dab(7));
        assert_ne!(dab(7), dab(8));
    }

    #[test]
    fn fill_region_with_selection() {
        let mut b = RgbaBuffer::new(16, 16);
        let sel = Mask::from_plot(16, 16, |p| raster::rect_filled(Point::new(2, 2), Point::new(5, 5), p));
        fill_region(&mut b, Some(&sel), Rgba8::WHITE);
        assert_eq!(b.get(3, 3), Rgba8::WHITE);
        assert_eq!(b.get(10, 10), Rgba8::TRANSPARENT);
        let _ = IRect::new(0, 0, 1, 1);
    }
}
