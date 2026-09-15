//! Frame-set batch verbs (ADR 0031; `docs/frames-page/DESIGN.md`) — the engine half of the
//! Frames page. Every verb here takes a [`FrameSet`], runs inside ONE `edit_doc` (one undo
//! record, one journal line, one replay tick), and is all-or-nothing: a set that reaches beyond
//! the roll, the 1024-frame cap, the 128-layer cap, or a delete that would empty the roll
//! **refuses** through [`Session::refuse`] and changes nothing. Three decided exceptions clamp
//! instead: a rigid shift clamps its delta to the room, a duration scale clamps into the
//! 16.6–1000 ms range, and a remove-by-name that would leave a frame empty substitutes a blank
//! layer.
//!
//! Policies shared by every verb:
//! - **The active target moves only when its frame is removed** (ADR 0013 applied to sets):
//!   creation, duplication, reordering, and retiming resolve the active frame by id afterwards.
//! - **The pixel-selection mask is never touched** — unlike the single-frame `FlipFrame` (mirrors
//!   it) and `RotateFrame` (clears it). One rule, undo-coherent, no special cases.
//! - **The Move group** clears only when the active frame's id or its active layer's id changed
//!   (the shipped single verbs' rule); vanished ids simply stop resolving.
//! - **No-ops record nothing** — `assert_undo_restores` demands that an undo changes the
//!   document, and a recorded no-op would make the Undo tile lie.
//! - **Not Repeatable** (ADR 0017): the nudge buttons repeat themselves.

use super::Session;
use crate::color::Rgba8;
use crate::document::{Document, Frame, Layer, DEFAULT_DURATION_US, MAX_FRAMES, MAX_LAYERS};
use crate::tool;

/// A canonical frame set: strictly ascending, deduplicated, never empty, every index below
/// `MAX_FRAMES`. Built only by [`FrameSet::parse`], so the invariants hold by construction.
///
/// Wire form (one DSL argument): whitespace-separated items, each `N` or `N-M` (inclusive,
/// 0-based like every other frame verb; the UI shows 1-based). `12-32 40`. Whitespace rather
/// than commas keeps the set one argument of the parser's comma splitter, so a free-text layer
/// name may trail it (`RemoveLayersNamed(12-32 40, Shading, v2)`).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FrameSet(Vec<usize>);

/// The index-set grammar shared by [`FrameSet`] and the layer set (ADR 0033): whitespace-separated
/// `N` / `N-M` items, any order and overlap, canonicalized (sorted, deduplicated). Errors: a bad
/// integer, a reversed range, an index at or beyond `cap` (which also bounds the expansion, so
/// `0-4294967295` can never allocate), and an empty set. `noun` names the axis in messages.
pub(super) fn parse_index_set(s: &str, cap: usize, noun: &str) -> Result<Vec<usize>, String> {
    let mut v: Vec<usize> = Vec::new();
    for tok in s.split_whitespace() {
        let (lo, hi) = match tok.split_once('-') {
            Some((a, b)) => (a, b),
            None => (tok, tok),
        };
        let lo: usize = lo.trim().parse().map_err(|_| format!("bad {} index '{}'", noun, tok))?;
        let hi: usize = hi.trim().parse().map_err(|_| format!("bad {} index '{}'", noun, tok))?;
        if lo > hi {
            return Err(format!("reversed {} range '{}'", noun, tok));
        }
        if hi >= cap {
            return Err(format!("{} index {} beyond the {}-{} cap", noun, hi, cap, noun));
        }
        v.extend(lo..=hi);
    }
    if v.is_empty() {
        return Err(format!("empty {} set", noun));
    }
    v.sort_unstable();
    v.dedup();
    Ok(v)
}

/// The canonical wire form of a sorted index list: maximal inclusive ranges, space-separated
/// (`12-32 40`).
pub(super) fn ranges_to_dsl(v: &[usize]) -> String {
    let mut out = String::new();
    let mut i = 0;
    while i < v.len() {
        let lo = v[i];
        let mut j = i;
        while j + 1 < v.len() && v[j + 1] == v[j] + 1 {
            j += 1;
        }
        if !out.is_empty() {
            out.push(' ');
        }
        if j == i {
            out.push_str(&lo.to_string());
        } else {
            out.push_str(&format!("{}-{}", lo, v[j]));
        }
        i = j + 1;
    }
    out
}

impl FrameSet {
    /// Parse the wire form (see [`parse_index_set`]; the cap is `MAX_FRAMES`).
    pub fn parse(s: &str) -> Result<FrameSet, String> {
        parse_index_set(s, MAX_FRAMES, "frame").map(FrameSet)
    }

    /// The member indices, ascending.
    pub fn indices(&self) -> &[usize] {
        &self.0
    }

    /// How many frames the set names (never zero).
    pub fn count(&self) -> usize {
        self.0.len()
    }

    pub fn first(&self) -> usize {
        self.0[0]
    }

    pub fn last(&self) -> usize {
        self.0[self.0.len() - 1]
    }

    pub fn contains(&self, i: usize) -> bool {
        self.0.binary_search(&i).is_ok()
    }

    /// The canonical wire form: maximal inclusive ranges, space-separated (`12-32 40`).
    pub fn to_dsl(&self) -> String {
        ranges_to_dsl(&self.0)
    }
}

