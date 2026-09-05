//! Symmetry / mirror drawing (ADR 0026): every write of Pencil, Brush, Eraser, the airbrushes,
//! Dodge/Burn, Bucket, Line, and Shape lands once per image of its point through a half-pixel
//! axis, driven through the DSL exactly as the shell and the journal drive it. The `PINS` at the
//! bottom are literal layer-hash snapshots in the `aa_off_pins` doctrine: a moved pin IS the bug —
//! re-pin only after a deliberate, announced behavior change.
//!
//! Regenerate (after such a change) with:
//!   cargo test --test symmetry print_symmetry_pins -- --ignored --nocapture

use makapix_engine::util::hash_hex;
use makapix_engine::{Rgba8, Session};

fn run(src: &str) -> Session {
    let mut s = Session::empty();
    s.run_script(src).expect("script ok");
    s
}

fn hash(s: &Session, f: usize, l: usize) -> String {
    hash_hex(s.layer_hash(f, l))
}

const RED: Rgba8 = Rgba8::new(255, 0, 0, 255);
const GREEN: Rgba8 = Rgba8::new(0, 255, 0, 255);
const BLACK: Rgba8 = Rgba8::new(0, 0, 0, 255);
const CLEAR: Rgba8 = Rgba8::TRANSPARENT;

/// Every pixel of layer 0 that is not transparent, as (x, y).
fn painted(s: &Session, w: i32, h: i32) -> Vec<(i32, i32)> {
    let mut v = Vec::new();
    for y in 0..h {
        for x in 0..w {
            if s.pixel(0, 0, x, y) != CLEAR {
                v.push((x, y));
            }
        }
    }
    v
}

/// Assert the layer is an exact left ↔ right mirror through the canvas center.
fn assert_h_symmetric(s: &Session, w: i32, h: i32) {
    for y in 0..h {
        for x in 0..w {
            assert_eq!(s.pixel(0, 0, x, y), s.pixel(0, 0, w - 1 - x, y), "({x},{y}) vs its H image");
        }
    }
}

#[test]
fn h_center_is_exact_for_odd_and_even_widths() {
    // Odd: the axis runs through column 4 of a 9-wide canvas → (2,3) mirrors to (6,3).
    let odd = run("NewDocument(9,8)\nSelectTool(Pencil); SetPrimaryColor(#FF0000FF); SetSymmetry(h,c,c)\nTap(2,3)");
    assert_eq!(painted(&odd, 9, 8), vec![(2, 3), (6, 3)]);
    // Even: the axis runs between columns 3 and 4 of an 8-wide canvas → (2,3) mirrors to (5,3).
    let even = run("NewDocument(8,8)\nSelectTool(Pencil); SetPrimaryColor(#FF0000FF); SetSymmetry(h,c,c)\nTap(2,3)");
    assert_eq!(painted(&even, 8, 8), vec![(2, 3), (5, 3)]);
}

#[test]
fn v_mirrors_top_to_bottom() {
    let s = run("NewDocument(8,9)\nSelectTool(Pencil); SetPrimaryColor(#FF0000FF); SetSymmetry(v,c,c)\nTap(2,1)");
    assert_eq!(painted(&s, 8, 9), vec![(2, 1), (2, 7)]);
}

#[test]
fn both_yields_four_images() {
    let s = run("NewDocument(8,8)\nSelectTool(Pencil); SetPrimaryColor(#FF0000FF); SetSymmetry(both,c,c)\nTap(1,2)");
    assert_eq!(painted(&s, 8, 8), vec![(1, 2), (6, 2), (1, 5), (6, 5)]);
}

#[test]
fn a_pixel_on_the_axis_is_written_once_and_the_stroke_is_one_undo_step() {
    let mut s = run("NewDocument(9,8)\nSelectTool(Pencil); SetPrimaryColor(#FF0000FF); SetSymmetry(h,c,c)\nTap(4,3)");
    assert_eq!(painted(&s, 9, 8), vec![(4, 3)], "the axis pixel is its own image");
    s.run_script("Undo()").unwrap();
    assert_eq!(painted(&s, 9, 8), Vec::<(i32, i32)>::new(), "one Undo reverts the whole tap");
    assert!(!s.doc.can_undo(), "the tap and its mirror were ONE record");
}

