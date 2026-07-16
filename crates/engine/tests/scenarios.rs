//! Scenario, property, and stress tests driven through the public DSL/Session API —
//! the same surface the Flutter shell uses (SPEC §22.3).

use makapix_engine::render;
use makapix_engine::util::SeededRng;
use makapix_engine::Rgba8;
use makapix_engine::Session;

fn run(src: &str) -> Session {
    let mut s = Session::empty();
    s.run_script(src).expect("script ok");
    s
}

#[test]
fn pencil_outline_shape_and_undo() {
    let s = run(
        r#"
        NewDocument(8,8)
        SelectTool(Pencil); SetPrimaryColor(#FF0000FF)
        Stroke([(1,1),(4,1),(4,4),(1,4),(1,1)])
    "#,
    );
    assert_eq!(s.pixel(0, 0, 1, 1), Rgba8::rgb(255, 0, 0));
    assert_eq!(s.pixel(0, 0, 4, 4), Rgba8::rgb(255, 0, 0));
    assert_eq!(s.pixel(0, 0, 2, 2), Rgba8::TRANSPARENT); // hollow interior
}

// A staircase drag (single-step moves) whose turns each produce a "corner double". Without
// pixel-perfect the corners (2,1) and (3,2) are painted; with it on they are dropped, leaving a
// clean 1px diagonal through (1,1),(2,2),(3,3).
const STAIRCASE: &str = "Stroke([(1,1),(2,1),(2,2),(3,2),(3,3)])";
const RED: Rgba8 = Rgba8 { r: 255, g: 0, b: 0, a: 255 };

#[test]
fn pencil_pixel_perfect_removes_corner() {
    let s = run(&format!(
        r#"
        NewDocument(8,8)
        SelectTool(Pencil); SetPrimaryColor(#FF0000FF); SetBrushSize(1); SetPixelPerfect(true)
        {STAIRCASE}
    "#
    ));
    // Kept diagonal.
    assert_eq!(s.pixel(0, 0, 1, 1), RED);
    assert_eq!(s.pixel(0, 0, 2, 2), RED);
    assert_eq!(s.pixel(0, 0, 3, 3), RED);
    // Corner doubles removed.
    assert_eq!(s.pixel(0, 0, 2, 1), Rgba8::TRANSPARENT);
    assert_eq!(s.pixel(0, 0, 3, 2), Rgba8::TRANSPARENT);
}

#[test]
fn pencil_pixel_perfect_off_keeps_corner() {
    let s = run(&format!(
        r#"
        NewDocument(8,8)
        SelectTool(Pencil); SetPrimaryColor(#FF0000FF); SetBrushSize(1); SetPixelPerfect(false)
        {STAIRCASE}
    "#
    ));
    // Every stepped pixel, corners included, is painted (today's behaviour — regression guard).
    assert_eq!(s.pixel(0, 0, 2, 1), RED);
    assert_eq!(s.pixel(0, 0, 3, 2), RED);
}

#[test]
fn pencil_pixel_perfect_restores_underlying() {
    // Pre-fill the corner pixel green, then draw the pixel-perfect staircase over it. The removed
    // corner must be restored to the underlying green, not punched out to transparent.
    let s = run(&format!(
        r#"
        NewDocument(8,8)
        SelectTool(Pencil); SetPrimaryColor(#00FF00FF); SetBrushSize(1); SetPixelPerfect(false)
        Tap(2,1)
        SetPrimaryColor(#FF0000FF); SetPixelPerfect(true)
        {STAIRCASE}
    "#
    ));
    assert_eq!(s.pixel(0, 0, 2, 1), Rgba8::rgb(0, 255, 0));
    assert_eq!(s.pixel(0, 0, 2, 2), RED); // rest of the stroke still drawn
}

#[test]
fn pencil_pixel_perfect_only_at_size_1() {
    // Above 1px the filter is a no-op: the corner is still painted.
    let s = run(&format!(
        r#"
        NewDocument(8,8)
        SelectTool(Pencil); SetPrimaryColor(#FF0000FF); SetBrushSize(2); SetPixelPerfect(true)
        {STAIRCASE}
    "#
    ));
    assert_eq!(s.pixel(0, 0, 2, 1), RED);
}

#[test]
fn pencil_pixel_perfect_undo_restores_blank() {
    // The whole pixel-perfect stroke is one undo record; undo returns the canvas to blank.
    let s = run(&format!(
        r#"
        NewDocument(8,8)
        SelectTool(Pencil); SetPrimaryColor(#FF0000FF); SetBrushSize(1); SetPixelPerfect(true)
        {STAIRCASE}
        Undo()
    "#
    ));
    for (x, y) in [(1, 1), (2, 2), (3, 3), (2, 1), (3, 2)] {
        assert_eq!(s.pixel(0, 0, x, y), Rgba8::TRANSPARENT, "({x},{y}) should be blank after undo");
    }
}

// The same staircase drawn with the precision pen (off-finger reticle, Hold on): entering Hold
// stamps + commits (1,1), then ONE drag segment steps the reticle through (2,1)→(2,2)→(3,2)→(3,3).
const PEN_STAIRCASE: &str = "SetCursor(1,1); CursorPenDown(); CursorStrokeBegin(); \
    MoveCursor(1,0); MoveCursor(0,1); MoveCursor(1,0); MoveCursor(0,1); CursorStrokeEnd(); CursorPenUp()";

#[test]
fn pencil_pixel_perfect_applies_to_precision_pen_line() {
    // Perfect + Precision together: the pen-held reticle path runs the same corner-double filter
    // as a finger stroke (it used to be ignored on the pen path).
    let s = run(&format!(
        r#"
        NewDocument(8,8)
        SelectTool(Pencil); SetPrimaryColor(#FF0000FF); SetBrushSize(1); SetPixelPerfect(true)
        {PEN_STAIRCASE}
    "#
    ));
    // Kept diagonal.
    assert_eq!(s.pixel(0, 0, 1, 1), RED);
    assert_eq!(s.pixel(0, 0, 2, 2), RED);
    assert_eq!(s.pixel(0, 0, 3, 3), RED);
    // Corner doubles removed.
    assert_eq!(s.pixel(0, 0, 2, 1), Rgba8::TRANSPARENT);
    assert_eq!(s.pixel(0, 0, 3, 2), Rgba8::TRANSPARENT);
}

#[test]
fn pencil_pixel_perfect_pen_line_restores_underlying_and_undo_splits_dab_and_drag() {
    // A removed corner restores the pre-line pixel (green); the Hold dab and the drag segment
    // are SEPARATE undo steps — undo mid-Hold reverts the last drag, not everything.
    let mut s = run(&format!(
        r#"
        NewDocument(8,8)
        SelectTool(Pencil); SetPrimaryColor(#00FF00FF); SetBrushSize(1); SetPixelPerfect(false)
        Tap(2,1)
        SetPrimaryColor(#FF0000FF); SetPixelPerfect(true)
        {PEN_STAIRCASE}
    "#
    ));
    assert_eq!(s.pixel(0, 0, 2, 1), Rgba8::rgb(0, 255, 0));
    assert_eq!(s.pixel(0, 0, 2, 2), RED); // rest of the line still drawn
    assert!(s.doc.undo()); // undo the drag segment: the Hold dab at (1,1) survives
    assert_eq!(s.pixel(0, 0, 2, 2), Rgba8::TRANSPARENT);
    assert_eq!(s.pixel(0, 0, 1, 1), RED);
    assert_eq!(s.pixel(0, 0, 2, 1), Rgba8::rgb(0, 255, 0)); // the earlier green dot is intact
    assert!(s.doc.undo()); // undo the Hold dab
    assert_eq!(s.pixel(0, 0, 1, 1), Rgba8::TRANSPARENT);
}

#[test]
fn undo_redo_is_identity_over_random_script() {
    // Property: after N random edits, undo all then redo all returns the exact document.
    let mut rng = SeededRng::new(123);
    let mut s = Session::new(24, 24);
    let colors = ["#FF0000FF", "#00FF00FF", "#0000FFFF", "#FFFFFFFF"];
    let mut hashes = vec![s.doc.content_hash()];
    for _ in 0..40 {
        let c = colors[rng.below(colors.len() as u32) as usize];
        let x = rng.below(24) as i32;
        let y = rng.below(24) as i32;
        s.run_script(&format!("SelectTool(Pencil); SetPrimaryColor({}); Tap({},{})", c, x, y))
            .unwrap();
        hashes.push(s.doc.content_hash());
    }
    let final_hash = s.doc.content_hash();
    // undo everything
    while s.doc.undo() {}
    assert_eq!(s.doc.content_hash(), hashes[0]);
    // redo everything
    while s.doc.redo() {}
    assert_eq!(s.doc.content_hash(), final_hash);
}

#[test]
fn save_load_roundtrip_many_frames() {
    let mut s = Session::new(64, 64);
    for i in 0..50 {
        s.run_script(&format!("SetPrimaryColor(#10{:02X}30FF); SelectTool(Bucket); Tap(1,1)", i % 256))
            .unwrap();
        s.add_frame();
    }
    let bytes = s.save_bytes();
    let mut s2 = Session::empty();
    s2.load_bytes(&bytes).unwrap();
    assert_eq!(s2.doc.content_hash(), s.doc.content_hash());
    assert_eq!(s2.doc.frames.len(), 51);
}

#[test]
fn selection_invert_twice_is_identity() {
    let mut s = Session::new(16, 16);
    s.run_script("SelectTool(SelectRect); Stroke([(2,2),(8,8)])").unwrap();
    let before = s.bounds_of_selection();
    s.invert_selection();
    s.invert_selection();
    assert_eq!(s.bounds_of_selection(), before);
}

#[test]
fn copy_paste_in_place_is_noop() {
    let mut s = Session::new(20, 20);
    s.run_script(
        r#"
        SelectTool(Pencil); SetPrimaryColor(#ABCDEFFF)
        Stroke([(3,3),(9,3),(9,9)])
        SelectAll(); Copy()
    "#,
    )
    .unwrap();
    let h = s.doc.content_hash();
    s.paste();
    assert_eq!(s.doc.content_hash(), h, "paste in place over identical pixels is a no-op");
}

#[test]
fn cross_frame_layer_duplicate() {
    let mut s = Session::new(16, 16);
    s.run_script(
        r#"
        SelectTool(Bucket); SetPrimaryColor(#225588FF); Tap(0,0)
        AddFrame(); AddFrame(); AddFrame()
        SetActiveFrame(0)
        DuplicateLayerToFrames(1, 2, 3)
    "#,
    )
    .unwrap();
    // frames 1..3 should each now have 2 layers, the second matching frame 0's content
    for f in 1..4 {
        assert_eq!(s.doc.frames[f].layers.len(), 2);
        assert_eq!(s.pixel(f, 1, 5, 5), Rgba8::rgb(0x22, 0x55, 0x88));
    }
}

#[test]
fn per_frame_undo_cap_compaction() {
    // Exceed 128 edits on one frame; undo stack for that frame must cap at 128.
    let mut s = Session::new(16, 16);
    for i in 0..200 {
        let x = i % 16;
        let y = (i / 16) % 16;
        s.run_script(&format!("SetPrimaryColor(#FFFFFFFF); Tap({},{})", x, y)).unwrap();
    }
    let fid = s.doc.active_frame().id;
    assert!(s.doc.history.frame_depth(fid) <= 128, "depth={}", s.doc.history.frame_depth(fid));
}

#[test]
fn stress_hundreds_of_frames_tens_of_layers_no_crash() {
    // SPEC §23: create a large animation, draw on it, composite — must not crash and must
    // stay within a sane memory bound thanks to sparse tiles + COW.
    let mut s = Session::new(64, 64);
    let frames = 300;
    let layers_per_frame = 12;
    for f in 0..frames {
        if f > 0 {
            s.add_frame();
        }
        for l in 0..layers_per_frame {
            if l > 0 {
                s.add_layer();
            }
            // a small stroke per layer (sparse — only a few tiles touched)
            let x = (f * 7 + l * 3) % 60;
            let y = (f * 5 + l * 2) % 60;
            s.settings.primary = Rgba8::rgb((f % 256) as u8, (l * 20) as u8, 128);
            s.tool = makapix_engine::tool::ToolKind::Pencil;
            s.settings.brush_size = 2;
            s.stroke_path(&[(x as i32, y as i32), (x as i32 + 4, y as i32 + 4)]);
        }
    }
    assert_eq!(s.doc.frames.len(), frames);
    assert_eq!(s.doc.active_frame().layers.len(), layers_per_frame);

    // composite every frame — must not panic
    let mut total = 0u64;
    for f in &s.doc.frames {
        let flat = render::composite_frame(f, s.doc.canvas_rect());
        total += flat.to_rgba_bytes().len() as u64;
    }
    assert!(total > 0);

    // memory must stay reasonable (sparse): far below the 16 GiB dense worst case.
    let mb = s.doc.memory_bytes() / (1024 * 1024);
    println!("stress: {} frames x {} layers, resident ~{} MiB", frames, layers_per_frame, mb);
    assert!(mb < 512, "resident {} MiB exceeded budget", mb);

    // round-trip the whole thing
    let bytes = s.save_bytes();
    let mut s2 = Session::empty();
    s2.load_bytes(&bytes).unwrap();
    assert_eq!(s2.doc.content_hash(), s.doc.content_hash());
    println!("stress: .mkpx size {} KiB", bytes.len() / 1024);
}

#[test]
fn tiny_canvases_draw_resize_crop_roundtrip() {
    // The canvas minimum is 1×1: every 1..8 size must create, draw, composite, and round-trip.
    for (w, h) in [(1u16, 1u16), (1, 7), (5, 1), (3, 3), (2, 6)] {
        let s = run(&format!(
            "NewDocument({w},{h})\nSelectTool(Pencil); SetPrimaryColor(#FF0000FF)\nTap(0,0)"
        ));
        assert_eq!(s.doc.size, makapix_engine::geom::Size::new(w, h));
        assert_eq!(s.pixel(0, 0, 0, 0), RED);
        let flat = render::composite_frame(s.doc.active_frame(), s.doc.canvas_rect());
        assert_eq!(flat.to_rgba_bytes().len(), w as usize * h as usize * 4);
        let bytes = s.save_bytes();
        let mut s2 = Session::empty();
        s2.load_bytes(&bytes).unwrap();
        assert_eq!(s2.doc.content_hash(), s.doc.content_hash());
    }

    // Resize below the old minimum, then back up: pixels shifted per anchor, no clamp to 8.
    let mut s = run("NewDocument(16,16)\nSelectTool(Pencil); SetPrimaryColor(#FF0000FF)\nTap(0,0)");
    s.resize_canvas(1, 1, 0, 0);
    assert_eq!(s.doc.size, makapix_engine::geom::Size::new(1, 1));
    assert_eq!(s.pixel(0, 0, 0, 0), RED);
    s.resize_canvas(4, 4, 0, 0);
    assert_eq!(s.pixel(0, 0, 0, 0), RED);

    // NewDocument(0,0) clamps up to the 1×1 minimum, not 8×8.
    let s = run("NewDocument(0,0)");
    assert_eq!(s.doc.size, makapix_engine::geom::Size::new(1, 1));
}

// ---- FillNoise + mem probe (memory stress enablers) ----

#[test]
fn fill_noise_is_deterministic_dense_and_roundtrips() {
    let a = run("NewDocument(64,64)\nFillNoise(42)");
    let b = run("NewDocument(64,64)\nFillNoise(42)");
    let c = run("NewDocument(64,64)\nFillNoise(43)");
    assert_eq!(a.doc.content_hash(), b.doc.content_hash(), "same seed => same content");
    assert_ne!(a.doc.content_hash(), c.doc.content_hash(), "different seed => different content");
    // Every canvas pixel non-transparent; the full canvas tile grid is materialized.
    for y in 0..64 {
        for x in 0..64 {
            assert_ne!(a.pixel(0, 0, x, y).a, 0, "({},{}) transparent", x, y);
        }
    }
    let r = makapix_engine::probe::mem_report(&a.doc, &[]);
    assert_eq!(r.doc_tiles, 4, "64x64 canvas = 2x2 tiles, all present");
    // Incompressible content must still round-trip .mkpx byte-exactly.
    let bytes = a.save_bytes();
    let mut back = Session::empty();
    back.load_bytes(&bytes).expect("load noise .mkpx");
    assert_eq!(back.doc.content_hash(), a.doc.content_hash(), "noise roundtrip");
}

#[test]
fn mem_report_sees_cow_sharing_and_history_retention() {
    let s = run("NewDocument(64,64)\nFillNoise(7)\nDuplicateFrame(0)");
    let r = makapix_engine::probe::mem_report(&s.doc, &[]);
    assert_eq!(r.doc_tiles, 8, "two frames x 4 present tiles (with multiplicity)");
    assert_eq!(r.doc_unique_tiles, 4, "duplicate frame shares tiles via Arc");
    assert_eq!(r.history_tiles, 0, "history references the same live tiles");

    // Diverge one tile on the duplicate: unique count grows by exactly one.
    let mut s = s;
    s.run_script("SetActiveFrame(1)\nSelectTool(Pencil)\nSetPrimaryColor(#00FF00FF)\nStroke([(1,1),(1,1)])")
        .unwrap();
    let r = makapix_engine::probe::mem_report(&s.doc, &[]);
    assert_eq!(r.doc_tiles, 8);
    assert_eq!(r.doc_unique_tiles, 5, "one tile COW-diverged");

    // Undo the noise fill entirely: the live doc empties but history retains the noise tiles.
    let s2 = run("NewDocument(64,64)\nFillNoise(9)\nUndo()");
    let r2 = makapix_engine::probe::mem_report(&s2.doc, &[]);
    assert_eq!(r2.doc_tiles, 0, "undo restored the empty layer");
    assert_eq!(r2.history_tiles, 4, "the noise generation is retained by the redo side");
    assert!(r2.total_bytes() >= 4 * 4096);
}

#[test]
fn history_table_retention_is_linear_not_quadratic() {
    // Before the Arc'd tile table (memlab M1), DocStructure records cloned every layer's
    // tile-slot table: building F frames retained 4608·F² bytes of tables (18.9 MB at F=64).
    // With COW tables the snapshots share the live tables until they diverge, so retention is
    // O(F) — a few table generations per frame, not F copies of the whole vector.
    let mut s = Session::empty();
    let mut script = String::from("NewDocument(256,256)\n");
    let frames = 64;
    for f in 0..frames {
        if f > 0 {
            script.push_str("AddFrame()\n");
        }
        script.push_str(&format!("FillNoise({})\n", f + 1));
    }
    s.run_script(&script).unwrap();
    let r = makapix_engine::probe::mem_report(&s.doc, &[]);
    let per_table = 576 * 8; // 24×24 storage slots × pointer size at 256×256
    let quadratic = per_table * frames * frames; // what the old code retained
    assert!(
        r.history_table_bytes <= 6 * frames * per_table,
        "history tables {} bytes — expected O(frames), old quadratic was {}",
        r.history_table_bytes,
        quadratic
    );
    // Sanity: the undo timeline still works end-to-end after the change (each frame produced
    // two records: AddFrame + FillNoise).
    for _ in 0..2 * frames {
        s.run_script("Undo()").unwrap();
    }
    assert_eq!(s.doc.frames.len(), 1, "undo chain rewinds the AddFrames");
}

#[test]
fn history_byte_budget_evicts_oldest_but_keeps_floor() {
    // 20 full-canvas noise repaints at 256x256: each Pixels record weighs ~528 KB (64 tiles x 2
    // sides). A 4 MiB budget holds ~7 of those, but the MIN_RECORDS floor (8) wins.
    let mut s = run("NewDocument(256,256)");
    s.doc.history.set_byte_budget(Some(4 * 1024 * 1024));
    for i in 0..20 {
        s.run_script(&format!("FillNoise({})", i + 1)).unwrap();
    }
    assert_eq!(s.doc.history.undo.len(), makapix_engine::history::MIN_RECORDS);
    // The surviving records still undo cleanly.
    for _ in 0..makapix_engine::history::MIN_RECORDS {
        assert!(s.doc.undo(), "records within the floor must undo");
    }
    assert!(!s.doc.undo(), "evicted records are gone");

    // A generous budget retains everything (count caps permitting).
    let mut s2 = run("NewDocument(256,256)");
    s2.doc.history.set_byte_budget(Some(64 * 1024 * 1024));
    for i in 0..20 {
        s2.run_script(&format!("FillNoise({})", i + 1)).unwrap();
    }
    assert_eq!(s2.doc.history.undo.len(), 20);
    assert!(s2.doc.history.retained_bytes() > 10 * 1024 * 1024);
}

// ---- document memory budget (SPEC §8.2b, enforcement M3) ----

#[test]
fn mem_budget_rolls_back_pixel_edits_past_hard() {
    // 4 MiB hard budget = 16 full-noise 256x256 layers. Growing layer by layer, the fills that
    // would cross the cap are rolled back (layer stays empty), the session never exceeds it,
    // and refusals are counted for the shell.
    let mut s = run("NewDocument(256,256)\nSetMemBudget(3145728,4194304)\nFillNoise(1)");
    for i in 0..24 {
        s.run_script(&format!("AddLayer()\nFillNoise({})", i + 2)).unwrap();
    }
    let unique = s.doc.unique_payload_bytes();
    assert!(unique <= 4 * 1024 * 1024, "unique payload {} exceeds the hard budget", unique);
    let (refusals, last) = s.mem_refusal_state();
    assert!(refusals >= 9, "expected ~9 refused fills, got {}", refusals);
    assert!(last.unwrap().contains("memory budget"));
    assert!(s.state_json().contains("\"mem_soft_exceeded\":true"));
    // The layers refused their fill are still present (AddLayer is free) but empty.
    let last_layer = s.doc.frames[0].layers.last().unwrap();
    assert_eq!(last_layer.pixels.present_tiles(), 0);
    // Undo still rewinds the accepted fills cleanly.
    while s.doc.undo() {}
    assert_eq!(s.doc.unique_payload_bytes(), 0);
}

#[test]
fn mem_budget_rolls_back_structural_edits_past_hard() {
    // Two noise layers, then an artificially tiny budget: MergeDown would materialize a fresh
    // merged buffer over the cap, so the whole frame mutation is rolled back.
    let mut s = run("NewDocument(256,256)\nFillNoise(1)\nAddLayer()\nFillNoise(2)");
    assert_eq!(s.doc.frames[0].layers.len(), 2);
    s.run_script("SetMemBudget(65536,131072)").unwrap();
    s.run_script("MergeDown(1)").unwrap();
    assert_eq!(s.doc.frames[0].layers.len(), 2, "merge must be rolled back over budget");
    let (refusals, _) = s.mem_refusal_state();
    assert!(refusals >= 1);
}

#[test]
fn mem_budget_refuses_over_budget_files_at_load() {
    // A 64-tile noise doc saves fine, then a session with a tiny budget refuses to load it
    // before materializing anything; the default budget loads it.
    let s = run("NewDocument(256,256)\nFillNoise(7)");
    let bytes = s.save_bytes();
    let mut tiny = Session::empty();
    tiny.run_script("SetMemBudget(65536,65536)").unwrap();
    assert!(tiny.load_bytes(&bytes).is_err(), "16 KiB budget must refuse a 256 KiB file");
    let mut normal = Session::empty();
    normal.load_bytes(&bytes).unwrap();
    assert_eq!(normal.doc.content_hash(), s.doc.content_hash());
}
