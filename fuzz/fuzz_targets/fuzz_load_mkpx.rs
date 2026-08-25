#![no_main]
//! Coverage-guided fuzz of the `.mkpx` loader (docs/fuzzing/ANALYSIS.md §2.1).
//!
//! Since mkpx-upload shipped, other users' `.mkpx` files reach this parser via Club
//! edit/remix — the input is adversarial, and in the shipped app a panic aborts the
//! whole process (`panic = "abort"`). Oracles here:
//!   1. No panic on any byte string, strict or tolerant path (crash oracle).
//!   2. Every FFI read path survives whatever state a load leaves behind.
//!   3. A strict-loadable document must round-trip: save → load → identical content
//!      hash, and the resave must be byte-identical (the byte-determinism promise).
//! Run with `-rss_limit_mb=512` (tools/fuzz/run_fuzz.sh does) so the Android ~1 GiB
//! allocator wall acts as an oracle on the workstation: an allocation bomb that would
//! SIGABRT a phone shows up here as an RSS-limit finding.

use libfuzzer_sys::{fuzz_mutator, fuzz_target, fuzzer_mutate};
use makapix_engine::Session;

// ---- CRC re-signing custom mutator (docs/fuzzing/ANALYSIS.md §1.6/§3.3) ----
//
// The loader verifies a whole-file CRC-32C BEFORE trusting any body byte
// (`io.rs::load_from_bytes_tolerant_budgeted`), so every naively-mutated input dies at
// that one branch: a 2026-08-25 run did 18.4M executions and never moved past 1618
// edges. This is the §1.6 "semantic wall".
//
// The countermeasure re-signs after mutating: restore the signature, rebuild the fixed
// 13-byte INTG trailer, and store a correct CRC over the new body. That models exactly
// what a real attacker does (CRC-32C is not cryptographic — a crafted hostile file
// simply carries a valid checksum), and it keeps the shipped verification path IN the
// fuzzed build, unlike a skip-verification feature flag.
//
// A share of mutations is deliberately left unsigned so the reject paths (bad magic,
// missing/short trailer, CRC mismatch) stay reachable rather than becoming dead code.

const SIGNATURE: [u8; 8] = [0x89, b'M', b'K', b'P', b'X', 0x0D, 0x0A, 0x1A];
/// fourcc(4) + flags(1) + length(4) + crc32c payload(4) — `io.rs::INTG_LEN`.
const INTG_LEN: usize = 13;

/// CRC-32C (Castagnoli, reflected poly 0x82F63B78) — mirrors `io.rs::crc32c`. Duplicated
/// rather than exported: the fuzz harness must not widen the engine's public API.
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

fuzz_mutator!(|data: &mut [u8], size: usize, max_size: usize, seed: u32| {
    let new_size = fuzzer_mutate(data, size, max_size);

    // Leave 1 in 8 mutants unsigned so container-rejection paths stay covered.
    if seed % 8 == 0 || new_size < SIGNATURE.len() + INTG_LEN {
        return new_size;
    }

    data[..SIGNATURE.len()].copy_from_slice(&SIGNATURE);
    let body_end = new_size - INTG_LEN;
    let crc = crc32c(&data[..body_end]);
    let trailer = &mut data[body_end..new_size];
    trailer[..4].copy_from_slice(b"INTG");
    trailer[4] = 1; // bit0 = critical
    trailer[5..9].copy_from_slice(&4u32.to_le_bytes()); // payload length
    trailer[9..13].copy_from_slice(&crc.to_le_bytes());
    new_size
});

/// Exercise the read paths that cross the FFI, with deliberately stale indices
/// (same pattern as `crates/engine/tests/fuzz_inputs.rs::poke_reads`).
fn poke_reads(sess: &Session) {
    let _ = sess.composite_active_bytes();
    let _ = sess.state_json();
    let _ = sess.pixel(999, 999, 9999, -9999);
    let _ = sess.layer_hash(999, 999);
    let _ = sess.frame_hash(999);
}

fuzz_target!(|data: &[u8]| {
    // Strict path (the load the CLI and tests use).
    let mut strict = Session::new(8, 8);
    let strict_ok = strict.load_bytes(data).is_ok();
    poke_reads(&strict);

    // Tolerant path (the app's open path — repairs what it can, warns).
    let mut tolerant = Session::new(8, 8);
    let _ = tolerant.load_bytes_tolerant(data);
    poke_reads(&tolerant);
    let _ = tolerant.save_bytes();

    if strict_ok {
        let saved = strict.save_bytes();
        let mut reloaded = Session::empty();
        assert!(
            reloaded.load_bytes(&saved).is_ok(),
            "resave of a strict-loaded document failed to load"
        );
        assert!(
            reloaded.doc.content_hash() == strict.doc.content_hash(),
            "round-trip content hash mismatch"
        );
        assert!(
            reloaded.save_bytes() == saved,
            "resave is not byte-deterministic"
        );
    }
});
