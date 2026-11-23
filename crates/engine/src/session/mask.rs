//! The mask stamp (ADR 0039): a 1-bit mask colored with the primary color and written through
//! the paint path. The shell lays text out into such a mask; the engine never learns what the
//! mask depicts — a caption, a logo, anything 1-bit.
//!
//! Two halves, deliberately asymmetric:
//!
//! * **The draft** (`MaskDraft` / `MaskDraftMove` / `MaskDraftCancel`) is a display-only preview
//!   the shell keeps in step with what the artist types. It is never journaled, so nothing may
//!   depend on it: it is not part of checkpoints or of `is_quiescent`, and a replay never sees it.
//! * **The stamp** (`MaskStamp`) is self-contained — its own position and mask — so the Journal
//!   holds one line per committed mask and replay needs no draft before it.
//!
//! A stamp obeys the selection, the pattern gate (ADR 0025), and symmetry (ADR 0026), like a
//! stroke. Unlike a stroke it may write into the off-canvas gutter, as Paste and Move do
//! (ADR 0030): a caption dragged past the edge is parked, not destroyed.

use super::{RepeatOp, Session};
use crate::buffer::RgbaBuffer;
use crate::color::Rgba8;
use crate::document::Frame;
use crate::geom::{IRect, Point, MAX_DIM};
use crate::selection::Mask;
use crate::tool::{self, CoverMap, Mirror, PaintMode, PatternGate};

/// The largest side a mask may have: the storage side at the canvas cap (canvas + its gutter).
/// A mask larger than the storage could never land whole, and the bound keeps a hostile DSL line
/// from asking for an unbounded allocation.
pub const MASK_MAX_SIDE: u32 = MAX_DIM as u32 * 3;

/// A rectangular 1-bit mask, row-major: bit `i = y*w + x` lives at `bits[i/8] >> (i%8)` — the
/// [`crate::tool::Pattern`] convention. Canonical: no bit at or beyond `w*h` is ever set.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BitMask {
    w: u32,
    h: u32,
    bits: Vec<u8>,
}

impl BitMask {
    pub fn width(&self) -> u32 {
        self.w
    }
    pub fn height(&self) -> u32 {
        self.h
    }

    #[inline]
    pub fn get(&self, x: u32, y: u32) -> bool {
        let i = (y * self.w + x) as usize;
        self.bits[i / 8] >> (i % 8) & 1 == 1
    }

    /// Parse `w, h, hex`: exactly `2 * ceil(w*h/8)` hex digits, byte by byte in order (byte `k`
    /// holds bits `8k..8k+7`, low bit first), each byte written high digit first.
    pub fn parse(w: u32, h: u32, hex: &str) -> Result<BitMask, String> {
        if !(1..=MASK_MAX_SIDE).contains(&w) || !(1..=MASK_MAX_SIDE).contains(&h) {
            return Err(format!("mask side out of range (1..={})", MASK_MAX_SIDE));
        }
        let n = (w as usize * h as usize).div_ceil(8);
        let hex = hex.trim().as_bytes();
        if hex.len() != n * 2 {
            return Err(format!("mask bits: expected {} hex digits, got {}", n * 2, hex.len()));
        }
        let digit = |c: u8| (c as char).to_digit(16).map(|d| d as u8).ok_or_else(|| format!("mask bits: bad hex digit '{}'", c as char));
        let mut bits = Vec::with_capacity(n);
        for pair in hex.chunks_exact(2) {
            bits.push(digit(pair[0])? << 4 | digit(pair[1])?);
        }
        let tail = (w as usize * h as usize) % 8;
        if tail != 0 && bits[n - 1] >> tail != 0 {
            return Err("mask bits set beyond w*h".to_string());
        }
        Ok(BitMask { w, h, bits })
    }