/// A clone of `src` with fresh identities: a new frame id, then a new id per layer bottom→top —
/// the exact allocation order of `duplicate_frame`, kept fixed because journals replay and the
/// shell finds the copies by id afterwards.
fn freshen(doc: &mut Document, mut f: Frame) -> Frame {
    f.id = doc.new_frame_id();
    for l in &mut f.layers {
        l.id = doc.layer_ids.alloc();
    }
    f
}

/// A blank frame exactly as `AddFrame` makes one: the default duration, one "Layer 1".
fn blank_frame(doc: &mut Document) -> Frame {
    let layers = vec![doc.new_layer("Layer 1")];
    Frame { id: doc.new_frame_id(), duration_us: DEFAULT_DURATION_US, layers, active_layer: 0 }
}

/// The TOPMOST layer named `name` (highest stack index), exact and case-sensitive.
fn topmost_layer_named(f: &Frame, name: &str) -> Option<usize> {
    f.layers.iter().rposition(|l| l.name == name)
}

impl Session {
    /// Refuse when the set reaches beyond the roll. The first check of every batch verb (and of
    /// the layer set's cross-frame copy, ADR 0033).
    pub(super) fn frame_set_ok(&mut self, verb: &str, set: &FrameSet) -> bool {
        let n = self.doc.frames.len();
        if set.last() >= n {
            self.refuse(&format!(
                "{}: frame {} is out of range (the animation has {} frames)",
                verb,
                set.last() + 1,
                n
            ));
            return false;
        }
        true
    }

    /// Refuse when adding `added` frames would pass the frame cap.
    fn frame_cap_ok(&mut self, verb: &str, added: usize) -> bool {
        let n = self.doc.frames.len();
        if n + added > MAX_FRAMES {
            self.refuse(&format!(
                "{}: {} + {} frames would exceed the {}-frame cap",
                verb, n, added, MAX_FRAMES
            ));
            return false;
        }
        true
    }

    /// Re-resolve the active frame by id after a rebuild (ADR 0013), falling back to `or`.
    fn reactivate_by_id(&mut self, id: u32, or: usize) {
        let n = self.doc.frames.len();
        self.doc.active_frame = self.doc.frame_index_by_id(id).unwrap_or(or.min(n.saturating_sub(1)));
    }

    /// Whether every layer of every member is empty — the no-op guard of the content batches.
    fn members_all_empty(&self, set: &FrameSet) -> bool {
        set.indices().iter().all(|&j| self.doc.frames[j].layers.iter().all(|l| l.pixels.is_empty()))
    }

    // ---- structural ----

    /// Remove every member. Refused when the set covers every frame. The active target keeps its
    /// identity when it survives; when it was removed, the first survivor at or after its old
    /// index becomes active, else the last survivor — the single `remove_frame` rule whenever the
    /// set is one frame.
    pub fn remove_frames(&mut self, set: &FrameSet) {
        if !self.frame_set_ok("RemoveFrames", set) {
            return;
        }
        if set.count() >= self.doc.frames.len() {
            self.refuse("RemoveFrames: cannot delete every frame");
            return;
        }
        let active_before = self.doc.active_frame().id;
        self.edit_doc("remove_frames", |s| {
            let old_active = s.doc.active_frame;
            let old = std::mem::take(&mut s.doc.frames);
            let mut kept: Vec<Frame> = Vec::with_capacity(old.len() - set.count());
            let mut new_active: Option<usize> = None;
            for (j, f) in old.into_iter().enumerate() {
                if set.contains(j) {
                    continue;
                }
                if new_active.is_none() && j >= old_active {
                    new_active = Some(kept.len());
                }
                kept.push(f);
            }
            s.doc.active_frame = new_active.unwrap_or(kept.len() - 1);
            s.doc.frames = kept;
        });
        if self.doc.active_frame().id != active_before {
            self.clear_move_group(); // the active frame itself was removed
        }
    }

    /// Each member's copy lands right after its source (3,5 → 3,3′,5,5′), with fresh ids. The
    /// original stays active (by identity) — unlike the single `duplicate_frame`, which follows
    /// its copy: a batch is a remote control, not an activation.
    pub fn duplicate_frames(&mut self, set: &FrameSet) {
        if !self.frame_set_ok("DuplicateFrames", set) || !self.frame_cap_ok("DuplicateFrames", set.count()) {
            return;
        }
        let active = self.doc.active_frame().id;
        self.edit_doc("duplicate_frames", |s| {
            let old = std::mem::take(&mut s.doc.frames);
            let mut out: Vec<Frame> = Vec::with_capacity(old.len() + set.count());
            for (j, f) in old.into_iter().enumerate() {
                let copy = if set.contains(j) { Some(freshen(&mut s.doc, f.clone())) } else { None };
                out.push(f);
                if let Some(c) = copy {
                    out.push(c);
                }
            }
            s.doc.frames = out;
            s.reactivate_by_id(active, 0);
        });
    }

    /// Copies of the members, in order, as ONE contiguous block right after the last member
    /// ("loop this segment twice"). Fresh ids; the active target unchanged by identity.
    pub fn repeat_frames_after(&mut self, set: &FrameSet) {
        if !self.frame_set_ok("RepeatFramesAfter", set) || !self.frame_cap_ok("RepeatFramesAfter", set.count()) {
            return;
        }
        let active = self.doc.active_frame().id;
        self.edit_doc("repeat_frames_after", |s| {
            let mut block: Vec<Frame> = Vec::with_capacity(set.count());
            for &j in set.indices() {
                let f = s.doc.frames[j].clone();
                block.push(freshen(&mut s.doc, f));
            }
            let at = set.last() + 1;
            let tail = s.doc.frames.split_off(at);
            s.doc.frames.extend(block);
            s.doc.frames.extend(tail);
            s.reactivate_by_id(active, 0);
        });
    }

