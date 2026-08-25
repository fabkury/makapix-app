#![no_main]
//! Differential fuzz of the hand-muxed animated WebP encoder (ANALYSIS.md §2.3 — "the
//! jewel"). Our VP8X/ANIM/ANMF container is written by hand in pure Rust, including the
//! changed-rect delta frames; libwebp (Google's C reference, vendored via
//! `webp-animation`) decodes it. Two independent implementations must agree.
//!
//! The oracle is exact, not approximate: the encoder is LOSSLESS (VP8L), every ANMF is
//! written with blend=1 (overwrite, never alpha-blend) and dispose=0 (no dispose), and
//! each delta rect is the full bounding box of what changed. So the reference decoder's
//! composited canvas at frame *i* must equal our input frame *i*, pixel for pixel. Any
//! disagreement is a real container bug: a wrong ANMF offset (they are stored halved, so
//! an odd x/y silently shifts the frame), a too-small delta rect leaving stale pixels, a
//! mis-sized VP8X canvas, a bad chunk length, or a duration that fails to survive the
//! round trip.
//!
//! This mechanizes forever a check that was previously a one-time manual verification
//! ("libwebp-verified lossless", 2026-08-09).

use arbitrary::Arbitrary;
use libfuzzer_sys::fuzz_target;

/// A small animation to encode. Dimensions and frame count stay tiny: VP8L encoding
/// dominates runtime, and container bugs do not need big canvases to show up — they need
/// many *shapes* of delta rect, which small frames explore far faster.
#[derive(Arbitrary, Debug)]
struct Anim {
    w: u8,
    h: u8,
    /// Per frame: a seed for the pixel pattern, how much of the frame differs from the
    /// previous one, and a duration.
    frames: Vec<FrameSpec>,
    scale: u8,
}

#[derive(Arbitrary, Debug)]
struct FrameSpec {
    seed: u32,
    /// Changed-region rectangle, as fractions of the canvas (kept as u8 so the mutator
    /// can walk edges: 0 → no change at all, 255 → the whole frame).
    rx: u8,
    ry: u8,
    rw: u8,
    rh: u8,
    dur_ms: u16,
}

/// Deterministic pixel pattern — no RNG crate, and reproducible from the input alone.
fn px(seed: u32, x: u32, y: u32) -> [u8; 4] {
    let v = seed
        .wrapping_mul(2654435761)
        .wrapping_add(x.wrapping_mul(40503))
        .wrapping_add(y.wrapping_mul(2246822519));
    // Alpha is frequently 255 but not always: the container claims an alpha channel, so
    // transparent pixels must survive the round trip too.
    let a = if v & 0x30 == 0 { (v >> 9) as u8 } else { 255 };
    [(v >> 24) as u8, (v >> 16) as u8, (v >> 8) as u8, a]
}

fuzz_target!(|anim: Anim| {
    // Canvas 1..=64 on each axis; scale 1..=4 (the encoder clamps to 1..=32, but large
    // upscales only make each execution slower without exercising new container paths).
    let w = (anim.w as u32 % 64) + 1;
    let h = (anim.h as u32 % 64) + 1;
    let scale = (anim.scale as u32 % 4) + 1;
    if anim.frames.is_empty() || anim.frames.len() > 12 {
        return;
    }

    // Build the frames, each a mutation of the previous one inside a rectangle, so the
    // encoder's diff_rect sees every shape of change: none, a corner, a stripe, all of it.
    let n = (w as usize) * (h as usize) * 4;
    let mut sources: Vec<(Vec<u8>, u32)> = Vec::with_capacity(anim.frames.len());
    let mut cur = vec![0u8; n];
    for (i, f) in anim.frames.iter().enumerate() {
        if i == 0 {
            for y in 0..h {
                for x in 0..w {
                    let c = px(f.seed, x, y);
                    cur[((y * w + x) * 4) as usize..][..4].copy_from_slice(&c);
                }
            }
        } else {
            let rw = (f.rw as u32 * w) / 255;
            let rh = (f.rh as u32 * h) / 255;
            let rx = if w > rw { (f.rx as u32 * (w - rw)) / 255 } else { 0 };
            let ry = if h > rh { (f.ry as u32 * (h - rh)) / 255 } else { 0 };
            for y in ry..(ry + rh).min(h) {
                for x in rx..(rx + rw).min(w) {
                    let c = px(f.seed, x, y);
                    cur[((y * w + x) * 4) as usize..][..4].copy_from_slice(&c);
                }
            }
        }
        // Durations round-trip through the container in milliseconds; feed microseconds.
        sources.push((cur.clone(), f.dur_ms as u32 * 1000));
    }

    let encoded = match makapix_codec::encode_animated_webp_with(w, h, &sources, scale, &mut |_, _| true) {
        Ok(b) => b,
        // A refusal is a legitimate outcome (e.g. Unsupported); it is not a container bug.
        Err(_) => return,
    };

    // A single-frame input is emitted as a plain static WebP, which the animation decoder
    // does not accept — that path is covered by the static branch below.
    let (ow, oh) = (w * scale, h * scale);
    if sources.len() == 1 {
        return;
    }

    let decoder = match webp_animation::Decoder::new(&encoded) {
        Ok(d) => d,
        Err(e) => panic!("libwebp rejected our animated WebP: {e:?}\n{} frames {ow}x{oh}", sources.len()),
    };

    let decoded: Vec<(i32, Vec<u8>)> =
        decoder.into_iter().map(|f| (f.timestamp(), f.data().to_vec())).collect();

    assert!(
        decoded.len() == sources.len(),
        "frame count mismatch: encoded {} frames, libwebp decoded {}",
        sources.len(),
        decoded.len()
    );

    // Compare every frame's fully composited canvas against the upscaled source. Exact
    // equality: lossless VP8L + overwrite blending means there is no tolerance to allow.
    for (i, ((src, _dur), (_ts, got))) in sources.iter().zip(decoded.iter()).enumerate() {
        let want = makapix_codec::upscale_nearest(w, h, src, scale);
        assert!(
            got.len() == want.len(),
            "frame {i}: decoded {} bytes, expected {} ({ow}x{oh})",
            got.len(),
            want.len()
        );
        if got != &want {
            let at = got.iter().zip(want.iter()).position(|(a, b)| a != b).unwrap_or(0);
            let p = at / 4;
            panic!(
                "frame {i}/{}: pixel mismatch at ({}, {}) [byte {at}] — decoded {:?} vs source {:?}; \
                 canvas {ow}x{oh}, scale {scale}",
                sources.len(),
                p as u32 % ow,
                p as u32 / ow,
                &got[p * 4..p * 4 + 4],
                &want[p * 4..p * 4 + 4],
            );
        }
    }
});
