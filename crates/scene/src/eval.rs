//! Keyframe evaluation — the normative tween semantics (pure integer, Q16 easing), plus the
//! net-transform composition (`net_xf` / `compose_pin`) the compositor consumes. Every rule
//! here is part of the seam contract with the shell: the engine evaluates, Dart never
//! re-implements tween math.

use crate::model::{ActorMode, Prop, Track, TrackProp, Tracks, Tween};
use makapix_engine::transform::rot_cos_sin;

/// Q16 fixed-point one.
pub const ONE_Q16: i64 = 65_536;

/// Easing curve over Q16 progress. Endpoints are exact by construction for every curve:
/// e(0) = 0, e(ONE) = ONE (unit-tested).
pub fn ease_q16(tween: Tween, u: i64) -> i64 {
    match tween {
        Tween::Hold => 0, // callers short-circuit Hold; defensive zero here
        Tween::Linear => u,
        Tween::EaseIn => (u * u) >> 16,
        Tween::EaseOut => ONE_Q16 - (((ONE_Q16 - u) * (ONE_Q16 - u)) >> 16),
        // smoothstep t²(3−2t)
        Tween::EaseInOut => (((u * u) >> 16) * (3 * ONE_Q16 - 2 * u)) >> 16,
    }
}

/// Integer lerp with round-half-up (in the floored sense): the one documented deterministic
/// rounding rule.
pub fn lerp_i32(v0: i32, v1: i32, e_q16: i64) -> i32 {
    v0 + ((((v1 - v0) as i64 * e_q16) + 32_768) >> 16) as i32
}

/// Evaluate one track at `frame`:
/// - no keys → `base`
/// - before the first key → the first key's value (hold-before)
/// - at/after the last key → the last key's value (hold-after)
/// - exactly on a key → that key's value
/// - between k0 and k1 → k0's tween shapes the segment (Hold = k0's value; rotation
///   interpolates raw millidegrees, no wrap — 0 → 720 000 is two full CW turns).
pub fn eval_track(t: &Track, frame: u32) -> i32 {
    let keys = &t.keys;
    if keys.is_empty() {
        return t.base;
    }
    if frame <= keys[0].frame {
        return keys[0].v;
    }
    let last = &keys[keys.len() - 1];
    if frame >= last.frame {
        return last.v;
    }
    // Segment: the greatest key with k.frame <= frame (binary search; exact hits returned).
    let i = match keys.binary_search_by_key(&frame, |k| k.frame) {
        Ok(i) => return keys[i].v,
        Err(i) => i - 1,
    };
    let (k0, k1) = (&keys[i], &keys[i + 1]);
    if k0.tween == Tween::Hold {
        return k0.v;
    }
    let u = (((frame - k0.frame) as i64) << 16) / ((k1.frame - k0.frame) as i64);
    lerp_i32(k0.v, k1.v, ease_q16(k0.tween, u))
}

/// The evaluated pose of one Actor at one frame — everything the compositor and the shell's
/// overlay need, in the model's fixed-point units.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct ActorPose {
    pub x: i32,
    pub y: i32,
    pub rot_md: i32,
    pub scale_milli: i32,
    pub flip_h: bool,
    pub flip_v: bool,
    pub opacity: i32,
    pub pivot_x_milli: i32,
    pub pivot_y_milli: i32,
    pub pose: u32,
}

pub fn eval_tracks(t: &Tracks, frame: u32) -> ActorPose {
    ActorPose {
        x: eval_track(t.get(TrackProp::X), frame),
        y: eval_track(t.get(TrackProp::Y), frame),
        rot_md: eval_track(t.get(TrackProp::Rot), frame),
        scale_milli: eval_track(t.get(TrackProp::Scale), frame),
        flip_h: eval_track(t.get(TrackProp::FlipH), frame) != 0,
        flip_v: eval_track(t.get(TrackProp::FlipV), frame) != 0,
        opacity: eval_track(t.get(TrackProp::Opacity), frame).clamp(0, 255),
        pivot_x_milli: eval_track(t.get(TrackProp::PivotX), frame),
        pivot_y_milli: eval_track(t.get(TrackProp::PivotY), frame),
        pose: eval_track(t.get(TrackProp::Pose), frame).max(0) as u32,
    }
}

