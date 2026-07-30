//! `SceneSession` — the single stateful entry point (the engine `Session`'s twin): owns the
//! Scene plus editor-only state (playhead, selection, auto-key, gesture bracketing, budgets),
//! runs the DSL, wraps edits in absolute undo records, and serves `state_json` to the shell.
//! Never panics on hostile input: unknown ids no-op, values clamp.

mod parse;
pub use parse::{parse_line, SceneAction};

use crate::eval::{self, ActorPose, NetXf};
use crate::history::{ActorMetaRec, PropMetaRec, SceneEdit, SceneHistory, SceneMetaRec};
use crate::model::{
    Actor, ActorId, ActorMode, PixelStyle, Prop, PropId, Scene, SceneFps, Track, TrackProp,
    Tracks, Tween, MAX_ACTORS, MAX_CYCLE_STEP, MAX_PROPS, MAX_PROP_DIM, MAX_PROP_FRAMES,
    MAX_SCENE_FRAMES, SCENE_MEM_HARD, SCENE_MEM_SOFT,
};
use makapix_engine::buffer::RgbaBuffer;
use makapix_engine::color::Rgba8;
use makapix_engine::transform::rot_cos_sin;
use makapix_engine::util::SeededRng;
use std::cell::RefCell;
use std::collections::HashMap;
use std::sync::Arc;

pub struct SceneSession {
    pub scene: Scene,
    pub(crate) history: SceneHistory,
    pub playhead: u32,
    pub selected_actor: Option<ActorId>,
    pub auto_key: bool,
    playing: bool,
    /// Virtual playback clock, µs since Play (advanced by `AdvanceClock`; CLI/test driven).
    clock_us: u64,
    play_start_frame: u32,
    mem_budget_override: Option<(usize, usize)>,
    mem_exact: usize,
    mem_refusals: u32,
    mem_last_refusal: Option<String>,
    /// Bumped by every output-affecting mutation; the shell's frame-cache invalidation signal.
    cache_epoch: u64,
    /// Open gesture bracket: first-touch snapshots of tracks, keyed by (actor, prop index).
    gesture: Option<HashMap<(ActorId, usize), Track>>,
    /// The transform cache (P2). RefCell keeps `composite` callable on `&self`; eviction and
    /// hits can never change output (assert.det guards it).
    cache: RefCell<crate::compose::TransformCache>,
}

impl SceneSession {
    pub fn new(w: u16, h: u16, fps: SceneFps) -> Self {
        SceneSession {
            scene: Scene::new(w, h, fps),
            history: SceneHistory::new(),
            playhead: 0,
            selected_actor: None,
            auto_key: true,
            playing: false,
            clock_us: 0,
            play_start_frame: 0,
            mem_budget_override: None,
            mem_exact: 0,
            mem_refusals: 0,
            mem_last_refusal: None,
            cache_epoch: 0,
            gesture: None,
            cache: RefCell::new(crate::compose::TransformCache::new(
                crate::compose::TRANSFORM_CACHE_BUDGET,
            )),
        }
    }

    /// 64×64 at 12.5 fps (the CLI's starting session, like `Session::empty`).
    pub fn empty() -> Self {
        SceneSession::new(64, 64, SceneFps::F12_5)
    }

    // ---- small read API ---------------------------------------------------------------------

    pub fn size(&self) -> (u16, u16) {
        (self.scene.w, self.scene.h)
    }
    pub fn frame_count(&self) -> u32 {
        self.scene.frame_count
    }
    pub fn cache_epoch(&self) -> u64 {
        self.cache_epoch
    }
    pub fn is_playing(&self) -> bool {
        self.playing
    }
    /// The clock-derived playback frame (loop-region aware), or the playhead when paused.
    pub fn current_play_frame(&self) -> u32 {
        if !self.playing {
            return self.playhead;
        }
        let (a, b) = (self.scene.loop_a, self.scene.loop_b.max(self.scene.loop_a));
        let len = b - a + 1;
        let advanced = (self.clock_us / self.scene.fps.frame_us() as u64) as u32;
        let start = self.play_start_frame.clamp(a, b) - a;
        a + (start + advanced) % len
    }
    pub fn eval_pose(&self, actor: ActorId, frame: u32) -> Option<ActorPose> {
        self.scene.actor(actor).map(|a| eval::eval_tracks(&a.tracks, frame))
    }
    /// The Actor's net transform at `frame` (pin composition applied).
    pub fn net_xf(&self, actor: &Actor, frame: u32) -> NetXf {
        let pose = eval::eval_tracks(&actor.tracks, frame);
        match actor.pin_to.and_then(|p| self.scene.actor(p)) {
            Some(parent) => {
                let ppose = eval::eval_tracks(&parent.tracks, frame);
                eval::compose_pin(&ppose, &pose)
            }
            None => eval::net_xf(&pose),
        }
    }
    pub fn resolved_src_frame(&self, actor: ActorId, frame: u32) -> Option<u32> {
        let a = self.scene.actor(actor)?;
        let p = self.scene.prop(a.prop)?;
        let pose = eval::eval_tracks(&a.tracks, frame);
        Some(eval::resolve_src_frame(p, a.mode, &pose, frame))
    }

    // ---- compositing (P2) -------------------------------------------------------------------

    /// The canonical image of frame `n` (canvas-sized, straight alpha).
    pub fn composite(&self, n: u32) -> RgbaBuffer {
        crate::compose::scene_frame(&self.scene, &mut self.cache.borrow_mut(), n)
    }
    pub fn composite_bytes(&self, n: u32) -> Vec<u8> {
        self.composite(n).to_rgba_bytes()
    }
    pub fn frame_hash(&self, n: u32) -> u64 {
        self.composite(n).content_hash() as u64
    }

    /// Nearest-fit thumbnail of a Prop's frame 0 into exactly `tw`×`th` RGBA (art centered,
    /// transparent padding) — the Cast sheet / gallery tile source.
    pub fn prop_thumb_bytes(&self, prop: PropId, tw: u32, th: u32) -> Vec<u8> {
        let Some(p) = self.scene.prop(prop) else { return Vec::new() };
        self.thumb_of(&p.frames[0], p.w, p.h, tw, th)
    }

    /// Thumbnail of an Actor's resolved source frame at the playhead.
    pub fn actor_thumb_bytes(&self, actor: ActorId, tw: u32, th: u32) -> Vec<u8> {
        let Some(a) = self.scene.actor(actor) else { return Vec::new() };
        let Some(p) = self.scene.prop(a.prop) else { return Vec::new() };
        let src = self.resolved_src_frame(actor, self.playhead).unwrap_or(0);
        let src = src.min(p.frames.len().saturating_sub(1) as u32) as usize;
        self.thumb_of(&p.frames[src], p.w, p.h, tw, th)
    }

