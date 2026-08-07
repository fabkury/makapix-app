//! Color: 8-bit straight RGBA at the boundary, premultiplied internally; integer-exact
//! sRGB math and HSV conversion (SPEC §6). No linear-light path.

use crate::document::BlendMode;

/// Straight (non-premultiplied) 8-bit RGBA — the public/boundary representation.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct Rgba8 {
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub a: u8,
}

impl Rgba8 {
    pub const TRANSPARENT: Rgba8 = Rgba8 { r: 0, g: 0, b: 0, a: 0 };
    pub const BLACK: Rgba8 = Rgba8 { r: 0, g: 0, b: 0, a: 255 };
    pub const WHITE: Rgba8 = Rgba8 { r: 255, g: 255, b: 255, a: 255 };

    pub const fn new(r: u8, g: u8, b: u8, a: u8) -> Self {
        Rgba8 { r, g, b, a }
    }
    pub const fn rgb(r: u8, g: u8, b: u8) -> Self {
        Rgba8 { r, g, b, a: 255 }
    }
    pub fn is_transparent(&self) -> bool {
        self.a == 0
    }

    /// Parse `#RGB`, `#RGBA`, `#RRGGBB`, or `#RRGGBBAA` (leading `#` optional).
    pub fn from_hex(s: &str) -> Option<Rgba8> {
        let s = s.trim().trim_start_matches('#');
        let hex2 = |b: &[u8]| -> Option<u8> {
            let hi = (b[0] as char).to_digit(16)?;
            let lo = (b[1] as char).to_digit(16)?;
            Some((hi * 16 + lo) as u8)
        };
        let b = s.as_bytes();
        match b.len() {
            6 => Some(Rgba8::new(hex2(&b[0..2])?, hex2(&b[2..4])?, hex2(&b[4..6])?, 255)),
            8 => Some(Rgba8::new(
                hex2(&b[0..2])?,
                hex2(&b[2..4])?,
                hex2(&b[4..6])?,
                hex2(&b[6..8])?,
            )),
            3 => {
                let d = |c: char| c.to_digit(16).map(|v| (v * 17) as u8);
                Some(Rgba8::new(d(s.chars().next()?)?, d(s.chars().nth(1)?)?, d(s.chars().nth(2)?)?, 255))
            }
            4 => {
                let d = |c: char| c.to_digit(16).map(|v| (v * 17) as u8);
                Some(Rgba8::new(
                    d(s.chars().next()?)?,
                    d(s.chars().nth(1)?)?,
                    d(s.chars().nth(2)?)?,
                    d(s.chars().nth(3)?)?,
                ))
            }
            _ => None,
        }
    }

    pub fn to_hex(&self) -> String {
        format!("#{:02X}{:02X}{:02X}{:02X}", self.r, self.g, self.b, self.a)
    }
}

/// Premultiplied 8-bit RGBA — internal storage for correct/fast alpha-over (SPEC §6.1).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Default)]
pub struct Premul8 {
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub a: u8,
}

#[inline]
fn mul255(a: u8, b: u8) -> u8 {
    // round((a*b)/255) without floats, exact.
    let t = a as u32 * b as u32 + 128;
    (((t >> 8) + t) >> 8) as u8
}

pub fn to_premul(c: Rgba8) -> Premul8 {
    Premul8 { r: mul255(c.r, c.a), g: mul255(c.g, c.a), b: mul255(c.b, c.a), a: c.a }
}

pub fn from_premul(p: Premul8) -> Rgba8 {
    if p.a == 0 {
        return Rgba8::TRANSPARENT;
    }
    let un = |v: u8| -> u8 {
        let r = (v as u32 * 255 + p.a as u32 / 2) / p.a as u32;
        r.min(255) as u8
    };
    Rgba8::new(un(p.r), un(p.g), un(p.b), p.a)
}

/// Alpha-over of straight colors in sRGB (the Normal blend). `src` over `dst`.
pub fn over(src: Rgba8, dst: Rgba8) -> Rgba8 {
    if src.a == 255 || dst.a == 0 {
        return if src.a == 255 { src } else { blend_straight(src, dst) };
    }
    if src.a == 0 {
        return dst;
    }
    blend_straight(src, dst)
}

fn blend_straight(src: Rgba8, dst: Rgba8) -> Rgba8 {
    // out_a = src.a + dst.a*(1-src.a)
    let sa = src.a as u32;
    let inv = 255 - sa;
    let out_a = sa + (dst.a as u32 * inv + 127) / 255;
    if out_a == 0 {
        return Rgba8::TRANSPARENT;
    }
    let chan = |s: u8, d: u8| -> u8 {
        // premultiplied composite then un-premultiply by out_a
        let num = s as u32 * sa + (d as u32 * dst.a as u32 * inv) / 255;
        ((num + out_a / 2) / out_a).min(255) as u8
    };
    Rgba8::new(chan(src.r, dst.r), chan(src.g, dst.g), chan(src.b, dst.b), out_a as u8)
}

/// Composite `src` over `dst` with an extra `opacity` (0..=255) applied to src's alpha.
pub fn over_opacity(mut src: Rgba8, dst: Rgba8, opacity: u8) -> Rgba8 {
    if opacity != 255 {
        src.a = mul255(src.a, opacity);
    }
    over(src, dst)
}

// ---- Layer blend modes (SPEC §6.4; wire values in the format spec §12.2) ----

/// Integer lerp `a→b` at `t∈0..=255`: `(a·(255−t) + b·t + 127)/255` — pinned rounding, u32 math.
#[inline]
fn lerp255(a: u8, b: u8, t: u8) -> u8 {
    ((a as u32 * (255 - t as u32) + b as u32 * t as u32 + 127) / 255) as u8
}