    /// Build from ASCII rows (`#` = set); the readable form for tests.
    pub fn from_rows(rows: &[&str]) -> Option<BitMask> {
        let h = rows.len() as u32;
        let w = rows.first()?.len() as u32;
        if !(1..=MASK_MAX_SIDE).contains(&w) || !(1..=MASK_MAX_SIDE).contains(&h) {
            return None;
        }
        let mut bits = vec![0u8; (w as usize * h as usize).div_ceil(8)];
        for (y, row) in rows.iter().enumerate() {
            if row.len() as u32 != w {
                return None;
            }
            for (x, c) in row.bytes().enumerate() {
                if c == b'#' {
                    let i = y * w as usize + x;
                    bits[i / 8] |= 1 << (i % 8);
                }
            }
        }
        Some(BitMask { w, h, bits })
    }

    /// The hex form [`BitMask::parse`] reads back.
    pub fn to_hex(&self) -> String {
        let mut s = String::with_capacity(self.bits.len() * 2);
        for b in &self.bits {
            s.push_str(&format!("{:02x}", b));
        }
        s
    }

    /// Visit every set bit as (x, y), row-major.
    fn for_each_set(&self, mut f: impl FnMut(i32, i32)) {
        for y in 0..self.h {
            for x in 0..self.w {
                if self.get(x, y) {
                    f(x as i32, y as i32);
                }
            }
        }
    }
}

/// The open mask draft: the mask and its top-left in CANVAS coordinates. A storage-geometry
/// change cancels it (`cancel_transform_drafts`), so the position never needs re-basing.
pub struct MaskDraft {
    mask: BitMask,
    pos: Point,
}

impl Session {
    /// Open or replace the mask draft with `mask` at canvas (x, y). Display-only: the document
    /// is untouched and nothing is recorded.
    pub fn mask_draft_set(&mut self, x: i32, y: i32, mask: BitMask) {
        self.mask_draft = Some(MaskDraft { mask, pos: Point::new(x, y) });
    }

    /// Translate the open mask draft by whole pixels. No-op without one.
    pub fn mask_draft_move(&mut self, dx: i32, dy: i32) {
        if let Some(d) = &mut self.mask_draft {
            d.pos.x = d.pos.x.saturating_add(dx);
            d.pos.y = d.pos.y.saturating_add(dy);
        }
    }

    /// Discard the mask draft without drawing anything.
    pub fn mask_draft_cancel(&mut self) {
        self.mask_draft = None;
    }

    /// The mask draft's rect in canvas coordinates, if one is open — for the state probe.
    pub fn mask_draft_rect(&self) -> Option<IRect> {
        self.mask_draft.as_ref().map(|d| IRect::new(d.pos.x, d.pos.y, d.mask.w, d.mask.h))
    }

    /// Stamp `mask` at canvas (x, y) into the active layer in the primary color, as one undo
    /// step, and arm Repeat (ADR 0040). Self-contained: any open draft is dropped, never read.
    /// A silent no-op on a hidden or locked layer — the silence the figure commit keeps.
    pub fn mask_stamp(&mut self, x: i32, y: i32, mask: BitMask) {
        self.mask_draft = None;
        if !self.active_editable() {
            return;
        }
        let (pos, color) = (Point::new(x, y), self.settings.primary);
        self.stamp_mask_recorded(&mask, pos, color);
        self.repeat_record = Some(RepeatOp::Mask { mask, pos, color });
    }

    /// One recorded stamp against the live target — the shared body of the commit and of Repeat.
    pub(super) fn stamp_mask_recorded(&mut self, mask: &BitMask, pos: Point, color: Rgba8) {
        let before = self.begin_edit();
        let ctx = self.stamp_ctx();
        ctx.stamp(&mut self.doc.active_frame_mut().active_layer_mut().pixels, mask, pos, color);
        self.commit_edit(before);
    }

    /// Everything a stamp reads from the session, frozen so the layer can be borrowed mutably.
    fn stamp_ctx(&self) -> StampCtx {
        let origin = self.doc.origin();
        StampCtx {
            origin,
            clip: self.doc.storage_rect(),
            sel: self.selection_clone(),
            gate: self.settings.pattern.map(|pattern| PatternGate { pattern, origin }),
            mirror: self.mirror(),
        }
    }