    fn thumb_of(&self, src: &RgbaBuffer, sw: u32, sh: u32, tw: u32, th: u32) -> Vec<u8> {
        let (tw, th) = (tw.clamp(1, 512), th.clamp(1, 512));
        let mut out = RgbaBuffer::new(tw, th);
        // Fit (never upscale beyond integer nearest): scale = min(tw/sw, th/sh) in float,
        // centered; nearest sampling keeps it crisp.
        let scale = (tw as f32 / sw as f32).min(th as f32 / sh as f32);
        let fw = ((sw as f32 * scale).round() as i32).max(1);
        let fh = ((sh as f32 * scale).round() as i32).max(1);
        let ox = (tw as i32 - fw) / 2;
        let oy = (th as i32 - fh) / 2;
        for y in 0..fh {
            for x in 0..fw {
                let sx = ((x as f32 + 0.5) / scale).floor() as i32;
                let sy = ((y as f32 + 0.5) / scale).floor() as i32;
                let c = src.get(sx.clamp(0, sw as i32 - 1), sy.clamp(0, sh as i32 - 1));
                if c.a != 0 {
                    out.set(ox + x, oy + y, c);
                }
            }
        }
        out.to_rgba_bytes()
    }

    /// Topmost visible Actor whose transformed OPAQUE pixel covers scene point (x, y) at
    /// `frame`, else None. Nearest-sampled (style-agnostic — a hit test, not a render).
    pub fn hit_test(&self, frame: u32, x: i32, y: i32) -> Option<ActorId> {
        for actor in self.scene.actors.iter().rev() {
            if !actor.visible {
                continue;
            }
            let pose = eval::eval_tracks(&actor.tracks, frame);
            if pose.opacity <= 0 {
                continue;
            }
            let Some(prop) = self.scene.prop(actor.prop) else { continue };
            if prop.frames.is_empty() {
                continue;
            }
            let xf = self.net_xf(actor, frame);
            let (cos, sin) = rot_cos_sin(xf.rot_md.rem_euclid(360_000));
            let s = (xf.scale_micro.max(1)) as f32 / 1_000_000.0;
            let fxs = if xf.flip_h { -1.0f32 } else { 1.0 };
            let fys = if xf.flip_v { -1.0f32 } else { 1.0 };
            let gx = x as f32 + 0.5 - xf.tx_q8 as f32 / 256.0;
            let gy = y as f32 + 0.5 - xf.ty_q8 as f32 / 256.0;
            let rx = (cos * gx + sin * gy) / s * fxs + xf.pivot_x_milli as f32 / 1000.0;
            let ry = (-sin * gx + cos * gy) / s * fys + xf.pivot_y_milli as f32 / 1000.0;
            let lx = rx.floor() as i32;
            let ly = ry.floor() as i32;
            if lx < 0 || ly < 0 || lx >= prop.w as i32 || ly >= prop.h as i32 {
                continue;
            }
            let src_idx = eval::resolve_src_frame(prop, actor.mode, &pose, frame);
            let src = &prop.frames[src_idx.min(prop.frames.len() as u32 - 1) as usize];
            if src.get(lx, ly).a != 0 {
                return Some(actor.id);
            }
        }
        None
    }

    // ---- memory budget protocol (engine pattern) --------------------------------------------

    pub fn mem_budgets(&self) -> (usize, usize) {
        self.mem_budget_override.unwrap_or((SCENE_MEM_SOFT, SCENE_MEM_HARD))
    }
    pub fn set_mem_budgets(&mut self, soft: usize, hard: usize) {
        self.mem_budget_override = Some((soft, hard.max(soft)));
    }
    pub fn mem_refusal_state(&self) -> (u32, Option<&str>) {
        (self.mem_refusals, self.mem_last_refusal.as_deref())
    }
    pub fn mem_recalibrate(&mut self) -> usize {
        self.mem_exact = self.scene.budgeted_bytes();
        self.mem_exact
    }
    fn mem_refuse(&mut self, what: &str) {
        self.mem_refusals += 1;
        self.mem_last_refusal = Some(what.to_string());
    }

    // ---- edit plumbing ----------------------------------------------------------------------

    fn bump(&mut self) {
        self.cache_epoch = self.cache_epoch.wrapping_add(1);
    }

    fn push_edit(&mut self, e: SceneEdit) {
        self.history.push(e);
        self.bump();
    }

    /// Route a track mutation: inside a gesture the first touch snapshots the track and no
    /// record is pushed (EndGesture coalesces); outside, one TrackEdit per call.
    fn edit_track(&mut self, actor: ActorId, prop: TrackProp, f: impl FnOnce(&mut Track)) {
        let Some(a) = self.scene.actor_mut(actor) else { return };
        let before = a.tracks.get(prop).clone();
        f(a.tracks.get_mut(prop));
        let after = a.tracks.get(prop).clone();
        if before == after {
            return;
        }
        if let Some(g) = self.gesture.as_mut() {
            g.entry((actor, prop.index())).or_insert(before);
            self.bump();
        } else {
            self.push_edit(SceneEdit::TrackEdit { id: actor, prop, before, after });
        }
    }

    fn end_gesture(&mut self) {
        let Some(g) = self.gesture.take() else { return };
        let mut parts: Vec<SceneEdit> = Vec::new();
        for ((actor, prop_ix), before) in g {
            let prop = TrackProp::ALL[prop_ix];
            let Some(a) = self.scene.actor(actor) else { continue };
            let after = a.tracks.get(prop).clone();
            if before != after {
                parts.push(SceneEdit::TrackEdit { id: actor, prop, before, after });
            }
        }
        match parts.len() {
            0 => {}
            1 => self.push_edit(parts.pop().expect("one part")),
            _ => {
                // Deterministic member order (actor id, then property index).
                parts.sort_by_key(|e| match e {
                    SceneEdit::TrackEdit { id, prop, .. } => (*id, prop.index()),
                    _ => (u32::MAX, 0),
                });
                self.push_edit(SceneEdit::Compound(parts));
            }
        }
    }

    fn sanitize(&mut self) {
        if self.scene.frame_count == 0 {
            self.scene.frame_count = 1;
        }
        self.scene.loop_b = self.scene.loop_b.min(self.scene.frame_count - 1);
        self.scene.loop_a = self.scene.loop_a.min(self.scene.loop_b);
        self.playhead = self.playhead.min(self.scene.frame_count - 1);
        if let Some(sel) = self.selected_actor {
            if self.scene.actor(sel).is_none() {
                self.selected_actor = None;
            }
        }
    }

