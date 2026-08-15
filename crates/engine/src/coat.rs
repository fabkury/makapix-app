//! Single-coat stroke overlay (ADR 0007, SPEC §11). While a Brush/Airbrush/Dodge/Burn stroke is
//! live, its dabs combine into a per-stroke coverage buffer with **max** — never blend — and the
//! document layer stays pristine. The compositor previews the coat at display time (under the
//! layer's blend mode and opacity); `pointer_up` resolves the same coat into the layer once.
//! Repainting inside one stroke therefore never deepens; over-stamping is visually free, which is
//! why the Spacing parameter no longer exists: dabs land at every path pixel.
//!
//! Preview and commit share one integer path — [`StrokeCoat::resolve`] — so what the artist sees
//! mid-stroke is bit-identical to what lands in the layer.

use crate::color::{self, Rgba8};
use crate::geom::{IRect, Point};
use crate::raster;
use crate::selection::Mask;
use crate::tool::{BrushShape, ToolKind};
use crate::util::hash_xy;

/// Mist speck alpha band (pre-color-alpha). Every speck stays translucent, but each pixel draws
/// its own depth from the hash: alpha ranges from `MIST_ALPHA_FLOOR` up to a per-pixel ceiling
/// that scales with the local density envelope — which already carries both Intensity and the
/// distance-to-path falloff, so high-Intensity strokes are denser AND deeper, and rim specks are
/// faint. These two constants are the main feel-tuning knobs for Mist.
const MIST_ALPHA_FLOOR: u32 = 24;
const MIST_ALPHA_CEIL_MAX: u32 = 160;

/// Fraction of the Dots footprint radius that is fully dense before the rim feather begins —
/// at Intensity 255 the core is solid (a user decision) and only the fringe scatters.
const DOTS_CORE: f32 = 0.5;

/// The paint settings a stroke froze at its start (ADR 0007: mid-stroke `Set*` verbs apply from
/// the next stroke). Dispatch during the stroke keys off `tool` here, never off the session's
/// live tool — a journaled mid-stroke `SelectTool` must not reroute or strand the coat.
#[derive(Clone, Debug)]
pub struct PaintCtx {
    pub tool: ToolKind,
    pub color: Rgba8,
    pub size: u16,
    pub shape: BrushShape,
    pub intensity: u8,
    /// Dodge/Burn signed value shift; 0.0 for the paint tools.
    pub dv: f32,
    /// Per-stroke speckle-field seed (Dots/Mist; 0 otherwise). Drawn from the session RNG —
    /// exactly one draw per scatter stroke, on the live and replay paths alike.
    pub seed: u64,
    /// The stroke's frame/layer, pinned by id [audit F-29].
    pub fid: u32,
    pub lid: u32,
}

/// The per-stroke coverage buffer. `cover` is pre-color-alpha coverage over the canvas rect that
/// was current at stroke start (storage coordinates; the gutter can hold no coverage because the
/// paint clip is the canvas window). The selection mask applies at *write* time, so preview and
/// commit can never disagree about clipping.
pub struct StrokeCoat {
    rect: IRect,
    cover: Vec<u8>,
    /// Dirty bounds in storage coordinates (`None` until the first covered pixel).
    bbox: Option<IRect>,
    pub ctx: PaintCtx,
}

impl StrokeCoat {
    pub fn new(canvas_rect: IRect, ctx: PaintCtx) -> Self {
        StrokeCoat {
            rect: canvas_rect,
            cover: vec![0; (canvas_rect.w * canvas_rect.h) as usize],
            bbox: None,
            ctx,
        }
    }

    /// Whether `tool` paints through a coat (the four single-coat families). Pencil and Eraser
    /// keep their continuous direct writes (ADR 0007).
    pub fn tool_uses_coat(tool: ToolKind) -> bool {
        matches!(tool, ToolKind::Brush | ToolKind::Dodge | ToolKind::Burn) || tool.is_airbrush()
    }