    /// The display-time preview of the open mask draft: a clone of the active frame with the mask
    /// stamped exactly as a commit would stamp it, so layer opacity, blend modes, layers above,
    /// the selection, the pattern, and symmetry all show true. `None` without a draft, or on an
    /// uneditable layer (see [`Session::mask_draft_paint_raw`]).
    pub(super) fn mask_draft_preview_frame(&self) -> Option<Frame> {
        let d = self.mask_draft.as_ref()?;
        if !self.active_editable() {
            return None;
        }
        let mut frame = self.doc.active_frame().clone();
        let li = frame.active_layer;
        self.stamp_ctx().stamp(&mut frame.layers[li].pixels, &d.mask, d.pos, self.settings.primary);
        Some(frame)
    }

    /// On a hidden or locked layer a commit would do nothing, but the artist still has to see
    /// what they are typing: paint the bare mask over the finished display instead.
    pub(super) fn mask_draft_paint_raw(&self, display: &mut RgbaBuffer) {
        let d = match &self.mask_draft {
            Some(d) if !self.active_editable() => d,
            _ => return,
        };
        let o = self.doc.origin();
        let color = self.settings.primary;
        d.mask.for_each_set(|x, y| {
            display.blend_over(d.pos.x.saturating_add(o.x).saturating_add(x), d.pos.y.saturating_add(o.y).saturating_add(y), color);
        });
    }
}

/// The live selection, pattern, and symmetry a stamp is written under. The clip is the whole
/// storage, not the canvas: off-canvas pixels are parked in the gutter (ADR 0030).
struct StampCtx {
    origin: Point,
    clip: IRect,
    sel: Option<Mask>,
    gate: Option<PatternGate>,
    mirror: Mirror,
}

