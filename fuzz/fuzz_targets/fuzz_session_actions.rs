#![no_main]
//! Structure-aware fuzz of the DSL + `Session` state machine (docs/fuzzing/ANALYSIS.md §2.2).
//!
//! libFuzzer's byte string is decoded (via `arbitrary`) into a starting document plus a
//! sequence of *valid, interestingly-interleaved* editor actions — the F-29 class of bug
//! (change the active layer mid-stroke) and the FZ-4/FZ-5 class (a draft or drag left open
//! when a structural verb arrives) live in interleavings no human writes as a test. Each
//! action is rendered to DSL text and run through `run_script`, i.e. the exact path the
//! Flutter shell, the journal replay, and the CLI all use.
//!
//! Actions render one at a time against the live session, so indices land near the real
//! frame/layer counts and a preview verb can rewind to the value it found (the shell's
//! preview/commit protocol). A line the parser rejects changes nothing, so it is dropped
//! from the recorded script: the script in a panic message replays the run exactly.
//!
//! The alphabet covers every parser verb (`crates/engine/src/session/parse.rs`) except the
//! ones excluded below with a reason; `crates/engine/tests/fuzz_alphabet.rs` fails when a
//! parser verb is neither rendered here nor excluded (fuzzing-review W2).
//!
//! excluded verb: SetMemBudget — tiny budgets need their own oracle (fuzzing-review W7)
//!
//! Compound oracle after the sequence:
//!   1. No panic (crash oracle, always on).
//!   2. Undo coherence: if `Undo()` changes the document, `Redo()` must restore the
//!      exact content hash.
//!   3. Round-trip: save → load → identical content hash, byte-identical resave.

use arbitrary::Arbitrary;
use libfuzzer_sys::fuzz_target;
use makapix_engine::Session;

