#![no_main]
//! Fuzz the compact `.mkpx` envelope and the path behind it (fuzzing-review W4).
//!
//! An explicit "Save .mkpx" and the Club layers attachment are the **compact** profile: a
//! 12-byte header (signature + stated length) around a zlib stream
//! (`makapix_codec::mkpx_compact`). On Club edit/remix another user's file goes through
//! `mkpx_compact::open` and then the tolerant loader — untrusted bytes, and a panic
//! aborts the app. Oracles:
//!   1. No panic in `open` on any bytes (hostile header, hostile deflate stream).
//!   2. Whatever `open` returns survives the tolerant loader, the META reader, and the
//!      read paths the shell calls after an open.
//!   3. `open` is exact: its output has the stated length, and compressing it again
//!      opens back to the same bytes.
//! `-malloc_limit_mb` (tools/fuzz/run_fuzz.sh) is the bomb oracle: a small file that makes
//! `open` allocate past it is a finding.

use libfuzzer_sys::{fuzz_mutator, fuzz_target, fuzzer_mutate};
use makapix_codec::mkpx_compact;
use makapix_engine::Session;

const PLAIN_SIG: [u8; 8] = [0x89, b'M', b'K', b'P', b'X', 0x0D, 0x0A, 0x1A];
/// fourcc(4) + flags(1) + length(4) + crc32c payload(4) — `io.rs::INTG_LEN`.
const INTG_LEN: usize = 13;

/// CRC-32C, as in `fuzz_load_mkpx` (the same re-signing reasoning applies).
fn crc32c(bytes: &[u8]) -> u32 {
    let mut crc = 0xFFFF_FFFFu32;
    for &b in bytes {
        crc ^= b as u32;
        for _ in 0..8 {
            crc = if crc & 1 != 0 { (crc >> 1) ^ 0x82F6_3B78 } else { crc >> 1 };
        }
    }
    crc ^ 0xFFFF_FFFF
}

// Two walls stand between a mutated compact file and the loader behind it: zlib's Adler-32
// over the inflated bytes, then the plain container's CRC-32C. Mutating the envelope bytes
// directly exercises the header checks and the inflater (which runs before its checksum is
// compared) but almost never gets past both. So half of the mutations work on the INSIDE:
// open the envelope, mutate the plain bytes, re-sign them, and wrap them again — what an
// attacker with the format spec does. The other half mutate the raw envelope.
fuzz_mutator!(|data: &mut [u8], size: usize, max_size: usize, seed: u32| {
    if seed % 2 == 0 {
        if let Ok(mut plain) = mkpx_compact::open(&data[..size]) {
            let plain_len = plain.len();
            plain.resize(plain_len + 256, 0);
            let cap = plain.len();
            let n = fuzzer_mutate(&mut plain, plain_len, cap);
            plain.truncate(n);
            // 1 in 8 of these stays unsigned so the loader's reject paths stay covered.
            if seed % 16 != 0 && n >= PLAIN_SIG.len() + INTG_LEN {
                plain[..PLAIN_SIG.len()].copy_from_slice(&PLAIN_SIG);
                let body_end = n - INTG_LEN;
                let crc = crc32c(&plain[..body_end]);
                let trailer = &mut plain[body_end..];
                trailer[..4].copy_from_slice(b"INTG");
                trailer[4] = 1; // bit0 = critical
                trailer[5..9].copy_from_slice(&4u32.to_le_bytes());
                trailer[9..13].copy_from_slice(&crc.to_le_bytes());
            }
            let wrapped = mkpx_compact::compress(&plain);
            if wrapped.len() <= max_size {
                data[..wrapped.len()].copy_from_slice(&wrapped);
                return wrapped.len();
            }
        }
    }
    fuzzer_mutate(data, size, max_size)
});

fuzz_target!(|data: &[u8]| {
    let _ = mkpx_compact::is_compact(data);
    let Ok(plain) = mkpx_compact::open(data) else { return };

    if mkpx_compact::is_compact(data) {
        let stated = u32::from_le_bytes([data[8], data[9], data[10], data[11]]) as usize;
        assert!(
            plain.len() == stated,
            "open returned {} bytes for a stated length of {}",
            plain.len(),
            stated
        );
    }
    let rewrapped = mkpx_compact::compress(&plain);
    assert!(mkpx_compact::is_compact(&rewrapped), "compress did not produce a compact file");
    assert!(
        mkpx_compact::open(&rewrapped).as_deref() == Ok(&plain[..]),
        "compress → open is not exact"
    );

    // The edit/remix path: the META read, the app's tolerant open, then what the shell reads.
    let _ = makapix_engine::io::read_meta_str(&plain);
    let mut sess = Session::new(8, 8);
    if sess.load_bytes_tolerant(&plain).is_ok() {
        let _ = sess.composite_active_bytes();
        let _ = sess.state_json();
        let _ = sess.frame_thumb_bytes(0, 16, 16);
        let saved = sess.save_bytes();
        let mut re = Session::empty();
        assert!(
            re.load_bytes(&saved).is_ok(),
            "the save of an opened compact document fails a strict load"
        );
    }
});