impl StampCtx {
    /// Write `mask` at canvas `pos` into `buf` (a layer's storage buffer). Under symmetry the
    /// primary and its images go through one coverage map, so a pixel on the axis is composited
    /// once (the figure rule, ADR 0026).
    fn stamp(&self, buf: &mut RgbaBuffer, mask: &BitMask, pos: Point, color: Rgba8) {
        let (bx, by) = (pos.x.saturating_add(self.origin.x), pos.y.saturating_add(self.origin.y));
        let (sel, gate, clip) = (self.sel.as_ref(), self.gate, self.clip);
        if self.mirror.is_none() {
            mask.for_each_set(|x, y| {
                tool::plot(buf, sel, gate, clip, bx.saturating_add(x), by.saturating_add(y), color, PaintMode::Over);
            });
            return;
        }
        let mut map = CoverMap::new(clip);
        mask.for_each_set(|x, y| map.raise_mirrored(self.mirror, bx.saturating_add(x), by.saturating_add(y), 255));
        map.for_each(|x, y, _| tool::plot(buf, sel, gate, clip, x, y, color, PaintMode::Over));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tool::{SymMode, Symmetry};

    fn px(s: &Session, x: i32, y: i32) -> Rgba8 {
        let o = s.doc.origin();
        s.doc.active_frame().active_layer().pixels.get(x + o.x, y + o.y)
    }

    const RED: Rgba8 = Rgba8 { r: 255, g: 0, b: 0, a: 255 };

    fn session() -> Session {
        let mut s = Session::new(16, 16);
        s.settings.primary = RED;
        s
    }

    #[test]
    fn hex_round_trips_and_rejects_non_canonical() {
        let m = BitMask::from_rows(&["#.#", ".#.", "#.#"]).unwrap();
        assert_eq!(BitMask::parse(3, 3, &m.to_hex()).unwrap(), m);
        assert!(BitMask::parse(3, 3, "ffff").is_err(), "bits beyond w*h");
        assert!(BitMask::parse(3, 3, "ff").is_err(), "too few digits");
        assert!(BitMask::parse(0, 3, "").is_err());
        assert!(BitMask::parse(MASK_MAX_SIDE + 1, 1, "00").is_err());
        assert!(BitMask::parse(2, 2, "0g").is_err());
    }

    #[test]
    fn stamp_writes_the_primary_color_as_one_undo_step() {
        let mut s = session();
        s.run_script("MaskStamp(2, 3, 2, 2, 09)").unwrap(); // bits 0 and 3: (0,0) and (1,1)
        assert_eq!(px(&s, 2, 3), RED);
        assert_eq!(px(&s, 3, 4), RED);
        assert_eq!(px(&s, 3, 3).a, 0);
        s.run_script("Undo()").unwrap();
        assert_eq!(px(&s, 2, 3).a, 0);
        assert_eq!(px(&s, 3, 4).a, 0);
    }

    #[test]
    fn stamp_is_self_contained_and_drops_the_draft() {
        let mut s = session();
        s.run_script("MaskDraft(0, 0, 1, 1, 01); MaskDraftMove(5, 5)").unwrap();
        assert_eq!(s.mask_draft_rect(), Some(IRect::new(5, 5, 1, 1)));
        assert_eq!(px(&s, 5, 5).a, 0, "a draft never touches the document");
        s.run_script("MaskStamp(1, 1, 1, 1, 01)").unwrap();
        assert!(s.mask_draft_rect().is_none());
        assert_eq!(px(&s, 1, 1), RED);
        assert_eq!(px(&s, 5, 5).a, 0, "the stamp lands where IT says, not where the draft was");
    }

    #[test]
    fn draft_previews_exactly_what_the_stamp_writes() {
        let mut s = session();
        s.run_script("SetSymmetry(h,c,c); SetPattern(2,2,9); SelectTool(SelectRect); PointerDown(0,0); PointerMove(15,9); PointerUp()").unwrap();
        s.run_script("MaskDraft(1, 1, 4, 3, ff0f)").unwrap();
        let preview = s.display_bytes(false, false, false);
        s.run_script("MaskStamp(1, 1, 4, 3, ff0f)").unwrap();
        assert_eq!(s.display_bytes(false, false, false), preview);
    }

    #[test]
    fn stamp_obeys_selection_pattern_and_symmetry() {
        let mut s = session();
        s.settings.symmetry = Symmetry { mode: SymMode::H, ..Symmetry::OFF };
        s.run_script("MaskStamp(0, 0, 1, 1, 01)").unwrap();
        assert_eq!(px(&s, 0, 0), RED);
        assert_eq!(px(&s, 15, 0), RED, "mirrored across the centered vertical axis");
        let mut s = session();
        s.run_script("SetPattern(2,1,1); MaskStamp(0, 0, 2, 1, 03)").unwrap();
        assert_eq!(px(&s, 0, 0), RED);
        assert_eq!(px(&s, 1, 0).a, 0, "the OFF pattern cell stays untouched");
        let mut s = session();
        s.run_script("SelectTool(SelectRect); PointerDown(0,0); PointerMove(0,0); PointerUp(); MaskStamp(0, 0, 2, 1, 03)").unwrap();
        assert_eq!(px(&s, 0, 0), RED);
        assert_eq!(px(&s, 1, 0).a, 0, "outside the selection");
    }

    #[test]
    fn off_canvas_pixels_are_parked_in_the_gutter() {
        let mut s = session();
        s.run_script("MaskStamp(-1, 0, 2, 1, 03)").unwrap();
        assert_eq!(px(&s, 0, 0), RED);
        assert_eq!(px(&s, -1, 0), RED, "kept off-canvas, like a paste (ADR 0030)");
    }

    #[test]
    fn locked_layer_refuses_silently_and_far_positions_do_not_panic() {
        let mut s = session();
        s.run_script("SetLayerLocked(0, true); MaskStamp(0, 0, 1, 1, 01)").unwrap();
        assert_eq!(px(&s, 0, 0).a, 0);
        assert!(!s.can_repeat());
        let mut s = session();
        s.run_script("MaskStamp(2147483647, -2147483648, 2, 2, 0f); MaskDraft(2147483647, 2147483647, 1, 1, 01); MaskDraftMove(2147483647, 2147483647)").unwrap();
        let _ = s.display_bytes(false, false, false);
    }

    #[test]
    fn repeat_restamps_with_the_live_symmetry_and_pattern() {
        let mut s = session();
        s.run_script("MaskStamp(0, 0, 1, 1, 01); AddFrame(); SetPrimaryColor(#00FF00FF); SetSymmetry(h,c,c); Repeat()").unwrap();
        assert_eq!(px(&s, 0, 0), RED, "the color is the commit's (ADR 0040)");
        assert_eq!(px(&s, 15, 0), RED, "symmetry is the one in force at Repeat time");
    }
}