/// HardLight's per-channel core: `cs < 128 → multiply(cb, 2cs)`, else `screen(cb, 2cs−255)`.
/// The 128 split is pinned; u16 keeps `2·cs` in range (≤ 254 on the multiply branch,
/// `510 − 2cs ≤ 254` on the screen branch's complement).
#[inline]
fn hard_light(cb: u8, cs: u8) -> u8 {
    if cs < 128 {
        mul255(cb, (2 * cs as u16) as u8)
    } else {
        255 - mul255(255 - cb, (510 - 2 * cs as u16) as u8)
    }
}

/// Per-channel separable blend `B(cb, cs)` on straight u8 channels (W3C compositing §9.1.x),
/// every branch integer-exact with pinned rounding via `mul255`.
fn blend_channel(mode: BlendMode, cb: u8, cs: u8) -> u8 {
    match mode {
        BlendMode::Normal => cs,
        BlendMode::Multiply => mul255(cb, cs),
        BlendMode::Screen => 255 - mul255(255 - cb, 255 - cs),
        BlendMode::Overlay => hard_light(cs, cb), // HardLight with cb/cs swapped
        BlendMode::HardLight => hard_light(cb, cs),
        BlendMode::Darken => cb.min(cs),
        BlendMode::Lighten => cb.max(cs),
        BlendMode::Addition => (cb as u16 + cs as u16).min(255) as u8,
        BlendMode::Subtract => cb.saturating_sub(cs),
        BlendMode::Difference => cb.abs_diff(cs),
        // Non-negative by algebra (mul255(cb,cs) ≤ min(cb,cs)); the .min is defensive.
        BlendMode::Exclusion => (cb as u32 + cs as u32 - 2 * mul255(cb, cs) as u32).min(255) as u8,
    }
}

/// The blend-aware compositor primitive: `src` over `dst` under `mode` with layer `opacity`.
/// `Normal` — or a transparent backdrop, which degrades every separable mode to plain
/// source — is exactly [`over_opacity`]. Otherwise the W3C backdrop-alpha weighting replaces
/// src's RGB with `Cs' = lerp(Cs, B(Cb, Cs), αb)` per channel (straight colors), then
/// alpha-overs as usual. A transparent source stays a no-op for every mode, which is what
/// keeps the compositor's absent-tile skip and `a == 0` early-return exact.
pub fn composite(mode: BlendMode, src: Rgba8, dst: Rgba8, opacity: u8) -> Rgba8 {
    if mode == BlendMode::Normal || dst.a == 0 {
        return over_opacity(src, dst, opacity);
    }
    let mixed = Rgba8::new(
        lerp255(src.r, blend_channel(mode, dst.r, src.r), dst.a),
        lerp255(src.g, blend_channel(mode, dst.g, src.g), dst.a),
        lerp255(src.b, blend_channel(mode, dst.b, src.b), dst.a),
        src.a,
    );
    over_opacity(mixed, dst, opacity)
}

/// Integer-exact linear interpolation between two straight colors in sRGB at `t∈[0,1]`.
pub fn lerp_srgb(a: Rgba8, b: Rgba8, t: f32) -> Rgba8 {
    let t = t.clamp(0.0, 1.0);
    let lerp = |x: u8, y: u8| -> u8 {
        let v = x as f32 + (y as f32 - x as f32) * t;
        (v + 0.5).clamp(0.0, 255.0) as u8
    };
    Rgba8::new(lerp(a.r, b.r), lerp(a.g, b.g), lerp(a.b, b.b), lerp(a.a, b.a))
}

/// HSV with H in degrees [0,360), S/V in [0,1]. Conversions are rounding-defined for oracles.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Hsv {
    pub h: f32,
    pub s: f32,
    pub v: f32,
}

pub fn rgb_to_hsv(c: Rgba8) -> Hsv {
    let r = c.r as f32 / 255.0;
    let g = c.g as f32 / 255.0;
    let b = c.b as f32 / 255.0;
    let max = r.max(g).max(b);
    let min = r.min(g).min(b);
    let d = max - min;
    let v = max;
    let s = if max <= 0.0 { 0.0 } else { d / max };
    let h = if d <= 0.0 {
        0.0
    } else if max == r {
        60.0 * (((g - b) / d) % 6.0)
    } else if max == g {
        60.0 * ((b - r) / d + 2.0)
    } else {
        60.0 * ((r - g) / d + 4.0)
    };
    let h = if h < 0.0 { h + 360.0 } else { h };
    Hsv { h, s, v }
}

pub fn hsv_to_rgb(hsv: Hsv, a: u8) -> Rgba8 {
    let h = ((hsv.h % 360.0) + 360.0) % 360.0;
    let s = hsv.s.clamp(0.0, 1.0);
    let v = hsv.v.clamp(0.0, 1.0);
    let c = v * s;
    let x = c * (1.0 - (((h / 60.0) % 2.0) - 1.0).abs());
    let m = v - c;
    let (r1, g1, b1) = match (h / 60.0) as i32 {
        0 => (c, x, 0.0),
        1 => (x, c, 0.0),
        2 => (0.0, c, x),
        3 => (0.0, x, c),
        4 => (x, 0.0, c),
        _ => (c, 0.0, x),
    };
    let to8 = |v: f32| ((v + m) * 255.0 + 0.5).clamp(0.0, 255.0) as u8;
    Rgba8::new(to8(r1), to8(g1), to8(b1), a)
}

