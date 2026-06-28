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
            let mut v = z;
            v = (v ^ (v >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
            v = (v ^ (v >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
            v ^ (v >> 31)
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
}
