//! Layer-set batch verbs (ADR 0033; `docs/layers-page/DESIGN.md`) — the engine half of the
//! Layers page. Every verb here takes a [`LayerSet`] over the **active frame's** stack, runs
//! inside ONE `edit_frame` (one undo record, one journal line, one replay tick; the cross-frame
//! copy uses `edit_doc`), and is all-or-nothing: a set that reaches beyond the stack, the
//! 128-layer cap, a Merge set with a gap, or a content batch over a locked member **refuses**
//! through [`Session::refuse`] and changes nothing. Two decided exceptions: a rigid shift clamps
//! its delta to the room, and a delete that covers every layer substitutes one blank layer.
//!
//! Policies shared by every verb (the Frames page's, applied to a stack):
//! - **The active layer moves only when its layer is removed or merged away** (ADR 0013): the
//!   other batches resolve it by id afterwards. A removed active layer yields to the layer now at
//!   the same index, clamped (the single `remove_layer` rule); a merged-away one to the survivor.
//! - **The pixel-selection mask is never touched.**
//! - **The lock guards pixels**: Flip, Rotate, Invert, Clear and Merge refuse a locked member;
//!   property, structural and cross-frame batches pass through, as the single verbs allow.
//! - **The Move group** clears when the stack's membership changed (the single `add_layer` /
//!   `duplicate_layer` / `merge_down` rule) or the active layer's id changed; a reorder keeps it
//!   (the group is held by id).
//! - **No-ops record nothing**; **not Repeatable** (ADR 0017).

use super::frames::{parse_index_set, ranges_to_dsl};
use super::{FrameSet, Session};
use crate::color::Rgba8;
use crate::document::{BlendMode, Layer, MAX_LAYERS};
use crate::tool;

/// A canonical layer set of the active frame: strictly ascending, deduplicated, never empty,
/// every index below `MAX_LAYERS`. **0-based bottom-first on the wire** like every layer verb
/// (the UI counts the bottom layer as 1). Same grammar as [`FrameSet`]: `0-3 7`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LayerSet(Vec<usize>);

impl LayerSet {
    pub fn parse(s: &str) -> Result<LayerSet, String> {
        parse_index_set(s, MAX_LAYERS, "layer").map(LayerSet)
    }

    pub fn indices(&self) -> &[usize] {
        &self.0
    }

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

    /// One unbroken run of indices (no gap) — what Merge needs.
    pub fn is_contiguous(&self) -> bool {
        self.last() - self.first() + 1 == self.0.len()
    }

    pub fn to_dsl(&self) -> String {
        ranges_to_dsl(&self.0)
    }
}

impl Session {
    /// Refuse when the set reaches beyond the active frame's stack. The first check of every verb.
    fn layer_set_ok(&mut self, verb: &str, set: &LayerSet) -> bool {
        let n = self.doc.active_frame().layers.len();
        if set.last() >= n {
            self.refuse(&format!(
                "{}: layer {} is out of range (the frame has {} layers)",
                verb,
                set.last() + 1,
                n
            ));
            return false;
        }
        true
    }

    /// Refuse when adding `added` layers to the active frame would pass the cap.
    fn layer_cap_ok(&mut self, verb: &str, added: usize) -> bool {
        let n = self.doc.active_frame().layers.len();
        if n + added > MAX_LAYERS {
            self.refuse(&format!("{}: {} + {} layers would exceed the {}-layer cap", verb, n, added, MAX_LAYERS));
            return false;
        }
        true
    }

    /// Refuse a content batch (or Merge) over a locked member: the lock guards pixels.
    fn no_locked_members(&mut self, verb: &str, set: &LayerSet) -> bool {
        let locked = set.indices().iter().filter(|&&i| self.doc.active_frame().layers[i].locked).count();
        if locked > 0 {
            self.refuse(&format!(
                "{}: {} selected layer{} locked — unlock {} first",
                verb,
                locked,
                if locked == 1 { " is" } else { "s are" },
                if locked == 1 { "it" } else { "them" }
            ));
            return false;
        }
        true
    }

    /// Whether every member is empty — the no-op guard of the content batches.
    fn layer_members_all_empty(&self, set: &LayerSet) -> bool {
        set.indices().iter().all(|&i| self.doc.active_frame().layers[i].pixels.is_empty())
    }

