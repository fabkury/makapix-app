//! The Scene compositor: evaluate every Actor at a frame, resolve its source art (Cycle or
//! Pose), transform it through the cached pixel-exact resampler, and alpha-over blit in
//! z-order. A scene frame is a pure function of the document (ADR-0001's frame grid + the Q8
//! translation semantics), so the transform cache can never change output — `assert.det`
//! (warm vs cold) guards that continuously.

use crate::eval::{self, NetXf};
use crate::model::{PixelStyle, PropId, Scene};
use makapix_engine::buffer::RgbaBuffer;
use makapix_engine::color;
use makapix_engine::geom::{IRect, Point};
use makapix_engine::transform::{actor_resample, ActorXf, SampleStyle};
use std::collections::HashMap;
use std::sync::Arc;

pub const TRANSFORM_CACHE_BUDGET: usize = crate::model::SCENE_HISTORY_BUDGET * 4; // 32 MiB
/// A single rendered entry larger than this bypasses the cache and renders canvas-clipped
/// per frame (a 1024-px prop at 8× would otherwise materialize a ~256 MiB dense buffer).
pub const TRANSFORM_ENTRY_CAP: usize = 16 * 1024 * 1024;

/// Cache key: everything that affects the rendered pixels. The integer part of the
/// translation never changes sampling, so only the Q8 fractional part participates.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub struct CacheKey {
    pub prop: PropId,
    pub frame: u16,
    pub art_epoch: u32,
    pub rot_md: u32, // rem_euclid 360_000 (normalization is part of the semantics)
    pub scale_micro: i64,
    pub flip_h: bool,
    pub flip_v: bool,
    pub pivot_x_milli: i32,
    pub pivot_y_milli: i32,
    pub frac_x_q8: u8,
    pub frac_y_q8: u8,
    pub style: u8, // 0 = nearest, 1 = cleanEdge
}

struct Entry {
    buf: Arc<RgbaBuffer>,
    origin: Point,
    bytes: usize,
    last_use: u64,
}

/// LRU-by-monotonic-tick transform cache (no wall time — deterministic). Eviction can never
/// change output, only cost.
pub struct TransformCache {
    map: HashMap<CacheKey, Entry>,
    bytes: usize,
    budget: usize,
    tick: u64,
}

impl TransformCache {
    pub fn new(budget: usize) -> Self {
        TransformCache { map: HashMap::new(), bytes: 0, budget, tick: 0 }
    }

    pub fn clear(&mut self) {
        self.map.clear();
        self.bytes = 0;
    }

    pub fn bytes(&self) -> usize {
        self.bytes
    }

    pub fn get_or_render(
        &mut self,
        key: CacheKey,
        render: impl FnOnce() -> (RgbaBuffer, Point),
    ) -> (Arc<RgbaBuffer>, Point) {
        self.tick += 1;
        if let Some(e) = self.map.get_mut(&key) {
            e.last_use = self.tick;
            return (e.buf.clone(), e.origin);
        }
        let (buf, origin) = render();
        let bytes = buf.memory_bytes() + buf.tile_table_bytes();
        let arc = Arc::new(buf);
        if bytes <= TRANSFORM_ENTRY_CAP {
            self.bytes += bytes;
            self.map.insert(key, Entry { buf: arc.clone(), origin, bytes, last_use: self.tick });
            while self.bytes > self.budget && self.map.len() > 1 {
                // Evict the least-recently-used entry (skip the one just inserted).
                let victim = self
                    .map
                    .iter()
                    .filter(|(k, _)| **k != key)
                    .min_by_key(|(_, e)| e.last_use)
                    .map(|(k, _)| *k);
                match victim {
                    Some(k) => {
                        if let Some(e) = self.map.remove(&k) {
                            self.bytes = self.bytes.saturating_sub(e.bytes);
                        }
                    }
                    None => break,
                }
            }
        }
        (arc, origin)
    }
}

