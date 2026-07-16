//! Observability probes (SPEC §22) — how the AI "sees" without rendering a full picture:
//! structural ASCII, JSON state, photometric ramps/thumbnails, stats, and closed-form
//! oracles. All are pure reads.

use crate::buffer::{RgbaBuffer, Tile, TILE};
use crate::color::Rgba8;
use crate::document::{Document, Frame};
use crate::geom::{IRect, Point};
use crate::history::Edit;
use crate::selection::Mask;
use crate::tool::{gradient_eval, GradientKind, Stop};
use std::collections::{BTreeMap, HashSet};
use std::sync::Arc;

/// One-glyph-per-pixel structural dump with a color legend (SPEC §22, §3.1).
pub fn ascii(buf: &RgbaBuffer, rect: IRect) -> String {
    let mut legend: BTreeMap<u32, char> = BTreeMap::new();
    let mut next = b'A';
    let mut key = |c: Rgba8| -> char {
        if c.a == 0 {
            return '.';
        }
        let k = ((c.r as u32) << 24) | ((c.g as u32) << 16) | ((c.b as u32) << 8) | c.a as u32;
        if let Some(ch) = legend.get(&k) {
            *ch
        } else {
            let ch = next as char;
            legend.insert(k, ch);
            next = if next >= b'Z' { b'a' } else { next + 1 };
            ch
        }
    };
    let mut body = String::new();
    for y in rect.y..rect.bottom() {
        for x in rect.x..rect.right() {
            body.push(key(buf.get(x, y)));
            body.push(' ');
        }
        body.push('\n');
    }
    let mut out = String::from("legend: . #00000000");
    for (k, ch) in &legend {
        let col = Rgba8::new((k >> 24) as u8, (k >> 16) as u8, (k >> 8) as u8, *k as u8);
        out.push_str(&format!("  {} {}", ch, col.to_hex()));
    }
    out.push('\n');
    out.push_str(&body);
    out
}

/// JSON document state (SPEC §22, §3.6).
pub fn state_json(doc: &Document) -> String {
    let mut s = String::new();
    s.push_str(&format!(
        "{{\"size\":[{},{}],\"active_frame\":{},\"frames\":{},\"memory_bytes\":{},",
        doc.size.w,
        doc.size.h,
        doc.active_frame,
        doc.frames.len(),
        doc.memory_bytes()
    ));
    s.push_str(&format!(
        "\"undo_depth\":{},\"redo_depth\":{},\"can_undo\":{},\"can_redo\":{},",
        doc.history.undo.len(),
        doc.history.redo.len(),
        doc.can_undo(),
        doc.can_redo()
    ));
    s.push_str(&format!("\"active_palette\":{},", doc.active_palette));
    s.push_str("\"palette_names\":[");
    for (i, p) in doc.palettes.iter().enumerate() {
        if i > 0 {
            s.push(',');
        }
        s.push_str(&format!("\"{}\"", p.name.replace('"', "'")));
    }
    s.push_str("],");
    s.push_str("\"palette\":[");
    for (i, c) in doc.palette().colors.iter().enumerate() {
        if i > 0 {
            s.push(',');
        }
        s.push_str(&format!("\"{}\"", c.to_hex()));
    }
    s.push_str("],");
    s.push_str("\"frame_detail\":[");
    for (i, f) in doc.frames.iter().enumerate() {
        if i > 0 {
            s.push(',');
        }
        s.push_str(&format!(
            "{{\"i\":{},\"id\":{},\"duration_us\":{},\"active_layer\":{},\"layers\":[",
            i, f.id, f.duration_us, f.active_layer
        ));
        for (j, l) in f.layers.iter().enumerate() {
            if j > 0 {
                s.push(',');
            }
            s.push_str(&format!(
                "{{\"name\":\"{}\",\"visible\":{},\"locked\":{},\"opacity\":{},\"present_tiles\":{}}}",
                l.name.replace('"', "'"),
                l.visible,
                l.locked,
                l.opacity,
                l.pixels.present_tiles()
            ));
        }
        s.push_str("]}");
    }
    s.push_str(&format!(
        "],\"per_frame_depth\":[{}]}}",
        doc.frames
            .iter()
            .map(|f| doc.history.frame_depth(f.id).to_string())
            .collect::<Vec<_>>()
            .join(",")
    ));
    s
}

