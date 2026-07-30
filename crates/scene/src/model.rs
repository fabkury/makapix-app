//! The Scene document model: a Scene has a Cast of Props performed by Actors, each Actor a set
//! of keyframed Tracks on the Scene's fixed frame grid (ADR-0001). Everything is integer or
//! fixed-point (millidegrees, thousandths, milli-pixels) so evaluation and hashing never fork
//! per platform. Vocabulary is canonical in the repo-root CONTEXT.md.

use makapix_engine::buffer::RgbaBuffer;
use makapix_engine::color::Rgba8;
use makapix_engine::util::{Hasher, IdGen};
use std::collections::HashSet;
use std::sync::Arc;

pub type PropId = u32;
pub type ActorId = u32;

pub const MAX_SCENE_FRAMES: u32 = 1024;
pub const MAX_PROPS: usize = 64;
pub const MAX_ACTORS: usize = 64;
pub const MAX_PROP_FRAMES: usize = 256;
/// Props may exceed the Scene canvas (pans, scrolling backgrounds) up to this per-side cap.
pub const MAX_PROP_DIM: u32 = 1024;
pub const MAX_CYCLE_STEP: u16 = 1024;

// Fixed-point property ranges (also the .mkps loader's Corrupt bounds).
pub const SCALE_MIN_MILLI: i32 = 100; // 0.1× (the engine Resize convention)
pub const SCALE_MAX_MILLI: i32 = 8000; // 8×
pub const ROT_MAX_MILLIDEG: i32 = 7_200_000; // ±20 turns bounds the trig argument
pub const POS_MAX: i32 = 65_536; // scene px; far beyond any legal canvas
pub const PIVOT_MAX_MILLI: i32 = 2_048_000; // prop-local milli-px; ±2×MAX_PROP_DIM allows orbiting

// Memory budgets (feasibility §6). The measured quantity is the unique Prop art payload +
// tile tables (`Scene::unique_art_bytes`), the exact analogue of the editor's document budget.
pub const SCENE_MEM_SOFT: usize = 160 * 1024 * 1024;
pub const SCENE_MEM_HARD: usize = 192 * 1024 * 1024;
pub const SCENE_HISTORY_BUDGET: usize = 8 * 1024 * 1024;
/// Decoded-RGBA ceiling for one Prop import, gated before buffers are built.
pub const PROP_IMPORT_MAX_BYTES: usize = 64 * 1024 * 1024;

/// The curated GIF-safe frame-rate list (ADR-0001): every rate is an exact whole number of
/// GIF centiseconds, so preview timing and export timing are identical by construction.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum SceneFps {
    F10,
    F12_5,
    F20,
    F25,
    F50,
}

impl SceneFps {
    /// Exact GIF centiseconds per frame: 10 | 8 | 5 | 4 | 2.
    pub fn frame_cs(self) -> u32 {
        match self {
            SceneFps::F10 => 10,
            SceneFps::F12_5 => 8,
            SceneFps::F20 => 5,
            SceneFps::F25 => 4,
            SceneFps::F50 => 2,
        }
    }
    pub fn frame_us(self) -> u32 {
        self.frame_cs() * 10_000
    }
    pub fn millifps(self) -> u32 {
        match self {
            SceneFps::F10 => 10_000,
            SceneFps::F12_5 => 12_500,
            SceneFps::F20 => 20_000,
            SceneFps::F25 => 25_000,
            SceneFps::F50 => 50_000,
        }
    }
    pub fn from_millifps(v: u32) -> Option<Self> {
        Some(match v {
            10_000 => SceneFps::F10,
            12_500 => SceneFps::F12_5,
            20_000 => SceneFps::F20,
            25_000 => SceneFps::F25,
            50_000 => SceneFps::F50,
            _ => return None,
        })
    }
    /// The `.mkps` wire value.
    pub fn code(self) -> u8 {
        match self {
            SceneFps::F10 => 0,
            SceneFps::F12_5 => 1,
            SceneFps::F20 => 2,
            SceneFps::F25 => 3,
            SceneFps::F50 => 4,
        }
    }
    pub fn from_code(v: u8) -> Option<Self> {
        Some(match v {
            0 => SceneFps::F10,
            1 => SceneFps::F12_5,
            2 => SceneFps::F20,
            3 => SceneFps::F25,
            4 => SceneFps::F50,
            _ => return None,
        })
    }
    pub const ALL: [SceneFps; 5] =
        [SceneFps::F10, SceneFps::F12_5, SceneFps::F20, SceneFps::F25, SceneFps::F50];
}