    #[inline]
    fn index(&self, x: i32, y: i32) -> Option<usize> {
        if !self.rect.contains(Point::new(x, y)) {
            return None;
        }
        Some(((y - self.rect.y) as u32 * self.rect.w + (x - self.rect.x) as u32) as usize)
    }

    /// Coverage at a storage coordinate (0 outside the coat's rect).
    #[inline]
    pub fn cover_at(&self, x: i32, y: i32) -> u8 {
        self.index(x, y).map_or(0, |i| self.cover[i])
    }

    /// Dirty bounds in storage coordinates.
    pub fn bbox(&self) -> Option<IRect> {
        self.bbox
    }

    /// Max-combine `v` into the coverage at (x, y), honoring the selection mask.
    #[inline]
    fn raise(&mut self, sel: Option<&Mask>, x: i32, y: i32, v: u8) {
        if v == 0 {
            return;
        }
        let Some(i) = self.index(x, y) else { return };
        if let Some(m) = sel {
            if !m.get(x, y) {
                return;
            }
        }
        if self.cover[i] < v {
            self.cover[i] = v;
        }
        self.bbox = Some(match self.bbox {
            None => IRect::new(x, y, 1, 1),
            Some(b) => {
                let x0 = b.x.min(x);
                let y0 = b.y.min(y);
                let x1 = b.right().max(x + 1);
                let y1 = b.bottom().max(y + 1);
                IRect::new(x0, y0, (x1 - x0) as u32, (y1 - y0) as u32)
            }
        });
    }

    /// One dab of the frozen tool at `p` (storage coordinates).
    pub fn dab(&mut self, sel: Option<&Mask>, p: Point) {
        let size = self.ctx.size.max(1);
        match self.ctx.tool {
            // Brush and Dodge/Burn share the stamp footprint convention (radius (size−1)/2,
            // shape honored); their coverage is binary — the swept union.
            ToolKind::Brush | ToolKind::Dodge | ToolKind::Burn => {
                let radius = (size as i32 - 1) / 2;
                match self.ctx.shape {
                    BrushShape::Round => {
                        if size <= 1 {
                            self.raise(sel, p.x, p.y, 255);
                        } else {
                            let mut pts = Vec::new();
                            raster::disc(p, radius.max(1), &mut |x, y| pts.push((x, y)));
                            for (x, y) in pts {
                                self.raise(sel, x, y, 255);
                            }
                        }
                    }
                    BrushShape::Square => {
                        for dy in -radius..=radius {
                            for dx in -radius..=radius {
                                self.raise(sel, p.x + dx, p.y + dy, 255);
                            }
                        }
                    }
                }
            }
            // Airbrush family: radial profiles over radius = size (the airbrush footprint
            // convention). Max over dense dab centers = the profile of distance-to-path.
            ToolKind::AirbrushSoft => self.radial_dab(sel, p, smoothstep),
            ToolKind::AirbrushMist => self.radial_dab(sel, p, smoothstep),
            ToolKind::Airbrush => self.radial_dab(sel, p, |t| {
                // Flat dense core (d ≤ radius·DOTS_CORE), smoothstepping to 0 at the rim.
                // t is 1 at the center, 0 at the rim, so the core is t ≥ 1 − DOTS_CORE.
                let fringe = 1.0 - DOTS_CORE;
                if t >= fringe {
                    1.0
                } else {
                    smoothstep(t / fringe)
                }
            }),
            _ => {}
        }
    }

    /// Radial coverage stamp: profile(t) with t = 1 − d/radius, quantized like `soft_dab`
    /// ((x + 0.5) truncation) and scaled by the frozen Intensity.
    fn radial_dab(&mut self, sel: Option<&Mask>, p: Point, profile: impl Fn(f32) -> f32) {
        let radius = self.ctx.size.max(1) as i32;
        let rf = radius as f32;
        let peak = self.ctx.intensity as f32;
        for dy in -radius..=radius {
            for dx in -radius..=radius {
                let d = ((dx * dx + dy * dy) as f32).sqrt();
                if d >= rf {
                    continue;
                }
                let v = (peak * profile(1.0 - d / rf) + 0.5) as u32;
                self.raise(sel, p.x + dx, p.y + dy, v.min(255) as u8);
            }
        }
    }

