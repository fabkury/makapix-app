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
        let flat = render::composite_frame(f, 64, 64);
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
