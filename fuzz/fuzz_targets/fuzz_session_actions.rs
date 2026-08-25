#![no_main]
//! Structure-aware fuzz of the DSL + `Session` state machine (docs/fuzzing/ANALYSIS.md §2.2).
//!
//! libFuzzer's byte string is decoded (via `arbitrary`) into a sequence of *valid,
//! interestingly-interleaved* editor actions — the F-29 class of bug (change the active
//! layer mid-stroke) lives in interleavings no human writes as a test. The sequence is
//! rendered to DSL text and run through `run_script`, i.e. the exact path the Flutter
//! shell, the journal replay, and the CLI all use.
//!
//! Compound oracle after the sequence:
//!   1. No panic (crash oracle, always on).
//!   2. Undo coherence: if `Undo()` changes the document, `Redo()` must restore the
//!      exact content hash.
//!   3. Round-trip: save → load → identical content hash, byte-identical resave.

use arbitrary::Arbitrary;
use libfuzzer_sys::fuzz_target;
use makapix_engine::Session;
use std::fmt::Write;

#[derive(Arbitrary, Debug, Clone, Copy)]
enum Tool {
    Pencil,
    Brush,
    Airbrush,
    AirbrushSoft,
    AirbrushMist,
    Eraser,
    Bucket,
    Gradient,
    Dodge,
    Burn,
    Move,
    Eyedropper,
    Line,
    Rectangle,
    Ellipse,
    Triangle,
    SelectRect,
    SelectEllipse,
    SelectFree,
    SelectByColor,
    SelectLayer,
    HsvShift,
    BrightnessContrast,
    Levels,
    CopyPaste,
}

impl Tool {
    fn name(self) -> &'static str {
        match self {
            Tool::Pencil => "Pencil",
            Tool::Brush => "Brush",
            Tool::Airbrush => "Airbrush",
            Tool::AirbrushSoft => "AirbrushSoft",
            Tool::AirbrushMist => "AirbrushMist",
            Tool::Eraser => "Eraser",
            Tool::Bucket => "Bucket",
            Tool::Gradient => "Gradient",
            Tool::Dodge => "Dodge",
            Tool::Burn => "Burn",
            Tool::Move => "Move",
            Tool::Eyedropper => "Eyedropper",
            Tool::Line => "Line",
            Tool::Rectangle => "Rectangle",
            Tool::Ellipse => "Ellipse",
            Tool::Triangle => "Triangle",
            Tool::SelectRect => "SelectRect",
            Tool::SelectEllipse => "SelectEllipse",
            Tool::SelectFree => "SelectFree",
            Tool::SelectByColor => "SelectByColor",
            Tool::SelectLayer => "SelectLayer",
            Tool::HsvShift => "HsvShift",
            Tool::BrightnessContrast => "BrightnessContrast",
            Tool::Levels => "Levels",
            Tool::CopyPaste => "CopyPaste",
        }
    }
}

/// One editor action. Argument types are chosen to keep values *near* the interesting
/// ranges: `i8` pointer coordinates straddle a 32×32 canvas (in-bounds, gutter, and
/// out-of-bounds negatives), `u8` indices overshoot the 64-layer cap and often the
/// frame count. The huge-coordinate class (F-6) keeps one dedicated raw variant.
#[derive(Arbitrary, Debug)]
enum Act {
    SelectTool(Tool),
    PointerDown(i8, i8),
    PointerMove(i8, i8),
    PointerUp,
    PointerDownRaw(i32, i32),
    PointerMoveRaw(i32, i32),
    CancelStroke,
    Tap(i8, i8),
    ShapeSet(i8, i8, i8, i8),
    ShapeCommit,
    ShapeCancel,
    SetShapeFill(bool),
    SetLineWidth(u8),
    SetBrushSize(u8),
    SetPrimaryColor(u32),
    SetSecondaryColor(u32),
    AddFrame,
    AddFrameAt(u8),
    DuplicateFrame(u8),
    RemoveFrame(u8),
    ReorderFrame(u8, u8),
    SetActiveFrame(u8),
    SetFrameDuration(u8, u8),
    AddLayer,
    AddLayerAt(u8),
    RemoveLayer(u8),
    DuplicateLayer(u8),
    MergeDown(u8),
    ReorderLayer(u8, u8),
    SetActiveLayer(u8),
    SetLayerOpacity(u8, u8),
    SetLayerVisible(u8, bool),
    SetLayerLocked(u8, bool),
    Undo,
    Redo,
    SelectAll,
    SelectNone,
    InvertSelection,
    SelectByAlphaReplace,
    Copy,
    Cut,
    Paste,
    PasteToFrame(u8),
    FillSelection,
    ClearSelection,
    FillNoise(u16),
    FlipH,
    FlipV,
    FlipFrameH,
    Invert,
    Rotate(u8),
    RotateLayer(u8),
    NudgeLayers(i8, i8),
    ResizeCanvas(u8, u8),
    CropToSelection,
    SetLevels(u8, i8, u8),
    ApplyLevels,
    SetHsvShift(i8, i8, i8),
    ApplyHsvShift,
    SetBrightnessContrast(i8, i8),
    ApplyBrightnessContrast,
    SetAA(bool),
    SetContiguous(bool),
    SetPixelPerfect(bool),
    SetWrap(bool),
    AddPaletteColor(u32),
    RemovePaletteColor(u8),
}

