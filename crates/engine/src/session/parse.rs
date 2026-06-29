//! Action-script DSL: parsing (`name(args)` lines) and execution against a `Session`
//! (SPEC §9). The same DSL drives the CLI harness, unit tests, and recorded sessions.

use super::Session;
use crate::color::Rgba8;
use crate::document::LoopMode;
use crate::selection::CombineMode;
use crate::tool::{BrushShape, GradientKind, Stop, ToolKind};

#[derive(Clone, Debug)]
pub enum Action {
    NewDocument(u16, u16),
    AddFrame,
    DuplicateFrame(usize),
    RemoveFrame(usize),
    ReorderFrame(usize, usize),
    SetActiveFrame(usize),
    SetFrameDuration(usize, f32),
    SetAllDurations(f32),
    SetLoopMode(LoopMode),
    AddLayer,
    RemoveLayer(usize),
    DuplicateLayer(usize),
    ReorderLayer(usize, usize),
    SetActiveLayer(usize),
    SetActiveLayers(Vec<usize>),
    SetMoveGroup(Vec<usize>),
    NudgeLayers(i32, i32),
    NudgeMove(i32, i32),
    SetLayerOpacity(usize, u8),
    SetLayerVisible(usize, bool),
    SetLayerLocked(usize, bool),
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
    SetGradientDither(bool),
    SetGradientSmoothstep(bool),
    SetHsvShift(f32, f32, f32),
    SetSelectionMode(CombineMode),
    SetShapeFill(bool),
    SetLineWidth(u16),
    SetProtectPixels(bool),
    SetWrap(bool),
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
    PlotCursor,
    AirbrushCursor,
    EyedropCursor,
    SelectAll,
    SelectNone,
    InvertSelection,
    MoveSelection(i32, i32),
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
    ClearSelection,
    ApplyHsvShift,
    FlipH,
    FlipV,
    Invert,
    Rotate(u8),
    ResizeCanvas(u16, u16, bool),
    CropToSelection,
    AddPaletteColor(Rgba8),
    RemovePaletteColor(usize),
    EditPaletteColor(usize, Rgba8),
    DuplicatePaletteColor(usize),
    SwapPaletteColors(usize, usize),
    NewPalette(String),
    RenamePalette(String),
    SetActivePalette(usize),
    ClearPalette,
    Undo,
    Redo,
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
        match a {
            NewDocument(w, h) => *self = Session::new(w.clamp(8, 256), h.clamp(8, 256)),
            AddFrame => self.add_frame(),
            DuplicateFrame(i) => self.duplicate_frame(i),
            RemoveFrame(i) => self.remove_frame(i),
            ReorderFrame(f, t) => self.reorder_frame(f, t),
            SetActiveFrame(i) => self.set_active_frame(i),
            SetFrameDuration(i, ms) => self.set_frame_duration(i, ms_to_us(ms)),
            SetAllDurations(ms) => self.set_all_durations(ms_to_us(ms)),
            SetLoopMode(m) => self.set_loop_mode(m),
            AddLayer => self.add_layer(),
            RemoveLayer(i) => self.remove_layer(i),
            DuplicateLayer(i) => self.duplicate_layer(i),
            ReorderLayer(f, t) => self.reorder_layer(f, t),
            SetActiveLayer(i) => self.set_active_layer(i),
            SetActiveLayers(v) => self.set_active_layers(&v),
            SetMoveGroup(v) => self.set_move_group(&v),
            NudgeLayers(dx, dy) => self.nudge_layers(dx, dy),
            NudgeMove(dx, dy) => self.nudge_move(dx, dy),
            SetLayerOpacity(i, o) => self.set_layer_opacity(i, o),
            SetLayerVisible(i, v) => self.set_layer_visible(i, v),
            SetLayerLocked(i, v) => self.set_layer_locked(i, v),
            RenameLayer(i, name) => self.rename_layer(i, name),
            DuplicateLayerToFrames(t) => self.duplicate_layer_to_frames(&t),
            SelectTool(t) => self.tool = t,
            SetPrimaryColor(c) => self.settings.primary = c,
            SetSecondaryColor(c) => self.settings.secondary = c,
            SetBrushSize(s) => self.settings.brush_size = s.max(1),
            SetBrushShape(s) => self.settings.brush_shape = s,
            SetIntensity(i) => self.settings.intensity = i,
            SetSpacing(s) => self.settings.spacing = s.clamp(1, 1000),
            SetThreshold(t) => self.settings.threshold = t,
            SetAlphaCutoff(t) => self.settings.alpha_cutoff = t,
            SelectByAlpha(m) => self.select_by_alpha(m),
            SetContiguous(b) => self.settings.contiguous = b,
            SetFillAllLayers(b) => self.settings.fill_all_layers = b,
            SetGradientType(k) => self.settings.gradient.kind = k,
            SetGradientStops(s) => self.settings.gradient.stops = s,
            SetGradientDither(b) => self.settings.gradient.dither = b,
            SetGradientSmoothstep(b) => self.settings.gradient.smoothstep = b,
            SetHsvShift(dh, ds, dv) => self.settings.hsv = (dh, ds, dv),
            SetSelectionMode(m) => self.selection_mode = m,
            SetShapeFill(b) => self.settings.shape_fill = b,
            SetLineWidth(w) => self.settings.line_width = w.max(1),
            SetProtectPixels(b) => self.settings.protect_pixels = b,
            SetWrap(b) => self.settings.wrap = b,
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
            PlotCursor => self.plot_cursor(),
            AirbrushCursor => self.airbrush_cursor(),
            EyedropCursor => self.eyedrop_cursor(),
            SelectAll => self.select_all(),
            SelectNone => self.select_none(),
            InvertSelection => self.invert_selection(),
            MoveSelection(dx, dy) => self.move_selection(dx, dy),
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
            ClearSelection => self.clear_selection_pixels(),
            ApplyHsvShift => self.apply_hsv_shift(),
            FlipH => self.flip_horizontal(),
            FlipV => self.flip_vertical(),
            Invert => self.map_active(crate::color::invert),
            Rotate(q) => self.rotate(q),
            ResizeCanvas(w, h, center) => self.resize_canvas(w, h, center),
            CropToSelection => self.crop_to_selection(),
            AddPaletteColor(c) => self.add_palette_color(c),
            RemovePaletteColor(i) => self.remove_palette_color(i),
            EditPaletteColor(i, c) => self.set_palette_color(i, c),
            DuplicatePaletteColor(i) => self.duplicate_palette_color(i),
            SwapPaletteColors(i, j) => self.swap_palette_colors(i, j),
            NewPalette(name) => self.new_palette(name),
            RenamePalette(name) => self.rename_palette(name),
            SetActivePalette(i) => self.set_active_palette(i),
            ClearPalette => self.clear_palette(),
            Undo => {
                self.doc.undo();
            }
            Redo => {
                self.doc.redo();
            }
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

    Ok(match name {
        "NewDocument" => NewDocument(u16a(0)?, u16a(1)?),
        "AddFrame" => AddFrame,
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
        "RemoveLayer" => RemoveLayer(usza(0)?),
        "DuplicateLayer" => DuplicateLayer(usza(0)?),
        "ReorderLayer" => ReorderLayer(usza(0)?, usza(1)?),
        "SetActiveLayer" => SetActiveLayer(usza(0)?),
        "SetActiveLayers" => SetActiveLayers(extract_ints(inner).into_iter().map(|i| i.max(0) as usize).collect()),
        "SetMoveGroup" => SetMoveGroup(extract_ints(inner).into_iter().map(|i| i.max(0) as usize).collect()),
        "NudgeLayers" => NudgeLayers(i32a(0)?, i32a(1)?),
        "NudgeMove" => NudgeMove(i32a(0)?, i32a(1)?),
        "SetLayerOpacity" => SetLayerOpacity(usza(0)?, u8a(1)?),
        "SetLayerVisible" => SetLayerVisible(usza(0)?, boola(1)?),
        "SetLayerLocked" => SetLayerLocked(usza(0)?, boola(1)?),
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
        "SetGradientDither" => SetGradientDither(boola(0)?),
        "SetGradientSmoothstep" => SetGradientSmoothstep(boola(0)?),
        "SetHsvShift" => SetHsvShift(f32a(0)?, f32a(1)?, f32a(2)?),
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
        "PlotCursor" => PlotCursor,
        "AirbrushCursor" => AirbrushCursor,
        "EyedropCursor" => EyedropCursor,
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
        "ClearSelection" => ClearSelection,
        "ApplyHsvShift" => ApplyHsvShift,
        "FlipH" => FlipH,
        "FlipV" => FlipV,
        "Invert" => Invert,
        "Rotate" => Rotate(u8a(0)?),
        "ResizeCanvas" => ResizeCanvas(u16a(0)?, u16a(1)?, args.get(2).map(|s| *s == "true" || *s == "1").unwrap_or(true)),
        "CropToSelection" => CropToSelection,
        "AddPaletteColor" => AddPaletteColor(color(0)?),
        "RemovePaletteColor" => RemovePaletteColor(usza(0)?),
        "EditPaletteColor" => EditPaletteColor(usza(0)?, color(1)?),
        "DuplicatePaletteColor" => DuplicatePaletteColor(usza(0)?),
        "SwapPaletteColors" => SwapPaletteColors(usza(0)?, usza(1)?),
        "NewPalette" => NewPalette(inner.trim().to_string()),
        "RenamePalette" => RenamePalette(inner.trim().to_string()),
        "SetActivePalette" => SetActivePalette(usza(0)?),
        "ClearPalette" => ClearPalette,
        "Undo" => Undo,
        "Redo" => Redo,
        "Play" => Play,
        "Pause" => Pause,
        "AdvanceClock" => AdvanceClock(u64a(0)?),
        "SetSeed" => SetSeed(u64a(0)?),
        other => return Err(format!("unknown action '{}'", other)),
    })
}
