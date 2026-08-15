//! AA-OFF pin suite: literal layer-hash snapshots of every tool path the AA feature touches
//! (round/square Brush, Eraser via mouse and precision pen, Line/Rect/Ellipse/Triangle in
//! fill/outline × axis-aligned/rotated). The AA work (docs/aa-brush/DESIGN.md, ADR 0008) must
//! keep AA-OFF output bit-identical — these hashes are the machine check. If one ever changes,
//! the change IS the bug; do not re-pin without a deliberate, announced behavior change.
//!
//! Regenerate (after such an announced change) with:
//!   cargo test --test aa_off_pins print_pins -- --ignored --nocapture

use makapix_engine::util::hash_hex;
use makapix_engine::Session;

fn run(src: &str) -> Session {
    let mut s = Session::empty();
    s.run_script(src).expect("script ok");
    s
}

fn hash_of(script: &str) -> String {
    hash_hex(run(script).layer_hash(0, 0))
}

/// (name, script, pinned layer-0 hash)
const PINS: &[(&str, &str, &str)] = &[
    (
        "brush_round5",
        "NewDocument(24,24)\nSelectTool(Brush); SetPrimaryColor(#FF0000FF); SetBrushShape(Round); SetBrushSize(5)\nStroke([(4,4),(16,10),(19,19)])",
        "1adc7f01df66002d3d1006e39b32d501",
    ),
    (
        "brush_round1",
        "NewDocument(24,24)\nSelectTool(Brush); SetPrimaryColor(#FF0000FF); SetBrushShape(Round); SetBrushSize(1)\nStroke([(1,1),(2,1),(2,2),(3,2),(3,3)])",
        "dc8007ea7f887f62f1ed11e4ed68ad5c",
    ),
    (
        "brush_square4",
        "NewDocument(24,24)\nSelectTool(Brush); SetPrimaryColor(#FF0000FF); SetBrushShape(Square); SetBrushSize(4)\nStroke([(4,4),(16,10)])",
        "43723539bc9f233fdec5cebfe1fe209f",
    ),
    (
        "brush_semi_alpha_self_cross",
        "NewDocument(24,24)\nSelectTool(Brush); SetPrimaryColor(#00FF0080); SetBrushShape(Round); SetBrushSize(5)\nStroke([(4,4),(18,18),(4,18),(18,4)])",
        "f83b0c14cd4757d927642f079831cd71",
    ),
    (
        "brush_selection_clip",
        "NewDocument(24,24)\nSelectTool(SelectRect); PointerDown(6,6); PointerMove(15,15); PointerUp()\nSelectTool(Brush); SetPrimaryColor(#FF0000FF); SetBrushShape(Round); SetBrushSize(5)\nStroke([(4,4),(18,18)])",
        "7fa23e9e923ca9b97d0bc2f3b4ba216d",
    ),
    (
        "eraser_round5",
        "NewDocument(24,24)\nSetPrimaryColor(#0000FFFF); SelectAll(); FillSelection(); SelectNone()\nSelectTool(Eraser); SetBrushShape(Round); SetBrushSize(5)\nStroke([(4,4),(16,10),(19,19)])",
        "3a8f10ec338c19758689eeab145d4169",
    ),
    (
        "eraser_round1",
        "NewDocument(24,24)\nSetPrimaryColor(#0000FFFF); SelectAll(); FillSelection(); SelectNone()\nSelectTool(Eraser); SetBrushShape(Round); SetBrushSize(1)\nStroke([(1,1),(2,1),(2,2),(3,2),(3,3)])",
        "b5c49d4ec7f2b363c57d5deeed608d39",
    ),
    (
        "eraser_square3",
        "NewDocument(24,24)\nSetPrimaryColor(#0000FFFF); SelectAll(); FillSelection(); SelectNone()\nSelectTool(Eraser); SetBrushShape(Square); SetBrushSize(3)\nStroke([(4,4),(16,10)])",
        "c655a6d0a7836a03f1a3ea93b6e7f349",
    ),
    (
        "eraser_semi_alpha_field",
        "NewDocument(24,24)\nSetPrimaryColor(#0000FF80); SelectAll(); FillSelection(); SelectNone()\nSelectTool(Eraser); SetBrushShape(Round); SetBrushSize(5)\nStroke([(4,4),(16,10)])",
        "6e9d5577fc1d1a10b1a469e6a0c4a7b4",
    ),
    (
        "eraser_selection_clip",
        "NewDocument(24,24)\nSetPrimaryColor(#0000FFFF); SelectAll(); FillSelection(); SelectNone()\nSelectTool(SelectRect); PointerDown(6,6); PointerMove(15,15); PointerUp()\nSelectTool(Eraser); SetBrushShape(Round); SetBrushSize(5)\nStroke([(4,4),(18,18)])",
        "a36072aa4efca8790a39ef34e3f9a3f9",
    ),
    (
        "eraser_precision_pen",
        "NewDocument(24,24)\nSetPrimaryColor(#0000FFFF); SelectAll(); FillSelection(); SelectNone()\nSelectTool(Eraser); SetBrushShape(Round); SetBrushSize(3)\nSetCursor(3,3); CursorPenDown(); CursorStrokeBegin(); MoveCursor(9,4); CursorStrokeEnd(); CursorPenUp()",
        "d4a82079ccdda3d562f4bf47fe762225",
    ),
    (
        "line_w1",
        "NewDocument(24,24)\nSelectTool(Line); SetPrimaryColor(#FF0000FF); SetLineWidth(1)\nPointerDown(3,20); PointerMove(20,5); PointerUp()",
        "cf35c3092f9069ca2a7560a1c85eac72",
    ),
    (
        "line_w4",
        "NewDocument(24,24)\nSelectTool(Line); SetPrimaryColor(#FF0000FF); SetLineWidth(4)\nPointerDown(3,20); PointerMove(20,5); PointerUp()",
        "f49fb9750a528504ad290c52dc83adda",
    ),
    (
        "rect_fill",
        "NewDocument(24,24)\nSelectTool(Rectangle); SetPrimaryColor(#FF0000FF); SetShapeFill(true)\nPointerDown(3,3); PointerMove(18,12); PointerUp()",
        "50f124e610c6b36dd7bf5af4f8897a3d",
    ),
    (
        "rect_outline_w2",
        "NewDocument(24,24)\nSelectTool(Rectangle); SetPrimaryColor(#FF0000FF); SetShapeFill(false); SetLineWidth(2)\nPointerDown(3,3); PointerMove(18,12); PointerUp()",
        "b5bba1c610f56c85edba2a852b86b22d",
    ),
    (
        "ellipse_fill",
        "NewDocument(24,24)\nSelectTool(Ellipse); SetPrimaryColor(#FF0000FF); SetShapeFill(true)\nPointerDown(3,3); PointerMove(18,12); PointerUp()",
        "8affb381a7304e05f44300a9f3eb4a75",
    ),
    (
        "ellipse_outline_w2",
        "NewDocument(24,24)\nSelectTool(Ellipse); SetPrimaryColor(#FF0000FF); SetShapeFill(false); SetLineWidth(2)\nPointerDown(3,3); PointerMove(18,12); PointerUp()",
        "5667aa1142a4ea8dbb9139ea8a397475",
    ),
    (
        "rect_rot_fill",
        "NewDocument(24,24)\nSelectTool(Rectangle); SetPrimaryColor(#FF0000FF); SetShapeFill(true)\nShapeSet(3,3,20,16); SetShapeRotation(300); ShapeCommit()",
        "6a93c25694a4d951e538ddae159a1405",
    ),
    (
        "rect_rot_outline_w2",
        "NewDocument(24,24)\nSelectTool(Rectangle); SetPrimaryColor(#FF0000FF); SetShapeFill(false); SetLineWidth(2)\nShapeSet(3,3,20,16); SetShapeRotation(300); ShapeCommit()",
        "8f7ca1657a5acecd4a4e61d2a8af8ce1",
    ),
    (
        "ellipse_rot_fill",
        "NewDocument(24,24)\nSelectTool(Ellipse); SetPrimaryColor(#FF0000FF); SetShapeFill(true)\nShapeSet(3,3,20,16); SetShapeRotation(300); ShapeCommit()",
        "d401fe30456fba7d49f0fb6582faa629",
    ),
    (
        "ellipse_rot_outline_w2",
        "NewDocument(24,24)\nSelectTool(Ellipse); SetPrimaryColor(#FF0000FF); SetShapeFill(false); SetLineWidth(2)\nShapeSet(3,3,20,16); SetShapeRotation(300); ShapeCommit()",
        "441734b864f3a539ef18d2fe73abc401",
    ),
    (
        "triangle_fill_tip",
        "NewDocument(24,24)\nSelectTool(Triangle); SetPrimaryColor(#FF0000FF); SetShapeFill(true)\nShapeSet(3,3,20,18); SetTriangleTip(400); ShapeCommit()",
        "db3364c0f553635c3d7f93af765b2ba6",
    ),
    (
        "triangle_outline_w2",
        "NewDocument(24,24)\nSelectTool(Triangle); SetPrimaryColor(#FF0000FF); SetShapeFill(false); SetLineWidth(2)\nShapeSet(3,3,20,18); ShapeCommit()",
        "4dd3ba80020c979eb003687f55069b8a",
    ),
    (
        "triangle_rot_fill",
        "NewDocument(24,24)\nSelectTool(Triangle); SetPrimaryColor(#FF0000FF); SetShapeFill(true)\nShapeSet(3,3,20,18); SetShapeRotation(300); ShapeCommit()",
        "f9b63e194860be0ece14297264344016",
    ),
];

#[test]
fn aa_off_output_is_pinned() {
    for (name, script, expected) in PINS {
        assert_eq!(&hash_of(script), expected, "AA-OFF output changed for pin '{name}'");
    }
}

/// Every pinned scenario must actually draw something — a hash of an empty layer would pin
/// nothing and hide a broken script.
#[test]
fn pins_are_not_empty() {
    let empty = hash_hex(run("NewDocument(24,24)").layer_hash(0, 0));
    for (name, script, _) in PINS {
        assert_ne!(hash_of(script), empty, "pin '{name}' drew nothing");
    }
}

/// Hash harvester: prints the table values. Run after a DELIBERATE behavior change only.
#[test]
#[ignore]
fn print_pins() {
    for (name, script, _) in PINS {
        println!("(\"{name}\", \"{}\")", hash_of(script));
    }
}
