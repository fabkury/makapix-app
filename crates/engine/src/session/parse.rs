//! Action-script DSL: parsing (`name(args)` lines) and execution against a `Session`
//! (SPEC §9). The same DSL drives the CLI harness, unit tests, and recorded sessions.

use super::Session;
use crate::color::Rgba8;
use crate::document::{BlendMode, LoopMode};
use crate::geom::{MAX_DIM, MIN_DIM};
use crate::selection::CombineMode;
use crate::tool::{BrushShape, GradientKind, Stop, ToolKind};

#[derive(Clone, Debug)]
pub enum Action {
    NewDocument(u16, u16),
    AddFrame,
    AddFrameAt(usize),
    DuplicateFrame(usize),
    RemoveFrame(usize),
    ReorderFrame(usize, usize),
    SetActiveFrame(usize),
    SetFrameDuration(usize, f32),
    SetAllDurations(f32),
    SetLoopMode(LoopMode),
    AddLayer,
    AddLayerAt(usize),
    RemoveLayer(usize),
    DuplicateLayer(usize),
    MergeDown(usize),
    ReorderLayer(usize, usize),
    SetActiveLayer(usize),
    SetActiveLayers(Vec<usize>),
    SetMoveGroup(Vec<usize>),
    NudgeLayers(i32, i32),
    NudgeMove(i32, i32),
    SetLayerOpacity(usize, u8),
    SetLayerOpacityPreview(usize, u8),
    SetLayerVisible(usize, bool),
    SetLayerLocked(usize, bool),
    SetLayerBlend(usize, BlendMode),
    PreviewLayerBlend(usize, BlendMode),
    RenameLayer(usize, String),
    DuplicateLayerToFrames(Vec<usize>),
    SelectTool(ToolKind),
    SetPrimaryColor(Rgba8),
    SetSecondaryColor(Rgba8),
    SetBrushSize(u16),
    SetBrushShape(BrushShape),
    SetIntensity(u8),
    SetSpacing(u16),
    SetThreshold(u8),
    SetAlphaCutoff(u8),
    SelectByAlpha(CombineMode),
    SetContiguous(bool),
    SetFillAllLayers(bool),
    SetGradientType(GradientKind),
    SetGradientStops(Vec<Stop>),
    SetGradientSmoothstep(bool),
    SetHsvShift(f32, f32, f32),
    SetHsvScope(bool), // true = the whole active frame, false = the active layer / selection
    SetBrightnessContrast(i32, f32), // brightness delta [-255,255], contrast factor around 128
    SetBcScope(bool),                // scope flag, same semantics as SetHsvScope
    SetLevels(u8, i32, u8), // low input, gamma in thousandths (the SetCleanEdgeWidth convention;
    // 1000 = 1.0, clamped 100..=10000 at use), high input — (0, 1000, 255) = identity
    SetLevelsScope(bool), // scope flag, same semantics as SetHsvScope
    SetSelectionMode(CombineMode),
    SetShapeFill(bool),
    SetLineWidth(u16),
    SetProtectPixels(bool),
    SetWrap(bool),
    SetPixelPerfect(bool),
    /// Anti-alias (ADR 0008): one shared flag for round Brush, Line/Rect/Ellipse/Triangle, and
    /// round Eraser — fractional-coverage edges instead of hard pixel steps.
    SetAA(bool),
    SetOverscanView(bool),
    SetCleanEdge(bool),
    SetCleanEdgeWidth(i32), // thousandths, 0..=2000 = 0.0..=2.0 (the SetShapeRotation convention)
    SetScaleCleanEdge(bool), // the Resize tool's cleanEdge toggle — independent from SetCleanEdge
    SetScaleCleanEdgeWidth(i32), // thousandths, 0..=2000
    SetEyedropSource(bool), // true = Layer (active layer's raw pixel), false = Frame (composited)
    SetSelectColorSource(bool), // true = Layer (active layer's raw pixels), false = Frame (composited)
    PointerDown(i32, i32),
    PointerMove(i32, i32),
    PointerUp,
    CancelStroke,
    ShapeSet(i32, i32, i32, i32),
    SetShapeRotation(i32),
    SetTriangleTip(i32),
    ShapeCommit,
    ShapeCancel,
    Tap(i32, i32),
    Stroke(Vec<(i32, i32)>),
    SetCursor(i32, i32),
    MoveCursor(i32, i32),
    CursorPenDown,
    CursorPenUp,
    CursorStrokeBegin,
    CursorStrokeEnd,
    PlotCursor,
    AirbrushCursor,
    EyedropCursor,
    SelectColorCursor,
    FillCursor,
    SelectAll,
    SelectNone,
    InvertSelection,
    MoveSelection(i32, i32),
    MoveSelectionBegin,
    MoveSelectionCommit,
    Copy,
    Cut,
    Paste,
    PasteToFrame(usize),
    PasteDraft,
    PasteMove(i32, i32),
    PasteCommit,
    PasteCancel,
    MoveDraftBegin,
    MoveDraftMove(i32, i32),
    MoveDraftCommit,
    MoveDraftCancel,
    FillSelection,
    /// Stress primitive: fill the active layer's canvas with seeded random noise (see
    /// `Session::fill_noise`).
    FillNoise(u64),
    ClearSelection,
    /// Re-execute the last repeatable committed op on the live target (ADR 0017).
    Repeat,
    ApplyHsvShift,
    ApplyBrightnessContrast,
    ApplyLevels,
    FlipH,
    FlipV,
    FlipFrameH,
    FlipFrameV,
    FlipCanvasH,
    FlipCanvasV,
    Invert,
    Rotate(u8),
    RotateLayer(u8),
    RotateFrame(u8),
    InvertFrame,
    RotateDraftBegin,
    RotateDraftBeginFrame,
    RotateDraftSetAngle(i32),
    RotateDraftMove(i32, i32), // whole-pixel nudge of the open draft, relative (PasteMove style)
    RotateDraftCommit,
    RotateDraftCancel,
    ScaleLayer(i32, i32), // X/Y factors in thousandths (1000 = 1×), clamped 100..=8000
    ScaleFrame(i32, i32),
    ScaleDraftBegin,
    ScaleDraftBeginFrame,
    ScaleDraftSet(i32, i32), // thousandths
    ScaleDraftMove(i32, i32), // whole-pixel nudge of the open draft, relative (PasteMove style)
    ScaleDraftCommit,
    ScaleDraftCancel,
    ResizeCanvas(u16, u16, u8, u8), // (w, h, anchor-x, anchor-y): 0 = left/top, 1 = center, 2 = right/bottom
    CropToSelection,
    AddPaletteColor(Rgba8),
    RemovePaletteColor(usize),
    EditPaletteColor(usize, Rgba8),
    DuplicatePaletteColor(usize),
    /// Set/clear the optional display name of active-palette entry `i` (empty name = clear).
    NamePaletteColor(usize, String),
    SwapPaletteColors(usize, usize),
    NewPalette(String),
    RenamePalette(String),
    SetActivePalette(usize),
    ClearPalette,
    DeletePalette(usize),
    DuplicatePalette(usize),
    MovePalette(usize, usize),
    RenamePaletteAt(usize, String),
    ClearPaletteAt(usize),
    SortPalette,
    SortPaletteAt(usize),
    Undo,
    Redo,
    /// Drop the whole undo/redo history (frees everything it retains). Used by the memory stress
    /// lab to separate document growth from history retention; also the right tool after a bulk
    /// import when the pre-import states are meaningless.
    ClearHistory,
    /// Override the document memory budgets (soft, hard) in bytes — tests / stress lab only
    /// (SPEC §8.2b; the shipped defaults live in `document::MEM_*_BUDGET`).
    SetMemBudget(u64, u64),
    Play,
    Pause,
    AdvanceClock(u64),
    SetSeed(u64),
}

