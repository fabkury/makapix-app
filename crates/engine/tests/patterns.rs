//! Patterns (ADR 0025): the canvas-anchored paint gate on Pencil/Brush/Eraser/Bucket and the
//! Gradient's Bayer dither, driven through the DSL exactly as the shell and the journal drive
//! them. The `PINS` at the bottom are literal layer-hash snapshots in the `aa_off_pins` doctrine:
//! a moved pin IS the bug — re-pin only after a deliberate, announced behavior change.
//!
//! Regenerate (after such a change) with:
//!   cargo test --test patterns print_pattern_pins -- --ignored --nocapture

use makapix_engine::tool::{bayer_threshold, Pattern};
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
const BLACK: Rgba8 = Rgba8::new(0, 0, 0, 255);
const WHITE: Rgba8 = Rgba8::new(255, 255, 255, 255);
const CLEAR: Rgba8 = Rgba8::TRANSPARENT;

/// The 2×2 checker: (0,0) and (1,1) ON → bits 0 and 3 → hex 9.
const CHECKER: &str = "SetPattern(2,2,9)";
fn checker_on(x: i32, y: i32) -> bool {
    (x + y) % 2 == 0
}

#[test]
fn pencil_tap_on_an_off_cell_paints_nothing_and_records_no_undo_step() {
    let mut s = run(&format!("NewDocument(8,8)\nSelectTool(Pencil); SetPrimaryColor(#FF0000FF); {CHECKER}\nTap(1,0)"));
    assert_eq!(s.pixel(0, 0, 1, 0), CLEAR, "(1,0) is an OFF cell");
    // The engine's standing empty-edit rule applies: no pixel changed, so no undo step — exactly
    // as painting a color over itself records nothing.
    assert!(!s.doc.can_undo(), "an empty gated tap records no undo step (the empty-edit rule)");
    s.run_script("Tap(0,0)").unwrap();
    assert_eq!(s.pixel(0, 0, 0, 0), RED, "(0,0) is an ON cell");
}

#[test]
fn brush_dab_writes_exactly_the_on_subset_of_its_footprint() {
    let gated = run(&format!(
        "NewDocument(16,16)\nSelectTool(Brush); SetPrimaryColor(#FF0000FF); SetBrushShape(Round); SetBrushSize(5); {CHECKER}\nTap(7,7)"
    ));
    let plain = run("NewDocument(16,16)\nSelectTool(Brush); SetPrimaryColor(#FF0000FF); SetBrushShape(Round); SetBrushSize(5)\nTap(7,7)");
    let mut painted = 0;
    for y in 0..16 {
        for x in 0..16 {
            let expect = if plain.pixel(0, 0, x, y) == RED && checker_on(x, y) { RED } else { CLEAR };
            assert_eq!(gated.pixel(0, 0, x, y), expect, "({x},{y})");
            if expect == RED {
                painted += 1;
            }
        }
    }
    assert!(painted > 0 && painted * 2 <= 21 + 1, "about half the 21-pixel disc: {painted}");
}

#[test]
fn eraser_erases_on_cells_only() {
    let s = run(&format!(
        "NewDocument(8,8)\nSelectTool(Pencil); SetPrimaryColor(#FF0000FF); SetBrushShape(Square); SetBrushSize(16)\nTap(4,4)\n\
         SelectTool(Eraser); SetBrushShape(Square); SetBrushSize(16); {CHECKER}\nTap(4,4)"
    ));
    for y in 0..8 {
        for x in 0..8 {
            let expect = if checker_on(x, y) { CLEAR } else { RED };
            assert_eq!(s.pixel(0, 0, x, y), expect, "({x},{y})");
        }
    }
}

