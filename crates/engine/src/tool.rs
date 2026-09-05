//! Tools & operations (SPEC §11, §28.1). Each is a pure mutation of a layer `RgbaBuffer`,
//! optionally clipped to a selection `Mask`. The `Session` (session.rs) drives these from
//! pointer/DSL input and wraps each committed change in one undo record.

use crate::buffer::RgbaBuffer;
use crate::color::{self, Rgba8};
use crate::geom::{IRect, Point};
use crate::raster;
use crate::selection::Mask;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ToolKind {
    Pencil,
    Brush,
    Airbrush,
    /// Airbrush in Soft mode: a deterministic radial stamp, peak alpha at the center
    /// smoothstepping to 0 at the rim. One shell tile groups the Airbrush family (ADR 0006).
    AirbrushSoft,
    /// Airbrush in Mist mode: a center-weighted scatter of faint translucent specks.
    AirbrushMist,
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
    /// Levels: the third pointer-inert adjustment tool — the pending (low, gamma‰, high) in
    /// `ToolSettings::levels` previews live and bakes on Apply (GIMP Colors > Levels, input side).
    Levels,
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
                | ToolKind::AirbrushSoft
                | ToolKind::AirbrushMist
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

    /// The Airbrush family — one shell tool tile, three ways of laying paint (Dots = plain
    /// `Airbrush` for journal back-compat, Soft, Mist). All three share the single-coat stroke
    /// paths (coat lifecycle, precision dab, stroke commit); only the dab differs. [ADR 0006]
    pub fn is_airbrush(self) -> bool {
        matches!(self, ToolKind::Airbrush | ToolKind::AirbrushSoft | ToolKind::AirbrushMist)
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

// ---- patterns (ADR 0025) ----

/// The largest pattern side the engine accepts (`SetPattern(w,h,hex)` rejects anything wider or
/// taller). The v1 catalog stops at 8×8; 12×12 and 16×16 tiles are already valid on the wire, and
/// raising this constant (with `PATTERN_BYTES`) is the whole change for larger ones — the hex
/// encoding is one big-endian integer of `w*h` bits, so no journal format changes with the cap.
pub const PATTERN_MAX_SIDE: u8 = 16;
/// Bytes of bit storage a `Pattern` carries: enough for a `PATTERN_MAX_SIDE`² tile.
pub const PATTERN_BYTES: usize = (PATTERN_MAX_SIDE as usize * PATTERN_MAX_SIDE as usize).div_ceil(8);

/// A repeating bitmask that gates painting (ADR 0025): where the bit is ON the tool paints as
/// usual, where it is OFF the pixel is left untouched — never a second color, never a transparent
/// write. Bit `y*w + x` (row-major, LSB first) is the cell at (x, y); `on()` tiles it over the
/// **canvas** grid, so overlapping strokes always mesh. Plain data: `Copy`, no allocation, and
/// compared by value (a tile is its bits, whatever a catalog calls it).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Pattern {
    w: u8,
    h: u8,
    bits: [u8; PATTERN_BYTES],
}

impl Pattern {
    /// Build from raw bits (`bits[i/8] >> (i%8)` is cell `i = y*w + x`). `None` when a side is
    /// outside `1..=PATTERN_MAX_SIDE` or any bit at or beyond `w*h` is set.
    pub fn new(w: u8, h: u8, bits: [u8; PATTERN_BYTES]) -> Option<Pattern> {
        if !(1..=PATTERN_MAX_SIDE).contains(&w) || !(1..=PATTERN_MAX_SIDE).contains(&h) {
            return None;
        }
        let n = w as usize * h as usize;
        for i in n..PATTERN_BYTES * 8 {
            if bits[i / 8] >> (i % 8) & 1 != 0 {
                return None;
            }
        }
        Some(Pattern { w, h, bits })
    }

    /// Parse the DSL form: `hex` is one big-endian hexadecimal integer whose bit `y*w + x` is cell
    /// (x, y) — leading zeros optional, no `0x`. Rejects bad sides, non-hex digits, an empty or
    /// over-long string, and set bits beyond `w*h` (so a journal line can never smuggle a tile
    /// that `on()` would silently truncate).
    pub fn parse(w: u8, h: u8, hex: &str) -> Result<Pattern, String> {
        if !(1..=PATTERN_MAX_SIDE).contains(&w) || !(1..=PATTERN_MAX_SIDE).contains(&h) {
            return Err(format!("pattern side out of range (1..={})", PATTERN_MAX_SIDE));
        }
        let hex = hex.trim();
        if hex.is_empty() || hex.len() > PATTERN_BYTES * 2 {
            return Err("pattern bits: expected 1..=64 hex digits".to_string());
        }
        let mut bits = [0u8; PATTERN_BYTES];
        // Digit k from the right holds bits 4k..4k+3.
        for (k, c) in hex.bytes().rev().enumerate() {
            let d = (c as char).to_digit(16).ok_or_else(|| format!("pattern bits: bad hex digit '{}'", c as char))?;
            bits[k / 2] |= (d as u8) << ((k % 2) * 4);
        }
        Pattern::new(w, h, bits).ok_or_else(|| "pattern bits set beyond w*h".to_string())
    }

    /// Build from ASCII rows (`#` = ON, anything else = OFF); rows must be equal length. The
    /// readable form for tests and catalogs.
    pub fn from_rows(rows: &[&str]) -> Option<Pattern> {
        let h = rows.len();
        let w = rows.first()?.len();
        if h == 0 || w == 0 || h > PATTERN_MAX_SIDE as usize || w > PATTERN_MAX_SIDE as usize {
            return None;
        }
        let mut bits = [0u8; PATTERN_BYTES];
        for (y, row) in rows.iter().enumerate() {
            if row.len() != w {
                return None;
            }
            for (x, c) in row.bytes().enumerate() {
                if c == b'#' {
                    let i = y * w + x;
                    bits[i / 8] |= 1 << (i % 8);
                }
            }
        }
        Pattern::new(w as u8, h as u8, bits)
    }

    pub fn width(&self) -> u8 {
        self.w
    }
    pub fn height(&self) -> u8 {
        self.h
    }

    /// The cell at canvas coordinate (x, y), tiled — negative coordinates wrap like positive ones.
    #[inline]
    pub fn on(&self, x: i32, y: i32) -> bool {
        let cx = x.rem_euclid(self.w as i32) as usize;
        let cy = y.rem_euclid(self.h as i32) as usize;
        let i = cy * self.w as usize + cx;
        self.bits[i / 8] >> (i % 8) & 1 != 0
    }

    /// True when every cell is ON — a gate that admits everything (the catalog never lists one).
    pub fn is_all_on(&self) -> bool {
        (0..self.w as i32).all(|x| (0..self.h as i32).all(|y| self.on(x, y)))
    }

    /// The bits as the DSL hex integer, fixed width (`ceil(w*h/4)` digits, lowercase).
    pub fn hex(&self) -> String {
        let digits = (self.w as usize * self.h as usize).div_ceil(4);
        (0..digits)
            .rev()
            .map(|k| {
                let d = self.bits[k / 2] >> ((k % 2) * 4) & 0xF;
                char::from_digit(d as u32, 16).unwrap_or('0')
            })
            .collect()
    }

    /// The `SetPattern(w,h,hex)` line that reproduces this tile.
    pub fn to_dsl(&self) -> String {
        format!("SetPattern({},{},{})", self.w, self.h, self.hex())
    }
}

/// A pattern in force for one write path, with the canvas origin it is anchored to (storage
/// coordinates: the overscan gutter offsets the canvas by `origin`, and the gate must tile over
/// the artwork, not the gutter). Frozen into a coat's `PaintCtx` at stroke start like every
/// other paint setting (ADR 0007); read at tap time by the Pencil and the Bucket.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PatternGate {
    pub pattern: Pattern,
    pub origin: Point,
}