impl Session {
    pub fn run_script(&mut self, src: &str) -> Result<(), String> {
        for (n, raw) in src.lines().enumerate() {
            for stmt in raw.split(';') {
                let line = stmt.trim();
                if line.is_empty() || line.starts_with('#') || line.starts_with("//") {
                    continue;
                }
                let act = parse_line(line).map_err(|e| format!("line {}: {} [{}]", n + 1, e, line))?;
                self.exec(act);
            }
        }
        Ok(())
    }

    pub fn exec(&mut self, a: Action) {
        use Action::*;
        // Any action may change frame count/durations (undo/redo included) — dirty the
        // playback timeline cache, except for the per-vsync AdvanceClock chatter it serves.
        // Over-invalidation is safe: the rebuild is one O(frames) pass. [battery F15]
        if !matches!(a, AdvanceClock(_)) {
            self.play_cache_dirty = true;
        }
        match a {
            NewDocument(w, h) => {
                // A replayed Journal can contain NewDocument mid-stream; checkpoints taken
                // before it must survive so backward scrubs restore across the reset. Carry
                // the store across the whole-session replacement. [replay]
                let cps = std::mem::take(&mut self.checkpoints);
                *self = Session::new(w.clamp(MIN_DIM, MAX_DIM), h.clamp(MIN_DIM, MAX_DIM));
                self.checkpoints = cps;
            }
            AddFrame => self.add_frame(),
            AddFrameAt(i) => self.add_frame_at(i),
            DuplicateFrame(i) => self.duplicate_frame(i),
            RemoveFrame(i) => self.remove_frame(i),
            ReorderFrame(f, t) => self.reorder_frame(f, t),
            SetActiveFrame(i) => self.set_active_frame(i),
            SetFrameDuration(i, ms) => self.set_frame_duration(i, ms_to_us(ms)),
            SetAllDurations(ms) => self.set_all_durations(ms_to_us(ms)),
            SetLoopMode(m) => self.set_loop_mode(m),
            AddLayer => self.add_layer(),
            AddLayerAt(i) => self.add_layer_at(i),
            RemoveLayer(i) => self.remove_layer(i),
            DuplicateLayer(i) => self.duplicate_layer(i),
            MergeDown(i) => self.merge_down(i),
            ReorderLayer(f, t) => self.reorder_layer(f, t),
            SetActiveLayer(i) => self.set_active_layer(i),
            SetActiveLayers(v) => self.set_active_layers(&v),
            SetMoveGroup(v) => self.set_move_group(&v),
            NudgeLayers(dx, dy) => self.nudge_layers(dx, dy),
            NudgeMove(dx, dy) => self.nudge_move(dx, dy),
            SetLayerOpacity(i, o) => self.set_layer_opacity(i, o),
            SetLayerOpacityPreview(i, o) => self.set_layer_opacity_preview(i, o),
            SetLayerVisible(i, v) => self.set_layer_visible(i, v),
            SetLayerLocked(i, v) => self.set_layer_locked(i, v),
            SetLayerBlend(i, b) => self.set_layer_blend(i, b),
            PreviewLayerBlend(i, b) => self.preview_layer_blend(i, b),
            RenameLayer(i, name) => self.rename_layer(i, name),
            DuplicateLayerToFrames(t) => self.duplicate_layer_to_frames(&t),
            SelectTool(t) => self.tool = t,
            SetPrimaryColor(c) => self.settings.primary = c,
            SetSecondaryColor(c) => self.settings.secondary = c,
            SetBrushSize(s) => self.settings.brush_size = s.max(1),
            SetBrushShape(s) => self.settings.brush_shape = s,
            SetIntensity(i) => self.settings.intensity = i,
            // Fossilized by replay (the ADR 0006 doctrine): Spacing was removed with the
            // single-coat stroke model (ADR 0007), but journals recorded before it contain
            // `SetSpacing(...)` lines — the verb must parse forever and do nothing.
            SetSpacing(_) => {}
            SetThreshold(t) => self.settings.threshold = t,
            SetAlphaCutoff(t) => self.settings.alpha_cutoff = t,
            SelectByAlpha(m) => self.select_by_alpha(m),
            SetContiguous(b) => self.settings.contiguous = b,
            SetFillAllLayers(b) => self.settings.fill_all_layers = b,
            SetGradientType(k) => self.settings.gradient.kind = k,
            SetGradientStops(s) => self.settings.gradient.stops = s,
            SetGradientSmoothstep(b) => self.settings.gradient.smoothstep = b,
            SetHsvShift(dh, ds, dv) => self.settings.hsv = (dh, ds, dv),
            SetHsvScope(frame) => self.settings.hsv_frame = frame,
            SetBrightnessContrast(db, cf) => self.settings.bc = (db, cf),
            SetBcScope(frame) => self.settings.bc_frame = frame,
            SetLevels(lo, g, hi) => self.settings.levels = (lo, g, hi),
            SetLevelsScope(frame) => self.settings.levels_frame = frame,
            SetSelectionMode(m) => self.selection_mode = m,
            SetShapeFill(b) => self.settings.shape_fill = b,
            SetLineWidth(w) => self.settings.line_width = w.max(1),
            SetProtectPixels(b) => self.settings.protect_pixels = b,
            SetWrap(b) => self.settings.wrap = b,
            SetPixelPerfect(b) => self.settings.pixel_perfect = b,
            SetAA(b) => self.settings.aa = b,
            SetOverscanView(b) => self.settings.overscan_view = b,
            SetEyedropSource(b) => self.settings.eyedrop_layer = b,
            SetSelectColorSource(b) => self.settings.select_color_layer = b,
            SetCleanEdge(b) => self.set_clean_edge(b),
            SetCleanEdgeWidth(w) => self.set_clean_edge_width(w),
            SetScaleCleanEdge(b) => self.set_scale_clean_edge(b),
            SetScaleCleanEdgeWidth(w) => self.set_scale_clean_edge_width(w),
            PointerDown(x, y) => self.pointer_down(x, y),
            PointerMove(x, y) => self.pointer_move(x, y),
            PointerUp => self.pointer_up(),
            CancelStroke => self.cancel_stroke(),
            ShapeSet(ax, ay, bx, by) => self.shape_set(ax, ay, bx, by),
            SetShapeRotation(m) => self.set_shape_rotation(m),
            SetTriangleTip(t) => self.set_triangle_tip(t),
            ShapeCommit => self.shape_commit(),
            ShapeCancel => self.shape_cancel(),
            Tap(x, y) => self.tap(x, y),
            Stroke(pts) => self.stroke_path(&pts),
            SetCursor(x, y) => self.set_cursor(x, y),
            MoveCursor(dx, dy) => self.move_cursor(dx, dy),
            CursorPenDown => self.cursor_pen_down(),
            CursorPenUp => self.cursor_pen_up(),
            CursorStrokeBegin => self.cursor_stroke_begin(),
            CursorStrokeEnd => self.cursor_stroke_end(),
            PlotCursor => self.plot_cursor(),
            AirbrushCursor => self.airbrush_cursor(),
            EyedropCursor => self.eyedrop_cursor(),
            SelectColorCursor => self.select_color_cursor(),
            FillCursor => self.fill_cursor(),
            SelectAll => self.select_all(),
            SelectNone => self.select_none(),
            InvertSelection => self.invert_selection(),
            MoveSelection(dx, dy) => self.move_selection(dx, dy),
            MoveSelectionBegin => self.move_selection_begin(),
            MoveSelectionCommit => self.move_selection_commit(),
            Copy => self.copy(),
            Cut => self.cut(),
            Paste => self.paste(),
            PasteToFrame(i) => self.paste_to_frame(i),
            PasteDraft => self.paste_begin(),
            PasteMove(dx, dy) => self.paste_move(dx, dy),
            PasteCommit => self.paste_commit(),
            PasteCancel => self.paste_cancel(),
            MoveDraftBegin => self.move_draft_begin(),
            MoveDraftMove(dx, dy) => self.move_draft_move(dx, dy),
            MoveDraftCommit => self.move_draft_commit(),
            MoveDraftCancel => self.move_draft_cancel(),
            FillSelection => self.fill_selection(),
            FillNoise(seed) => self.fill_noise(seed),
            ClearSelection => self.clear_selection_pixels(),
            ApplyHsvShift => self.apply_hsv_shift(),
            ApplyBrightnessContrast => self.apply_brightness_contrast(),
            ApplyLevels => self.apply_levels(),
            FlipH => self.flip_horizontal(),
            FlipV => self.flip_vertical(),
            FlipFrameH => self.flip_frame(true),
            FlipFrameV => self.flip_frame(false),
            FlipCanvasH => self.flip_document(true),
            FlipCanvasV => self.flip_document(false),
            Invert => self.map_active(crate::color::invert),
            InvertFrame => self.map_frame(crate::color::invert),
            Rotate(q) => self.rotate(q),
            RotateLayer(q) => self.rotate_layer(q),
            RotateFrame(q) => self.rotate_frame(q),
            RotateDraftBegin => self.rotate_draft_begin(),
            RotateDraftBeginFrame => self.rotate_draft_begin_frame(),
            RotateDraftSetAngle(m) => self.rotate_draft_set_angle(m),
            RotateDraftMove(dx, dy) => self.rotate_draft_move(dx, dy),
            RotateDraftCommit => self.rotate_draft_commit(),
            RotateDraftCancel => self.rotate_draft_cancel(),
            ScaleLayer(sx, sy) => self.scale_layer(sx, sy),
            ScaleFrame(sx, sy) => self.scale_frame(sx, sy),
            ScaleDraftBegin => self.scale_draft_begin(),
            ScaleDraftBeginFrame => self.scale_draft_begin_frame(),
            ScaleDraftSet(sx, sy) => self.scale_draft_set(sx, sy),
            ScaleDraftMove(dx, dy) => self.scale_draft_move(dx, dy),
            ScaleDraftCommit => self.scale_draft_commit(),
            ScaleDraftCancel => self.scale_draft_cancel(),
            ResizeCanvas(w, h, ax, ay) => self.resize_canvas(w, h, ax, ay),
            CropToSelection => self.crop_to_selection(),
            AddPaletteColor(c) => self.add_palette_color(c),
            RemovePaletteColor(i) => self.remove_palette_color(i),
            EditPaletteColor(i, c) => self.set_palette_color(i, c),
            DuplicatePaletteColor(i) => self.duplicate_palette_color(i),
            NamePaletteColor(i, name) => self.name_palette_color(i, &name),
            SwapPaletteColors(i, j) => self.swap_palette_colors(i, j),
            NewPalette(name) => self.new_palette(name),
            RenamePalette(name) => self.rename_palette(name),
            SetActivePalette(i) => self.set_active_palette(i),
            ClearPalette => self.clear_palette(),
            DeletePalette(i) => self.delete_palette(i),
            DuplicatePalette(i) => self.duplicate_palette(i),
            MovePalette(from, to) => self.move_palette(from, to),
            RenamePaletteAt(i, name) => self.rename_palette_at(i, name),
            ClearPaletteAt(i) => self.clear_palette_at(i),
            SortPalette => self.sort_palette(),
            SortPaletteAt(i) => self.sort_palette_at(i),
            Undo => {
                // An open stroke settles (commits) first, so Undo pops the just-drawn pixels
                // instead of churning absolute snapshots under untracked ones. [fuzz FZ-1]
                self.settle_open_edits();
                self.doc.undo();
                self.mem_recalibrate();
                // No Move-group repair needed: it is held by layer id (ADR 0013), so a layer
                // stack that undo shrank simply stops resolving the ids it no longer has.
            }
            Redo => {
                // Settling mid-stroke pushes a record, which clears the redo stack — standard
                // editor semantics: new drawing kills the redoable branch. [fuzz FZ-1]
                self.settle_open_edits();
                self.doc.redo();
                self.mem_recalibrate();
            }
            Repeat => self.repeat(),
            ClearHistory => self.doc.history = crate::history::History::new(),
            SetMemBudget(soft, hard) => self.set_mem_budgets(soft as usize, hard as usize),
            Play => self.play(),
            Pause => self.pause(),
            AdvanceClock(ms) => self.advance_clock_ms(ms),
            SetSeed(n) => self.set_seed(n),
        }
    }
}

