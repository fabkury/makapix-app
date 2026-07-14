//! Tools & operations (SPEC §11, §28.1). Each is a pure mutation of a layer `RgbaBuffer`,
//! optionally clipped to a selection `Mask`. The `Session` (session.rs) drives these from
//! pointer/DSL input and wraps each committed change in one undo record.

use crate::buffer::RgbaBuffer;
use crate::color::{self, Rgba8};
use crate::geom::{IRect, Point};
use crate::raster;
use crate::selection::Mask;
use crate::util::SeededRng;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ToolKind {
    Pencil,
    Brush,
    Airbrush,
    Eraser,
    Bucket,
    Gradient,
    Dodge,
    Burn,
    Move,
    Eyedropper,
    Line,
    Rectangle,
    Ellipse,
    Triangle,
    SelectRect,
    SelectEllipse,
    SelectCircle,
    SelectPoly,
    SelectFree,
    SelectByColor,
    /// Select Layer: turn the active layer's alpha channel into a selection (alpha > cutoff).
    SelectLayer,
    HsvShift,
    /// Brightness/Contrast: like HsvShift, a pointer-inert adjustment tool — the pending
    /// (brightness, contrast) in `ToolSettings::bc` previews live and bakes on Apply.
    BrightnessContrast,
    /// Copy & Paste: hosts the clipboard ops (Copy/Cut/Paste/Clear). Paste shows a movable, semi-
    /// transparent draft that is dragged into place then committed. No drawing of its own.
    CopyPaste,
}

impl ToolKind {
    /// The stamp paint mode for the solid-footprint tools (Pencil/Brush/Eraser); `None` for tools
    /// that don't stamp a footprint (Airbrush sprays, Bucket fills, shapes, selection, …). The one
    /// place the Pencil→Replace / Brush→Over / Eraser→Erase mapping lives. [audit F-20]
    pub fn paint_mode(self) -> Option<PaintMode> {
        match self {
            ToolKind::Pencil => Some(PaintMode::Replace),
            ToolKind::Brush => Some(PaintMode::Over),
            ToolKind::Eraser => Some(PaintMode::Erase),
            _ => None,
        }
    }

    /// Whether a completed stroke with this tool writes pixels and must commit one undo record.
    /// Single source of truth — this was duplicated across two hand-synced lists in `pointer_up`,
    /// so adding a pixel-writing tool meant remembering to edit both. [audit F-20]
    pub fn commits_stroke(self) -> bool {
        matches!(
            self,
            ToolKind::Pencil
                | ToolKind::Brush
                | ToolKind::Eraser
                | ToolKind::Airbrush
                | ToolKind::Bucket
                | ToolKind::Dodge
                | ToolKind::Burn
                | ToolKind::Gradient
                | ToolKind::Line
                | ToolKind::Rectangle
                | ToolKind::Ellipse
                | ToolKind::Triangle
                | ToolKind::Move
        )
    }
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
        // Sanitize a non-finite `t` (NaN/inf) to a safe value, so gradient sorting and sampling can
        // never observe a NaN — a NaN stop used to panic via `partial_cmp(..).unwrap()`. [audit F-1]
        let t = if t.is_finite() { t.clamp(0.0, 1.0) } else { 0.0 };
        Stop { color, t }
    }
}