    /// One blank frame (default duration, one "Layer 1") before or after each member — a hold
    /// pattern. Cap-checked as a whole; the active target unchanged by identity.
    pub fn insert_blank_frames(&mut self, set: &FrameSet, after: bool) {
        if !self.frame_set_ok("InsertBlankFrames", set) || !self.frame_cap_ok("InsertBlankFrames", set.count()) {
            return;
        }
        let active = self.doc.active_frame().id;
        self.edit_doc("insert_blank_frames", |s| {
            let old = std::mem::take(&mut s.doc.frames);
            let mut out: Vec<Frame> = Vec::with_capacity(old.len() + set.count());
            for (j, f) in old.into_iter().enumerate() {
                let member = set.contains(j);
                if member && !after {
                    out.push(blank_frame(&mut s.doc));
                }
                out.push(f);
                if member && after {
                    out.push(blank_frame(&mut s.doc));
                }
            }
            s.doc.frames = out;
            s.reactivate_by_id(active, 0);
        });
    }

    /// Rigid shift: the members move as one body by `delta` slots (gaps kept, unselected frames
    /// flow around), the delta clamped so no member leaves the roll. A clamp to zero is a no-op
    /// with no record. The journal stores the requested delta; replay re-clamps identically.
    pub fn shift_frames(&mut self, set: &FrameSet, delta: i32) {
        if !self.frame_set_ok("ShiftFrames", set) {
            return;
        }
        let n = self.doc.frames.len() as i64;
        let k = (delta as i64).clamp(-(set.first() as i64), n - 1 - set.last() as i64);
        if k == 0 {
            return;
        }
        let active = self.doc.active_frame().id;
        self.edit_doc("shift_frames", |s| {
            let old = std::mem::take(&mut s.doc.frames);
            let n = old.len();
            let mut slots: Vec<Option<Frame>> = (0..n).map(|_| None).collect();
            let mut rest: Vec<Frame> = Vec::with_capacity(n - set.count());
            for (j, f) in old.into_iter().enumerate() {
                if set.contains(j) {
                    slots[(j as i64 + k) as usize] = Some(f); // distinct and in range by the clamp
                } else {
                    rest.push(f);
                }
            }
            let mut rest = rest.into_iter();
            // Every empty slot takes the next unselected frame in old order; the counts match by
            // construction (n slots, |S| placed, n − |S| in `rest`).
            s.doc.frames = slots.into_iter().filter_map(|slot| slot.or_else(|| rest.next())).collect();
            s.reactivate_by_id(active, 0);
        });
    }

    /// The occupants of the selected slots swap places: the slots stay, their contents reverse
    /// (on a discontiguous set too). Fewer than two members is a no-op with no record.
    pub fn reverse_frames(&mut self, set: &FrameSet) {
        if !self.frame_set_ok("ReverseFrames", set) || set.count() < 2 {
            return;
        }
        let active = self.doc.active_frame().id;
        self.edit_doc("reverse_frames", |s| {
            let idx = set.indices();
            let occupants: Vec<Frame> = idx.iter().map(|&j| s.doc.frames[j].clone()).collect();
            for (r, &j) in idx.iter().enumerate() {
                s.doc.frames[j] = occupants[idx.len() - 1 - r].clone();
            }
            s.reactivate_by_id(active, 0);
        });
    }

    // ---- durations ----

    /// One duration (clamped to the engine range) on every member; no-op when all already hold it.
    pub fn set_frame_durations(&mut self, set: &FrameSet, us: u32) {
        if !self.frame_set_ok("SetFrameDurations", set) {
            return;
        }
        let d = Document::clamp_duration(us);
        if set.indices().iter().all(|&j| self.doc.frames[j].duration_us == d) {
            return;
        }
        self.edit_doc("set_frame_durations", |s| {
            for &j in set.indices() {
                s.doc.frames[j].duration_us = d;
            }
        });
    }

    /// Scale every member's duration by `permille` / 1000 (rounded half up, integer math), then
    /// clamp. Frames pinned by the clamp are the shell's to report; no-op when nothing changes.
    pub fn scale_frame_durations(&mut self, set: &FrameSet, permille: u32) {
        if !self.frame_set_ok("ScaleFrameDurations", set) {
            return;
        }
        let scaled = |us: u32| -> u32 {
            let v = (us as u64 * permille as u64 + 500) / 1000;
            Document::clamp_duration(v.min(u32::MAX as u64) as u32)
        };
        if set.indices().iter().all(|&j| scaled(self.doc.frames[j].duration_us) == self.doc.frames[j].duration_us) {
            return;
        }
        self.edit_doc("scale_frame_durations", |s| {
            for &j in set.indices() {
                let f = &mut s.doc.frames[j];
                f.duration_us = scaled(f.duration_us);
            }
        });
    }

    // ---- content (whole frame, every layer, storage-wide; the mask untouched) ----