#[test]
fn overlapping_strokes_tile_seamlessly_because_the_gate_is_canvas_anchored() {
    // Two overlapping dabs begun at different phases must produce the same checker as one
    // big fill would: no seam, no doubled cells.
    let s = run(&format!(
        "NewDocument(8,8)\nSelectTool(Pencil); SetPrimaryColor(#FF0000FF); SetBrushShape(Square); SetBrushSize(5); {CHECKER}\nTap(2,2)\nTap(3,3)"
    ));
    for y in 0..8 {
        for x in 0..8 {
            let in_union = (0..=4).contains(&x) && (0..=4).contains(&y) || (1..=5).contains(&x) && (1..=5).contains(&y);
            let expect = if in_union && checker_on(x, y) { RED } else { CLEAR };
            assert_eq!(s.pixel(0, 0, x, y), expect, "({x},{y})");
        }
    }
}

#[test]
fn bucket_region_ignores_the_gate_and_only_the_writes_are_masked() {
    // A black wall at x=4 splits the canvas; the flood from (0,0) must reach every left-side
    // pixel — including ON cells only reachable through OFF cells — and never cross the wall.
    let s = run(&format!(
        "NewDocument(8,8)\nSelectTool(Pencil); SetPrimaryColor(#000000FF); SetBrushShape(Square); SetBrushSize(1)\n\
         Stroke([(4,0),(4,7)])\nSelectTool(Bucket); SetPrimaryColor(#FFFFFFFF); {CHECKER}\nTap(0,0)"
    ));
    for y in 0..8 {
        for x in 0..8 {
            let expect = if x == 4 {
                BLACK
            } else if x < 4 && checker_on(x, y) {
                WHITE
            } else {
                CLEAR
            };
            assert_eq!(s.pixel(0, 0, x, y), expect, "({x},{y})");
        }
    }
}

#[test]
fn bucket_repeat_reproduces_the_dither_even_after_the_pattern_went_off() {
    let mut s = run(&format!("NewDocument(4,4)\nSelectTool(Bucket); SetPrimaryColor(#FFFFFFFF); {CHECKER}\nTap(0,0)"));
    s.run_script("SetPattern(off)\nAddFrame()\nRepeat()").unwrap();
    assert_eq!(s.repeat_label(), Some("Fill"));
    for y in 0..4 {
        for x in 0..4 {
            let expect = if checker_on(x, y) { WHITE } else { CLEAR };
            assert_eq!(s.pixel(1, 0, x, y), expect, "frame 1 ({x},{y})");
        }
    }
}

#[test]
fn selection_and_pattern_are_independent_gates() {
    let s = run(&format!(
        "NewDocument(8,8)\nSelectTool(SelectRect); Stroke([(2,2),(5,5)])\n\
         SelectTool(Pencil); SetPrimaryColor(#FF0000FF); SetBrushShape(Square); SetBrushSize(16); {CHECKER}\nTap(4,4)"
    ));
    for y in 0..8 {
        for x in 0..8 {
            let in_sel = (2..=5).contains(&x) && (2..=5).contains(&y);
            let expect = if in_sel && checker_on(x, y) { RED } else { CLEAR };
            assert_eq!(s.pixel(0, 0, x, y), expect, "({x},{y})");
        }
    }
}

#[test]
fn a_mid_stroke_set_pattern_applies_from_the_next_stroke() {
    // ADR 0007: the coat freezes its settings at stroke start.
    let live = run(&format!(
        "NewDocument(16,16)\nSelectTool(Brush); SetPrimaryColor(#FF0000FF); SetBrushSize(3)\n\
         PointerDown(2,2); {CHECKER}; PointerMove(12,12); PointerUp()"
    ));
    let plain = run("NewDocument(16,16)\nSelectTool(Brush); SetPrimaryColor(#FF0000FF); SetBrushSize(3)\nPointerDown(2,2); PointerMove(12,12); PointerUp()");
    assert_eq!(hash(&live, 0, 0), hash(&plain, 0, 0));
}

