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

use libfuzzer_sys::fuzz_target;
use makapix_engine::Session;

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