/// Extract every signed integer embedded in `s` (handles `[(x,y),(x,y)]` and `x,y,...`).
fn extract_ints(s: &str) -> Vec<i32> {
    let mut out = Vec::new();
    let mut cur = String::new();
    for ch in s.chars() {
        if ch.is_ascii_digit() || (ch == '-' && cur.is_empty()) {
            cur.push(ch);
        } else if !cur.is_empty() {
            if let Ok(v) = cur.parse() {
                out.push(v);
            }
            cur.clear();
        }
    }
    if let Ok(v) = cur.parse() {
        out.push(v);
    }
    out
}

fn ms_to_us(ms: f32) -> u32 {
    (ms * 1000.0).round().clamp(0.0, u32::MAX as f32) as u32
}

fn parse_tool(s: &str) -> Result<ToolKind, String> {
    use ToolKind::*;
    Ok(match s {
        "Pencil" => Pencil,
        // Legacy alias: "Precision" used to be a standalone tool; it is now a per-tool mode
        // (driven entirely from the shell). Old recorded scripts still parse → plain Pencil.
        "PrecisionPencil" => Pencil,
        "Brush" => Brush,
        "Airbrush" => Airbrush,
        "AirbrushSoft" => AirbrushSoft,
        "AirbrushMist" => AirbrushMist,
        "Eraser" => Eraser,
        "Bucket" => Bucket,
        "Gradient" => Gradient,
        "Dodge" => Dodge,
        "Burn" => Burn,
        "Move" => Move,
        // Legacy alias: MoveLayer merged into Move (Move now moves the layer when nothing is selected).
        "MoveLayer" => Move,
        "Eyedropper" => Eyedropper,
        "Line" => Line,
        "Rectangle" => Rectangle,
        "Ellipse" => Ellipse,
        "Triangle" => Triangle,
        "SelectRect" => SelectRect,
        "SelectEllipse" => SelectEllipse,
        "SelectCircle" => SelectCircle,
        "SelectPoly" => SelectPoly,
        "SelectFree" => SelectFree,
        "SelectByColor" => SelectByColor,
        "SelectLayer" => SelectLayer,
        "HsvShift" => HsvShift,
        "BrightnessContrast" => BrightnessContrast,
        "Levels" => Levels,
        "CopyPaste" => CopyPaste,
        other => return Err(format!("unknown tool '{}'", other)),
    })
}