#[derive(Arbitrary, Debug, Clone, Copy)]
enum Tool {
    Pencil,
    PrecisionPencil,
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
    MoveLayer,
    Eyedropper,
    Line,
    Rectangle,
    Ellipse,
    Triangle,
    SelectRect,
    SelectEllipse,
    SelectCircle,
    SelectPoly,
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
            Tool::PrecisionPencil => "PrecisionPencil",
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
            Tool::MoveLayer => "MoveLayer",
            Tool::Eyedropper => "Eyedropper",
            Tool::Line => "Line",
            Tool::Rectangle => "Rectangle",
            Tool::Ellipse => "Ellipse",
            Tool::Triangle => "Triangle",
            Tool::SelectRect => "SelectRect",
            Tool::SelectEllipse => "SelectEllipse",
            Tool::SelectCircle => "SelectCircle",
            Tool::SelectPoly => "SelectPoly",
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

/// The document the sequence starts from. `Blank` is the historical 32×32; `Tiny` is the
/// canvas where `clamp_pointer` collapses distinct inputs (the FZ-5 trigger); `Rich` is a
/// small multi-frame, multi-layer document with blend, opacity, and off-canvas pixels, so
/// structural verbs have something to chew on from the first action.
#[derive(Arbitrary, Debug, Clone, Copy)]
enum Start {
    Blank,
    Tiny(u8, u8),
    Rich(u8),
}

/// A frame set or layer set (ADR 0031/0033), rendered against the live count: a range
/// starting at `a` spanning `b % 4` more, plus an optional single index from `c`.
#[derive(Arbitrary, Debug, Clone, Copy)]
struct Set(u8, u8, u8);

/// Names come from a small alphabet so the by-name batch verbs find matches: two default
/// layer names, a comma (the first-comma split rule), empty, non-ASCII, and a long one.
#[derive(Arbitrary, Debug, Clone, Copy)]
struct Name(u8);

const NAMES: [&str; 8] = [
    "Layer 1",
    "Layer 2",
    "a",
    "a, b",
    "",
    "ü€",
    "Layer 1 copy",
    "0123456789012345678901234567890123456789012345678901234567890123",
];

const BLENDS: [&str; 11] = [
    "Normal", "Multiply", "Screen", "Overlay", "Darken", "Lighten", "Addition", "Subtract",
    "Difference", "Exclusion", "HardLight",
];

const COMBINE: [&str; 4] = ["Replace", "Add", "Subtract", "Intersect"];

const DITHERS: [&str; 19] = [
    "0", "2", "4", "8", "3", "blue", "halftone4", "halftone8", "hlines2", "hlines4", "hlines8",
    "vlines2", "vlines4", "vlines8", "diag4", "diag8", "noise", "ign", "junk",
];

const ANCHORS: [&str; 9] = [
    "TopLeft", "Top", "TopRight", "Left", "Center", "Right", "BottomLeft", "Bottom", "BottomRight",
];

/// Pointer and shape input. Argument types keep values *near* the interesting ranges: `i8`
/// coordinates straddle a 32×32 canvas (in-bounds, gutter, out-of-bounds negatives); the
/// huge-coordinate class (F-6) keeps dedicated raw variants.
#[derive(Arbitrary, Debug)]
enum PointerAct {
    SelectTool(Tool),
    PointerDown(i8, i8),
    PointerMove(i8, i8),
    PointerUp,
    PointerDownRaw(i32, i32),
    PointerMoveRaw(i32, i32),
    CancelStroke,
    Tap(i8, i8),
    Stroke(Vec<(i8, i8)>),
    ShapeSet(i8, i8, i8, i8),
    SetShapeRotation(i16),
    SetTriangleTip(i16),
    ShapeCommit,
    ShapeCancel,
}

/// The Precision-mode reticle pen: Hold, drag segments, and the one-shot cursor tools. The
/// open pen segment is settled state like a stroke, so it belongs to the FZ-1 class.
#[derive(Arbitrary, Debug)]
enum CursorAct {
    SetCursor(i8, i8),
    MoveCursor(i8, i8),
    CursorPenDown,
    CursorPenUp,
    CursorStrokeBegin,
    CursorStrokeEnd,
    PlotCursor,
    AirbrushCursor,
    EyedropCursor,
    SelectColorCursor,
    FillCursor,
}

/// Selections, the clipboard, and every draft family — the open-edit verbs whose
/// interleaving with structural changes produced FZ-1, FZ-4, and FZ-5.
#[derive(Arbitrary, Debug)]
enum DraftAct {
    SelectAll,
    SelectNone,
    InvertSelection,
    SelectByAlpha(u8),
    MoveSelection(i8, i8),
    MoveSelectionBegin,
    MoveSelectionCommit,
    Copy,
    Cut,
    Paste,
    PasteToFrame(u8),
    PasteDraft,
    PasteMove(i8, i8),
    PasteCommit,
    PasteCancel,
    MaskDraft(i8, i8, u8, u8, [u8; 4]),
    MaskDraftMove(i8, i8),
    MaskDraftCancel,
    MaskStamp(i8, i8, u8, u8, [u8; 4]),
    MoveDraftBegin,
    MoveDraftMove(i8, i8),
    MoveDraftCommit,
    MoveDraftCancel,
    RotateDraftBegin,
    RotateDraftBeginFrame,
    RotateDraftSetAngle(i16),
    RotateDraftMove(i8, i8),
    RotateDraftCommit,
    RotateDraftCancel,
    ScaleDraftBegin,
    ScaleDraftBeginFrame,
    ScaleDraftSet(u8, u8),
    ScaleDraftMove(i8, i8),
    ScaleDraftCommit,
    ScaleDraftCancel,
    FillSelection,
    ClearSelection,
    CropToSelection,
}

#[derive(Arbitrary, Debug)]
enum FrameAct {
    NewDocument(u8, u8),
    AddFrame,
    AddFrameAt(u8),
    DuplicateFrame(u8),
    RemoveFrame(u8),
    ReorderFrame(u8, u8),
    SetActiveFrame(u8),
    SetFrameDuration(u8, u16),
    SetAllDurations(u16),
    SetLoopMode(u8),
    RemoveFrames(Set),
    DuplicateFrames(Set),
    RepeatFramesAfter(Set),
    InsertBlankFrames(Set, bool),
    ShiftFrames(Set, i8),
    ReverseFrames(Set),
    SetFrameDurations(Set, u16),
    ScaleFrameDurations(Set, u16),
    FlipFramesH(Set),
    FlipFramesV(Set),
    RotateFrames(Set, u8),
    InvertFrames(Set),
    CopyLayerToFrames(Set),
    RemoveLayersNamed(Set, Name),
    SetLayersVisibleNamed(Set, bool, Name),
    SetLayersLockedNamed(Set, bool, Name),
    DuplicateLayerToFrames(Vec<u8>),
    // Collapsing a frame's stack (ADR 0038).
    FlattenFrames(Set),
    MergeVisible(Set),
}

#[derive(Arbitrary, Debug)]
enum LayerAct {
    AddLayer,
    AddLayerAt(u8),
    RemoveLayer(u8),
    DuplicateLayer(u8),
    MergeDown(u8),
    ReorderLayer(u8, u8),
    SetActiveLayer(u8),
    SetActiveLayers(Vec<u8>),
    SetMoveGroup(Vec<u8>),
    NudgeLayers(i8, i8),
    NudgeMove(i8, i8),
    SetLayerOpacity(u8, u8),
    /// The opacity slider drag: previews, then the rewind to the pre-drag value, then the
    /// one committing `SetLayerOpacity` (or none, for a cancelled drag).
    OpacityDrag(u8, Vec<u8>, Option<u8>),
    SetLayerVisible(u8, bool),
    SetLayerLocked(u8, bool),
    SetLayerBlend(u8, u8),
    /// The blend picker: taps preview, close rewinds, then commits if the choice changed.
    BlendPick(u8, Vec<u8>, Option<u8>),
    RenameLayer(u8, Name),
    RemoveLayers(Set),
    DuplicateLayers(Set),
    MergeLayers(Set),
    ShiftLayers(Set, i8),
    ReverseLayers(Set),
    InsertBlankLayers(Set, bool),
    SetLayersVisible(Set, bool),
    SetLayersLocked(Set, bool),
    SetLayersOpacity(Set, u8),
    SetLayersBlend(Set, u8),
    ResetLayers(Set),
    RenameLayers(Set, Name),
    FlipLayersH(Set),
    FlipLayersV(Set),
    RotateLayers(Set, u8),
    InvertLayers(Set),
    ClearLayers(Set),
    CopyLayersToFrames(Set, Set),
}

#[derive(Arbitrary, Debug)]
enum SettingAct {
    SetPrimaryColor(u32),
    SetSecondaryColor(u32),
    SetBrushSize(u8),
    SetBrushShape(bool),
    SetIntensity(u8),
    SetSpacing(u8),
    SetThreshold(u8),
    SetAlphaCutoff(u8),
    SetContiguous(bool),
    SetDiagonal(bool),
    SetFillAllLayers(bool),
    SetGradientType(bool),
    SetGradientStops(Vec<(u32, u8)>),
    SetGradientSmoothstep(bool),
    SetGradientDither(u8),
    SetSelectionMode(u8),
    SetShapeFill(bool),
    SetLineWidth(u8),
    SetProtectPixels(bool),
    SetWrap(bool),
    SetPixelPerfect(bool),
    SetAA(bool),
    /// ADR 0025: sides 1..=16 (the wire cap) with up to 64 bits of the tile; a tile whose set
    /// bits exceed w*h is rejected by the parser — that path is fuzzed on purpose.
    SetPattern(u8, u8, u64),
    SetPatternOff,
    SetSymmetry(u8, Option<i8>, Option<i8>),
    SetOverscanView(bool),
    SetCleanEdge(bool),
    SetCleanEdgeWidth(u8),
    SetScaleCleanEdge(bool),
    SetScaleCleanEdgeWidth(u8),
    SetEyedropSource(bool),
    SetSelectColorSource(bool),
    SetCopySource(bool),
    SetHsvShift(i8, i8, i8),
    SetHsvScope(bool),
    SetBrightnessContrast(i8, i8),
    SetBcScope(bool),
    SetLevels(u8, i8, u8),
    SetLevelsScope(bool),
    SetSeed(u64),
}

#[derive(Arbitrary, Debug)]
enum EditAct {
    ApplyLevels,
    ApplyHsvShift,
    ApplyBrightnessContrast,
    ReplaceColor(u32, u32, u8, u8),
    Outline(u32, bool, bool, u8),
    FillNoise(u16),
    FlipH,
    FlipV,
    FlipFrameH,
    FlipFrameV,
    FlipCanvasH,
    FlipCanvasV,
    Invert,
    InvertFrame,
    Rotate(u8),
    RotateLayer(u8),
    RotateFrame(u8),
    ScaleLayer(u8, u8),
    ScaleFrame(u8, u8),
    ResizeCanvas(u8, u8, u8),
    CropCanvas(u8, u8, u8, u8),
    Repeat,
}

#[derive(Arbitrary, Debug)]
enum PaletteAct {
    AddPaletteColor(u32),
    RemovePaletteColor(u8),
    EditPaletteColor(u8, u32),
    DuplicatePaletteColor(u8),
    NamePaletteColor(u8, Name),
    SwapPaletteColors(u8, u8),
    NewPalette(Name),
    RenamePalette(Name),
    SetActivePalette(u8),
    ClearPalette,
    DeletePalette(u8),
    DuplicatePalette(u8),
    MovePalette(u8, u8),
    RenamePaletteAt(u8, Name),
    ClearPaletteAt(u8),
    SortPalette,
    SortPaletteAt(u8),
}

#[derive(Arbitrary, Debug)]
enum HistoryAct {
    Undo,
    Redo,
    ClearHistory,
    Play,
    Pause,
    AdvanceClock(u16),
}

/// One editor action. The variant list doubles as a weighting: `arbitrary` picks variants
/// uniformly, so the groups that build state (pointer, drafts) appear more than once and the
/// ~200-verb alphabet doesn't drown the stroke and draft sequences the history bugs need.
#[derive(Arbitrary, Debug)]
enum Act {
    Pointer(PointerAct),
    Pointer2(PointerAct),
    Pointer3(PointerAct),
    Cursor(CursorAct),
    Draft(DraftAct),
    Draft2(DraftAct),
    Frame(FrameAct),
    Layer(LayerAct),
    Layer2(LayerAct),
    Setting(SettingAct),
    Edit(EditAct),
    Palette(PaletteAct),
    History(HistoryAct),
    History2(HistoryAct),
}

/// An index near `n` live items: usually `0..=n` (one past the end included), sometimes a
/// raw overshoot.
fn idx(b: u8, n: usize) -> usize {
    if b < 224 {
        b as usize % (n + 1)
    } else {
        b as usize
    }
}

/// `w,h,hexbits` for a small canonical mask (ADR 0039): 1..=8 wide, 1..=4 tall, the bits
/// trimmed to `w*h` so the parser accepts every one.
fn mask_args(w: u8, h: u8, bits: &[u8; 4]) -> String {
    let (w, h) = (1 + w as usize % 8, 1 + h as usize % 4);
    let n = (w * h).div_ceil(8);
    let mut hex = String::new();
    for (k, b) in bits.iter().take(n).enumerate() {
        let live = (w * h - k * 8).min(8);
        hex.push_str(&format!("{:02x}", if live == 8 { *b } else { b & ((1u8 << live) - 1) }));
    }
    format!("{},{},{}", w, h, hex)
}

fn set(s: Set, n: usize) -> String {
    let lo = idx(s.0, n);
    let hi = lo + (s.1 % 4) as usize;
    let mut out = if hi == lo { lo.to_string() } else { format!("{}-{}", lo, hi) };
    if s.2 & 1 == 1 {
        out.push_str(&format!(" {}", idx(s.2 >> 1, n)));
    }
    out
}

fn name(n: Name) -> &'static str {
    NAMES[n.0 as usize % NAMES.len()]
}