/// Apply an HSV shift (degrees, ±sat, ±val as fractions) to a straight color, alpha kept.
pub fn hsv_shift(c: Rgba8, dh: f32, ds: f32, dv: f32) -> Rgba8 {
    if c.a == 0 {
        return c;
    }
    let mut hsv = rgb_to_hsv(c);
    hsv.h = ((hsv.h + dh) % 360.0 + 360.0) % 360.0;
    hsv.s = (hsv.s + ds).clamp(0.0, 1.0);
    hsv.v = (hsv.v + dv).clamp(0.0, 1.0);
    hsv_to_rgb(hsv, c.a)
}

/// Per-channel max absolute difference of RGBA — the threshold metric for fill/select.
pub fn max_channel_delta(a: Rgba8, b: Rgba8) -> u8 {
    let d = |x: u8, y: u8| (x as i32 - y as i32).unsigned_abs() as u8;
    d(a.r, b.r).max(d(a.g, b.g)).max(d(a.b, b.b)).max(d(a.a, b.a))
}

/// Invert RGB (keep alpha).
pub fn invert(c: Rgba8) -> Rgba8 {
    Rgba8::new(255 - c.r, 255 - c.g, 255 - c.b, c.a)
}

/// Ordering key for the `SortPalette` action: grays-first hue ramps (SPEC §13 palettes).
/// Integer-only on purpose — palette order must never fork per platform.
///
/// Groups, in order: grays (saturation ≤ 10%, so black/white/near-grays form one leading
/// dark→light ramp) · colored (12 hue buckets of 30° in wheel order red→yellow→green→cyan→
/// blue→magenta, each bucket dark→light by Rec.709 luma) · fully transparent entries last.
/// Alpha is the final tiebreak everywhere (opaque→translucent), so translucent variants sit
/// right after their opaque parent. Callers must use a stable sort so exact ties keep their
/// existing relative order.
pub fn palette_sort_key(c: Rgba8) -> (u8, u8, u32, u16, u8, u8) {
    let (r, g, b) = (c.r as i32, c.g as i32, c.b as i32);
    let max = r.max(g).max(b);
    let min = r.min(g).min(b);
    let chroma = max - min;
    let luma = (2126 * r + 7152 * g + 722 * b) as u32;
    let gray = chroma * 10 <= max; // saturation ≤ 10% (black included: 0 ≤ 0)
    let group: u8 = if c.a == 0 {
        2
    } else if gray {
        0
    } else {
        1
    };
    let (bucket, hue) = if chroma == 0 || gray {
        (0u8, 0u16) // hue is meaningless/noisy for grays — luma alone orders the ramp
    } else {
        // Integer hue on a 0..1536 wheel (6 sectors × 256), red at 0.
        let h = if max == r {
            ((g - b) * 256 / chroma).rem_euclid(1536)
        } else if max == g {
            512 + (b - r) * 256 / chroma
        } else {
            1024 + (r - g) * 256 / chroma
        };
        ((h / 128) as u8, h as u16) // 1536/128 = 12 buckets of 30°
    };
    let sat = if max == 0 { 0 } else { (chroma * 255 / max) as u8 };
    (group, bucket, luma, hue, sat, 255 - c.a)
}

/// Adjust brightness (`db` in [-255,255]) and contrast (`cf` multiplier around 128).
pub fn brightness_contrast(c: Rgba8, db: i32, cf: f32) -> Rgba8 {
    let adj = |v: u8| -> u8 {
        let f = (v as f32 - 128.0) * cf + 128.0 + db as f32;
        (f + 0.5).clamp(0.0, 255.0) as u8
    };
    Rgba8::new(adj(c.r), adj(c.g), adj(c.b), c.a)
}

/// Build the per-channel lookup table for the Levels adjustment (GIMP Colors > Levels input
/// side): `lo`/`hi` are the input black/white points, `gamma_th` is gamma in thousandths
/// (1000 = 1.0; > 1000 brightens midtones). Per input `v`: normalize into the `lo..hi` span,
/// raise to `1/γ`, requantize round-half-up — `v ≤ lo` crushes to 0, `v ≥ hi` blows to 255.
///
/// Determinism (SPEC §5): γ = 1 takes a pure-integer affine path, everything else goes through
/// `util::det_pow` — never libm — so the table is byte-identical on every platform. Parameters
/// are sanitized here (`lo ≤ 254`, `hi ≥ lo+1`, γ clamped to [0.1, 10]); the raw DSL values
/// stay unclamped in `ToolSettings` like the sibling adjustment tools'.
pub fn levels_lut(lo: u8, gamma_th: i32, hi: u8) -> [u8; 256] {
    let lo = lo.min(254) as i32;
    let hi = (hi as i32).max(lo + 1);
    let g = gamma_th.clamp(100, 10_000);
    let span = hi - lo; // 1..=255
    let e = 1000.0 / g as f64; // exponent 1/γ
    let mut lut = [0u8; 256];
    for (v, out) in lut.iter_mut().enumerate() {
        let vi = v as i32;
        *out = if vi <= lo {
            0
        } else if vi >= hi {
            255
        } else if g == 1000 {
            // round-half-up of (v-lo)·255/span, exactly, in integers
            (((vi - lo) * 510 + span) / (2 * span)) as u8
        } else {
            let n = (vi - lo) as f64 / span as f64;
            (crate::util::det_pow(n, e) * 255.0 + 0.5).clamp(0.0, 255.0) as u8
        };
    }
    lut
}

/// Map RGB through a Levels lookup table, alpha kept.
pub fn apply_levels_lut(c: Rgba8, lut: &[u8; 256]) -> Rgba8 {
    Rgba8::new(lut[c.r as usize], lut[c.g as usize], lut[c.b as usize], c.a)
}