impl PatternGate {
    /// Whether the pattern admits a write at storage coordinate (x, y).
    #[inline]
    pub fn admits(&self, x: i32, y: i32) -> bool {
        self.pattern.on(x - self.origin.x, y - self.origin.y)
    }
}

/// Whether an optional gate admits (x, y) — `None` admits everything.
#[inline]
fn gate_admits(gate: Option<PatternGate>, x: i32, y: i32) -> bool {
    gate.map(|g| g.admits(x, y)).unwrap_or(true)
}

// ---- symmetry (ADR 0026) ----

/// Mirror-drawing mode (ADR 0026). `H` mirrors left ↔ right (its axis is a *vertical* line),
/// `V` mirrors top ↔ bottom (a *horizontal* axis line), `Both` is the two together and yields
/// four images of every write (the fourth is the point reflection).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum SymMode {
    #[default]
    Off,
    H,
    V,
    Both,
}

impl SymMode {
    /// The DSL token (`SetSymmetry(<mode>, ax, ay)`).
    pub fn token(self) -> &'static str {
        match self {
            SymMode::Off => "off",
            SymMode::H => "h",
            SymMode::V => "v",
            SymMode::Both => "both",
        }
    }
    pub fn parse(s: &str) -> Option<SymMode> {
        let s = s.trim();
        if s.eq_ignore_ascii_case("off") {
            Some(SymMode::Off)
        } else if s.eq_ignore_ascii_case("h") {
            Some(SymMode::H)
        } else if s.eq_ignore_ascii_case("v") {
            Some(SymMode::V)
        } else if s.eq_ignore_ascii_case("both") {
            Some(SymMode::Both)
        } else {
            None
        }
    }
    pub fn mirrors_x(self) -> bool {
        matches!(self, SymMode::H | SymMode::Both)
    }
    pub fn mirrors_y(self) -> bool {
        matches!(self, SymMode::V | SymMode::Both)
    }
}

/// The symmetry setting (ADR 0026): a session setting like AA and the pattern — journaled,
/// never saved in `.mkpx`. Each axis is an integer `A` in **half-pixel canvas units** with the
/// reflection `x' = A − x`: `A` even mirrors through pixel column `A/2`, `A` odd mirrors between
/// two columns. `None` = centered (`A = w − 1`, exact for odd and even canvases) and follows
/// every canvas resize; an explicit value is clamped to `0 … 2(w − 1)` when resolved.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub struct Symmetry {
    pub mode: SymMode,
    pub ax: Option<i32>,
    pub ay: Option<i32>,
}

impl Symmetry {
    pub const OFF: Symmetry = Symmetry { mode: SymMode::Off, ax: None, ay: None };

    /// Resolve against the canvas window (storage coordinates) into the storage-space
    /// reflection sums a write path uses. The canvas center is `w − 1` in half-pixel units;
    /// the storage sum adds the origin twice (`x_s' = A + 2·ox − x_s`), so the overscan gutter
    /// never shifts the axis.
    pub fn resolve(&self, canvas: IRect) -> Mirror {
        let axis = |explicit: Option<i32>, extent: u32, origin: i32| -> Option<i32> {
            let hi = 2 * (extent as i32 - 1).max(0);
            let a = explicit.unwrap_or(extent as i32 - 1).clamp(0, hi);
            Some(a + 2 * origin)
        };
        Mirror {
            h: if self.mode.mirrors_x() { axis(self.ax, canvas.w, canvas.x) } else { None },
            v: if self.mode.mirrors_y() { axis(self.ay, canvas.h, canvas.y) } else { None },
        }
    }

    /// The DSL line that restates this setting.
    pub fn to_dsl(&self) -> String {
        let axis = |a: Option<i32>| a.map(|v| v.to_string()).unwrap_or_else(|| "c".to_string());
        format!("SetSymmetry({},{},{})", self.mode.token(), axis(self.ax), axis(self.ay))
    }
}

/// A resolved mirror for one write path (storage coordinates): `x' = h − x`, `y' = v − y`.
/// `NONE` is the identity. Frozen into a coat's `PaintCtx` at stroke start (ADR 0007); read
/// live by the Pencil, the Bucket, and the figure commit, like the pattern gate.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Mirror {
    pub h: Option<i32>,
    pub v: Option<i32>,
}

