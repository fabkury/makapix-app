//! Replace color and Outline — the two 2026-09-04 riders of the Symmetry release
//! (`docs/symmetry/DESIGN.md`), driven through the DSL as the shell drives them.

use makapix_engine::{Rgba8, Session};

fn run(src: &str) -> Session {
    let mut s = Session::empty();
    s.run_script(src).expect("script ok");
    s
}

const RED: Rgba8 = Rgba8::new(255, 0, 0, 255);
const GREEN: Rgba8 = Rgba8::new(0, 255, 0, 255);
const BLUE: Rgba8 = Rgba8::new(0, 0, 255, 255);
const BLACK: Rgba8 = Rgba8::new(0, 0, 0, 255);
const CLEAR: Rgba8 = Rgba8::TRANSPARENT;

fn count(s: &Session, f: usize, l: usize, w: i32, h: i32, c: Rgba8) -> usize {
    let mut n = 0;
    for y in 0..h {
        for x in 0..w {
            if s.pixel(f, l, x, y) == c {
                n += 1;
            }
        }
    }
    n
}

/// A 16×8 canvas: a red 4-wide band at x 2..5, a green pixel at (8,1), and a blue pixel at (12,6).
const SCENE: &str = "NewDocument(16,8)\nSelectTool(Pencil); SetPrimaryColor(#FF0000FF)\nStroke([(2,0),(2,7)]); Stroke([(3,0),(3,7)]); Stroke([(4,0),(4,7)]); Stroke([(5,0),(5,7)])\nSetPrimaryColor(#00FF00FF); Tap(8,1)\nSetPrimaryColor(#0000FFFF); Tap(12,6)";

#[test]
fn replace_color_layer_scope_recolors_exact_matches_in_one_undo_step() {
    let mut s = run(&format!("{SCENE}\nReplaceColor(#FF0000FF,#000000FF,layer,0)"));
    assert_eq!(count(&s, 0, 0, 16, 8, BLACK), 32, "the whole band");
    assert_eq!(count(&s, 0, 0, 16, 8, RED), 0);
    assert_eq!(s.pixel(0, 0, 8, 1), GREEN, "other colors untouched");
    assert_eq!(s.repeat_label(), Some("Replace color"));
    s.run_script("Undo()").unwrap();
    assert_eq!(count(&s, 0, 0, 16, 8, RED), 32, "one Undo reverts it all");
}

#[test]
fn replace_color_tolerance_uses_the_bucket_metric() {
    // Near-red (250,10,0) sits within delta 10 of red; the green is far away.
    let s = run(&format!(
        "{SCENE}\nSelectTool(Pencil); SetPrimaryColor(#FA0A00FF); Tap(10,3)\nReplaceColor(#FF0000FF,#000000FF,layer,10)"
    ));
    assert_eq!(s.pixel(0, 0, 10, 3), BLACK, "within tolerance");
    assert_eq!(s.pixel(0, 0, 8, 1), GREEN);
    let exact = run(&format!("{SCENE}\nSelectTool(Pencil); SetPrimaryColor(#FA0A00FF); Tap(10,3)\nReplaceColor(#FF0000FF,#000000FF,layer,0)"));
    assert_eq!(exact.pixel(0, 0, 10, 3), Rgba8::new(250, 10, 0, 255), "tolerance 0 is exact");
}

#[test]
fn replace_color_allows_transparent_on_both_sides() {
    // from-transparent fills the empty pixels; to-transparent erases a color.
    let fill = run(&format!("{SCENE}\nReplaceColor(#00000000,#0000FFFF,layer,0)"));
    assert_eq!(fill.pixel(0, 0, 0, 0), BLUE, "empty pixels filled");
    assert_eq!(fill.pixel(0, 0, 2, 0), RED, "content untouched");
    let erase = run(&format!("{SCENE}\nReplaceColor(#FF0000FF,#00000000,layer,0)"));
    assert_eq!(count(&erase, 0, 0, 16, 8, RED), 0);
    assert_eq!(erase.pixel(0, 0, 2, 0), CLEAR, "the band is erased");
}

#[test]
fn replace_color_clips_to_the_selection() {
    let s = run(&format!("{SCENE}\nSelectTool(SelectRect)\nStroke([(0,0),(15,3)])\nReplaceColor(#FF0000FF,#000000FF,layer,0)"));
    assert_eq!(s.pixel(0, 0, 2, 1), BLACK, "inside the marquee");
    assert_eq!(s.pixel(0, 0, 2, 6), RED, "outside the marquee");
}

