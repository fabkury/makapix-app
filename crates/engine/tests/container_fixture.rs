//! Pins the `.mkpx` v10 container bytes across refactors of the shared container machinery
//! (`io::container`, extracted 2026-07-30): a committed fixture must load and re-save to the
//! exact same bytes forever, and the loader's rejection matrix must keep its exact error
//! variants. If `fixture_bytes_are_stable` ever fails, the container format changed — that is
//! a format-versioning event, never a refactor detail.

use makapix_engine::io::{self, IoError};

const FIXTURE: &[u8] = include_bytes!("fixtures/gen_32x32_3f2l_seed5.mkpx");

#[test]
fn fixture_bytes_are_stable() {
    let doc = io::load_from_bytes(FIXTURE).expect("fixture loads");
    assert_eq!(doc.size.w, 32);
    assert_eq!(doc.size.h, 32);
    assert_eq!(doc.frames.len(), 3);
    assert_eq!(doc.frames[0].layers.len(), 2);
    let resaved = io::save_to_bytes(&doc);
    assert_eq!(resaved, FIXTURE, "save(load(fixture)) must be byte-identical to the fixture");
}

#[test]
fn rejects_bad_magic() {
    let mut b = FIXTURE.to_vec();
    b[1] ^= 0xFF;
    assert!(matches!(io::load_from_bytes(&b), Err(IoError::BadMagic)));
}

#[test]
fn rejects_flipped_body_byte_via_crc() {
    let mut b = FIXTURE.to_vec();
    b[40] ^= 0xFF; // inside HEAD
    assert!(matches!(io::load_from_bytes(&b), Err(IoError::Corrupt("crc mismatch"))));
}

#[test]
fn rejects_truncation() {
    // Any truncation breaks the INTG trailer before the body is ever parsed.
    for cut in [1usize, 13, 100] {
        let b = &FIXTURE[..FIXTURE.len() - cut];
        assert!(io::load_from_bytes(b).is_err(), "truncated by {} must fail", cut);
    }
    assert!(matches!(io::load_from_bytes(&FIXTURE[..4]), Err(IoError::Incomplete)));
}

/// Rebuild the fixture with one chunk's header tampered, fixing up the INTG CRC so the
/// tampering reaches the chunk walk (not the CRC gate).
fn retail(body: Vec<u8>) -> Vec<u8> {
    let mut w = body;
    let crc = {
        // CRC-32C over the body, matching container::finish_intg.
        // (Recomputed here through the public save path: crc32c is not re-exported, so this
        // test re-derives it via a tiny local table — kept in sync by the fixture test above.)
        const fn table() -> [u32; 256] {
            let mut t = [0u32; 256];
            let mut i = 0usize;
            while i < 256 {
                let mut crc = i as u32;
                let mut j = 0;
                while j < 8 {
                    crc = if crc & 1 != 0 { (crc >> 1) ^ 0x82F6_3B78 } else { crc >> 1 };
                    j += 1;
                }
                t[i] = crc;
                i += 1;
            }
            t
        }
        static T: [u32; 256] = table();
        let mut crc = 0xFFFF_FFFFu32;
        for &b in &w {
            crc = (crc >> 8) ^ T[((crc ^ b as u32) & 0xFF) as usize];
        }
        crc ^ 0xFFFF_FFFF
    };
    w.extend_from_slice(b"INTG");
    w.push(1);
    w.extend_from_slice(&4u32.to_le_bytes());
    w.extend_from_slice(&crc.to_le_bytes());
    w
}

#[test]
fn rejects_unknown_critical_chunk() {
    // Body without the INTG trailer, plus a crafted unknown critical chunk, re-trailed.
    let mut body = FIXTURE[..FIXTURE.len() - 13].to_vec();
    body.extend_from_slice(b"XXXX");
    body.push(1); // critical
    body.extend_from_slice(&0u32.to_le_bytes());
    let b = retail(body);
    assert!(matches!(io::load_from_bytes(&b), Err(IoError::UnsupportedChunk(_))));
}

#[test]
fn skips_unknown_ancillary_chunk() {
    let mut body = FIXTURE[..FIXTURE.len() - 13].to_vec();
    body.extend_from_slice(b"xxxx");
    body.push(0); // ancillary
    body.extend_from_slice(&2u32.to_le_bytes());
    body.extend_from_slice(&[1, 2]);
    let b = retail(body);
    assert!(io::load_from_bytes(&b).is_ok(), "unknown ancillary chunks are skipped");
}

#[test]
fn rejects_duplicate_chunk() {
    // Duplicate the HEAD chunk at the end of the body.
    let head_len =
        u32::from_le_bytes([FIXTURE[13], FIXTURE[14], FIXTURE[15], FIXTURE[16]]) as usize;
    let head_chunk = &FIXTURE[8..8 + 9 + head_len];
    let mut body = FIXTURE[..FIXTURE.len() - 13].to_vec();
    body.extend_from_slice(head_chunk);
    let b = retail(body);
    assert!(matches!(io::load_from_bytes(&b), Err(IoError::Corrupt("duplicate chunk"))));
}

#[test]
fn rejects_head_not_first() {
    // Swap the signature-adjacent HEAD chunk for an ancillary decoy at position 0.
    let mut body = Vec::new();
    body.extend_from_slice(&FIXTURE[..8]);
    body.extend_from_slice(b"xxxx");
    body.push(0);
    body.extend_from_slice(&0u32.to_le_bytes());
    body.extend_from_slice(&FIXTURE[8..FIXTURE.len() - 13]);
    let b = retail(body);
    assert!(matches!(io::load_from_bytes(&b), Err(IoError::Corrupt("HEAD not first"))));
}

#[test]
fn over_budget_dictionary_is_refused_before_materializing() {
    // The fixture's own dictionary is tiny; loading it under an absurdly small hard budget
    // must refuse with the budget error (the pre-materialization gate).
    assert!(matches!(
        io::load_from_bytes_budgeted(FIXTURE, 0),
        Err(IoError::TooLarge("memory budget"))
    ));
}