/// One reflection of the active set: which axes it flips.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Reflection {
    pub fx: bool,
    pub fy: bool,
}

impl Mirror {
    pub const NONE: Mirror = Mirror { h: None, v: None };

    #[inline]
    pub fn is_none(&self) -> bool {
        self.h.is_none() && self.v.is_none()
    }

    /// The active reflections, identity first, in a fixed order (id, x, y, xy) — so two points
    /// transformed in parallel stay paired (a mirrored line segment keeps its endpoints).
    pub fn reflections(&self) -> impl Iterator<Item = Reflection> {
        let (h, v) = (self.h.is_some(), self.v.is_some());
        [
            Some(Reflection { fx: false, fy: false }),
            h.then_some(Reflection { fx: true, fy: false }),
            v.then_some(Reflection { fx: false, fy: true }),
            (h && v).then_some(Reflection { fx: true, fy: true }),
        ]
        .into_iter()
        .flatten()
    }

    /// Apply one reflection to a storage point.
    #[inline]
    pub fn apply(&self, r: Reflection, p: Point) -> Point {
        let x = if r.fx { self.h.map_or(p.x, |h| h - p.x) } else { p.x };
        let y = if r.fy { self.v.map_or(p.y, |v| v - p.y) } else { p.y };
        Point::new(x, y)
    }

    /// The distinct images of `p` (the primary first). A point on an axis has fewer than the
    /// reflection count — it is written once, never twice.
    pub fn images(&self, p: Point) -> Images {
        let mut out = Images { pts: [p; 4], n: 0, i: 0 };
        for r in self.reflections() {
            let q = self.apply(r, p);
            if !out.pts[..out.n].contains(&q) {
                out.pts[out.n] = q;
                out.n += 1;
            }
        }
        out
    }

    /// The canonical image of (x, y): the lexicographically smallest, so a position hash (the
    /// airbrush speckle field) is identical across all images and the mirror is pixel-exact.
    #[inline]
    pub fn canonical(&self, x: i32, y: i32) -> (i32, i32) {
        if self.is_none() {
            return (x, y);
        }
        let mut best = (x, y);
        for q in self.images(Point::new(x, y)) {
            if (q.x, q.y) < best {
                best = (q.x, q.y);
            }
        }
        best
    }
}

/// The distinct images of one point under a [`Mirror`] (at most four).
#[derive(Clone, Copy, Debug)]
pub struct Images {
    pts: [Point; 4],
    n: usize,
    i: usize,
}

impl Iterator for Images {
    type Item = Point;
    fn next(&mut self) -> Option<Point> {
        if self.i < self.n {
            let p = self.pts[self.i];
            self.i += 1;
            Some(p)
        } else {
            None
        }
    }
}

/// The canonical Bayer matrices (ordered-dither thresholds `0..n²`), used by the Gradient's
/// dither (ADR 0025). `BAYER4` and `BAYER8` are the recursive expansions of `BAYER2`
/// (`M(2n) = [[4M, 4M+2], [4M+3, 4M+1]]`) — a unit test pins that.
pub const BAYER2: [[u8; 2]; 2] = [[0, 2], [3, 1]];
pub const BAYER4: [[u8; 4]; 4] = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]];
pub const BAYER8: [[u8; 8]; 8] = [
    [0, 32, 8, 40, 2, 34, 10, 42],
    [48, 16, 56, 24, 50, 18, 58, 26],
    [12, 44, 4, 36, 14, 46, 6, 38],
    [60, 28, 52, 20, 62, 30, 54, 22],
    [3, 35, 11, 43, 1, 33, 9, 41],
    [51, 19, 59, 27, 49, 17, 57, 25],
    [15, 47, 7, 39, 13, 45, 5, 37],
    [63, 31, 55, 23, 61, 29, 53, 21],
];

/// The Bayer threshold at canvas coordinate (x, y) for an `n`×`n` matrix, `n ∈ {2, 4, 8}` (any
/// other `n` reads as 2×2). Negative coordinates wrap like positive ones.
#[inline]
pub fn bayer_threshold(n: u8, x: i32, y: i32) -> u16 {
    match n {
        4 => BAYER4[y.rem_euclid(4) as usize][x.rem_euclid(4) as usize] as u16,
        8 => BAYER8[y.rem_euclid(8) as usize][x.rem_euclid(8) as usize] as u16,
        _ => BAYER2[y.rem_euclid(2) as usize][x.rem_euclid(2) as usize] as u16,
    }
}