#[cfg(test)]
mod tests {
    use super::*;

    const ALL_MODES: [BlendMode; 11] = [
        BlendMode::Normal,
        BlendMode::Multiply,
        BlendMode::Screen,
        BlendMode::Overlay,
        BlendMode::Darken,
        BlendMode::Lighten,
        BlendMode::Addition,
        BlendMode::Subtract,
        BlendMode::Difference,
        BlendMode::Exclusion,
        BlendMode::HardLight,
    ];

    #[test]
    fn blend_channel_hand_values() {
        // Opaque backdrop + opaque source degenerates the weighting to B(cb, cs) exactly.
        // cb = 100, cs = 200, hand-computed under mul255's round-half-up:
        //   Multiply  round(100·200/255) = 78        Screen 255 − round(155·55/255) = 222
        //   Overlay   hard_light(200, 100) = mul255(200, 200) = 157
        //   HardLight 255 − mul255(155, 110) = 188   Exclusion 100 + 200 − 2·78 = 144
        let src = Rgba8::rgb(200, 200, 200);
        let dst = Rgba8::rgb(100, 100, 100);
        let expect = [
            (BlendMode::Multiply, 78),
            (BlendMode::Screen, 222),
            (BlendMode::Overlay, 157),
            (BlendMode::Darken, 100),
            (BlendMode::Lighten, 200),
            (BlendMode::Addition, 255),
            (BlendMode::Subtract, 0),
            (BlendMode::Difference, 100),
            (BlendMode::Exclusion, 144),
            (BlendMode::HardLight, 188),
        ];
        for (mode, want) in expect {
            let got = composite(mode, src, dst, 255);
            assert_eq!((got.r, got.g, got.b, got.a), (want, want, want, 255), "{:?}", mode);
        }
    }

    #[test]
    fn hard_light_split_at_128() {
        // cb = 100: cs = 127 takes the multiply branch (mul255(100, 254) = 100);
        // cs = 128 takes the screen branch (255 − mul255(155, 254) = 101).
        assert_eq!(hard_light(100, 127), 100);
        assert_eq!(hard_light(100, 128), 101);
        // Overlay is HardLight with the operands swapped.
        assert_eq!(blend_channel(BlendMode::Overlay, 100, 200), hard_light(200, 100));
    }

    #[test]
    fn composite_transparent_backdrop_degrades_to_src() {
        let samples = [
            (Rgba8::new(200, 10, 90, 255), 255),
            (Rgba8::new(30, 250, 128, 128), 200),
            (Rgba8::new(0, 0, 0, 64), 64),
        ];
        for mode in ALL_MODES {
            for (src, op) in samples {
                assert_eq!(
                    composite(mode, src, Rgba8::TRANSPARENT, op),
                    over_opacity(src, Rgba8::TRANSPARENT, op),
                    "{:?}",
                    mode
                );
            }
        }
    }

    #[test]
    fn composite_half_alpha_backdrop_weights() {
        // dst.a = 128 → Cs' = lerp255(cs, B, 128); with an opaque source the result is Cs'.
        // cb = 100, cs = 200: Multiply → lerp255(200, 78, 128) = 139;
        //                     Screen   → lerp255(200, 222, 128) = 211.
        let src = Rgba8::rgb(200, 200, 200);
        let dst = Rgba8::new(100, 100, 100, 128);
        assert_eq!(composite(BlendMode::Multiply, src, dst, 255).r, 139);
        assert_eq!(composite(BlendMode::Screen, src, dst, 255).r, 211);
    }

    #[test]
    fn composite_normal_is_over_opacity() {
        for src in [Rgba8::new(10, 200, 30, 255), Rgba8::new(255, 0, 128, 77), Rgba8::TRANSPARENT] {
            for dst in [Rgba8::rgb(90, 90, 90), Rgba8::new(1, 2, 3, 40), Rgba8::TRANSPARENT] {
                for op in [255, 128, 0] {
                    assert_eq!(composite(BlendMode::Normal, src, dst, op), over_opacity(src, dst, op));
                }
            }
        }
    }

    #[test]
    fn composite_transparent_src_identity() {
        // A transparent source is a no-op for every mode — the compositor's absent-tile skip
        // and `a == 0` early-return depend on this being exact.
        for mode in ALL_MODES {
            for dst in [Rgba8::rgb(10, 200, 30), Rgba8::new(90, 40, 250, 128)] {
                assert_eq!(composite(mode, Rgba8::TRANSPARENT, dst, 255), dst, "{:?}", mode);
            }
        }
    }

    #[test]
    fn exclusion_never_overflows() {
        for cb in 0..=255u8 {
            for cs in 0..=255u8 {
                let v = cb as i32 + cs as i32 - 2 * mul255(cb, cs) as i32;
                assert!((0..=255).contains(&v), "cb={} cs={} v={}", cb, cs, v);
            }
        }
    }

    #[test]
    fn blend_mode_names_and_bytes_roundtrip() {
        for mode in ALL_MODES {
            assert_eq!(BlendMode::from_u8(mode as u8), mode);
            assert_eq!(BlendMode::from_name(mode.name()), Some(mode));
        }
        assert_eq!(BlendMode::from_u8(11), BlendMode::Normal, "unknown wire byte degrades");
        assert_eq!(BlendMode::from_u8(200), BlendMode::Normal);
        assert_eq!(BlendMode::from_name("Divide"), None, "unknown token errors");
    }

