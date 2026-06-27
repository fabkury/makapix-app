//! The reference CPU compositor (SPEC §18) — the canonical image. Flattens a frame's
//! visible layers bottom→top with per-layer opacity via alpha-over in sRGB. Any GPU
//! fast-path in the shell is golden-tested against this.

use crate::buffer::RgbaBuffer;
use crate::color::{self, Rgba8};
use crate::document::{Document, Frame};
use crate::geom::Point;

/// Flatten the visible layers of `frame` into a single straight-RGBA buffer.
pub fn composite_frame(frame: &Frame, w: u32, h: u32) -> RgbaBuffer {
    let mut out = RgbaBuffer::new(w, h);
    for layer in &frame.layers {
        if !layer.visible || layer.opacity == 0 {
            continue;
        }
        for y in 0..h as i32 {
            for x in 0..w as i32 {
                let src = layer.pixels.get(x, y);
                if src.a == 0 {
                    continue;
                }
                let dst = out.get(x, y);
                out.set(x, y, color::over_opacity(src, dst, layer.opacity));
            }
        }
    }
    out
}

/// Composite the active frame of a document.
pub fn composite_active(doc: &Document) -> RgbaBuffer {
    composite_frame(doc.active_frame(), doc.size.w as u32, doc.size.h as u32)
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
/// grid, checker background). Used by the shell's canvas and the `render` probe.
pub fn render_display(doc: &Document, frame: &Frame, ov: &Overlays) -> RgbaBuffer {
    let w = doc.size.w as u32;
    let h = doc.size.h as u32;
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
        blit_onion(&mut out, prev, w, h, Rgba8::new(255, 80, 80, 64));
    }
    if let Some(next) = ov.onion_next {
        blit_onion(&mut out, next, w, h, Rgba8::new(80, 80, 255, 64));
    }

    let flat = composite_frame(frame, w, h);
    for y in 0..h as i32 {
        for x in 0..w as i32 {
            let c = flat.get(x, y);
            if c.a != 0 {
                out.blend_over(x, y, c);
            }
        }
    }

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
        draw_reticle(&mut out, cur);
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

fn blit_onion(out: &mut RgbaBuffer, frame: &Frame, w: u32, h: u32, tint: Rgba8) {
    let flat = composite_frame(frame, w, h);
    for y in 0..h as i32 {
        for x in 0..w as i32 {
            if flat.get(x, y).a != 0 {
                out.blend_over(x, y, tint);
            }
        }
    }
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
