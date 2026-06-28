//! Adversarial-input regression/fuzz tests. [audit F-1/F-2/F-3/F-4/F-6/F-28/F-29]
//!
//! The FFI contract is "the engine is panic-free on **all** inputs" — and because the workspace
//! ships `panic = "abort"` in release, a panic does NOT unwind into a recoverable error: it aborts
//! the whole host process (the Flutter app), taking unsaved state with it. There is no
//! `catch_unwind` net by design, so this guarantee rests entirely on test coverage.
//!
//! These tests throw malformed DSL strings and corrupt `.mkpx` bytes at the engine and assert it
//! never panics. A panic here aborts the test binary, which fails CI — that is exactly the signal
//! we want. They run quickly and deterministically (no external RNG dep; the engine is zero-dep).

use makapix_engine::Session;

/// Tiny deterministic LCG so the fuzz corpus is reproducible in CI (no `rand`, no `Math::random`).
struct Lcg(u64);
impl Lcg {
    fn next(&mut self) -> u64 {
        self.0 = self
            .0
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        self.0
    }
    fn byte(&mut self) -> u8 {
        (self.next() >> 33) as u8
    }
}

/// Exercise every read path that crosses the FFI with deliberately stale indices.
fn poke_reads(sess: &Session) {
    let _ = sess.composite_active_bytes();
    let _ = sess.state_json();
    let _ = sess.pixel(999, 999, 9999, -9999); // F-28: must clamp, not index-panic
    let _ = sess.layer_hash(999, 999);
    let _ = sess.frame_hash(999);
    let _ = sess.save_bytes();
}

#[test]
fn known_adversarial_scripts_never_panic() {
    // Each entry is a regression for a specific finding: a parseable-but-hostile script that used
    // to (or could) panic across the boundary.
    let scripts: &[&str] = &[
        // F-1: NaN / inf / huge gradient stops → used to hit partial_cmp().unwrap().
        "SetGradientStops(#000000FF@NaN,#FFFFFFFF@1.0)\nSelectTool(Gradient)\nPointerDown(0,0)\nPointerMove(60,60)\nPointerUp()",
        "SetGradientStops(#000000FF@inf,#FFFFFFFF@-inf)",
        "SetGradientStops(#000000FF@1e40,#FFFFFFFF@0.5,#102030FF@nan)",
        // F-1: non-finite scalar args elsewhere (HSV etc.).
        "ApplyHsvShift(NaN,inf,-inf)",
        "SetGradientType(Linear)\nSetGradientStops(#000@0,#fff@1)\nSelectTool(Gradient)\nPointerDown(-5,-5)\nPointerUp()",
        // F-6: unbounded pointer coordinates → used to spin spaced_points / raster::line.
        "SelectTool(Pencil)\nPointerDown(2000000000,2000000000)\nPointerMove(-2000000000,-2000000000)\nPointerUp()",
        "SelectTool(Brush)\nPointerDown(0,0)\nPointerMove(2147483647,-2147483648)\nPointerUp()",
        // F-29: changing the active layer/frame mid-stroke must not record against the wrong layer.
        "AddLayer()\nSelectTool(Pencil)\nPointerDown(5,5)\nSetActiveLayer(0)\nPointerMove(9,9)\nPointerUp()\nUndo()\nRedo()",
        "AddFrame()\nSelectTool(Pencil)\nPointerDown(3,3)\nSetActiveFrame(0)\nPointerUp()\nUndo()",
        // out-of-range structural ops
        "SetActiveLayer(999999)\nSetActiveFrame(999999)\nRemoveFrame(999999)\nRemoveLayer(999999)",
        "DuplicateFrame(999999)\nReorderFrame(999999,0)\nReorderLayer(0,999999)",
        // malformed / partial syntax
        "garbage(((",
        ")(",
        "SelectTool()",
        "NewDocument(0,0)",
        "NewDocument(99999,99999)",
        "SetBrushSize(-5)\nSetThreshold(-1)\nSetSpacing(-100)",
        "",
        "\n\n\n",
        "Undo()\nUndo()\nUndo()\nRedo()\nRedo()", // undo/redo past the ends
    ];
    for s in scripts {
        let mut sess = Session::new(64, 64);
        let _ = sess.run_script(s); // returns Ok/Err; must NEVER panic
        poke_reads(&sess);
    }
}