/// Per-Prop pixel render style: crisp cleanEdge reconstruction vs. chunky nearest-neighbor —
/// the art's identity, not the placement's (design decision, 02-prioritization).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum PixelStyle {
    Nearest,
    CleanEdge,
}

/// Playing = the Actor loops its Prop's Cycle; Posing = the shown frame is driven by the
/// hold-only `pose` track. A per-Actor mode (design decision). Posing ships after v0.1 but is
/// modeled and persisted from day one.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum ActorMode {
    Playing,
    Posing,
}

/// The easing of the tween FROM a Key TO the next Key. Hold jumps with no interpolation.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Tween {
    Hold,
    Linear,
    EaseIn,
    EaseOut,
    EaseInOut,
}

impl Tween {
    pub fn code(self) -> u8 {
        match self {
            Tween::Hold => 0,
            Tween::Linear => 1,
            Tween::EaseIn => 2,
            Tween::EaseOut => 3,
            Tween::EaseInOut => 4,
        }
    }
    pub fn from_code(v: u8) -> Option<Self> {
        Some(match v {
            0 => Tween::Hold,
            1 => Tween::Linear,
            2 => Tween::EaseIn,
            3 => Tween::EaseOut,
            4 => Tween::EaseInOut,
            _ => return None,
        })
    }
    pub fn name(self) -> &'static str {
        match self {
            Tween::Hold => "hold",
            Tween::Linear => "linear",
            Tween::EaseIn => "easein",
            Tween::EaseOut => "easeout",
            Tween::EaseInOut => "easeinout",
        }
    }
    pub fn parse(s: &str) -> Option<Self> {
        Some(match s {
            "hold" => Tween::Hold,
            "linear" => Tween::Linear,
            "easein" => Tween::EaseIn,
            "easeout" => Tween::EaseOut,
            "easeinout" => Tween::EaseInOut,
            _ => return None,
        })
    }
}

/// One recorded value on the frame grid. All property values are i32 (bools are 0/1, pose is
/// a non-negative frame index) so keys, history, DSL, and the file format stay uniform while
/// evaluation remains pure-integer.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Key {
    pub frame: u32,
    pub v: i32,
    pub tween: Tween,
}

/// One animatable property: `base` when keyless, else the sorted unique-frame key list.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Track {
    pub base: i32,
    pub keys: Vec<Key>,
}

impl Track {
    pub fn constant(base: i32) -> Self {
        Track { base, keys: Vec::new() }
    }
    /// Key index at exactly `frame`, if present.
    pub fn key_at(&self, frame: u32) -> Option<usize> {
        self.keys.binary_search_by_key(&frame, |k| k.frame).ok()
    }
    /// Insert-or-replace at `frame`. A replaced key keeps its existing tween; a new key gets
    /// `default_tween`.
    pub fn upsert(&mut self, frame: u32, v: i32, default_tween: Tween) {
        match self.keys.binary_search_by_key(&frame, |k| k.frame) {
            Ok(i) => self.keys[i].v = v,
            Err(i) => self.keys.insert(i, Key { frame, v, tween: default_tween }),
        }
    }
    pub fn remove(&mut self, frame: u32) -> bool {
        match self.keys.binary_search_by_key(&frame, |k| k.frame) {
            Ok(i) => {
                self.keys.remove(i);
                true
            }
            Err(_) => false,
        }
    }
}