    // ---- undo/redo --------------------------------------------------------------------------

    fn apply_edit(&mut self, e: &SceneEdit, forward: bool) {
        match e {
            SceneEdit::SceneMeta { before, after } => {
                (if forward { after } else { before }).apply(&mut self.scene);
            }
            SceneEdit::CastInsert { index, prop } => {
                if forward {
                    let i = (*index).min(self.scene.cast.len());
                    self.scene.cast.insert(i, (**prop).clone());
                } else if *index < self.scene.cast.len() {
                    self.scene.cast.remove(*index);
                }
            }
            SceneEdit::CastRemove { index, prop, actors } => {
                if forward {
                    // Remove the actors (descending index order), then the prop.
                    let mut idxs: Vec<usize> = actors.iter().map(|(i, _)| *i).collect();
                    idxs.sort_unstable_by(|a, b| b.cmp(a));
                    for i in idxs {
                        if i < self.scene.actors.len() {
                            self.scene.actors.remove(i);
                        }
                    }
                    if *index < self.scene.cast.len() {
                        self.scene.cast.remove(*index);
                    }
                } else {
                    let i = (*index).min(self.scene.cast.len());
                    self.scene.cast.insert(i, (**prop).clone());
                    let mut pairs: Vec<&(usize, Arc<Actor>)> = actors.iter().collect();
                    pairs.sort_by_key(|(i, _)| *i);
                    for (i, a) in pairs {
                        let i = (*i).min(self.scene.actors.len());
                        self.scene.actors.insert(i, (**a).clone());
                    }
                }
            }
            SceneEdit::PropMeta { id, before, after } => {
                if let Some(p) = self.scene.prop_mut(*id) {
                    (if forward { after } else { before }).apply(p);
                }
            }
            SceneEdit::ActorInsert { index, actor } => {
                if forward {
                    let i = (*index).min(self.scene.actors.len());
                    self.scene.actors.insert(i, (**actor).clone());
                } else if *index < self.scene.actors.len() {
                    self.scene.actors.remove(*index);
                }
            }
            SceneEdit::ActorRemove { index, actor } => {
                if forward {
                    if *index < self.scene.actors.len() {
                        self.scene.actors.remove(*index);
                    }
                } else {
                    let i = (*index).min(self.scene.actors.len());
                    self.scene.actors.insert(i, (**actor).clone());
                }
            }
            SceneEdit::ActorMeta { id, before, after } => {
                if let Some(a) = self.scene.actor_mut(*id) {
                    (if forward { after } else { before }).apply(a);
                }
            }
            SceneEdit::ActorZ { from, to } => {
                let (src, dst) = if forward { (*from, *to) } else { (*to, *from) };
                if src < self.scene.actors.len() && dst < self.scene.actors.len() {
                    let a = self.scene.actors.remove(src);
                    self.scene.actors.insert(dst, a);
                }
            }
            SceneEdit::TrackEdit { id, prop, before, after } => {
                if let Some(a) = self.scene.actor_mut(*id) {
                    *a.tracks.get_mut(*prop) = if forward { after.clone() } else { before.clone() };
                }
            }
            SceneEdit::Compound(parts) => {
                if forward {
                    for p in parts {
                        self.apply_edit(p, true);
                    }
                } else {
                    for p in parts.iter().rev() {
                        self.apply_edit(p, false);
                    }
                }
            }
        }
    }

    fn undo(&mut self) {
        self.gesture = None; // an open bracket dies with the step (its edits were unrecorded)
        if let Some(e) = self.history.pop_undo() {
            self.apply_edit(&e, false);
            self.history.park_redo(e);
            self.mem_recalibrate();
            self.sanitize();
            self.bump();
        }
    }

    fn redo(&mut self) {
        self.gesture = None;
        if let Some(e) = self.history.pop_redo() {
            self.apply_edit(&e, true);
            self.history.park_undo(e);
            self.mem_recalibrate();
            self.sanitize();
            self.bump();
        }
    }

    // ---- cast & actor helpers ---------------------------------------------------------------

    /// Estimate a dense art payload before building it (the pre-materialization budget gate).
    fn dense_estimate(w: u32, h: u32, frames: u32) -> usize {
        let tiles_x = w.div_ceil(32) as usize;
        let tiles_y = h.div_ceil(32) as usize;
        tiles_x * tiles_y * 4096 * frames as usize
    }

    /// Insert a fully-built Prop (the ONE cast-growing chokepoint): budget-gated, recorded.
    /// Returns the id, or None on refusal.
    pub(crate) fn insert_prop(&mut self, mut prop: Prop, label: &str) -> Option<PropId> {
        if self.scene.cast.len() >= MAX_PROPS {
            self.mem_refuse("the cast is full");
            return None;
        }
        let (_, hard) = self.mem_budgets();
        // Exact art bytes of the incoming prop (its buffers exist, but nothing is in the scene
        // yet — refusing here drops them without ever entering the document).
        let incoming: usize = prop.frames.iter().map(|f| f.memory_bytes()).sum();
        if self.mem_exact + incoming > hard {
            self.mem_refuse(&format!("'{}' exceeds the scene memory budget", label));
            return None;
        }
        let id = self.scene.prop_ids.alloc();
        prop.id = id;
        let index = self.scene.cast.len();
        self.scene.cast.push(prop);
        let arc = Arc::new(self.scene.cast[index].clone());
        self.push_edit(SceneEdit::CastInsert { index, prop: arc });
        self.mem_recalibrate();
        Some(id)
    }

    fn place_actor(&mut self, prop: PropId, x: i32, y: i32) {
        if self.scene.actors.len() >= MAX_ACTORS {
            return;
        }
        let Some(p) = self.scene.prop(prop) else { return };
        let (pw, ph, pname) = (p.w, p.h, p.name.clone());
        let id = self.scene.actor_ids.alloc();
        let n = self.scene.actors.iter().filter(|a| a.prop == prop).count() + 1;
        let mut tracks = Tracks::default_for(pw, ph);
        tracks.get_mut(TrackProp::X).base = TrackProp::X.clamp(x as i64);
        tracks.get_mut(TrackProp::Y).base = TrackProp::Y.clamp(y as i64);
        let actor = Actor {
            id,
            name: if n == 1 { pname } else { format!("{} {}", pname, n) },
            prop,
            mode: ActorMode::Playing,
            pin_to: None,
            visible: true,
            tracks,
        };
        let index = self.scene.actors.len();
        self.scene.actors.push(actor);
        self.push_edit(SceneEdit::ActorInsert {
            index,
            actor: Arc::new(self.scene.actors[index].clone()),
        });
        self.selected_actor = Some(id);
    }

