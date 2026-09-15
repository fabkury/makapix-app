//! The memoized layer content hash (ADR 0031, `RgbaBuffer::hash_memo`) must equal an uncached
//! recomputation after EVERY step of a random verb sequence — strokes, fills, structural
//! layer/frame ops, the frame-set batch verbs, canvas transforms, undo/redo, save→load, and
//! replay checkpoints. A stale memo would show a stale thumbnail; this is the fuzz-style guard.

use makapix_engine::io;
use makapix_engine::Session;

struct Lcg(u64);
impl Lcg {
    fn next(&mut self) -> u64 {
        self.0 = self.0.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        self.0 >> 33
    }
    fn below(&mut self, n: u64) -> u64 {
        self.next() % n
    }
}

fn assert_memo_fresh(s: &Session, step: usize, line: &str) {
    for (fi, f) in s.doc.frames.iter().enumerate() {
        for (li, l) in f.layers.iter().enumerate() {
            assert_eq!(
                l.pixels.content_hash(),
                l.pixels.content_hash_uncached(),
                "stale memo after step {} `{}` (frame {}, layer {})",
                step,
                line,
                fi,
                li
            );
        }
    }
}

fn random_line(rng: &mut Lcg) -> String {
    let n = rng.below(6) as usize;
    let set = match rng.below(4) {
        0 => "0".to_string(),
        1 => format!("0-{}", n),
        2 => format!("{} {}", n, n + 2),
        _ => format!("1-{} {}", n + 1, n + 3),
    };
    let flag = rng.below(2);
    match rng.below(46) {
        0..=2 => format!(
            "SelectTool(Pencil)\nSetBrushSize({})\nSetPrimaryColor(#{:06X}FF)\nStroke([({},{}),({},{})])",
            1 + rng.below(5),
            rng.below(0xFFFFFF),
            rng.below(40),
            rng.below(40),
            rng.below(40),
            rng.below(40)
        ),
        3..=4 => format!(
            "SelectTool(Brush)\nSetBrushSize({})\nPointerDown({},{})\nPointerMove({},{})\nPointerUp()",
            2 + rng.below(6),
            rng.below(40),
            rng.below(40),
            rng.below(40),
            rng.below(40)
        ),
        5 => format!("FillNoise({})", rng.below(1000)),
        6 => "AddLayer()".into(),
        7 => "AddFrame()".into(),
        8 => "DuplicateFrame(0)".into(),
        9 => "RemoveLayer(0)".into(),
        10 => "RemoveFrame(0)".into(),
        11 => "MergeDown(1)".into(),
        12..=13 => "Undo()".into(),
        14 => "Redo()".into(),
        15 => "FlipCanvasH()".into(),
        16 => "Rotate(1)".into(),
        17 => format!("SelectTool(Bucket)\nSetPrimaryColor(#{:06X}FF)\nTap({},{})", rng.below(0xFFFFFF), rng.below(40), rng.below(40)),
        18 => format!("RemoveFrames({})", set),
        19 => format!("DuplicateFrames({})", set),
        20 => format!("RepeatFramesAfter({})", set),
        21 => format!("InsertBlankFrames({}, {})", set, if flag == 0 { "before" } else { "after" }),
        22 => format!("ShiftFrames({}, {})", set, rng.below(7) as i64 - 3),
        23 => format!("ReverseFrames({})", set),
        24 => format!("SetFrameDurations({}, {})", set, 20 + rng.below(500)),
        25 => format!("ScaleFrameDurations({}, {})", set, 200 + rng.below(3000)),
        26 => format!("FlipFramesH({})", set),
        27 => format!("FlipFramesV({})", set),
        28 => format!("RotateFrames({}, {})", set, 1 + rng.below(3)),
        29 => format!("InvertFrames({})", set),
        30 => format!("CopyLayerToFrames({})", set),
        31 => format!("RemoveLayersNamed({}, Layer 1)", set),
        32 => format!("SetLayersVisibleNamed({}, {}, Layer 1)", set, flag),
        33 => format!("SetLayersLockedNamed({}, {}, Layer 1)", set, flag),
        // ADR 0033 layer-set batch verbs over the active frame's stack (the same small sets).
        34 => format!("RemoveLayers({})", set),
        35 => format!("DuplicateLayers({})", set),
        36 => format!("MergeLayers({})", set),
        37 => format!("ShiftLayers({}, {})", set, rng.below(5) as i64 - 2),
        38 => format!("ReverseLayers({})", set),
        39 => format!("InsertBlankLayers({}, {})", set, if flag == 0 { "below" } else { "above" }),
        40 => format!("SetLayersVisible({}, {})", set, flag),
        41 => format!("SetLayersOpacity({}, {})", set, rng.below(256)),
        42 => format!("FlipLayersH({})", set),
        43 => format!("RotateLayers({}, {})", set, 1 + rng.below(3)),
        44 => format!("InvertLayers({})", set),
        _ => format!("ClearLayers({})", set),
    }
}

#[test]
fn memoized_hash_never_lags_the_tiles() {
    let mut rng = Lcg(0x9E37_79B9_7F4A_7C15);
    let mut s = Session::new(40, 40);
    let mut checkpoints: Vec<u32> = Vec::new();
    for step in 0..900 {
        let line = random_line(&mut rng);
        s.run_script(&line).expect("every generated line parses");
        assert_memo_fresh(&s, step, &line);
        if step % 60 == 30 {
            if let Some(id) = s.take_checkpoint() {
                checkpoints.push(id);
            }
        }
        if step % 130 == 129 && !checkpoints.is_empty() {
            let id = checkpoints[rng.below(checkpoints.len() as u64) as usize];
            assert!(s.restore_checkpoint(id), "checkpoint {} restores", id);
            assert_memo_fresh(&s, step, "restore_checkpoint");
        }
        if step % 200 == 199 {
            let bytes = io::save_to_bytes(&s.doc);
            let loaded = io::load_from_bytes(&bytes).expect("round trip");
            for (fi, f) in loaded.frames.iter().enumerate() {
                for (li, l) in f.layers.iter().enumerate() {
                    assert_eq!(l.pixels.content_hash(), l.pixels.content_hash_uncached(), "loaded {} {}", fi, li);
                }
                assert_eq!(
                    f.content_hash(),
                    s.doc.frames[fi].content_hash(),
                    "a loaded frame hashes like the live one (frame {})",
                    fi
                );
            }
        }
    }
    // The document-level hash is built from the memoized layer hashes; a fresh walk agrees.
    let live = s.doc.content_hash();
    let reloaded = io::load_from_bytes(&io::save_to_bytes(&s.doc)).unwrap().content_hash();
    assert_eq!(live, reloaded);
}
