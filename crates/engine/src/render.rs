//! The reference CPU compositor (SPEC §18) — the canonical image. Flattens a frame's
//! visible layers bottom→top with per-layer opacity via alpha-over in sRGB. Any GPU
//! fast-path in the shell is golden-tested against this.

use crate::buffer::{RgbaBuffer, TILE};
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
    let mut out = RgbaBuffer::new(src.w, src.h);
    for layer in &frame.layers {
        if !layer.visible || layer.opacity == 0 {
            continue;
        }
        let px = &layer.pixels;
        for_present_pixels_in(px, src, |sx, sy| {
            let s = px.get(sx, sy);
            if s.a == 0 {
                return;
            }
            let (lx, ly) = (sx - src.x, sy - src.y);
            let dst = out.get(lx, ly);
            out.set(lx, ly, color::over_opacity(s, dst, layer.opacity));
        });
    }
    out
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
}

/// Render a frame to a display buffer with optional overlays (onion skin, selection ants,
/// grid, checker background). Used by the shell's canvas and the `render` probe. `src` (storage
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

    let flat = composite_frame(frame, src);
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
    use crate::document::Document;

    #[test]
    fn composite_single_layer_passthrough() {
        let mut d = Document::new(8, 8);
        d.active_frame_mut().active_layer_mut().pixels.set(1, 1, Rgba8::WHITE);
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
}