/// Sampled RGBA along a line — the readable form of a gradient axis (SPEC §22, §3.2).
pub fn ramp(buf: &RgbaBuffer, p0: Point, p1: Point, samples: usize) -> String {
    let n = samples.max(2);
    let mut out = format!("# ramp ({},{})->({},{}) samples={}\n", p0.x, p0.y, p1.x, p1.y, n);
    for i in 0..n {
        let t = i as f32 / (n - 1) as f32;
        let x = (p0.x as f32 + (p1.x - p0.x) as f32 * t).round() as i32;
        let y = (p0.y as f32 + (p1.y - p0.y) as f32 * t).round() as i32;
        out.push_str(&format!("t={:.2}  {}\n", t, buf.get(x, y).to_hex()));
    }
    out
}

/// Average-pooled hex thumbnail (SPEC §22, §3.3).
pub fn thumb(buf: &RgbaBuffer, tw: u32, th: u32) -> String {
    let (w, h) = (buf.width(), buf.height());
    let mut out = format!("# thumb {}x{} (avg RGBA)\n", tw, th);
    for ty in 0..th {
        for tx in 0..tw {
            let x0 = tx * w / tw;
            let x1 = ((tx + 1) * w / tw).max(x0 + 1);
            let y0 = ty * h / th;
            let y1 = ((ty + 1) * h / th).max(y0 + 1);
            let (mut r, mut g, mut b, mut a, mut n) = (0u32, 0u32, 0u32, 0u32, 0u32);
            for y in y0..y1 {
                for x in x0..x1 {
                    let c = buf.get(x as i32, y as i32);
                    r += c.r as u32;
                    g += c.g as u32;
                    b += c.b as u32;
                    a += c.a as u32;
                    n += 1;
                }
            }
            let n = n.max(1);
            let avg = Rgba8::new((r / n) as u8, (g / n) as u8, (b / n) as u8, (a / n) as u8);
            out.push_str(&avg.to_hex());
            out.push(' ');
        }
        out.push('\n');
    }
    out
}

pub struct Stats {
    pub non_transparent: u64,
    pub bbox: Option<IRect>,
    pub present_tiles: usize,
    pub memory_bytes: usize,
}

/// Content stats over `window` (in buffer coords — the canvas rect for a layer buffer, so the
/// gutter is excluded and `bbox` comes back window-relative, i.e. canvas coords, matching the
/// `pixel` probe). `present_tiles`/`memory_bytes` describe the WHOLE buffer — they are
/// tiling/COW diagnostics of the real storage, not of the window.
pub fn stats(buf: &RgbaBuffer, window: IRect) -> Stats {
    let mut count = 0u64;
    let (mut minx, mut miny, mut maxx, mut maxy) = (i32::MAX, i32::MAX, i32::MIN, i32::MIN);
    for y in window.y..window.bottom() {
        for x in window.x..window.right() {
            if buf.get(x, y).a != 0 {
                count += 1;
                minx = minx.min(x);
                miny = miny.min(y);
                maxx = maxx.max(x);
                maxy = maxy.max(y);
            }
        }
    }
    let bbox = (count > 0).then(|| {
        IRect::new(minx - window.x, miny - window.y, (maxx - minx + 1) as u32, (maxy - miny + 1) as u32)
    });
    Stats {
        non_transparent: count,
        bbox,
        present_tiles: buf.present_tiles(),
        memory_bytes: buf.memory_bytes(),
    }
}

pub fn stats_text(buf: &RgbaBuffer, window: IRect) -> String {
    let s = stats(buf, window);
    let bbox = s
        .bbox
        .map(|r| format!("({},{},{},{})", r.x, r.y, r.w, r.h))
        .unwrap_or_else(|| "none".into());
    format!(
        "# stats non_transparent={} bbox={} present_tiles={} memory_bytes={}\n",
        s.non_transparent, bbox, s.present_tiles, s.memory_bytes
    )
}

const TILE_BYTES: usize = (TILE * TILE * 4) as usize;

/// Engine-accounted memory census (the `mem` probe). All tile figures are deduped by `Arc`
/// pointer, so COW sharing (duplicated frames/layers, undo records referencing live tiles) is
/// measured rather than double-counted. Byte figures count tile payloads only (4096 B each);
/// allocator/`Arc` overhead is what the OS-level measurement adds on top.
pub struct MemReport {
    /// Present tiles across all live layers, with multiplicity (what `Document::memory_bytes`
    /// counts): `doc_tiles × 4096 = Document::memory_bytes()`.
    pub doc_tiles: usize,
    /// Live-document tiles after Arc-pointer dedup — COW sharing wins show as the gap to
    /// `doc_tiles`.
    pub doc_unique_tiles: usize,
    /// Fixed tile-slot-table overhead of every live layer (one pointer per grid slot, present or
    /// not; 3w×3h storage makes this a real per-layer constant).
    pub tile_table_bytes: usize,
    pub layers_total: usize,
    pub undo_records: usize,
    pub redo_records: usize,
    /// Unique tiles reachable *only* from history records (undo + redo) — the memory the history
    /// retains beyond the live document.
    pub history_tiles: usize,
    /// Tile-slot-table bytes held by history frame snapshots (`FrameContent`/`DocStructure`
    /// before+after clones). Unlike tiles these are NOT Arc-shared — every snapshot re-allocates
    /// its layers' tables — so structural edits on long animations retain O(frames²·layers)
    /// table bytes here.
    pub history_table_bytes: usize,
    /// Unique tiles reachable only from session extras (clipboard, paste draft).
    pub session_tiles: usize,
    /// Unique selection-mask bytes (live selection + masks retained by history records).
    pub mask_bytes: usize,
}