    /// Dense dab trail from `a` to `b` (storage coordinates): a dab at every line pixel.
    /// Max-composition makes the over-stamping free — this is why Spacing no longer exists.
    pub fn segment(&mut self, sel: Option<&Mask>, a: Point, b: Point) {
        let mut pts = Vec::new();
        raster::line(a, b, |x, y| pts.push(Point::new(x, y)));
        for p in pts {
            self.dab(sel, p);
        }
    }

    /// Whether the speckle field has a speck at (x, y) for local density `c`. `c == 255` is
    /// exactly solid (plain `hash < c` would miss 1/256 of pixels at full Intensity).
    #[inline]
    fn speck(&self, x: i32, y: i32, c: u8) -> bool {
        c == 255 || (hash_xy(x, y, self.ctx.seed) & 0xFF) < c as u64
    }

    /// THE shared preview/commit path: the layer pixel at (x, y) after this coat applies to
    /// `under`. Identity where the coat has no effect. The compositor calls this per pixel to
    /// preview; `commit_into` calls it to flatten — bit-identical by construction.
    pub fn resolve(&self, x: i32, y: i32, under: Rgba8) -> Rgba8 {
        let c = self.cover_at(x, y);
        if c == 0 {
            return under;
        }
        match self.ctx.tool {
            ToolKind::Dodge | ToolKind::Burn => {
                if under.a == 0 {
                    under
                } else {
                    color::hsv_shift(under, 0.0, 0.0, self.ctx.dv)
                }
            }
            // Dots: coverage is the density envelope; specks land at the color's own alpha.
            ToolKind::Airbrush => {
                if self.speck(x, y, c) {
                    color::over(self.ctx.color, under)
                } else {
                    under
                }
            }
            // Mist: multi-level speckle — the same hash decides both WHETHER a pixel is a speck
            // (low byte vs the density envelope) and HOW DEEP it is (the next byte picks an
            // alpha between the floor and a ceiling scaled by the envelope). Purely geometric
            // and idempotent like everything else in the coat; the grainy varied-opacity look
            // that accumulation used to produce now comes from the field itself.
            ToolKind::AirbrushMist => {
                let h = hash_xy(x, y, self.ctx.seed);
                if c == 255 || (h & 0xFF) < c as u64 {
                    let ceil = MIST_ALPHA_FLOOR + ((MIST_ALPHA_CEIL_MAX - MIST_ALPHA_FLOOR) * c as u32) / 255;
                    let v = ((h >> 8) & 0xFF) as u32;
                    let raw = MIST_ALPHA_FLOOR + ((ceil - MIST_ALPHA_FLOOR) * v) / 255;
                    let a = (raw * self.ctx.color.a as u32 + 127) / 255;
                    if a == 0 {
                        return under;
                    }
                    let src = Rgba8::new(self.ctx.color.r, self.ctx.color.g, self.ctx.color.b, a.min(255) as u8);
                    color::over(src, under)
                } else {
                    under
                }
            }
            // Brush (c = 255 ⇒ alpha = color.a) and Soft (c = the falloff envelope): one coat
            // of the color at coverage × the color's own alpha.
            _ => {
                let a = (c as u32 * self.ctx.color.a as u32 + 127) / 255;
                if a == 0 {
                    return under;
                }
                let src = Rgba8::new(self.ctx.color.r, self.ctx.color.g, self.ctx.color.b, a as u8);
                color::over(src, under)
            }
        }
    }

    /// Flatten the coat into `buf` (the stroke's layer), clipped to `clip` — the intersection of
    /// the coat's frozen rect and the CURRENT canvas rect, so a journaled mid-stroke canvas
    /// resize can't write out of bounds (ADR 0007).
    pub fn commit_into(&self, buf: &mut crate::buffer::RgbaBuffer, clip: IRect) {
        let Some(b) = self.bbox else { return };
        let x0 = b.x.max(clip.x);
        let y0 = b.y.max(clip.y);
        let x1 = b.right().min(clip.right());
        let y1 = b.bottom().min(clip.bottom());
        for y in y0..y1 {
            for x in x0..x1 {
                let under = buf.get(x, y);
                let out = self.resolve(x, y, under);
                if out != under {
                    buf.set(x, y, out);
                }
            }
        }
    }
}