#[test]
fn a_mirrored_stroke_is_one_undo_step_including_its_images() {
    let mut s = run("NewDocument(8,8)\nSelectTool(Pencil); SetPrimaryColor(#FF0000FF); SetSymmetry(both,c,c)\nStroke([(1,1),(2,2)])");
    assert_eq!(painted(&s, 8, 8).len(), 8);
    s.run_script("Undo()").unwrap();
    assert!(painted(&s, 8, 8).is_empty());
    assert!(!s.doc.can_undo());
}

#[test]
fn translucent_brush_crossing_its_own_axis_never_darkens() {
    // A 50%-alpha brush swept across the axis: its mirror overlaps it exactly there, and the
    // single coat max-combines (ADR 0007) — every covered pixel is one coat, alpha 128.
    let s = run(
        "NewDocument(16,16)\nSelectTool(Brush); SetPrimaryColor(#FF000080); SetBrushShape(Round); SetBrushSize(3); SetSymmetry(h,c,c)\nStroke([(4,8),(11,8)])",
    );
    let px = painted(&s, 16, 16);
    assert!(!px.is_empty());
    for &(x, y) in &px {
        assert_eq!(s.pixel(0, 0, x, y).a, 128, "({x},{y}): one coat, never two");
    }
    assert_h_symmetric(&s, 16, 16);
}

#[test]
fn aa_brush_mirror_keeps_the_rim_exact_and_symmetric() {
    let s = run(
        "NewDocument(16,16)\nSelectTool(Brush); SetPrimaryColor(#0000FFFF); SetBrushShape(Round); SetBrushSize(5); SetAA(true); SetSymmetry(both,c,c)\nStroke([(3,3),(6,5)])",
    );
    assert_h_symmetric(&s, 16, 16);
    for y in 0..16 {
        for x in 0..16 {
            assert_eq!(s.pixel(0, 0, x, y), s.pixel(0, 0, x, 15 - y), "({x},{y}) vs its V image");
        }
    }
}

#[test]
fn eraser_mirrors_too() {
    let s = run(
        "NewDocument(8,8)\nSelectTool(Pencil); SetPrimaryColor(#000000FF)\nStroke([(0,4),(7,4)])\nSelectTool(Eraser); SetBrushSize(1); SetSymmetry(h,c,c)\nTap(1,4)",
    );
    assert_eq!(s.pixel(0, 0, 1, 4), CLEAR);
    assert_eq!(s.pixel(0, 0, 6, 4), CLEAR, "the mirrored erase");
    assert_eq!(s.pixel(0, 0, 2, 4), BLACK);
}

#[test]
fn line_and_shape_mirror_pixel_exactly_without_double_blending() {
    // A 50%-alpha AA line from one corner past the axis: its image overlaps it near the axis
    // and the coverage map composites each pixel once — alpha never exceeds the color's.
    let s = run(
        "NewDocument(16,16)\nSelectTool(Line); SetPrimaryColor(#FF000080); SetAA(true); SetSymmetry(h,c,c)\nShapeSet(2,2,12,9); ShapeCommit()",
    );
    assert_h_symmetric(&s, 16, 16);
    for &(x, y) in &painted(&s, 16, 16) {
        assert!(s.pixel(0, 0, x, y).a <= 128, "({x},{y}) blended twice");
    }
    // A filled, hard rectangle under Both: four boxes, four-fold symmetric. (The DSL's `a`,`b` are
    // already-rotated corners, so a rotation here would need rotated corners — the shell's job.)
    let r = run(
        "NewDocument(16,16)\nSelectTool(Rectangle); SetPrimaryColor(#00FF00FF); SetShapeFill(true); SetSymmetry(both,c,c)\nShapeSet(1,1,6,4); ShapeCommit()",
    );
    assert_h_symmetric(&r, 16, 16);
    for y in 0..16 {
        for x in 0..16 {
            assert_eq!(r.pixel(0, 0, x, y), r.pixel(0, 0, x, 15 - y), "({x},{y}) vs its V image");
        }
    }
    assert_eq!(painted(&r, 16, 16).len(), 4 * 24, "four disjoint 6×4 boxes");
}