    /// Mirror every layer of every member across the X axis (`horizontal`) or the Y axis — the
    /// storage-wide loop of `flip_frame`, per member, in one record.
    pub fn flip_frames(&mut self, set: &FrameSet, horizontal: bool) {
        if !self.frame_set_ok(if horizontal { "FlipFramesH" } else { "FlipFramesV" }, set) {
            return;
        }
        if self.members_all_empty(set) {
            return;
        }
        let storage = self.doc.storage();
        let (w, h) = (storage.w as i32, storage.h as i32);
        self.edit_doc("flip_frames", |s| {
            for &j in set.indices() {
                for l in &mut s.doc.frames[j].layers {
                    super::canvas::flip_storage(&mut l.pixels, w, h, horizontal);
                }
            }
        });
    }

    /// Rotate every layer of every member by `quarter_turns` × 90° clockwise about the storage
    /// center (non-square canvases park the overhang in the gutter, as `rotate_frame` does). Runs
    /// one frame-scope rotate draft per member through the same resampler as the single verb, so
    /// the result is byte-identical; the Repeat record is untouched (batches are not Repeatable).
    pub fn rotate_frames(&mut self, set: &FrameSet, quarter_turns: u8) {
        let q = quarter_turns % 4;
        if !self.frame_set_ok("RotateFrames", set) || q == 0 || self.members_all_empty(set) {
            return;
        }
        let (cw, ch) = {
            let s = self.doc.storage();
            (s.w as i32, s.h as i32)
        };
        self.edit_doc("rotate_frames", |s| {
            for &j in set.indices() {
                let mut d = s.frame_rotate_draft(j);
                d.angle = super::canvas::quarter_turn_mrad(q) as f32 / 1000.0; // = rotate_draft_set_angle
                super::canvas::apply_rotation_to_frame(&d, &mut s.doc.frames[j], cw, ch);
            }
        });
    }

    /// Apply a per-pixel color transform to every layer of every member (`InvertFrames` passes
    /// `color::invert`) — the `map_frame` body per member, in one record.
    pub fn map_frames(&mut self, set: &FrameSet, f: impl Fn(Rgba8) -> Rgba8) {
        if !self.frame_set_ok("InvertFrames", set) || self.members_all_empty(set) {
            return;
        }
        self.edit_doc("map_frames", |s| {
            for &j in set.indices() {
                for l in &mut s.doc.frames[j].layers {
                    tool::map_region(&mut l.pixels, None, &f);
                }
            }
        });
    }

    // ---- layers across frames ----

    /// The strict twin of `DuplicateLayerToFrames`: a copy of the active frame's active layer
    /// pushed on top of every member's stack, refused as a whole when any member already holds
    /// the layer cap. The active frame in the set gets a copy of its own layer (the artist chose
    /// it); the active target is unchanged.
    pub fn copy_layer_to_frames(&mut self, set: &FrameSet) {
        if !self.frame_set_ok("CopyLayerToFrames", set) {
            return;
        }
        if let Some(&j) = set.indices().iter().find(|&&j| self.doc.frames[j].layers.len() >= MAX_LAYERS) {
            self.refuse(&format!("CopyLayerToFrames: frame {} already has {} layers", j + 1, MAX_LAYERS));
            return;
        }
        let src = self.doc.active_frame().active_layer().clone();
        self.edit_doc("copy_layer_to_frames", |s| {
            for &j in set.indices() {
                let mut copy = src.clone();
                copy.id = s.doc.layer_ids.alloc();
                s.doc.frames[j].layers.push(copy);
            }
        });
    }

    /// Remove the topmost layer named `name` from every member that has one (exact,
    /// case-sensitive). A frame that would be left empty gets a blank "Layer 1" instead, which
    /// becomes its active layer; otherwise the frame's active layer follows identity, else clamps
    /// to the same index (the `remove_layer` rule). No hit anywhere is a no-op with no record.
    pub fn remove_layers_named(&mut self, set: &FrameSet, name: &str) {
        if !self.frame_set_ok("RemoveLayersNamed", set) {
            return;
        }
        let hits: Vec<(usize, usize)> = set
            .indices()
            .iter()
            .filter_map(|&j| topmost_layer_named(&self.doc.frames[j], name).map(|li| (j, li)))
            .collect();
        if hits.is_empty() {
            return;
        }
        let active_layer_before = self.doc.active_frame().active_layer().id;
        self.edit_doc("remove_layers_named", |s| {
            for &(fi, li) in &hits {
                let fresh = if s.doc.frames[fi].layers.len() == 1 {
                    let id = s.doc.layer_ids.alloc();
                    Some(Layer::new(id, s.doc.storage(), "Layer 1"))
                } else {
                    None
                };
                let f = &mut s.doc.frames[fi];
                let active_id = f.layers[f.active_layer].id;
                f.layers.remove(li);
                match fresh {
                    Some(blank) => {
                        f.layers.push(blank);
                        f.active_layer = 0;
                    }
                    None => {
                        let n = f.layers.len();
                        f.active_layer = f
                            .layers
                            .iter()
                            .position(|l| l.id == active_id)
                            .unwrap_or(f.active_layer.min(n - 1));
                    }
                }
            }
        });
        if self.doc.active_frame().active_layer().id != active_layer_before {
            self.clear_move_group(); // the active frame's active layer was the one removed
        }
    }

    /// Set the visible flag on the topmost layer named `name` of every member that has one; a
    /// no-op with no record when no hit differs.
    pub fn set_layers_visible_named(&mut self, set: &FrameSet, visible: bool, name: &str) {
        if !self.frame_set_ok("SetLayersVisibleNamed", set) {
            return;
        }
        let hits = self.differing_hits(set, name, |l| l.visible != visible);
        if hits.is_empty() {
            return;
        }
        self.edit_doc("set_layers_visible_named", |s| {
            for &(fi, li) in &hits {
                s.doc.frames[fi].layers[li].visible = visible;
            }
        });
    }