/// The ten animatable properties, in canonical order (also the `.mkps` ACTS track order and
/// the `state_json` map order).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum TrackProp {
    X,
    Y,
    Rot,
    Scale,
    FlipH,
    FlipV,
    Opacity,
    PivotX,
    PivotY,
    Pose,
}

impl TrackProp {
    pub const ALL: [TrackProp; 10] = [
        TrackProp::X,
        TrackProp::Y,
        TrackProp::Rot,
        TrackProp::Scale,
        TrackProp::FlipH,
        TrackProp::FlipV,
        TrackProp::Opacity,
        TrackProp::PivotX,
        TrackProp::PivotY,
        TrackProp::Pose,
    ];
    pub fn index(self) -> usize {
        match self {
            TrackProp::X => 0,
            TrackProp::Y => 1,
            TrackProp::Rot => 2,
            TrackProp::Scale => 3,
            TrackProp::FlipH => 4,
            TrackProp::FlipV => 5,
            TrackProp::Opacity => 6,
            TrackProp::PivotX => 7,
            TrackProp::PivotY => 8,
            TrackProp::Pose => 9,
        }
    }
    /// DSL / state_json token.
    pub fn name(self) -> &'static str {
        match self {
            TrackProp::X => "x",
            TrackProp::Y => "y",
            TrackProp::Rot => "rot",
            TrackProp::Scale => "scale",
            TrackProp::FlipH => "flip_h",
            TrackProp::FlipV => "flip_v",
            TrackProp::Opacity => "opacity",
            TrackProp::PivotX => "pivot_x",
            TrackProp::PivotY => "pivot_y",
            TrackProp::Pose => "pose",
        }
    }
    /// DSL argument token (compact, no underscore — `fliph`, `pivotx`).
    pub fn parse(s: &str) -> Option<Self> {
        Some(match s {
            "x" => TrackProp::X,
            "y" => TrackProp::Y,
            "rot" => TrackProp::Rot,
            "scale" => TrackProp::Scale,
            "fliph" | "flip_h" => TrackProp::FlipH,
            "flipv" | "flip_v" => TrackProp::FlipV,
            "opacity" => TrackProp::Opacity,
            "pivotx" | "pivot_x" => TrackProp::PivotX,
            "pivoty" | "pivot_y" => TrackProp::PivotY,
            "pose" => TrackProp::Pose,
            _ => return None,
        })
    }
    /// Hold-only properties: flips and pose never interpolate (their tween is forced to Hold).
    pub fn hold_only(self) -> bool {
        matches!(self, TrackProp::FlipH | TrackProp::FlipV | TrackProp::Pose)
    }
    /// Clamp a value into this property's legal range.
    pub fn clamp(self, v: i64) -> i32 {
        let (lo, hi) = match self {
            TrackProp::X | TrackProp::Y => (-POS_MAX as i64, POS_MAX as i64),
            TrackProp::Rot => (-ROT_MAX_MILLIDEG as i64, ROT_MAX_MILLIDEG as i64),
            TrackProp::Scale => (SCALE_MIN_MILLI as i64, SCALE_MAX_MILLI as i64),
            TrackProp::FlipH | TrackProp::FlipV => (0, 1),
            TrackProp::Opacity => (0, 255),
            TrackProp::PivotX | TrackProp::PivotY => (-PIVOT_MAX_MILLI as i64, PIVOT_MAX_MILLI as i64),
            TrackProp::Pose => (0, (MAX_PROP_FRAMES - 1) as i64),
        };
        v.clamp(lo, hi) as i32
    }
    /// Whether a value is inside this property's legal range (the loader's Corrupt check).
    pub fn in_range(self, v: i32) -> bool {
        self.clamp(v as i64) == v
    }
}