    fn remove_actor(&mut self, id: ActorId) {
        let Some(index) = self.scene.actor_index(id) else { return };
        // Clear pins pointing at the removed actor first (part of the same undo step).
        let mut parts: Vec<SceneEdit> = Vec::new();
        for a in self.scene.actors.iter_mut() {
            if a.pin_to == Some(id) {
                let before = ActorMetaRec::of(a);
                a.pin_to = None;
                parts.push(SceneEdit::ActorMeta { id: a.id, before, after: ActorMetaRec::of(a) });
            }
        }
        let actor = Arc::new(self.scene.actors[index].clone());
        self.scene.actors.remove(index);
        parts.push(SceneEdit::ActorRemove { index, actor });
        let e = if parts.len() == 1 { parts.pop().expect("one part") } else { SceneEdit::Compound(parts) };
        self.push_edit(e);
        self.sanitize();
    }

    fn remove_prop(&mut self, id: PropId) {
        let Some(index) = self.scene.cast.iter().position(|p| p.id == id) else { return };
        let actors: Vec<(usize, Arc<Actor>)> = self
            .scene
            .actors
            .iter()
            .enumerate()
            .filter(|(_, a)| a.prop == id)
            .map(|(i, a)| (i, Arc::new(a.clone())))
            .collect();
        // Also clear pins pointing at any removed actor (compound with the cast removal).
        let removed_ids: Vec<ActorId> = actors.iter().map(|(_, a)| a.id).collect();
        let mut parts: Vec<SceneEdit> = Vec::new();
        for a in self.scene.actors.iter_mut() {
            if a.prop != id {
                if let Some(pin) = a.pin_to {
                    if removed_ids.contains(&pin) {
                        let before = ActorMetaRec::of(a);
                        a.pin_to = None;
                        parts.push(SceneEdit::ActorMeta {
                            id: a.id,
                            before,
                            after: ActorMetaRec::of(a),
                        });
                    }
                }
            }
        }
        let prop = Arc::new(self.scene.cast[index].clone());
        let edit = SceneEdit::CastRemove { index, prop, actors };
        self.apply_edit(&edit, true);
        parts.push(edit);
        let e = if parts.len() == 1 { parts.pop().expect("one part") } else { SceneEdit::Compound(parts) };
        self.history.push(e);
        self.bump();
        self.mem_recalibrate();
        self.sanitize();
    }

    fn prop_meta_edit(&mut self, id: PropId, f: impl FnOnce(&mut Prop)) {
        let Some(p) = self.scene.prop_mut(id) else { return };
        let before = PropMetaRec::of(p);
        f(p);
        p.art_epoch = p.art_epoch.wrapping_add(1);
        let after = PropMetaRec::of(p);
        if before != after {
            self.push_edit(SceneEdit::PropMeta { id, before, after });
        }
    }

    fn actor_meta_edit(&mut self, id: ActorId, f: impl FnOnce(&mut Actor)) {
        let Some(a) = self.scene.actor_mut(id) else { return };
        let before = ActorMetaRec::of(a);
        f(a);
        let after = ActorMetaRec::of(a);
        if before != after {
            self.push_edit(SceneEdit::ActorMeta { id, before, after });
        }
    }

    fn scene_meta_edit(&mut self, f: impl FnOnce(&mut Scene)) {
        let before = SceneMetaRec::of(&self.scene);
        f(&mut self.scene);
        self.sanitize();
        let after = SceneMetaRec::of(&self.scene);
        if before != after {
            self.push_edit(SceneEdit::SceneMeta { before, after });
        }
    }

    // ---- exec -------------------------------------------------------------------------------

