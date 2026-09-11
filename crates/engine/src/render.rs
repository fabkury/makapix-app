//! The reference CPU compositor (SPEC §18) — the canonical image. Flattens a frame's
//! visible layers bottom→top with per-layer opacity and blend mode (`color::composite`,
//! integer-exact in sRGB). Any GPU fast-path in the shell is golden-tested against this.

use crate::buffer::{RgbaBuffer, TILE};
use crate::coat::StrokeCoat;
use crate::color::{self, Rgba8};
use crate::document::{Document, Frame};
use crate::geom::{IRect, Point};

/// Run `f(x, y)` over every present (materialized) pixel of `src` **within `rect`** (buffer/storage
/// coordinates), skipping absent (fully-transparent) tiles entirely. Each pixel is visited exactly
/// once, so callers that compute a per-pixel result independent of visit order get identical output
/// to a full row scan — at a fraction of the cost when most of `src` is empty. [audit F-13]
#[inline]
fn for_present_pixels_in(src: &RgbaBuffer, rect: IRect, mut f: impl FnMut(i32, i32)) {
    for ty in 0..src.tiles_y() {
        for tx in 0..src.tiles_x() {
            if !src.tile_present(tx, ty) {
                continue;
            }
            let (tx0, ty0) = ((tx * TILE) as i32, (ty * TILE) as i32);
            // Clip the tile to `rect` so we never read outside the requested window.
            let x0 = tx0.max(rect.x);
            let y0 = ty0.max(rect.y);
            let x1 = (tx0 + TILE as i32).min(rect.right());
            let y1 = (ty0 + TILE as i32).min(rect.bottom());
            for y in y0..y1 {
                for x in x0..x1 {
                    f(x, y);
                }
            }
        }
    }
}

/// Flatten the visible layers of `frame` into a single straight-RGBA buffer covering `src` (a rect
/// in storage coordinates). The output is `src.w × src.h`, indexed from `(0,0)`: a layer pixel at
/// storage `(src.x+lx, src.y+ly)` lands at output `(lx, ly)`. Pass [`Document::canvas_rect`] for the
/// canvas image (display/export/thumbnails) or [`Document::storage_rect`] for the overscan view.
pub fn composite_frame(frame: &Frame, src: IRect) -> RgbaBuffer {
    composite_frame_ov(frame, src, None)
}

/// [`composite_frame`] with a live single-coat stroke previewed at its layer's position in the
/// stack — under that layer's blend mode and opacity (ADR 0007). The coat is matched to `frame`
/// and to its layer **by id**, so a mid-stroke frame/layer reorder or deletion degrades to a
/// plain composite instead of painting the wrong layer [audit F-29].
pub fn composite_frame_ov(frame: &Frame, src: IRect, coat: Option<&StrokeCoat>) -> RgbaBuffer {
    // Resolve the coat's layer index within THIS frame; a foreign frame gets no preview.
    let coat_layer: Option<usize> = coat
        .filter(|c| c.ctx.fid == frame.id)
        .and_then(|c| frame.layer_index_by_id(c.ctx.lid));
    let mut out = RgbaBuffer::new(src.w, src.h);
    for (li, layer) in frame.layers.iter().enumerate() {
        if !layer.visible || layer.opacity == 0 {
            continue;
        }
        let px = &layer.pixels;
        // The coat's dirty bbox (clipped to src), when this is the stroke's layer. Pixels inside
        // it take the dense pass below; the fast tile walk skips them so no pixel composites
        // twice. Outside the bbox the coat has no coverage and the fast path is untouched.
        let bbox = match (coat, coat_layer) {
            (Some(c), Some(cli)) if cli == li => c.bbox().and_then(|b| {
                let x0 = b.x.max(src.x);
                let y0 = b.y.max(src.y);
                let x1 = b.right().min(src.right());
                let y1 = b.bottom().min(src.bottom());
                (x0 < x1 && y0 < y1).then(|| IRect::new(x0, y0, (x1 - x0) as u32, (y1 - y0) as u32))
            }),
            _ => None,
        };
        for_present_pixels_in(px, src, |sx, sy| {
            if let Some(b) = bbox {
                if b.contains(Point::new(sx, sy)) {
                    return; // the dense coat pass owns this pixel
                }
            }
            let s = px.get(sx, sy);
            if s.a == 0 {
                return;
            }
            let (lx, ly) = (sx - src.x, sy - src.y);
            let dst = out.get(lx, ly);
            out.set(lx, ly, color::composite(layer.blend, s, dst, layer.opacity));
        });
        if let (Some(c), Some(b)) = (coat, bbox) {
            // Dense pass over the coat's bounds: absent tiles and transparent pixels included —
            // both would be skipped by the tile walk, yet the coat can cover them.
            for sy in b.y..b.bottom() {
                for sx in b.x..b.right() {
                    let s = c.resolve(sx, sy, px.get(sx, sy));
                    if s.a == 0 {
                        continue;
                    }
                    let (lx, ly) = (sx - src.x, sy - src.y);
                    let dst = out.get(lx, ly);
                    out.set(lx, ly, color::composite(layer.blend, s, dst, layer.opacity));
                }
            }
        }
    }
    out
}