/// Hermite smoothstep of t ∈ [0, 1] — polynomial only, deterministic on every platform.
#[inline]
fn smoothstep(t: f32) -> f32 {
    t * t * (3.0 - 2.0 * t)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ctx(tool: ToolKind) -> PaintCtx {
        PaintCtx {
            tool,
            color: Rgba8::WHITE,
            size: 4,
            shape: BrushShape::Round,
            intensity: 200,
            dv: 0.1,
            seed: 42,
            fid: 0,
            lid: 0,
        }
    }
    fn rect() -> IRect {
        IRect::new(0, 0, 32, 32)
    }

    #[test]
    fn brush_coat_is_flat_and_idempotent() {
        let mut c = StrokeCoat::new(rect(), ctx(ToolKind::Brush));
        c.segment(None, Point::new(4, 8), Point::new(20, 8));
        c.segment(None, Point::new(20, 8), Point::new(4, 8)); // scrub back
        let one = c.resolve(10, 8, Rgba8::TRANSPARENT);
        assert_eq!(one.a, 255, "opaque brush lays an opaque coat");
        // Resolving twice over the first result must not deepen (single coat).
        assert_eq!(c.resolve(10, 8, one), one);
    }

    #[test]
    fn translucent_brush_lays_one_uniform_coat() {
        let mut k = ctx(ToolKind::Brush);
        k.color = Rgba8::new(255, 0, 0, 128);
        let mut c = StrokeCoat::new(rect(), k);
        c.segment(None, Point::new(4, 8), Point::new(20, 8));
        c.segment(None, Point::new(20, 8), Point::new(4, 8)); // self-crossing scrub
        let p = c.resolve(10, 8, Rgba8::TRANSPARENT);
        assert_eq!(p.a, 128, "no overlap darkening within one stroke");
    }

    #[test]
    fn soft_envelope_is_monotone_and_capped_at_intensity() {
        let mut c = StrokeCoat::new(rect(), ctx(ToolKind::AirbrushSoft));
        c.dab(None, Point::new(16, 16));
        assert_eq!(c.cover_at(16, 16), 200, "peak = frozen Intensity");
        let alphas: Vec<u8> = (0..=4).map(|dx| c.cover_at(16 + dx, 16)).collect();
        for w in alphas.windows(2) {
            assert!(w[0] >= w[1], "coverage must not increase outward: {alphas:?}");
        }
        assert_eq!(c.cover_at(16 + 4, 16), 0, "rim is untouched");
    }

    #[test]
    fn dots_is_solid_at_255_and_empty_at_0() {
        let mut k = ctx(ToolKind::Airbrush);
        k.intensity = 255;
        let mut c = StrokeCoat::new(rect(), k);
        c.dab(None, Point::new(16, 16));
        // The flat core (d ≤ r·(1−DOTS_CORE) = 2 for size 4) must be exactly solid.
        for dy in -2i32..=2 {
            for dx in -2i32..=2 {
                if dx * dx + dy * dy > 4 {
                    continue;
                }
                let p = c.resolve(16 + dx, 16 + dy, Rgba8::TRANSPARENT);
                assert_eq!(p.a, 255, "core pixel ({dx},{dy}) must be solid at Intensity 255");
            }
        }
        let mut k0 = ctx(ToolKind::Airbrush);
        k0.intensity = 0;
        let mut c0 = StrokeCoat::new(rect(), k0);
        c0.dab(None, Point::new(16, 16));
        assert!(c0.bbox().is_none(), "Intensity 0 lays nothing");
    }

    #[test]
    fn speckle_field_is_seed_deterministic() {
        let sample = |seed: u64| {
            let mut k = ctx(ToolKind::AirbrushMist);
            k.seed = seed;
            k.intensity = 120;
            let mut c = StrokeCoat::new(rect(), k);
            c.segment(None, Point::new(8, 16), Point::new(24, 16));
            let mut specks = Vec::new();
            for y in 0..32 {
                for x in 0..32 {
                    if c.resolve(x, y, Rgba8::TRANSPARENT).a > 0 {
                        specks.push((x, y));
                    }
                }
            }
            specks
        };
        assert_eq!(sample(7), sample(7), "same seed + path = identical specks");
        assert_ne!(sample(7), sample(8), "different seed = different field");
    }

    #[test]
    fn mist_specks_vary_in_depth_and_fade_outward() {
        // Multi-level speckle: each speck draws its own alpha from the hash (grainy varied
        // opacity WITHIN one stroke), every speck stays translucent, and depth fades with
        // distance from the path (the ceiling rides the density envelope).
        let mut k = ctx(ToolKind::AirbrushMist);
        k.intensity = 255;
        k.size = 8;
        let mut c = StrokeCoat::new(rect(), k);
        c.dab(None, Point::new(16, 16));
        let mut inner_max = 0u8;
        let mut outer_max = 0u8;
        let mut distinct = std::collections::BTreeSet::new();
        for y in 0..32 {
            for x in 0..32 {
                let a = c.resolve(x, y, Rgba8::TRANSPARENT).a;
                assert!(a < 255, "mist specks must be translucent");
                if a == 0 {
                    continue;
                }
                distinct.insert(a);
                let d2 = (x - 16) * (x - 16) + (y - 16) * (y - 16);
                if d2 <= 4 {
                    inner_max = inner_max.max(a);
                } else if d2 >= 36 {
                    outer_max = outer_max.max(a);
                }
            }
        }
        assert!(distinct.len() >= 4, "specks must vary in depth: {distinct:?}");
        assert!(outer_max > 0, "the rim still lands faint specks");
        assert!(
            inner_max > outer_max,
            "depth fades outward: inner max {inner_max} vs outer max {outer_max}"
        );
    }

    #[test]
    fn shift_applies_once_and_skips_transparent() {
        let c = {
            let mut c = StrokeCoat::new(rect(), ctx(ToolKind::Dodge));
            c.dab(None, Point::new(16, 16));
            c
        };
        let gray = Rgba8::rgb(100, 100, 100);
        let once = c.resolve(16, 16, gray);
        assert!(once.r > gray.r, "dodge lightens");
        assert_eq!(
            c.resolve(16, 16, Rgba8::TRANSPARENT),
            Rgba8::TRANSPARENT,
            "transparent pixels stay untouched"
        );
    }

    #[test]
    fn selection_clips_at_write_time() {
        let mut m = Mask::new(32, 32);
        for y in 0..32 {
            for x in 0..16 {
                m.set(x, y, true);
            }
        }
        let mut c = StrokeCoat::new(rect(), ctx(ToolKind::Brush));
        c.segment(Some(&m), Point::new(8, 8), Point::new(24, 8));
        assert!(c.cover_at(10, 8) > 0, "inside the selection");
        assert_eq!(c.cover_at(20, 8), 0, "outside the selection: no coverage ever written");
    }

    #[test]
    fn commit_matches_resolve_bit_for_bit() {
        let mut c = StrokeCoat::new(rect(), ctx(ToolKind::AirbrushSoft));
        c.segment(None, Point::new(8, 16), Point::new(24, 16));
        let mut buf = crate::buffer::RgbaBuffer::new(32, 32);
        buf.fill_all(Rgba8::rgb(40, 40, 40));
        // What preview would show for each pixel...
        let preview: Vec<Rgba8> =
            (0..32 * 32).map(|i| c.resolve(i % 32, i / 32, buf.get(i % 32, i / 32))).collect();
        // ...must equal what commit writes.
        c.commit_into(&mut buf, rect());
        for y in 0..32 {
            for x in 0..32 {
                assert_eq!(buf.get(x, y), preview[(y * 32 + x) as usize], "at ({x},{y})");
            }
        }
    }
}