#[test]
fn bucket_floods_every_seed_image_and_repeat_reads_the_live_symmetry() {
    // A black wall at x = 7 splits a 16-wide canvas; under H the mirrored seed (13,2) floods the
    // right half while the tap floods the left. Both regions are decided against the pre-fill
    // buffer and written once.
    let mut s = run(
        "NewDocument(16,8)\nSelectTool(Pencil); SetPrimaryColor(#000000FF)\nStroke([(7,0),(7,7)])\nSelectTool(Bucket); SetPrimaryColor(#00FF00FF); SetSymmetry(h,c,c)\nTap(2,2)",
    );
    assert_eq!(s.pixel(0, 0, 2, 2), GREEN);
    assert_eq!(s.pixel(0, 0, 13, 2), GREEN, "the mirrored seed's region");
    assert_eq!(s.pixel(0, 0, 7, 3), BLACK, "the wall stands");
    // Repeat under a live Off: only the tapped region again (the record does not freeze the mode).
    s.run_script("Undo(); SetSymmetry(off); Repeat()").unwrap();
    assert_eq!(s.pixel(0, 0, 2, 2), GREEN);
    assert_eq!(s.pixel(0, 0, 13, 2), CLEAR, "Repeat fills under the symmetry in force now");
}

#[test]
fn the_selection_clips_every_image_and_is_never_mirrored() {
    let s = run(
        "NewDocument(16,8)\nSelectTool(SelectRect)\nStroke([(0,0),(6,7)])\nSelectTool(Pencil); SetPrimaryColor(#FF0000FF); SetSymmetry(h,c,c)\nTap(2,2); Tap(5,2)",
    );
    assert_eq!(s.pixel(0, 0, 2, 2), RED);
    assert_eq!(s.pixel(0, 0, 5, 2), RED);
    assert_eq!(s.pixel(0, 0, 13, 2), CLEAR, "the image lies outside the marquee");
    assert_eq!(s.pixel(0, 0, 10, 2), CLEAR);
}

#[test]
fn the_pattern_gate_is_consulted_at_each_images_own_coordinate() {
    // 2×2 checker: (x + y) even is ON. Under H on a 16-wide canvas, x' = 15 − x flips parity,
    // so a tap on an ON cell has its image on an OFF cell — and paints only the primary.
    let s = run(
        "NewDocument(16,8)\nSelectTool(Pencil); SetPrimaryColor(#FF0000FF); SetPattern(2,2,9); SetSymmetry(h,c,c)\nTap(2,2)",
    );
    assert_eq!(painted(&s, 16, 8), vec![(2, 2)], "(13,2) is an OFF cell of the canvas-anchored dither");
}

#[test]
fn airbrush_specks_mirror_pixel_exactly() {
    let s = run(
        "NewDocument(16,16)\nSelectTool(Airbrush); SetPrimaryColor(#000000FF); SetBrushSize(5); SetIntensity(120); SetSeed(7); SetSymmetry(h,c,c)\nStroke([(3,8),(6,8)])",
    );
    assert!(painted(&s, 16, 16).len() > 4, "a scatter landed");
    assert_h_symmetric(&s, 16, 16);
    let m = run(
        "NewDocument(16,16)\nSelectTool(AirbrushMist); SetPrimaryColor(#000000FF); SetBrushSize(6); SetIntensity(200); SetSeed(9); SetSymmetry(both,c,c)\nStroke([(3,3),(6,6)])",
    );
    assert_h_symmetric(&m, 16, 16);
}

#[test]
fn pixel_perfect_pencil_stays_symmetric_across_its_own_axis() {
    let s = run(
        "NewDocument(16,16)\nSelectTool(Pencil); SetPrimaryColor(#FF0000FF); SetPixelPerfect(true); SetSymmetry(h,c,c)\nStroke([(3,3),(4,3),(5,4),(6,4),(7,5),(8,5),(9,6),(9,7),(9,8)])",
    );
    assert_h_symmetric(&s, 16, 16);
    // The primary line stays connected (no gap where the mirror crossed it).
    assert_eq!(s.pixel(0, 0, 7, 5), RED);
    assert_eq!(s.pixel(0, 0, 8, 5), RED);
}

