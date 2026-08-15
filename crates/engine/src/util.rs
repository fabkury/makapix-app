//! Foundational utilities: content hashing, a seeded PRNG, a virtual clock, and id types.
//!
//! Dependency-free by design (SPEC §4). Determinism is the contract (SPEC §5): the only
//! randomness is `SeededRng`, the only time is `VirtualClock`.

/// 128-bit content hash. We use a dependency-free FNV-1a over 64-bit halves with distinct
/// offset bases; collision-resistant enough for undo invariants and regression checks.
pub type Hash = u128;

const FNV_OFFSET_A: u64 = 0xcbf2_9ce4_8422_2325;
const FNV_OFFSET_B: u64 = 0x84222325cbf29ce4u64 ^ 0x9e37_79b9_7f4a_7c15;
const FNV_PRIME: u64 = 0x0000_0100_0000_01b3;

/// Deterministic 128-bit hash of a byte slice.
pub fn hash_bytes(bytes: &[u8]) -> Hash {
    let mut a = FNV_OFFSET_A;
    let mut b = FNV_OFFSET_B;
    for (i, &byte) in bytes.iter().enumerate() {
        a ^= byte as u64;
        a = a.wrapping_mul(FNV_PRIME);
        // second lane mixes position to harden against transposition collisions
        b ^= (byte as u64).wrapping_add((i as u64).wrapping_mul(0x9E37_79B9));
        b = b.wrapping_mul(FNV_PRIME);
    }
    ((a as u128) << 64) | (b as u128)
}

/// Incremental hasher for streaming many chunks (buffers, tile tables) deterministically.
#[derive(Clone, Debug)]
pub struct Hasher {
    a: u64,
    b: u64,
    n: u64,
}

impl Default for Hasher {
    fn default() -> Self {
        Hasher { a: FNV_OFFSET_A, b: FNV_OFFSET_B, n: 0 }
    }
}

impl Hasher {
    pub fn new() -> Self {
        Self::default()
    }
    pub fn write(&mut self, bytes: &[u8]) {
        for &byte in bytes {
            self.a ^= byte as u64;
            self.a = self.a.wrapping_mul(FNV_PRIME);
            self.b ^= (byte as u64).wrapping_add(self.n.wrapping_mul(0x9E37_79B9));
            self.b = self.b.wrapping_mul(FNV_PRIME);
            self.n = self.n.wrapping_add(1);
        }
    }
    pub fn write_u32(&mut self, v: u32) {
        self.write(&v.to_le_bytes());
    }
    pub fn finish(&self) -> Hash {
        ((self.a as u128) << 64) | (self.b as u128)
    }
}

/// Lowercase 32-hex-digit rendering of a `Hash`.
pub fn hash_hex(h: Hash) -> String {
    format!("{:032x}", h)
}