#[derive(Clone)]
pub struct GradientSpec {
    pub kind: GradientKind,
    pub stops: Vec<Stop>,
    /// Ease each colour transition with the smoothstep curve instead of a linear ramp.
    pub smoothstep: bool,
}
impl Default for GradientSpec {
    fn default() -> Self {
        GradientSpec {
            kind: GradientKind::Linear,
            stops: vec![Stop::new(Rgba8::BLACK, 0.0), Stop::new(Rgba8::WHITE, 1.0)],
            smoothstep: false,
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
    /// Brush/Airbrush stamp spacing along a stroke, as a percent of brush size (e.g. 25 = a stamp
    /// every quarter-diameter). Higher = more separated stamps. 1..=1000.
    pub spacing: u16,
    pub threshold: u8,
    /// Select-Layer alpha cutoff (0..=254): pixels with alpha > this (the opaque/drawn pixels) are
    /// "selected". Default 0 (all non-transparent pixels).
    pub alpha_cutoff: u8,
    pub contiguous: bool,
    /// Bucket "All layers": decide the fill region from the composited image (all visible layers),
    /// while still writing the fill into the active layer only.
    pub fill_all_layers: bool,
    pub gradient: GradientSpec,
    pub hsv: (f32, f32, f32),
    /// HSV tool "Frame" scope: the shift (preview + apply) hits every layer of the active frame,
    /// ignoring the selection, instead of the active layer / selection.
    pub hsv_frame: bool,
    /// Brightness/Contrast pending adjustment: (brightness delta in [-255, 255], contrast factor
    /// around the 128 pivot — 1.0 = no change). Previewed live, baked by ApplyBrightnessContrast.
    pub bc: (i32, f32),
    /// Brightness/Contrast "Frame" scope (same semantics as `hsv_frame`).
    pub bc_frame: bool,
    pub shape_fill: bool,
    pub line_width: u16,
    /// When true, a layer Move refuses to push any opaque pixel off-canvas (non-destructive).
    pub protect_pixels: bool,
    /// When true, a layer Move wraps pixels around the canvas edges (top↔bottom, left↔right)
    /// instead of clipping them off. Mutually exclusive with `protect_pixels` (enforced by the UI).
    pub wrap: bool,
    /// Pencil "pixel perfect": while drawing a 1px Pencil stroke, drop the redundant "corner double"
    /// pixels (the L-shaped elbow at each turn) so the line stays a clean 1px wide. Only meaningful
    /// at `brush_size == 1`; a no-op otherwise.
    pub pixel_perfect: bool,
    /// Overscan view: when on, the display renders the whole storage area (canvas + gutter, the gutter
    /// dimmed) and selection gestures may reach into the gutter. A view/interaction flag driven from
    /// the shell (like `wrap`); it never affects paint tools, export or thumbnails. [SPEC §8]
    pub overscan_view: bool,
    /// Rotate tool: sample free-angle rotations through the cleanEdge edge-aware reconstruction
    /// (`crate::cleanedge`) instead of plain nearest-neighbour. The default rotation mode.
    pub clean_edge: bool,
    /// cleanEdge line width, 0.0..=2.0 (the sampler saturates the effective width to its
    /// internal [0.45, 1.142] identity-preserving band, like the reference shader).
    pub clean_edge_width: f32,
    /// Resize tool: sample upscales through the cleanEdge reconstruction (only applies when
    /// both factors ≥ 1; downscaling is always nearest-neighbour). Independent from the Rotate
    /// tool's `clean_edge`. The default resize mode.
    pub scale_clean_edge: bool,
    /// The Resize tool's cleanEdge line width, 0.0..=2.0 (same semantics as `clean_edge_width`,
    /// independent value).
    pub scale_clean_edge_width: f32,
}
impl Default for ToolSettings {
    fn default() -> Self {
        ToolSettings {
            primary: Rgba8::BLACK,
            secondary: Rgba8::WHITE,
            brush_size: 1,
            brush_shape: BrushShape::Round,
            intensity: 128,
            spacing: 25,
            threshold: 0,
            alpha_cutoff: 0,
            contiguous: true,
            fill_all_layers: false,
            gradient: GradientSpec::default(),
            hsv: (0.0, 0.0, 0.0),
            hsv_frame: false,
            bc: (0, 1.0),
            bc_frame: false,
            shape_fill: true,
            line_width: 1,
            protect_pixels: false,
            wrap: false,
            pixel_perfect: false,
            overscan_view: false,
            clean_edge: true,
            clean_edge_width: 1.0,
            scale_clean_edge: true,
            scale_clean_edge_width: 1.0,
        }
    }
}

/// Write `color` at (x,y) honoring the edit `clip` (the canvas window, in storage coords — pixels
/// outside it are the off-canvas gutter that tools may not draw into), the selection clip, and the
/// paint mode. Storage coordinates throughout.
#[inline]
pub fn plot(buf: &mut RgbaBuffer, sel: Option<&Mask>, clip: IRect, x: i32, y: i32, color: Rgba8, mode: PaintMode) {
    if !clip.contains(Point::new(x, y)) {
        return; // outside the editable window (the gutter) — never draw here
    }
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
    clip: IRect,
    center: Point,
    size: u16,
    shape: BrushShape,
    color: Rgba8,
    mode: PaintMode,
) {
    let radius = (size.max(1) as i32 - 1) / 2;
    let mut f = |x: i32, y: i32| plot(buf, sel, clip, x, y, color, mode);
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
#[allow(clippy::too_many_arguments)]
pub fn stroke_segment(
    buf: &mut RgbaBuffer,
    sel: Option<&Mask>,
    clip: IRect,
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
        stamp(buf, sel, clip, c, size, shape, color, mode);
    }
}

/// Flood fill from `seed` (SPEC §11.2). Returns true if any pixel changed.
/// Flood-fill from `seed`. The fill is always written to `buf` (the active layer). The region to
/// fill is decided by `reference` when `Some` — the composited image, for the "All layers" mode, so
/// connectivity/colour-matching considers every layer — otherwise by `buf` itself (active layer).
#[allow(clippy::too_many_arguments)]
pub fn flood_fill(
    buf: &mut RgbaBuffer,
    reference: Option<&RgbaBuffer>,
    sel: Option<&Mask>,
    clip: IRect,
    seed: Point,
    color: Rgba8,
    threshold: u8,
    contiguous: bool,
    mode: PaintMode,
) {
    let w = buf.width() as i32;
    // Bucket is canvas-only: the flood may neither start nor spread outside `clip` (the gutter).
    if !clip.contains(seed) {
        return;
    }
    // Sample the deciding buffer: the reference (composite) if given, else the layer being filled.
    let read = |x: i32, y: i32, b: &RgbaBuffer| match reference {
        Some(r) => r.get(x, y),
        None => b.get(x, y),
    };
    let target = read(seed.x, seed.y, buf);
    let in_sel = |x: i32, y: i32| sel.map(|m| m.get(x, y)).unwrap_or(true);
    if contiguous {
        let mut visited = vec![false; (w * buf.height() as i32) as usize];
        let mut stack = vec![seed];
        while let Some(p) = stack.pop() {
            if !clip.contains(p) {
                continue;
            }
            let idx = (p.y * w + p.x) as usize;
            if visited[idx] {
                continue;
            }
            visited[idx] = true;
            if !in_sel(p.x, p.y) || color::max_channel_delta(read(p.x, p.y, buf), target) > threshold {
                continue;
            }
            plot(buf, sel, clip, p.x, p.y, color, mode);
            stack.push(Point::new(p.x + 1, p.y));
            stack.push(Point::new(p.x - 1, p.y));
            stack.push(Point::new(p.x, p.y + 1));
            stack.push(Point::new(p.x, p.y - 1));
        }
    } else {
        for y in clip.y..clip.bottom() {
            for x in clip.x..clip.right() {
                if in_sel(x, y) && color::max_channel_delta(read(x, y, buf), target) <= threshold {
                    plot(buf, sel, clip, x, y, color, mode);
                }
            }
        }
    }
}

/// The smoothstep easing curve `3t²-2t³` (zero slope at both ends) — used to ease the interpolation
/// between adjacent stops when the Gradient's "smoothstep" option is on, instead of a linear ramp.
#[inline]
pub fn smoothstep(t: f32) -> f32 {
    let t = t.clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

/// Sample a gradient's color at `t∈[0,1]` over stops **already sorted** ascending by `t`. The hot
/// path: callers that fill many pixels sort once and call this per pixel (no per-pixel alloc). [F-14]
/// When `smooth`, the local fraction between the two bounding stops is eased through `smoothstep`, so
/// each colour transition eases in/out while the stop positions themselves stay put.
pub fn gradient_color_at_sorted(s: &[Stop], t: f32, smooth: bool) -> Rgba8 {
    if s.is_empty() {
        return Rgba8::TRANSPARENT;
    }
    if t <= s[0].t {
        return s[0].color;
    }
    if t >= s[s.len() - 1].t {
        return s[s.len() - 1].color;
    }
    for i in 0..s.len() - 1 {
        if t >= s[i].t && t <= s[i + 1].t {
            let span = (s[i + 1].t - s[i].t).max(1e-6);
            let mut local = (t - s[i].t) / span;
            if smooth {
                local = smoothstep(local);
            }
            return color::lerp_srgb(s[i].color, s[i + 1].color, local);
        }
    }
    s[s.len() - 1].color
}

/// Sample a gradient's color at `t∈[0,1]` over arbitrary-order stops (sorts a copy first). Use the
/// `_sorted` variant in per-pixel loops. The sort is total-order so it never panics on a NaN. [F-1]
pub fn gradient_color_at(stops: &[Stop], t: f32, smooth: bool) -> Rgba8 {
    let mut s: Vec<Stop> = stops.to_vec();
    s.sort_by(|a, b| a.t.total_cmp(&b.t));
    gradient_color_at_sorted(&s, t, smooth)
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
pub fn gradient_eval(kind: GradientKind, stops: &[Stop], p0: Point, p1: Point, x: i32, y: i32, smooth: bool) -> Rgba8 {
    gradient_color_at(stops, gradient_t(kind, p0, p1, x, y), smooth)
}

/// Like `gradient_eval` but assumes `stops` are pre-sorted — for per-pixel fill/preview loops. [F-14]
pub fn gradient_eval_sorted(kind: GradientKind, stops: &[Stop], p0: Point, p1: Point, x: i32, y: i32, smooth: bool) -> Rgba8 {
    gradient_color_at_sorted(stops, gradient_t(kind, p0, p1, x, y), smooth)
}

/// Fill a region with the gradient, clipped to selection and the canvas `clip` (SPEC §11.3).
/// Deterministic per pixel.
pub fn apply_gradient(buf: &mut RgbaBuffer, sel: Option<&Mask>, clip: IRect, spec: &GradientSpec, p0: Point, p1: Point) {
    // Sort the stops ONCE, not once per pixel — `gradient_color_at` used to clone+sort the whole
    // stop vector for every pixel (65 536× on a 256² fill). [audit F-14]
    let mut stops = spec.stops.clone();
    stops.sort_by(|a, b| a.t.total_cmp(&b.t));
    for y in clip.y..clip.bottom() {
        for x in clip.x..clip.right() {
            if let Some(m) = sel {
                if !m.get(x, y) {
                    continue;
                }
            }
            let t = gradient_t(spec.kind, p0, p1, x, y);
            buf.set(x, y, gradient_color_at_sorted(&stops, t, spec.smoothstep));
        }
    }
}

/// Airbrush dab: stochastically spray `intensity`-many points within radius (SPEC §11.1).
#[allow(clippy::too_many_arguments)]
pub fn airbrush_dab(
    buf: &mut RgbaBuffer,
    sel: Option<&Mask>,
    clip: IRect,
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
            plot(buf, sel, clip, center.x + dx as i32, center.y + dy as i32, color, PaintMode::Over);
        }
    }
}

/// Dodge (lighten, dv>0) / Burn (darken, dv<0) the value channel within a stamp.
pub fn dodge_burn_stamp(
    buf: &mut RgbaBuffer,
    sel: Option<&Mask>,
    clip: IRect,
    center: Point,
    size: u16,
    shape: BrushShape,
    dv: f32,
) {
    let radius = (size.max(1) as i32 - 1) / 2;
    let mut apply = |x: i32, y: i32| {
        if !clip.contains(Point::new(x, y)) {
            return;
        }
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

/// Fill the selection (or the whole `clip` window when there's no selection) with a solid color.
pub fn fill_region(buf: &mut RgbaBuffer, sel: Option<&Mask>, clip: IRect, color: Rgba8) {
    for y in clip.y..clip.bottom() {
        for x in clip.x..clip.right() {
            plot(buf, sel, clip, x, y, color, PaintMode::Replace);
        }
    }
}

/// Clear (erase) the selection, or the whole layer (gutter included) when there's no selection.
pub fn clear_region(buf: &mut RgbaBuffer, sel: Option<&Mask>, clip: IRect) {
    if sel.is_none() {
        buf.clear();
        return;
    }
    for y in clip.y..clip.bottom() {
        for x in clip.x..clip.right() {
            plot(buf, sel, clip, x, y, Rgba8::TRANSPARENT, PaintMode::Erase);
        }
    }
}

/// Map a Rectangle/Ellipse ToolKind to the rotated-rasteriser code (None = handled elsewhere:
/// Line never rotates, Triangle has its own rot+tip path).
fn rotated_kind(kind: ToolKind) -> Option<u8> {
    match kind {
        ToolKind::Rectangle => Some(0),
        ToolKind::Ellipse => Some(1),
        _ => None,
    }
}

/// Draw a shape (Line/Rectangle/Ellipse/Triangle), outline or filled (SPEC §28.1), optionally
/// rotated by `rot` radians (Rectangle/Ellipse/Triangle). `tip` ∈ [-1, 1] skews a Triangle's apex
/// horizontally along its top edge (ignored by the other shapes).
#[allow(clippy::too_many_arguments)]
pub fn draw_shape(
    buf: &mut RgbaBuffer,
    sel: Option<&Mask>,
    clip: IRect,
    kind: ToolKind,
    a: Point,
    b: Point,
    rot: f32,
    tip: f32,
    color: Rgba8,
    fill: bool,
    line_width: u16,
    mode: PaintMode,
) {
    let lw = line_width.max(1) as i32;
    let mut f = |x: i32, y: i32| plot(buf, sel, clip, x, y, color, mode);
    // The Triangle carries its own rotation + apex skew through one path.
    if kind == ToolKind::Triangle {
        if fill {
            raster::triangle_filled(a, b, rot, tip, &mut f);
        } else {
            raster::triangle_outline(a, b, rot, tip, lw, &mut f);
        }
        return;
    }
    // A rotated Rectangle/Ellipse goes through the exact inverse-rotation rasteriser.
    if rot.abs() > 1e-4 {
        if let Some(k) = rotated_kind(kind) {
            raster::rotated_shape(a, b, rot, k, fill, lw, &mut f);
            return;
        }
    }
    match kind {
        ToolKind::Line => raster::thick_line(a, b, lw, &mut f),
        ToolKind::Rectangle => {
            if fill {
                raster::rect_filled(a, b, &mut f)
            } else {
                raster::rect_outline(a, b, lw, &mut f)
            }
        }
        ToolKind::Ellipse => {
            if fill {
                raster::ellipse_filled(a, b, &mut f)
            } else {
                raster::ellipse_outline(a, b, lw, &mut f)
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
        stamp(&mut b, None, IRect::new(0, 0, 16, 16), Point::new(5, 5), 1, BrushShape::Square, Rgba8::WHITE, PaintMode::Replace);
        assert_eq!(b.get(5, 5), Rgba8::WHITE);
    }

    #[test]
    fn flood_fill_fills_region() {
        let mut b = RgbaBuffer::new(8, 8);
        flood_fill(&mut b, None, None, IRect::new(0, 0, 8, 8), Point::new(0, 0), Rgba8::WHITE, 0, true, PaintMode::Replace);
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
        flood_fill(&mut b, None, None, IRect::new(0, 0, 8, 8), Point::new(0, 0), Rgba8::WHITE, 0, true, PaintMode::Replace);
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
            smoothstep: false,
        };
        apply_gradient(&mut b, None, IRect::new(0, 0, 16, 1), &spec, Point::new(0, 0), Point::new(15, 0));
        assert_eq!(b.get(0, 0), Rgba8::rgb(255, 0, 0));
        assert_eq!(b.get(15, 0), Rgba8::rgb(0, 0, 255));
    }

    #[test]
    fn smoothstep_eases_the_ramp_but_keeps_endpoints() {
        let stops = vec![Stop::new(Rgba8::BLACK, 0.0), Stop::new(Rgba8::WHITE, 1.0)];
        // Endpoints and the midpoint are unchanged (smoothstep(0)=0, (.5)=.5, (1)=1)…
        assert_eq!(gradient_color_at(&stops, 0.0, true), Rgba8::BLACK);
        assert_eq!(gradient_color_at(&stops, 1.0, true), Rgba8::WHITE);
        assert_eq!(gradient_color_at(&stops, 0.5, true), gradient_color_at(&stops, 0.5, false));
        // …but a quarter of the way along, smoothstep is darker than the linear ramp (eased-in).
        let lin = gradient_color_at(&stops, 0.25, false);
        let smooth = gradient_color_at(&stops, 0.25, true);
        assert!(smooth.r < lin.r, "smoothstep should sit below the linear ramp at t=0.25");
        assert_eq!(smoothstep(0.25), 0.25 * 0.25 * (3.0 - 0.5));
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
            smoothstep: false,
        };
        let (p0, p1) = (Point::new(16, 16), Point::new(16, 0));
        apply_gradient(&mut b, None, IRect::new(0, 0, 32, 32), &spec, p0, p1);
        for y in 0..32 {
            for x in 0..32 {
                let expected = gradient_eval(spec.kind, &spec.stops, p0, p1, x, y, spec.smoothstep);
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
                airbrush_dab(&mut b, None, IRect::new(0, 0, 32, 32), Point::new(16, 16), 6, 200, Rgba8::WHITE, &mut rng);
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
        fill_region(&mut b, Some(&sel), IRect::new(0, 0, 16, 16), Rgba8::WHITE);
        assert_eq!(b.get(3, 3), Rgba8::WHITE);
        assert_eq!(b.get(10, 10), Rgba8::TRANSPARENT);
        let _ = IRect::new(0, 0, 1, 1);
    }
}