/// The ten tracks of one Actor, indexed by [`TrackProp::index`].
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Tracks(pub [Track; 10]);

impl Tracks {
    /// Defaults for a Prop of `w`×`h`: identity transform, full opacity, centered pivot
    /// (milli-pixels), pose 0. Position base is overwritten by PlaceActor.
    pub fn default_for(w: u32, h: u32) -> Self {
        Tracks([
            Track::constant(0),                 // x
            Track::constant(0),                 // y
            Track::constant(0),                 // rot
            Track::constant(1000),              // scale
            Track::constant(0),                 // flip_h
            Track::constant(0),                 // flip_v
            Track::constant(255),               // opacity
            Track::constant((w * 500) as i32),  // pivot_x = w/2 px
            Track::constant((h * 500) as i32),  // pivot_y
            Track::constant(0),                 // pose
        ])
    }
    pub fn get(&self, p: TrackProp) -> &Track {
        &self.0[p.index()]
    }
    pub fn get_mut(&mut self, p: TrackProp) -> &mut Track {
        &mut self.0[p.index()]
    }
}

/// A piece of art in the Cast: 1..=256 frames of shared `w`×`h`, its Cycle mapping (scene
/// frames per prop frame, quantized at import per ADR-0001), and its pixel style.
#[derive(Clone)]
pub struct Prop {
    pub id: PropId,
    pub name: String,
    pub w: u32,
    pub h: u32,
    pub frames: Vec<RgbaBuffer>,
    /// Scene frames each prop frame holds during Playing; len == frames.len(), entries 1..=1024.
    pub cycle_map: Vec<u16>,
    pub style: PixelStyle,
    /// Any pixel with 0 < a < 255 (scanned once at import) — drives the GIF threshold notice.
    pub has_semi_alpha: bool,
    /// Bumped whenever the art or style changes; part of the transform-cache key (P2).
    pub art_epoch: u32,
}

impl Prop {
    /// Total Cycle length in scene frames (≥ 1).
    pub fn cycle_len(&self) -> u32 {
        self.cycle_map.iter().map(|&s| s as u32).sum::<u32>().max(1)
    }
    /// Playing-mode source frame for a scene frame: the unique j with
    /// `prefix[j] <= scene_frame % cycle_len < prefix[j+1]`.
    pub fn cycle_frame(&self, scene_frame: u32) -> u32 {
        let m = scene_frame % self.cycle_len();
        let mut acc = 0u32;
        for (j, &steps) in self.cycle_map.iter().enumerate() {
            acc += steps as u32;
            if m < acc {
                return j as u32;
            }
        }
        (self.frames.len().saturating_sub(1)) as u32
    }
}

/// One placement of a Prop — the thing you tap, transform, and keyframe on the Stage.
#[derive(Clone, Debug)]
pub struct Actor {
    pub id: ActorId,
    pub name: String,
    pub prop: PropId,
    pub mode: ActorMode,
    /// One-level parenting ("pin to"): the target must exist, differ from self, and be
    /// unpinned. Format-level in v0.1 (no UI).
    pub pin_to: Option<ActorId>,
    pub visible: bool,
    pub tracks: Tracks,
}

/// The Animator's document. `actors` vec order IS z-order: index 0 draws first (bottom) —
/// the engine's layer-stack convention.
#[derive(Clone)]
pub struct Scene {
    pub w: u16,
    pub h: u16,
    pub fps: SceneFps,
    pub frame_count: u32,
    pub background: Rgba8,
    /// Review loop region (inclusive), persisted session state: `loop_a <= loop_b < frame_count`.
    pub loop_a: u32,
    pub loop_b: u32,
    pub cast: Vec<Prop>,
    pub actors: Vec<Actor>,
    pub prop_ids: IdGen,
    pub actor_ids: IdGen,
}