    /// Re-resolve the active layer by id after a rebuild, falling back to `or` (clamped).
    fn reactivate_layer_by_id(&mut self, id: u32, or: usize) {
        let f = self.doc.active_frame_mut();
        let n = f.layers.len();
        f.active_layer = f.layers.iter().position(|l| l.id == id).unwrap_or(or.min(n.saturating_sub(1)));
    }

    fn active_layer_id(&self) -> u32 {
        self.doc.active_frame().active_layer().id
    }

    // ---- structural ----

    /// Remove every member. When the set covers the whole stack, one blank "Layer 1" replaces
    /// it (the `RemoveLayersNamed` rule) and becomes active. Otherwise the active layer keeps its
    /// identity when it survives, else the layer now at its old index (clamped) — the single
    /// `remove_layer` rule.
    pub fn remove_layers(&mut self, set: &LayerSet) {
        if !self.layer_set_ok("RemoveLayers", set) {
            return;
        }
        let active_before = self.active_layer_id();
        if set.count() >= self.doc.active_frame().layers.len() {
            self.edit_frame(|s| {
                let blank = s.doc.new_layer("Layer 1");
                let f = s.doc.active_frame_mut();
                f.layers = vec![blank];
                f.active_layer = 0;
            });
        } else {
            self.edit_frame(|s| {
                let f = s.doc.active_frame_mut();
                let old_active = f.active_layer;
                let old = std::mem::take(&mut f.layers);
                f.layers = old.into_iter().enumerate().filter(|(i, _)| !set.contains(*i)).map(|(_, l)| l).collect();
                let n = f.layers.len();
                f.active_layer =
                    f.layers.iter().position(|l| l.id == active_before).unwrap_or(old_active.min(n - 1));
            });
        }
        if self.active_layer_id() != active_before {
            self.clear_move_group();
        }
    }

    /// Each member's copy lands right above its source, named "<name> copy" (the single
    /// `duplicate_layer` rule) with a fresh id. The original stays active by identity.
    pub fn duplicate_layers(&mut self, set: &LayerSet) {
        if !self.layer_set_ok("DuplicateLayers", set) || !self.layer_cap_ok("DuplicateLayers", set.count()) {
            return;
        }
        let active = self.active_layer_id();
        self.edit_frame(|s| {
            let old = std::mem::take(&mut s.doc.active_frame_mut().layers);
            let mut out: Vec<Layer> = Vec::with_capacity(old.len() + set.count());
            for (i, l) in old.into_iter().enumerate() {
                let copy = if set.contains(i) {
                    let mut c = l.clone();
                    c.id = s.doc.layer_ids.alloc();
                    c.name = format!("{} copy", c.name);
                    Some(c)
                } else {
                    None
                };
                out.push(l);
                if let Some(c) = copy {
                    out.push(c);
                }
            }
            s.doc.active_frame_mut().layers = out;
            s.reactivate_layer_by_id(active, 0);
        });
        self.clear_move_group();
    }

    /// Merge one contiguous run top-down into its bottom member — repeated `merge_down` inside
    /// the run, so byte-identical to doing it by hand: a hidden or opacity-0 member contributes
    /// nothing, every other composites with its own blend and opacity; the survivor keeps its id
    /// and properties. Refused on a gap or a locked member; one member is a no-op.
    pub fn merge_layers(&mut self, set: &LayerSet) {
        if !self.layer_set_ok("MergeLayers", set) {
            return;
        }
        if !set.is_contiguous() {
            self.refuse("MergeLayers: the selection has a gap — Merge needs one contiguous run");
            return;
        }
        if !self.no_locked_members("MergeLayers", set) || set.count() < 2 {
            return;
        }
        let active = self.active_layer_id();
        let survivor = self.doc.active_frame().layers[set.first()].id;
        let st = self.doc.storage();
        let (w, h) = (st.w as i32, st.h as i32);
        self.edit_frame(|s| {
            let f = s.doc.active_frame_mut();
            for i in (set.first() + 1..=set.last()).rev() {
                let src = f.layers.remove(i);
                if src.visible && src.opacity > 0 {
                    let dst = &mut f.layers[i - 1].pixels;
                    for y in 0..h {
                        for x in 0..w {
                            let p = src.pixels.get(x, y);
                            if p.a != 0 {
                                let d = dst.get(x, y);
                                dst.set(x, y, crate::color::composite(src.blend, p, d, src.opacity));
                            }
                        }
                    }
                }
            }
            let was_in_run = f.layers.iter().all(|l| l.id != active);
            let target = if was_in_run { survivor } else { active };
            s.reactivate_layer_by_id(target, set.first());
        });
        self.clear_move_group();
    }