    #[test]
    fn palette_sort_key_groups_and_ramps() {
        let key = palette_sort_key;
        // Grays (incl. black/white) precede colored entries; transparent goes last.
        assert!(key(Rgba8::BLACK) < key(Rgba8::rgb(255, 0, 0)));
        assert!(key(Rgba8::WHITE) < key(Rgba8::rgb(255, 0, 0)));
        assert!(key(Rgba8::rgb(255, 0, 0)) < key(Rgba8::new(128, 128, 128, 0)));
        // The gray ramp orders dark→light.
        assert!(key(Rgba8::BLACK) < key(Rgba8::rgb(128, 128, 128)));
        assert!(key(Rgba8::rgb(128, 128, 128)) < key(Rgba8::WHITE));
        // Near-gray (sat ≤ 10%) joins the gray ramp; a saturated color of any hue does not.
        assert_eq!(key(Rgba8::rgb(200, 190, 195)).0, 0);
        assert_eq!(key(Rgba8::rgb(200, 100, 100)).0, 1);
        // Hue wheel order: red < yellow < green < cyan < blue < magenta.
        let (r, y, g, c, b, m) = (
            Rgba8::rgb(255, 0, 0),
            Rgba8::rgb(255, 255, 0),
            Rgba8::rgb(0, 255, 0),
            Rgba8::rgb(0, 255, 255),
            Rgba8::rgb(0, 0, 255),
            Rgba8::rgb(255, 0, 255),
        );
        assert!(key(r) < key(y) && key(y) < key(g) && key(g) < key(c));
        assert!(key(c) < key(b) && key(b) < key(m));
        // Within one hue bucket: dark→light by luma.
        assert!(key(Rgba8::rgb(64, 0, 0)) < key(Rgba8::rgb(255, 0, 0)));
        assert!(key(Rgba8::rgb(255, 0, 0)) < key(Rgba8::rgb(255, 128, 128)));
        // Same RGB: opaque before translucent, both before fully transparent.
        assert!(key(Rgba8::rgb(10, 200, 30)) < key(Rgba8::new(10, 200, 30, 128)));
        assert!(key(Rgba8::new(10, 200, 30, 128)) < key(Rgba8::new(10, 200, 30, 0)));
    }

    #[test]
    fn hex_roundtrip() {
        let c = Rgba8::new(0x12, 0x34, 0x56, 0x78);
        assert_eq!(Rgba8::from_hex(&c.to_hex()), Some(c));
        assert_eq!(Rgba8::from_hex("#FF0000"), Some(Rgba8::rgb(255, 0, 0)));
        assert_eq!(Rgba8::from_hex("#f00"), Some(Rgba8::rgb(255, 0, 0)));
        assert_eq!(Rgba8::from_hex("nope"), None); // 'n','o','p' are not hex digits
        assert_eq!(Rgba8::from_hex("#12"), None); // wrong length
    }

    #[test]
    fn premul_roundtrip_opaque() {
        for &c in &[Rgba8::rgb(10, 200, 30), Rgba8::WHITE, Rgba8::BLACK] {
            assert_eq!(from_premul(to_premul(c)), c);
        }
    }

    #[test]
    fn over_opaque_src_wins() {
        assert_eq!(over(Rgba8::rgb(255, 0, 0), Rgba8::rgb(0, 255, 0)), Rgba8::rgb(255, 0, 0));
    }

    #[test]
    fn over_transparent_src_is_noop() {
        let dst = Rgba8::rgb(1, 2, 3);
        assert_eq!(over(Rgba8::TRANSPARENT, dst), dst);
    }

    #[test]
    fn over_half_alpha_midpoint() {
        // red at 50% (a=128) over opaque green ≈ (128,127,0,255) by straight sRGB composite
        let out = over(Rgba8::new(255, 0, 0, 128), Rgba8::rgb(0, 255, 0));
        assert_eq!(out.a, 255);
        assert!((out.r as i32 - 128).abs() <= 2, "r={}", out.r);
        assert!((out.g as i32 - 127).abs() <= 2, "g={}", out.g);
        assert_eq!(out.b, 0);
    }

    #[test]
    fn hsv_roundtrip_close() {
        for &c in &[Rgba8::rgb(200, 100, 50), Rgba8::rgb(10, 240, 130), Rgba8::rgb(128, 128, 128)] {
            let back = hsv_to_rgb(rgb_to_hsv(c), 255);
            assert!(max_channel_delta(c, back) <= 2, "{:?} -> {:?}", c, back);
        }
    }

    #[test]
    fn hsv_shift_hue_wraps() {
        let c = Rgba8::rgb(255, 0, 0); // hue 0
        let shifted = hsv_shift(c, 120.0, 0.0, 0.0); // → green
        assert!(shifted.g > 200 && shifted.r < 60);
    }

    #[test]
    fn lerp_endpoints_exact() {
        let a = Rgba8::rgb(255, 0, 0);
        let b = Rgba8::rgb(0, 0, 255);
        assert_eq!(lerp_srgb(a, b, 0.0), a);
        assert_eq!(lerp_srgb(a, b, 1.0), b);
    }

    // ---- Levels LUT (low/gamma/high): goldens from an independent high-precision reference ----
    //
    // The golden arrays below were produced by a Python-stdlib reference (60-digit Decimal, no
    // dependencies) that mirrors the levels_lut contract exactly:
    //
    //     lo = min(lo,254); hi = max(hi,lo+1); g = clamp(gamma_th,100,10000); span = hi-lo
    //     v <= lo -> 0 ; v >= hi -> 255
    //     g == 1000 -> ((v-lo)*510 + span) // (2*span)            (exact integer round-half-up)
    //     else      -> floor((Decimal(v-lo)/span) ** (1000/g) * 255 + 1/2)
    //
    // For every pow-path entry the generator also measures the distance of out·255 from its
    // nearest .5 rounding boundary and REJECTS any triple with a margin under 1e-6; the engine's
    // det_pow pipeline is accurate to ~1e-12 absolute on the 0..255 scale (see util.rs Gate A
    // tests), five orders below that screen, so the exact-equality asserts here cannot flake —
    // any mismatch is a real defect. Accepted margins:
    //   (0,1000,255) integer path, exact       (0,2200,255)  6.448e-3      (0,455,255) 2.916e-3
    //   (32,1000,224) integer path, exact      (16,2500,240) 3.753e-4
    //   (0,10000,255) 4.645e-5                 (0,100,255)   7.353e-3