#[test]
fn aa_is_inert_while_a_pattern_is_on() {
    let aa = run(&format!(
        "NewDocument(16,16)\nSelectTool(Brush); SetPrimaryColor(#FF0000FF); SetBrushShape(Round); SetBrushSize(7); SetAA(true); {CHECKER}\nStroke([(3,3),(12,10)])"
    ));
    let hard = run(&format!(
        "NewDocument(16,16)\nSelectTool(Brush); SetPrimaryColor(#FF0000FF); SetBrushShape(Round); SetBrushSize(7); SetAA(false); {CHECKER}\nStroke([(3,3),(12,10)])"
    ));
    assert_eq!(hash(&aa, 0, 0), hash(&hard, 0, 0));
    // …and AA is back the moment the pattern goes off.
    let aa_off_pattern = run("NewDocument(16,16)\nSelectTool(Brush); SetPrimaryColor(#FF0000FF); SetBrushShape(Round); SetBrushSize(7); SetAA(true); SetPattern(2,2,9); SetPattern(off)\nStroke([(3,3),(12,10)])");
    let aa_plain = run("NewDocument(16,16)\nSelectTool(Brush); SetPrimaryColor(#FF0000FF); SetBrushShape(Round); SetBrushSize(7); SetAA(true)\nStroke([(3,3),(12,10)])");
    assert_eq!(hash(&aa_off_pattern, 0, 0), hash(&aa_plain, 0, 0));
    assert_ne!(hash(&aa_plain, 0, 0), hash(&hard, 0, 0), "sanity: AA does change the ungated stroke");
}

#[test]
fn a_pattern_never_leaks_into_the_non_participating_tools() {
    for tool in ["Line", "Rectangle", "Ellipse", "Airbrush", "AirbrushSoft", "Dodge"] {
        let gated = run(&format!(
            "NewDocument(16,16)\nSetSeed(7)\nSelectTool(Pencil); SetPrimaryColor(#808080FF); SetBrushShape(Square); SetBrushSize(16)\nTap(8,8)\n\
             SelectTool({tool}); SetPrimaryColor(#FF0000FF); SetBrushSize(5); SetIntensity(200); {CHECKER}\nStroke([(2,2),(13,11)])"
        ));
        let plain = run(&format!(
            "NewDocument(16,16)\nSetSeed(7)\nSelectTool(Pencil); SetPrimaryColor(#808080FF); SetBrushShape(Square); SetBrushSize(16)\nTap(8,8)\n\
             SelectTool({tool}); SetPrimaryColor(#FF0000FF); SetBrushSize(5); SetIntensity(200)\nStroke([(2,2),(13,11)])"
        ));
        assert_eq!(hash(&gated, 0, 0), hash(&plain, 0, 0), "{tool}");
    }
}

#[test]
fn larger_tiles_up_to_16x16_are_accepted_on_the_wire() {
    // A 12×12 tile with only its top-left cell ON, and a 16×16 with only the last cell ON.
    let s = run("NewDocument(32,32)\nSelectTool(Pencil); SetPrimaryColor(#FF0000FF); SetBrushShape(Square); SetBrushSize(64); SetPattern(12,12,1)\nTap(16,16)");
    for y in 0..32 {
        for x in 0..32 {
            let expect = if x % 12 == 0 && y % 12 == 0 { RED } else { CLEAR };
            assert_eq!(s.pixel(0, 0, x, y), expect, "({x},{y})");
        }
    }
    let last = Pattern::parse(16, 16, &format!("8{}", "0".repeat(63))).unwrap();
    assert!(last.on(15, 15) && !last.on(0, 0) && last.on(31, 31));
    let s = run(&format!("NewDocument(32,32)\nSelectTool(Pencil); SetPrimaryColor(#FF0000FF); SetBrushShape(Square); SetBrushSize(64); {}\nTap(16,16)", last.to_dsl()));
    assert_eq!(s.pixel(0, 0, 15, 15), RED);
    assert_eq!(s.pixel(0, 0, 31, 31), RED);
    assert_eq!(s.pixel(0, 0, 0, 0), CLEAR);
}