#[test]
fn an_explicit_axis_is_honored_and_clamped_to_the_canvas() {
    // A = 4 in half-pixels: x' = 4 − x. (1,3) → (3,3); (10,3) → (−6,3), off-canvas and dropped.
    let s = run("NewDocument(16,8)\nSelectTool(Pencil); SetPrimaryColor(#FF0000FF); SetSymmetry(h,4,c)\nTap(1,3); Tap(10,3)");
    assert_eq!(painted(&s, 16, 8), vec![(1, 3), (3, 3), (10, 3)]);
    // A = 5: between columns 2 and 3. (2,1) → (3,1).
    let h = run("NewDocument(16,8)\nSelectTool(Pencil); SetPrimaryColor(#FF0000FF); SetSymmetry(h,5,c)\nTap(2,1)");
    assert_eq!(painted(&h, 16, 8), vec![(2, 1), (3, 1)]);
    // Out-of-range axes clamp to the canvas: 999 → 30 (the last column), −5 → 0 (the first).
    let c = run("NewDocument(16,8)\nSelectTool(Pencil); SetPrimaryColor(#FF0000FF); SetSymmetry(h,999,c)\nTap(14,3)");
    assert_eq!(painted(&c, 16, 8), vec![(14, 3)], "(16,3) is off-canvas: the axis stopped at the edge");
    let z = run("NewDocument(16,8)\nSelectTool(Pencil); SetPrimaryColor(#FF0000FF); SetSymmetry(h,-5,c)\nTap(0,3); Tap(1,3)");
    assert_eq!(painted(&z, 16, 8), vec![(0, 3), (1, 3)], "axis at column 0: (1,3) → (−1,3) dropped");
}

#[test]
fn a_centered_axis_follows_a_canvas_resize() {
    let s = run(
        "NewDocument(8,8)\nSelectTool(Pencil); SetPrimaryColor(#FF0000FF); SetSymmetry(h,c,c)\nResizeCanvas(12,8,Center)\nTap(1,3)",
    );
    assert_eq!(painted(&s, 12, 8), vec![(1, 3), (10, 3)], "the center moved with the canvas");
}

#[test]
fn set_symmetry_round_trips_through_the_dsl_and_rejects_garbage() {
    let s = run("NewDocument(8,8)\nSetSymmetry(both,3,c)");
    assert!(s.state_json().contains("\"symmetry\":\"SetSymmetry(both,3,c)\""), "{}", s.state_json());
    let o = run("NewDocument(8,8)\nSetSymmetry(both,3,c)\nSetSymmetry(off)");
    assert!(o.state_json().contains("\"symmetry\":\"SetSymmetry(off,c,c)\""));
    let mut bad = Session::empty();
    assert!(bad.run_script("SetSymmetry(diag)").is_err());
    assert!(bad.run_script("SetSymmetry(h,x,c)").is_err());
}

#[test]
fn symmetry_never_leaks_into_the_non_participating_tools() {
    // The Gradient fills its whole span once; a mirror would be visible as a second ramp.
    let g = run(
        "NewDocument(16,4)\nSelectTool(Gradient); SetGradientType(Linear); SetGradientStops(#FF0000FF@0,#0000FFFF@1); SetSymmetry(h,c,c)\nShapeSet(0,0,15,0); ShapeCommit()",
    );
    let plain = run(
        "NewDocument(16,4)\nSelectTool(Gradient); SetGradientType(Linear); SetGradientStops(#FF0000FF@0,#0000FFFF@1)\nShapeSet(0,0,15,0); ShapeCommit()",
    );
    assert_eq!(hash(&g, 0, 0), hash(&plain, 0, 0), "the Gradient ignores symmetry");
}