    // triple (0, 1000, 255): integer path, exact
    const GOLD_0_1000_255: [u8; 256] = [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
        16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
        32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47,
        48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63,
        64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79,
        80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95,
        96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111,
        112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127,
        128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143,
        144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159,
        160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175,
        176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191,
        192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207,
        208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223,
        224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239,
        240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255,
    ];

    // triple (0, 2200, 255): min boundary margin 6.448E-3
    const GOLD_0_2200_255: [u8; 256] = [
        0, 21, 28, 34, 39, 43, 46, 50, 53, 56, 59, 61, 64, 66, 68, 70,
        72, 74, 76, 78, 80, 82, 84, 85, 87, 89, 90, 92, 93, 95, 96, 98,
        99, 101, 102, 103, 105, 106, 107, 109, 110, 111, 112, 114, 115, 116, 117, 118,
        119, 120, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135,
        136, 137, 138, 139, 140, 141, 142, 143, 144, 144, 145, 146, 147, 148, 149, 150,
        151, 151, 152, 153, 154, 155, 156, 156, 157, 158, 159, 160, 160, 161, 162, 163,
        164, 164, 165, 166, 167, 167, 168, 169, 170, 170, 171, 172, 173, 173, 174, 175,
        175, 176, 177, 178, 178, 179, 180, 180, 181, 182, 182, 183, 184, 184, 185, 186,
        186, 187, 188, 188, 189, 190, 190, 191, 192, 192, 193, 194, 194, 195, 195, 196,
        197, 197, 198, 199, 199, 200, 200, 201, 202, 202, 203, 203, 204, 205, 205, 206,
        206, 207, 207, 208, 209, 209, 210, 210, 211, 212, 212, 213, 213, 214, 214, 215,
        215, 216, 217, 217, 218, 218, 219, 219, 220, 220, 221, 221, 222, 223, 223, 224,
        224, 225, 225, 226, 226, 227, 227, 228, 228, 229, 229, 230, 230, 231, 231, 232,
        232, 233, 233, 234, 234, 235, 235, 236, 236, 237, 237, 238, 238, 239, 239, 240,
        240, 241, 241, 242, 242, 243, 243, 244, 244, 245, 245, 246, 246, 247, 247, 248,
        248, 249, 249, 249, 250, 250, 251, 251, 252, 252, 253, 253, 254, 254, 255, 255,
    ];

    // triple (0, 455, 255): min boundary margin 2.916E-3
    const GOLD_0_455_255: [u8; 256] = [
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2,
        3, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 6, 6, 6,
        6, 7, 7, 7, 8, 8, 8, 9, 9, 9, 10, 10, 11, 11, 11, 12,
        12, 13, 13, 14, 14, 14, 15, 15, 16, 16, 17, 17, 18, 18, 19, 19,
        20, 21, 21, 22, 22, 23, 23, 24, 25, 25, 26, 26, 27, 28, 28, 29,
        30, 30, 31, 32, 33, 33, 34, 35, 36, 36, 37, 38, 39, 39, 40, 41,
        42, 43, 43, 44, 45, 46, 47, 48, 49, 50, 50, 51, 52, 53, 54, 55,
        56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 72,
        73, 74, 75, 76, 77, 78, 79, 81, 82, 83, 84, 85, 87, 88, 89, 90,
        92, 93, 94, 95, 97, 98, 99, 101, 102, 103, 105, 106, 107, 109, 110, 111,
        113, 114, 116, 117, 119, 120, 122, 123, 124, 126, 127, 129, 130, 132, 134, 135,
        137, 138, 140, 141, 143, 145, 146, 148, 150, 151, 153, 154, 156, 158, 160, 161,
        163, 165, 166, 168, 170, 172, 173, 175, 177, 179, 181, 183, 184, 186, 188, 190,
        192, 194, 196, 197, 199, 201, 203, 205, 207, 209, 211, 213, 215, 217, 219, 221,
        223, 225, 227, 229, 231, 234, 236, 238, 240, 242, 244, 246, 248, 251, 253, 255,
    ];

    // triple (32, 1000, 224): integer path, exact
    const GOLD_32_1000_224: [u8; 256] = [
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 1, 3, 4, 5, 7, 8, 9, 11, 12, 13, 15, 16, 17, 19, 20,
        21, 23, 24, 25, 27, 28, 29, 31, 32, 33, 35, 36, 37, 39, 40, 41,
        43, 44, 45, 46, 48, 49, 50, 52, 53, 54, 56, 57, 58, 60, 61, 62,
        64, 65, 66, 68, 69, 70, 72, 73, 74, 76, 77, 78, 80, 81, 82, 84,
        85, 86, 88, 89, 90, 92, 93, 94, 96, 97, 98, 100, 101, 102, 104, 105,
        106, 108, 109, 110, 112, 113, 114, 116, 117, 118, 120, 121, 122, 124, 125, 126,
        128, 129, 130, 131, 133, 134, 135, 137, 138, 139, 141, 142, 143, 145, 146, 147,
        149, 150, 151, 153, 154, 155, 157, 158, 159, 161, 162, 163, 165, 166, 167, 169,
        170, 171, 173, 174, 175, 177, 178, 179, 181, 182, 183, 185, 186, 187, 189, 190,
        191, 193, 194, 195, 197, 198, 199, 201, 202, 203, 205, 206, 207, 209, 210, 211,
        213, 214, 215, 216, 218, 219, 220, 222, 223, 224, 226, 227, 228, 230, 231, 232,
        234, 235, 236, 238, 239, 240, 242, 243, 244, 246, 247, 248, 250, 251, 252, 254,
        255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
        255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    ];

