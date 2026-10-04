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
//!   4. A tolerant-loadable document must save to a file that loads strictly, unchanged.
//!   5. The META reader survives any bytes, and what it reads splices back and reads
//!      back unchanged without altering the document (fuzzing-review W4).
//! The compact envelope has its own target, `fuzz_mkpx_open`.
//! Run with `-rss_limit_mb=1024 -malloc_limit_mb=512` (tools/fuzz/run_fuzz.sh does) so the
//! Android ~1 GiB allocator wall acts as an oracle on the workstation: an allocation bomb
//! that would SIGABRT a phone shows up here as a memory-limit finding.

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

/// Exercise the read paths that cross the FFI, with deliberately stale indices and with
/// valid ones (the idea of `crates/engine/tests/fuzz_inputs.rs::poke_reads`, wider): the
/// shell calls all of these right after an open, on whatever the load left behind.
fn poke_reads(sess: &Session) {
    let _ = sess.composite_active_bytes();
    let _ = sess.state_json();
    let _ = sess.mem_json();
    let _ = sess.pixel(999, 999, 9999, -9999);
    let _ = sess.save_estimate_bytes();
    let _ = sess.content_bounds();
    let _ = sess.bounds_of_selection();
    let _ = sess.outline_mask();
    let _ = sess.used_colors(64);
    let _ = sess.used_colors_sorted_json();
    let _ = sess.display_bytes(true, true, true);
    for (f, l) in [(0usize, 0usize), (999, 999)] {
        let _ = sess.composite_frame_bytes(f);
        let _ = sess.composite_frame_storage_bytes(f);
        let _ = sess.frame_thumb_bytes(f, 16, 16);
        let _ = sess.layer_thumb_bytes(f, l, 16, 16);
        let _ = sess.layer_thumb_hash(f, l);
        let _ = sess.layer_rgba_bytes(f, l);
        let _ = sess.layer_hash(f, l);
        let _ = sess.frame_hash(f);
    }
}

/// `io.rs::MAX_STR`: the longest string `splice_meta_str` accepts.
const MAX_STR: usize = 4096;

/// The META reader and splicer (`io::read_meta_str` / `io::splice_meta_str`): the Club
/// edit/remix path reads provenance out of other users' files with the first, and publish
/// writes it with the second. The reader must survive any bytes; whatever it returns must
/// splice back into the same file and read back unchanged, without touching the document.
fn poke_meta(data: &[u8], strict: Option<&Session>) {
    let Ok(entries) = makapix_engine::io::read_meta_str(data) else { return };
    // The reader decodes lossily, so invalid UTF-8 can grow a string past the splicer's
    // cap; the splicer legitimately refuses those.
    if entries.iter().any(|(k, v)| k.len() > MAX_STR || v.len() > MAX_STR) {
        return;
    }
    let refs: Vec<(&str, &str)> = entries.iter().map(|(k, v)| (k.as_str(), v.as_str())).collect();
    let spliced = makapix_engine::io::splice_meta_str(data, &refs)
        .expect("splice_meta_str refused entries read_meta_str returned from the same file");
    let reread =
        makapix_engine::io::read_meta_str(&spliced).expect("a spliced file failed read_meta_str");
    assert!(reread == entries, "META entries changed across splice + read");
    if let Some(strict) = strict {
        let mut re = Session::empty();
        assert!(re.load_bytes(&spliced).is_ok(), "a META splice broke a strict-loadable file");
        assert!(
            re.doc.content_hash() == strict.doc.content_hash(),
            "a META splice changed the document"
        );
    }
    let _ = makapix_engine::io::splice_meta_str(data, &[]); // strip
}

fuzz_target!(|data: &[u8]| {
    // Strict path (the load the CLI and tests use).
    let mut strict = Session::new(8, 8);
    let strict_ok = strict.load_bytes(data).is_ok();
    poke_reads(&strict);
    poke_meta(data, strict_ok.then_some(&strict));

    // Tolerant path (the app's open path — repairs what it can, warns). The app then
    // autosaves what it opened: that save must be a strictly valid file holding the same
    // document, or the repair loses the drawing on the next open.
    let mut tolerant = Session::new(8, 8);
    let tolerant_ok = tolerant.load_bytes_tolerant(data).is_ok();
    poke_reads(&tolerant);
    let resaved = tolerant.save_bytes();
    if tolerant_ok {
        let mut re = Session::empty();
        assert!(
            re.load_bytes(&resaved).is_ok(),
            "the save of a tolerant-loaded document fails a strict load"
        );
        assert!(
            re.doc.content_hash() == tolerant.doc.content_hash(),
            "tolerant load → save → strict load changed the document"
        );
    }

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