impl Scene {
    /// New Scene at `w`×`h` (clamped to the engine's 1..=256 canvas range) with two seconds of
    /// frames at `fps`, a transparent background, and a full-range loop.
    pub fn new(w: u16, h: u16, fps: SceneFps) -> Self {
        use makapix_engine::geom::{MAX_DIM, MIN_DIM};
        let w = w.clamp(MIN_DIM, MAX_DIM);
        let h = h.clamp(MIN_DIM, MAX_DIM);
        let frame_count = (2_000_000 / fps.frame_us()).clamp(1, MAX_SCENE_FRAMES);
        Scene {
            w,
            h,
            fps,
            frame_count,
            background: Rgba8::TRANSPARENT,
            loop_a: 0,
            loop_b: frame_count - 1,
            cast: Vec::new(),
            actors: Vec::new(),
            prop_ids: IdGen::starting_at(1),
            actor_ids: IdGen::starting_at(1),
        }
    }

    pub fn prop(&self, id: PropId) -> Option<&Prop> {
        self.cast.iter().find(|p| p.id == id)
    }
    pub fn prop_mut(&mut self, id: PropId) -> Option<&mut Prop> {
        self.cast.iter_mut().find(|p| p.id == id)
    }
    pub fn actor(&self, id: ActorId) -> Option<&Actor> {
        self.actors.iter().find(|a| a.id == id)
    }
    pub fn actor_mut(&mut self, id: ActorId) -> Option<&mut Actor> {
        self.actors.iter_mut().find(|a| a.id == id)
    }
    pub fn actor_index(&self, id: ActorId) -> Option<usize> {
        self.actors.iter().position(|a| a.id == id)
    }

    /// Semantic content hash over every model field in canonical order (prop art via the
    /// per-frame buffer content hashes). The `.mkps` round-trip invariant.
    pub fn content_hash(&self) -> u128 {
        let mut h = Hasher::new();
        h.write_u32(self.w as u32);
        h.write_u32(self.h as u32);
        h.write_u32(self.fps.millifps());
        h.write_u32(self.frame_count);
        h.write(&[self.background.r, self.background.g, self.background.b, self.background.a]);
        h.write_u32(self.loop_a);
        h.write_u32(self.loop_b);
        h.write_u32(self.cast.len() as u32);
        for p in &self.cast {
            h.write_u32(p.id);
            h.write(p.name.as_bytes());
            h.write_u32(p.w);
            h.write_u32(p.h);
            h.write_u32(p.frames.len() as u32);
            for f in &p.frames {
                let fh = f.content_hash();
                h.write(&fh.to_le_bytes());
            }
            for &s in &p.cycle_map {
                h.write_u32(s as u32);
            }
            h.write(&[matches!(p.style, PixelStyle::CleanEdge) as u8, p.has_semi_alpha as u8]);
        }
        h.write_u32(self.actors.len() as u32);
        for a in &self.actors {
            h.write_u32(a.id);
            h.write(a.name.as_bytes());
            h.write_u32(a.prop);
            h.write(&[matches!(a.mode, ActorMode::Posing) as u8, a.visible as u8]);
            h.write_u32(a.pin_to.map_or(0, |p| p.wrapping_add(1)));
            for tp in TrackProp::ALL {
                let t = a.tracks.get(tp);
                h.write_u32(t.base as u32);
                h.write_u32(t.keys.len() as u32);
                for k in &t.keys {
                    h.write_u32(k.frame);
                    h.write_u32(k.v as u32);
                    h.write(&[k.tween.code()]);
                }
            }
        }
        h.finish()
    }