#[test]
fn replace_color_frame_and_all_scopes_touch_editable_layers_only_in_one_step() {
    // Two frames × two layers, red on every layer; layer 1 of frame 0 is locked, layer 1 of
    // frame 1 is hidden. `frame` recolors frame 0's editable layers; `all` recolors every
    // editable layer of both frames. Each is one undo step.
    let base = "NewDocument(8,8)\nSelectTool(Pencil); SetPrimaryColor(#FF0000FF)\nTap(1,1)\nAddLayer(); Tap(2,2)\nDuplicateFrame(0); SetActiveFrame(1)\nSetActiveFrame(0); SetLayerLocked(1,true)\nSetActiveFrame(1); SetLayerVisible(1,false)\nSetActiveFrame(0); SetActiveLayer(0)";
    let mut f = run(&format!("{base}\nReplaceColor(#FF0000FF,#00FF00FF,frame,0)"));
    assert_eq!(f.pixel(0, 0, 1, 1), GREEN, "frame 0 layer 0 recolored");
    assert_eq!(f.pixel(0, 1, 2, 2), RED, "frame 0 layer 1 is locked: untouched");
    assert_eq!(f.pixel(1, 0, 1, 1), RED, "frame 1 untouched by the frame scope");
    f.run_script("Undo()").unwrap();
    assert_eq!(f.pixel(0, 0, 1, 1), RED, "one Undo");
    let mut a = run(&format!("{base}\nReplaceColor(#FF0000FF,#00FF00FF,all,0)"));
    assert_eq!(a.pixel(0, 0, 1, 1), GREEN);
    assert_eq!(a.pixel(0, 1, 2, 2), RED, "locked stays");
    assert_eq!(a.pixel(1, 0, 1, 1), GREEN, "frame 1 layer 0 recolored");
    assert_eq!(a.pixel(1, 1, 2, 2), RED, "hidden stays (the engine's editability rule)");
    a.run_script("Undo()").unwrap();
    assert_eq!(a.pixel(1, 0, 1, 1), RED, "all frames revert in one Undo");
    assert_eq!(a.pixel(0, 0, 1, 1), RED);
}

#[test]
fn replace_color_with_no_match_records_nothing_and_repeat_reads_live_targets() {
    let mut s = run(&format!("{SCENE}\nReplaceColor(#123456FF,#000000FF,all,0)"));
    let steps_before = s.doc.can_undo();
    assert!(steps_before, "the scene itself is undoable");
    s.run_script("Undo()").unwrap(); // must undo a SCENE stroke, not an empty replace
    assert_eq!(s.pixel(0, 0, 12, 6), CLEAR, "the blue tap was the last real step");
    // Repeat: the frozen from/to/scope on the live layer.
    let mut r = run(&format!("{SCENE}\nReplaceColor(#FF0000FF,#000000FF,layer,0)\nUndo()\nAddLayer()\nSelectTool(Pencil); SetPrimaryColor(#FF0000FF); Tap(0,0)\nRepeat()"));
    assert_eq!(r.pixel(0, 1, 0, 0), BLACK, "Repeat recolored the new layer");
    assert_eq!(r.pixel(0, 0, 2, 0), RED, "the old layer was not the target");
    r.run_script("Undo()").unwrap();
    assert_eq!(r.pixel(0, 1, 0, 0), RED);
}

#[test]
fn replace_color_rejects_garbage() {
    let mut s = Session::empty();
    assert!(s.run_script("ReplaceColor(#FF0000FF,#000000FF,everywhere,0)").is_err());
    assert!(s.run_script("ReplaceColor(nope,#000000FF,layer,0)").is_err());
}

/// A 3×3 red square at (3..5, 3..5) on a 12×12 canvas.
const SQUARE: &str = "NewDocument(12,12)\nSelectTool(Rectangle); SetPrimaryColor(#FF0000FF); SetShapeFill(true)\nShapeSet(3,3,5,5); ShapeCommit()";

#[test]
fn outline_outside_round_draws_the_four_connected_ring() {
    let mut s = run(&format!("{SQUARE}\nOutline(#000000FF,outside,round,1)"));
    // The 4-connected dilation of a 3×3 square minus itself: the four 3-long edges = 12 pixels,
    // no corners.
    assert_eq!(count(&s, 0, 0, 12, 12, BLACK), 12);
    assert_eq!(s.pixel(0, 0, 2, 3), BLACK);
    assert_eq!(s.pixel(0, 0, 2, 2), CLEAR, "round corners: the diagonal is empty");
    assert_eq!(count(&s, 0, 0, 12, 12, RED), 9, "content untouched");
    assert_eq!(s.repeat_label(), Some("Outline"));
    s.run_script("Undo()").unwrap();
    assert_eq!(count(&s, 0, 0, 12, 12, BLACK), 0, "one Undo");
}

