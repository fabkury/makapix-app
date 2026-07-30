//! Scene undo/redo: absolute before/after records (any record is droppable during budget
//! eviction — the engine history's invariant), byte-weighted against a small budget. Scene
//! records are orders of magnitude lighter than pixel history (Keys and struct fields), except
//! the cast records, which hold `Arc`s of Prop art and are weighted by it.

use crate::model::{Actor, ActorId, ActorMode, Prop, PropId, Scene, SceneFps, Track, TrackProp};
use makapix_engine::color::Rgba8;
use std::sync::Arc;

pub const SCENE_MIN_RECORDS: usize = 8;

/// Scene-level metadata snapshot (SetFps / SetFrameCount / SetBackground / SetLoop).
#[derive(Clone, Copy, PartialEq, Debug)]
pub struct SceneMetaRec {
    pub fps: SceneFps,
    pub frame_count: u32,
    pub background: Rgba8,
    pub loop_a: u32,
    pub loop_b: u32,
}

impl SceneMetaRec {
    pub fn of(s: &Scene) -> Self {
        SceneMetaRec {
            fps: s.fps,
            frame_count: s.frame_count,
            background: s.background,
            loop_a: s.loop_a,
            loop_b: s.loop_b,
        }
    }
    pub fn apply(&self, s: &mut Scene) {
        s.fps = self.fps;
        s.frame_count = self.frame_count;
        s.background = self.background;
        s.loop_a = self.loop_a;
        s.loop_b = self.loop_b;
    }
}

/// Prop metadata (name / style / cycle_map — art changes are `PropArt`).
#[derive(Clone, PartialEq, Debug)]
pub struct PropMetaRec {
    pub name: String,
    pub style: crate::model::PixelStyle,
    pub cycle_map: Vec<u16>,
}

impl PropMetaRec {
    pub fn of(p: &Prop) -> Self {
        PropMetaRec { name: p.name.clone(), style: p.style, cycle_map: p.cycle_map.clone() }
    }
    pub fn apply(&self, p: &mut Prop) {
        p.name = self.name.clone();
        p.style = self.style;
        p.cycle_map = self.cycle_map.clone();
        p.art_epoch = p.art_epoch.wrapping_add(1);
    }
}

/// Actor metadata (name / mode / pin / visible — tracks are `TrackEdit`, z is `ActorZ`).
#[derive(Clone, PartialEq, Debug)]
pub struct ActorMetaRec {
    pub name: String,
    pub mode: ActorMode,
    pub pin_to: Option<ActorId>,
    pub visible: bool,
}

impl ActorMetaRec {
    pub fn of(a: &Actor) -> Self {
        ActorMetaRec { name: a.name.clone(), mode: a.mode, pin_to: a.pin_to, visible: a.visible }
    }
    pub fn apply(&self, a: &mut Actor) {
        a.name = self.name.clone();
        a.mode = self.mode;
        a.pin_to = self.pin_to;
        a.visible = self.visible;
    }
}

/// One undoable edit, absolute (before AND after), so records drop independently.
#[derive(Clone)]
pub enum SceneEdit {
    SceneMeta { before: SceneMetaRec, after: SceneMetaRec },
    CastInsert { index: usize, prop: Arc<Prop> },
    /// Cascade: removing a Prop removes its Actors too (positions retained for undo).
    CastRemove { index: usize, prop: Arc<Prop>, actors: Vec<(usize, Arc<Actor>)> },
    PropMeta { id: PropId, before: PropMetaRec, after: PropMetaRec },
    ActorInsert { index: usize, actor: Arc<Actor> },
    ActorRemove { index: usize, actor: Arc<Actor> },
    ActorMeta { id: ActorId, before: ActorMetaRec, after: ActorMetaRec },
    ActorZ { from: usize, to: usize },
    /// Whole-track snapshot (base + keys) — tracks are tiny, so absolute beats deltas.
    TrackEdit { id: ActorId, prop: TrackProp, before: Track, after: Track },
    /// Several edits as ONE undo step (a gesture touching x+y; an import placing Actors).
    /// Undo applies members in reverse order; redo in order.
    Compound(Vec<SceneEdit>),
}

fn track_weight(t: &Track) -> usize {
    32 + t.keys.len() * 16
}

fn prop_weight(p: &Prop) -> usize {
    // Art dominates: count materialized tiles (COW-shared with the live scene until edited,
    // but the budget stays honest by over-counting — the engine history's stance).
    let mut tiles = 0usize;
    for f in &p.frames {
        tiles += f.present_tiles();
    }
    256 + p.name.len() + p.cycle_map.len() * 2 + tiles * 4096
}