    pub fn exec(&mut self, a: SceneAction) {
        use SceneAction::*;
        match a {
            NewScene(w, h, millifps) => {
                let fps = SceneFps::from_millifps(millifps).unwrap_or(SceneFps::F12_5);
                self.scene = Scene::new(w, h, fps);
                self.history.clear();
                self.cache.borrow_mut().clear();
                self.playhead = 0;
                self.selected_actor = None;
                self.playing = false;
                self.gesture = None;
                self.mem_recalibrate();
                self.bump();
            }
            SetFps(millifps) => {
                if let Some(fps) = SceneFps::from_millifps(millifps) {
                    self.scene_meta_edit(|s| s.fps = fps);
                }
            }
            SetFrameCount(n) => {
                let n = n.clamp(1, MAX_SCENE_FRAMES);
                self.scene_meta_edit(|s| {
                    s.frame_count = n;
                    // Keys beyond the end are retained (shrinking is non-destructive); the loop
                    // region clamps via sanitize.
                });
            }
            SetBackground(c) => self.scene_meta_edit(|s| s.background = c),
            SetLoop(a0, b0) => {
                let fc = self.scene.frame_count;
                let b = b0.min(fc - 1);
                let a0 = a0.min(b);
                self.scene_meta_edit(|s| {
                    s.loop_a = a0;
                    s.loop_b = b;
                });
            }
            GenProp(w, h, frames, seed) => {
                let w = w.clamp(1, MAX_PROP_DIM);
                let h = h.clamp(1, MAX_PROP_DIM);
                let frames = frames.clamp(1, MAX_PROP_FRAMES as u32);
                let (_, hard) = self.mem_budgets();
                if self.mem_exact + Self::dense_estimate(w, h, frames) > hard {
                    self.mem_refuse("'GenProp' exceeds the scene memory budget");
                    return;
                }
                let mut rng = SeededRng::new(seed);
                let mut bufs = Vec::with_capacity(frames as usize);
                for _ in 0..frames {
                    let mut b = RgbaBuffer::new(w, h);
                    for y in 0..h as i32 {
                        for x in 0..w as i32 {
                            let v = rng.next_u64();
                            b.set(
                                x,
                                y,
                                Rgba8::new(v as u8, (v >> 8) as u8, (v >> 16) as u8, 255),
                            );
                        }
                    }
                    bufs.push(b);
                }
                let prop = Prop {
                    id: 0,
                    name: format!("noise{}", self.scene.cast.len() + 1),
                    w,
                    h,
                    frames: bufs,
                    cycle_map: vec![1; frames as usize],
                    style: PixelStyle::Nearest,
                    has_semi_alpha: false,
                    art_epoch: 0,
                };
                self.insert_prop(prop, "GenProp");
            }
            GenPropSolid(w, h, c) => {
                let w = w.clamp(1, MAX_PROP_DIM);
                let h = h.clamp(1, MAX_PROP_DIM);
                let (_, hard) = self.mem_budgets();
                if self.mem_exact + Self::dense_estimate(w, h, 1) > hard {
                    self.mem_refuse("'GenPropSolid' exceeds the scene memory budget");
                    return;
                }
                let mut b = RgbaBuffer::new(w, h);
                if c.a != 0 {
                    b.fill_rect(makapix_engine::geom::IRect::new(0, 0, w, h), c);
                }
                let prop = Prop {
                    id: 0,
                    name: format!("solid{}", self.scene.cast.len() + 1),
                    w,
                    h,
                    frames: vec![b],
                    cycle_map: vec![1],
                    style: PixelStyle::Nearest,
                    has_semi_alpha: c.a != 0 && c.a != 255,
                    art_epoch: 0,
                };
                self.insert_prop(prop, "GenPropSolid");
            }
            RemoveProp(id) => self.remove_prop(id),
            RenameProp(id, name) => self.prop_meta_edit(id, |p| p.name = name),
            SetPropStyle(id, style) => self.prop_meta_edit(id, |p| p.style = style),
            SetCycleStep(id, frame_ix, steps) => self.prop_meta_edit(id, |p| {
                if let Some(s) = p.cycle_map.get_mut(frame_ix as usize) {
                    *s = steps.clamp(1, MAX_CYCLE_STEP);
                }
            }),
            SetCycleAll(id, steps) => self.prop_meta_edit(id, |p| {
                let s = steps.clamp(1, MAX_CYCLE_STEP);
                for e in p.cycle_map.iter_mut() {
                    *e = s;
                }
            }),
            PlaceActor(prop) => {
                let (w, h) = (self.scene.w as i32, self.scene.h as i32);
                self.place_actor(prop, w / 2, h / 2);
            }
            PlaceActorAt(prop, x, y) => self.place_actor(prop, x, y),
            DuplicateActor(id) => {
                if self.scene.actors.len() >= MAX_ACTORS {
                    return;
                }
                let Some(index) = self.scene.actor_index(id) else { return };
                let mut copy = self.scene.actors[index].clone();
                copy.id = self.scene.actor_ids.alloc();
                copy.name = format!("{} copy", copy.name);
                let at = index + 1;
                self.scene.actors.insert(at, copy);
                self.push_edit(SceneEdit::ActorInsert {
                    index: at,
                    actor: Arc::new(self.scene.actors[at].clone()),
                });
                self.selected_actor = Some(self.scene.actors[at].id);
            }
            RemoveActor(id) => self.remove_actor(id),
            RenameActor(id, name) => self.actor_meta_edit(id, |a| a.name = name),
            SelectActor(id) => {
                if self.scene.actor(id).is_some() {
                    self.selected_actor = Some(id);
                }
            }
            SelectNone => self.selected_actor = None,
            SetActorMode(id, mode) => self.actor_meta_edit(id, |a| a.mode = mode),
            SetPinTo(id, parent) => {
                if id == parent
                    || self.scene.actor(parent).is_none_or(|p| p.pin_to.is_some())
                    || self.scene.actors.iter().any(|a| a.pin_to == Some(id))
                {
                    return; // one level only: parent unpinned, self childless
                }
                self.actor_meta_edit(id, |a| a.pin_to = Some(parent));
            }
            ClearPin(id) => self.actor_meta_edit(id, |a| a.pin_to = None),
            ReorderActor(from, to) => {
                let n = self.scene.actors.len();
                if from >= n || to >= n || from == to {
                    return;
                }
                let a = self.scene.actors.remove(from);
                self.scene.actors.insert(to, a);
                self.push_edit(SceneEdit::ActorZ { from, to });
            }
            SetActorVisible(id, v) => self.actor_meta_edit(id, |a| a.visible = v),
            SetBase(actor, prop, v) => {
                let v = prop.clamp(v);
                self.edit_track(actor, prop, |t| t.base = v);
            }
            SetKey(actor, prop, frame, v) => {
                let v = prop.clamp(v);
                let frame = frame.min(MAX_SCENE_FRAMES - 1);
                let default = if prop.hold_only() { Tween::Hold } else { Tween::Linear };
                self.edit_track(actor, prop, |t| t.upsert(frame, v, default));
            }
            SetKeyTween(actor, prop, frame, v, tw) => {
                let v = prop.clamp(v);
                let frame = frame.min(MAX_SCENE_FRAMES - 1);
                let tw = if prop.hold_only() { Tween::Hold } else { tw };
                self.edit_track(actor, prop, |t| {
                    t.upsert(frame, v, tw);
                    if let Some(i) = t.key_at(frame) {
                        t.keys[i].tween = tw;
                    }
                });
            }
            RemoveKey(actor, prop, frame) => {
                self.edit_track(actor, prop, |t| {
                    t.remove(frame);
                });
            }
            MoveKey(actor, prop, from, to) => {
                let to = to.min(MAX_SCENE_FRAMES - 1);
                if from == to {
                    return;
                }
                self.edit_track(actor, prop, |t| {
                    if let Some(i) = t.key_at(from) {
                        let k = t.keys.remove(i);
                        t.upsert(to, k.v, k.tween);
                        // Landing on an existing key replaced its value but kept its tween;
                        // carry the moved key's tween explicitly.
                        if let Some(j) = t.key_at(to) {
                            t.keys[j].tween = k.tween;
                        }
                    }
                });
            }
            MoveActorKeys(actor, from, to) => {
                let to = to.min(MAX_SCENE_FRAMES - 1);
                if from == to {
                    return;
                }
                // One undo step across every track keyed at `from` (Tracks-level retime).
                let had_gesture = self.gesture.is_some();
                if !had_gesture {
                    self.gesture = Some(HashMap::new());
                }
                for prop in TrackProp::ALL {
                    let has = self
                        .scene
                        .actor(actor)
                        .map(|a| a.tracks.get(prop).key_at(from).is_some())
                        .unwrap_or(false);
                    if has {
                        self.exec(SceneAction::MoveKey(actor, prop, from, to));
                    }
                }
                if !had_gesture {
                    self.end_gesture();
                }
            }
            SetTween(actor, prop, frame, tw) => {
                let tw = if prop.hold_only() { Tween::Hold } else { tw };
                self.edit_track(actor, prop, |t| {
                    if let Some(i) = t.key_at(frame) {
                        t.keys[i].tween = tw;
                    }
                });
            }
            ClearTrack(actor, prop) => {
                let at = self.playhead;
                self.edit_track(actor, prop, |t| {
                    let v = eval::eval_track(t, at);
                    t.keys.clear();
                    t.base = v;
                });
            }
            SetAtPlayhead(actor, prop, v) => {
                let v = prop.clamp(v);
                let frame = self.playhead;
                let auto = self.auto_key;
                let default = if prop.hold_only() { Tween::Hold } else { Tween::Linear };
                self.edit_track(actor, prop, |t| {
                    if auto || !t.keys.is_empty() {
                        // An un-keyed edit on a keyed track must land as a key or it would not
                        // render (preview truth).
                        t.upsert(frame, v, default);
                    } else {
                        t.base = v;
                    }
                });
            }
            BeginGesture => {
                if self.gesture.is_none() {
                    self.gesture = Some(HashMap::new());
                }
            }
            EndGesture => self.end_gesture(),
            SetPlayhead(f) => {
                self.playhead = f.min(self.scene.frame_count - 1);
                self.playing = false;
            }
            SetAutoKey(b) => self.auto_key = b,
            Play => {
                if !self.playing {
                    self.playing = true;
                    self.clock_us = 0;
                    self.play_start_frame = self.playhead;
                }
            }
            Pause => {
                if self.playing {
                    self.playhead = self.current_play_frame();
                    self.playing = false;
                }
            }
            AdvanceClock(ms) => {
                if self.playing {
                    self.clock_us = self.clock_us.saturating_add(ms.saturating_mul(1000));
                }
            }
            Undo => self.undo(),
            Redo => self.redo(),
            ClearHistory => self.history.clear(),
            SetMemBudget(soft, hard) => self.set_mem_budgets(soft as usize, hard as usize),
        }
    }