/// A point sampler over a frame's composite: [`sample`](Self::sample) returns the very pixel
/// [`composite_frame_ov`] would put at storage `(sx, sy)` — one `color::composite` per
/// contributing layer in stack order, the live coat resolved on its own layer — without
/// flattening anything. A thumbnail reads a few thousand samples of a frame that may hold
/// hundreds of thousands of pixels, so this is the Frames page's contact-sheet path (ADR 0031);
/// the byte-equality with the full composite is pinned by
/// `sampler_matches_full_composite_on_random_documents`.
pub struct FrameSampler<'a> {
    frame: &'a Frame,
    coat: Option<&'a StrokeCoat>,
    /// The coat's layer index within `frame` (matched by frame AND layer id, as the full path).
    coat_layer: Option<usize>,
    /// The coat's dirty bounds — the only pixels where `resolve` can differ from the layer.
    bbox: Option<IRect>,
}

impl<'a> FrameSampler<'a> {
    pub fn new(frame: &'a Frame, coat: Option<&'a StrokeCoat>) -> Self {
        let coat_layer = coat.filter(|c| c.ctx.fid == frame.id).and_then(|c| frame.layer_index_by_id(c.ctx.lid));
        let bbox = match (coat, coat_layer) {
            (Some(c), Some(_)) => c.bbox(),
            _ => None,
        };
        FrameSampler { frame, coat, coat_layer, bbox }
    }

    /// The composite at storage `(sx, sy)`; transparent outside every layer's buffer.
    pub fn sample(&self, sx: i32, sy: i32) -> Rgba8 {
        let p = Point::new(sx, sy);
        let mut out = Rgba8::TRANSPARENT;
        for (li, layer) in self.frame.layers.iter().enumerate() {
            if !layer.visible || layer.opacity == 0 {
                continue;
            }
            let under = layer.pixels.get(sx, sy);
            let s = match (self.coat, self.coat_layer, self.bbox) {
                (Some(c), Some(cli), Some(b)) if cli == li && b.contains(p) => c.resolve(sx, sy, under),
                _ => under,
            };
            if s.a == 0 {
                continue;
            }
            out = color::composite(layer.blend, s, out, layer.opacity);
        }
        out
    }
}

/// Composite the canvas window of the active frame of a document.
pub fn composite_active(doc: &Document) -> RgbaBuffer {
    composite_frame(doc.active_frame(), doc.canvas_rect())
}

/// Overlay options for display rendering (engine-side; the shell may also draw these).
#[derive(Clone, Default)]
pub struct Overlays<'a> {
    pub onion_prev: Option<&'a Frame>,
    pub onion_next: Option<&'a Frame>,
    pub grid: bool,
    pub checker_bg: bool,
    /// Precision-mode reticle position (off-finger draw-by-button). Drawn last, on top.
    pub cursor: Option<Point>,
    /// The live single-coat stroke, previewed inside the frame composite at its layer's stack
    /// position (never for onion frames). See [`composite_frame_ov`].
    pub coat: Option<&'a StrokeCoat>,
}

