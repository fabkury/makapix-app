//! Observability probes (SPEC §22) — how the AI "sees" without rendering a full picture:
//! structural ASCII, JSON state, photometric ramps/thumbnails, stats, and closed-form
//! oracles. All are pure reads.

use crate::buffer::RgbaBuffer;
use crate::color::Rgba8;
use crate::document::Document;
use crate::geom::{IRect, Point};
use crate::tool::{gradient_eval, GradientKind, Stop};
use std::collections::BTreeMap;

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

pub fn stats(buf: &RgbaBuffer) -> Stats {
    let mut count = 0u64;
    for y in 0..buf.height() as i32 {
        for x in 0..buf.width() as i32 {
            if buf.get(x, y).a != 0 {
                count += 1;
            }
        }
    }
    Stats {
        non_transparent: count,
        bbox: buf.opaque_bounds(),
        present_tiles: buf.present_tiles(),
        memory_bytes: buf.memory_bytes(),
    }
}

pub fn stats_text(buf: &RgbaBuffer) -> String {
    let s = stats(buf);
    let bbox = s
        .bbox
        .map(|r| format!("({},{},{},{})", r.x, r.y, r.w, r.h))
        .unwrap_or_else(|| "none".into());
    format!(
        "# stats non_transparent={} bbox={} present_tiles={} memory_bytes={}\n",
        s.non_transparent, bbox, s.present_tiles, s.memory_bytes
    )
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
    fn state_json_well_formed_ish() {
        let d = Document::new(16, 16);
        let s = state_json(&d);
        assert!(s.starts_with("{\"size\":[16,16]"));
        assert!(s.contains("\"frames\":1"));
    }
}