/// The Gradient's ordered dither in force for one fill: the Bayer size and the canvas origin the
/// matrix is anchored to (storage coordinates, like `PatternGate::origin`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Dither {
    pub n: u8,
    pub origin: Point,
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
    /// Ease each color transition with the smoothstep curve instead of a linear ramp.
    pub smoothstep: bool,
    /// Ordered dither (ADR 0025): 0 = off (a smooth ramp); 2, 4, or 8 = the Bayer matrix size.
    /// When on, every pixel is exactly one of the two stop colors bounding it (alpha included),
    /// chosen by comparing the (smoothstepped) local fraction against the Bayer threshold at the
    /// pixel's canvas coordinate. Independent from `ToolSettings::pattern`, which the Gradient
    /// never reads.
    pub dither: u8,
}
impl GradientSpec {
    /// The dither in force for a fill anchored at `origin`, or `None` when off.
    pub fn dither_at(&self, origin: Point) -> Option<Dither> {
        matches!(self.dither, 2 | 4 | 8).then_some(Dither { n: self.dither, origin })
    }
}
impl Default for GradientSpec {
    fn default() -> Self {
        GradientSpec {
            kind: GradientKind::Linear,
            stops: vec![Stop::new(Rgba8::BLACK, 0.0), Stop::new(Rgba8::WHITE, 1.0)],
            smoothstep: false,
            dither: 0,
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
    /// Levels pending adjustment: (low input, gamma in thousandths, high input) — (0, 1000, 255)
    /// = identity. Stored raw like the DSL sent it; `color::levels_lut` sanitizes. Previewed
    /// live, baked by ApplyLevels.
    pub levels: (u8, i32, u8),
    /// Levels "Frame" scope (same semantics as `hsv_frame`).
    pub levels_frame: bool,
    pub shape_fill: bool,
    pub line_width: u16,
    /// When true, a layer Move refuses to push any opaque pixel off-canvas (non-destructive).
    /// **Retired from the editor UI 2026-09-04 (ADR 0023):** the shell never sets it anymore, but
    /// `SetProtectPixels` stays fully functional so journals recorded with it replay unchanged.
    pub protect_pixels: bool,
    /// When true, a layer Move wraps pixels around the canvas edges (top↔bottom, left↔right)
    /// instead of clipping them off. Takes precedence over `protect_pixels` wherever both are set.
    pub wrap: bool,
    /// Pencil "pixel perfect": while drawing a 1px Pencil stroke, drop the redundant "corner double"
    /// pixels (the L-shaped elbow at each turn) so the line stays a clean 1px wide. Only meaningful
    /// at `brush_size == 1`; a no-op otherwise.
    pub pixel_perfect: bool,
    /// Anti-alias (AA, ADR 0008): one shared flag for the round Brush, the shape tools
    /// (Line/Rectangle/Ellipse/Triangle), and the round Eraser — fractional-coverage edges from
    /// the supersampled AA rasterizers instead of hard pixel steps. Ignored by every other tool;
    /// a size-1 or Square brush stays hard regardless (see `Session::open_coat`).
    pub aa: bool,
    /// The pattern in force (ADR 0025), `None` = off. One global tile; the shell resolves its
    /// per-tool On/Off and pushes only what applies to the current tool. Read by the Pencil,
    /// Brush, Eraser, and Bucket write paths; every other tool ignores it. AA is inert while a
    /// pattern is on (`Session::open_coat`).
    pub pattern: Option<Pattern>,
    /// Mirror drawing (ADR 0026): `Off` by default; a session setting, never saved. Read by the
    /// stroke coat (frozen at stroke start), the Pencil, the Bucket, and the figure commit.
    pub symmetry: Symmetry,
    /// Overscan view: when on, the display renders the whole storage area (canvas + gutter, the gutter
    /// dimmed) and selection gestures may reach into the gutter. A view/interaction flag driven from
    /// the shell (like `wrap`); it never affects paint tools, export or thumbnails. [SPEC §8]
    pub overscan_view: bool,
    /// Rotate tool: sample free-angle rotations through the cleanEdge edge-aware reconstruction
    /// (`crate::cleanedge`) instead of plain nearest-neighbor. The default rotation mode.
    pub clean_edge: bool,
    /// cleanEdge line width, 0.0..=2.0 (the sampler saturates the effective width to its
    /// internal [0.45, 1.142] identity-preserving band, like the reference shader).
    pub clean_edge_width: f32,
    /// Resize tool: sample upscales through the cleanEdge reconstruction (only applies when
    /// both factors ≥ 1; downscaling is always nearest-neighbor). Independent from the Rotate
    /// tool's `clean_edge`. The default resize mode.
    pub scale_clean_edge: bool,
    /// The Resize tool's cleanEdge line width, 0.0..=2.0 (same semantics as `clean_edge_width`,
    /// independent value).
    pub scale_clean_edge_width: f32,
    /// Eyedropper source: when true, picks sample the active layer's raw stored pixel (layer
    /// opacity/visibility ignored — the paint you'd re-apply editing that layer) instead of the
    /// composited frame (the default).
    pub eyedrop_layer: bool,
    /// Select Color source: when true, the color mask is built from the active layer's raw stored
    /// pixels (layer opacity/visibility ignored) instead of the composited frame (the default).
    /// Independent from `eyedrop_layer`.
    pub select_color_layer: bool,
}
impl Default for ToolSettings {
    fn default() -> Self {
        ToolSettings {
            primary: Rgba8::BLACK,
            secondary: Rgba8::WHITE,
            brush_size: 1,
            brush_shape: BrushShape::Round,
            intensity: 50,
            threshold: 0,
            alpha_cutoff: 0,
            contiguous: true,
            fill_all_layers: false,
            gradient: GradientSpec::default(),
            hsv: (0.0, 0.0, 0.0),
            hsv_frame: false,
            bc: (0, 1.0),
            bc_frame: false,
            levels: (0, 1000, 255),
            levels_frame: false,
            shape_fill: true,
            line_width: 1,
            protect_pixels: false,
            wrap: false,
            pixel_perfect: false,
            aa: false,
            pattern: None,
            symmetry: Symmetry::OFF,
            overscan_view: false,
            clean_edge: true,
            clean_edge_width: 1.0,
            scale_clean_edge: true,
            scale_clean_edge_width: 1.0,
            eyedrop_layer: false,
            select_color_layer: false,
        }
    }
}

/// Write `color` at (x,y) honoring the edit `clip` (the canvas window, in storage coords — pixels
/// outside it are the off-canvas gutter that tools may not draw into), the selection clip, the
/// pattern `gate` (ADR 0025 — an OFF cell leaves the pixel untouched), and the paint mode.
/// Storage coordinates throughout.
#[inline]
#[allow(clippy::too_many_arguments)]
pub fn plot(
    buf: &mut RgbaBuffer,
    sel: Option<&Mask>,
    gate: Option<PatternGate>,
    clip: IRect,
    x: i32,
    y: i32,
    color: Rgba8,
    mode: PaintMode,
) {
    if !clip.contains(Point::new(x, y)) {
        return; // outside the editable window (the gutter) — never draw here
    }
    if let Some(m) = sel {
        if !m.get(x, y) {
            return;
        }
    }
    if !gate_admits(gate, x, y) {
        return;
    }
    match mode {
        PaintMode::Replace => buf.set(x, y, color),
        PaintMode::Over => buf.blend_over(x, y, color),
        PaintMode::Erase => buf.set(x, y, Rgba8::TRANSPARENT),
    }
}

/// A single brush stamp of the configured size/shape.
#[allow(clippy::too_many_arguments)]
pub fn stamp(
    buf: &mut RgbaBuffer,
    sel: Option<&Mask>,
    gate: Option<PatternGate>,
    clip: IRect,
    center: Point,
    size: u16,
    shape: BrushShape,
    color: Rgba8,
    mode: PaintMode,
) {
    let radius = (size.max(1) as i32 - 1) / 2;
    let mut f = |x: i32, y: i32| plot(buf, sel, gate, clip, x, y, color, mode);
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
    gate: Option<PatternGate>,
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
        stamp(buf, sel, gate, clip, c, size, shape, color, mode);
    }
}

/// Flood-fill from every seed in `seeds` (SPEC §11.2; several seeds = the images of one tap
/// under symmetry, ADR 0026). The fill is always written to `buf` (the active layer). The
/// region to fill is decided by `reference` when `Some` — the composited image, for the "All
/// layers" mode, so connectivity/color-matching considers every layer — otherwise by `buf`
/// itself (active layer). Every seed's region is decided against the **pre-fill** buffer and
/// the union is written once: a second flood run after the first write would see a
/// half-dithered region and behave erratically. The pattern `gate` (ADR 0025) never shapes the
/// region — threshold, contiguity, and the reference decide it exactly as without one, and a
/// gated-off pixel still propagates the flood — it only decides which pixels inside the region
/// get written. Seeds outside `clip` (the gutter) are ignored.
#[allow(clippy::too_many_arguments)]
pub fn flood_fill(
    buf: &mut RgbaBuffer,
    reference: Option<&RgbaBuffer>,
    sel: Option<&Mask>,
    gate: Option<PatternGate>,
    clip: IRect,
    seeds: &[Point],
    color: Rgba8,
    threshold: u8,
    contiguous: bool,
    mode: PaintMode,
) {
    let w = buf.width() as i32;
    let h = buf.height() as i32;
    // Sample the deciding buffer: the reference (composite) if given, else the layer being filled.
    let read = |x: i32, y: i32, b: &RgbaBuffer| match reference {
        Some(r) => r.get(x, y),
        None => b.get(x, y),
    };
    let in_sel = |x: i32, y: i32| sel.map(|m| m.get(x, y)).unwrap_or(true);
    let mut region = vec![false; (w * h) as usize];
    let mut any = false;
    for &seed in seeds {
        // Bucket is canvas-only: the flood may neither start nor spread outside `clip`.
        if !clip.contains(seed) {
            continue;
        }
        let target = read(seed.x, seed.y, buf);
        if contiguous {
            let mut visited = vec![false; (w * h) as usize];
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
                region[idx] = true;
                any = true;
                stack.push(Point::new(p.x + 1, p.y));
                stack.push(Point::new(p.x - 1, p.y));
                stack.push(Point::new(p.x, p.y + 1));
                stack.push(Point::new(p.x, p.y - 1));
            }
        } else {
            for y in clip.y..clip.bottom() {
                for x in clip.x..clip.right() {
                    if in_sel(x, y) && color::max_channel_delta(read(x, y, buf), target) <= threshold {
                        region[(y * w + x) as usize] = true;
                        any = true;
                    }
                }
            }
        }
    }
    if !any {
        return;
    }
    for y in clip.y..clip.bottom() {
        for x in clip.x..clip.right() {
            if region[(y * w + x) as usize] {
                plot(buf, sel, gate, clip, x, y, color, mode);
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
/// each color transition eases in/out while the stop positions themselves stay put.
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

/// Sample a gradient at `t` for the pixel at storage coordinate (x, y) over **sorted** stops,
/// honoring an optional ordered dither (ADR 0025). With `dither = Some(d)`, the pixel is exactly
/// one of the two stop colors bounding `t` (alpha included): stop `i+1` when
/// `floor(local · n²) > bayer_n(cx, cy)`, else stop `i`, where `local` is the (smoothstepped) local
/// fraction and (cx, cy) the pixel's canvas coordinate. So `local = 0` is all stop `i`, `local = 1`
/// all stop `i+1`, and the density between is the classic ordered-dither ladder. Pixels at or past
/// the first/last stop take that stop's color as without dithering. Integer compare on a truncated
/// product: the same IEEE `f32` fraction the smooth ramp already puts on the wire.
pub fn gradient_sample_sorted(s: &[Stop], t: f32, smooth: bool, dither: Option<Dither>, x: i32, y: i32) -> Rgba8 {
    let Some(d) = dither else {
        return gradient_color_at_sorted(s, t, smooth);
    };
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
            let cells = d.n as i32 * d.n as i32;
            let q = (local * cells as f32) as i32; // truncation == floor for a non-negative fraction
            let th = bayer_threshold(d.n, x - d.origin.x, y - d.origin.y) as i32;
            return if q > th { s[i + 1].color } else { s[i].color };
        }
    }
    s[s.len() - 1].color
}

/// Evaluate the gradient color for a pixel (closed form; the oracle uses the same path).
#[allow(clippy::too_many_arguments)]
pub fn gradient_eval(
    kind: GradientKind,
    stops: &[Stop],
    p0: Point,
    p1: Point,
    x: i32,
    y: i32,
    smooth: bool,
    dither: Option<Dither>,
) -> Rgba8 {
    let mut s: Vec<Stop> = stops.to_vec();
    s.sort_by(|a, b| a.t.total_cmp(&b.t));
    gradient_sample_sorted(&s, gradient_t(kind, p0, p1, x, y), smooth, dither, x, y)
}

/// Like `gradient_eval` but assumes `stops` are pre-sorted — for per-pixel fill/preview loops. [F-14]
#[allow(clippy::too_many_arguments)]
pub fn gradient_eval_sorted(
    kind: GradientKind,
    stops: &[Stop],
    p0: Point,
    p1: Point,
    x: i32,
    y: i32,
    smooth: bool,
    dither: Option<Dither>,
) -> Rgba8 {
    gradient_sample_sorted(stops, gradient_t(kind, p0, p1, x, y), smooth, dither, x, y)
}

/// Blend a gradient over a region (source-over, like the Brush/shape tools' `PaintMode::Over`),
/// clipped to selection and the canvas `clip` (SPEC §11.3). Transparent and semi-transparent stops
/// composite onto existing content instead of overwriting it (behavior change 2026-08-16; earlier
/// journals with gradients over content replay with the new blend). Deterministic per pixel.
/// `origin` is the canvas origin in storage coordinates — what the dither's Bayer matrix is
/// anchored to (ADR 0025); irrelevant when `spec.dither == 0`.
#[allow(clippy::too_many_arguments)]
pub fn apply_gradient(
    buf: &mut RgbaBuffer,
    sel: Option<&Mask>,
    clip: IRect,
    spec: &GradientSpec,
    p0: Point,
    p1: Point,
    origin: Point,
) {
    // Sort the stops ONCE, not once per pixel — `gradient_color_at` used to clone+sort the whole
    // stop vector for every pixel (65 536× on a 256² fill). [audit F-14]
    let mut stops = spec.stops.clone();
    stops.sort_by(|a, b| a.t.total_cmp(&b.t));
    let dither = spec.dither_at(origin);
    for y in clip.y..clip.bottom() {
        for x in clip.x..clip.right() {
            if let Some(m) = sel {
                if !m.get(x, y) {
                    continue;
                }
            }
            let t = gradient_t(spec.kind, p0, p1, x, y);
            buf.blend_over(x, y, gradient_sample_sorted(&stops, t, spec.smoothstep, dither, x, y));
        }
    }
}

// The Airbrush/Dodge/Burn dab implementations moved into the single-coat stroke model
// (`crate::coat`, ADR 0007): dabs write max-combined coverage into a per-stroke coat, and
// `StrokeCoat::resolve` applies it — there are no per-dab layer writes anymore.

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
            plot(buf, sel, None, clip, x, y, color, PaintMode::Replace);
        }
    }
}