/// Render a frame to a display buffer with optional overlays (onion skin, grid, checker
/// background, precision cursor, live coat). Selection marching ants are NOT drawn here —
/// the shell animates them from `mkpx_outline_mask`.
/// Used by the shell's canvas and the `render` probe. `src` (storage
/// coordinates) selects the window: the canvas rect for the normal view, the full storage rect for
/// the overscan view. The output is `src.w × src.h` and everything is drawn output-relative.
pub fn render_display(frame: &Frame, src: IRect, ov: &Overlays) -> RgbaBuffer {
    let w = src.w;
    let h = src.h;
    let mut out = RgbaBuffer::new(w, h);

    if ov.checker_bg {
        for y in 0..h as i32 {
            for x in 0..w as i32 {
                let c = if ((x / 8) + (y / 8)) % 2 == 0 {
                    Rgba8::rgb(200, 200, 200)
                } else {
                    Rgba8::rgb(160, 160, 160)
                };
                out.set(x, y, c);
            }
        }
    }
    if let Some(prev) = ov.onion_prev {
        blit_onion(&mut out, prev, src, Rgba8::new(255, 80, 80, 64));
    }
    if let Some(next) = ov.onion_next {
        blit_onion(&mut out, next, src, Rgba8::new(80, 80, 255, 64));
    }

    let flat = composite_frame_ov(frame, src, ov.coat);
    for_present_pixels_in(&flat, IRect::new(0, 0, w, h), |x, y| {
        let c = flat.get(x, y);
        if c.a != 0 {
            out.blend_over(x, y, c);
        }
    });

    if ov.grid && w <= 64 && h <= 64 {
        for y in 0..h as i32 {
            for x in 0..w as i32 {
                if x % 8 == 0 || y % 8 == 0 {
                    out.blend_over(x, y, Rgba8::new(0, 0, 0, 40));
                }
            }
        }
    }
    if let Some(cur) = ov.cursor {
        // The reticle position arrives in storage coords; draw it output-relative.
        draw_reticle(&mut out, Point::new(cur.x - src.x, cur.y - src.y));
    }
    out
}

/// A crosshair reticle that points at the target pixel without covering it (the target
/// pixel and its immediate ring stay visible — that's the point of precision mode).
fn draw_reticle(out: &mut RgbaBuffer, c: Point) {
    let mut put = |x: i32, y: i32| {
        // alternating black/white for contrast on any background
        let on = (x + y) % 2 == 0;
        out.set(x, y, if on { Rgba8::BLACK } else { Rgba8::WHITE });
    };
    // arms start at distance 2 so the center pixel + 1-ring remain visible
    for d in 2..=4 {
        put(c.x, c.y - d);
        put(c.x, c.y + d);
        put(c.x - d, c.y);
        put(c.x + d, c.y);
    }
    // four corner ticks of a box at distance 2 to frame the target
    for &(dx, dy) in &[(-2, -2), (2, -2), (-2, 2), (2, 2)] {
        put(c.x + dx, c.y + dy);
    }
}

