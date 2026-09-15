//! Pure import logic (SPEC §13): place decoded frames into the document by scaling or
//! cropping to the canvas size, starting at any frame, optionally as a new layer in each
//! existing frame. `makapix-codec` produces the `DecodedFrame`s; this stays dependency-free
//! and oracle-testable.
//!
//! Since ADR 0030 (2026-09-09) an import rasterizes straight into a **storage-sized** layer
//! buffer: whatever part of the placed image hangs off the canvas is parked in the off-canvas
//! gutter (recoverable with the Move tool, like a moved or pasted pixel) instead of being
//! dropped. Only the storage boundary clips. `Stretch` and the anchored `Crop` still fill exactly
//! the canvas; `Native` places the whole source 1:1 — and, combined with an explicit `crop_rect`
//! (ADR 0034, 2026-09-15), places the cropped region 1:1 where the plain crop path would have
//! downscaled it to the canvas.

use crate::buffer::RgbaBuffer;
use crate::color::Rgba8;
use crate::document::{Document, Frame};
use crate::geom::IRect;
use crate::session::Session;

/// A decoded source frame (straight RGBA, row-major). Produced by the codec crate.
#[derive(Clone)]
pub struct DecodedFrame {
    pub rgba: Vec<u8>,
    pub w: u32,
    pub h: u32,
    pub duration_us: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ScaleMode {
    /// Resize the source to exactly fill the canvas (nearest-neighbor).
    Stretch,
    /// Fit preserving aspect ratio, centered, transparent padding.
    Fit,
    /// Take a canvas-sized crop from the source at the anchor.
    Crop,
    /// Place the whole source **1:1** (ADR 0030): centered on the canvas by default, or at
    /// `placement`; a source larger than the canvas overhangs into the gutter, clipped only at the
    /// storage boundary. The shell offers it for sources that fit within the storage area. With a
    /// `crop_rect` (ADR 0034) the region itself is placed 1:1 instead of downscaled to the canvas.
    Native,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Anchor {
    Center,
    TopLeft,
}

#[derive(Clone, Copy, Debug)]
pub struct ImportConfig {
    pub mode: ScaleMode,
    pub anchor: Anchor,
    pub start_frame: usize,
    pub as_layer: bool,
    /// Explicit source crop region (in source pixels) from the interactive crop widget. When set,
    /// that region is placed **1:1, centered** on the canvas — downscaled (aspect-preserved) only
    /// when larger than the canvas, never upscaled — overriding `mode`, with one exception: under
    /// `ScaleMode::Native` (ADR 0034) an oversize region is **not** downscaled; it lands 1:1 with
    /// the overhang parked in the gutter and clipped at the storage boundary, like a `Native`
    /// whole-source import.
    pub crop_rect: Option<IRect>,
    /// Explicit placement (ADR 0019): the top-left of the placed image in canvas pixels, replacing
    /// the centered anchor of the crop-rect, `Fit` and `Native` paths. May be negative or run past
    /// the far edge — the part outside the canvas lands in the off-canvas gutter (ADR 0030); only
    /// the part beyond the whole storage area is dropped. Ignored by `Stretch` (fills the canvas)
    /// and by the anchored `Crop` mode. `None` keeps today's centering.
    pub placement: Option<(i32, i32)>,
}

impl Default for ImportConfig {
    fn default() -> Self {
        ImportConfig {
            mode: ScaleMode::Fit,
            anchor: Anchor::Center,
            start_frame: 0,
            as_layer: true,
            crop_rect: None,
            placement: None,
        }
    }
}

/// Fit `(rw,rh)` inside `(cw,ch)` preserving aspect ratio, **never upscaling**. Integer-exact
/// (cross-multiply, floor division) so imports stay byte-deterministic across platforms.
fn fit_no_upscale(rw: u32, rh: u32, cw: u32, ch: u32) -> (u32, u32) {
    if rw <= cw && rh <= ch {
        return (rw, rh); // fits as-is → placed 1:1
    }
    // Downscale: pick the binding axis without floats. Width-bound when cw/rw <= ch/rh.
    if (rw as u64) * (ch as u64) >= (rh as u64) * (cw as u64) {
        (cw, ((rh as u64 * cw as u64) / rw as u64).max(1) as u32)
    } else {
        (((rw as u64 * ch as u64) / rh as u64).max(1) as u32, ch)
    }
}

fn src_get(rgba: &[u8], w: u32, h: u32, x: i32, y: i32) -> Rgba8 {
    if x < 0 || y < 0 || x as u32 >= w || y as u32 >= h {
        return Rgba8::TRANSPARENT;
    }
    let i = ((y as u32 * w + x as u32) * 4) as usize;
    if i + 3 < rgba.len() {
        Rgba8::new(rgba[i], rgba[i + 1], rgba[i + 2], rgba[i + 3])
    } else {
        Rgba8::TRANSPARENT
    }
}

/// Where a `(dw, dh)` placed image lands on a `(cw, ch)` canvas: the explicit placement when
/// set, else centered (integer division, matching the pre-placement behavior exactly).
fn place_origin(cfg: &ImportConfig, cw: u32, ch: u32, dw: u32, dh: u32) -> (i32, i32) {
    cfg.placement.unwrap_or(((cw as i32 - dw as i32) / 2, (ch as i32 - dh as i32) / 2))
}

/// Set a pixel of the storage-sized output when it lies inside it — a placement may hang off
/// any edge of the canvas (into the gutter) and, past that, off the storage area (dropped).
/// `x, y` are canvas coordinates; `org` is the canvas origin within the buffer.
fn set_clipped(out: &mut RgbaBuffer, org: (i32, i32), x: i32, y: i32, c: Rgba8) {
    let (sx, sy) = (org.0 + x, org.1 + y);
    if sx >= 0 && sy >= 0 && (sx as u32) < out.width() && (sy as u32) < out.height() {
        out.set(sx, sy, c);
    }
}

/// Rasterize one decoded frame into a **canvas-sized** buffer per the config — the no-gutter
/// twin of [`frame_to_storage`] (everything off the canvas is dropped). Kept for oracle tests
/// and tools that want the canvas window alone.
pub fn frame_to_buffer(df: &DecodedFrame, cw: u32, ch: u32, cfg: &ImportConfig) -> RgbaBuffer {
    frame_to_storage(df, cw, ch, (0, 0), cfg)
}

/// Rasterize one decoded frame into a **storage-sized** buffer per the config (ADR 0030): the
/// canvas is `cw`×`ch` with a `gutter` of `(gw, gh)` pixels on every side, so the buffer is
/// `(cw + 2·gw) × (ch + 2·gh)` and the canvas top-left sits at `(gw, gh)`. `Stretch` and the
/// anchored `Crop` fill exactly the canvas; the crop-rect, `Fit` and `Native` paths place an
/// image whose off-canvas part is kept in the gutter and clipped only at the storage boundary.
/// An empty gutter costs nothing: the buffer is tiled and lazily allocated.
pub fn frame_to_storage(df: &DecodedFrame, cw: u32, ch: u32, gutter: (u32, u32), cfg: &ImportConfig) -> RgbaBuffer {
    let (gw, gh) = gutter;
    let mut out = RgbaBuffer::new(cw + 2 * gw, ch + 2 * gh);
    let org = (gw as i32, gh as i32);
    // Explicit interactive crop: place the chosen source region **1:1** — downscaling
    // (aspect-preserved, nearest-neighbor) only when the region is larger than the canvas, and
    // not even then under `Native` (ADR 0034: the region keeps its size, the overhang is parked).
    // Never upscaled; a smaller region lands centered unless `placement` says where.
    if let Some(cr) = cfg.crop_rect {
        let (rw, rh) = (cr.w.max(1), cr.h.max(1));
        let (dw, dh) = if cfg.mode == ScaleMode::Native { (rw, rh) } else { fit_no_upscale(rw, rh, cw, ch) };
        let (ox, oy) = place_origin(cfg, cw, ch, dw, dh);
        for y in 0..dh as i32 {
            for x in 0..dw as i32 {
                let sx = cr.x + (x as u64 * rw as u64 / dw as u64) as i32;
                let sy = cr.y + (y as u64 * rh as u64 / dh as u64) as i32;
                let c = src_get(&df.rgba, df.w, df.h, sx, sy);
                if c.a != 0 {
                    set_clipped(&mut out, org, ox + x, oy + y, c);
                }
            }
        }
        return out;
    }
    match cfg.mode {
        ScaleMode::Stretch => {
            for y in 0..ch as i32 {
                for x in 0..cw as i32 {
                    let sx = (x as u64 * df.w as u64 / cw.max(1) as u64) as i32;
                    let sy = (y as u64 * df.h as u64 / ch.max(1) as u64) as i32;
                    let c = src_get(&df.rgba, df.w, df.h, sx, sy);
                    if c.a != 0 {
                        out.set(org.0 + x, org.1 + y, c);
                    }
                }
            }
        }
        ScaleMode::Fit => {
            let scale = (cw as f32 / df.w as f32).min(ch as f32 / df.h as f32);
            let dw = (df.w as f32 * scale).round() as i32;
            let dh = (df.h as f32 * scale).round() as i32;
            let (ox, oy) = place_origin(cfg, cw, ch, dw.max(0) as u32, dh.max(0) as u32);
            for y in 0..dh {
                for x in 0..dw {
                    let sx = (x as f32 / scale) as i32;
                    let sy = (y as f32 / scale) as i32;
                    let c = src_get(&df.rgba, df.w, df.h, sx, sy);
                    if c.a != 0 {
                        set_clipped(&mut out, org, ox + x, oy + y, c);
                    }
                }
            }
        }
        ScaleMode::Crop => {
            let (ox, oy) = match cfg.anchor {
                Anchor::Center => ((df.w as i32 - cw as i32) / 2, (df.h as i32 - ch as i32) / 2),
                Anchor::TopLeft => (0, 0),
            };
            for y in 0..ch as i32 {
                for x in 0..cw as i32 {
                    let c = src_get(&df.rgba, df.w, df.h, ox + x, oy + y);
                    if c.a != 0 {
                        out.set(org.0 + x, org.1 + y, c);
                    }
                }
            }
        }
        ScaleMode::Native => {
            // The whole source at its own size; centered by the same truncating division the
            // shell's Place page mirrors, so an oversize source overhangs symmetrically.
            let (ox, oy) = place_origin(cfg, cw, ch, df.w, df.h);
            for y in 0..df.h as i32 {
                for x in 0..df.w as i32 {
                    let c = src_get(&df.rgba, df.w, df.h, x, y);
                    if c.a != 0 {
                        set_clipped(&mut out, org, ox + x, oy + y, c);
                    }
                }
            }
        }
    }
    out
}

impl Session {
    /// Import decoded frames into the document (SPEC §13). Structural & undoable.
    ///
    /// Runs through [`Session::edit_doc`] — the shared document-mutation chokepoint — so an import
    /// that would push the unique tile payload past the hard memory budget is rolled back wholesale
    /// and registers a refusal, exactly like `add_frame`/`duplicate_frame`/paste. Before this the
    /// import hand-rolled `record_doc_structure` and so was the one structural op that could drive
    /// the document over budget (and produce a file its own loader then refuses on reload). [audit P-0]
    ///
    /// Returns `true` when the import committed; `false` when the input was empty or the budget
    /// gate rolled the whole import back (a refusal is registered) — so the shell can tell
    /// "nothing happened" apart from success instead of reading a refusal as an import.
    pub fn import_decoded(&mut self, frames: &[DecodedFrame], cfg: ImportConfig) -> bool {
        if frames.is_empty() {
            return false;
        }
        let (cw, ch) = (self.doc.size.w as u32, self.doc.size.h as u32);
        let storage = self.doc.storage();
        let margin = self.doc.margin();
        // Rasterize straight into a storage-sized layer buffer (ADR 0030): the canvas sits at the
        // document origin and the placed image's overhang lands in the gutter around it.
        let gutter = (margin.w as u32, margin.h as u32);

        let refusals_before = self.mem_refusal_state().0;
        self.edit_doc("import", |s| {
            for (i, df) in frames.iter().enumerate() {
                let target = cfg.start_frame + i;
                let buf = frame_to_storage(df, cw, ch, gutter, &cfg);
                let dur = Document::clamp_duration(df.duration_us.max(1));

                if cfg.as_layer && target < s.doc.frames.len() {
                    if s.doc.frames[target].layers.len() < crate::document::MAX_LAYERS {
                        let id = s.doc.layer_ids.alloc();
                        let mut layer =
                            crate::document::Layer::new(id, storage, format!("Import {}", i + 1));
                        layer.pixels = buf;
                        s.doc.frames[target].layers.push(layer);
                    } else {
                        s.refuse_layer_cap("Import");
                    }
                } else {
                    // ensure frames exist up to `target`
                    while s.doc.frames.len() <= target && s.doc.frames.len() < crate::document::MAX_FRAMES {
                        let fid = s.doc.frame_ids.alloc();
                        let lid = s.doc.layer_ids.alloc();
                        let layer = crate::document::Layer::new(lid, storage, "Layer 1");
                        s.doc.frames.push(Frame { id: fid, duration_us: dur, layers: vec![layer], active_layer: 0 });
                    }
                    if target < s.doc.frames.len() {
                        let f = &mut s.doc.frames[target];
                        f.duration_us = dur;
                        let al = f.active_layer;
                        f.layers[al].pixels = buf;
                    }
                }
            }
            s.doc.active_frame = cfg.start_frame.min(s.doc.frames.len() - 1);
        });
        self.mem_refusal_state().0 == refusals_before
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn checker(w: u32, h: u32) -> DecodedFrame {
        let mut rgba = vec![0u8; (w * h * 4) as usize];
        for y in 0..h {
            for x in 0..w {
                let i = ((y * w + x) * 4) as usize;
                let on = (x + y) % 2 == 0;
                rgba[i] = if on { 255 } else { 0 };
                rgba[i + 3] = 255;
            }
        }
        DecodedFrame { rgba, w, h, duration_us: 80_000 }
    }

    /// A `w`×`h` solid red frame.
    fn solid(w: u32, h: u32) -> DecodedFrame {
        let mut rgba = vec![0u8; (w * h * 4) as usize];
        for px in rgba.chunks_mut(4) {
            px[0] = 255;
            px[3] = 255;
        }
        DecodedFrame { rgba, w, h, duration_us: 80_000 }
    }

    fn crop_cfg(w: u32, h: u32, placement: Option<(i32, i32)>) -> ImportConfig {
        ImportConfig { crop_rect: Some(IRect::new(0, 0, w, h)), placement, ..Default::default() }
    }

    fn set_pixels(buf: &RgbaBuffer, w: u32, h: u32) -> Vec<(i32, i32)> {
        let mut v = Vec::new();
        for y in 0..h as i32 {
            for x in 0..w as i32 {
                if buf.get(x, y).a != 0 {
                    v.push((x, y));
                }
            }
        }
        v
    }

    #[test]
    fn placement_none_keeps_centering() {
        let df = solid(2, 2);
        let a = frame_to_buffer(&df, 6, 6, &crop_cfg(2, 2, None));
        let b = frame_to_buffer(&df, 6, 6, &crop_cfg(2, 2, Some((2, 2))));
        assert_eq!(set_pixels(&a, 6, 6), vec![(2, 2), (3, 2), (2, 3), (3, 3)]);
        assert_eq!(set_pixels(&a, 6, 6), set_pixels(&b, 6, 6), "explicit center == default center");
    }

    // Without a gutter the canvas boundary is the storage boundary, so the outside is dropped.
    #[test]
    fn placement_moves_and_clips_at_every_edge() {
        let df = solid(2, 2);
        assert_eq!(set_pixels(&frame_to_buffer(&df, 4, 4, &crop_cfg(2, 2, Some((0, 0)))), 4, 4),
            vec![(0, 0), (1, 0), (0, 1), (1, 1)]);
        // Hanging off the top-left: only the bottom-right source pixel lands.
        assert_eq!(set_pixels(&frame_to_buffer(&df, 4, 4, &crop_cfg(2, 2, Some((-1, -1)))), 4, 4), vec![(0, 0)]);
        // Hanging off the bottom-right.
        assert_eq!(set_pixels(&frame_to_buffer(&df, 4, 4, &crop_cfg(2, 2, Some((3, 3)))), 4, 4), vec![(3, 3)]);
        // Entirely outside: nothing, and no panic.
        assert!(set_pixels(&frame_to_buffer(&df, 4, 4, &crop_cfg(2, 2, Some((9, -9)))), 4, 4).is_empty());
    }

    #[test]
    fn placement_applies_to_fit_letterbox_but_not_stretch() {
        // 4×2 source into 4×4: Fit gives a 4×2 band, centered at y=1 by default, at y=0 when placed.
        let df = solid(4, 2);
        let centered = frame_to_buffer(&df, 4, 4, &ImportConfig { mode: ScaleMode::Fit, ..Default::default() });
        assert_eq!(set_pixels(&centered, 4, 4).iter().map(|p| p.1).min(), Some(1));
        let placed = frame_to_buffer(
            &df, 4, 4, &ImportConfig { mode: ScaleMode::Fit, placement: Some((0, 0)), ..Default::default() });
        assert_eq!(set_pixels(&placed, 4, 4).iter().map(|p| p.1).max(), Some(1));
        assert_eq!(set_pixels(&placed, 4, 4).len(), 8);
        let stretched = frame_to_buffer(
            &df, 4, 4, &ImportConfig { mode: ScaleMode::Stretch, placement: Some((2, 2)), ..Default::default() });
        assert_eq!(set_pixels(&stretched, 4, 4).len(), 16, "Stretch ignores placement");
    }

    /// Storage-space pixels of a frame_to_storage result, as canvas coordinates (gutter → negative).
    fn set_pixels_canvas(buf: &RgbaBuffer, gutter: (u32, u32)) -> Vec<(i32, i32)> {
        let mut v = Vec::new();
        for y in 0..buf.height() as i32 {
            for x in 0..buf.width() as i32 {
                if buf.get(x, y).a != 0 {
                    v.push((x - gutter.0 as i32, y - gutter.1 as i32));
                }
            }
        }
        v
    }

    // ADR 0030: with a gutter, the part of a placement that hangs off the canvas is parked there
    // instead of dropped; only the storage boundary clips.
    #[test]
    fn placement_parks_off_canvas_pixels_in_the_gutter_and_clips_at_storage() {
        let df = solid(2, 2);
        let g = (4, 4); // a 4×4 canvas with a full-canvas gutter → 12×12 storage
        // Hanging off the top-left: every source pixel survives, three of them in the gutter.
        let buf = frame_to_storage(&df, 4, 4, g, &crop_cfg(2, 2, Some((-1, -1))));
        assert_eq!(buf.width(), 12);
        assert_eq!(set_pixels_canvas(&buf, g), vec![(-1, -1), (0, -1), (-1, 0), (0, 0)]);
        // Entirely off the canvas but inside storage: all parked.
        let buf = frame_to_storage(&df, 4, 4, g, &crop_cfg(2, 2, Some((5, -4))));
        assert_eq!(set_pixels_canvas(&buf, g), vec![(5, -4), (6, -4), (5, -3), (6, -3)]);
        // Straddling the storage edge: the beyond-storage part is dropped, no panic.
        let buf = frame_to_storage(&df, 4, 4, g, &crop_cfg(2, 2, Some((7, 7))));
        assert_eq!(set_pixels_canvas(&buf, g), vec![(7, 7)]);
        // Entirely beyond storage: nothing lands.
        assert!(set_pixels_canvas(&frame_to_storage(&df, 4, 4, g, &crop_cfg(2, 2, Some((-9, 0)))), g).is_empty());
    }

    // `Native` places the whole source 1:1; an oversize source overhangs symmetrically (the same
    // truncating centering the Place page mirrors) and the overhang lives in the gutter.
    #[test]
    fn native_places_the_whole_source_1_to_1_with_the_overhang_in_the_gutter() {
        let df = solid(6, 2);
        let g = (4, 4);
        let cfg = ImportConfig { mode: ScaleMode::Native, ..Default::default() };
        let buf = frame_to_storage(&df, 4, 4, g, &cfg);
        let px = set_pixels_canvas(&buf, g);
        assert_eq!(px.len(), 12, "every source pixel lands");
        assert_eq!(px.iter().map(|p| p.0).min(), Some(-1), "(4-6)/2 = -1: one column parked left");
        assert_eq!(px.iter().map(|p| p.0).max(), Some(4), "one column parked right");
        assert_eq!(px.iter().map(|p| p.1).min(), Some(1));
        // Explicit placement moves it; the no-gutter twin drops the overhang.
        let placed = frame_to_storage(&df, 4, 4, g, &ImportConfig { placement: Some((0, 0)), ..cfg });
        assert_eq!(set_pixels_canvas(&placed, g).iter().map(|p| p.0).max(), Some(5));
        assert_eq!(set_pixels(&frame_to_buffer(&df, 4, 4, &cfg), 4, 4).len(), 8);
    }

    // Stretch and the anchored Crop still fill exactly the canvas: never a gutter pixel.
    #[test]
    fn stretch_and_anchored_crop_never_touch_the_gutter() {
        let df = checker(8, 8);
        let g = (4, 4);
        for mode in [ScaleMode::Stretch, ScaleMode::Crop] {
            let buf = frame_to_storage(&df, 4, 4, g, &ImportConfig { mode, placement: Some((-3, -3)), ..Default::default() });
            let px = set_pixels_canvas(&buf, g);
            assert!(!px.is_empty());
            assert!(px.iter().all(|&(x, y)| (0..4).contains(&x) && (0..4).contains(&y)), "{:?}", mode);
        }
    }

    // End to end: an import's overhang is in the document's gutter (canvas-relative negative
    // coordinates through `Session::pixel`), export-invisible, and undo takes it away again.
    #[test]
    fn import_decoded_parks_the_overhang_in_the_document_gutter() {
        let mut s = Session::new(4, 4);
        let ok = s.import_decoded(
            &[solid(6, 2)],
            ImportConfig { mode: ScaleMode::Native, as_layer: true, start_frame: 0, ..Default::default() },
        );
        assert!(ok);
        assert_eq!(s.pixel(0, 1, -1, 1).a, 255, "parked left of the canvas");
        assert_eq!(s.pixel(0, 1, 4, 1).a, 255, "parked right of the canvas");
        assert_eq!(s.pixel(0, 1, 0, 1).a, 255);
        assert_eq!(s.pixel(0, 1, -2, 1).a, 0);
        let composite = s.composite_frame_bytes(0);
        assert_eq!(composite.len(), 4 * 4 * 4, "export stays canvas-cropped");
        s.run_script("Undo()").unwrap();
        assert_eq!(s.pixel(0, 0, -1, 1).a, 0, "undo removes the parked pixels with the layer");
    }

    #[test]
    fn stretch_fills_canvas() {
        let df = checker(4, 4);
        let buf = frame_to_buffer(&df, 16, 16, &ImportConfig { mode: ScaleMode::Stretch, ..Default::default() });
        assert!(buf.opaque_bounds().is_some());
    }

    #[test]
    fn import_as_new_frames() {
        let mut s = Session::new(16, 16);
        let frames = vec![checker(16, 16), checker(8, 8), checker(4, 4)];
        s.import_decoded(&frames, ImportConfig { as_layer: false, start_frame: 0, ..Default::default() });
        assert!(s.doc.frames.len() >= 3);
        assert!(s.doc.undo()); // structural import is undoable
    }

    #[test]
    fn fit_no_upscale_cases() {
        assert_eq!(fit_no_upscale(4, 8, 16, 16), (4, 8)); // fits → 1:1
        assert_eq!(fit_no_upscale(16, 16, 16, 16), (16, 16)); // equal → 1:1
        assert_eq!(fit_no_upscale(32, 16, 16, 16), (16, 8)); // wide, width-bound
        assert_eq!(fit_no_upscale(16, 32, 16, 16), (8, 16)); // tall, height-bound
        assert_eq!(fit_no_upscale(300, 100, 32, 32), (32, 10)); // width-bound, floor
    }

    #[test]
    fn crop_rect_places_region_1to1_centered() {
        // 8x8 source: left half red, right half blue. Crop just the right (blue) 4x8 half.
        let (w, h) = (8u32, 8u32);
        let mut rgba = vec![0u8; (w * h * 4) as usize];
        for y in 0..h {
            for x in 0..w {
                let i = ((y * w + x) * 4) as usize;
                if x < 4 {
                    rgba[i] = 255;
                } else {
                    rgba[i + 2] = 255;
                }
                rgba[i + 3] = 255;
            }
        }
        let df = DecodedFrame { rgba, w, h, duration_us: 100_000 };
        let cfg = ImportConfig { crop_rect: Some(IRect::new(4, 0, 4, 8)), ..Default::default() };
        let buf = frame_to_buffer(&df, 16, 16, &cfg);
        // 4x8 region ≤ 16x16 canvas → placed 1:1 at ox=(16-4)/2=6, oy=(16-8)/2=4.
        assert_eq!(buf.get(0, 0), Rgba8::TRANSPARENT); // padding stays clear
        assert_eq!(buf.get(6, 4), Rgba8::new(0, 0, 255, 255)); // top-left of the region: blue
        assert_eq!(buf.get(9, 11), Rgba8::new(0, 0, 255, 255)); // bottom-right of the region: blue
        assert_eq!(buf.get(15, 15), Rgba8::TRANSPARENT); // padding stays clear
    }

    #[test]
    fn crop_rect_downscales_when_larger_than_canvas() {
        // 32x16 opaque source, cropped whole, into a 16x16 canvas → downscaled to 16x8, centered.
        let (w, h) = (32u32, 16u32);
        let mut rgba = vec![0u8; (w * h * 4) as usize];
        for p in rgba.chunks_exact_mut(4) {
            p[2] = 255;
            p[3] = 255; // opaque blue
        }
        let df = DecodedFrame { rgba, w, h, duration_us: 100_000 };
        let cfg = ImportConfig { crop_rect: Some(IRect::new(0, 0, 32, 16)), ..Default::default() };
        let buf = frame_to_buffer(&df, 16, 16, &cfg);
        // dest 16x8 at oy=(16-8)/2=4: the band [4,12) is filled, rows above/below transparent.
        assert_eq!(buf.get(0, 0), Rgba8::TRANSPARENT);
        assert_eq!(buf.get(0, 4), Rgba8::new(0, 0, 255, 255));
        assert_eq!(buf.get(15, 11), Rgba8::new(0, 0, 255, 255));
        assert_eq!(buf.get(0, 12), Rgba8::TRANSPARENT);
    }

    // ADR 0034: the same oversize crop under `Native` is NOT downscaled — it lands 1:1 with the
    // overhang parked in the gutter, and the storage boundary is the only clip.
    #[test]
    fn crop_rect_under_native_places_the_region_1_to_1_into_the_gutter() {
        let df = solid(20, 8);
        let g = (4, 4); // 4×4 canvas, 12×12 storage
        // Crop the middle 10×2 band: wider than the canvas (4) but within storage (12).
        let cfg = ImportConfig {
            mode: ScaleMode::Native,
            crop_rect: Some(IRect::new(5, 3, 10, 2)),
            ..Default::default()
        };
        let px = set_pixels_canvas(&frame_to_storage(&df, 4, 4, g, &cfg), g);
        assert_eq!(px.len(), 20, "every cropped pixel lands, none downscaled away");
        assert_eq!(px.iter().map(|p| p.0).min(), Some(-3), "(4-10)/2 = -3: three columns parked left");
        assert_eq!(px.iter().map(|p| p.0).max(), Some(6), "three columns parked right");
        assert_eq!(px.iter().map(|p| p.1).min(), Some(1), "(4-2)/2 = 1");
        // The plain crop path downscales the same region to the canvas width.
        let fit = ImportConfig { mode: ScaleMode::Crop, ..cfg };
        let px = set_pixels_canvas(&frame_to_storage(&df, 4, 4, g, &fit), g);
        assert_eq!(px.iter().map(|p| p.0).min(), Some(0));
        assert_eq!(px.iter().map(|p| p.0).max(), Some(3));
        // Wider than storage: placement decides which part survives; the rest is dropped.
        let wide = ImportConfig { crop_rect: Some(IRect::new(0, 0, 20, 8)), placement: Some((-2, -2)), ..cfg };
        let px = set_pixels_canvas(&frame_to_storage(&df, 4, 4, g, &wide), g);
        assert_eq!(px.iter().map(|p| p.0).min(), Some(-2));
        assert_eq!(px.iter().map(|p| p.0).max(), Some(7), "columns past the storage edge are gone");
        assert_eq!(px.len(), 10 * 8, "10 of 20 columns survive; all 8 rows (-2..6) fit in storage");
    }

    #[test]
    fn import_as_layer_into_existing() {
        let mut s = Session::new(16, 16);
        s.add_frame(); // now 2 frames
        let frames = vec![checker(16, 16), checker(16, 16)];
        s.import_decoded(&frames, ImportConfig { as_layer: true, start_frame: 0, ..Default::default() });
        assert_eq!(s.doc.frames[0].layers.len(), 2);
        assert_eq!(s.doc.frames[1].layers.len(), 2);
    }

    // An import that would push the document past the hard memory budget is refused and rolled
    // back wholesale — the same invariant every other structural op holds. Before routing import
    // through `edit_doc` this import committed silently, driving the session over budget and
    // producing a file the loader then refused on reload. [audit P-0]
    #[test]
    fn import_over_budget_is_refused_and_rolled_back() {
        let mut s = Session::new(256, 256);
        // Tiny budget: a single fully-opaque 256×256 frame (64 tiles = 256 KiB) already exceeds it.
        s.set_mem_budgets(64 * 1024, 64 * 1024);
        let before_payload = s.doc.unique_payload_bytes();
        let before_frames = s.doc.frames.len();
        let before_refusals = s.mem_refusal_state().0;

        let big = checker(256, 256); // opaque → materializes all 64 canvas tiles
        s.import_decoded(
            &[big.clone(), big],
            ImportConfig { mode: ScaleMode::Stretch, as_layer: false, start_frame: 0, ..Default::default() },
        );

        assert_eq!(s.doc.frames.len(), before_frames, "refused import adds no frames");
        assert_eq!(s.doc.unique_payload_bytes(), before_payload, "payload unchanged after rollback");
        assert!(s.mem_refusal_state().0 > before_refusals, "the refusal is registered");
        assert!(!s.doc.can_undo(), "a refused import records no undo step");
    }

    // A within-budget import still commits and stays undoable (the rollback path must not catch
    // legitimate imports).
    #[test]
    fn import_within_budget_commits() {
        let mut s = Session::new(64, 64);
        s.set_mem_budgets(64 * 1024 * 1024, 64 * 1024 * 1024); // generous
        s.import_decoded(
            &[checker(64, 64)],
            ImportConfig { mode: ScaleMode::Stretch, as_layer: false, start_frame: 0, ..Default::default() },
        );
        assert!(s.doc.unique_payload_bytes() > 0, "import materialized pixels");
        assert!(s.doc.can_undo(), "a committed import is undoable");
        assert_eq!(s.mem_refusal_state().0, 0, "no refusal for a within-budget import");
    }
}