impl MemReport {
    pub fn doc_bytes(&self) -> usize {
        self.doc_tiles * TILE_BYTES
    }
    pub fn doc_unique_bytes(&self) -> usize {
        self.doc_unique_tiles * TILE_BYTES
    }
    pub fn history_bytes(&self) -> usize {
        self.history_tiles * TILE_BYTES
    }
    pub fn session_bytes(&self) -> usize {
        self.session_tiles * TILE_BYTES
    }
    pub fn total_unique_tiles(&self) -> usize {
        self.doc_unique_tiles + self.history_tiles + self.session_tiles
    }
    /// Grand engine-accounted total: unique tile payloads + tile tables (live + history-held) +
    /// masks.
    pub fn total_bytes(&self) -> usize {
        self.total_unique_tiles() * TILE_BYTES
            + self.tile_table_bytes
            + self.history_table_bytes
            + self.mask_bytes
    }

    pub fn to_json(&self) -> String {
        format!(
            "{{\"doc_tiles\":{},\"doc_bytes\":{},\"doc_unique_tiles\":{},\"doc_unique_bytes\":{},\
             \"tile_table_bytes\":{},\"layers_total\":{},\
             \"undo_records\":{},\"redo_records\":{},\
             \"history_tiles\":{},\"history_bytes\":{},\"history_table_bytes\":{},\
             \"session_tiles\":{},\"session_bytes\":{},\
             \"mask_bytes\":{},\"total_unique_tiles\":{},\"total_bytes\":{}}}",
            self.doc_tiles,
            self.doc_bytes(),
            self.doc_unique_tiles,
            self.doc_unique_bytes(),
            self.tile_table_bytes,
            self.layers_total,
            self.undo_records,
            self.redo_records,
            self.history_tiles,
            self.history_bytes(),
            self.history_table_bytes,
            self.session_tiles,
            self.session_bytes(),
            self.mask_bytes,
            self.total_unique_tiles(),
            self.total_bytes()
        )
    }
}

/// Walk the live document, the whole undo/redo history, and any session-held buffers (`extras`:
/// clipboard, paste draft), deduping tiles by `Arc` pointer to produce a [`MemReport`].
pub fn mem_report(doc: &Document, extras: &[&RgbaBuffer]) -> MemReport {
    let mut seen: HashSet<*const Tile> = HashSet::new();
    let mut doc_tiles = 0usize;
    let mut tile_table_bytes = 0usize;
    let mut layers_total = 0usize;

    // Walk snapshot frames: dedup their tiles into `seen`, and sum their (never-shared) tile
    // tables into the accumulator.
    let visit_frames = |frames: &[Frame], seen: &mut HashSet<*const Tile>, tables: &mut usize| {
        for f in frames {
            for l in &f.layers {
                *tables += l.pixels.tile_table_bytes();
                l.pixels.visit_tile_arcs(&mut |t| {
                    seen.insert(Arc::as_ptr(t));
                });
            }
        }
    };

    for f in &doc.frames {
        for l in &f.layers {
            layers_total += 1;
            doc_tiles += l.pixels.present_tiles();
            tile_table_bytes += l.pixels.tile_table_bytes();
            l.pixels.visit_tile_arcs(&mut |t| {
                seen.insert(Arc::as_ptr(t));
            });
        }
    }
    let doc_unique_tiles = seen.len();

    let mut masks: HashSet<*const Mask> = HashSet::new();
    let mut mask_bytes = 0usize;
    let mut visit_mask = |m: &Option<Arc<Mask>>, masks: &mut HashSet<*const Mask>| {
        if let Some(m) = m {
            if masks.insert(Arc::as_ptr(m)) {
                mask_bytes += m.memory_bytes();
            }
        }
    };
    visit_mask(&doc.selection, &mut masks);

    let mut history_table_bytes = 0usize;
    for rec in doc.history.undo.iter().chain(doc.history.redo.iter()) {
        visit_mask(&rec.sel_before, &mut masks);
        visit_mask(&rec.sel_after, &mut masks);
        match &rec.edit {
            Edit::Pixels { patch, .. } => patch.visit_tile_arcs(&mut |t| {
                seen.insert(Arc::as_ptr(t));
            }),
            Edit::FrameContent { before, after, .. } => {
                visit_frames(std::slice::from_ref(before.as_ref()), &mut seen, &mut history_table_bytes);
                visit_frames(std::slice::from_ref(after.as_ref()), &mut seen, &mut history_table_bytes);
            }
            Edit::DocStructure { before, after, .. } => {
                visit_frames(before, &mut seen, &mut history_table_bytes);
                visit_frames(after, &mut seen, &mut history_table_bytes);
            }
            Edit::Selection => {}
        }
    }
    let history_tiles = seen.len() - doc_unique_tiles;

    for buf in extras {
        buf.visit_tile_arcs(&mut |t| {
            seen.insert(Arc::as_ptr(t));
        });
    }
    let session_tiles = seen.len() - doc_unique_tiles - history_tiles;

    MemReport {
        doc_tiles,
        doc_unique_tiles,
        tile_table_bytes,
        layers_total,
        undo_records: doc.history.undo.len(),
        redo_records: doc.history.redo.len(),
        history_tiles,
        history_table_bytes,
        session_tiles,
        mask_bytes,
    }
}