    // ---- .mkps persistence (P3) -------------------------------------------------------------

    /// Serialize the Scene (+ the playhead as persisted session state) to plain `.mkps` bytes.
    pub fn save_bytes(&self) -> Vec<u8> {
        crate::io::save_to_bytes(&self.scene, self.playhead)
    }

    /// [`SceneSession::save_bytes`] inside the MKPZ DEFLATE envelope (explicit Save/export;
    /// autosave uses plain, the editor's convention).
    pub fn save_bytes_compact(&self) -> Vec<u8> {
        makapix_codec::mkpx_compact::compress(&self.save_bytes())
    }

    /// Replace the session's document from `.mkps` bytes (plain or compact, sniffed compact
    /// FIRST — same as the editor's loader). The loader budget-refuses oversized dictionaries
    /// before materializing; history, gesture, selection, and caches reset.
    pub fn load_bytes(&mut self, data: &[u8]) -> Result<(), crate::io::SceneIoError> {
        let plain;
        let bytes: &[u8] = if makapix_codec::mkpx_compact::is_compact(data) {
            plain = makapix_codec::mkpx_compact::open(data)
                .map_err(|_| crate::io::SceneIoError::Corrupt("compact envelope"))?;
            &plain
        } else {
            data
        };
        let (_, hard) = self.mem_budgets();
        let (scene, playhead) = crate::io::load_from_bytes(bytes, hard)?;
        self.scene = scene;
        self.playhead = playhead.min(self.scene.frame_count - 1);
        self.selected_actor = None;
        self.playing = false;
        self.gesture = None;
        self.history.clear();
        self.cache.borrow_mut().clear();
        self.mem_recalibrate();
        self.bump();
        Ok(())
    }

    // ---- Prop import (P2) — the ONE art-ingestion chokepoint --------------------------------

    /// Import art as Prop(s): `.mkpx` (plain or compact, by signature — whole drawing, or one
    /// Prop per layer with `split_layers`) or any codec raster (PNG/GIF/WEBP/APNG/BMP/JPEG).
    /// Cycles quantize to the Scene grid here (ADR-0001). With `place_actors`, each new Prop
    /// gets an Actor (split parts self-assemble at their original alignment and z-order — the
    /// "layers become limbs" moment). The whole import is ONE undo step. Budget-refused
    /// imports leave the Scene untouched and return Err (the P-0 lesson: imports go through
    /// the chokepoint).
    pub fn import_prop_bytes(
        &mut self,
        data: &[u8],
        name: &str,
        split_layers: bool,
        place_actors: bool,
    ) -> Result<ImportOutcome, String> {
        let built = self.build_import_props(data, name, split_layers)?;
        // Budget gate BEFORE any scene mutation, on the exact bytes of everything built.
        if self.scene.cast.len() + built.len() > MAX_PROPS {
            self.mem_refuse("the cast is full");
            return Err("the cast is full".into());
        }
        let incoming: usize =
            built.iter().flat_map(|p| p.frames.iter()).map(|f| f.memory_bytes()).sum();
        let (_, hard) = self.mem_budgets();
        if self.mem_exact + incoming > hard {
            self.mem_refuse("import exceeds the scene memory budget");
            return Err("import exceeds the scene memory budget".into());
        }

        let mut parts: Vec<SceneEdit> = Vec::new();
        let mut outcome = ImportOutcome { props: Vec::new(), actors: Vec::new() };
        for mut prop in built {
            let id = self.scene.prop_ids.alloc();
            prop.id = id;
            let index = self.scene.cast.len();
            self.scene.cast.push(prop);
            parts.push(SceneEdit::CastInsert {
                index,
                prop: Arc::new(self.scene.cast[index].clone()),
            });
            outcome.props.push(id);
            if place_actors && self.scene.actors.len() < MAX_ACTORS {
                let p = &self.scene.cast[index];
                let (pw, ph, pname) = (p.w, p.h, p.name.clone());
                // Split parts align at the source origin (pivot = center → position = center);
                // whole/raster imports center on the Scene.
                let (ax, ay) = if split_layers {
                    ((pw / 2) as i32, (ph / 2) as i32)
                } else {
                    (self.scene.w as i32 / 2, self.scene.h as i32 / 2)
                };
                let aid = self.scene.actor_ids.alloc();
                let mut tracks = Tracks::default_for(pw, ph);
                tracks.get_mut(TrackProp::X).base = TrackProp::X.clamp(ax as i64);
                tracks.get_mut(TrackProp::Y).base = TrackProp::Y.clamp(ay as i64);
                let actor = Actor {
                    id: aid,
                    name: pname,
                    prop: id,
                    mode: ActorMode::Playing,
                    pin_to: None,
                    visible: true,
                    tracks,
                };
                let aindex = self.scene.actors.len();
                self.scene.actors.push(actor);
                parts.push(SceneEdit::ActorInsert {
                    index: aindex,
                    actor: Arc::new(self.scene.actors[aindex].clone()),
                });
                outcome.actors.push(aid);
            }
        }
        if outcome.props.is_empty() {
            return Err("nothing to import".into());
        }
        let e = if parts.len() == 1 { parts.pop().expect("one part") } else { SceneEdit::Compound(parts) };
        self.history.push(e);
        self.bump();
        self.mem_recalibrate();
        if let Some(&last) = outcome.actors.last() {
            self.selected_actor = Some(last);
        }
        Ok(outcome)
    }