/// SplitMix64 finalizer: a fast, high-quality 64-bit mixer. Doubles as `SeededRng`'s state
/// expander and as the position hash behind the single-coat speckle field (ADR 0007) — pure
/// integer ops, so it is deterministic on every platform by construction.
#[inline]
pub fn splitmix64(z: u64) -> u64 {
    let mut v = z;
    v = (v ^ (v >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    v = (v ^ (v >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    v ^ (v >> 31)
}

/// Deterministic per-pixel hash for the speckle field: mixes a pixel position with a per-stroke
/// seed. Two rounds of `splitmix64` decorrelate the structured (x, y) lattice from the seed.
#[inline]
pub fn hash_xy(x: i32, y: i32, seed: u64) -> u64 {
    let p = ((x as u32 as u64) << 32) | (y as u32 as u64);
    splitmix64(seed.wrapping_add(splitmix64(p)))
}

/// xoshiro256** — small, fast, high-quality, fully deterministic from a seed (SPEC §5.1).
#[derive(Clone, Debug)]
pub struct SeededRng {
    s: [u64; 4],
}

impl Default for SeededRng {
    fn default() -> Self {
        SeededRng::new(0)
    }
}

impl SeededRng {
    pub fn new(seed: u64) -> Self {
        // SplitMix64 to expand the seed into the 256-bit state.
        let mut z = seed;
        let mut next = || {
            z = z.wrapping_add(0x9E37_79B9_7F4A_7C15);
            splitmix64(z)
        };
        SeededRng { s: [next(), next(), next(), next()] }
    }

    #[inline]
    pub fn next_u64(&mut self) -> u64 {
        let result = self.s[1].wrapping_mul(5).rotate_left(7).wrapping_mul(9);
        let t = self.s[1] << 17;
        self.s[2] ^= self.s[0];
        self.s[3] ^= self.s[1];
        self.s[1] ^= self.s[2];
        self.s[0] ^= self.s[3];
        self.s[2] ^= t;
        self.s[3] = self.s[3].rotate_left(45);
        result
    }

    /// Uniform `f32` in `[0, 1)`.
    #[inline]
    pub fn next_f32(&mut self) -> f32 {
        // top 24 bits → 24-bit mantissa precision
        ((self.next_u64() >> 40) as f32) / (1u32 << 24) as f32
    }

    /// Uniform integer in `[0, n)` (n > 0).
    #[inline]
    pub fn below(&mut self, n: u32) -> u32 {
        if n == 0 {
            return 0;
        }
        (self.next_u64() % n as u64) as u32
    }
}

/// Virtual clock — the only time source in the engine (SPEC §5.2). Real time never enters.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct VirtualClock {
    pub now_us: u64,
}

impl VirtualClock {
    pub fn advance_us(&mut self, us: u64) {
        self.now_us = self.now_us.wrapping_add(us);
    }
    pub fn advance_ms(&mut self, ms: u64) {
        self.advance_us(ms.wrapping_mul(1000));
    }
}

// ---------------------------------------------------------------------------------------------
// Deterministic transcendentals (SPEC §5). Goldens must be byte-identical across Windows x86-64,
// Android ARM64/ARM32, and iOS ARM64, but libm's `powf`/`exp`/`ln` are not correctly rounded —
// their last-ulp behavior forks per platform (the same hazard the quarter-turn snap table in
// session/canvas.rs routes around for `cos`/`sin`). These implementations use ONLY operations
// IEEE 754 defines exactly (+ − × ÷, floor, comparisons, bit manipulation) in a fixed evaluation
// order, and never `mul_add` — Rust/LLVM does not contract or reassociate float expressions, so
// every platform computes bit-identical results.

/// Deterministic log2 of a positive, finite, normal `x`.
pub fn det_log2(x: f64) -> f64 {
    debug_assert!(x >= f64::MIN_POSITIVE && x.is_finite());
    let bits = x.to_bits();
    let mut k = ((bits >> 52) & 0x7ff) as i64 - 1023;
    // Mantissa in [1, 2); halving (exact) when above √2 narrows it to (√2/2, √2], which keeps
    // the series argument t small: t = (m−1)/(m+1) ∈ (−0.1716, 0.1716].
    let mut m = f64::from_bits((bits & 0x000f_ffff_ffff_ffff) | (1023u64 << 52));
    if m > std::f64::consts::SQRT_2 {
        m *= 0.5;
        k += 1;
    }
    let t = (m - 1.0) / (m + 1.0);
    let t2 = t * t;
    // ln m = 2·atanh(t); atanh(t)/t = Σ t^(2i)/(2i+1), Horner-truncated after t^18/19 — the next
    // term is < 3e-18 relative for |t| ≤ 0.1716.
    const ODD: [f64; 9] = [17.0, 15.0, 13.0, 11.0, 9.0, 7.0, 5.0, 3.0, 1.0];
    let mut s = 1.0 / 19.0;
    for &d in &ODD {
        s = s * t2 + 1.0 / d;
    }
    let ln_m = 2.0 * t * s;
    k as f64 + ln_m * std::f64::consts::LOG2_E
}

/// Deterministic 2^y for y ∈ (−1000, 1000).
pub fn det_exp2(y: f64) -> f64 {
    debug_assert!(y > -1000.0 && y < 1000.0);
    let i = (y.floor() as i64).clamp(-1022, 1023);
    let f = y - i as f64; // exact: the fractional part's bits are a suffix of y's mantissa
    let x = f * std::f64::consts::LN_2; // [0, ln 2)
    // exp(x) = Σ x^k/k!, nested-Horner-truncated at k = 17 — the next term is < 3e-19 for
    // x < ln 2.
    let mut s = 1.0;
    let mut k = 17.0;
    while k >= 1.0 {
        s = 1.0 + x * s / k;
        k -= 1.0; // exact for these small integers
    }
    s * f64::from_bits(((1023 + i) as u64) << 52)
}

/// Deterministic x^e for x ∈ [0, 1], e ∈ (0, 64) — the Levels gamma curve. Out-of-domain x
/// clamps to the endpoint values (0^e = 0, 1^e = 1).
pub fn det_pow(x: f64, e: f64) -> f64 {
    debug_assert!(e > 0.0 && e < 64.0);
    if x <= 0.0 {
        return 0.0;
    }
    if x >= 1.0 {
        return 1.0;
    }
    det_exp2(e * det_log2(x))
}

/// Deterministic (sin x, cos x) for the AA shape rasterizers (ADR 0008). libm's `sin_cos` is
/// not correctly rounded and forks per platform, so AA-ON rotation goes through this instead
/// (AA-OFF keeps the legacy libm path untouched — its pixels are pinned). Quadrant reduction
/// around a fixed π/2 literal, then fixed-length Taylor polynomials in a fixed evaluation
/// order (IEEE-exact ops only, no `mul_add`, same doctrine as `det_log2`). Absolute error is
/// < 1e-10 over the shape-rotation range (|x| ≤ ~7 rad) — five orders below the 1/512-pixel
/// quantum the 16×16 subsample grid can even see.
pub fn det_sincos(x: f64) -> (f64, f64) {
    debug_assert!(x.abs() < 1.0e6, "det_sincos expects a UI-scale angle");
    const HALF_PI: f64 = std::f64::consts::FRAC_PI_2;
    // Nearest quadrant multiple: r ∈ [-π/4 - ε, π/4 + ε] (the reduction constant's rounding is
    // itself deterministic, so the tiny residual is identical everywhere).
    let q = (x / HALF_PI + 0.5).floor();
    let r = x - q * HALF_PI;
    let r2 = r * r;
    // sin r / r and cos r as Horner-truncated Taylor series; at |r| ≤ π/4 the next terms
    // (r^15/15!, r^14/14!) are < 3e-14.
    let s = r
        * (1.0
            + r2 * (-1.0 / 6.0
                + r2 * (1.0 / 120.0
                    + r2 * (-1.0 / 5040.0 + r2 * (1.0 / 362_880.0 + r2 * (-1.0 / 39_916_800.0 + r2 / 6_227_020_800.0))))));
    let c = 1.0
        + r2 * (-1.0 / 2.0
            + r2 * (1.0 / 24.0
                + r2 * (-1.0 / 720.0 + r2 * (1.0 / 40_320.0 + r2 * (-1.0 / 3_628_800.0 + r2 / 479_001_600.0)))));
    match (q as i64).rem_euclid(4) {
        0 => (s, c),
        1 => (c, -s),
        2 => (-s, -c),
        _ => (-c, s),
    }
}

/// Monotonic id generator for stable frame/layer ids that survive reordering.
#[derive(Clone, Debug, Default)]
pub struct IdGen {
    next: u32,
}
impl IdGen {
    /// Start allocating ids at `next`. Used when rehydrating a persisted document so freshly
    /// allocated ids sit just past the highest stored id — without an O(max_id) warm-up loop (a
    /// crafted file with id 0xFFFFFFFF would otherwise spin ~4.3 billion iterations). [audit F-2]
    pub fn starting_at(next: u32) -> Self {
        IdGen { next }
    }
    pub fn alloc(&mut self) -> u32 {
        let id = self.next;
        self.next = self.next.wrapping_add(1);
        id
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn det_sincos_tracks_libm_and_pins_the_axes() {
        // Exact at the axes (the reduction lands r = 0 there, up to the π/2 literal's rounding).
        assert_eq!(det_sincos(0.0), (0.0, 1.0));
        // Close to libm everywhere the shape rotation can reach (libm is the accuracy referee
        // only — determinism is what det_sincos adds).
        let mut x = -7.0f64;
        while x <= 7.0 {
            let (s, c) = det_sincos(x);
            assert!((s - x.sin()).abs() < 1e-10, "sin({x}) drifted: {s}");
            assert!((c - x.cos()).abs() < 1e-10, "cos({x}) drifted: {c}");
            assert!((s * s + c * c - 1.0).abs() < 1e-9);
            x += 0.0137;
        }
    }

    #[test]
    fn hash_is_order_sensitive() {
        assert_ne!(hash_bytes(&[1, 2, 3]), hash_bytes(&[3, 2, 1]));
        assert_eq!(hash_bytes(&[1, 2, 3]), hash_bytes(&[1, 2, 3]));
    }

    #[test]
    fn hasher_matches_oneshot_for_single_write() {
        let mut h = Hasher::new();
        h.write(&[9, 8, 7, 6]);
        assert_eq!(h.finish(), hash_bytes(&[9, 8, 7, 6]));
    }

    /// Pin `splitmix64`'s exact outputs (reference values from the canonical SplitMix64
    /// finalizer) so the RNG state expansion and the speckle field can never fork silently.
    #[test]
    fn splitmix64_bit_patterns_are_pinned() {
        assert_eq!(splitmix64(0), 0);
        // Canonical SplitMix64 test vector: first output for seed 0.
        assert_eq!(splitmix64(0x9E37_79B9_7F4A_7C15), 0xE220_A839_7B1D_CDAF);
        // Seeding is unchanged by the extraction: seed 0's first state word is the mix of
        // one golden-ratio step.
        assert_eq!(SeededRng::new(0).s[0], 0xE220_A839_7B1D_CDAF);
    }

    #[test]
    fn hash_xy_is_deterministic_and_position_sensitive() {
        assert_eq!(hash_xy(3, 7, 42), hash_xy(3, 7, 42));
        assert_ne!(hash_xy(3, 7, 42), hash_xy(7, 3, 42), "transposed coords must differ");
        assert_ne!(hash_xy(3, 7, 42), hash_xy(3, 7, 43), "seed must matter");
        assert_ne!(hash_xy(-1, 0, 1), hash_xy(0, -1, 1), "negative coords stay distinct");
        // The low byte (the speck threshold lane) is roughly uniform: over a 64×64 grid,
        // each bucket of 16 values should land within a loose band around 256.
        let mut buckets = [0u32; 16];
        for y in 0..64 {
            for x in 0..64 {
                buckets[(hash_xy(x, y, 5) & 0xFF) as usize / 16] += 1;
            }
        }
        for (i, &n) in buckets.iter().enumerate() {
            assert!((160..=360).contains(&n), "bucket {i} skewed: {n}/4096");
        }
    }

    #[test]
    fn rng_is_deterministic_and_reproducible() {
        let mut a = SeededRng::new(42);
        let mut b = SeededRng::new(42);
        for _ in 0..1000 {
            assert_eq!(a.next_u64(), b.next_u64());
        }
        let mut c = SeededRng::new(43);
        assert_ne!(SeededRng::new(42).next_u64(), c.next_u64());
    }

    #[test]
    fn rng_f32_in_range() {
        let mut r = SeededRng::new(7);
        for _ in 0..10_000 {
            let v = r.next_f32();
            assert!((0.0..1.0).contains(&v));
        }
    }

    #[test]
    fn rng_below_bounds() {
        let mut r = SeededRng::new(1);
        for _ in 0..10_000 {
            assert!(r.below(10) < 10);
        }
    }

    // ---- deterministic transcendentals (the Levels gamma curve, SPEC §5) ----

    /// The std consts feed the deterministic pipeline; pin their exact bit patterns so a toolchain
    /// or platform that disagreed would fail loudly instead of forking goldens silently.
    #[test]
    fn det_constants_bit_patterns() {
        assert_eq!(std::f64::consts::LN_2.to_bits(), 0x3FE6_2E42_FEFA_39EF);
        assert_eq!(std::f64::consts::LOG2_E.to_bits(), 0x3FF7_1547_652B_82FE);
        assert_eq!(std::f64::consts::SQRT_2.to_bits(), 0x3FF6_A09E_667F_3BCD);
    }

    /// Correctness oracle: agree with libm's `powf` (accurate to ~1 ulp on the test machine) to
    /// 1e-12 relative over a dense grid spanning the whole Levels domain. This proves the series
    /// math is right; determinism is by construction (only IEEE-exact ops).
    #[test]
    fn det_pow_matches_std_powf_on_dense_grid() {
        // Exponents 1/γ for the full clamped gamma range γ ∈ [0.1, 10], plus uneven values.
        let exps = [
            10.0, 8.0, 5.0, 3.3333, 2.1978, 2.0, 1.4286, 1.0, 0.7519, 0.4545, 0.4, 0.3077, 0.2,
            0.1337, 0.1,
        ];
        for &e in &exps {
            for xi in 1..4096u32 {
                let x = xi as f64 / 4096.0;
                let want = x.powf(e);
                let got = det_pow(x, e);
                let rel = ((got - want) / want).abs();
                assert!(rel < 1e-12, "x={x} e={e}: det {got} vs powf {want} (rel {rel:e})");
            }
        }
    }

    #[test]
    fn det_pow_exact_at_one_and_monotone() {
        for &e in &[0.1, 0.5, 1.0, 2.0, 10.0] {
            assert_eq!(det_pow(1.0, e), 1.0);
            assert_eq!(det_pow(0.0, e), 0.0);
            let mut prev = 0.0;
            for xi in 1..=4096u32 {
                let v = det_pow(xi as f64 / 4096.0, e);
                assert!(v > 0.0 && v <= 1.0);
                assert!(v >= prev, "not monotone at x={}/4096 e={e}", xi);
                prev = v;
            }
        }
    }

    /// exp2 ∘ log2 must be the identity to ~1e-14 relative (each leg contributes ≤ a few ulps).
    #[test]
    fn det_exp2_log2_roundtrip() {
        for xi in 1..=4096u32 {
            let x = xi as f64 / 4096.0;
            let back = det_exp2(det_log2(x));
            let rel = ((back - x) / x).abs();
            assert!(rel < 1e-13, "roundtrip x={x}: {back} (rel {rel:e})");
        }
        // And across magnitudes, incl. values above 1 (det_log2's full domain).
        for &x in &[1.0, 1.5, 2.0, 3.0, 255.0, 1e6, 1e-6] {
            let back = det_exp2(det_log2(x));
            assert!(((back - x) / x).abs() < 1e-13);
        }
    }
}