/// Playing: the Prop's Cycle resolves the source frame; Posing: the pose track (clamped).
pub fn resolve_src_frame(prop: &Prop, mode: ActorMode, pose: &ActorPose, scene_frame: u32) -> u32 {
    match mode {
        ActorMode::Playing => prop.cycle_frame(scene_frame),
        ActorMode::Posing => pose.pose.min(prop.frames.len().saturating_sub(1) as u32),
    }
}

/// Quantize-at-import (ADR-0001): scene frames a source frame of `duration_us` holds, at
/// `frame_us` per scene frame — round-half-up, clamped 1..=1024.
pub fn quantize_duration(duration_us: u32, frame_us: u32) -> u16 {
    let steps = (duration_us as u64 + (frame_us as u64) / 2) / frame_us.max(1) as u64;
    steps.clamp(1, 1024) as u16
}

/// The net actor similarity the compositor renders: `dst = T(t)·R(rot)·S(scale)·F(flips)·
/// T(-pivot/1000)`, translation in Q8 (1/256 px — the quantization is part of the DEFINED
/// composition semantics, so cached and cold renders agree by construction).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct NetXf {
    pub tx_q8: i32,
    pub ty_q8: i32,
    pub rot_md: i32,
    /// millionths (thousandths², so a pinned child's product stays exact).
    pub scale_micro: i64,
    pub flip_h: bool,
    pub flip_v: bool,
    pub pivot_x_milli: i32,
    pub pivot_y_milli: i32,
}

/// Unpinned: the pose's own transform. Translation is exact (x·256).
pub fn net_xf(pose: &ActorPose) -> NetXf {
    NetXf {
        tx_q8: pose.x.saturating_mul(256),
        ty_q8: pose.y.saturating_mul(256),
        rot_md: pose.rot_md,
        scale_micro: pose.scale_milli as i64 * 1000,
        flip_h: pose.flip_h,
        flip_v: pose.flip_v,
        pivot_x_milli: pose.pivot_x_milli,
        pivot_y_milli: pose.pivot_y_milli,
    }
}

/// Pinned (one level): `W_child = W_parent · L_child`. The child's (x, y) are coordinates in
/// the PARENT'S prop-local pixel space ("pin to this spot on the parent's art"); the child
/// inherits the parent's rotation/scale/flip but NOT its opacity; the net pivot is the
/// child's own (the innermost `T(-pivot_c)` is untouched by composition).
pub fn compose_pin(parent: &ActorPose, child: &ActorPose) -> NetXf {
    // A reflection conjugates rotation: with exactly one parent flip, the child's rotation
    // runs the other way in world space.
    let s_p: i64 = if parent.flip_h != parent.flip_v { -1 } else { 1 };
    let net_rot_md = (parent.rot_md as i64 + s_p * child.rot_md as i64)
        .clamp(-(crate::model::ROT_MAX_MILLIDEG as i64), crate::model::ROT_MAX_MILLIDEG as i64)
        as i32;
    let net_scale_micro = parent.scale_milli as i64 * child.scale_milli as i64;
    // Child anchor in parent prop-local space, transformed by the parent's R·S·F about the
    // parent pivot, then translated by the parent position.
    let (cos, sin) = rot_cos_sin(parent.rot_md);
    let sx = if parent.flip_h { -1.0 } else { 1.0 };
    let sy = if parent.flip_v { -1.0 } else { 1.0 };
    let s = parent.scale_milli as f32 / 1000.0;
    let lx = (child.x as f32 - parent.pivot_x_milli as f32 / 1000.0) * sx * s;
    let ly = (child.y as f32 - parent.pivot_y_milli as f32 / 1000.0) * sy * s;
    let wx = parent.x as f32 + cos * lx - sin * ly;
    let wy = parent.y as f32 + sin * lx + cos * ly;
    NetXf {
        tx_q8: (wx * 256.0 + 0.5).floor() as i32,
        ty_q8: (wy * 256.0 + 0.5).floor() as i32,
        rot_md: net_rot_md,
        scale_micro: net_scale_micro,
        flip_h: parent.flip_h != child.flip_h,
        flip_v: parent.flip_v != child.flip_v,
        pivot_x_milli: child.pivot_x_milli,
        pivot_y_milli: child.pivot_y_milli,
    }
}