fn blend(b: u8) -> &'static str {
    BLENDS[b as usize % BLENDS.len()]
}

fn ints(v: &[u8], n: usize) -> String {
    v.iter().take(8).map(|&b| idx(b, n).to_string()).collect::<Vec<_>>().join(",")
}

/// A canvas side: usually the cheap 1..=64 band where most interleavings live, occasionally
/// 72..=184 (several 32-px tiles past it). Never the 512 cap: under the fuzz build's
/// instrumentation a few frame rotations of a 512x512 multi-layer document take 30 s, every
/// such input became a timeout artifact, and libFuzzer's taste for 0xFF made 512 the most
/// common large size. The cap itself is covered by the loader's boundary seeds and the
/// engine tests; the interleavings this target hunts behave the same at 184.
fn side(b: u8) -> u16 {
    match b {
        0..=239 => (b as u16 % 64) + 1,
        240..=254 => 64 + (b as u16 - 239) * 8,
        255 => 33, // libFuzzer's favorite byte: keep it cheap (one past a tile edge)
    }
}

/// Render `act` against the live session into one or more DSL lines.
fn render(act: &Act, sess: &Session, out: &mut Vec<String>) {
    let frames = sess.doc.frames.len();
    let layers = sess.doc.active_frame().layers.len();
    let mut l = |s: String| out.push(s);
    match act {
        Act::Pointer(a) | Act::Pointer2(a) | Act::Pointer3(a) => match a {
            PointerAct::SelectTool(t) => l(format!("SelectTool({})", t.name())),
            PointerAct::PointerDown(x, y) => l(format!("PointerDown({},{})", x, y)),
            PointerAct::PointerMove(x, y) => l(format!("PointerMove({},{})", x, y)),
            PointerAct::PointerUp => l("PointerUp()".into()),
            PointerAct::PointerDownRaw(x, y) => l(format!("PointerDown({},{})", x, y)),
            PointerAct::PointerMoveRaw(x, y) => l(format!("PointerMove({},{})", x, y)),
            PointerAct::CancelStroke => l("CancelStroke()".into()),
            PointerAct::Tap(x, y) => l(format!("Tap({},{})", x, y)),
            PointerAct::Stroke(pts) => {
                if !pts.is_empty() {
                    let p: Vec<String> =
                        pts.iter().take(16).map(|(x, y)| format!("({},{})", x, y)).collect();
                    l(format!("Stroke([{}])", p.join(",")));
                }
            }
            PointerAct::ShapeSet(ax, ay, bx, by) => {
                l(format!("ShapeSet({},{},{},{})", ax, ay, bx, by))
            }
            PointerAct::SetShapeRotation(m) => l(format!("SetShapeRotation({})", m)),
            PointerAct::SetTriangleTip(t) => l(format!("SetTriangleTip({})", t)),
            PointerAct::ShapeCommit => l("ShapeCommit()".into()),
            PointerAct::ShapeCancel => l("ShapeCancel()".into()),
        },
        Act::Cursor(a) => match a {
            CursorAct::SetCursor(x, y) => l(format!("SetCursor({},{})", x, y)),
            CursorAct::MoveCursor(dx, dy) => l(format!("MoveCursor({},{})", dx, dy)),
            CursorAct::CursorPenDown => l("CursorPenDown()".into()),
            CursorAct::CursorPenUp => l("CursorPenUp()".into()),
            CursorAct::CursorStrokeBegin => l("CursorStrokeBegin()".into()),
            CursorAct::CursorStrokeEnd => l("CursorStrokeEnd()".into()),
            CursorAct::PlotCursor => l("PlotCursor()".into()),
            CursorAct::AirbrushCursor => l("AirbrushCursor()".into()),
            CursorAct::EyedropCursor => l("EyedropCursor()".into()),
            CursorAct::SelectColorCursor => l("SelectColorCursor()".into()),
            CursorAct::FillCursor => l("FillCursor()".into()),
        },
        Act::Draft(a) | Act::Draft2(a) => match a {
            DraftAct::SelectAll => l("SelectAll()".into()),
            DraftAct::SelectNone => l("SelectNone()".into()),
            DraftAct::InvertSelection => l("InvertSelection()".into()),
            DraftAct::SelectByAlpha(m) => {
                l(format!("SelectByAlpha({})", COMBINE[*m as usize % COMBINE.len()]))
            }
            DraftAct::MoveSelection(dx, dy) => l(format!("MoveSelection({},{})", dx, dy)),
            DraftAct::MoveSelectionBegin => l("MoveSelectionBegin()".into()),
            DraftAct::MoveSelectionCommit => l("MoveSelectionCommit()".into()),
            DraftAct::Copy => l("Copy()".into()),
            DraftAct::Cut => l("Cut()".into()),
            DraftAct::Paste => l("Paste()".into()),
            DraftAct::PasteToFrame(i) => l(format!("PasteToFrame({})", idx(*i, frames))),
            DraftAct::PasteDraft => l("PasteDraft()".into()),
            DraftAct::PasteMove(dx, dy) => l(format!("PasteMove({},{})", dx, dy)),
            DraftAct::PasteCommit => l("PasteCommit()".into()),
            DraftAct::PasteCancel => l("PasteCancel()".into()),
            DraftAct::MaskDraft(x, y, w, h, bits) => l(format!("MaskDraft({},{},{})", x, y, mask_args(*w, *h, bits))),
            DraftAct::MaskDraftMove(dx, dy) => l(format!("MaskDraftMove({},{})", dx, dy)),
            DraftAct::MaskDraftCancel => l("MaskDraftCancel()".into()),
            DraftAct::MaskStamp(x, y, w, h, bits) => l(format!("MaskStamp({},{},{})", x, y, mask_args(*w, *h, bits))),
            DraftAct::MoveDraftBegin => l("MoveDraftBegin()".into()),
            DraftAct::MoveDraftMove(dx, dy) => l(format!("MoveDraftMove({},{})", dx, dy)),
            DraftAct::MoveDraftCommit => l("MoveDraftCommit()".into()),
            DraftAct::MoveDraftCancel => l("MoveDraftCancel()".into()),
            DraftAct::RotateDraftBegin => l("RotateDraftBegin()".into()),
            DraftAct::RotateDraftBeginFrame => l("RotateDraftBeginFrame()".into()),
            DraftAct::RotateDraftSetAngle(m) => l(format!("RotateDraftSetAngle({})", m)),
            DraftAct::RotateDraftMove(dx, dy) => l(format!("RotateDraftMove({},{})", dx, dy)),
            DraftAct::RotateDraftCommit => l("RotateDraftCommit()".into()),
            DraftAct::RotateDraftCancel => l("RotateDraftCancel()".into()),
            DraftAct::ScaleDraftBegin => l("ScaleDraftBegin()".into()),
            DraftAct::ScaleDraftBeginFrame => l("ScaleDraftBeginFrame()".into()),
            // Thousandths; 0..=8160 straddles the 100..=8000 clamp.
            DraftAct::ScaleDraftSet(x, y) => {
                l(format!("ScaleDraftSet({},{})", *x as i32 * 32, *y as i32 * 32))
            }
            DraftAct::ScaleDraftMove(dx, dy) => l(format!("ScaleDraftMove({},{})", dx, dy)),
            DraftAct::ScaleDraftCommit => l("ScaleDraftCommit()".into()),
            DraftAct::ScaleDraftCancel => l("ScaleDraftCancel()".into()),
            DraftAct::FillSelection => l("FillSelection()".into()),
            DraftAct::ClearSelection => l("ClearSelection()".into()),
            DraftAct::CropToSelection => l("CropToSelection()".into()),
        },
        Act::Frame(a) => match a {
            FrameAct::NewDocument(w, h) => l(format!("NewDocument({},{})", side(*w), side(*h))),
            FrameAct::AddFrame => l("AddFrame()".into()),
            FrameAct::AddFrameAt(i) => l(format!("AddFrameAt({})", idx(*i, frames))),
            FrameAct::DuplicateFrame(i) => l(format!("DuplicateFrame({})", idx(*i, frames))),
            FrameAct::RemoveFrame(i) => l(format!("RemoveFrame({})", idx(*i, frames))),
            FrameAct::ReorderFrame(a, b) => {
                l(format!("ReorderFrame({},{})", idx(*a, frames), idx(*b, frames)))
            }
            FrameAct::SetActiveFrame(i) => l(format!("SetActiveFrame({})", idx(*i, frames))),
            FrameAct::SetFrameDuration(i, ms) => {
                l(format!("SetFrameDuration({},{})", idx(*i, frames), ms))
            }
            FrameAct::SetAllDurations(ms) => l(format!("SetAllDurations({})", ms)),
            FrameAct::SetLoopMode(m) => {
                l(format!("SetLoopMode({})", ["Loop", "Once", "PingPong"][*m as usize % 3]))
            }
            FrameAct::RemoveFrames(s) => l(format!("RemoveFrames({})", set(*s, frames))),
            FrameAct::DuplicateFrames(s) => l(format!("DuplicateFrames({})", set(*s, frames))),
            FrameAct::RepeatFramesAfter(s) => {
                l(format!("RepeatFramesAfter({})", set(*s, frames)))
            }
            FrameAct::InsertBlankFrames(s, after) => l(format!(
                "InsertBlankFrames({},{})",
                set(*s, frames),
                if *after { "after" } else { "before" }
            )),
            FrameAct::ShiftFrames(s, d) => l(format!("ShiftFrames({},{})", set(*s, frames), d)),
            FrameAct::ReverseFrames(s) => l(format!("ReverseFrames({})", set(*s, frames))),
            FrameAct::SetFrameDurations(s, ms) => {
                l(format!("SetFrameDurations({},{})", set(*s, frames), ms))
            }
            FrameAct::ScaleFrameDurations(s, p) => {
                l(format!("ScaleFrameDurations({},{})", set(*s, frames), p))
            }
            FrameAct::FlipFramesH(s) => l(format!("FlipFramesH({})", set(*s, frames))),
            FrameAct::FlipFramesV(s) => l(format!("FlipFramesV({})", set(*s, frames))),
            FrameAct::RotateFrames(s, q) => {
                l(format!("RotateFrames({},{})", set(*s, frames), q))
            }
            FrameAct::InvertFrames(s) => l(format!("InvertFrames({})", set(*s, frames))),
            FrameAct::FlattenFrames(s) => l(format!("FlattenFrames({})", set(*s, frames))),
            FrameAct::MergeVisible(s) => l(format!("MergeVisible({})", set(*s, frames))),
            FrameAct::CopyLayerToFrames(s) => {
                l(format!("CopyLayerToFrames({})", set(*s, frames)))
            }
            FrameAct::RemoveLayersNamed(s, n) => {
                l(format!("RemoveLayersNamed({},{})", set(*s, frames), name(*n)))
            }
            FrameAct::SetLayersVisibleNamed(s, v, n) => {
                l(format!("SetLayersVisibleNamed({},{},{})", set(*s, frames), v, name(*n)))
            }
            FrameAct::SetLayersLockedNamed(s, v, n) => {
                l(format!("SetLayersLockedNamed({},{},{})", set(*s, frames), v, name(*n)))
            }
            FrameAct::DuplicateLayerToFrames(v) => {
                l(format!("DuplicateLayerToFrames({})", ints(v, frames)))
            }
        },
        Act::Layer(a) | Act::Layer2(a) => match a {
            LayerAct::AddLayer => l("AddLayer()".into()),
            LayerAct::AddLayerAt(i) => l(format!("AddLayerAt({})", idx(*i, layers))),
            LayerAct::RemoveLayer(i) => l(format!("RemoveLayer({})", idx(*i, layers))),
            LayerAct::DuplicateLayer(i) => l(format!("DuplicateLayer({})", idx(*i, layers))),
            LayerAct::MergeDown(i) => l(format!("MergeDown({})", idx(*i, layers))),
            LayerAct::ReorderLayer(a, b) => {
                l(format!("ReorderLayer({},{})", idx(*a, layers), idx(*b, layers)))
            }
            LayerAct::SetActiveLayer(i) => l(format!("SetActiveLayer({})", idx(*i, layers))),
            LayerAct::SetActiveLayers(v) => l(format!("SetActiveLayers({})", ints(v, layers))),
            LayerAct::SetMoveGroup(v) => l(format!("SetMoveGroup({})", ints(v, layers))),
            LayerAct::NudgeLayers(dx, dy) => l(format!("NudgeLayers({},{})", dx, dy)),
            LayerAct::NudgeMove(dx, dy) => l(format!("NudgeMove({},{})", dx, dy)),
            LayerAct::SetLayerOpacity(i, o) => {
                l(format!("SetLayerOpacity({},{})", idx(*i, layers), o))
            }
            LayerAct::OpacityDrag(i, previews, commit) => {
                let i = *i as usize % layers;
                let pre = sess.doc.active_frame().layers[i].opacity;
                for v in previews.iter().take(4) {
                    l(format!("SetLayerOpacityPreview({},{})", i, v));
                }
                l(format!("SetLayerOpacityPreview({},{})", i, pre));
                if let Some(v) = commit {
                    l(format!("SetLayerOpacity({},{})", i, v));
                }
            }
            LayerAct::SetLayerVisible(i, v) => {
                l(format!("SetLayerVisible({},{})", idx(*i, layers), v))
            }
            LayerAct::SetLayerLocked(i, v) => {
                l(format!("SetLayerLocked({},{})", idx(*i, layers), v))
            }
            LayerAct::SetLayerBlend(i, b) => {
                l(format!("SetLayerBlend({},{})", idx(*i, layers), blend(*b)))
            }
            LayerAct::BlendPick(i, taps, commit) => {
                let i = *i as usize % layers;
                // The variant names are the wire names (`BlendMode::from_name`).
                let orig = format!("{:?}", sess.doc.active_frame().layers[i].blend);
                for b in taps.iter().take(4) {
                    l(format!("PreviewLayerBlend({},{})", i, blend(*b)));
                }
                l(format!("PreviewLayerBlend({},{})", i, orig));
                if let Some(b) = commit {
                    l(format!("SetLayerBlend({},{})", i, blend(*b)));
                }
            }
            LayerAct::RenameLayer(i, n) => {
                l(format!("RenameLayer({},{})", idx(*i, layers), name(*n)))
            }
            LayerAct::RemoveLayers(s) => l(format!("RemoveLayers({})", set(*s, layers))),
            LayerAct::DuplicateLayers(s) => l(format!("DuplicateLayers({})", set(*s, layers))),
            LayerAct::MergeLayers(s) => l(format!("MergeLayers({})", set(*s, layers))),
            LayerAct::ShiftLayers(s, d) => l(format!("ShiftLayers({},{})", set(*s, layers), d)),
            LayerAct::ReverseLayers(s) => l(format!("ReverseLayers({})", set(*s, layers))),
            LayerAct::InsertBlankLayers(s, above) => l(format!(
                "InsertBlankLayers({},{})",
                set(*s, layers),
                if *above { "above" } else { "below" }
            )),
            LayerAct::SetLayersVisible(s, v) => {
                l(format!("SetLayersVisible({},{})", set(*s, layers), v))
            }
            LayerAct::SetLayersLocked(s, v) => {
                l(format!("SetLayersLocked({},{})", set(*s, layers), v))
            }
            LayerAct::SetLayersOpacity(s, o) => {
                l(format!("SetLayersOpacity({},{})", set(*s, layers), o))
            }
            LayerAct::SetLayersBlend(s, b) => {
                l(format!("SetLayersBlend({},{})", set(*s, layers), blend(*b)))
            }
            LayerAct::ResetLayers(s) => l(format!("ResetLayers({})", set(*s, layers))),
            LayerAct::RenameLayers(s, n) => {
                l(format!("RenameLayers({},{})", set(*s, layers), name(*n)))
            }
            LayerAct::FlipLayersH(s) => l(format!("FlipLayersH({})", set(*s, layers))),
            LayerAct::FlipLayersV(s) => l(format!("FlipLayersV({})", set(*s, layers))),
            LayerAct::RotateLayers(s, q) => {
                l(format!("RotateLayers({},{})", set(*s, layers), q))
            }
            LayerAct::InvertLayers(s) => l(format!("InvertLayers({})", set(*s, layers))),
            LayerAct::ClearLayers(s) => l(format!("ClearLayers({})", set(*s, layers))),
            LayerAct::CopyLayersToFrames(s, f) => l(format!(
                "CopyLayersToFrames({},{})",
                set(*s, layers),
                set(*f, frames)
            )),
        },
        Act::Setting(a) => match a {
            SettingAct::SetPrimaryColor(c) => l(format!("SetPrimaryColor(#{:08X})", c)),
            SettingAct::SetSecondaryColor(c) => l(format!("SetSecondaryColor(#{:08X})", c)),
            SettingAct::SetBrushSize(s) => l(format!("SetBrushSize({})", s)),
            SettingAct::SetBrushShape(r) => {
                l(format!("SetBrushShape({})", if *r { "Round" } else { "Square" }))
            }
            SettingAct::SetIntensity(v) => l(format!("SetIntensity({})", v)),
            SettingAct::SetSpacing(v) => l(format!("SetSpacing({})", v)),
            SettingAct::SetThreshold(v) => l(format!("SetThreshold({})", v)),
            SettingAct::SetAlphaCutoff(v) => l(format!("SetAlphaCutoff({})", v)),
            SettingAct::SetContiguous(b) => l(format!("SetContiguous({})", b)),
            SettingAct::SetDiagonal(b) => l(format!("SetDiagonal({})", b)),
            SettingAct::SetFillAllLayers(b) => l(format!("SetFillAllLayers({})", b)),
            SettingAct::SetGradientType(r) => {
                l(format!("SetGradientType({})", if *r { "Radial" } else { "Linear" }))
            }
            // t in 0..=1.275 straddles the 0..=1 stop domain.
            SettingAct::SetGradientStops(stops) => {
                let s: Vec<String> = stops
                    .iter()
                    .take(6)
                    .map(|(c, t)| format!("#{:08X}@{}", c, *t as f32 / 200.0))
                    .collect();
                l(format!("SetGradientStops([{}])", s.join(",")));
            }
            SettingAct::SetGradientSmoothstep(b) => l(format!("SetGradientSmoothstep({})", b)),
            SettingAct::SetGradientDither(n) => {
                l(format!("SetGradientDither({})", DITHERS[*n as usize % DITHERS.len()]))
            }
            SettingAct::SetSelectionMode(m) => {
                l(format!("SetSelectionMode({})", COMBINE[*m as usize % COMBINE.len()]))
            }
            SettingAct::SetShapeFill(b) => l(format!("SetShapeFill({})", b)),
            SettingAct::SetLineWidth(w) => l(format!("SetLineWidth({})", w)),
            SettingAct::SetProtectPixels(b) => l(format!("SetProtectPixels({})", b)),
            SettingAct::SetWrap(b) => l(format!("SetWrap({})", b)),
            SettingAct::SetPixelPerfect(b) => l(format!("SetPixelPerfect({})", b)),
            SettingAct::SetAA(b) => l(format!("SetAA({})", b)),
            SettingAct::SetPattern(w, h, bits) => {
                l(format!("SetPattern({},{},{:x})", w % 17, h % 17, bits))
            }
            SettingAct::SetPatternOff => l("SetPattern(off)".into()),
            SettingAct::SetSymmetry(m, ax, ay) => {
                let axis = |a: &Option<i8>| a.map_or("c".to_string(), |v| v.to_string());
                l(format!(
                    "SetSymmetry({},{},{})",
                    ["off", "h", "v", "both"][*m as usize % 4],
                    axis(ax),
                    axis(ay)
                ))
            }
            SettingAct::SetOverscanView(b) => l(format!("SetOverscanView({})", b)),
            SettingAct::SetCleanEdge(b) => l(format!("SetCleanEdge({})", b)),
            SettingAct::SetCleanEdgeWidth(w) => {
                l(format!("SetCleanEdgeWidth({})", *w as i32 * 9 - 100))
            }
            SettingAct::SetScaleCleanEdge(b) => l(format!("SetScaleCleanEdge({})", b)),
            SettingAct::SetScaleCleanEdgeWidth(w) => {
                l(format!("SetScaleCleanEdgeWidth({})", *w as i32 * 9 - 100))
            }
            SettingAct::SetEyedropSource(b) => {
                l(format!("SetEyedropSource({})", if *b { "Layer" } else { "Frame" }))
            }
            SettingAct::SetSelectColorSource(b) => {
                l(format!("SetSelectColorSource({})", if *b { "Layer" } else { "Frame" }))
            }
            SettingAct::SetCopySource(b) => {
                l(format!("SetCopySource({})", if *b { "Layer" } else { "Frame" }))
            }
            SettingAct::SetHsvShift(h, s, v) => l(format!("SetHsvShift({},{},{})", h, s, v)),
            SettingAct::SetHsvScope(f) => {
                l(format!("SetHsvScope({})", if *f { "frame" } else { "layer" }))
            }
            SettingAct::SetBrightnessContrast(b, c) => {
                l(format!("SetBrightnessContrast({},{})", b, c))
            }
            SettingAct::SetBcScope(f) => {
                l(format!("SetBcScope({})", if *f { "frame" } else { "layer" }))
            }
            SettingAct::SetLevels(lo, mid, hi) => {
                l(format!("SetLevels({},{},{})", lo, *mid as i32 * 40 + 1000, hi))
            }
            SettingAct::SetLevelsScope(f) => {
                l(format!("SetLevelsScope({})", if *f { "frame" } else { "layer" }))
            }
            SettingAct::SetSeed(s) => l(format!("SetSeed({})", s)),
        },
        Act::Edit(a) => match a {
            EditAct::ApplyLevels => l("ApplyLevels()".into()),
            EditAct::ApplyHsvShift => l("ApplyHsvShift()".into()),
            EditAct::ApplyBrightnessContrast => l("ApplyBrightnessContrast()".into()),
            EditAct::ReplaceColor(from, to, scope, tol) => l(format!(
                "ReplaceColor(#{:08X},#{:08X},{},{})",
                from,
                to,
                ["layer", "frame", "all"][*scope as usize % 3],
                tol
            )),
            EditAct::Outline(c, inside, square, w) => l(format!(
                "Outline(#{:08X},{},{},{})",
                c,
                if *inside { "inside" } else { "outside" },
                if *square { "square" } else { "round" },
                w % 9
            )),
            EditAct::FillNoise(seed) => l(format!("FillNoise({})", seed)),
            EditAct::FlipH => l("FlipH()".into()),
            EditAct::FlipV => l("FlipV()".into()),
            EditAct::FlipFrameH => l("FlipFrameH()".into()),
            EditAct::FlipFrameV => l("FlipFrameV()".into()),
            EditAct::FlipCanvasH => l("FlipCanvasH()".into()),
            EditAct::FlipCanvasV => l("FlipCanvasV()".into()),
            EditAct::Invert => l("Invert()".into()),
            EditAct::InvertFrame => l("InvertFrame()".into()),
            EditAct::Rotate(q) => l(format!("Rotate({})", q)),
            EditAct::RotateLayer(q) => l(format!("RotateLayer({})", q)),
            EditAct::RotateFrame(q) => l(format!("RotateFrame({})", q)),
            EditAct::ScaleLayer(x, y) => {
                l(format!("ScaleLayer({},{})", *x as i32 * 32, *y as i32 * 32))
            }
            EditAct::ScaleFrame(x, y) => {
                l(format!("ScaleFrame({},{})", *x as i32 * 32, *y as i32 * 32))
            }
            EditAct::ResizeCanvas(w, h, a) => l(format!(
                "ResizeCanvas({},{},{})",
                side(*w),
                side(*h),
                ANCHORS[*a as usize % ANCHORS.len()]
            )),
            EditAct::CropCanvas(x, y, w, h) => {
                l(format!("CropCanvas({},{},{},{})", x, y, w, h))
            }
            EditAct::Repeat => l("Repeat()".into()),
        },
        Act::Palette(a) => match a {
            PaletteAct::AddPaletteColor(c) => l(format!("AddPaletteColor(#{:08X})", c)),
            PaletteAct::RemovePaletteColor(i) => l(format!("RemovePaletteColor({})", i)),
            PaletteAct::EditPaletteColor(i, c) => {
                l(format!("EditPaletteColor({},#{:08X})", i, c))
            }
            PaletteAct::DuplicatePaletteColor(i) => l(format!("DuplicatePaletteColor({})", i)),
            PaletteAct::NamePaletteColor(i, n) => {
                l(format!("NamePaletteColor({},{})", i, name(*n)))
            }
            PaletteAct::SwapPaletteColors(a, b) => l(format!("SwapPaletteColors({},{})", a, b)),
            PaletteAct::NewPalette(n) => l(format!("NewPalette({})", name(*n))),
            PaletteAct::RenamePalette(n) => l(format!("RenamePalette({})", name(*n))),
            PaletteAct::SetActivePalette(i) => l(format!("SetActivePalette({})", i % 8)),
            PaletteAct::ClearPalette => l("ClearPalette()".into()),
            PaletteAct::DeletePalette(i) => l(format!("DeletePalette({})", i % 8)),
            PaletteAct::DuplicatePalette(i) => l(format!("DuplicatePalette({})", i % 8)),
            PaletteAct::MovePalette(a, b) => l(format!("MovePalette({},{})", a % 8, b % 8)),
            PaletteAct::RenamePaletteAt(i, n) => {
                l(format!("RenamePaletteAt({},{})", i % 8, name(*n)))
            }
            PaletteAct::ClearPaletteAt(i) => l(format!("ClearPaletteAt({})", i % 8)),
            PaletteAct::SortPalette => l("SortPalette()".into()),
            PaletteAct::SortPaletteAt(i) => l(format!("SortPaletteAt({})", i % 8)),
        },
        Act::History(a) | Act::History2(a) => match a {
            HistoryAct::Undo => l("Undo()".into()),
            HistoryAct::Redo => l("Redo()".into()),
            HistoryAct::ClearHistory => l("ClearHistory()".into()),
            HistoryAct::Play => l("Play()".into()),
            HistoryAct::Pause => l("Pause()".into()),
            HistoryAct::AdvanceClock(ms) => l(format!("AdvanceClock({})", ms)),
        },
    }
}