fn render(act: &Act, out: &mut String) {
    match act {
        Act::SelectTool(t) => writeln!(out, "SelectTool({})", t.name()),
        Act::PointerDown(x, y) => writeln!(out, "PointerDown({},{})", x, y),
        Act::PointerMove(x, y) => writeln!(out, "PointerMove({},{})", x, y),
        Act::PointerUp => writeln!(out, "PointerUp()"),
        Act::PointerDownRaw(x, y) => writeln!(out, "PointerDown({},{})", x, y),
        Act::PointerMoveRaw(x, y) => writeln!(out, "PointerMove({},{})", x, y),
        Act::CancelStroke => writeln!(out, "CancelStroke()"),
        Act::Tap(x, y) => writeln!(out, "Tap({},{})", x, y),
        Act::ShapeSet(ax, ay, bx, by) => writeln!(out, "ShapeSet({},{},{},{})", ax, ay, bx, by),
        Act::ShapeCommit => writeln!(out, "ShapeCommit()"),
        Act::ShapeCancel => writeln!(out, "ShapeCancel()"),
        Act::SetShapeFill(b) => writeln!(out, "SetShapeFill({})", b),
        Act::SetLineWidth(w) => writeln!(out, "SetLineWidth({})", w),
        Act::SetBrushSize(s) => writeln!(out, "SetBrushSize({})", s),
        Act::SetPrimaryColor(c) => writeln!(out, "SetPrimaryColor(#{:08X})", c),
        Act::SetSecondaryColor(c) => writeln!(out, "SetSecondaryColor(#{:08X})", c),
        Act::AddFrame => writeln!(out, "AddFrame()"),
        Act::AddFrameAt(i) => writeln!(out, "AddFrameAt({})", i),
        Act::DuplicateFrame(i) => writeln!(out, "DuplicateFrame({})", i),
        Act::RemoveFrame(i) => writeln!(out, "RemoveFrame({})", i),
        Act::ReorderFrame(a, b) => writeln!(out, "ReorderFrame({},{})", a, b),
        Act::SetActiveFrame(i) => writeln!(out, "SetActiveFrame({})", i),
        Act::SetFrameDuration(i, ms) => writeln!(out, "SetFrameDuration({},{})", i, ms),
        Act::AddLayer => writeln!(out, "AddLayer()"),
        Act::AddLayerAt(i) => writeln!(out, "AddLayerAt({})", i),
        Act::RemoveLayer(i) => writeln!(out, "RemoveLayer({})", i),
        Act::DuplicateLayer(i) => writeln!(out, "DuplicateLayer({})", i),
        Act::MergeDown(i) => writeln!(out, "MergeDown({})", i),
        Act::ReorderLayer(a, b) => writeln!(out, "ReorderLayer({},{})", a, b),
        Act::SetActiveLayer(i) => writeln!(out, "SetActiveLayer({})", i),
        Act::SetLayerOpacity(i, o) => writeln!(out, "SetLayerOpacity({},{})", i, o),
        Act::SetLayerVisible(i, v) => writeln!(out, "SetLayerVisible({},{})", i, v),
        Act::SetLayerLocked(i, v) => writeln!(out, "SetLayerLocked({},{})", i, v),
        Act::Undo => writeln!(out, "Undo()"),
        Act::Redo => writeln!(out, "Redo()"),
        Act::SelectAll => writeln!(out, "SelectAll()"),
        Act::SelectNone => writeln!(out, "SelectNone()"),
        Act::InvertSelection => writeln!(out, "InvertSelection()"),
        Act::SelectByAlphaReplace => writeln!(out, "SelectByAlpha(Replace)"),
        Act::Copy => writeln!(out, "Copy()"),
        Act::Cut => writeln!(out, "Cut()"),
        Act::Paste => writeln!(out, "Paste()"),
        Act::PasteToFrame(i) => writeln!(out, "PasteToFrame({})", i),
        Act::FillSelection => writeln!(out, "FillSelection()"),
        Act::ClearSelection => writeln!(out, "ClearSelection()"),
        Act::FillNoise(seed) => writeln!(out, "FillNoise({})", seed),
        Act::FlipH => writeln!(out, "FlipH()"),
        Act::FlipV => writeln!(out, "FlipV()"),
        Act::FlipFrameH => writeln!(out, "FlipFrameH()"),
        Act::Invert => writeln!(out, "Invert()"),
        Act::Rotate(q) => writeln!(out, "Rotate({})", q),
        Act::RotateLayer(q) => writeln!(out, "RotateLayer({})", q),
        Act::NudgeLayers(dx, dy) => writeln!(out, "NudgeLayers({},{})", dx, dy),
        // Clamp to the legal 1..=64 band so resizes usually succeed (the reject path
        // is cheap to reach; the interesting bugs are in successful resizes).
        Act::ResizeCanvas(w, h) => writeln!(
            out,
            "ResizeCanvas({},{})",
            (*w as u16 % 64) + 1,
            (*h as u16 % 64) + 1
        ),
        Act::CropToSelection => writeln!(out, "CropToSelection()"),
        Act::SetLevels(lo, mid, hi) => writeln!(out, "SetLevels({},{},{})", lo, mid, hi),
        Act::ApplyLevels => writeln!(out, "ApplyLevels()"),
        Act::SetHsvShift(h, s, v) => writeln!(out, "SetHsvShift({},{},{})", h, s, v),
        Act::ApplyHsvShift => writeln!(out, "ApplyHsvShift()"),
        Act::SetBrightnessContrast(b, c) => {
            writeln!(out, "SetBrightnessContrast({},{})", b, c)
        }
        Act::ApplyBrightnessContrast => writeln!(out, "ApplyBrightnessContrast()"),
        Act::SetAA(b) => writeln!(out, "SetAA({})", b),
        Act::SetContiguous(b) => writeln!(out, "SetContiguous({})", b),
        Act::SetPixelPerfect(b) => writeln!(out, "SetPixelPerfect({})", b),
        Act::SetWrap(b) => writeln!(out, "SetWrap({})", b),
        Act::AddPaletteColor(c) => writeln!(out, "AddPaletteColor(#{:08X})", c),
        Act::RemovePaletteColor(i) => writeln!(out, "RemovePaletteColor({})", i),
    }
    .expect("write! to String cannot fail");
}

