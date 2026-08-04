//! Pure import logic (SPEC §16): place decoded frames into the document by scaling or
//! cropping to the canvas size, starting at any frame, optionally as a new layer in each
//! existing frame. `makapix-codec` produces the `DecodedFrame`s; this stays dependency-free
//! and oracle-testable.

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
    /// when larger than the canvas, never upscaled — overriding `mode`.
    pub crop_rect: Option<IRect>,
}

impl Default for ImportConfig {
    fn default() -> Self {
        ImportConfig {
            mode: ScaleMode::Fit,
            anchor: Anchor::Center,
            start_frame: 0,
            as_layer: true,
            crop_rect: None,
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

/// Rasterize one decoded frame into a canvas-sized buffer per the config.
pub fn frame_to_buffer(df: &DecodedFrame, cw: u32, ch: u32, cfg: &ImportConfig) -> RgbaBuffer {
    let mut out = RgbaBuffer::new(cw, ch);
    // Explicit interactive crop: place the chosen source region **1:1, centered** — downscaling
    // (aspect-preserved, nearest-neighbor) only when the region is larger than the canvas. Never
    // upscaled; a smaller region lands centered with transparent padding.
    if let Some(cr) = cfg.crop_rect {
        let (rw, rh) = (cr.w.max(1), cr.h.max(1));
        let (dw, dh) = fit_no_upscale(rw, rh, cw, ch);
        let ox = (cw as i32 - dw as i32) / 2;
        let oy = (ch as i32 - dh as i32) / 2;
        for y in 0..dh as i32 {
            for x in 0..dw as i32 {
                let sx = cr.x + (x as u64 * rw as u64 / dw as u64) as i32;
                let sy = cr.y + (y as u64 * rh as u64 / dh as u64) as i32;
                let c = src_get(&df.rgba, df.w, df.h, sx, sy);
                if c.a != 0 {
                    out.set(ox + x, oy + y, c);
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
                        out.set(x, y, c);
                    }
                }
            }
        }
        ScaleMode::Fit => {
            let scale = (cw as f32 / df.w as f32).min(ch as f32 / df.h as f32);
            let dw = (df.w as f32 * scale).round() as i32;
            let dh = (df.h as f32 * scale).round() as i32;
            let ox = (cw as i32 - dw) / 2;
            let oy = (ch as i32 - dh) / 2;
            for y in 0..dh {
                for x in 0..dw {
                    let sx = (x as f32 / scale) as i32;
                    let sy = (y as f32 / scale) as i32;
                    let c = src_get(&df.rgba, df.w, df.h, sx, sy);
                    if c.a != 0 {
                        out.set(ox + x, oy + y, c);
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
                        out.set(x, y, c);
                    }
                }
            }
        }
    }
    out
}

impl Session {
    /// Import decoded frames into the document (SPEC §16.1). Structural & undoable.
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
        let origin = self.doc.origin();

        // Place a canvas-sized decoded frame into a storage-sized layer buffer, at the canvas origin.
        let to_storage = |buf: &RgbaBuffer| {
            let mut sbuf = RgbaBuffer::from_size(storage);
            sbuf.blit_over(buf, origin);
            sbuf
        };

        let refusals_before = self.mem_refusal_state().0;
        self.edit_doc("import", |s| {
            for (i, df) in frames.iter().enumerate() {
                let target = cfg.start_frame + i;
                let buf = to_storage(&frame_to_buffer(df, cw, ch, &cfg));
                let dur = Document::clamp_duration(df.duration_us.max(1));

                if cfg.as_layer && target < s.doc.frames.len() {
                    if s.doc.frames[target].layers.len() < crate::document::MAX_LAYERS {
                        let id = s.doc.layer_ids.alloc();
                        let mut layer =
                            crate::document::Layer::new(id, storage, format!("Import {}", i + 1));
                        layer.pixels = buf;
                        s.doc.frames[target].layers.push(layer);
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