#[test]
fn off_is_byte_identical_to_the_pre_symmetry_engine() {
    // `SetSymmetry(off)` and a never-set session must produce the same pixels for every path
    // the feature touched — the un-mirrored code is untouched by construction, this pins it.
    let base = "NewDocument(16,16)\nSelectTool(Pencil); SetPrimaryColor(#FF0000FF); SetPixelPerfect(true)\nStroke([(1,1),(3,2),(6,2)])\nSelectTool(Brush); SetBrushSize(4); SetAA(true)\nStroke([(2,9),(9,12)])\nSelectTool(Line); SetPrimaryColor(#00FF00FF)\nShapeSet(0,15,15,4); ShapeCommit()\nSelectTool(Bucket); SetPrimaryColor(#0000FF40)\nTap(14,0)";
    let a = run(base);
    let b = run(&format!("{base}\nSetSymmetry(h,c,c)\nSetSymmetry(off)"));
    let c = run(&base.replace("NewDocument(16,16)", "NewDocument(16,16)\nSetSymmetry(off,c,c)"));
    assert_eq!(hash(&a, 0, 0), hash(&b, 0, 0));
    assert_eq!(hash(&a, 0, 0), hash(&c, 0, 0));
}

// ---------------------------------------------------------------------------------------------
// Pins: literal layer hashes of representative mirrored outputs.
// ---------------------------------------------------------------------------------------------

const PINS: &[(&str, &str, &str)] = &[
    (
        "pencil_h_odd",
        "NewDocument(17,9)\nSelectTool(Pencil); SetPrimaryColor(#FF0000FF); SetPixelPerfect(true); SetSymmetry(h,c,c)\nStroke([(2,2),(5,3),(8,6),(9,7)])",
        "d256fd0369f32c829feb51fd2f46ebc7",
    ),
    (
        "brush_aa_both",
        "NewDocument(24,24)\nSelectTool(Brush); SetPrimaryColor(#0000FF80); SetBrushShape(Round); SetBrushSize(6); SetAA(true); SetSymmetry(both,c,c)\nStroke([(4,4),(12,7),(11,12)])",
        "73e24e222f539535868545958a92735d",
    ),
    (
        "line_aa_v_explicit_axis",
        "NewDocument(24,24)\nSelectTool(Line); SetPrimaryColor(#00FF00FF); SetLineWidth(2); SetAA(true); SetSymmetry(v,c,9)\nShapeSet(1,1,22,3); ShapeCommit()",
        "24ec2b8bdfb0a1ed622e1c77ed4bc44d",
    ),
    (
        "ellipse_outline_both",
        "NewDocument(24,24)\nSelectTool(Ellipse); SetPrimaryColor(#FF00FFFF); SetShapeFill(false); SetLineWidth(1); SetSymmetry(both,c,c)\nShapeSet(2,2,9,7); ShapeCommit()",
        "1ccef66cf315a5a59bee6090d148ef9d",
    ),
    (
        "bucket_h_wall",
        "NewDocument(24,12)\nSelectTool(Pencil); SetPrimaryColor(#000000FF)\nStroke([(10,0),(10,11)])\nSelectTool(Bucket); SetPrimaryColor(#00FF00FF); SetSymmetry(h,c,c)\nTap(2,2)",
        "5de6cadbf2ec055a0c956182fc91342b",
    ),
    (
        "airbrush_dots_h",
        "NewDocument(24,24)\nSelectTool(Airbrush); SetPrimaryColor(#000000FF); SetBrushSize(6); SetIntensity(140); SetSeed(11); SetSymmetry(h,c,c)\nStroke([(4,12),(9,12)])",
        "7b5195e7a6b1424afe5cc8ab8af8b792",
    ),
];

#[test]
fn symmetry_output_is_pinned() {
    for (name, script, pin) in PINS {
        assert_eq!(&hash_of(script), pin, "{name}: pinned hash moved — the change IS the bug");
    }
}

fn hash_of(script: &str) -> String {
    hash(&run(script), 0, 0)
}

#[test]
#[ignore]
fn print_symmetry_pins() {
    for (name, script, _) in PINS {
        println!("{name}: {}", hash_of(script));
    }
}