fuzz_target!(|acts: Vec<Act>| {
    let mut script = String::new();
    for act in acts.iter().take(64) {
        render(act, &mut script);
    }

    let mut sess = Session::new(32, 32);
    let _ = sess.run_script(&script);

    // Settle open interactions before the semantic oracles: a sequence ending
    // mid-stroke leaves painted pixels whose undo entry only lands on PointerUp, so
    // the final oracles demand a settled state (see docs/fuzzing/FINDINGS.md FZ-1).
    // Mid-sequence Undo still explores the unsettled class under the crash oracle.
    let _ = sess.run_script(
        "PointerUp()\nShapeCancel()\nPasteCancel()\nMoveDraftCancel()\n\
         RotateDraftCancel()\nScaleDraftCancel()\nMoveSelectionCommit()",
    );

    // Oracle 2 — undo coherence. Driven through the DSL itself so no private API is
    // needed: if Undo() is a no-op (empty stack, or the last entry restores identical
    // content) the check conservatively skips.
    let after = sess.doc.content_hash();
    let _ = sess.run_script("Undo()");
    if sess.doc.content_hash() != after {
        let undone = sess.doc.content_hash();
        let _ = sess.run_script("Redo()");
        if sess.doc.content_hash() != after {
            panic!(
                "Undo changed the document but Redo did not restore it\n\
                 after={:?} undone={:?} redone={:?}\n--- script ---\n{}--- end ---",
                after,
                undone,
                sess.doc.content_hash(),
                script
            );
        }
    }

    // Oracle 3 — round-trip + byte determinism, from whatever state the sequence
    // (possibly mid-stroke, mid-paste, mid-draft) left behind: the FFI contract says
    // save may be called at any time.
    let saved = sess.save_bytes();
    let mut reloaded = Session::empty();
    if reloaded.load_bytes(&saved).is_err() {
        panic!(
            "document produced by an action sequence failed to reload\n--- script ---\n{}--- end ---",
            script
        );
    }
    if reloaded.doc.content_hash() != sess.doc.content_hash() {
        panic!(
            "round-trip content hash mismatch after action sequence\n--- script ---\n{}--- end ---",
            script
        );
    }
    let resaved = reloaded.save_bytes();
    if resaved != saved {
        let diff = saved
            .iter()
            .zip(resaved.iter())
            .position(|(a, b)| a != b)
            .unwrap_or(saved.len().min(resaved.len()));
        panic!(
            "resave is not byte-deterministic after action sequence\n\
             len {} vs {}, first diff at byte {}\n--- script ---\n{}--- end ---",
            saved.len(),
            resaved.len(),
            diff,
            script
        );
    }
});