    /// Rigid shift by `delta` slots (positive = toward the top of the stack), clamped so no
    /// member leaves the stack; gaps kept, unselected layers flow around. A clamp to zero is a
    /// no-op with no record. The journal stores the requested delta; replay re-clamps.
    pub fn shift_layers(&mut self, set: &LayerSet, delta: i32) {
        if !self.layer_set_ok("ShiftLayers", set) {
            return;
        }
        let n = self.doc.active_frame().layers.len() as i64;
        let k = (delta as i64).clamp(-(set.first() as i64), n - 1 - set.last() as i64);
        if k == 0 {
            return;
        }
        let active = self.active_layer_id();
        self.edit_frame(|s| {
            let old = std::mem::take(&mut s.doc.active_frame_mut().layers);
            let n = old.len();
            let mut slots: Vec<Option<Layer>> = (0..n).map(|_| None).collect();
            let mut rest: Vec<Layer> = Vec::with_capacity(n - set.count());
            for (i, l) in old.into_iter().enumerate() {
                if set.contains(i) {
                    slots[(i as i64 + k) as usize] = Some(l);
                } else {
                    rest.push(l);
                }
            }
            let mut rest = rest.into_iter();
            s.doc.active_frame_mut().layers = slots.into_iter().filter_map(|slot| slot.or_else(|| rest.next())).collect();
            s.reactivate_layer_by_id(active, 0);
        });
    }

    /// The occupants of the selected slots reverse; fewer than two members is a no-op.
    pub fn reverse_layers(&mut self, set: &LayerSet) {
        if !self.layer_set_ok("ReverseLayers", set) || set.count() < 2 {
            return;
        }
        let active = self.active_layer_id();
        self.edit_frame(|s| {
            let f = s.doc.active_frame_mut();
            let idx = set.indices();
            let occupants: Vec<Layer> = idx.iter().map(|&i| f.layers[i].clone()).collect();
            for (r, &i) in idx.iter().enumerate() {
                f.layers[i] = occupants[idx.len() - 1 - r].clone();
            }
            s.reactivate_layer_by_id(active, 0);
        });
    }

    /// One blank layer ("Layer N", visible, unlocked, 255, Normal) right above (`above`) or
    /// below each member. Cap-checked as a whole; the active layer unchanged by identity.
    pub fn insert_blank_layers(&mut self, set: &LayerSet, above: bool) {
        if !self.layer_set_ok("InsertBlankLayers", set) || !self.layer_cap_ok("InsertBlankLayers", set.count()) {
            return;
        }
        let active = self.active_layer_id();
        self.edit_frame(|s| {
            let old = std::mem::take(&mut s.doc.active_frame_mut().layers);
            let mut out: Vec<Layer> = Vec::with_capacity(old.len() + set.count());
            let blank = |s: &mut Session, out: &mut Vec<Layer>| {
                let name = format!("Layer {}", out.len() + 1);
                out.push(s.doc.new_layer(name));
            };
            for (i, l) in old.into_iter().enumerate() {
                let member = set.contains(i);
                if member && !above {
                    blank(s, &mut out);
                }
                out.push(l);
                if member && above {
                    blank(s, &mut out);
                }
            }
            s.doc.active_frame_mut().layers = out;
            s.reactivate_layer_by_id(active, 0);
        });
        self.clear_move_group();
    }

    // ---- properties (the lock does not guard these) ----

    /// Set the visible flag on every member; no-op when none differs.
    pub fn set_layers_visible(&mut self, set: &LayerSet, visible: bool) {
        if !self.layer_set_ok("SetLayersVisible", set) {
            return;
        }
        if set.indices().iter().all(|&i| self.doc.active_frame().layers[i].visible == visible) {
            return;
        }
        self.edit_frame(|s| {
            for &i in set.indices() {
                s.doc.active_frame_mut().layers[i].visible = visible;
            }
        });
    }

    /// Set the locked flag on every member; no-op when none differs.
    pub fn set_layers_locked(&mut self, set: &LayerSet, locked: bool) {
        if !self.layer_set_ok("SetLayersLocked", set) {
            return;
        }
        if set.indices().iter().all(|&i| self.doc.active_frame().layers[i].locked == locked) {
            return;
        }
        self.edit_frame(|s| {
            for &i in set.indices() {
                s.doc.active_frame_mut().layers[i].locked = locked;
            }
        });
    }