/// Fill `rect` with seeded random RGBA noise — every pixel non-transparent, every tile distinct
/// and incompressible. The single source of the stress-noise byte pattern: `Session::fill_noise`
/// (the `FillNoise` DSL action), the `mkpx gen` harness command, and the app's stress lab must
/// all produce identical content for a given seed.
pub fn noise_fill(buf: &mut RgbaBuffer, rect: IRect, seed: u64) {
    let mut rng = crate::util::SeededRng::new(seed);
    for y in rect.y..rect.bottom() {
        for x in rect.x..rect.right() {
            let v = rng.next_u64();
            // Alpha ORs in 1 so no pixel is transparent (keeps every tile fully materialized and
            // immune to compact()); the low bias is irrelevant for stress content.
            let c = Rgba8::new(v as u8, (v >> 8) as u8, (v >> 16) as u8, (v >> 24) as u8 | 1);
            buf.set(x, y, c);
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
            plot(buf, sel, None, clip, x, y, Rgba8::TRANSPARENT, PaintMode::Erase);
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

/// The AA shapes' shared geometry dispatch (ADR 0008): route a Line/Rectangle/Ellipse/Triangle
/// to its coverage rasterizer. Commit (`draw_shape` with `aa`) and the live preview both go
/// through THIS function with the same inputs, so their coverage per pixel is identical by
/// construction — only the plotting differs (clip/selection on commit, the display on preview).
#[allow(clippy::too_many_arguments)]
pub fn shape_cover_aa(
    kind: ToolKind,
    a: Point,
    b: Point,
    rot: f32,
    tip: f32,
    fill: bool,
    line_width: u16,
    plot: &mut dyn FnMut(i32, i32, u8),
) {
    let lw = line_width.max(1) as i32;
    match kind {
        ToolKind::Line => raster::thick_line_aa(a, b, lw, plot),
        ToolKind::Rectangle => raster::rect_aa(a, b, rot, fill, lw, plot),
        ToolKind::Ellipse => raster::ellipse_aa(a, b, rot, fill, lw, plot),
        ToolKind::Triangle => raster::triangle_aa(a, b, rot, tip, fill, lw, plot),
        _ => {}
    }
}

/// Coverage ⊗ color: the color with its alpha scaled by `cover` — the coat's 8-bit rounding
/// idiom, shared by the AA shape commit and preview so the two can never disagree.
#[inline]
pub fn cover_color(color: Rgba8, cover: u8) -> Option<Rgba8> {
    let a = (cover as u32 * color.a as u32 + 127) / 255;
    if a == 0 {
        None
    } else {
        Some(Rgba8::new(color.r, color.g, color.b, a as u8))
    }
}

/// Every (x, y, coverage) plot of a figure, AA or hard (hard plots carry coverage 255), through
/// the same rasterizers `draw_shape` and the preview use. The mirrored figure paths (ADR 0026)
/// feed these plots into a [`CoverMap`] so the primary and its images max-combine.
#[allow(clippy::too_many_arguments)]
pub fn shape_plots(
    kind: ToolKind,
    a: Point,
    b: Point,
    rot: f32,
    tip: f32,
    fill: bool,
    line_width: u16,
    aa: bool,
    plot: &mut dyn FnMut(i32, i32, u8),
) {
    if aa {
        shape_cover_aa(kind, a, b, rot, tip, fill, line_width, plot);
        return;
    }
    let lw = line_width.max(1) as i32;
    let mut f = |x: i32, y: i32| plot(x, y, 255);
    if kind == ToolKind::Triangle {
        if fill {
            raster::triangle_filled(a, b, rot, tip, &mut f);
        } else {
            raster::triangle_outline(a, b, rot, tip, lw, &mut f);
        }
        return;
    }
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

/// A max-combined coverage map over one rect (ADR 0026): a mirrored figure's primary and image
/// plots land here first, so where they overlap on the axis the pixel is composited **once** at
/// the higher coverage — never blended twice (the coat's rule, ADR 0007, applied to figures).
pub struct CoverMap {
    rect: IRect,
    cover: Vec<u8>,
}

impl CoverMap {
    pub fn new(rect: IRect) -> CoverMap {
        CoverMap { rect, cover: vec![0; (rect.w * rect.h) as usize] }
    }
    #[inline]
    pub fn raise(&mut self, x: i32, y: i32, c: u8) {
        if c == 0 || !self.rect.contains(Point::new(x, y)) {
            return;
        }
        let i = ((y - self.rect.y) as u32 * self.rect.w + (x - self.rect.x) as u32) as usize;
        if self.cover[i] < c {
            self.cover[i] = c;
        }
    }
    /// Raise every image of (x, y) under `mirror`.
    #[inline]
    pub fn raise_mirrored(&mut self, mirror: Mirror, x: i32, y: i32, c: u8) {
        for q in mirror.images(Point::new(x, y)) {
            self.raise(q.x, q.y, c);
        }
    }
    /// Visit every covered pixel (row-major).
    pub fn for_each(&self, mut f: impl FnMut(i32, i32, u8)) {
        for y in 0..self.rect.h as i32 {
            for x in 0..self.rect.w as i32 {
                let c = self.cover[(y as u32 * self.rect.w + x as u32) as usize];
                if c > 0 {
                    f(self.rect.x + x, self.rect.y + y, c);
                }
            }
        }
    }
}

/// The coverage map of a figure and all its images under `mirror`, over `rect`.
#[allow(clippy::too_many_arguments)]
pub fn shape_cover_mirrored(
    rect: IRect,
    mirror: Mirror,
    kind: ToolKind,
    a: Point,
    b: Point,
    rot: f32,
    tip: f32,
    fill: bool,
    line_width: u16,
    aa: bool,
) -> CoverMap {
    let mut map = CoverMap::new(rect);
    shape_plots(kind, a, b, rot, tip, fill, line_width, aa, &mut |x, y, c| map.raise_mirrored(mirror, x, y, c));
    map
}

/// Draw a shape (Line/Rectangle/Ellipse/Triangle), outline or filled (SPEC §28.1), optionally
/// rotated by `rot` radians (Rectangle/Ellipse/Triangle). `tip` ∈ [-1, 1] skews a Triangle's apex
/// horizontally along its top edge (ignored by the other shapes). With `aa` (ADR 0008) the shape
/// draws through the coverage rasterizers instead — fractional rim alpha via [`cover_color`].
/// With a `mirror` (ADR 0026) the rasterized pixels are reflected — a pixel-exact mirror — and
/// the primary and its images composite through one [`CoverMap`]; without one the path is
/// byte-identical to the pre-symmetry engine.
#[allow(clippy::too_many_arguments)]
pub fn draw_shape(
    buf: &mut RgbaBuffer,
    sel: Option<&Mask>,
    clip: IRect,
    mirror: Mirror,
    kind: ToolKind,
    a: Point,
    b: Point,
    rot: f32,
    tip: f32,
    color: Rgba8,
    fill: bool,
    line_width: u16,
    mode: PaintMode,
    aa: bool,
) {
    if !mirror.is_none() {
        let map = shape_cover_mirrored(clip, mirror, kind, a, b, rot, tip, fill, line_width, aa);
        map.for_each(|x, y, c| {
            if let Some(src) = cover_color(color, c) {
                plot(buf, sel, None, clip, x, y, src, mode);
            }
        });
        return;
    }
    if aa {
        shape_cover_aa(kind, a, b, rot, tip, fill, line_width, &mut |x, y, c| {
            if let Some(src) = cover_color(color, c) {
                plot(buf, sel, None, clip, x, y, src, mode);
            }
        });
        return;
    }
    let lw = line_width.max(1) as i32;
    let mut f = |x: i32, y: i32| plot(buf, sel, None, clip, x, y, color, mode);
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
        stamp(&mut b, None, None, IRect::new(0, 0, 16, 16), Point::new(5, 5), 1, BrushShape::Square, Rgba8::WHITE, PaintMode::Replace);
        assert_eq!(b.get(5, 5), Rgba8::WHITE);
    }

    #[test]
    fn flood_fill_fills_region() {
        let mut b = RgbaBuffer::new(8, 8);
        flood_fill(&mut b, None, None, None, IRect::new(0, 0, 8, 8), &[Point::new(0, 0)], Rgba8::WHITE, 0, true, PaintMode::Replace);
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
        flood_fill(&mut b, None, None, None, IRect::new(0, 0, 8, 8), &[Point::new(0, 0)], Rgba8::WHITE, 0, true, PaintMode::Replace);
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
            dither: 0,
        };
        apply_gradient(&mut b, None, IRect::new(0, 0, 16, 1), &spec, Point::new(0, 0), Point::new(15, 0), Point::new(0, 0));
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
            dither: 0,
        };
        let (p0, p1) = (Point::new(16, 16), Point::new(16, 0));
        apply_gradient(&mut b, None, IRect::new(0, 0, 32, 32), &spec, p0, p1, Point::new(0, 0));
        for y in 0..32 {
            for x in 0..32 {
                let expected = gradient_eval(spec.kind, &spec.stops, p0, p1, x, y, spec.smoothstep, None);
                assert_eq!(b.get(x, y), expected);
            }
        }
    }

    // (The airbrush/soft/mist dab tests moved to `crate::coat` with the dab implementations —
    // falloff, peak, seed determinism, and translucency are asserted on the coat now.)

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

#[cfg(test)]
mod pattern_tests {
    use super::*;

    #[test]
    fn pattern_parse_bounds_and_round_trip() {
        assert!(Pattern::parse(0, 2, "1").is_err());
        assert!(Pattern::parse(2, 17, "1").is_err());
        assert!(Pattern::parse(2, 2, "").is_err());
        assert!(Pattern::parse(2, 2, "10").is_err(), "bit 4 is beyond a 2×2 tile");
        assert!(Pattern::parse(2, 2, "g").is_err());
        assert!(Pattern::parse(2, 2, &"0".repeat(65)).is_err());
        assert!(Pattern::parse(16, 16, &"f".repeat(64)).unwrap().is_all_on());
        let p = Pattern::parse(4, 4, "5A5A").unwrap();
        assert_eq!(p.hex(), "5a5a");
        assert_eq!(p.to_dsl(), "SetPattern(4,4,5a5a)");
        assert_eq!(Pattern::parse(4, 4, "00005a5a").unwrap(), p, "leading zeros are optional");
        assert_eq!(p.width(), 4);
        assert_eq!(p.height(), 4);
        // 5a5a = rows 0101 / 1010 / 0101 / 1010 (bit y*4+x) — a 4×4 checker with (0,0) OFF.
        for y in 0..4 {
            for x in 0..4 {
                assert_eq!(p.on(x, y), (x + y) % 2 == 1, "({x},{y})");
            }
        }
        // Fixed-width hex: a 3×5 tile has 15 bits → 4 digits.
        let q = Pattern::parse(3, 5, "1").unwrap();
        assert_eq!(q.hex(), "0001");
    }

    #[test]
    fn pattern_from_rows_matches_bits_and_tiles_with_wraparound() {
        let p = Pattern::from_rows(&["#.", ".#"]).unwrap();
        assert_eq!(p, Pattern::parse(2, 2, "9").unwrap());
        assert!(p.on(0, 0) && p.on(1, 1) && !p.on(1, 0) && !p.on(0, 1));
        assert!(p.on(-2, -2) && p.on(-1, -1) && !p.on(-1, 0), "negative coordinates wrap");
        assert!(p.on(200, 400) && !p.on(201, 400));
        assert!(Pattern::from_rows(&["#.", "#"]).is_none(), "ragged rows");
        assert!(Pattern::from_rows(&[]).is_none());
        let wide = Pattern::from_rows(&["#...#...#...", "............"]).unwrap();
        assert_eq!((wide.width(), wide.height()), (12, 2));
        assert!(wide.on(4, 0) && !wide.on(4, 1) && wide.on(16, 2));
        assert!(!Pattern::from_rows(&["##", "##"]).unwrap().on(1, 1) == false);
        assert!(Pattern::from_rows(&["##", "##"]).unwrap().is_all_on());
        assert!(!Pattern::from_rows(&["##", "#."]).unwrap().is_all_on());
    }

    #[test]
    fn pattern_gate_is_anchored_to_the_origin_it_carries() {
        let g = PatternGate { pattern: Pattern::from_rows(&["#.", ".#"]).unwrap(), origin: Point::new(5, 3) };
        assert!(g.admits(5, 3), "the canvas origin is cell (0,0)");
        assert!(!g.admits(6, 3));
        assert!(g.admits(6, 4));
        assert!(g.admits(4, 2), "the gutter left of the origin wraps consistently");
    }

    #[test]
    fn bayer_tables_are_the_recursive_expansions() {
        fn expand(m: &[Vec<u8>]) -> Vec<Vec<u8>> {
            let n = m.len();
            let mut out = vec![vec![0u8; 2 * n]; 2 * n];
            for y in 0..n {
                for x in 0..n {
                    let v = 4 * m[y][x];
                    out[y][x] = v;
                    out[y][x + n] = v + 2;
                    out[y + n][x] = v + 3;
                    out[y + n][x + n] = v + 1;
                }
            }
            out
        }
        let b2: Vec<Vec<u8>> = BAYER2.iter().map(|r| r.to_vec()).collect();
        let b4 = expand(&b2);
        let b8 = expand(&b4);
        assert_eq!(b4, BAYER4.iter().map(|r| r.to_vec()).collect::<Vec<_>>());
        assert_eq!(b8, BAYER8.iter().map(|r| r.to_vec()).collect::<Vec<_>>());
        // Each table is a permutation of 0..n².
        for (n, t) in [(2usize, b2), (4, b4), (8, b8)] {
            let mut seen: Vec<u8> = t.iter().flatten().copied().collect();
            seen.sort_unstable();
            assert_eq!(seen, (0..(n * n) as u8).collect::<Vec<_>>());
        }
        assert_eq!(bayer_threshold(8, 7, 7), 21);
        assert_eq!(bayer_threshold(8, 15, -1), 21);
        assert_eq!(bayer_threshold(3, 1, 0), 2, "an unknown size reads as 2×2");
    }

    #[test]
    fn dithered_sample_is_exactly_one_of_two_stops_and_the_ends_are_solid() {
        let stops = [Stop::new(Rgba8::rgb(255, 0, 0), 0.0), Stop::new(Rgba8::rgb(0, 0, 255), 1.0)];
        let d = Some(Dither { n: 4, origin: Point::new(0, 0) });
        for y in 0..4 {
            for x in 0..4 {
                assert_eq!(gradient_sample_sorted(&stops, 0.0, false, d, x, y), Rgba8::rgb(255, 0, 0));
                assert_eq!(gradient_sample_sorted(&stops, 1.0, false, d, x, y), Rgba8::rgb(0, 0, 255));
                let mid = gradient_sample_sorted(&stops, 0.5, false, d, x, y);
                // floor(0.5·16) = 8 > threshold ⇔ threshold < 8: exactly half the cells.
                let expect = if BAYER4[y as usize][x as usize] < 8 { Rgba8::rgb(0, 0, 255) } else { Rgba8::rgb(255, 0, 0) };
                assert_eq!(mid, expect, "({x},{y})");
            }
        }
        // The dither honors the origin: shifting it by one column swaps the checker phase.
        let shifted = Some(Dither { n: 2, origin: Point::new(1, 0) });
        let a = gradient_sample_sorted(&stops, 0.5, false, shifted, 1, 0);
        let b = gradient_sample_sorted(&stops, 0.5, false, Some(Dither { n: 2, origin: Point::new(0, 0) }), 0, 0);
        assert_eq!(a, b);
        // dither = None is the smooth ramp.
        assert_eq!(gradient_sample_sorted(&stops, 0.5, false, None, 0, 0), gradient_color_at_sorted(&stops, 0.5, false));
        // GradientSpec::dither_at maps 0 and junk to None.
        let mut spec = GradientSpec::default();
        assert!(spec.dither_at(Point::new(0, 0)).is_none());
        spec.dither = 8;
        assert_eq!(spec.dither_at(Point::new(2, 2)), Some(Dither { n: 8, origin: Point::new(2, 2) }));
        spec.dither = 3;
        assert!(spec.dither_at(Point::new(0, 0)).is_none());
    }
}