/// The opening lines for each `Start`. `Rich` builds its document through the DSL so the
/// recorded script stays self-contained.
fn prelude(start: Start) -> Vec<String> {
    match start {
        Start::Blank => vec!["NewDocument(32,32)".into()],
        Start::Tiny(w, h) => vec![format!("NewDocument({},{})", w % 4 + 1, h % 4 + 1)],
        Start::Rich(seed) => {
            let mut v: Vec<String> = [
                "NewDocument(32,32)",
                "FillNoise(SEED)",
                "AddLayer()",
                "SelectTool(Rectangle)",
                "SetShapeFill(true)",
                "SetPrimaryColor(#FF000080)",
                "ShapeSet(4,4,20,24)",
                "ShapeCommit()",
                "SetLayerOpacity(1,160)",
                "AddLayer()",
                "SetLayerBlend(2,Multiply)",
                "SelectTool(Brush)",
                "SetBrushSize(3)",
                "Stroke([(0,0),(31,31),(40,-5)])",
                "DuplicateFrame(0)",
                "SetActiveFrame(1)",
                "FlipH()",
                "AddFrame()",
                "SetFrameDuration(2,250)",
                "SetActiveFrame(0)",
                "SetActiveLayer(1)",
                "SelectTool(Pencil)",
            ]
            .iter()
            .map(|s| s.replace("SEED", &seed.to_string()))
            .collect();
            if seed & 1 == 1 {
                // A partial selection, so the first edits clip.
                v.splice(
                    v.len() - 1..,
                    ["SelectTool(SelectRect)", "PointerDown(8,8)", "PointerMove(24,20)", "PointerUp()", "SelectTool(Pencil)"]
                        .iter()
                        .map(|s| s.to_string()),
                );
            }
            v
        }
    }
}