#[test]
fn outline_outside_square_fills_the_corners_and_width_grows_the_ring() {
    let s = run(&format!("{SQUARE}\nOutline(#000000FF,outside,square,1)"));
    assert_eq!(count(&s, 0, 0, 12, 12, BLACK), 16, "the full 5×5 ring");
    assert_eq!(s.pixel(0, 0, 2, 2), BLACK, "square corners");
    let w2 = run(&format!("{SQUARE}\nOutline(#000000FF,outside,square,2)"));
    assert_eq!(count(&w2, 0, 0, 12, 12, BLACK), 49 - 9, "a 7×7 minus the 3×3");
}

#[test]
fn outline_inside_eats_the_rim_and_leaves_the_core() {
    let s = run(&format!("{SQUARE}\nOutline(#000000FF,inside,square,1)"));
    assert_eq!(count(&s, 0, 0, 12, 12, BLACK), 8, "the square's own rim");
    assert_eq!(s.pixel(0, 0, 4, 4), RED, "the center survives");
    // Width ≥ the thickness recolors the whole shape (expected).
    let all = run(&format!("{SQUARE}\nOutline(#000000FF,inside,round,2)"));
    assert_eq!(count(&all, 0, 0, 12, 12, RED), 0);
}

#[test]
fn outline_is_clipped_by_the_canvas_and_the_selection() {
    // Content touching the edge: the outside ring is clipped there (no auto-grow).
    let edge = run("NewDocument(6,6)\nSelectTool(Pencil); SetPrimaryColor(#FF0000FF); Tap(0,0)\nOutline(#000000FF,outside,square,1)");
    assert_eq!(count(&edge, 0, 0, 6, 6, BLACK), 3, "only the three in-canvas neighbors");
    // A tight selection around the square clips the outside ring away entirely.
    let sel = run(&format!("{SQUARE}\nSelectTool(SelectRect)\nStroke([(3,3),(5,5)])\nOutline(#000000FF,outside,square,1)"));
    assert_eq!(count(&sel, 0, 0, 12, 12, BLACK), 0, "the ring lies outside the mask");
    // A selection covering the left half: the ring lands only inside it, from the selected alpha.
    let half = run(&format!("{SQUARE}\nSelectTool(SelectRect)\nStroke([(0,0),(4,11)])\nOutline(#000000FF,outside,square,1)"));
    assert_eq!(half.pixel(0, 0, 2, 4), BLACK);
    assert_eq!(half.pixel(0, 0, 6, 4), CLEAR, "outside the selection");
    // Column 5 is unselected, so the selected content ends at column 4: its outside ring at
    // column 5 is clipped by the mask as well.
    assert_eq!(half.pixel(0, 0, 5, 4), RED);
}

#[test]
fn outline_never_mirrors_and_is_not_pattern_gated() {
    let plain = run(&format!("{SQUARE}\nOutline(#000000FF,outside,square,1)"));
    let sym = run(&format!("{SQUARE}\nSetSymmetry(both,c,c); SetPattern(2,2,9)\nOutline(#000000FF,outside,square,1)"));
    assert_eq!(count(&plain, 0, 0, 12, 12, BLACK), count(&sym, 0, 0, 12, 12, BLACK));
    for y in 0..12 {
        for x in 0..12 {
            assert_eq!(plain.pixel(0, 0, x, y), sym.pixel(0, 0, x, y), "({x},{y})");
        }
    }
}

#[test]
fn outline_on_a_locked_layer_is_a_no_op_and_repeat_reads_the_live_layer() {
    let mut s = run(&format!("{SQUARE}\nSetLayerLocked(0,true)\nOutline(#000000FF,outside,square,1)"));
    assert_eq!(count(&s, 0, 0, 12, 12, BLACK), 0);
    s.run_script("SetLayerLocked(0,false); Outline(#000000FF,outside,square,1)\nUndo()\nAddLayer(); SelectTool(Pencil); SetPrimaryColor(#00FF00FF); Tap(8,8)\nRepeat()").unwrap();
    assert_eq!(s.pixel(0, 1, 7, 8), BLACK, "Repeat outlined the new layer's dot");
    assert_eq!(count(&s, 0, 0, 12, 12, BLACK), 0, "the old layer untouched");
}

#[test]
fn outline_rejects_garbage() {
    let mut s = Session::empty();
    assert!(s.run_script("Outline(#000000FF,around,round,1)").is_err());
    assert!(s.run_script("Outline(#000000FF,outside,fancy,1)").is_err());
}