fn parse_stops(inner: &str) -> Result<Vec<Stop>, String> {
    let inner = inner.trim().trim_start_matches('[').trim_end_matches(']');
    let mut stops = Vec::new();
    for tok in inner.split(',') {
        let tok = tok.trim();
        if tok.is_empty() {
            continue;
        }
        let (c, t) = tok.split_once('@').ok_or(format!("stop '{}' missing @t", tok))?;
        let color = Rgba8::from_hex(c.trim()).ok_or(format!("bad stop color '{}'", c))?;
        let t = t.trim().parse::<f32>().map_err(|_| format!("bad stop t '{}'", t))?;
        if !t.is_finite() {
            return Err(format!("non-finite stop t '{}'", t)); // reject NaN/inf at the boundary [F-1]
        }
        stops.push(Stop::new(color, t));
    }
    if stops.len() < 2 {
        return Err("need >= 2 gradient stops".into());
    }
    Ok(stops)
}

/// Third `ResizeCanvas` argument → anchor cell (x, y), each 0 = left/top, 1 = center,
/// 2 = right/bottom. Accepts the 9 direction names (case-insensitive, dashes ignored) plus the
/// legacy booleans `true`/`1` = Center and `false`/`0` = TopLeft. Unknown strings fall back to
/// Center (the historical default), keeping the parser lenient.
fn resize_anchor(s: &str) -> (u8, u8) {
    match s.to_ascii_lowercase().replace('-', "").as_str() {
        "topleft" | "false" | "0" => (0, 0),
        "top" => (1, 0),
        "topright" => (2, 0),
        "left" => (0, 1),
        "right" => (2, 1),
        "bottomleft" => (0, 2),
        "bottom" => (1, 2),
        "bottomright" => (2, 2),
        _ => (1, 1), // "center" | "center" | "true" | "1" | unknown
    }
}

