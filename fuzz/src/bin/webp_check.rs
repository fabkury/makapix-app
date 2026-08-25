//! Proves the animated-WebP differential oracle is real and non-vacuous.
//!
//! `cargo +nightly run --release --bin webp_check` (from `fuzz/`). Two halves:
//!   1. POSITIVE — encode several animations with our hand-written muxer, decode them
//!      with libwebp (the C reference), and require pixel-exact equality per frame.
//!      If this fails, the encoder is wrong.
//!   2. NEGATIVE — corrupt one ANMF placement byte and require the same comparison to
//!      NOTICE. A differential that cannot fail is not a test, so this pins that the
//!      oracle in `fuzz_webp_differential` would actually catch a container bug.

fn px(seed: u32, x: u32, y: u32) -> [u8; 4] {
    let v = seed
        .wrapping_mul(2654435761)
        .wrapping_add(x.wrapping_mul(40503))
        .wrapping_add(y.wrapping_mul(2246822519));
    let a = if v & 0x30 == 0 { (v >> 9) as u8 } else { 255 };
    [(v >> 24) as u8, (v >> 16) as u8, (v >> 8) as u8, a]
}

/// Build `n` frames of `w`x`h`, each differing from the previous inside a moving rect.
fn build(w: u32, h: u32, n: usize) -> Vec<(Vec<u8>, u32)> {
    let mut out = Vec::new();
    let mut cur = vec![0u8; (w * h * 4) as usize];
    for i in 0..n {
        let (rx, ry) = ((i as u32 * 3) % w, (i as u32 * 5) % h);
        let (rw, rh) = ((w / 2).max(1), (h / 3).max(1));
        if i == 0 {
            for y in 0..h {
                for x in 0..w {
                    cur[((y * w + x) * 4) as usize..][..4].copy_from_slice(&px(7, x, y));
                }
            }
        } else {
            for y in ry..(ry + rh).min(h) {
                for x in rx..(rx + rw).min(w) {
                    cur[((y * w + x) * 4) as usize..][..4]
                        .copy_from_slice(&px(i as u32 * 977 + 13, x, y));
                }
            }
        }
        out.push((cur.clone(), 40_000));
    }
    out
}

/// Decode with libwebp and compare each composited frame to the upscaled source.
/// Returns Err(description) on any disagreement.
fn differential(w: u32, h: u32, scale: u32, src: &[(Vec<u8>, u32)], encoded: &[u8]) -> Result<usize, String> {
    let dec = webp_animation::Decoder::new(encoded).map_err(|e| format!("libwebp rejected: {e:?}"))?;
    let frames: Vec<Vec<u8>> = dec.into_iter().map(|f| f.data().to_vec()).collect();
    if frames.len() != src.len() {
        return Err(format!("frame count {} vs {}", frames.len(), src.len()));
    }
    for (i, ((s, _), got)) in src.iter().zip(frames.iter()).enumerate() {
        let want = makapix_codec::upscale_nearest(w, h, s, scale);
        if got != &want {
            let at = got.iter().zip(want.iter()).position(|(a, b)| a != b).unwrap_or(0);
            return Err(format!("frame {i}: first differing byte at {at}"));
        }
    }
    Ok(frames.len())
}

fn main() {
    let cases: &[(u32, u32, usize, u32)] = &[
        (16, 16, 4, 1),
        (13, 7, 6, 1),   // odd dimensions — ANMF offsets are stored halved
        (32, 24, 3, 2),  // upscaled
        (5, 5, 8, 3),
        (64, 64, 2, 1),
        (1, 1, 3, 1),    // degenerate canvas
    ];

    let mut checked = 0;
    for &(w, h, n, scale) in cases {
        let src = build(w, h, n);
        let encoded = makapix_codec::encode_animated_webp_with(w, h, &src, scale, &mut |_, _| true)
            .unwrap_or_else(|e| panic!("encode failed for {w}x{h} n={n} scale={scale}: {e:?}"));
        match differential(w, h, scale, &src, &encoded) {
            Ok(f) => {
                println!("POSITIVE {w}x{h} n={n} scale={scale}: {f} frames match libwebp exactly ({} bytes)", encoded.len());
                checked += 1;
            }
            Err(e) => panic!("POSITIVE {w}x{h} n={n} scale={scale} FAILED: {e}"),
        }
    }
    println!("-- {checked}/{} positive cases passed\n", cases.len());

    // NEGATIVE: shift one delta frame's placement so the container stays VALID but paints
    // in the wrong spot — the class of bug this differential exists to catch. Moving a
    // frame LEFT (x offset is stored halved, so -1 unit = 2 px) keeps it inside the canvas,
    // where a bounds check cannot save us and only the pixel comparison can notice.
    // (Shifting right instead makes libwebp reject the file outright; that is detection
    // too, but it proves the rejection path rather than the comparison path.)
    let (w, h, n, scale) = (32, 32, 5, 1);
    let src = build(w, h, n);
    let good = makapix_codec::encode_animated_webp_with(w, h, &src, scale, &mut |_, _| true).unwrap();

    let mut shifted = None;
    let mut pos = 0;
    while let Some(rel) = good[pos..].windows(4).position(|c| c == b"ANMF") {
        let payload = pos + rel + 8; // fourcc(4) + size(4)
        if good[payload] > 0 {
            let mut bad = good.clone();
            bad[payload] -= 1; // move this frame 2 px left
            shifted = Some((payload, bad));
            break;
        }
        pos = pos + rel + 4;
    }
    let (at, bad) = shifted.expect("expected an ANMF placed at x > 0 to shift");
    println!("NEGATIVE: moved one ANMF 2 px left (x offset byte {at}) — still a valid container");
    match differential(w, h, scale, &src, &bad) {
        Ok(_) => panic!(
            "NEGATIVE FAILED: the oracle accepted a container with a misplaced frame — \
             fuzz_webp_differential would not catch a placement bug"
        ),
        Err(e) => println!("NEGATIVE: detected, as required -> {e}"),
    }
    println!("\nOracle verified: exact on correct output, and it fails on a misplaced frame.");
}