#[test]
fn malformed_pattern_lines_are_rejected() {
    let mut s = Session::empty();
    s.run_script("NewDocument(4,4)").unwrap();
    for bad in ["SetPattern(17,1,1)", "SetPattern(0,2,1)", "SetPattern(2,2,10)", "SetPattern(2,2,zz)", "SetPattern(2,2)", "SetPattern(2,2,)", "SetGradientDither(3)", "SetGradientDither(16)"] {
        assert!(s.run_script(bad).is_err(), "{bad} must not parse");
    }
    for good in ["SetPattern(2,2,f)", "SetPattern(2,2,000f)", "SetPattern(OFF)", "SetPattern(off)", "SetGradientDither(0)", "SetGradientDither(8)"] {
        assert!(s.run_script(good).is_ok(), "{good} must parse");
    }
}

#[test]
fn gradient_dither_yields_exactly_the_two_stop_colors_with_a_monotone_ladder() {
    let s = run("NewDocument(64,8)\nSelectTool(Gradient); SetGradientType(Linear); SetGradientStops(#FF0000FF@0,#0000FFFF@1); SetGradientDither(4)\nShapeSet(0,0,63,0); ShapeCommit()");
    let blue = Rgba8::new(0, 0, 255, 255);
    // Ordered dither: the blue density over each 4-column period (one Bayer 4×4 period wide, the
    // 8 rows tall) never decreases along the ramp — per-column counts legitimately zigzag.
    let mut prev = 0;
    for bx in 0..16 {
        let mut blues = 0;
        for x in bx * 4..bx * 4 + 4 {
            for y in 0..8 {
                let p = s.pixel(0, 0, x, y);
                assert!(p == RED || p == blue, "({x},{y}) = {p:?} is not a stop color");
                if p == blue {
                    blues += 1;
                }
            }
        }
        assert!(blues >= prev, "period {bx}: {blues} < {prev}");
        prev = blues;
    }
    assert_eq!(s.pixel(0, 0, 0, 0), RED);
    assert_eq!(s.pixel(0, 0, 63, 7), blue);
}

#[test]
fn gradient_dither_with_alpha_stops_produces_exactly_two_alphas() {
    let s = run("NewDocument(32,4)\nSelectTool(Gradient); SetGradientStops(#FFFF00FF@0,#FFFF0000@1); SetGradientDither(2)\nShapeSet(0,0,31,0); ShapeCommit()");
    for x in 0..32 {
        for y in 0..4 {
            let a = s.pixel(0, 0, x, y).a;
            assert!(a == 0 || a == 255, "({x},{y}) alpha {a}");
        }
    }
}

#[test]
fn gradient_dither_is_anchored_to_the_canvas_origin() {
    // The threshold at canvas (x, y) is the Bayer entry — verified against a 50 % ramp point.
    let s = run("NewDocument(16,16)\nSelectTool(Gradient); SetGradientStops(#000000FF@0,#FFFFFFFF@1); SetGradientDither(4)\nShapeSet(0,0,0,1); ShapeCommit()");
    // p0=(0,0), p1=(0,1): every pixel at y ≥ 1 has t = 1 → white; y = 0 has t = 0 → black. A
    // degenerate ramp makes the dither irrelevant, so check the threshold table directly instead:
    assert_eq!(s.pixel(0, 0, 3, 0), BLACK);
    assert_eq!(s.pixel(0, 0, 3, 1), WHITE);
    assert_eq!(bayer_threshold(4, 0, 0), 0);
    assert_eq!(bayer_threshold(4, 1, 0), 8);
    assert_eq!(bayer_threshold(4, -1, -1), 5, "negative coordinates wrap like positive ones");
    // A mid-ramp half-gray plane at t = 0.5 under Bayer 4×4 lights exactly the 8 cells with
    // threshold < 8 per 4×4 block.
    let s = run("NewDocument(8,8)\nSelectTool(Gradient); SetGradientStops(#000000FF@0,#FFFFFFFF@1); SetGradientDither(4); SetGradientType(Linear)\nShapeSet(-8,0,7,0); ShapeCommit()");
    // t(x) = (x+8)/15 spans 0.53..1 — not a plane; use the direct rule instead: the pixel is white
    // iff floor(t·16) > bayer(x, y).
    for y in 0..8 {
        for x in 0..8 {
            // The same f32 expression `gradient_t` evaluates (dx = 15, len² = 225, dy = 0).
            let t = ((x as f32 + 8.0) * 15.0 + 0.0) / 225.0;
            let expect = if ((t * 16.0) as i32) > bayer_threshold(4, x, y) as i32 { WHITE } else { BLACK };
            assert_eq!(s.pixel(0, 0, x, y), expect, "({x},{y})");
        }
    }
}

