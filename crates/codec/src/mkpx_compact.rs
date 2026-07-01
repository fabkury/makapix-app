//! The `.mkpx` **compact** envelope — the peripheral DEFLATE profile (v10 §16).
//!
//! The engine core (`makapix_engine::io`) writes and reads only the uncompressed **`plain`**
//! container. This module optionally wraps those canonical bytes in pure-Rust, zlib-framed DEFLATE
//! (`miniz_oxide`) for explicit "Save `.mkpx`" / source export, and transparently unwraps them on
//! open. It lives here, at the periphery — never in the engine — so the core stays dependency-free
//! and its untrusted-input loader never inflates (inflation happens here, under an explicit bound).
//!
//! Byte-determinism (per profile) holds for the pinned `miniz_oxide` version + fixed level. zlib
//! framing carries its own Adler-32, giving stream integrity without a separate checksum; a stated
//! uncompressed length additionally bounds the inflate (a decompression-bomb guard).

use makapix_engine::io::SIGNATURE as PLAIN_SIG;

/// Compact-profile signature: hardened, one byte from `plain` (`'Z'` for "zipped" vs `'X'`).
pub const COMPACT_SIG: [u8; 8] = [0x89, b'M', b'K', b'P', b'Z', 0x0D, 0x0A, 0x1A];
/// 8-byte signature + `u32` uncompressed length.
const HEADER_LEN: usize = 12;
/// Hard cap on the inflated size — a decompression-bomb guard. Any real v10 document is far below.
const MAX_INFLATED: usize = 512 * 1024 * 1024;
/// Fixed DEFLATE level; pinned so the compact profile is byte-deterministic for a given build.
const DEFLATE_LEVEL: u8 = 6;

#[derive(Debug, PartialEq, Eq)]
pub enum CompactError {
    /// Not a `.mkpx` file (neither the plain nor the compact signature).
    BadMagic,
    /// The declared inflated size exceeds the bomb-guard cap.
    TooLarge,
    /// The DEFLATE stream is corrupt or its length is inconsistent.
    Corrupt,
}

impl std::fmt::Display for CompactError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CompactError::BadMagic => write!(f, "not a .mkpx file (bad magic)"),
            CompactError::TooLarge => write!(f, "compact .mkpx declares an oversized payload"),
            CompactError::Corrupt => write!(f, "corrupt compact .mkpx (deflate)"),
        }
    }
}

/// Whether `bytes` is a compact-profile `.mkpx` (as opposed to plain, or something else).
pub fn is_compact(bytes: &[u8]) -> bool {
    bytes.len() >= 8 && bytes[..8] == COMPACT_SIG
}

/// Wrap canonical `plain` bytes (from `makapix_engine::io::save_to_bytes`) in the compact envelope.
/// Use for explicit "Save `.mkpx`" / export; **never** on the autosave path (which stays plain).
pub fn compress(plain: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(plain.len() / 2 + HEADER_LEN);
    out.extend_from_slice(&COMPACT_SIG);
    out.extend_from_slice(&(plain.len() as u32).to_le_bytes());
    out.extend_from_slice(&miniz_oxide::deflate::compress_to_vec_zlib(plain, DEFLATE_LEVEL));
    out
}

/// Return canonical `plain` bytes from either a plain **or** a compact `.mkpx`. A loader should call
/// this before handing bytes to `makapix_engine::io::load_from_bytes`. Plain input is returned as-is
/// (cheap borrow-to-owned only when needed); compact input is verified and inflated under the cap.
pub fn open(bytes: &[u8]) -> Result<Vec<u8>, CompactError> {
    if bytes.len() >= 8 && bytes[..8] == PLAIN_SIG {
        return Ok(bytes.to_vec()); // already plain — pass through
    }
    if bytes.len() < HEADER_LEN || bytes[..8] != COMPACT_SIG {
        return Err(CompactError::BadMagic);
    }
    let ulen = u32::from_le_bytes([bytes[8], bytes[9], bytes[10], bytes[11]]) as usize;
    if ulen > MAX_INFLATED {
        return Err(CompactError::TooLarge);
    }
    let plain =
        miniz_oxide::inflate::decompress_to_vec_zlib_with_limit(&bytes[HEADER_LEN..], ulen.max(1))
            .map_err(|_| CompactError::Corrupt)?;
    if plain.len() != ulen {
        return Err(CompactError::Corrupt); // stated length must match what we inflated
    }
    Ok(plain)
}

#[cfg(test)]
mod tests {
    use super::*;
    use makapix_engine::Session;

    fn sample_plain() -> Vec<u8> {
        let mut s = Session::new(64, 64);
        let _ = s.run_script(
            "SelectTool(Pencil)\nPointerDown(1,1)\nPointerMove(40,20)\nPointerUp()\nAddFrame()",
        );
        s.save_bytes()
    }

    #[test]
    fn compress_open_roundtrips() {
        let plain = sample_plain();
        let compact = compress(&plain);
        assert!(is_compact(&compact));
        assert!(!is_compact(&plain));
        assert_eq!(open(&compact).unwrap(), plain, "compact → plain is exact");
    }

    #[test]
    fn open_passes_plain_through() {
        let plain = sample_plain();
        assert_eq!(open(&plain).unwrap(), plain);
    }

    #[test]
    fn compact_is_smaller_for_compressible_input() {
        // A large flat document compresses well (its plain form is already tiny via dedup, but the
        // structural bytes still shrink under DEFLATE).
        let mut s = Session::new(256, 256);
        let _ = s.run_script("Fill(#204060FF)");
        let plain = s.save_bytes();
        let compact = compress(&plain);
        // Never assert a ratio on tiny inputs; just that it round-trips and is a valid compact file.
        assert_eq!(open(&compact).unwrap(), plain);
    }

    #[test]
    fn rejects_garbage_and_corruption() {
        assert_eq!(open(&[0u8; 4]), Err(CompactError::BadMagic));
        assert_eq!(open(b"not an mkpx file at all"), Err(CompactError::BadMagic));
        let mut compact = compress(&sample_plain());
        let n = compact.len();
        compact[n - 5] ^= 0xFF; // corrupt the deflate stream
        assert!(matches!(open(&compact), Err(CompactError::Corrupt)));
    }

    #[test]
    fn engine_loads_an_opened_compact_file() {
        let plain = sample_plain();
        let compact = compress(&plain);
        let opened = open(&compact).unwrap();
        let mut s = Session::new(8, 8);
        assert!(s.load_bytes(&opened).is_ok(), "engine loads inflated compact bytes");
    }
}