    /// Set the locked flag on the topmost layer named `name` of every member that has one; a
    /// no-op with no record when no hit differs.
    pub fn set_layers_locked_named(&mut self, set: &FrameSet, locked: bool, name: &str) {
        if !self.frame_set_ok("SetLayersLockedNamed", set) {
            return;
        }
        let hits = self.differing_hits(set, name, |l| l.locked != locked);
        if hits.is_empty() {
            return;
        }
        self.edit_doc("set_layers_locked_named", |s| {
            for &(fi, li) in &hits {
                s.doc.frames[fi].layers[li].locked = locked;
            }
        });
    }

    /// `(frame, layer)` of every member's topmost layer named `name` for which `differs` holds.
    fn differing_hits(&self, set: &FrameSet, name: &str, differs: impl Fn(&Layer) -> bool) -> Vec<(usize, usize)> {
        set.indices()
            .iter()
            .filter_map(|&j| {
                let f = &self.doc.frames[j];
                topmost_layer_named(f, name).filter(|&li| differs(&f.layers[li])).map(|li| (j, li))
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::color::Rgba8;

    fn set(s: &str) -> FrameSet {
        FrameSet::parse(s).unwrap()
    }

    /// A session with `n` frames, frame `i` painted white at (i, 0) on its first layer.
    fn roll(n: usize) -> Session {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        for i in 0..n {
            if i > 0 {
                s.add_frame();
            }
            s.tap(i as i32, 0);
        }
        s.set_active_frame(0);
        s
    }

    fn ids(s: &Session) -> Vec<u32> {
        s.doc.frames.iter().map(|f| f.id).collect()
    }

    fn undo_len(s: &Session) -> usize {
        s.doc.history.undo.len()
    }

    // ---- the set grammar ----

    #[test]
    fn frame_set_parses_ranges_and_canonicalizes() {
        assert_eq!(set("3 1-2 2 5-5").indices(), &[1, 2, 3, 5]);
        assert_eq!(set("3 1-2 2 5-5").to_dsl(), "1-3 5");
        assert_eq!(set("12-32 40").to_dsl(), "12-32 40");
        assert_eq!(set("0").to_dsl(), "0");
        assert_eq!(set("  7   9  ").indices(), &[7, 9]);
        assert!(set("1-3").contains(2));
        assert!(!set("1-3").contains(4));
        assert_eq!((set("4-6").first(), set("4-6").last(), set("4-6").count()), (4, 6, 3));
    }

    #[test]
    fn frame_set_rejects_bad_input() {
        for bad in ["", "   ", "5-3", "1,2", "1024", "0-1024", "-1", "3-", "x", "1-2-3"] {
            assert!(FrameSet::parse(bad).is_err(), "'{}' must not parse", bad);
        }
    }

    // ---- refusals ----

    #[test]
    fn out_of_range_set_refuses_the_whole_verb() {
        let mut s = roll(4);
        let before = s.doc.content_hash();
        let records = undo_len(&s);
        let (seq0, _) = s.refusal_state();
        s.run_script("RemoveFrames(1 9)").unwrap();
        assert_eq!(s.doc.content_hash(), before, "nothing changed");
        assert_eq!(undo_len(&s), records, "no record");
        let (seq1, why) = s.refusal_state();
        assert_eq!(seq1, seq0 + 1);
        assert!(why.unwrap().contains("frame 10 is out of range"), "{:?}", why);
        assert!(s.state_json().contains("\"refusal_seq\":1"));
        assert!(s.state_json().contains("\"last_refusal\":\"RemoveFrames"));
    }

    #[test]
    fn remove_frames_refuses_to_empty_the_roll() {
        let mut s = roll(3);
        s.run_script("RemoveFrames(0-2)").unwrap();
        assert_eq!(s.doc.frames.len(), 3);
        assert!(s.refusal_state().1.unwrap().contains("every frame"));
    }

    #[test]
    fn duplicate_frames_refuses_past_the_cap() {
        let mut s = Session::new(4, 4);
        // 1 → 1024 by doubling.
        while s.doc.frames.len() < MAX_FRAMES {
            let n = s.doc.frames.len();
            let add = (MAX_FRAMES - n).min(n);
            s.run_script(&format!("DuplicateFrames(0-{})", add - 1)).unwrap();
        }
        assert_eq!(s.doc.frames.len(), MAX_FRAMES);
        let (seq0, _) = s.refusal_state();
        s.run_script("DuplicateFrames(0)").unwrap();
        assert_eq!(s.doc.frames.len(), MAX_FRAMES);
        assert_eq!(s.refusal_state().0, seq0 + 1);
        assert!(s.refusal_state().1.unwrap().contains("1024-frame cap"));
    }

    // ---- remove ----

    #[test]
    fn remove_frames_keeps_the_active_frame_by_identity() {
        let mut s = roll(6);
        s.set_active_frame(4);
        let active = s.doc.active_frame().id;
        let records = undo_len(&s);
        s.run_script("RemoveFrames(1-2 5)").unwrap();
        assert_eq!(s.doc.frames.len(), 3);
        assert_eq!(s.doc.active_frame().id, active);
        assert_eq!(s.doc.active_frame, 2);
        assert_eq!(undo_len(&s), records + 1, "one record");
        assert!(s.assert_undo_restores());
    }

    #[test]
    fn remove_frames_lands_on_the_first_survivor_after_the_removed_active() {
        let mut s = roll(6);
        s.set_active_frame(2);
        let want = s.doc.frames[4].id;
        s.run_script("RemoveFrames(1-3)").unwrap();
        assert_eq!(s.doc.active_frame().id, want);
        assert_eq!(s.doc.active_frame, 1);
    }

    #[test]
    fn remove_frames_lands_on_the_last_survivor_when_nothing_follows() {
        let mut s = roll(5);
        s.set_active_frame(4);
        let want = s.doc.frames[1].id;
        s.run_script("RemoveFrames(2-4)").unwrap();
        assert_eq!(s.doc.active_frame().id, want);
        assert_eq!(s.doc.active_frame, 1);
    }

    #[test]
    fn remove_frames_matches_the_single_verb_for_one_member() {
        for active in 0..5 {
            for victim in 0..5 {
                let mut a = roll(5);
                a.set_active_frame(active);
                a.remove_frame(victim);
                let mut b = roll(5);
                b.set_active_frame(active);
                b.run_script(&format!("RemoveFrames({})", victim)).unwrap();
                assert_eq!(ids(&a), ids(&b), "active {} victim {}", active, victim);
                assert_eq!(a.doc.active_frame, b.doc.active_frame, "active {} victim {}", active, victim);
            }
        }
    }

    // ---- duplicate / repeat / insert ----

    #[test]
    fn duplicate_frames_copies_right_after_each_source_with_fresh_ids() {
        let mut s = roll(4);
        s.set_active_frame(3);
        let before = ids(&s);
        s.run_script("DuplicateFrames(0 2)").unwrap();
        let after = ids(&s);
        assert_eq!(after.len(), 6);
        assert_eq!([after[0], after[2], after[3], after[5]], [before[0], before[1], before[2], before[3]]);
        assert!(!before.contains(&after[1]) && !before.contains(&after[4]), "fresh frame ids");
        assert_ne!(s.doc.frames[0].layers[0].id, s.doc.frames[1].layers[0].id, "fresh layer ids");
        assert_eq!(s.pixel(1, 0, 0, 0), Rgba8::WHITE, "the copy carries the pixels");
        assert_eq!(s.doc.active_frame().id, before[3], "the original stays active");
        assert_eq!(s.doc.active_frame, 5);
        assert!(s.assert_undo_restores());
    }

    #[test]
    fn repeat_frames_after_appends_one_block_after_the_last_member() {
        let mut s = roll(5);
        let before = ids(&s);
        s.run_script("RepeatFramesAfter(1 3)").unwrap();
        let after = ids(&s);
        assert_eq!(after.len(), 7);
        assert_eq!(&after[..4], &before[..4]);
        assert_eq!(after[6], before[4]);
        assert_eq!(s.pixel(4, 0, 1, 0), Rgba8::WHITE, "block[0] copies frame 1");
        assert_eq!(s.pixel(5, 0, 3, 0), Rgba8::WHITE, "block[1] copies frame 3");
        assert!(s.assert_undo_restores());
    }

    #[test]
    fn insert_blank_frames_before_and_after() {
        let mut s = roll(3);
        let before = ids(&s);
        s.run_script("InsertBlankFrames(0 2, after)").unwrap();
        assert_eq!(s.doc.frames.len(), 5);
        assert_eq!([ids(&s)[0], ids(&s)[2], ids(&s)[3]], [before[0], before[1], before[2]]);
        assert!(s.doc.frames[1].layers[0].pixels.is_empty());
        assert_eq!(s.doc.frames[1].duration_us, DEFAULT_DURATION_US);
        assert_eq!(s.doc.frames[1].layers[0].name, "Layer 1");
        let mut t = roll(3);
        t.run_script("InsertBlankFrames(1, before)").unwrap();
        assert_eq!(t.doc.frames.len(), 4);
        assert_eq!(ids(&t)[2], before[1]);
        assert!(t.run_script("InsertBlankFrames(1, sideways)").is_err());
        assert!(s.assert_undo_restores());
    }

    // ---- shift / reverse ----

    #[test]
    fn shift_frames_moves_the_set_as_a_rigid_body() {
        let mut s = roll(8);
        let b = ids(&s);
        s.run_script("ShiftFrames(1 3, 2)").unwrap();
        let want: Vec<u32> = [0, 2, 4, 1, 5, 3, 6, 7].iter().map(|&i| b[i]).collect();
        assert_eq!(ids(&s), want);
        assert_eq!(s.doc.active_frame().id, b[0]);
        assert!(s.assert_undo_restores());
    }

    #[test]
    fn shift_frames_clamps_to_the_room() {
        let mut s = roll(8);
        let b = ids(&s);
        s.run_script("ShiftFrames(1 3, 10)").unwrap(); // k = 4
        let want: Vec<u32> = [0, 2, 4, 5, 6, 1, 7, 3].iter().map(|&i| b[i]).collect();
        assert_eq!(ids(&s), want);
        let mut t = roll(8);
        t.run_script("ShiftFrames(1 3, -5)").unwrap(); // k = -1
        let want: Vec<u32> = [1, 0, 3, 2, 4, 5, 6, 7].iter().map(|&i| b[i]).collect();
        assert_eq!(ids(&t), want);
    }

    #[test]
    fn shift_frames_clamped_to_zero_records_nothing() {
        let mut s = roll(4);
        let n = undo_len(&s);
        s.run_script("ShiftFrames(0-1, -3)").unwrap();
        assert_eq!(undo_len(&s), n);
        s.run_script("ShiftFrames(3, 1)").unwrap();
        assert_eq!(undo_len(&s), n);
        assert_eq!(s.refusal_state().0, 0, "a clamp is not a refusal");
    }

    #[test]
    fn reverse_frames_swaps_the_occupants_of_the_selected_slots() {
        let mut s = roll(6);
        let b = ids(&s);
        s.run_script("ReverseFrames(1 4-5)").unwrap();
        let want: Vec<u32> = [0, 5, 2, 3, 4, 1].iter().map(|&i| b[i]).collect();
        assert_eq!(ids(&s), want);
        let n = undo_len(&s);
        s.run_script("ReverseFrames(2)").unwrap();
        assert_eq!(undo_len(&s), n, "one member is a no-op");
        assert!(s.assert_undo_restores());
    }

    // ---- durations ----

    #[test]
    fn set_and_scale_frame_durations_clamp_round_and_skip_noops() {
        let mut s = roll(4);
        s.run_script("SetFrameDurations(0-3, 33.333)").unwrap();
        assert!(s.doc.frames.iter().all(|f| f.duration_us == 33_333));
        let n = undo_len(&s);
        s.run_script("SetFrameDurations(1-2, 33.333)").unwrap();
        assert_eq!(undo_len(&s), n, "already equal → no record");
        s.run_script("ScaleFrameDurations(0-3, 1500)").unwrap();
        assert!(s.doc.frames.iter().all(|f| f.duration_us == 50_000), "33333 × 1.5 rounds to 50000");
        s.run_script("ScaleFrameDurations(0-1, 100)").unwrap();
        assert_eq!(s.doc.frames[0].duration_us, crate::document::MIN_DURATION_US, "pinned at the floor");
        assert_eq!(s.doc.frames[2].duration_us, 50_000);
        s.run_script("SetFrameDurations(3, 5000)").unwrap();
        assert_eq!(s.doc.frames[3].duration_us, crate::document::MAX_DURATION_US);
        let n = undo_len(&s);
        s.run_script("ScaleFrameDurations(3, 4294967295)").unwrap();
        assert_eq!(undo_len(&s), n, "already at the ceiling → no record, no overflow");
        assert!(s.assert_undo_restores());
    }

    // ---- content ----

    #[test]
    fn flip_and_invert_frames_match_the_single_verbs_per_frame() {
        for verb in ["FlipFramesH", "FlipFramesV", "InvertFrames"] {
            let build = || {
                let mut s = roll(3);
                s.add_layer();
                s.settings.primary = Rgba8::rgb(200, 30, 60);
                s.tap(5, 7);
                s.set_active_frame(0);
                s
            };
            let mut a = build();
            let mut b = build();
            a.run_script(&format!("{}(0 2)", verb)).unwrap();
            for fi in [0usize, 2] {
                b.set_active_frame(fi);
                b.run_script(match verb {
                    "FlipFramesH" => "FlipFrameH()",
                    "FlipFramesV" => "FlipFrameV()",
                    _ => "InvertFrame()",
                })
                .unwrap();
            }
            for fi in 0..3 {
                assert_eq!(
                    a.doc.frames[fi].content_hash(),
                    b.doc.frames[fi].content_hash(),
                    "{} frame {}",
                    verb,
                    fi
                );
            }
            assert_eq!(a.doc.active_frame, 0, "{}: the active target did not move", verb);
            assert!(a.assert_undo_restores(), "{}", verb);
        }
    }

    #[test]
    fn rotate_frames_is_byte_identical_to_rotate_frame() {
        for clean_edge in [false, true] {
            for q in 1..=3u8 {
                let build = || {
                    let mut s = Session::new(12, 8);
                    s.settings.clean_edge = clean_edge;
                    s.settings.primary = Rgba8::WHITE;
                    s.tap(0, 0);
                    s.tap(11, 7);
                    s.add_layer();
                    s.settings.primary = Rgba8::rgb(255, 0, 0);
                    s.tap(3, 2);
                    s.add_frame();
                    s.tap(6, 6);
                    s.set_active_frame(0);
                    s
                };
                let mut batch = build();
                batch.run_script(&format!("RotateFrames(0-1, {})", q)).unwrap();
                let mut single = build();
                for fi in 0..2 {
                    single.set_active_frame(fi);
                    single.rotate_frame(q);
                }
                for fi in 0..2 {
                    assert_eq!(
                        batch.doc.frames[fi].content_hash(),
                        single.doc.frames[fi].content_hash(),
                        "q={} clean_edge={} frame {}",
                        q,
                        clean_edge,
                        fi
                    );
                }
                assert!(!batch.can_repeat(), "a batch rotation is not Repeatable");
                assert!(batch.assert_undo_restores());
            }
        }
    }

    #[test]
    fn content_batches_leave_the_selection_mask_alone() {
        let mut s = roll(2);
        s.run_script("SelectAll()").unwrap();
        let mask = s.doc.selection.clone().unwrap();
        s.run_script("FlipFramesH(0-1)\nRotateFrames(0-1, 1)\nInvertFrames(0-1)").unwrap();
        assert!(std::sync::Arc::ptr_eq(&mask, s.doc.selection.as_ref().unwrap()));
    }

    #[test]
    fn empty_content_batches_record_nothing() {
        let mut s = Session::new(8, 8);
        s.add_frame();
        let n = undo_len(&s);
        s.run_script("FlipFramesH(0-1)\nRotateFrames(0-1, 1)\nInvertFrames(0-1)").unwrap();
        assert_eq!(undo_len(&s), n);
    }

    // ---- layers by name ----

    #[test]
    fn copy_layer_to_frames_is_strict_and_copies_on_top() {
        let mut s = roll(3);
        s.run_script("RenameLayer(0, Shading, v2)").unwrap();
        s.run_script("CopyLayerToFrames(0-2)").unwrap();
        for fi in 0..3 {
            assert_eq!(s.doc.frames[fi].layers.len(), 2);
            assert_eq!(s.doc.frames[fi].layers[1].name, "Shading, v2");
        }
        assert_eq!(s.pixel(2, 1, 0, 0), Rgba8::WHITE, "frame 2 got frame 0's pixels on top");
        assert_eq!(s.doc.active_frame().active_layer, 0, "the active target did not move");
        assert!(s.assert_undo_restores());
        // Fill frame 1 to the cap, then the batch refuses as a whole.
        s.set_active_frame(1);
        while s.doc.frames[1].layers.len() < MAX_LAYERS {
            s.add_layer();
        }
        s.set_active_frame(0);
        let n = undo_len(&s);
        s.run_script("CopyLayerToFrames(0-2)").unwrap();
        assert_eq!(undo_len(&s), n);
        assert_eq!(s.doc.frames[0].layers.len(), 2, "nothing copied anywhere");
        assert!(s.refusal_state().1.unwrap().contains("frame 2 already has 128 layers"));
    }

    #[test]
    fn remove_layers_named_hits_the_topmost_and_substitutes_a_blank() {
        let mut s = roll(3);
        // Frame 0: [Layer 1, Sky, Sky] → the topmost Sky goes. Frame 1: [Sky] alone → blank.
        // Frame 2: no Sky → untouched.
        s.run_script("AddLayer()\nRenameLayer(1, Sky)\nAddLayer()\nRenameLayer(2, Sky)").unwrap();
        s.set_active_frame(1);
        s.run_script("RenameLayer(0, Sky)").unwrap();
        s.set_active_frame(0);
        s.set_active_layer(2);
        let top_id = s.doc.frames[0].layers[2].id;
        let mid_id = s.doc.frames[0].layers[1].id;
        s.run_script("RemoveLayersNamed(0-2, Sky)").unwrap();
        assert_eq!(s.doc.frames[0].layers.len(), 2);
        assert_eq!(s.doc.frames[0].layers[1].id, mid_id, "the topmost hit was removed");
        assert!(s.doc.frames[0].layers.iter().all(|l| l.id != top_id));
        assert_eq!(s.doc.frames[0].active_layer, 1, "active clamps to the same index");
        let f1 = &s.doc.frames[1];
        assert_eq!(f1.layers.len(), 1);
        assert_eq!(f1.layers[0].name, "Layer 1");
        assert!(f1.layers[0].visible && !f1.layers[0].locked && f1.layers[0].opacity == 255);
        assert!(f1.layers[0].pixels.is_empty(), "a fresh blank replaced the last layer");
        assert_eq!(f1.active_layer, 0);
        assert_eq!(s.doc.frames[2].layers.len(), 1, "no hit → untouched");
        assert!(s.assert_undo_restores());
        let n = undo_len(&s);
        s.run_script("RemoveLayersNamed(0-2, Nope)").unwrap();
        assert_eq!(undo_len(&s), n, "zero hits → no record");
    }

    #[test]
    fn set_layers_visible_and_locked_named_skip_noops() {
        let mut s = roll(3);
        s.run_script("RenameLayer(0, A)").unwrap();
        s.set_active_frame(2);
        s.run_script("RenameLayer(0, A)").unwrap();
        s.set_active_frame(0);
        s.run_script("SetLayersVisibleNamed(0-2, 0, A)").unwrap();
        assert!(!s.doc.frames[0].layers[0].visible && s.doc.frames[1].layers[0].visible && !s.doc.frames[2].layers[0].visible);
        let n = undo_len(&s);
        s.run_script("SetLayersVisibleNamed(0-2, false, A)").unwrap();
        assert_eq!(undo_len(&s), n, "no hit differs → no record");
        s.run_script("SetLayersLockedNamed(0 2, 1, A)").unwrap();
        assert!(s.doc.frames[0].layers[0].locked && s.doc.frames[2].layers[0].locked);
        assert!(s.run_script("SetLayersLockedNamed(0, maybe, A)").is_err());
        assert!(s.assert_undo_restores());
    }

    #[test]
    fn a_refusing_script_replays_identically() {
        let script = "RemoveFrames(1 9)\nDuplicateFrames(0-1)\nShiftFrames(0, 5)\nRemoveFrames(0-4)";
        let mut a = roll(3);
        a.run_script(script).unwrap();
        let mut b = roll(3);
        b.run_script(script).unwrap();
        assert_eq!(a.doc.content_hash(), b.doc.content_hash());
        assert_eq!(a.refusal_state().0, b.refusal_state().0);
        assert_eq!(a.refusal_state().0, 2, "two refusals: out of range, cover-all");
    }
}