    /// Decode `data` into fully-built Props (no scene mutation, no ids assigned).
    fn build_import_props(
        &self,
        data: &[u8],
        name: &str,
        split_layers: bool,
    ) -> Result<Vec<Prop>, String> {
        use makapix_engine::io::SIGNATURE;
        let fps_us = self.scene.fps.frame_us();
        let quant = |dur_us: u32| crate::eval::quantize_duration(dur_us, fps_us);

        // `.mkpx`, plain or inside the MKPZ compact envelope.
        let plain: Option<Vec<u8>> = if makapix_codec::mkpx_compact::is_compact(data) {
            Some(makapix_codec::mkpx_compact::open(data).map_err(|e| e.to_string())?)
        } else if data.len() >= 8 && data[..8] == SIGNATURE {
            Some(data.to_vec())
        } else {
            None
        };

        if let Some(plain) = plain {
            let doc = makapix_engine::io::load_from_bytes_budgeted(
                &plain,
                crate::model::PROP_IMPORT_MAX_BYTES,
            )
            .map_err(|e| e.to_string())?;
            let rect = doc.canvas_rect();
            let (w, h) = (rect.w, rect.h);
            if w > MAX_PROP_DIM || h > MAX_PROP_DIM {
                return Err("Props can be at most 1024 px per side".into());
            }
            if split_layers && doc.frames[0].layers.len() > 1 {
                // One Prop PER LAYER (frame-0 layer list defines the parts); each part's
                // frames are that layer's canvas-rect pixels per document frame.
                let n_layers = doc.frames[0].layers.len();
                let mut props = Vec::with_capacity(n_layers);
                for li in 0..n_layers {
                    let mut frames = Vec::with_capacity(doc.frames.len());
                    let mut cycle = Vec::with_capacity(doc.frames.len());
                    let mut semi = false;
                    for f in &doc.frames {
                        let buf = match f.layers.get(li) {
                            Some(l) => l.pixels.subimage(rect),
                            None => RgbaBuffer::new(w, h),
                        };
                        semi |= has_semi_alpha(&buf);
                        frames.push(buf);
                        cycle.push(quant(f.duration_us));
                    }
                    props.push(Prop {
                        id: 0,
                        name: doc.frames[0].layers[li].name.clone(),
                        w,
                        h,
                        frames,
                        cycle_map: cycle,
                        style: PixelStyle::Nearest,
                        has_semi_alpha: semi,
                        art_epoch: 0,
                    });
                }
                return Ok(props);
            }
            // Whole drawing: per-frame composites.
            let mut frames = Vec::with_capacity(doc.frames.len());
            let mut cycle = Vec::with_capacity(doc.frames.len());
            let mut semi = false;
            for f in &doc.frames {
                let buf = makapix_engine::render::composite_frame(f, rect);
                semi |= has_semi_alpha(&buf);
                frames.push(buf);
                cycle.push(quant(f.duration_us));
            }
            return Ok(vec![Prop {
                id: 0,
                name: if name.is_empty() { "drawing".into() } else { name.into() },
                w,
                h,
                frames,
                cycle_map: cycle,
                style: PixelStyle::Nearest,
                has_semi_alpha: semi,
                art_epoch: 0,
            }]);
        }

        // Raster formats through the codec (tight caps fire DURING decode).
        let decoded = makapix_codec::decode_with_limits(
            data,
            MAX_PROP_FRAMES,
            crate::model::PROP_IMPORT_MAX_BYTES,
        )
        .map_err(|e| e.to_string())?;
        let (w, h) = (decoded[0].w, decoded[0].h);
        if w > MAX_PROP_DIM || h > MAX_PROP_DIM {
            return Err("Props can be at most 1024 px per side".into());
        }
        let mut frames = Vec::with_capacity(decoded.len());
        let mut cycle = Vec::with_capacity(decoded.len());
        let mut semi = false;
        for df in &decoded {
            if df.w != w || df.h != h {
                return Err("animation frames must share one size".into());
            }
            let buf = RgbaBuffer::from_rgba_bytes(w, h, &df.rgba);
            semi |= has_semi_alpha(&buf);
            frames.push(buf);
            cycle.push(quant(df.duration_us));
        }
        Ok(vec![Prop {
            id: 0,
            name: if name.is_empty() { "image".into() } else { name.into() },
            w,
            h,
            frames,
            cycle_map: cycle,
            style: PixelStyle::Nearest,
            has_semi_alpha: semi,
            art_epoch: 0,
        }])
    }

    // ---- state_json / mem_json --------------------------------------------------------------

    fn uses_alpha(&self) -> bool {
        self.scene.actors.iter().filter(|a| a.visible).any(|a| {
            let op = a.tracks.get(TrackProp::Opacity);
            op.base < 255 && op.keys.is_empty()
                || op.keys.iter().any(|k| k.v < 255)
                || self.scene.prop(a.prop).is_some_and(|p| p.has_semi_alpha)
        })
    }