    // triple (16, 2500, 240): min boundary margin 3.753E-4
    const GOLD_16_2500_240: [u8; 256] = [
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 29, 39, 45, 51, 56, 60, 64, 67, 70, 74, 76, 79, 82, 84, 86,
        89, 91, 93, 95, 97, 99, 101, 103, 104, 106, 108, 109, 111, 113, 114, 116,
        117, 119, 120, 121, 123, 124, 125, 127, 128, 129, 131, 132, 133, 134, 135, 137,
        138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 149, 150, 151, 152, 153, 154,
        154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 165, 166, 167, 168,
        169, 170, 171, 171, 172, 173, 174, 175, 175, 176, 177, 178, 179, 179, 180, 181,
        182, 182, 183, 184, 185, 185, 186, 187, 188, 188, 189, 190, 190, 191, 192, 193,
        193, 194, 195, 195, 196, 197, 197, 198, 199, 199, 200, 201, 201, 202, 203, 203,
        204, 204, 205, 206, 206, 207, 208, 208, 209, 209, 210, 211, 211, 212, 212, 213,
        214, 214, 215, 215, 216, 217, 217, 218, 218, 219, 220, 220, 221, 221, 222, 222,
        223, 223, 224, 225, 225, 226, 226, 227, 227, 228, 228, 229, 229, 230, 230, 231,
        232, 232, 233, 233, 234, 234, 235, 235, 236, 236, 237, 237, 238, 238, 239, 239,
        240, 240, 241, 241, 242, 242, 243, 243, 244, 244, 245, 245, 246, 246, 247, 247,
        248, 248, 249, 249, 249, 250, 250, 251, 251, 252, 252, 253, 253, 254, 254, 255,
        255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    ];

    // triple (0, 10000, 255): min boundary margin 4.645E-5
    const GOLD_0_10000_255: [u8; 256] = [
        0, 147, 157, 164, 168, 172, 175, 178, 180, 183, 184, 186, 188, 189, 191, 192,
        193, 195, 196, 197, 198, 199, 200, 200, 201, 202, 203, 204, 204, 205, 206, 207,
        207, 208, 208, 209, 210, 210, 211, 211, 212, 212, 213, 213, 214, 214, 215, 215,
        216, 216, 217, 217, 218, 218, 218, 219, 219, 220, 220, 220, 221, 221, 221, 222,
        222, 222, 223, 223, 223, 224, 224, 224, 225, 225, 225, 226, 226, 226, 227, 227,
        227, 227, 228, 228, 228, 228, 229, 229, 229, 230, 230, 230, 230, 231, 231, 231,
        231, 232, 232, 232, 232, 232, 233, 233, 233, 233, 234, 234, 234, 234, 234, 235,
        235, 235, 235, 235, 236, 236, 236, 236, 236, 237, 237, 237, 237, 237, 238, 238,
        238, 238, 238, 239, 239, 239, 239, 239, 239, 240, 240, 240, 240, 240, 240, 241,
        241, 241, 241, 241, 241, 242, 242, 242, 242, 242, 242, 243, 243, 243, 243, 243,
        243, 244, 244, 244, 244, 244, 244, 244, 245, 245, 245, 245, 245, 245, 245, 246,
        246, 246, 246, 246, 246, 246, 247, 247, 247, 247, 247, 247, 247, 247, 248, 248,
        248, 248, 248, 248, 248, 249, 249, 249, 249, 249, 249, 249, 249, 249, 250, 250,
        250, 250, 250, 250, 250, 250, 251, 251, 251, 251, 251, 251, 251, 251, 251, 252,
        252, 252, 252, 252, 252, 252, 252, 252, 253, 253, 253, 253, 253, 253, 253, 253,
        253, 254, 254, 254, 254, 254, 254, 254, 254, 254, 254, 255, 255, 255, 255, 255,
    ];

    // triple (0, 100, 255): min boundary margin 7.353E-3
    const GOLD_0_100_255: [u8; 256] = [
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2,
        2, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 6, 6,
        6, 7, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 13, 13, 14,
        15, 16, 17, 17, 18, 19, 20, 21, 22, 24, 25, 26, 27, 29, 30, 32,
        33, 35, 37, 38, 40, 42, 44, 46, 48, 51, 53, 56, 58, 61, 64, 67,
        70, 73, 76, 80, 83, 87, 91, 95, 99, 103, 108, 113, 118, 123, 128, 133,
        139, 145, 151, 157, 164, 171, 178, 185, 193, 201, 209, 218, 227, 236, 245, 255,
    ];

    #[test]
    fn levels_lut_matches_reference_goldens() {
        let cases: [(u8, i32, u8, &[u8; 256]); 7] = [
            (0, 1000, 255, &GOLD_0_1000_255),
            (0, 2200, 255, &GOLD_0_2200_255),
            (0, 455, 255, &GOLD_0_455_255),
            (32, 1000, 224, &GOLD_32_1000_224),
            (16, 2500, 240, &GOLD_16_2500_240),
            (0, 10000, 255, &GOLD_0_10000_255),
            (0, 100, 255, &GOLD_0_100_255),
        ];
        for (lo, g, hi, want) in cases {
            let got = levels_lut(lo, g, hi);
            assert_eq!(&got, want, "LUT mismatch for ({lo}, {g}, {hi})");
        }
    }