#[test]
fn set_pattern_and_dither_round_trip_through_the_dsl() {
    for (w, h, hex) in [(2u8, 2u8, "9"), (4, 4, "5a5a"), (8, 8, "ff00ff00ff00ff00"), (3, 5, "4a5f"), (16, 16, "8000000000000000000000000000000000000000000000000000000000000001")] {
        let p = Pattern::parse(w, h, hex).unwrap();
        let again = Pattern::parse(w, h, &p.hex()).unwrap();
        assert_eq!(p, again);
        let mut s = Session::empty();
        s.run_script(&format!("NewDocument(4,4)\n{}", p.to_dsl())).unwrap();
        assert_eq!(s.settings.pattern, Some(p));
    }
}

/// (name, script, pinned layer-0 hash)
const PINS: &[(&str, &str, &str)] = &[
    (
        "pixel_perfect_elbow_under_checker",
        "NewDocument(16,16)\nSelectTool(Pencil); SetPrimaryColor(#FF0000FF); SetBrushSize(1); SetPixelPerfect(true); SetPattern(2,2,9)\nStroke([(1,1),(2,1),(2,2),(3,2),(3,3),(4,3),(4,4),(8,4),(8,8)])",
        "9ebc4f3667876fcadbe51522c27cfc40",
    ),
    (
        "brush_round7_bayer4_half",
        "NewDocument(24,24)\nSelectTool(Brush); SetPrimaryColor(#FF0000FF); SetBrushShape(Round); SetBrushSize(7); SetPattern(4,4,5a5a)\nStroke([(4,4),(16,10),(19,19)])",
        "5e5dbe84cba55c55cb5d50a1d74fe8c1",
    ),
    (
        "bucket_lines_h2",
        "NewDocument(16,16)\nSelectTool(Pencil); SetPrimaryColor(#000000FF)\nStroke([(0,8),(15,8)])\nSelectTool(Bucket); SetPrimaryColor(#00FF00FF); SetPattern(1,2,1)\nTap(0,0)",
        "953e888fc6a90fa45d10d044db304908",
    ),
    (
        "gradient_linear_bayer4",
        "NewDocument(32,32)\nSelectTool(Gradient); SetGradientType(Linear); SetGradientStops(#FF0000FF@0,#0000FFFF@1); SetGradientDither(4)\nShapeSet(0,0,31,31); ShapeCommit()",
        "e8807f95e4c40350189d6f3a057e48c0",
    ),
    (
        "gradient_linear_bayer8_smoothstep_3stops",
        "NewDocument(32,32)\nSelectTool(Gradient); SetGradientType(Linear); SetGradientStops(#FF0000FF@0,#00FF00FF@0.5,#0000FFFF@1); SetGradientSmoothstep(true); SetGradientDither(8)\nShapeSet(2,3,29,20); ShapeCommit()",
        "89938838da1e1e64bad2c4989455d238",
    ),
    (
        "gradient_radial_bayer2",
        "NewDocument(32,32)\nSelectTool(Gradient); SetGradientType(Radial); SetGradientStops(#FFFFFFFF@0,#000000FF@1); SetGradientDither(2)\nShapeSet(16,16,30,16); ShapeCommit()",
        "fb38c5d421f07bc97fc1ad6004e83b2d",
    ),
];

#[test]
fn pattern_output_is_pinned() {
    for (name, script, pin) in PINS {
        assert_eq!(&hash_of(script), pin, "{name}: pinned hash moved — the change IS the bug");
    }
}

fn hash_of(script: &str) -> String {
    hash(&run(script), 0, 0)
}

#[test]
#[ignore]
fn print_pattern_pins() {
    for (name, script, _) in PINS {
        println!("{name}: {}", hash_of(script));
    }
}