    /// One opacity on every member; no-op when all already hold it.
    pub fn set_layers_opacity(&mut self, set: &LayerSet, opacity: u8) {
        if !self.layer_set_ok("SetLayersOpacity", set) {
            return;
        }
        if set.indices().iter().all(|&i| self.doc.active_frame().layers[i].opacity == opacity) {
            return;
        }
        self.edit_frame(|s| {
            for &i in set.indices() {
                s.doc.active_frame_mut().layers[i].opacity = opacity;
            }
        });
    }

    /// One blend mode on every member; no-op when all already hold it.
    pub fn set_layers_blend(&mut self, set: &LayerSet, blend: BlendMode) {
        if !self.layer_set_ok("SetLayersBlend", set) {
            return;
        }
        if set.indices().iter().all(|&i| self.doc.active_frame().layers[i].blend == blend) {
            return;
        }
        self.edit_frame(|s| {
            for &i in set.indices() {
                s.doc.active_frame_mut().layers[i].blend = blend;
            }
        });
    }

    /// Opacity 255, Normal, visible, unlocked on every member; no-op when all already are.
    pub fn reset_layers(&mut self, set: &LayerSet) {
        if !self.layer_set_ok("ResetLayers", set) {
            return;
        }
        let is_default =
            |l: &Layer| l.opacity == 255 && l.blend == BlendMode::Normal && l.visible && !l.locked;
        if set.indices().iter().all(|&i| is_default(&self.doc.active_frame().layers[i])) {
            return;
        }
        self.edit_frame(|s| {
            for &i in set.indices() {
                let l = &mut s.doc.active_frame_mut().layers[i];
                l.opacity = 255;
                l.blend = BlendMode::Normal;
                l.visible = true;
                l.locked = false;
            }
        });
    }

    /// One name on every member; `{n}` expands to the member's 1-based rank **top first**
    /// ("Sketch {n}" → the topmost member is Sketch 1). No-op when nothing changes.
    pub fn rename_layers(&mut self, set: &LayerSet, pattern: &str) {
        if !self.layer_set_ok("RenameLayers", set) {
            return;
        }
        let count = set.count();
        let names: Vec<String> = set
            .indices()
            .iter()
            .enumerate()
            .map(|(r, _)| pattern.replace("{n}", &(count - r).to_string()))
            .collect();
        if set.indices().iter().zip(&names).all(|(&i, n)| self.doc.active_frame().layers[i].name == *n) {
            return;
        }
        self.edit_frame(|s| {
            for (&i, n) in set.indices().iter().zip(names) {
                s.doc.active_frame_mut().layers[i].name = n;
            }
        });
    }

    // ---- content (the member layers' pixels only, storage-wide; the mask untouched) ----

    /// Mirror every member across the X axis (`horizontal`) or the Y axis — the per-layer half of
    /// `flip_frame`, in one record. Refused over a locked member; all-empty is a no-op.
    pub fn flip_layers(&mut self, set: &LayerSet, horizontal: bool) {
        let verb = if horizontal { "FlipLayersH" } else { "FlipLayersV" };
        if !self.layer_set_ok(verb, set) || !self.no_locked_members(verb, set) || self.layer_members_all_empty(set) {
            return;
        }
        let storage = self.doc.storage();
        let (w, h) = (storage.w as i32, storage.h as i32);
        self.edit_frame(|s| {
            for &i in set.indices() {
                super::canvas::flip_storage(&mut s.doc.active_frame_mut().layers[i].pixels, w, h, horizontal);
            }
        });
    }

    /// Rotate every member by `quarter_turns` × 90° clockwise about the storage center: the
    /// frame-scope rotate draft restricted to the members, through the same resampler as
    /// `rotate_frame`, so a member's result is byte-identical to rotating the whole frame.
    pub fn rotate_layers(&mut self, set: &LayerSet, quarter_turns: u8) {
        let q = quarter_turns % 4;
        if !self.layer_set_ok("RotateLayers", set)
            || q == 0
            || !self.no_locked_members("RotateLayers", set)
            || self.layer_members_all_empty(set)
        {
            return;
        }
        let (cw, ch) = {
            let s = self.doc.storage();
            (s.w as i32, s.h as i32)
        };
        let fi = self.doc.active_frame;
        let members: Vec<u32> = set.indices().iter().map(|&i| self.doc.frames[fi].layers[i].id).collect();
        self.edit_frame(|s| {
            let mut d = s.frame_rotate_draft(fi);
            d.layers.retain(|e| members.contains(&e.lid));
            d.angle = super::canvas::quarter_turn_mrad(q) as f32 / 1000.0;
            super::canvas::apply_rotation_to_frame(&d, &mut s.doc.frames[fi], cw, ch);
        });
    }