/// Triage aid: with `MKPX_FUZZ_SCRIPT` set, every line is echoed to stderr as it runs, so a
/// panic inside the engine (a `debug_assert!` at save time, say) still shows the script that
/// led there. A rejected line is followed by `#^ rejected`; drop both for a CLI replay (the
/// `mkpx` CLI stops at the first script error). Reproduce an artifact with
/// `MKPX_FUZZ_SCRIPT=1 cargo +nightly-2026-08-25 fuzz run fuzz_session_actions <artifact>`.
fn echo() -> bool {
    static ECHO: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *ECHO.get_or_init(|| std::env::var_os("MKPX_FUZZ_SCRIPT").is_some())
}

#[derive(Arbitrary, Debug)]
struct Input {
    start: Start,
    acts: Vec<Act>,
}

fuzz_target!(|input: Input| {
    let mut sess = Session::new(32, 32);
    let mut script = String::new();
    let mut lines = prelude(input.start);
    let run = |sess: &mut Session, lines: &mut Vec<String>, script: &mut String| {
        for line in lines.drain(..) {
            if echo() {
                eprintln!("{}", line);
            }
            // A rejected line changes nothing; leave it out so the script replays exactly.
            if sess.run_script(&line).is_ok() {
                script.push_str(&line);
                script.push('\n');
            } else if echo() {
                eprintln!("#^ rejected"); // drop it and the line above for a CLI replay
            }
        }
    };
    run(&mut sess, &mut lines, &mut script);
    for act in input.acts.iter().take(64) {
        render(act, &sess, &mut lines);
        run(&mut sess, &mut lines, &mut script);
    }

    // Settle open interactions before the semantic oracles: a sequence ending
    // mid-stroke leaves painted pixels whose undo entry only lands on PointerUp, so
    // the final oracles demand a settled state (see docs/fuzzing/FINDINGS.md FZ-1).
    // Mid-sequence Undo still explores the unsettled class under the crash oracle.
    let _ = sess.run_script(
        "PointerUp()\nShapeCancel()\nPasteCancel()\nMoveDraftCancel()\n\
         RotateDraftCancel()\nScaleDraftCancel()\nMoveSelectionCommit()\nCursorPenUp()",
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