/// Axis-aligned bounding box of a transformed `w`×`h` prop rect, in scene pixels (for the
/// shell's selection overlay and the fallback hit test). Conservative (float corners, floored
/// min / ceiled max).
pub fn xf_bounds(xf: &NetXf, w: u32, h: u32) -> (i32, i32, i32, i32) {
    let (cos, sin) = rot_cos_sin(xf.rot_md);
    let s = xf.scale_micro as f32 / 1_000_000.0;
    let (px, py) = (xf.pivot_x_milli as f32 / 1000.0, xf.pivot_y_milli as f32 / 1000.0);
    let (tx, ty) = (xf.tx_q8 as f32 / 256.0, xf.ty_q8 as f32 / 256.0);
    let sx = if xf.flip_h { -s } else { s };
    let sy = if xf.flip_v { -s } else { s };
    let mut minx = f32::MAX;
    let mut miny = f32::MAX;
    let mut maxx = f32::MIN;
    let mut maxy = f32::MIN;
    for (cx, cy) in [(0.0, 0.0), (w as f32, 0.0), (0.0, h as f32), (w as f32, h as f32)] {
        let lx = (cx - px) * sx;
        let ly = (cy - py) * sy;
        let fx = tx + cos * lx - sin * ly;
        let fy = ty + sin * lx + cos * ly;
        minx = minx.min(fx);
        miny = miny.min(fy);
        maxx = maxx.max(fx);
        maxy = maxy.max(fy);
    }
    (minx.floor() as i32, miny.floor() as i32, (maxx.ceil() - minx.floor()) as i32, (maxy.ceil() - miny.floor()) as i32)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::Key;

    fn track(keys: &[(u32, i32, Tween)]) -> Track {
        Track {
            base: 0,
            keys: keys.iter().map(|&(frame, v, tween)| Key { frame, v, tween }).collect(),
        }
    }

    #[test]
    fn easing_endpoints_exact() {
        for tw in [Tween::Linear, Tween::EaseIn, Tween::EaseOut, Tween::EaseInOut] {
            assert_eq!(ease_q16(tw, 0), 0, "{tw:?}(0)");
            assert_eq!(ease_q16(tw, ONE_Q16), ONE_Q16, "{tw:?}(1)");
        }
    }

    #[test]
    fn easing_monotonic_and_symmetric() {
        for tw in [Tween::Linear, Tween::EaseIn, Tween::EaseOut, Tween::EaseInOut] {
            let mut prev = -1i64;
            for i in 0..=64 {
                let u = i * ONE_Q16 / 64;
                let e = ease_q16(tw, u);
                assert!(e >= prev, "{tw:?} not monotonic at {i}");
                prev = e;
            }
        }
        // easeout(u) == ONE − easein(ONE−u)
        for i in 0..=64 {
            let u = i * ONE_Q16 / 64;
            assert_eq!(ease_q16(Tween::EaseOut, u), ONE_Q16 - ease_q16(Tween::EaseIn, ONE_Q16 - u));
        }
    }

    #[test]
    fn linear_lerp_table() {
        let t = track(&[(0, 0, Tween::Linear), (10, 100, Tween::Hold)]);
        let got: Vec<i32> = (0..=10).map(|f| eval_track(&t, f)).collect();
        assert_eq!(got, [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100]);
    }

    #[test]
    fn easein_pinned_values() {
        let t = track(&[(0, 0, Tween::EaseIn), (10, 100, Tween::Hold)]);
        // u = f/10; e = u²; v = round(100·e)
        assert_eq!(eval_track(&t, 5), 25);
        assert_eq!(eval_track(&t, 3), 9);
        assert_eq!(eval_track(&t, 7), 49);
    }

    #[test]
    fn hold_semantics() {
        let t = track(&[(2, 5, Tween::Hold), (8, 9, Tween::Linear)]);
        assert_eq!(eval_track(&t, 0), 5); // hold-before-first
        assert_eq!(eval_track(&t, 2), 5); // exact
        assert_eq!(eval_track(&t, 7), 5); // held across the segment
        assert_eq!(eval_track(&t, 8), 9);
        assert_eq!(eval_track(&t, 99), 9); // hold-after-last
        assert_eq!(eval_track(&Track::constant(42), 3), 42); // keyless → base
    }

    #[test]
    fn rotation_no_wrap() {
        let t = track(&[(0, 0, Tween::Linear), (10, 720_000, Tween::Hold)]);
        assert_eq!(eval_track(&t, 5), 360_000); // two full turns pass through one full turn
    }

    #[test]
    fn quantize_rule() {
        assert_eq!(quantize_duration(100_000, 80_000), 1); // 1.25 → 1
        assert_eq!(quantize_duration(120_000, 80_000), 2); // 1.5 → 2 (half-up)
        assert_eq!(quantize_duration(10_000, 80_000), 1); // min clamp
        assert_eq!(quantize_duration(u32::MAX, 20_000), 1024); // max clamp
    }

    #[test]
    fn compose_pin_integer_parts() {
        let parent = ActorPose {
            x: 10,
            y: 20,
            rot_md: 90_000,
            scale_milli: 2000,
            flip_h: false,
            flip_v: false,
            opacity: 255,
            pivot_x_milli: 0,
            pivot_y_milli: 0,
            pose: 0,
        };
        let child = ActorPose {
            x: 5,
            y: 0,
            rot_md: 45_000,
            scale_milli: 1500,
            flip_h: true,
            flip_v: false,
            opacity: 128,
            pivot_x_milli: 4000,
            pivot_y_milli: 4000,
            pose: 0,
        };
        let net = compose_pin(&parent, &child);
        assert_eq!(net.rot_md, 135_000);
        assert_eq!(net.scale_micro, 3_000_000);
        assert!(net.flip_h);
        assert!(!net.flip_v);
        assert_eq!((net.pivot_x_milli, net.pivot_y_milli), (4000, 4000));
        // Parent rotated 90° CW, child anchor (5,0) scaled ×2 → world (10, 20) + R90·(10,0)
        // = (10, 30). Exact because 90° trig is integer-exact.
        assert_eq!((net.tx_q8, net.ty_q8), (10 * 256, 30 * 256));

        // Single parent flip conjugates child rotation.
        let flipped = ActorPose { flip_h: true, ..parent };
        assert_eq!(compose_pin(&flipped, &child).rot_md, 90_000 - 45_000);
    }

    #[test]
    fn unpinned_translation_exact() {
        let pose = ActorPose {
            x: -7,
            y: 3,
            rot_md: 0,
            scale_milli: 1000,
            flip_h: false,
            flip_v: false,
            opacity: 255,
            pivot_x_milli: 0,
            pivot_y_milli: 0,
            pose: 0,
        };
        let xf = net_xf(&pose);
        assert_eq!((xf.tx_q8, xf.ty_q8), (-7 * 256, 3 * 256));
    }

    #[test]
    fn bounds_identity() {
        let pose = ActorPose {
            x: 10,
            y: 20,
            rot_md: 0,
            scale_milli: 1000,
            flip_h: false,
            flip_v: false,
            opacity: 255,
            pivot_x_milli: 0,
            pivot_y_milli: 0,
            pose: 0,
        };
        let (x, y, w, h) = xf_bounds(&net_xf(&pose), 8, 4);
        assert_eq!((x, y, w, h), (10, 20, 8, 4));
    }
}