    /// A per-pixel color transform over every member (`InvertLayers` passes `color::invert`).
    pub fn map_layers(&mut self, set: &LayerSet, f: impl Fn(Rgba8) -> Rgba8) {
        if !self.layer_set_ok("InvertLayers", set)
            || !self.no_locked_members("InvertLayers", set)
            || self.layer_members_all_empty(set)
        {
            return;
        }
        self.edit_frame(|s| {
            for &i in set.indices() {
                tool::map_region(&mut s.doc.active_frame_mut().layers[i].pixels, None, &f);
            }
        });
    }

    /// Erase every pixel of every member; the layers stay. Refused over a locked member;
    /// all-empty is a no-op.
    pub fn clear_layers(&mut self, set: &LayerSet) {
        if !self.layer_set_ok("ClearLayers", set)
            || !self.no_locked_members("ClearLayers", set)
            || self.layer_members_all_empty(set)
        {
            return;
        }
        self.edit_frame(|s| {
            for &i in set.indices() {
                s.doc.active_frame_mut().layers[i].pixels.clear();
            }
        });
    }

    // ---- across frames ----

    /// The members, in stack order, pushed on top of every target frame's stack (fresh ids) —
    /// the strict `copy_layer_to_frames` generalized to a set. Refused as a whole when any target
    /// would pass the cap; the active frame among the targets gets copies of its own layers.
    pub fn copy_layers_to_frames(&mut self, set: &LayerSet, frames: &FrameSet) {
        if !self.layer_set_ok("CopyLayersToFrames", set) || !self.frame_set_ok("CopyLayersToFrames", frames) {
            return;
        }
        if let Some(&j) =
            frames.indices().iter().find(|&&j| self.doc.frames[j].layers.len() + set.count() > MAX_LAYERS)
        {
            self.refuse(&format!(
                "CopyLayersToFrames: frame {} would exceed the {}-layer cap ({} + {} layers)",
                j + 1,
                MAX_LAYERS,
                self.doc.frames[j].layers.len(),
                set.count()
            ));
            return;
        }
        let srcs: Vec<Layer> = set.indices().iter().map(|&i| self.doc.active_frame().layers[i].clone()).collect();
        self.edit_doc("copy_layers_to_frames", |s| {
            for &j in frames.indices() {
                for src in &srcs {
                    let mut copy = src.clone();
                    copy.id = s.doc.layer_ids.alloc();
                    s.doc.frames[j].layers.push(copy);
                }
            }
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn set(s: &str) -> LayerSet {
        LayerSet::parse(s).unwrap()
    }

    /// A session with `n` layers on one frame, layer `i` painted white at (i, 0) and named `L<i>`.
    fn stack(n: usize) -> Session {
        let mut s = Session::new(16, 16);
        s.settings.primary = Rgba8::WHITE;
        for i in 0..n {
            if i > 0 {
                s.add_layer();
            }
            s.rename_layer(i, format!("L{i}"));
            s.tap(i as i32, 0);
        }
        s.set_active_layer(0);
        s
    }

    fn names(s: &Session) -> Vec<String> {
        s.doc.active_frame().layers.iter().map(|l| l.name.clone()).collect()
    }

    fn ids(s: &Session) -> Vec<u32> {
        s.doc.active_frame().layers.iter().map(|l| l.id).collect()
    }

    fn undo_len(s: &Session) -> usize {
        s.doc.history.undo.len()
    }

    fn active_name(s: &Session) -> String {
        s.doc.active_frame().active_layer().name.clone()
    }

    #[test]
    fn layer_set_parses_and_caps_at_128() {
        assert_eq!(set("3 1-2 2").indices(), &[1, 2, 3]);
        assert_eq!(set("3 1-2 2 5").to_dsl(), "1-3 5");
        assert!(set("1-3").is_contiguous());
        assert!(!set("1 3").is_contiguous());
        assert!(LayerSet::parse("127").is_ok());
        assert!(LayerSet::parse("128").unwrap_err().contains("layer"));
        assert!(LayerSet::parse("").is_err());
        assert!(LayerSet::parse("5-3").is_err());
    }

    #[test]
    fn out_of_range_refuses_and_changes_nothing() {
        let mut s = stack(3);
        let n = undo_len(&s);
        s.run_script("RemoveLayers(1 5)").unwrap();
        assert_eq!(names(&s), ["L0", "L1", "L2"]);
        assert_eq!(undo_len(&s), n);
        assert!(s.refusal_state().1.unwrap().contains("layer 6 is out of range"));
    }

    #[test]
    fn remove_layers_follows_identity_then_clamps() {
        let mut s = stack(5);
        s.set_active_layer(3);
        s.run_script("RemoveLayers(1 3)").unwrap();
        assert_eq!(names(&s), ["L0", "L2", "L4"]);
        // The active layer (L3, index 3) was removed → the layer now at index 3, clamped to 2.
        assert_eq!(active_name(&s), "L4");
        assert!(s.assert_undo_restores());

        let mut s = stack(5);
        s.set_active_layer(4);
        s.run_script("RemoveLayers(0-1)").unwrap();
        assert_eq!(active_name(&s), "L4", "survives by identity");
    }

    #[test]
    fn remove_every_layer_substitutes_a_blank() {
        let mut s = stack(3);
        s.run_script("SetMoveGroup(0, 1)").unwrap();
        s.run_script("RemoveLayers(0-2)").unwrap();
        assert_eq!(names(&s), ["Layer 1"]);
        let l = s.doc.active_frame().active_layer();
        assert!(l.pixels.is_empty() && l.visible && !l.locked && l.opacity == 255);
        assert!(s.move_group.is_empty(), "the stack changed under the group");
        assert!(s.assert_undo_restores());
    }

    #[test]
    fn duplicate_layers_copies_above_with_the_single_verbs_name() {
        let mut s = stack(3);
        s.set_active_layer(2);
        let before = ids(&s);
        s.run_script("DuplicateLayers(0 2)").unwrap();
        assert_eq!(names(&s), ["L0", "L0 copy", "L1", "L2", "L2 copy"]);
        assert_eq!(active_name(&s), "L2", "the original stays active");
        let after = ids(&s);
        assert!(after.iter().filter(|id| !before.contains(id)).count() == 2, "fresh ids");
        assert_eq!(s.pixel(0, 1, 0, 0), Rgba8::WHITE);
        assert!(s.assert_undo_restores());
    }

    #[test]
    fn duplicate_past_the_cap_refuses_whole() {
        let mut s = stack(3);
        while s.doc.active_frame().layers.len() < MAX_LAYERS - 1 {
            s.add_layer();
        }
        let n = undo_len(&s);
        s.run_script("DuplicateLayers(0-1)").unwrap();
        assert_eq!(undo_len(&s), n);
        assert!(s.refusal_state().1.unwrap().contains("128-layer cap"));
    }

    #[test]
    fn merge_layers_is_byte_identical_to_merge_down_and_moves_the_active_to_the_survivor() {
        let build = || {
            let mut s = stack(5);
            s.set_layer_opacity(2, 128);
            s.set_layer_blend(3, BlendMode::Multiply);
            s.set_layer_visible(1, false);
            s
        };
        let mut batch = build();
        batch.set_active_layer(3);
        batch.run_script("MergeLayers(1-3)").unwrap();
        let mut single = build();
        single.merge_down(3);
        single.merge_down(2);
        assert_eq!(names(&batch), ["L0", "L1", "L4"]);
        assert_eq!(batch.doc.active_frame().content_hash(), single.doc.active_frame().content_hash());
        assert_eq!(active_name(&batch), "L1", "the run's survivor");
        assert_eq!(batch.doc.active_frame().layers[1].opacity, 255, "survivor keeps its properties");
        assert!(batch.assert_undo_restores());
    }

    #[test]
    fn merge_refuses_a_gap_a_lock_and_noops_on_one_member() {
        let mut s = stack(4);
        let n = undo_len(&s);
        s.run_script("MergeLayers(0 2)").unwrap();
        assert!(s.refusal_state().1.unwrap().contains("gap"));
        s.set_layer_locked(1, true);
        let seq = s.refusal_state().0;
        s.run_script("MergeLayers(0-2)").unwrap();
        assert_eq!(s.refusal_state().0, seq + 1);
        assert!(s.refusal_state().1.unwrap().contains("locked"));
        s.run_script("MergeLayers(3)").unwrap();
        assert_eq!(names(&s), ["L0", "L1", "L2", "L3"]);
        assert_eq!(undo_len(&s), n + 1, "only the lock toggle recorded");
    }

    #[test]
    fn shift_layers_is_rigid_and_clamps() {
        let mut s = stack(6);
        s.set_active_layer(4);
        s.run_script("ShiftLayers(1 4, 10)").unwrap(); // clamped to +1
        assert_eq!(names(&s), ["L0", "L2", "L1", "L3", "L5", "L4"]);
        assert_eq!(active_name(&s), "L4");
        assert!(s.assert_undo_restores());
        let n = undo_len(&s);
        s.run_script("ShiftLayers(0 5, 1)").unwrap(); // room = 0 → no-op
        assert_eq!(undo_len(&s), n);
        assert!(s.assert_undo_restores());
    }

    #[test]
    fn reverse_and_insert_blank() {
        let mut s = stack(4);
        s.run_script("ReverseLayers(0 2 3)").unwrap();
        assert_eq!(names(&s), ["L3", "L1", "L2", "L0"]);
        assert!(s.assert_undo_restores());
        // (assert_undo_restores redoes, so the reversed order is the one the inserts see.)
        s.run_script("InsertBlankLayers(1 3, above)").unwrap();
        assert_eq!(names(&s), ["L3", "L1", "Layer 3", "L2", "L0", "Layer 6"]);
        assert!(s.assert_undo_restores());
        s.run_script("InsertBlankLayers(0, below)").unwrap();
        assert_eq!(names(&s)[0], "Layer 1");
        assert_eq!(active_name(&s), "L0");
        assert!(s.assert_undo_restores());
    }

    #[test]
    fn property_batches_apply_and_noop_when_nothing_differs() {
        let mut s = stack(3);
        let n = undo_len(&s);
        s.run_script("SetLayersVisible(0-2, 1)").unwrap();
        assert_eq!(undo_len(&s), n, "already visible");
        s.run_script("SetLayersVisible(0 2, 0); SetLayersLocked(1, 1); SetLayersOpacity(0-2, 77); SetLayersBlend(1-2, Screen)")
            .unwrap();
        let ls = &s.doc.active_frame().layers;
        assert!(!ls[0].visible && ls[1].visible && !ls[2].visible);
        assert!(ls[1].locked, "the lock does not guard property batches on other members");
        assert!(ls.iter().all(|l| l.opacity == 77));
        assert_eq!((ls[0].blend, ls[1].blend, ls[2].blend), (BlendMode::Normal, BlendMode::Screen, BlendMode::Screen));
        assert_eq!(undo_len(&s), n + 4);
        s.run_script("ResetLayers(0-2)").unwrap();
        let ls = &s.doc.active_frame().layers;
        assert!(ls.iter().all(|l| l.visible && !l.locked && l.opacity == 255 && l.blend == BlendMode::Normal));
        assert!(s.assert_undo_restores());
        let n = undo_len(&s);
        s.run_script("ResetLayers(0-2)").unwrap();
        assert_eq!(undo_len(&s), n, "already default");
    }

    #[test]
    fn rename_layers_ranks_top_first() {
        let mut s = stack(4);
        s.run_script("RenameLayers(0 2-3, Sketch {n})").unwrap();
        assert_eq!(names(&s), ["Sketch 3", "L1", "Sketch 2", "Sketch 1"]);
        s.run_script("RenameLayers(1, Ink, v2)").unwrap();
        assert_eq!(names(&s)[1], "Ink, v2", "commas survive");
        let n = undo_len(&s);
        s.run_script("RenameLayers(1, Ink, v2)").unwrap();
        assert_eq!(undo_len(&s), n);
        assert!(s.assert_undo_restores());
    }

    #[test]
    fn content_batches_touch_members_only_and_refuse_locks() {
        let mut s = stack(3);
        s.run_script("FlipLayersH(0 2)").unwrap();
        assert_eq!(s.pixel(0, 0, 15, 0), Rgba8::WHITE);
        assert_eq!(s.pixel(0, 1, 1, 0), Rgba8::WHITE, "non-member untouched");
        assert_eq!(s.pixel(0, 2, 13, 0), Rgba8::WHITE);
        assert!(s.assert_undo_restores());
        s.run_script("InvertLayers(1)").unwrap();
        assert_eq!(s.pixel(0, 1, 1, 0), Rgba8::rgb(0, 0, 0));
        assert!(s.assert_undo_restores());
        s.run_script("ClearLayers(0-1)").unwrap();
        let ls = &s.doc.active_frame().layers;
        assert!(ls[0].pixels.is_empty() && ls[1].pixels.is_empty() && !ls[2].pixels.is_empty());
        assert_eq!(ls.len(), 3, "the layers stay");
        assert!(s.assert_undo_restores());
        s.set_layer_locked(2, true);
        let n = undo_len(&s);
        for verb in ["FlipLayersV(2)", "RotateLayers(2, 1)", "InvertLayers(1-2)", "ClearLayers(2)"] {
            let seq = s.refusal_state().0;
            s.run_script(verb).unwrap();
            assert_eq!(s.refusal_state().0, seq + 1, "{verb} must refuse");
        }
        assert_eq!(undo_len(&s), n);
        assert!(!s.can_repeat(), "batches are not Repeatable");
    }

    #[test]
    fn rotate_layers_matches_rotate_frame_per_member() {
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
                    s.add_layer();
                    s.settings.primary = Rgba8::rgb(0, 255, 0);
                    s.tap(6, 6);
                    s
                };
                let mut batch = build();
                batch.run_script(&format!("RotateLayers(0 2, {})", q)).unwrap();
                let mut whole = build();
                whole.rotate_frame(q);
                let untouched = build();
                for li in [0usize, 2] {
                    assert_eq!(
                        batch.doc.active_frame().layers[li].pixels.content_hash(),
                        whole.doc.active_frame().layers[li].pixels.content_hash(),
                        "q={} clean_edge={} layer {}",
                        q,
                        clean_edge,
                        li
                    );
                }
                assert_eq!(
                    batch.doc.active_frame().layers[1].pixels.content_hash(),
                    untouched.doc.active_frame().layers[1].pixels.content_hash(),
                    "the non-member is untouched"
                );
                assert!(batch.assert_undo_restores());
            }
        }
    }