/// Build the canonical (cache-key + render) transform for an Actor's net xf: rotation
/// normalized, translation split into a whole-pixel blit offset and a Q8 fraction.
pub fn canonicalize(xf: &NetXf) -> (ActorXf, Point) {
    let blit = Point::new(xf.tx_q8.div_euclid(256), xf.ty_q8.div_euclid(256));
    let frac = (xf.tx_q8.rem_euclid(256), xf.ty_q8.rem_euclid(256));
    (
        ActorXf {
            tx_q8: frac.0,
            ty_q8: frac.1,
            rot_md: xf.rot_md.rem_euclid(360_000),
            scale_micro: xf.scale_micro,
            flip_h: xf.flip_h,
            flip_v: xf.flip_v,
            pivot_x_milli: xf.pivot_x_milli,
            pivot_y_milli: xf.pivot_y_milli,
        },
        blit,
    )
}

fn style_of(style: PixelStyle) -> (SampleStyle, u8) {
    match style {
        PixelStyle::Nearest => (SampleStyle::Nearest, 0),
        // The editor's default cleanEdge width (1.0) — a per-Prop width knob can ride later.
        PixelStyle::CleanEdge => (SampleStyle::CleanEdge { line_width: 1.0 }, 1),
    }
}

/// Composite scene frame `n` — the canonical image (straight alpha, canvas-sized).
pub fn scene_frame(scene: &Scene, cache: &mut TransformCache, n: u32) -> RgbaBuffer {
    let (w, h) = (scene.w as u32, scene.h as u32);
    let mut out = RgbaBuffer::new(w, h);
    if scene.background.a != 0 {
        out.fill_rect(IRect::new(0, 0, w, h), scene.background);
    }
    for actor in &scene.actors {
        if !actor.visible {
            continue;
        }
        let pose = eval::eval_tracks(&actor.tracks, n);
        if pose.opacity <= 0 {
            continue;
        }
        let Some(prop) = scene.prop(actor.prop) else { continue };
        if prop.frames.is_empty() {
            continue;
        }
        let net = match actor.pin_to.and_then(|p| scene.actor(p)) {
            Some(parent) => {
                let ppose = eval::eval_tracks(&parent.tracks, n);
                eval::compose_pin(&ppose, &pose)
            }
            None => eval::net_xf(&pose),
        };
        let src_idx = eval::resolve_src_frame(prop, actor.mode, &pose, n);
        let src = &prop.frames[src_idx.min(prop.frames.len() as u32 - 1) as usize];
        let (xf, blit) = canonicalize(&net);
        let (style, style_code) = style_of(prop.style);
        let opacity = pose.opacity.clamp(0, 255) as u8;

        // Entry-cap check on the transformed bbox (frac-translation space).
        let (_, _, bw, bh) = eval::xf_bounds(&net, prop.w, prop.h);
        let dense = (bw.max(0) as usize) * (bh.max(0) as usize) * 4;
        let (buf, origin) = if dense > TRANSFORM_ENTRY_CAP {
            // Uncached, canvas-clipped: clip in frac space = canvas rect shifted by -blit.
            let clip = IRect::new(-blit.x, -blit.y, w, h);
            let (b, o) = actor_resample(src, prop.w, prop.h, &xf, style, Some(clip));
            (Arc::new(b), o)
        } else {
            cache.get_or_render(
                CacheKey {
                    prop: prop.id,
                    frame: src_idx as u16,
                    art_epoch: prop.art_epoch,
                    rot_md: xf.rot_md as u32,
                    scale_micro: xf.scale_micro,
                    flip_h: xf.flip_h,
                    flip_v: xf.flip_v,
                    pivot_x_milli: xf.pivot_x_milli,
                    pivot_y_milli: xf.pivot_y_milli,
                    frac_x_q8: xf.tx_q8 as u8,
                    frac_y_q8: xf.ty_q8 as u8,
                    style: style_code,
                },
                || actor_resample(src, prop.w, prop.h, &xf, style, None),
            )
        };

        // Alpha-over blit with the Actor's opacity, clipped to the canvas.
        if let Some(bb) = buf.opaque_bounds() {
            for y in bb.y..bb.bottom() {
                for x in bb.x..bb.right() {
                    let c = buf.get(x, y);
                    if c.a == 0 {
                        continue;
                    }
                    let dx = blit.x + origin.x + x;
                    let dy = blit.y + origin.y + y;
                    if dx < 0 || dy < 0 || dx >= w as i32 || dy >= h as i32 {
                        continue;
                    }
                    let blended = color::over_opacity(c, out.get(dx, dy), opacity);
                    out.set(dx, dy, blended);
                }
            }
        }
    }
    out
}
