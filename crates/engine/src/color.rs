//! Color: 8-bit straight RGBA at the boundary, premultiplied internally; integer-exact
//! sRGB math and HSV conversion (SPEC §6). No linear-light path.

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

/// Adjust brightness (`db` in [-255,255]) and contrast (`cf` multiplier around 128).
pub fn brightness_contrast(c: Rgba8, db: i32, cf: f32) -> Rgba8 {
    let adj = |v: u8| -> u8 {
        let f = (v as f32 - 128.0) * cf + 128.0 + db as f32;
        (f + 0.5).clamp(0.0, 255.0) as u8
    };
    Rgba8::new(adj(c.r), adj(c.g), adj(c.b), c.a)
}

#[cfg(test)]
mod tests {
    use super::*;

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
}