    #[test]
    fn content_batches_leave_the_selection_mask_alone() {
        let mut s = stack(2);
        s.run_script("SelectAll()").unwrap();
        let before = s.doc.selection.clone();
        s.run_script("FlipLayersH(0-1); RotateLayers(0-1, 1); InvertLayers(0); ClearLayers(1)").unwrap();
        assert_eq!(s.doc.selection.is_some(), before.is_some());
        assert_eq!(
            s.doc.selection.as_ref().map(|m| m.memory_bytes()),
            before.as_ref().map(|m| m.memory_bytes())
        );
    }

    #[test]
    fn copy_layers_to_frames_is_strict_and_stacks_in_order() {
        let mut s = stack(3);
        s.add_frame();
        s.add_frame();
        s.set_active_frame(0);
        s.run_script("CopyLayersToFrames(0 2, 0-2)").unwrap();
        assert_eq!(names(&s), ["L0", "L1", "L2", "L0", "L2"], "the source frame gets copies too");
        let f2: Vec<String> = s.doc.frames[2].layers.iter().map(|l| l.name.clone()).collect();
        assert_eq!(f2, ["Layer 1", "L0", "L2"]);
        assert_eq!(s.pixel(2, 1, 0, 0), Rgba8::WHITE);
        assert!(s.assert_undo_restores());
        // Fill frame 1 to one below the cap: a two-layer copy refuses the whole batch.
        s.set_active_frame(1);
        while s.doc.active_frame().layers.len() < MAX_LAYERS - 1 {
            s.add_layer();
        }
        s.set_active_frame(0);
        let n = undo_len(&s);
        let frame2_before = s.doc.frames[2].layers.len();
        s.run_script("CopyLayersToFrames(0-1, 1-2)").unwrap();
        assert_eq!(undo_len(&s), n);
        assert_eq!(s.doc.frames[2].layers.len(), frame2_before, "nothing copied anywhere");
        assert!(s.refusal_state().1.unwrap().contains("frame 2 would exceed"));
    }

    #[test]
    fn journal_replays_the_batches_identically() {
        let script = "NewDocument(16, 16); SelectTool(Pencil); SetPrimaryColor(#FF4040FF); Tap(2,2); \
                      AddLayer(); Tap(5,5); AddLayer(); Tap(9,9); \
                      DuplicateLayers(0-1); ShiftLayers(0 3, 1); ReverseLayers(0-2); \
                      SetLayersOpacity(1-2, 90); RenameLayers(0-4, Cel {n}); FlipLayersV(0 2 4); \
                      MergeLayers(2-4); RotateLayers(0-1, 3); InsertBlankLayers(1, below); \
                      RemoveLayers(0)";
        let mut a = Session::empty();
        a.run_script(script).unwrap();
        let mut b = Session::empty();
        b.run_script(script).unwrap();
        assert_eq!(a.doc.content_hash(), b.doc.content_hash());
        assert!(a.assert_undo_restores());
    }
}