pub struct GradientOracle {
    pub ok: bool,
    pub max_delta: u8,
    pub worst: Option<(i32, i32, Rgba8, Rgba8)>,
}

/// Closed-form gradient oracle (SPEC §22, §3.4): compare each pixel to the math.
pub fn gradient_oracle(
    buf: &RgbaBuffer,
    kind: GradientKind,
    stops: &[Stop],
    p0: Point,
    p1: Point,
    smooth: bool,
    tol: u8,
) -> GradientOracle {
    let mut max_delta = 0u8;
    let mut worst = None;
    for y in 0..buf.height() as i32 {
        for x in 0..buf.width() as i32 {
            let expected = gradient_eval(kind, stops, p0, p1, x, y, smooth);
            let actual = buf.get(x, y);
            let d = crate::color::max_channel_delta(expected, actual);
            if d > max_delta {
                max_delta = d;
                worst = Some((x, y, expected, actual));
            }
        }
    }
    GradientOracle { ok: max_delta <= tol, max_delta, worst }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ascii_legend_and_grid() {
        let mut b = RgbaBuffer::new(4, 2);
        b.set(0, 0, Rgba8::rgb(255, 0, 0));
        b.set(1, 0, Rgba8::rgb(255, 0, 0));
        let s = ascii(&b, IRect::new(0, 0, 4, 2));
        assert!(s.contains("legend"));
        assert!(s.contains("A A"));
    }

    #[test]
    fn ascii_window_offsets_into_the_buffer() {
        // A storage-like buffer: content sits at the window origin, not (0,0) — the window must
        // anchor there (the CLI passes `doc.canvas_rect()` for gutter-bearing layer buffers).
        let mut b = RgbaBuffer::new(8, 6);
        b.set(2, 1, Rgba8::rgb(255, 0, 0));
        let s = ascii(&b, IRect::new(2, 1, 3, 2));
        let grid: Vec<&str> = s.lines().skip(1).collect();
        assert_eq!(grid, ["A . . ", ". . . "]);
    }

    #[test]
    fn stats_window_excludes_outside_and_reports_relative_bbox() {
        let mut b = RgbaBuffer::new(10, 10);
        b.set(0, 0, Rgba8::rgb(1, 2, 3)); // outside the window (the "gutter")
        b.set(3, 4, Rgba8::rgb(255, 0, 0)); // inside
        b.set(5, 6, Rgba8::rgb(255, 0, 0)); // inside
        let st = stats(&b, IRect::new(2, 2, 6, 6));
        assert_eq!(st.non_transparent, 2, "content outside the window must not count");
        let bb = st.bbox.expect("bbox");
        assert_eq!((bb.x, bb.y, bb.w, bb.h), (1, 2, 3, 3), "bbox is window-relative");
        let empty = stats(&b, IRect::new(8, 8, 2, 2));
        assert_eq!(empty.non_transparent, 0);
        assert!(empty.bbox.is_none());
    }

    #[test]
    fn state_json_well_formed_ish() {
        let d = Document::new(16, 16);
        let s = state_json(&d);
        assert!(s.starts_with("{\"size\":[16,16]"));
        assert!(s.contains("\"frames\":1"));
    }
}