fn parse_line(line: &str) -> Result<Action, String> {
    use Action::*;
    let open = line.find('(').ok_or("expected '('")?;
    let close = line.rfind(')').ok_or("expected ')'")?;
    if close < open {
        return Err("')' before '('".into()); // e.g. ")(" — avoids a backwards-range slice panic [F-4]
    }
    let name = line[..open].trim();
    let inner = line[open + 1..close].trim();

    if name == "SetGradientStops" {
        return parse_stops(inner).map(SetGradientStops);
    }

    let args: Vec<&str> = if inner.is_empty() {
        Vec::new()
    } else {
        inner.split(',').map(|s| s.trim()).collect()
    };
    let i32a = |k: usize| -> Result<i32, String> {
        args.get(k).ok_or(format!("missing arg {}", k))?.parse().map_err(|_| format!("bad int {}", k))
    };
    let usza = |k: usize| -> Result<usize, String> {
        args.get(k).ok_or(format!("missing arg {}", k))?.parse().map_err(|_| format!("bad uint {}", k))
    };
    let u16a = |k: usize| -> Result<u16, String> {
        args.get(k).ok_or(format!("missing arg {}", k))?.parse().map_err(|_| format!("bad u16 {}", k))
    };
    let u8a = |k: usize| -> Result<u8, String> {
        args.get(k).ok_or(format!("missing arg {}", k))?.parse().map_err(|_| format!("bad u8 {}", k))
    };
    let u64a = |k: usize| -> Result<u64, String> {
        args.get(k).ok_or(format!("missing arg {}", k))?.parse().map_err(|_| format!("bad u64 {}", k))
    };
    let f32a = |k: usize| -> Result<f32, String> {
        let v: f32 = args.get(k).ok_or(format!("missing arg {}", k))?.parse().map_err(|_| format!("bad f32 {}", k))?;
        if !v.is_finite() {
            return Err(format!("non-finite f32 {}", k)); // reject NaN/inf (HSV, etc.) [F-1]
        }
        Ok(v)
    };
    let boola = |k: usize| -> Result<bool, String> {
        match args.get(k).copied().unwrap_or("") {
            "true" | "1" => Ok(true),
            "false" | "0" => Ok(false),
            o => Err(format!("bad bool '{}'", o)),
        }
    };
    let color = |k: usize| -> Result<Rgba8, String> {
        Rgba8::from_hex(args.get(k).copied().unwrap_or("")).ok_or("bad color".into())
    };
    let blend = |k: usize| -> Result<BlendMode, String> {
        let s = args.get(k).copied().unwrap_or("");
        BlendMode::from_name(s).ok_or_else(|| format!("bad blend mode '{}'", s))
    };

    Ok(match name {
        "NewDocument" => NewDocument(u16a(0)?, u16a(1)?),
        "AddFrame" => AddFrame,
        "AddFrameAt" => AddFrameAt(usza(0)?),
        "DuplicateFrame" => DuplicateFrame(usza(0)?),
        "RemoveFrame" => RemoveFrame(usza(0)?),
        "ReorderFrame" => ReorderFrame(usza(0)?, usza(1)?),
        "SetActiveFrame" => SetActiveFrame(usza(0)?),
        "SetFrameDuration" => SetFrameDuration(usza(0)?, f32a(1)?),
        "SetAllDurations" => SetAllDurations(f32a(0)?),
        "SetLoopMode" => SetLoopMode(match args.first().copied().unwrap_or("") {
            "Loop" => LoopMode::Loop,
            "Once" => LoopMode::Once,
            "PingPong" => LoopMode::PingPong,
            o => return Err(format!("bad loop mode '{}'", o)),
        }),
        "AddLayer" => AddLayer,
        "AddLayerAt" => AddLayerAt(usza(0)?),
        "RemoveLayer" => RemoveLayer(usza(0)?),
        "DuplicateLayer" => DuplicateLayer(usza(0)?),
        "MergeDown" => MergeDown(usza(0)?),
        "ReorderLayer" => ReorderLayer(usza(0)?, usza(1)?),
        "SetActiveLayer" => SetActiveLayer(usza(0)?),
        "SetActiveLayers" => SetActiveLayers(extract_ints(inner).into_iter().map(|i| i.max(0) as usize).collect()),
        "SetMoveGroup" => SetMoveGroup(extract_ints(inner).into_iter().map(|i| i.max(0) as usize).collect()),
        "NudgeLayers" => NudgeLayers(i32a(0)?, i32a(1)?),
        "NudgeMove" => NudgeMove(i32a(0)?, i32a(1)?),
        "SetLayerOpacity" => SetLayerOpacity(usza(0)?, u8a(1)?),
        "SetLayerOpacityPreview" => SetLayerOpacityPreview(usza(0)?, u8a(1)?),
        "SetLayerVisible" => SetLayerVisible(usza(0)?, boola(1)?),
        "SetLayerLocked" => SetLayerLocked(usza(0)?, boola(1)?),
        "SetLayerBlend" => SetLayerBlend(usza(0)?, blend(1)?),
        "PreviewLayerBlend" => PreviewLayerBlend(usza(0)?, blend(1)?),
        "RenameLayer" => {
            // index, then the rest is the (free-text) name — split on the first comma only so
            // names may themselves contain commas.
            let (idx, rest) = inner.split_once(',').ok_or("RenameLayer needs index, name")?;
            let i = idx.trim().parse::<usize>().map_err(|_| "bad layer index".to_string())?;
            RenameLayer(i, rest.trim().to_string())
        }
        "DuplicateLayerToFrames" => {
            let mut v = Vec::new();
            for k in 0..args.len() {
                v.push(usza(k)?);
            }
            DuplicateLayerToFrames(v)
        }
        "SelectTool" => SelectTool(parse_tool(args.first().copied().unwrap_or(""))?),
        "SetPrimaryColor" => SetPrimaryColor(color(0)?),
        "SetSecondaryColor" => SetSecondaryColor(color(0)?),
        "SetBrushSize" => SetBrushSize(u16a(0)?),
        "SetBrushShape" => SetBrushShape(match args.first().copied().unwrap_or("") {
            "Round" => BrushShape::Round,
            "Square" => BrushShape::Square,
            o => return Err(format!("bad shape '{}'", o)),
        }),
        "SetIntensity" => SetIntensity(u8a(0)?),
        "SetSpacing" => SetSpacing(u16a(0)?),
        "SetThreshold" => SetThreshold(u8a(0)?),
        "SetAlphaCutoff" => SetAlphaCutoff(u8a(0)?),
        "SelectByAlpha" => SelectByAlpha(match args.first().copied().unwrap_or("") {
            "Replace" => CombineMode::Replace,
            "Add" => CombineMode::Add,
            "Subtract" => CombineMode::Subtract,
            "Intersect" => CombineMode::Intersect,
            o => return Err(format!("bad selection mode '{}'", o)),
        }),
        "SetContiguous" => SetContiguous(boola(0)?),
        "SetFillAllLayers" => SetFillAllLayers(boola(0)?),
        "SetGradientType" => SetGradientType(match args.first().copied().unwrap_or("") {
            "Linear" => GradientKind::Linear,
            "Radial" => GradientKind::Radial,
            o => return Err(format!("bad gradient '{}'", o)),
        }),
        "SetGradientSmoothstep" => SetGradientSmoothstep(boola(0)?),
        "SetHsvShift" => SetHsvShift(f32a(0)?, f32a(1)?, f32a(2)?),
        "SetHsvScope" => SetHsvScope(args.first().map(|s| s.eq_ignore_ascii_case("frame")).unwrap_or(false)),
        "SetBrightnessContrast" => SetBrightnessContrast(i32a(0)?, f32a(1)?),
        "SetBcScope" => SetBcScope(args.first().map(|s| s.eq_ignore_ascii_case("frame")).unwrap_or(false)),
        "SetLevels" => SetLevels(u8a(0)?, i32a(1)?, u8a(2)?),
        "SetLevelsScope" => SetLevelsScope(args.first().map(|s| s.eq_ignore_ascii_case("frame")).unwrap_or(false)),
        "SetSelectionMode" => SetSelectionMode(match args.first().copied().unwrap_or("") {
            "Replace" => CombineMode::Replace,
            "Add" => CombineMode::Add,
            "Subtract" => CombineMode::Subtract,
            "Intersect" => CombineMode::Intersect,
            o => return Err(format!("bad selection mode '{}'", o)),
        }),
        "SetShapeFill" => SetShapeFill(boola(0)?),
        "SetLineWidth" => SetLineWidth(u16a(0)?),
        "SetProtectPixels" => SetProtectPixels(boola(0)?),
        "SetWrap" => SetWrap(boola(0)?),
        "SetPixelPerfect" => SetPixelPerfect(boola(0)?),
        "SetAA" => SetAA(boola(0)?),
        "SetOverscanView" => SetOverscanView(boola(0)?),
        "SetCleanEdge" => SetCleanEdge(boola(0)?),
        "SetCleanEdgeWidth" => SetCleanEdgeWidth(i32a(0)?),
        "SetScaleCleanEdge" => SetScaleCleanEdge(boola(0)?),
        "SetScaleCleanEdgeWidth" => SetScaleCleanEdgeWidth(i32a(0)?),
        "SetEyedropSource" => SetEyedropSource(match args.first().copied().unwrap_or("") {
            "Frame" => false,
            "Layer" => true,
            o => return Err(format!("bad eyedrop source '{}'", o)),
        }),
        "SetSelectColorSource" => SetSelectColorSource(match args.first().copied().unwrap_or("") {
            "Frame" => false,
            "Layer" => true,
            o => return Err(format!("bad select color source '{}'", o)),
        }),
        "PointerDown" => PointerDown(i32a(0)?, i32a(1)?),
        "PointerMove" => PointerMove(i32a(0)?, i32a(1)?),
        "PointerUp" => PointerUp,
        "CancelStroke" => CancelStroke,
        "ShapeSet" => ShapeSet(i32a(0)?, i32a(1)?, i32a(2)?, i32a(3)?),
        "SetShapeRotation" => SetShapeRotation(i32a(0)?),
        "SetTriangleTip" => SetTriangleTip(i32a(0)?),
        "ShapeCommit" => ShapeCommit,
        "ShapeCancel" => ShapeCancel,
        "Tap" => Tap(i32a(0)?, i32a(1)?),
        "SetCursor" => SetCursor(i32a(0)?, i32a(1)?),
        "MoveCursor" => MoveCursor(i32a(0)?, i32a(1)?),
        "CursorPenDown" => CursorPenDown,
        "CursorPenUp" => CursorPenUp,
        "CursorStrokeBegin" => CursorStrokeBegin,
        "CursorStrokeEnd" => CursorStrokeEnd,
        "PlotCursor" => PlotCursor,
        "AirbrushCursor" => AirbrushCursor,
        "EyedropCursor" => EyedropCursor,
        "SelectColorCursor" => SelectColorCursor,
        "FillCursor" => FillCursor,
        "Stroke" => {
            // Accept "[(x,y),(x,y),...]" or "x,y,x,y" — extract all integers robustly.
            let nums = extract_ints(inner);
            if nums.len() < 2 || nums.len() % 2 != 0 {
                return Err("Stroke needs an even count of ints".into());
            }
            let pts = nums.chunks(2).map(|c| (c[0], c[1])).collect();
            Stroke(pts)
        }
        "SelectAll" => SelectAll,
        "SelectNone" => SelectNone,
        "InvertSelection" => InvertSelection,
        "MoveSelection" => MoveSelection(i32a(0)?, i32a(1)?),
        "MoveSelectionBegin" => MoveSelectionBegin,
        "MoveSelectionCommit" => MoveSelectionCommit,
        "Copy" => Copy,
        "Cut" => Cut,
        "Paste" => Paste,
        "PasteToFrame" => PasteToFrame(usza(0)?),
        "PasteDraft" => PasteDraft,
        "PasteMove" => PasteMove(i32a(0)?, i32a(1)?),
        "PasteCommit" => PasteCommit,
        "PasteCancel" => PasteCancel,
        "MoveDraftBegin" => MoveDraftBegin,
        "MoveDraftMove" => MoveDraftMove(i32a(0)?, i32a(1)?),
        "MoveDraftCommit" => MoveDraftCommit,
        "MoveDraftCancel" => MoveDraftCancel,
        "FillSelection" => FillSelection,
        "FillNoise" => FillNoise(u64a(0)?),
        "ClearSelection" => ClearSelection,
        "ApplyHsvShift" => ApplyHsvShift,
        "ApplyBrightnessContrast" => ApplyBrightnessContrast,
        "ApplyLevels" => ApplyLevels,
        "FlipH" => FlipH,
        "FlipV" => FlipV,
        "FlipFrameH" => FlipFrameH,
        "FlipFrameV" => FlipFrameV,
        "FlipCanvasH" => FlipCanvasH,
        "FlipCanvasV" => FlipCanvasV,
        "Invert" => Invert,
        "InvertFrame" => InvertFrame,
        "Rotate" => Rotate(u8a(0)?),
        "RotateLayer" => RotateLayer(u8a(0)?),
        "RotateFrame" => RotateFrame(u8a(0)?),
        "RotateDraftBegin" => RotateDraftBegin,
        "RotateDraftBeginFrame" => RotateDraftBeginFrame,
        "RotateDraftSetAngle" => RotateDraftSetAngle(i32a(0)?),
        "RotateDraftMove" => RotateDraftMove(i32a(0)?, i32a(1)?),
        "RotateDraftCommit" => RotateDraftCommit,
        "RotateDraftCancel" => RotateDraftCancel,
        "ScaleLayer" => ScaleLayer(i32a(0)?, i32a(1)?),
        "ScaleFrame" => ScaleFrame(i32a(0)?, i32a(1)?),
        "ScaleDraftBegin" => ScaleDraftBegin,
        "ScaleDraftBeginFrame" => ScaleDraftBeginFrame,
        "ScaleDraftSet" => ScaleDraftSet(i32a(0)?, i32a(1)?),
        "ScaleDraftMove" => ScaleDraftMove(i32a(0)?, i32a(1)?),
        "ScaleDraftCommit" => ScaleDraftCommit,
        "ScaleDraftCancel" => ScaleDraftCancel,
        "ResizeCanvas" => {
            let (ax, ay) = resize_anchor(args.get(2).copied().unwrap_or("Center"));
            ResizeCanvas(u16a(0)?, u16a(1)?, ax, ay)
        }
        "CropToSelection" => CropToSelection,
        "AddPaletteColor" => AddPaletteColor(color(0)?),
        "RemovePaletteColor" => RemovePaletteColor(usza(0)?),
        "EditPaletteColor" => EditPaletteColor(usza(0)?, color(1)?),
        "DuplicatePaletteColor" => DuplicatePaletteColor(usza(0)?),
        "NamePaletteColor" => {
            // index, then the rest is the (free-text) name — split on the first comma only so
            // names may themselves contain commas (same contract as RenamePaletteAt). An empty
            // name is the documented way to clear: NamePaletteColor(3,) or NamePaletteColor(3, ).
            let (idx, rest) = inner.split_once(',').ok_or("NamePaletteColor needs index, name")?;
            let i = idx.trim().parse::<usize>().map_err(|_| "bad palette index".to_string())?;
            NamePaletteColor(i, rest.trim().to_string())
        }
        "SwapPaletteColors" => SwapPaletteColors(usza(0)?, usza(1)?),
        "NewPalette" => NewPalette(inner.trim().to_string()),
        "RenamePalette" => RenamePalette(inner.trim().to_string()),
        "SetActivePalette" => SetActivePalette(usza(0)?),
        "ClearPalette" => ClearPalette,
        "DeletePalette" => DeletePalette(usza(0)?),
        "DuplicatePalette" => DuplicatePalette(usza(0)?),
        "MovePalette" => MovePalette(usza(0)?, usza(1)?),
        "RenamePaletteAt" => {
            // index, then the rest is the (free-text) name — split on the first comma only so
            // names may themselves contain commas (same contract as RenameLayer).
            let (idx, rest) = inner.split_once(',').ok_or("RenamePaletteAt needs index, name")?;
            let i = idx.trim().parse::<usize>().map_err(|_| "bad palette index".to_string())?;
            RenamePaletteAt(i, rest.trim().to_string())
        }
        "ClearPaletteAt" => ClearPaletteAt(usza(0)?),
        "SortPalette" => SortPalette,
        "SortPaletteAt" => SortPaletteAt(usza(0)?),
        "Undo" => Undo,
        "Redo" => Redo,
        "Repeat" => Repeat,
        "ClearHistory" => ClearHistory,
        "SetMemBudget" => SetMemBudget(u64a(0)?, u64a(1)?),
        "Play" => Play,
        "Pause" => Pause,
        "AdvanceClock" => AdvanceClock(u64a(0)?),
        "SetSeed" => SetSeed(u64a(0)?),
        other => return Err(format!("unknown action '{}'", other)),
    })
}