fn actor_weight(a: &Actor) -> usize {
    256 + a.name.len() + a.tracks.0.iter().map(track_weight).sum::<usize>()
}

fn weight_of(e: &SceneEdit) -> usize {
    128 + match e {
        SceneEdit::SceneMeta { .. } => 64,
        SceneEdit::CastInsert { prop, .. } => prop_weight(prop),
        SceneEdit::CastRemove { prop, actors, .. } => {
            prop_weight(prop) + actors.iter().map(|(_, a)| actor_weight(a)).sum::<usize>()
        }
        SceneEdit::PropMeta { before, after, .. } => {
            64 + before.cycle_map.len() * 2 + after.cycle_map.len() * 2
        }
        SceneEdit::ActorInsert { actor, .. } | SceneEdit::ActorRemove { actor, .. } => {
            actor_weight(actor)
        }
        SceneEdit::ActorMeta { .. } => 128,
        SceneEdit::ActorZ { .. } => 16,
        SceneEdit::TrackEdit { before, after, .. } => track_weight(before) + track_weight(after),
        SceneEdit::Compound(parts) => parts.iter().map(weight_of).sum(),
    }
}

pub struct SceneHistory {
    pub undo: Vec<SceneEdit>,
    pub redo: Vec<SceneEdit>,
    bytes: usize,
    byte_budget: Option<usize>,
}

impl SceneHistory {
    pub fn new() -> Self {
        SceneHistory { undo: Vec::new(), redo: Vec::new(), bytes: 0, byte_budget: None }
    }
    fn budget(&self) -> usize {
        self.byte_budget.unwrap_or(crate::model::SCENE_HISTORY_BUDGET)
    }
    pub fn set_byte_budget(&mut self, b: Option<usize>) {
        self.byte_budget = b;
        self.enforce();
    }
    pub fn retained_bytes(&self) -> usize {
        self.bytes
    }
    pub fn can_undo(&self) -> bool {
        !self.undo.is_empty()
    }
    pub fn can_redo(&self) -> bool {
        !self.redo.is_empty()
    }

    /// Push a completed edit: clears redo, then evicts oldest records past the byte budget
    /// (always keeping at least [`SCENE_MIN_RECORDS`]).
    pub fn push(&mut self, e: SceneEdit) {
        for r in self.redo.drain(..) {
            let _ = r; // dropped; bytes for redo were counted at push time and removed on pop
        }
        self.bytes += weight_of(&e);
        self.undo.push(e);
        self.enforce();
    }

    fn enforce(&mut self) {
        while self.bytes > self.budget() && self.undo.len() > SCENE_MIN_RECORDS {
            let dropped = self.undo.remove(0);
            self.bytes = self.bytes.saturating_sub(weight_of(&dropped));
        }
    }

    /// Pop for undo; the caller applies the record's `before` side and must then call
    /// [`SceneHistory::park_redo`] with the same record.
    pub fn pop_undo(&mut self) -> Option<SceneEdit> {
        let e = self.undo.pop()?;
        self.bytes = self.bytes.saturating_sub(weight_of(&e));
        Some(e)
    }
    pub fn park_redo(&mut self, e: SceneEdit) {
        self.redo.push(e);
    }
    pub fn pop_redo(&mut self) -> Option<SceneEdit> {
        self.redo.pop()
    }
    /// Re-admit a redone record to the undo stack.
    pub fn park_undo(&mut self, e: SceneEdit) {
        self.bytes += weight_of(&e);
        self.undo.push(e);
        self.enforce();
    }

    pub fn clear(&mut self) {
        self.undo.clear();
        self.redo.clear();
        self.bytes = 0;
    }
}

impl Default for SceneHistory {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tiny_edit(v: i32) -> SceneEdit {
        SceneEdit::TrackEdit {
            id: 1,
            prop: TrackProp::X,
            before: Track::constant(0),
            after: Track::constant(v),
        }
    }

    #[test]
    fn push_clears_redo_and_budget_evicts_oldest() {
        let mut h = SceneHistory::new();
        h.set_byte_budget(Some(2000)); // each tiny edit weighs 128+32+32 = 192
        for i in 0..20 {
            h.push(tiny_edit(i));
        }
        assert!(h.undo.len() < 20, "budget evicted oldest records");
        assert!(h.undo.len() >= SCENE_MIN_RECORDS);
        let e = h.pop_undo().unwrap();
        h.park_redo(e);
        assert!(h.can_redo());
        h.push(tiny_edit(99));
        assert!(!h.can_redo(), "a new edit clears redo");
    }
}