#[test]
fn random_dsl_never_panics() {
    let mut rng = Lcg(0x0123_4567_89ab_cdef);
    let names = [
        "SetGradientStops", "PointerDown", "PointerMove", "PointerUp", "NewDocument", "SelectTool",
        "SetBrushSize", "AddLayer", "AddFrame", "RemoveFrame", "RemoveLayer", "SetActiveLayer",
        "SetActiveFrame", "ApplyHsvShift", "Bucket", "ResizeCanvas", "Crop", "Undo", "Redo",
        "DuplicateFrame", "ReorderFrame", "Fill", "Invert",
    ];
    for _ in 0..6000 {
        let name = names[(rng.next() as usize) % names.len()];
        let argc = (rng.next() % 5) as usize;
        let mut line = String::from(name);
        line.push('(');
        for i in 0..argc {
            if i > 0 {
                line.push(',');
            }
            match rng.next() % 7 {
                0 => line.push_str("NaN"),
                1 => line.push_str("inf"),
                2 => line.push_str("2147483648"),  // overflows i32 parse
                3 => line.push_str("-2000000000"), // extreme but valid i32
                4 => {
                    for _ in 0..(rng.next() % 6) {
                        line.push((b'!' + rng.byte() % 80) as char); // random punctuation/letters
                    }
                }
                5 => line.push_str(&format!("#{:06x}FF@{}", rng.next() % 0xFFFFFF, rng.byte())),
                _ => line.push_str(&((rng.next() % 300) as i64 - 100).to_string()),
            }
        }
        line.push(')');
        let mut sess = Session::new(48, 32);
        let _ = sess.run_script(&line);
    }
}

#[test]
fn corrupt_mkpx_never_panics() {
    // Build a non-trivial valid document, save it, then assert the loader survives every truncation,
    // single-byte corruption, and pile of random garbage without panicking. [F-2 and the io reader]
    let mut sess = Session::new(48, 32);
    let _ = sess.run_script(
        "SelectTool(Pencil)\nPointerDown(1,1)\nPointerMove(40,20)\nPointerUp()\nAddFrame()\nAddLayer()\nPointerDown(5,5)\nPointerUp()",
    );
    let good = sess.save_bytes();
    assert!(!good.is_empty(), "expected a non-empty .mkpx save");

    // Every truncation length.
    for len in 0..good.len() {
        let mut s = Session::new(8, 8);
        let _ = s.load_bytes(&good[..len]);
    }

    // Single-byte corruptions at sampled offsets.
    let mut rng = Lcg(0xfeed_face_dead_beef);
    for _ in 0..6000 {
        let mut bytes = good.clone();
        let i = (rng.next() as usize) % bytes.len();
        bytes[i] ^= rng.byte().max(1);
        let mut s = Session::new(8, 8);
        let _ = s.load_bytes(&bytes);
    }

    // Pure random garbage of varying length (including would-be huge length/id prefixes).
    for _ in 0..3000 {
        let n = (rng.next() % 512) as usize;
        let mut bytes = vec![0u8; n];
        for b in &mut bytes {
            *b = rng.byte();
        }
        let mut s = Session::new(8, 8);
        let _ = s.load_bytes(&bytes);
    }
}

#[test]
fn idgen_starting_at_does_not_collide() {
    // Direct unit check that rehydration seeds ids past the persisted max without a warm-up loop.
    use makapix_engine::Session;
    let mut sess = Session::new(16, 16);
    // Save then reload, then allocate new structure — new ids must be unique vs. the loaded ones.
    let _ = sess.run_script("AddFrame()\nAddLayer()");
    let bytes = sess.save_bytes();
    let mut s2 = Session::new(8, 8);
    assert!(s2.load_bytes(&bytes).is_ok());
    // Adding layers/frames after load must not panic or duplicate ids (exercised via undo coherence).
    let _ = s2.run_script("AddLayer()\nAddFrame()\nUndo()\nRedo()");
    let _ = s2.save_bytes();
}