    /// The budgeted quantity: (unique materialized tile payload, tile-table bytes) across all
    /// Prop frames, deduped by `Arc` pointer — the editor's `budgeted_bytes` analogue.
    pub fn unique_art_bytes(&self) -> (usize, usize) {
        let mut seen: HashSet<*const ()> = HashSet::new();
        let mut tables: HashSet<*const ()> = HashSet::new();
        let mut payload = 0usize;
        let mut table_bytes = 0usize;
        for p in &self.cast {
            for f in &p.frames {
                if tables.insert(f.table_ptr()) {
                    table_bytes += f.tile_table_bytes();
                }
                f.visit_tile_arcs(&mut |t| {
                    if seen.insert(Arc::as_ptr(t) as *const ()) {
                        payload += 4096;
                    }
                });
            }
        }
        (payload, table_bytes)
    }

    /// payload + tables — what the soft/hard budgets are enforced on.
    pub fn budgeted_bytes(&self) -> usize {
        let (p, t) = self.unique_art_bytes();
        p + t
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fps_table_is_exact() {
        for f in SceneFps::ALL {
            assert_eq!(f.frame_cs() * 10_000, f.frame_us());
            assert_eq!(SceneFps::from_millifps(f.millifps()), Some(f));
            assert_eq!(SceneFps::from_code(f.code()), Some(f));
            // The ADR-0001 guarantee: exact centiseconds.
            assert_eq!(100_000 % f.frame_us() % 10_000, 0);
        }
        assert_eq!(SceneFps::from_millifps(30_000), None);
        assert_eq!(SceneFps::from_code(9), None);
    }

    #[test]
    fn new_scene_defaults() {
        let s = Scene::new(64, 64, SceneFps::F12_5);
        assert_eq!(s.frame_count, 25); // 2 s at 12.5 fps
        assert_eq!((s.loop_a, s.loop_b), (0, 24));
        let s = Scene::new(999, 0, SceneFps::F50);
        assert_eq!((s.w, s.h), (256, 1)); // clamped to canvas range
        assert_eq!(s.frame_count, 100);
    }

    #[test]
    fn track_upsert_keeps_existing_tween() {
        let mut t = Track::constant(0);
        t.upsert(5, 10, Tween::Linear);
        t.upsert(2, 4, Tween::Hold);
        assert_eq!(t.keys.iter().map(|k| k.frame).collect::<Vec<_>>(), [2, 5]);
        t.upsert(5, 99, Tween::EaseIn); // replace: value updates, tween stays Linear
        assert_eq!(t.keys[1].v, 99);
        assert_eq!(t.keys[1].tween, Tween::Linear);
        assert!(t.remove(2));
        assert!(!t.remove(2));
    }

    #[test]
    fn cycle_frame_table() {
        let p = Prop {
            id: 1,
            name: "p".into(),
            w: 8,
            h: 8,
            frames: vec![RgbaBuffer::new(8, 8), RgbaBuffer::new(8, 8), RgbaBuffer::new(8, 8)],
            cycle_map: vec![2, 2, 2],
            style: PixelStyle::Nearest,
            has_semi_alpha: false,
            art_epoch: 0,
        };
        assert_eq!(p.cycle_len(), 6);
        let got: Vec<u32> = (0..8).map(|f| p.cycle_frame(f)).collect();
        assert_eq!(got, [0, 0, 1, 1, 2, 2, 0, 0]);
    }

    #[test]
    fn prop_clamps() {
        assert_eq!(TrackProp::Scale.clamp(0), 100);
        assert_eq!(TrackProp::Scale.clamp(99_999), 8000);
        assert_eq!(TrackProp::Opacity.clamp(-5), 0);
        assert_eq!(TrackProp::FlipH.clamp(7), 1);
        assert!(TrackProp::Rot.in_range(90_000));
        assert!(!TrackProp::Rot.in_range(i32::MAX));
    }

    #[test]
    fn content_hash_tracks_field_classes() {
        let mut s = Scene::new(32, 32, SceneFps::F25);
        let h0 = s.content_hash();
        s.frame_count = 77;
        let h1 = s.content_hash();
        assert_ne!(h0, h1);
        s.background = Rgba8::new(1, 2, 3, 4);
        assert_ne!(h1, s.content_hash());
    }
}