    /// Determinism lock: pin the content hash of two pow-path tables. A det_pow refactor that
    /// changes any entry, or a platform whose float ops are not IEEE-exact, fails here instantly.
    /// (Correctness is proven by the goldens above; these values were recorded from the verified
    /// implementation.)
    #[test]
    fn levels_lut_hash_locked() {
        use crate::util::{hash_bytes, hash_hex};
        assert_eq!(hash_hex(hash_bytes(&levels_lut(0, 2200, 255))), "1af0def27634514916bb217e2224e3fb");
        assert_eq!(hash_hex(hash_bytes(&levels_lut(16, 2500, 240))), "87b8ec7de93f15e8abc2cfd7133f7fa2");
    }

    /// γ = 1 is a pure affine remap; verify exact round-half-up against the algebraic property
    /// u = round_half_up(x)  ⇔  u − x ∈ (−1/2, 1/2]  ⇔  2·u·span − 2·(v−lo)·255 ∈ (−span, span]
    /// (an independent characterization, not a re-execution of the production formula).
    #[test]
    fn levels_gamma_one_is_exact_affine() {
        for &(lo, hi) in &[(0u8, 255u8), (32, 224), (0, 1), (254, 255), (100, 101), (10, 240)] {
            let lut = levels_lut(lo, 1000, hi);
            let (lo, hi) = (lo as i32, hi as i32);
            let span = hi - lo;
            for v in 0..256i32 {
                let u = lut[v as usize] as i32;
                if v <= lo {
                    assert_eq!(u, 0);
                } else if v >= hi {
                    assert_eq!(u, 255);
                } else {
                    let d = 2 * u * span - 2 * (v - lo) * 255;
                    assert!(d > -span && d <= span, "({lo},{hi}) v={v}: u={u} off by {d}/{span}");
                }
            }
        }
    }

    #[test]
    fn levels_lut_monotone_and_endpoints() {
        for &lo in &[0u8, 16, 32, 128, 254] {
            for &hi in &[1u8, 64, 224, 240, 255] {
                if hi <= lo {
                    continue;
                }
                for &g in &[100, 455, 999, 1000, 1001, 2200, 10_000] {
                    let lut = levels_lut(lo, g, hi);
                    assert_eq!(lut[lo as usize], 0);
                    assert_eq!(lut[hi as usize], 255);
                    assert_eq!(lut[0], 0);
                    assert_eq!(lut[255], 255);
                    for v in 0..255 {
                        assert!(
                            lut[v] <= lut[v + 1],
                            "({lo},{g},{hi}) not monotone at v={v}"
                        );
                    }
                }
                // The integer fast path at γ=1 must seam smoothly into the det_pow path.
                let (a, b, c) =
                    (levels_lut(lo, 999, hi), levels_lut(lo, 1000, hi), levels_lut(lo, 1001, hi));
                for v in 0..256 {
                    assert!((a[v] as i32 - b[v] as i32).abs() <= 1, "seam 999/1000 at v={v}");
                    assert!((c[v] as i32 - b[v] as i32).abs() <= 1, "seam 1001/1000 at v={v}");
                }
            }
        }
    }

    #[test]
    fn levels_lut_sanitizes_degenerate_params() {
        // hi ≤ lo collapses to the minimal one-step span above the (clamped) low point.
        assert_eq!(levels_lut(255, 1000, 0), levels_lut(254, 1000, 255));
        assert_eq!(levels_lut(200, 1000, 100), levels_lut(200, 1000, 201));
        // γ clamps to [0.1, 10].
        assert_eq!(levels_lut(0, 5, 255), levels_lut(0, 100, 255));
        assert_eq!(levels_lut(0, -1000, 255), levels_lut(0, 100, 255));
        assert_eq!(levels_lut(0, 999_999, 255), levels_lut(0, 10_000, 255));
    }

    /// The GIMP mid-gray contract: the input value under the gamma thumb, v* = lo + 0.5^γ·span,
    /// maps to ~128 — and γ's direction is brighten-above-1, darken-below-1.
    #[test]
    fn levels_gamma_semantics() {
        // (v* computed independently: 0.5^2.2·255 ≈ 55.5, 16 + 0.5^2.5·224 ≈ 55.6,
        //  0.5^0.455·255 ≈ 186.0)
        for &(lo, g, hi, v_star) in &[(0u8, 2200, 255u8, 55usize), (16, 2500, 240, 56), (0, 455, 255, 186)] {
            let lut = levels_lut(lo, g, hi);
            let got = lut[v_star] as i32;
            assert!((got - 128).abs() <= 2, "({lo},{g},{hi}) mid {v_star} -> {got}");
        }
        assert!(levels_lut(0, 2200, 255)[128] > 128); // γ > 1 brightens midtones
        assert!(levels_lut(0, 455, 255)[128] < 128); // γ < 1 darkens midtones
    }

    #[test]
    fn levels_alpha_passthrough() {
        let lut = levels_lut(16, 2500, 240);
        for &a in &[0u8, 1, 128, 254, 255] {
            let c = Rgba8::new(100, 150, 200, a);
            let out = apply_levels_lut(c, &lut);
            assert_eq!(out.a, a);
            assert_eq!(out.r, lut[100]);
            assert_eq!(out.g, lut[150]);
            assert_eq!(out.b, lut[200]);
        }
    }
}