fn blit_onion(out: &mut RgbaBuffer, frame: &Frame, src: IRect, tint: Rgba8) {
    let flat = composite_frame(frame, src);
    for_present_pixels_in(&flat, IRect::new(0, 0, src.w, src.h), |x, y| {
        if flat.get(x, y).a != 0 {
            out.blend_over(x, y, tint);
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::coat::PaintCtx;
    use crate::document::Document;
    use crate::tool::{BrushShape, ToolKind};

    /// THE sampler invariant (ADR 0031): at every storage pixel, `FrameSampler::sample` equals
    /// the full composite — over random sizes (square and not), 1–5 layers with every blend
    /// mode, edge opacities, hidden layers, gutter content, materialized-transparent tiles, and
    /// a live coat of every coat tool (sometimes on a foreign frame, which must not preview).
    #[test]
    fn sampler_matches_full_composite_on_random_documents() {
        let mut rng = crate::util::SeededRng::new(0x5EED_F00D);
        let opacities = [0u8, 1, 7, 128, 254, 255];
        let tools = [
            ToolKind::Brush,
            ToolKind::Airbrush,
            ToolKind::AirbrushMist,
            ToolKind::AirbrushSoft,
            ToolKind::Eraser,
            ToolKind::Dodge,
        ];
        for trial in 0..40u32 {
            let w = 1 + (rng.next_u64() % 48) as u16;
            let h = if trial.is_multiple_of(3) { w } else { 1 + (rng.next_u64() % 48) as u16 };
            let mut d = Document::new(w, h);
            let storage = d.storage();
            let nl = 1 + (rng.next_u64() % 5) as usize;
            for li in 0..nl {
                if li > 0 {
                    let l = d.new_layer(format!("L{}", li));
                    d.active_frame_mut().layers.push(l);
                }
                let layer = &mut d.active_frame_mut().layers[li];
                layer.blend = crate::document::BlendMode::from_u8((rng.next_u64() % 11) as u8);
                layer.opacity = opacities[(rng.next_u64() % opacities.len() as u64) as usize];
                layer.visible = !rng.next_u64().is_multiple_of(5);
                for _ in 0..(1 + rng.next_u64() % 4) {
                    let x = (rng.next_u64() % storage.w as u64) as i32;
                    let y = (rng.next_u64() % storage.h as u64) as i32;
                    let rw = 1 + (rng.next_u64() % 40) as u32;
                    let rh = 1 + (rng.next_u64() % 40) as u32;
                    let c = Rgba8::new(
                        (rng.next_u64() & 255) as u8,
                        (rng.next_u64() & 255) as u8,
                        (rng.next_u64() & 255) as u8,
                        if rng.next_u64().is_multiple_of(4) { 255 } else { (rng.next_u64() & 255) as u8 },
                    );
                    layer.pixels.fill_rect(IRect::new(x, y, rw, rh), c);
                }
                // A materialized transparent pixel keeps its tile present.
                let (tx, ty) = ((rng.next_u64() % storage.w as u64) as i32, (rng.next_u64() % storage.h as u64) as i32);
                layer.pixels.set(tx, ty, Rgba8::rgb(1, 2, 3));
                layer.pixels.set(tx, ty, Rgba8::TRANSPARENT);
            }
            let frame = d.active_frame();
            let li = (rng.next_u64() % nl as u64) as usize;
            let foreign = trial % 7 == 6;
            let tool = tools[(rng.next_u64() % tools.len() as u64) as usize];
            let ctx = PaintCtx {
                tool,
                color: Rgba8::new(
                    (rng.next_u64() & 255) as u8,
                    (rng.next_u64() & 255) as u8,
                    (rng.next_u64() & 255) as u8,
                    1 + (rng.next_u64() % 255) as u8,
                ),
                size: 1 + (rng.next_u64() % 9) as u16,
                shape: if rng.next_u64().is_multiple_of(2) { BrushShape::Round } else { BrushShape::Square },
                intensity: 1 + (rng.next_u64() % 255) as u8,
                aa: rng.next_u64().is_multiple_of(2),
                pattern: None,
                mirror: crate::tool::Mirror::NONE,
                dv: if matches!(tool, ToolKind::Dodge) { 0.3 } else { 0.0 },
                seed: rng.next_u64(),
                fid: if foreign { frame.id + 1000 } else { frame.id },
                lid: frame.layers[li].id,
            };
            let o = d.origin();
            let mut coat = crate::coat::StrokeCoat::new(d.canvas_rect(), ctx);
            let a = Point::new(o.x + (rng.next_u64() % w as u64) as i32, o.y + (rng.next_u64() % h as u64) as i32);
            let b = Point::new(o.x + (rng.next_u64() % w as u64) as i32, o.y + (rng.next_u64() % h as u64) as i32);
            coat.segment(None, a, b);
            let coat_opt = if trial % 5 == 4 { None } else { Some(&coat) };

            let sampler = FrameSampler::new(frame, coat_opt);
            let full_storage = composite_frame_ov(frame, d.storage_rect(), coat_opt);
            for y in 0..storage.h as i32 {
                for x in 0..storage.w as i32 {
                    assert_eq!(full_storage.get(x, y), sampler.sample(x, y), "trial {} storage ({}, {})", trial, x, y);
                }
            }
            let full_canvas = composite_frame_ov(frame, d.canvas_rect(), coat_opt);
            for ly in 0..h as i32 {
                for lx in 0..w as i32 {
                    assert_eq!(
                        full_canvas.get(lx, ly),
                        sampler.sample(o.x + lx, o.y + ly),
                        "trial {} canvas ({}, {})",
                        trial,
                        lx,
                        ly
                    );
                }
            }
        }
    }

    /// A coat over a blend-mode+opacity layer, spanning painted pixels, materialized-transparent
    /// pixels, and wholly absent tiles. THE invariant: previewing the coat composites exactly
    /// like committing it first — which simultaneously proves blend/opacity ordering, the
    /// absent-tile and transparent-pixel gaps, and that no pixel composites twice.
    #[test]
    fn coat_preview_equals_committed_composite() {
        let mut d = Document::new(16, 16);
        let o = d.origin();
        d.active_frame_mut().layers[0].pixels.fill_all(Rgba8::rgb(120, 140, 160));
        let mut top = d.new_layer("top");
        top.blend = crate::document::BlendMode::Multiply;
        top.opacity = 200;
        d.active_frame_mut().layers.push(top);
        d.active_frame_mut().active_layer = 1;
        // Partial content on the stroke layer: opaque patch + a materialized transparent pixel
        // (set then cleared keeps the tile present); the rest of the canvas is absent tiles.
        for dy in 0..4 {
            for dx in 0..4 {
                d.active_frame_mut().layers[1].pixels.set(o.x + dx, o.y + dy, Rgba8::rgb(250, 90, 30));
            }
        }
        d.active_frame_mut().layers[1].pixels.set(o.x + 2, o.y + 2, Rgba8::TRANSPARENT);
        let (fid, lid) = (d.active_frame().id, d.active_frame().layers[1].id);
        let ctx = PaintCtx {
            tool: ToolKind::AirbrushSoft,
            color: Rgba8::new(255, 0, 0, 180),
            size: 5,
            shape: BrushShape::Round,
            intensity: 220,
            aa: false,
            pattern: None,
            mirror: crate::tool::Mirror::NONE,
            dv: 0.0,
            seed: 9,
            fid,
            lid,
        };
        let mut coat = crate::coat::StrokeCoat::new(d.canvas_rect(), ctx);
        coat.segment(None, Point::new(o.x + 1, o.y + 2), Point::new(o.x + 13, o.y + 11));
        let preview = composite_frame_ov(d.active_frame(), d.canvas_rect(), Some(&coat));
        assert_ne!(
            preview.content_hash(),
            composite_frame(d.active_frame(), d.canvas_rect()).content_hash(),
            "the coat must be visible in the preview"
        );
        let mut committed_frame = d.active_frame().clone();
        coat.commit_into(&mut committed_frame.layers[1].pixels, d.canvas_rect());
        let committed = composite_frame(&committed_frame, d.canvas_rect());
        assert_eq!(preview.content_hash(), committed.content_hash(), "preview must equal commit");
    }

    /// The Eraser twin of the invariant above (ADR 0008: the Eraser rides the coat): an erasing
    /// coat over a blend-mode+opacity layer must PREVIEW exactly like committing it — including
    /// full-coverage punch-through (the layer stops contributing, lower layers show) and a
    /// fractional AA-style rim pixel (reduced alpha still composites under blend/opacity).
    #[test]
    fn eraser_coat_preview_equals_committed_composite() {
        let mut d = Document::new(16, 16);
        let o = d.origin();
        d.active_frame_mut().layers[0].pixels.fill_all(Rgba8::rgb(120, 140, 160));
        let mut top = d.new_layer("top");
        top.blend = crate::document::BlendMode::Multiply;
        top.opacity = 200;
        d.active_frame_mut().layers.push(top);
        d.active_frame_mut().active_layer = 1;
        for dy in 0..8 {
            for dx in 0..8 {
                d.active_frame_mut().layers[1].pixels.set(o.x + dx, o.y + dy, Rgba8::new(250, 90, 30, 230));
            }
        }
        let (fid, lid) = (d.active_frame().id, d.active_frame().layers[1].id);
        let ctx = PaintCtx {
            tool: ToolKind::Eraser,
            color: Rgba8::WHITE, // ignored by the erase resolve
            size: 4,
            shape: BrushShape::Round,
            intensity: 255,
            aa: false,
            pattern: None,
            mirror: crate::tool::Mirror::NONE,
            dv: 0.0,
            seed: 0,
            fid,
            lid,
        };
        let mut coat = crate::coat::StrokeCoat::new(d.canvas_rect(), ctx);
        coat.segment(None, Point::new(o.x + 2, o.y + 2), Point::new(o.x + 6, o.y + 6));
        coat.raise_for_test(o.x + 7, o.y + 1, 100); // a fractional AA-style rim pixel
        let preview = composite_frame_ov(d.active_frame(), d.canvas_rect(), Some(&coat));
        assert_ne!(
            preview.content_hash(),
            composite_frame(d.active_frame(), d.canvas_rect()).content_hash(),
            "the erase must be visible in the preview"
        );
        let mut committed_frame = d.active_frame().clone();
        coat.commit_into(&mut committed_frame.layers[1].pixels, d.canvas_rect());
        let committed = composite_frame(&committed_frame, d.canvas_rect());
        assert_eq!(preview.content_hash(), committed.content_hash(), "erase preview must equal commit");
        // Punch-through: where the erase covers fully, only the bottom layer shows (the
        // composite buffer is canvas-local — no gutter origin).
        assert_eq!(preview.get(3, 3), Rgba8::rgb(120, 140, 160), "full erase shows the layer below");
    }

    /// A coat pinned to a different frame id (or a deleted layer id) must degrade to a plain
    /// composite — never paint the wrong frame/layer [F-29].
    #[test]
    fn coat_on_foreign_frame_or_missing_layer_is_ignored() {
        let mut d = Document::new(8, 8);
        let o = d.origin();
        d.active_frame_mut().layers[0].pixels.set(o.x + 3, o.y + 3, Rgba8::WHITE);
        let (fid, lid) = (d.active_frame().id, d.active_frame().layers[0].id);
        let mk = |fid, lid| {
            let ctx = PaintCtx {
                tool: ToolKind::Brush,
                color: Rgba8::rgb(255, 0, 0),
                size: 3,
                shape: BrushShape::Round,
                intensity: 255,
                aa: false,
                pattern: None,
                mirror: crate::tool::Mirror::NONE,
                dv: 0.0,
                seed: 0,
                fid,
                lid,
            };
            let mut c = crate::coat::StrokeCoat::new(d.canvas_rect(), ctx);
            c.dab(None, Point::new(o.x + 3, o.y + 3));
            c
        };
        let plain = composite_frame(d.active_frame(), d.canvas_rect()).content_hash();
        let wrong_frame = mk(fid + 999, lid);
        let wrong_layer = mk(fid, lid + 999);
        let right = mk(fid, lid);
        assert_eq!(
            composite_frame_ov(d.active_frame(), d.canvas_rect(), Some(&wrong_frame)).content_hash(),
            plain
        );
        assert_eq!(
            composite_frame_ov(d.active_frame(), d.canvas_rect(), Some(&wrong_layer)).content_hash(),
            plain
        );
        assert_ne!(
            composite_frame_ov(d.active_frame(), d.canvas_rect(), Some(&right)).content_hash(),
            plain
        );
    }

    #[test]
    fn composite_single_layer_passthrough() {
        let mut d = Document::new(8, 8);
        let o = d.origin();
        d.active_frame_mut().active_layer_mut().pixels.set(o.x + 1, o.y + 1, Rgba8::WHITE);
        let flat = composite_active(&d);
        assert_eq!(flat.get(1, 1), Rgba8::WHITE);
    }

    #[test]
    fn composite_opaque_top_hides_bottom() {
        let mut d = Document::new(8, 8);
        d.active_frame_mut().layers[0].pixels.fill_all(Rgba8::rgb(0, 255, 0));
        let top = d.new_layer("top");
        d.active_frame_mut().layers.push(top);
        d.active_frame_mut().layers[1].pixels.fill_all(Rgba8::rgb(255, 0, 0));
        let flat = composite_active(&d);
        assert_eq!(flat.get(4, 4), Rgba8::rgb(255, 0, 0));
    }

    #[test]
    fn invisible_layer_skipped() {
        let mut d = Document::new(8, 8);
        d.active_frame_mut().layers[0].pixels.fill_all(Rgba8::rgb(0, 255, 0));
        let mut top = d.new_layer("top");
        top.visible = false;
        top.pixels.fill_all(Rgba8::rgb(255, 0, 0));
        d.active_frame_mut().layers.push(top);
        let flat = composite_active(&d);
        assert_eq!(flat.get(4, 4), Rgba8::rgb(0, 255, 0));
    }

    #[test]
    fn composite_multiply_layer_darkens() {
        // The flattened pixel must equal the color-level oracle exactly (opaque backdrop →
        // pure B(cb, cs): mul255(100, 200) = 78 per channel).
        let mut d = Document::new(8, 8);
        d.active_frame_mut().layers[0].pixels.fill_all(Rgba8::rgb(100, 100, 100));
        let mut top = d.new_layer("top");
        top.blend = crate::document::BlendMode::Multiply;
        top.pixels.fill_all(Rgba8::rgb(200, 200, 200));
        d.active_frame_mut().layers.push(top);
        let flat = composite_active(&d);
        assert_eq!(flat.get(4, 4), Rgba8::rgb(78, 78, 78));
        // Where the multiply layer has no backdrop below... both layers are filled here, so
        // instead check the oracle equivalence directly against color::composite.
        assert_eq!(
            flat.get(4, 4),
            color::composite(
                crate::document::BlendMode::Multiply,
                Rgba8::rgb(200, 200, 200),
                Rgba8::rgb(100, 100, 100),
                255
            )
        );
    }
}
