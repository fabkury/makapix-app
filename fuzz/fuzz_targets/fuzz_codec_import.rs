#![no_main]
//! Fuzz the import path we own (ANALYSIS.md §2.4/§3.2 item 4).
//!
//! The `image` decoders underneath are fuzzed heavily upstream by OSS-Fuzz, so finding
//! their bugs is a bonus, not the goal. What is OURS, and what this target aims at:
//!   * the decode→import wrapper: frame extraction, scale/anchor placement, the
//!     canvas-vs-source geometry arithmetic in `import::place_frame`;
//!   * the budget gate — `import_decoded` runs through `edit_doc`, so an oversized
//!     import must roll back wholesale and register a refusal rather than leaving the
//!     session over budget (the Android ~1 GiB allocator wall makes that a crash vector);
//!   * the invariant that whatever an import leaves behind is still a coherent document:
//!     it saves, reloads, and round-trips.
//!
//! Inputs are (arbitrary bytes → decode) plus a structured import configuration, so the
//! mutator explores the config space (canvas size, scale mode, anchor, as-layer, start
//! frame) rather than only the byte space.

use arbitrary::Arbitrary;
use libfuzzer_sys::fuzz_target;
use makapix_engine::geom::IRect;
use makapix_engine::import::{Anchor, ImportConfig, ScaleMode};
use makapix_engine::Session;

#[derive(Arbitrary, Debug)]
struct Input<'a> {
    canvas_w: u8,
    canvas_h: u8,
    mode: u8,
    anchor: bool,
    as_layer: bool,
    start: u8,
    /// Optional explicit source-crop region (the interactive crop widget's path, which
    /// overrides `mode` and is placed 1:1 centered) — our own geometry arithmetic, so
    /// worth steering into rather than leaving to chance.
    crop: Option<(i16, i16, i16, i16)>,
    /// Raw image bytes handed to `codec::decode`.
    bytes: &'a [u8],
}

fuzz_target!(|input: Input| {
    let frames = match makapix_codec::decode(input.bytes) {
        Ok(f) => f,
        Err(_) => return, // a rejected file is the expected outcome for most inputs
    };
    // Guard the fuzzer against its own success: a legitimately huge decode makes each
    // execution slow without testing more of our wrapper.
    if frames.is_empty() || frames.len() > 64 {
        return;
    }
    if frames.iter().any(|f| (f.w as u64) * (f.h as u64) > 4_000_000) {
        return;
    }

    let mut sess = Session::new((input.canvas_w as u16 % 256) + 1, (input.canvas_h as u16 % 256) + 1);
    let cfg = ImportConfig {
        mode: match input.mode % 3 {
            0 => ScaleMode::Stretch,
            1 => ScaleMode::Fit,
            _ => ScaleMode::Crop,
        },
        anchor: if input.anchor { Anchor::Center } else { Anchor::TopLeft },
        as_layer: input.as_layer,
        start_frame: input.start as usize,
        crop_rect: input
            .crop
            .map(|(x, y, w, h)| IRect::new(x as i32, y as i32, w.unsigned_abs() as u32, h.unsigned_abs() as u32)),
    };

    let committed = sess.import_decoded(&frames, cfg);

    // Whatever happened — commit, empty-input refusal, or budget rollback — the session
    // must still be a coherent document. These are the FFI read paths a shell would call
    // right after an import.
    let _ = sess.composite_active_bytes();
    let _ = sess.state_json();
    let _ = sess.mem_json();
    let _ = sess.frame_hash(0);

    // Budget invariant: a refusal means the import rolled back, and the engine must not
    // be sitting over the hard budget afterwards (that is what the rollback is for).
    let (refusals, _last) = sess.mem_refusal_state();
    if !committed && refusals == 0 {
        // Not committed and not refused ⇒ the input was empty, which we filtered above.
        panic!("import neither committed nor registered a refusal for {} frame(s)", frames.len());
    }

    // A document produced by an import must save, reload, and round-trip — the same
    // contract the loader target enforces, reached through a different door.
    let saved = sess.save_bytes();
    let mut re = Session::empty();
    match re.load_bytes(&saved) {
        Ok(()) => {
            assert!(
                re.doc.content_hash() == sess.doc.content_hash(),
                "round-trip hash mismatch after import ({} frames, committed={committed})",
                frames.len()
            );
            assert!(
                re.save_bytes() == saved,
                "resave not byte-deterministic after import ({} frames)",
                frames.len()
            );
        }
        Err(e) => {
            // The engine refuses to load documents past its own budget; that is legal
            // ONLY if the import itself was refused, never for a committed import.
            assert!(
                !committed,
                "a committed import produced a document its own loader rejects: {e:?}"
            );
        }
    }
});