    /// Single-line JSON of the whole session per the seam contract: scene header, cast,
    /// actors (with the pose EVALUATED at the playhead, bounds, resolved source frame, and
    /// all ten tracks), and the memory fields (editor-compatible names).
    pub fn state_json(&self) -> String {
        let mut s = String::with_capacity(2048);
        let sc = &self.scene;
        s.push('{');
        push_kv(&mut s, "w", &sc.w.to_string());
        push_kv(&mut s, "h", &sc.h.to_string());
        push_kv(&mut s, "millifps", &sc.fps.millifps().to_string());
        push_kv(&mut s, "frame_cs", &sc.fps.frame_cs().to_string());
        push_kv(&mut s, "frame_count", &sc.frame_count.to_string());
        push_str_kv(&mut s, "background", &sc.background.to_hex());
        push_kv(&mut s, "playhead", &self.playhead.to_string());
        push_kv(&mut s, "loop", &format!("[{},{}]", sc.loop_a, sc.loop_b));
        push_kv(&mut s, "playing", if self.playing { "true" } else { "false" });
        push_kv(&mut s, "auto_key", if self.auto_key { "true" } else { "false" });
        push_kv(
            &mut s,
            "selected_actor",
            &self.selected_actor.map_or("null".to_string(), |i| i.to_string()),
        );
        push_kv(&mut s, "can_undo", if self.history.can_undo() { "true" } else { "false" });
        push_kv(&mut s, "can_redo", if self.history.can_redo() { "true" } else { "false" });
        push_kv(&mut s, "cache_epoch", &self.cache_epoch.to_string());
        push_kv(&mut s, "uses_alpha", if self.uses_alpha() { "true" } else { "false" });

        s.push_str("\"cast\":[");
        for (i, p) in sc.cast.iter().enumerate() {
            if i > 0 {
                s.push(',');
            }
            s.push('{');
            push_kv(&mut s, "id", &p.id.to_string());
            push_str_kv(&mut s, "name", &p.name);
            push_kv(&mut s, "w", &p.w.to_string());
            push_kv(&mut s, "h", &p.h.to_string());
            push_kv(&mut s, "frames", &p.frames.len().to_string());
            let cycle: Vec<String> = p.cycle_map.iter().map(|c| c.to_string()).collect();
            push_kv(&mut s, "cycle", &format!("[{}]", cycle.join(",")));
            push_kv(&mut s, "cycle_len", &p.cycle_len().to_string());
            push_str_kv(
                &mut s,
                "style",
                if p.style == PixelStyle::CleanEdge { "cleanedge" } else { "nearest" },
            );
            push_kv(&mut s, "has_semi_alpha", if p.has_semi_alpha { "true" } else { "false" });
            s.push_str(&format!("\"art_epoch\":{}", p.art_epoch));
            s.push('}');
        }
        s.push_str("],");

        s.push_str("\"actors\":[");
        for (z, a) in sc.actors.iter().enumerate() {
            if z > 0 {
                s.push(',');
            }
            let pose = eval::eval_tracks(&a.tracks, self.playhead);
            let xf = self.net_xf(a, self.playhead);
            let (pw, ph) = sc.prop(a.prop).map_or((1, 1), |p| (p.w, p.h));
            let (bx, by, bw, bh) = eval::xf_bounds(&xf, pw, ph);
            let src = self.resolved_src_frame(a.id, self.playhead).unwrap_or(0);
            s.push('{');
            push_kv(&mut s, "id", &a.id.to_string());
            push_str_kv(&mut s, "name", &a.name);
            push_kv(&mut s, "prop", &a.prop.to_string());
            push_kv(&mut s, "z", &z.to_string());
            push_str_kv(&mut s, "mode", if a.mode == ActorMode::Posing { "posing" } else { "playing" });
            push_kv(&mut s, "pin_to", &a.pin_to.map_or("null".to_string(), |p| p.to_string()));
            push_kv(&mut s, "visible", if a.visible { "true" } else { "false" });
            push_kv(
                &mut s,
                "pose",
                &format!(
                    "{{\"x\":{},\"y\":{},\"rot_mdeg\":{},\"scale_milli\":{},\"opacity\":{},\"flip_h\":{},\"flip_v\":{},\"pivot_x_milli\":{},\"pivot_y_milli\":{},\"pose\":{}}}",
                    pose.x,
                    pose.y,
                    pose.rot_md,
                    pose.scale_milli,
                    pose.opacity,
                    pose.flip_h,
                    pose.flip_v,
                    pose.pivot_x_milli,
                    pose.pivot_y_milli,
                    pose.pose
                ),
            );
            push_kv(&mut s, "bounds", &format!("[{},{},{},{}]", bx, by, bw, bh));
            push_kv(&mut s, "src_frame", &src.to_string());
            s.push_str("\"tracks\":{");
            for (ti, tp) in TrackProp::ALL.iter().enumerate() {
                if ti > 0 {
                    s.push(',');
                }
                let t = a.tracks.get(*tp);
                s.push_str(&format!("\"{}\":{{\"base\":{},\"keys\":[", tp.name(), t.base));
                for (ki, k) in t.keys.iter().enumerate() {
                    if ki > 0 {
                        s.push(',');
                    }
                    s.push_str(&format!(
                        "{{\"f\":{},\"v\":{},\"tw\":\"{}\"}}",
                        k.frame,
                        k.v,
                        k.tween.name()
                    ));
                }
                s.push_str("]}");
            }
            s.push_str("}}");
        }
        s.push_str("],");

        let (unique, tables) = sc.unique_art_bytes();
        let (soft, hard) = self.mem_budgets();
        push_kv(&mut s, "mem_unique_bytes", &unique.to_string());
        push_kv(&mut s, "mem_table_bytes", &tables.to_string());
        push_kv(&mut s, "mem_budgeted_bytes", &(unique + tables).to_string());
        push_kv(&mut s, "mem_soft_budget", &soft.to_string());
        push_kv(&mut s, "mem_hard_budget", &hard.to_string());
        push_kv(
            &mut s,
            "mem_soft_exceeded",
            if unique + tables > soft { "true" } else { "false" },
        );
        push_kv(&mut s, "mem_refusals", &self.mem_refusals.to_string());
        s.push_str(&format!(
            "\"mem_last_refusal\":{}",
            self.mem_last_refusal
                .as_deref()
                .map_or("null".to_string(), |m| format!("\"{}\"", esc(m)))
        ));
        s.push('}');
        s
    }

    pub fn mem_json(&self) -> String {
        let (unique, tables) = self.scene.unique_art_bytes();
        let (soft, hard) = self.mem_budgets();
        format!(
            "{{\"unique_bytes\":{},\"table_bytes\":{},\"budgeted_bytes\":{},\"soft_budget\":{},\"hard_budget\":{},\"history_bytes\":{},\"refusals\":{}}}",
            unique,
            tables,
            unique + tables,
            soft,
            hard,
            self.history.retained_bytes(),
            self.mem_refusals
        )
    }
}

/// What an import produced (ids in creation order).
#[derive(Clone, Debug, Default)]
pub struct ImportOutcome {
    pub props: Vec<PropId>,
    pub actors: Vec<ActorId>,
}

fn has_semi_alpha(buf: &RgbaBuffer) -> bool {
    if let Some(bb) = buf.opaque_bounds() {
        for y in bb.y..bb.bottom() {
            for x in bb.x..bb.right() {
                let a = buf.get(x, y).a;
                if a != 0 && a != 255 {
                    return true;
                }
            }
        }
    }
    false
}

fn esc(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out
}

fn push_kv(s: &mut String, k: &str, raw: &str) {
    s.push('"');
    s.push_str(k);
    s.push_str("\":");
    s.push_str(raw);
    s.push(',');
}

fn push_str_kv(s: &mut String, k: &str, v: &str) {
    s.push('"');
    s.push_str(k);
    s.push_str("\":\"");
    s.push_str(&esc(v));
    s.push_str("\",");
}
