// Makapix Editor — the animated pixel-art editor pillar. Smartphone-first three-row UI
// (SPEC §20) over the deterministic Rust engine: the engine owns the document; this shell
// captures input and presents composited buffers. One of the app's two co-equal pillars
// (see lib/shell/app_shell.dart); reachable without signing in.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:makapix_club/club/anim/animation_timeline.dart';
import 'package:makapix_club/club/edit/club_edit_request.dart';
import 'package:makapix_club/club/publish/conformance.dart';
import 'package:makapix_club/club/publish/doc_provenance.dart';
import 'package:makapix_club/club/publish/publish_draft.dart';
import 'package:makapix_club/club/state/edit_bridge.dart';
import 'package:makapix_club/club/ui/publish_page.dart';
import 'package:makapix_club/dev/battery_stats.dart';
import 'package:makapix_club/engine_ffi.dart';
import 'package:makapix_club/share/image_share.dart';
import 'package:makapix_club/ui/layout.dart';

import 'blend_modes.dart';
import 'drag_gear.dart';
import 'gallery/gallery_page.dart';
import 'levels_math.dart';
import 'open_file.dart';
import 'palette_io.dart';
import 'palette_page.dart';
import 'patterns/pattern_tile.dart';
import 'patterns/patterns_catalog.dart';
import 'patterns/patterns_page.dart';
import 'tap_again.dart';
import 'keyboard/bindings_store.dart';
import 'keyboard/cheat_sheet.dart';
import 'keyboard/commands.dart';
import 'keyboard/constrain.dart';
import 'keyboard/default_bindings.dart';
import 'keyboard/dispatcher.dart';
import 'keyboard/editor_access.dart';
import 'persistence/autosave_controller.dart';
import 'persistence/drawing_meta.dart';
import 'persistence/drawing_store.dart';
import 'playback_clock.dart';
import 'replay/journal_format.dart';
import 'replay/journal_recorder.dart';
import 'replay/replay_host.dart';
import 'replay/replay_page.dart';
import 'replay/timelapse_export.dart';
import 'replay/timelapse_plan.dart';
import 'makapix_icon.dart';
import 'tools.dart';
import 'thumbnail.dart';
import 'widgets/painters.dart';
import 'widgets/strip_scroller.dart';
import 'dialogs/crop_dialog.dart';
import 'dialogs/place_dialog.dart';
import 'dialogs/raster_preview.dart';
import 'dialogs/color_picker_dialog.dart';
import 'dialogs/rename_drawing_dialog.dart';

// The editor screen's implementation is split across part files (each a private
// `extension _Editor* on _EditorPageState`) to keep every file focused and under
// ~400 lines; this file holds the widget, state fields, lifecycle, and build().
part 'editor_page.engine.dart';
part 'editor_page.fileio.dart';
part 'editor_page.canvas.dart';
part 'editor_page.timeline.dart';
part 'editor_page.sheets.dart';
part 'editor_page.controls.dart';
part 'editor_page.toolgrid.dart';
part 'editor_page.persistence.dart';
part 'editor_page.replay.dart';
part 'editor_page.keyboard.dart';

const double _kMinZoom = 0.25, _kMaxZoom = 32.0;
// One mouse-wheel notch zooms by this factor. The notch delta is what the Windows embedder
// delivers per notch (20 logical px per line × the default 3-line wheel setting); high-resolution
// wheels and free-spinning flicks send other magnitudes, which the exponent scales smoothly.
const double _kWheelZoomStep = 1.2, _kWheelNotchDelta = 60.0;
const _prefsKey = 'tool_order_v1';
const _prefs3RowKey = 'toolbar_3row_v1'; // ☰ → View → 3-row toolbar (row-3 grid in 3 rows, Play pinned)
const _prefsPinnedThirdKey = 'toolbar_pinned3_v1'; // 3-row mode: which tool is pinned in the 3rd slot (long-press to change)
const _prefsHiddenKey = 'tool_hidden_v1'; // ☰ → View → Show/hide tools: dsl names hidden from the row-3 grid (ADR 0018)
const _kCurrentDrawing = 'editor.currentDrawingId'; // last-open library drawing (silent restore)
const _kShareFormatPref = 'editor.shareFormat_v1'; // last-used Share format for animations (GIF/WebP)
const _kExportStillFormatPref = 'editor.exportStillFormat_v1'; // last-used frame/layer export format (PNG/WebP)
const _kAaPref = 'editor.aa_v1'; // the shared AA (anti-alias) toggle (ADR 0008), persisted across restarts
// The Gradient tool's extra colors (#RRGGBBAA list) and color count: a tool setting, not an
// artwork fact, so it is one editor-wide preference (like AA) rather than per drawing — and it
// survives the pillar switch that remounts the editor.
const _kGradExtraPref = 'editor.gradientColors_v1';
const _kGradCountPref = 'editor.gradientCount_v1';
// Patterns (ADR 0025): the global tile (`w,h,hex`), the tools that have it On, the Gradient's
// dither size, and the recents strip — editor-wide preferences like the gradient roster.
const _kPatternPref = 'editor.pattern_v1';
const _kPatternOnPref = 'editor.patternOn_v1';
const _kGradDitherPref = 'editor.gradientDither_v1';
const _kPatternRecentsPref = 'editor.patternRecents_v1';
const _transformTools = {'Flip', 'Rotate', 'Resize', 'Invert'};
// Row-3 "action" tools in the reorderable grid: tapping fires an action/toggle immediately rather
// than selecting a draw tool (handled in _toolTile / _doToolAction). Undo/Redo are NOT here — they
// are pinned at the left of row-3 (see _buildToolBar / _pinnedActionTile). Play is NOT here either —
// it is a selectable tool group whose controls live in row-1 (see _isPlayTool / _buildToolOptions);
// in 3-row toolbar mode it is also pinned beside Undo/Redo and hidden from the grid.
const _actionTools = {'Onion'};
// Tools that support a "Precision" mode (off-finger reticle + act-by-button). Precision is
// a per-tool toggle, remembered independently per tool — see [_precisionTools].
const _precisionTools = {'Pencil', 'Brush', 'Airbrush', 'Eraser', 'Bucket', 'Dodge', 'Burn', 'Eyedropper', 'SelectByColor'};
// Tools whose mark is a stamp/spray of `brush_size` — the row-1 Size slider's audience and the
// [ / ] keyboard Commands' enablement (the figure tools use line_width + fill instead).
const _kBrushSizeTools = {'Pencil', 'Brush', 'Airbrush', 'Eraser', 'Dodge', 'Burn'};
// The tools a pattern gates (ADR 0025). The Gradient has its own Bayer dither instead and never
// reads the pattern; every other tool paints ungated.
const _kPatternTools = {'Pencil', 'Brush', 'Eraser', 'Bucket'};

class EditorPage extends ConsumerStatefulWidget {
  const EditorPage({super.key});
  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends ConsumerState<EditorPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late Engine engine;
  // ---- Local persistence: the current library drawing + its autosave (see editor_page.persistence)
  DrawingStore? _store;
  SharedPreferences? _prefs;
  AutosaveController? _autosave;
  String? _drawingId;
  String _drawingTitle = 'Untitled';
  DateTime _drawingCreatedAt = DateTime.now();
  DateTime? _lastAutosaveWarn; // throttles the "couldn't autosave" toast
  // ---- The always-on Journal (CONTEXT.md "Replay vocabulary"; see editor_page.replay.dart):
  // the per-drawing action recorder, attached at every identity transition. `_journalAttaching`
  // is awaited by the autosave's preWrite so the first marker never races the attach;
  // `_resumeDocBytes` stashes the bytes _loadDrawingIntoEngine actually loaded (their FNV is
  // what attachResume reconciles against).
  JournalRecorder? _journal;

  /// The same recorder as [_journal], but deliberately NOT cleared by dispose: the final flush's
  /// preWrite still has to land its write-ahead marker after dispose has run, and reading the
  /// nulled [_journal] is why every session end used to re-anchor [G-42]. Cleared on release.
  JournalRecorder? _journalWriter;

  /// False until _initPersistence has finished restoring (or created) the current drawing.
  /// ADR 0014 gates canvas input on it: the boot canvas must not accept a stroke it cannot
  /// journal and that the restore is about to overwrite [G-39]. Silent by design — the drawing
  /// appearing IS the feedback.
  bool _persistenceReady = false;
  Future<void>? _journalAttaching;
  Uint8List? _resumeDocBytes;
  // The composited canvas image. A ValueNotifier so playback can repaint just the canvas
  // without a full-tree setState — that churn made the row-3 drag tiles' taps (e.g. Pause) flaky.
  final ValueNotifier<ui.Image?> _imageVN = ValueNotifier<ui.Image?>(null);
  // The redraw scheduler ("one frame, one fetch" — battery R1). _redraw() only marks these
  // dirty flags; _present() is the single worker that fetches + decodes + publishes, so at
  // most one engine display fetch and one GPU upload are in flight at any moment, and
  // sustained request bursts (120-240 Hz digitizers) coalesce to at most one presentation
  // per display frame. The old per-publisher _imageGen staleness stamp is gone: with a
  // single-flight presenter, decodes can no longer land out of order by construction.
  bool _presentInFlight = false; // _present() is running (leading edge taken)

  /// Whether the image currently in [_imageVN] is CANVAS-sized (a playback composite) rather
  /// than storage-sized (the editing display, canvas + overscan gutter). The two need different
  /// offsets, and painting a canvas-sized composite at the gutter-shifted offset displaced the
  /// whole animation under the overscan view [G-23].
  bool _imageIsCanvasSized = false;
  bool _presentBooked = false; // a trailing present is booked on the next frame
  bool _dirtyImage = false; // any presentation request pending
  bool _dirtyFull = false; // pending request wants a full-tree rebuild
  bool _dirtySelection = false; // pending request wants the selection mask re-pulled
  // Bumped to repaint ONLY the canvas overlays (selection ants, reticle, handles, ruler) during a
  // freehand stroke, instead of a full-tree setState that would also rebuild the film-roll and
  // layer strips (each doing per-tile FFI hash calls) on every pointer move. [audit F-9]
  final ValueNotifier<int> _overlayVN = ValueNotifier<int>(0);
  // Marching-ants phase (0..3). Driven by a 175 ms Timer — NOT an AnimationController: an
  // active controller forces full-refresh-rate frame production (measured 120 fps / +1.2 W
  // on an idle canvas, docs/battery/BASELINE.md), while the ants have only 4 visual states
  // per 700 ms period. The timer repaints the overlay layer ~5.7×/s instead. [battery F2]
  final ValueNotifier<int> _antPhase = ValueNotifier<int>(0);
  Timer? _antTimer;
  List<List<int>> _outlineEdges = const []; // each: [x1,y1,x2,y2,t] in canvas-corner coords
  // Cached selection-marquee boundary segments, refreshed only when the selection may have changed
  // (a selection tool acted) — NOT on every paint move; the live eraser footprint is recombined on
  // top cheaply each move. [audit F-11]
  List<List<int>> _selectionEdges = const [];
  // ---- Document memory budget (engine SPEC §8.2b): the engine rolls back mutations past the
  // hard budget and reports telemetry in state_json; the shell surfaces a banner while the soft
  // budget is exceeded and a snackbar per refusal. -1 = "not yet seen", so a loaded session's
  // pre-existing refusal count doesn't toast on the first refresh.
  int _memRefusalsSeen = -1;
  bool _memBannerShown = false;
  String _tool = 'Pencil';
  Color _primary = const Color(0xFF000000);
  // The last primary before the current one — the X Command's swap partner ("swap with
  // previous color"; the editor has no secondary color by design). Starts white so the very
  // first X toggles black↔white. Maintained by _setPrimary.
  Color _previousPrimary = const Color(0xFFFFFFFF);
  List<Color> _palette = [];
  // Optional per-entry display names, aligned with _palette (null = unnamed). Slot-bound in the
  // engine: they follow swaps/sorts/duplicates and survive in-place color edits.
  List<String?> _paletteNames = [];
  // "Size" and "Intensity" are remembered PER TOOL (keyed by the active tool), not shared
  // across tools. Each map holds a tool's last value; the getters fall back to the defaults.
  final Map<String, int> _sizeByTool = {};
  final Map<String, int> _intensityByTool = {};
  // Default size when the user hasn't chosen one: 8px for the Airbrush (a 1px airbrush is useless),
  // 1px for everything else.
  int get _brushSize => _sizeByTool[_tool] ?? (_tool == 'Airbrush' ? 8 : 1);
  set _brushSize(int v) => _sizeByTool[_tool] = v;
  bool _round = true;
  // The shared AA (anti-alias) flag (ADR 0008): one engine setting for round Brush, the shapes
  // (Line/Rect/Ellipse/Triangle), and the round Eraser. Default OFF; persisted (_kAaPref).
  bool _aa = false;
  bool _eyedropLayer = false; // Eyedropper source: false = composited frame (default), true = active layer's raw pixels
  bool _selColorLayer = false; // Select Color source: false = composited frame (default), true = active layer's raw pixels
  bool _perfect = false; // Pencil pixel-perfect: drop L-corner doubles on a 1px stroke
  int _threshold = 0; // Bucket / Select-by-Color color tolerance: exact-match by default
  bool _contiguous = true;
  bool _fillAllLayers = false; // Bucket: decide the fill region from the composited image
  bool _shapeFill = false; // shapes default to Outline (the engine is told on tool select)
  int _lineWidth = 1; // stroke thickness for Line and outline Rectangle/Ellipse (engine line_width)
  bool _lockRatio = false; // Rect/Ellipse: constrain width:height to _ratio (1 = square/circle)
  double _ratio = 1.0; // locked aspect ratio (width / height)
  // Pending figure draft (Line/Rect/Ellipse): two endpoints in canvas-pixel coords, or null when
  // no uncommitted figure. While set, a live preview + draggable handles show and row-1 gets
  // Commit/Cancel; nothing is written to the layer until Commit.
  Offset? _shapeA, _shapeB;
  // active gesture: 0=none, 1=dragging A, 2=dragging B, 3=drawing a new figure, 4=moving the whole
  // draft, 5=rotating, 6=dragging the Triangle's apex (horizontal tip position)
  int _shapeDrag = 0;
  // Start point of a not-yet-materialized new figure: when a press lands off the handles over an
  // existing draft, we defer replacing it until the finger actually moves, so a pinch-zoom or a
  // stray tap leaves the current draft intact.
  Offset? _newShapeStart;
  // Whole-draft reposition (drag off the handles): the canvas point where the move began and the
  // two endpoints at that moment, so each move is a rigid translation from the originals.
  Offset? _shapeMoveAnchor, _shapeMoveOrigA, _shapeMoveOrigB;
  // Canvas-space offset from the finger to the grabbed handle (endpoint or Triangle apex), kept for
  // the whole drag so the handle stays visible beside the finger instead of snapping under it —
  // the Ruler's _rulerGrabOffset convention.
  Offset _shapeGrabOffset = Offset.zero;
  // Shape-tool rotation (radians, around the box center) + the rotate-handle drag origin.
  double _shapeRot = 0;
  Offset? _rotOrigA, _rotOrigB;
  double _rotOrigAngle = 0;
  // Triangle apex skew along its top edge, in [-1, 1] (0 = centered isosceles; ±1 = right triangle).
  double _triTip = 0;
  // ---- Select Shape draft (Rectangle/Ellipse): an uncommitted selection the user drafts on the
  // canvas before it becomes a real selection. PURELY shell-side — the engine's selection is
  // untouched until Commit (then replayed as one pointer drag, the engine's immediate-select path).
  // Two endpoints in canvas-pixel coords (or null when no draft is pending) plus the kind toggle.
  Offset? _selA, _selB;
  String _selShapeKind = 'Rectangle'; // 'Rectangle' | 'Ellipse' | 'Lasso' (row-1 toggle → engine SelectRect/SelectEllipse/SelectFree)
  // The Select Shape tool keeps its OWN aspect-ratio lock, independent of the Shape tool's _lockRatio
  // /_ratio (so locking a square selection never disturbs a locked shape-draw ratio, and vice versa).
  bool _selLockRatio = false; // constrain the selection draft's width:height to _selRatio
  double _selRatio = 1.0; // locked selection aspect ratio (width / height); 1 = square/circle
  // active gesture: 0=none, 1=dragging A, 2=dragging B, 3=drawing a new draft, 4=moving the whole draft
  int _selDrag = 0;
  Offset? _newSelStart; // deferred start of a not-yet-materialized new draft (a stray tap leaves any draft intact)
  Offset? _selMoveAnchor, _selMoveOrigA, _selMoveOrigB; // whole-draft reposition origins
  Offset _selGrabOffset = Offset.zero; // finger→grabbed-corner offset, as _shapeGrabOffset
  // Cached distinct marching-ants boundary segments of the draft (the exact rect/ellipse pixels it
  // would select), rebuilt only when the draft changes — NOT on every animation tick. Each segment
  // is [x1,y1,x2,y2,t] in canvas-corner coords, mirroring _selectionEdges.
  List<List<int>> _selDraftEdges = const [];
  // Ruler tool: a non-destructive measurement line (two draggable endpoints in canvas-pixel
  // coords). Never drawn to the canvas; kept across tool switches (hidden unless pinned).
  Offset? _rulerA, _rulerB;
  // Pin: keep a simplified, semitransparent, non-interactive echo of the ruler visible while
  // other tools are active. Cleared together with the ruler (Clear button or canvas resize).
  bool _rulerPinned = false;
  // Angle mode: a third point forming a second arm A→C (A is the vertex). C is kept while the
  // mode is toggled off (hidden, remembered for the session); the mode itself resets on restart.
  Offset? _rulerC;
  bool _rulerAngle = false;
  int _rulerDrag = 0; // 0=none, 1=dragging A, 2=dragging B, 3=new measurement, 4=moving all, 5=dragging C
  // Canvas-space offset from the finger to the grabbed endpoint, kept for the whole drag so the
  // endpoint stays visible beside the finger instead of snapping under it.
  Offset _rulerGrabOffset = Offset.zero;
  // Whole-ruler drag (off both reticles): the finger anchor and the points at the move start,
  // so the move is a rigid translation clamped on-canvas.
  Offset? _rulerMoveAnchor, _rulerMoveOrigA, _rulerMoveOrigB, _rulerMoveOrigC;
  int _canvasW = 0, _canvasH = 0; // last-seen canvas size; a change auto-clears the stale ruler
  // Cached display (storage under overscan) size. Every size/overscan change funnels through
  // _act → _refreshState, so these are always current — the view-transform helpers and the
  // redraw path read them instead of making scalar FFI crossings per pointer event. [battery F20]
  int _dispW = 0, _dispH = 0;
  bool _radial = false;
  bool _gradSmooth = false; // Gradient: ease each color transition with the smoothstep curve
  // Per-tool starting points for the Intensity slider (until the user moves it): a 50 spray reads
  // as a gentle airbrush; Dodge/Burn open at the 128 midpoint so the first stroke visibly
  // lightens/darkens; anything else keeps 25.
  int get _intensity =>
      _intensityByTool[_tool] ?? switch (_tool) { 'Airbrush' => 50, 'Dodge' || 'Burn' => 128, _ => 25 };
  set _intensity(int v) => _intensityByTool[_tool] = v;
  String _selMode = 'Replace';
  int _alphaCutoff = 0; // Sel Lyr: alpha cutoff (0..254); pixels with alpha > this (opaque) are "selected"
  // Gradient: the first color is ALWAYS the primary color; the remaining (count-1) colors are
  // independent (_gradExtra). _gradCount is the total number of evenly-spaced colors, 2 up to
  // _gradExtra.length + 1 (the engine's SetGradientStops has no cap of its own — the swatch
  // roster is the limit). These are the defaults; _loadToolOrder restores the persisted roster
  // and count over them (_kGradExtraPref / _kGradCountPref), _persistGradient stores them.
  int _gradCount = 2;
  final List<Color> _gradExtra = [
    const Color(0xFFFFFFFF),
    const Color(0xFFFF8000),
    const Color(0xFF0080FF),
    const Color(0xFFFF00FF),
    const Color(0xFF00C040),
    const Color(0xFFFFD000),
    const Color(0xFFE02020),
  ];
  // Patterns (ADR 0025): ONE global tile, remembered until replaced (null until the first pick),
  // with an On/Off flag per gated tool — pick Bayer 4×4 once, have the Pencil On and the Bucket
  // Off. The engine holds only what is in force for the current tool: _pushToolSettings resolves
  // the pair into `SetPattern(w,h,hex)` or `SetPattern(off)` on every tool switch, so a journal
  // replays the same lines the live session ran. The Gradient keeps its own Bayer dither size
  // (0 = off) and the last non-zero one for the long-press toggle. All persisted editor-wide.
  PatternTile? _pattern;
  final Map<String, bool> _patternOn = {};
  final List<PatternTile> _patternRecents = [];
  int _gradDither = 0, _gradDitherLast = 4;
  // HSV-shift sliders: zero = no change, so entering the tool previews the document as-is.
  double _hsvH = 0, _hsvS = 0, _hsvV = 0;
  // Brightness/Contrast sliders: zero = no change too (the contrast slider is ±% around the 1.0×
  // factor, mapped to the engine's cf = 1 + v/100).
  double _bcBright = 0, _bcContrast = 0;
  // Levels thumbs (SetLevels(low, gamma‰, high)): the identity is NON-zero — (0, 1000, 255) —
  // so "reset" means this triple, never zeros.
  int _lvLow = 0, _lvGammaTh = 1000, _lvHigh = 255;
  // Flip/Rotate/Invert/HSV/BC/Levels scope toggles: false = the active layer (or selection), true =
  // every layer of the active frame (FlipFrame*/RotateFrame/InvertFrame/SetHsvScope/SetBcScope/
  // SetLevelsScope in the engine). Layer is the default.
  bool _flipFrame = false, _rotateFrame = false, _resizeFrame = false, _invertFrame = false, _hsvFrame = false, _bcFrame = false, _lvFrame = false;
  // Rotate tool cleanEdge resampling (SetCleanEdge/SetCleanEdgeWidth): free-angle rotations
  // sample the edge-aware cleanEdge reconstruction instead of nearest-neighbor. On by default
  // (must match the engine's ToolSettings default). Width 0–2 like the reference site's slider.
  bool _cleanEdge = true;
  double _cleanEdgeWidth = 1.0;
  // Resize tool cleanEdge (SetScaleCleanEdge/SetScaleCleanEdgeWidth) — INDEPENDENT from the
  // Rotate tool's pair above by design; defaults must match the engine's. Only applies when
  // upscaling (both factors ≥ 1); downscaling is always nearest-neighbor engine-side.
  bool _resizeCleanEdge = true;
  double _resizeCleanEdgeWidth = 1.0;
  // Move tool edge mode (off = Regular = pixels leaving the canvas clip off). The former
  // "Protect pixels" companion was removed from the UI 2026-09-04 (ADR 0023); the engine's
  // SetProtectPixels verb stays functional so old journals replay unchanged.
  bool _wrap = false; // pixels leaving one edge re-enter the opposite edge
  // Slow (ADR 0020): the Move / Move-selection / Paste draft drags are geared down (drag_gear.dart)
  // so an exact pixel is easy to land. Shared by the Move and CopyPaste tools, session-only (not
  // persisted, like Wrap) and UI-only — the engine never hears about it.
  bool _slowDrafts = false;
  // Move tool mode: false = move the layer/pixels (default); true = move only the selection mask.
  bool _moveSelectionMode = false;
  Offset? _moveSelDragLast; // last canvas position while dragging the selection mask
  bool _onion = false;
  bool _grid = false;
  bool _overscan = false; // show the off-canvas gutter (dimmed) around the canvas
  bool _playing = false;
  // Vsync-driven playback preview (replaced the old Timer.periodic(33): late or lost timer
  // callbacks lost virtual time so playback ran slow under load, and 30 Hz sampling aliased
  // 60 fps content). Created lazily in _play(); each tick sends the MEASURED elapsed ms to
  // the engine clock and decodes only when there is something new to show (_onPlayTick).
  Ticker? _playTicker;
  // R3 hybrid playback clock: the vsync ticker paces fast content; slow content parks on a
  // one-shot timer to the next frame boundary (zero frame production between changes). The
  // shared stopwatch is the single time source across both modes. [battery R3]
  Timer? _playTimer;
  final Stopwatch _playStopwatch = Stopwatch();
  final PlaybackClock _playClock = PlaybackClock();
  int _playShownFrame = -1; // playFrame at the last decode; -1 forces the first-tick decode

  /// The Playhead frame, republished every time the displayed composite changes. Row-1's
  /// "Frame X / Y" listens to THIS rather than rebuilding the whole tree each tick: the play tick
  /// deliberately avoids a full-tree setState so the row-3 tiles stay stable and tappable
  /// [battery R1], and a live frame counter must not undo that.
  final ValueNotifier<int> _playheadVN = ValueNotifier<int>(0);
  int _sendSeq = 0; // bumped by every _send — the tick handler's "did anything change" stamp
  int _playSeenSendSeq = 0; // _sendSeq snapshot taken after the tick's own AdvanceClock send
  Map<String, dynamic> _state = {};
  String? _error;
  final Set<int> _selLayers = {}; // layers grouped to move together with the Move tool (no selection)
  ClubEditSource? _clubSource; // set when a Club artwork is opened (enables Replace / remix)
  // Provenance of the working document (sticky import bit + Club parent sqids). Rides in the
  // .mkpx META chunk on every save, so it survives save-to-local / reopen / export — the
  // server-contract requirement from docs/artwork-provenance message 0002. Unlike _clubSource
  // (in-memory Replace conveniences), this is durable history.
  DocProvenance _provenance = DocProvenance.fresh();
  // Precision mode is remembered per tool: a tool name is present here while its Precision toggle
  // is on. Only tools in [_precisionTools] are ever added.
  final Set<String> _precisionOn = {};
  // precision off-finger cursor (shared by whichever paint tool is in precision mode)
  bool _penDown = false;
  Offset? _lastTouch;
  double _accX = 0, _accY = 0;
  int _cursorX = 0, _cursorY = 0; // reticle position (canvas px), mirrored from the engine
  int? _eraserX, _eraserY; // eraser footprint center (canvas px) during an active erase drag
  // Last canvas cell sent on the freehand paint path — the same-cell dedupe stamp. At zoom > 1
  // several screen-pixel moves land in one cell; repeats would re-run the full engine
  // roundtrip + composite + GPU upload for zero visual change. [battery F4]
  int? _paintLastCx, _paintLastCy;
  int _lastLifecycleFlushMs = 0; // debounces the background-walk autosave flush [battery F11]
  // Canvas view transform: _zoom is relative to fit-to-screen (1.0 = fit), _pan is an extra
  // screen-pixel offset. Two fingers, the mouse wheel, and trackpad gestures pan/zoom; the
  // app-bar Fit button resets both.
  double _zoom = 1.0;
  Offset _pan = Offset.zero;
  // Last laid-out canvas box (cached by _buildCanvas): the keyboard zoom Commands need the
  // box for focal-point math outside the LayoutBuilder.
  Size? _lastCanvasBox;
  // Hold bindings (DESIGN.md §2.3). While Space is held, canvas drags pan the view; the
  // routing decision is taken at drag BEGIN (`_panDragLast` non-null marks a pan drag), so a
  // mid-drag press/release never changes a gesture's meaning under the finger.
  bool _spacePanning = false;
  Offset? _panDragLast; // last screen position of an in-flight hold-Space pan drag
  String? _holdPickPrevTool; // tool to restore when the hold-Alt Eyedropper is released
  // Held Shift (DESIGN.md §2.4): directional drags snap/lock while true. Fixed gesture
  // grammar, not a Binding; mid-drag changes re-evaluate on the next pointer event.
  bool _constrainHeld = false;
  // Shared by the Move / Move-selection / Paste drags (at most one drag exists at a time):
  // the drag origin in canvas coords, the gear divisor, and the total delta already sent to
  // the engine. The continue handlers send CORRECTIVE deltas toward the (possibly axis-locked,
  // geared) total from the origin, so a held Shift locks the whole drag without off-axis drift
  // and a Slow drag carries its fractional remainder across events (drag_gear.dart).
  TotalDragTracker? _drag;
  // Multi-touch on the canvas: one finger draws, two+ fingers pan/zoom. While pinching, drawing is
  // suspended until all fingers lift.
  final Map<int, Offset> _touchPos = {}; // live position of every finger on the canvas
  int? _drawPointer; // the finger that owns the in-progress draw (null = none/suspended)
  bool _pinching = false;

  // ---- ADR 0010: gesture atomicity -------------------------------------------------------
  // A Gesture is atomic: nothing else reaches the engine until it ends, and competing input ends
  // it first (finish-then-do). These latch the three gesture families the pointer fields above
  // do not already cover, so ONE predicate (_interactionActive) knows about all five.

  /// True between onPointerPanZoomStart/End — a trackpad pan/zoom is in flight. Latched at Start
  /// so an Update can tell whether its gesture BEGAN during a stroke or pinch [G-10].
  bool _trackpadGesture = false;

  /// The tool that owned a row-1 (or opacity) slider when its drag began; null when no control
  /// drag is live. Keyed by tool so a mid-drag tool switch cannot write into the new tool's
  /// per-tool memory [G-08].
  String? _controlDragTool;

  /// Restores the pre-drag value of the live control drag (ADR 0010: value gestures revert on
  /// cancel, view gestures only end).
  VoidCallback? _controlDragRevert;

  /// Set when a competing Command finished or cancelled a control drag: further ticks from the
  /// still-held slider are ignored until the widget reports onChangeEnd.
  bool _controlDragDead = false;

  /// Guards the teardown itself against the gate that triggers it (the PointerUp we send to
  /// finish a stroke must not try to finish it again).
  bool _endingInteraction = false;

  /// Any Gesture in flight: canvas drag, pinch, precision pen, trackpad gesture, control drag.
  bool get _interactionActive =>
      _drawPointer != null || _pinching || _penDown || _trackpadGesture || _controlDragTool != null;
  double _pinchStartDist = 1, _pinchStartZoom = 1;
  Offset _pinchStartMid = Offset.zero, _pinchStartPan = Offset.zero;
  // Desktop trackpad gesture (PointerPanZoomEvent stream): two-finger scroll pans, pinch zooms
  // around the cursor. The event's pan and scale are cumulative from gesture start, so each
  // update recomputes the whole transform from this start state (incremental application of
  // panDelta + a re-anchored zoom drifts — the pinch fights its own pan component).
  double _trackpadStartZoom = 1;
  Offset _trackpadStartPan = Offset.zero, _trackpadStartFocal = Offset.zero;
  // Last mouse hover position over the canvas, in canvas-local coords — the pinch focal point.
  // The PanZoom events' own position is NOT trusted: on Windows, DirectManipulation gesture
  // events don't carry the cursor point (it can arrive as the window origin), which sent the
  // canvas flying sideways on pinch. Hover events are the same local space the wheel zoom
  // anchors with, which is verified correct.
  Offset? _canvasHoverPos;
  // configurable bottom toolbar
  List<String> _toolOrder = tools.map((t) => t.dsl).toList();
  // ☰ → View → 3-row toolbar: the row-3 grid reflows to 3 rows (3 tiles per row in landscape) and
  // the pinned tool joins Undo/Redo (its grid tile hides, but it stays in _toolOrder so the saved
  // order never churns). The persisted choice always wins; until the user chooses, every device
  // defaults to 2-row (the former tablet-defaults-to-3-row rule was removed by decision 2026-07-24).
  bool? _threeRowPref;
  bool get _threeRowToolbar => _threeRowPref ?? false;
  set _threeRowToolbar(bool v) => _threeRowPref = v;
  // Chrome scale: tablets get ~20% larger strips/tiles/swatches — bigger touch targets, and the
  // bands don't look skeletal at tablet sizes. Applied multiplicatively in the region builders.
  double get _chromeScale => isTabletish(context) ? 1.2 : 1.0;
  // 3-row mode: the tool pinned in the 3rd slot (below Undo/Redo). Defaults to Pencil; long-press the
  // slot to change. The pinned tool stays in _toolOrder (only hidden from the grid) so pinning never
  // churns the saved order — see _visibleOrder / _pinnedThirdTile / _pinnedThirdConfigSheet.
  String _pinnedThirdTool = 'Pencil';
  // ☰ → View → Show/hide tools (ADR 0018): tools hidden from the row-3 grid. Display-time only —
  // hidden tools keep their slot in _toolOrder (unhide restores it), stay fully reachable through
  // the keyboard / hold-pick / paste / pinned slot, and the active tool may be hidden (it stays
  // active). Persisted editor-wide (_prefsHiddenKey); see _visibleOrder / _setToolHidden.
  Set<String> _hiddenTools = {};
  String? _dragTool; // tool dsl being long-press-dragged in row-3 (null = not dragging)
  int? _dropIndex; // live insertion index among the non-dragged tools (for drag preview)
  // film-roll frame thumbnails (cached, invalidated by per-frame content hash)
  final Map<int, ThumbCache> _frameThumbs = {};
  final Set<int> _thumbInFlight = {};
  // Film-roll scroll position, shared by the portrait band and the landscape strip (only one is
  // mounted at a time). _filmTileExtent is the per-tile main-axis extent (tile + margins) stashed
  // by _buildFilmRoll so _ensureActiveFrameVisible can compute tile offsets without layout queries.
  final ScrollController _filmCtrl = ScrollController();
  double _filmTileExtent = 0;
  // Controllers for the strips StripScroller's wheel remap drives (the film roll reuses
  // _filmCtrl above; the layer-sheet mini-stack owns its controller in the sheet). Like
  // _filmCtrl, each serves both orientations — only one instance is ever mounted.
  final ScrollController _layerStripCtrl = ScrollController();
  final ScrollController _optionsRowCtrl = ScrollController();
  final ScrollController _paletteStripCtrl = ScrollController();
  final ScrollController _toolGridCtrl = ScrollController();
  // layers film-strip thumbnails, keyed by (frame,layer) and invalidated by per-layer content hash
  final Map<int, ThumbCache> _layerThumbs = {};
  final Set<int> _layerThumbInFlight = {};
  int _layerKey(int frame, int layer) => frame * 100000 + layer;

  // Whether the current tool offers a Precision toggle at all.
  bool get _precisionCapable => _precisionTools.contains(_tool);
  // Whether the current tool offers the AA toggle: the shape tools always; Brush and Eraser
  // only in Round mode (the engine ignores AA for Square, so the chip hides with it).
  bool get _aaCapable => _tool == 'Line' || _tool == 'Shape' || ((_tool == 'Brush' || _tool == 'Eraser') && _round);
  // Whether the current tool paints through the pattern right now (ADR 0025).
  bool get _patternActive => _kPatternTools.contains(_tool) && (_patternOn[_tool] ?? false) && _pattern != null;
  // The pattern line the engine needs for the current tool — what _pushToolSettings emits.
  String get _patternDsl => _patternActive ? _pattern!.dsl : 'SetPattern(off)';
  // Whether the current tool is *in* precision mode right now.
  bool get _isPrecision => _precisionOn.contains(_tool);

  // UI-only action groups: selecting one reveals its row-1 buttons but does not change the
  // engine's draw tool, and the canvas is inert while one is active.
  bool get _isTransformTool => _transformTools.contains(_tool);

  // The Play tool: a selectable playback group (like the transform tools). Its controls — play/pause,
  // prev/next frame, go to frame — live in row-1, and the canvas is inert while it's active.
  bool get _isPlayTool => _tool == 'PlayPause';

  // Tools whose canvas is inert (no drawing on tap/drag): the transform action groups, the Play
  // group, and Sel Lyr (whose alpha→selection actions are triggered from row-1, not the canvas).
  bool get _isInertCanvasTool => _isTransformTool || _isPlayTool || _tool == 'SelectLayer';

  // Freehand selection tools — their drag grows a live marquee preview, so the outline must be
  // re-pulled on every move (unlike paint tools). Excludes the inert SelectLayer. [audit F-9/F-11]
  bool get _isSelectionTool => _tool.startsWith('Select') && _tool != 'SelectLayer';

  // Off-finger "reticle" mode: dragging moves a cursor (drawn as a screen-space marching-ants
  // overlay) rather than the finger, and an action button effects one operation at a time. This
  // is exactly the active tool being in precision mode.
  bool get _isCursorTool => _isPrecision;

  // Draft tools use the draft flow (drag → adjust the two endpoint handles → commit), not
  // immediate-on-release: the figures (Line/Rect/Ellipse) and the Gradient.
  bool get _isDraftTool => _tool == 'Line' || _tool == 'Shape' || _tool == 'Gradient';
  // Which shape the unified "Shape" tool draws (Ellipse/Triangle/Rectangle); maps to a ToolKind.
  String _shapeKind = 'Rectangle';
  // Which Airbrush mode is active (Dots/Soft/Mist); stored as the engine ToolKind name the
  // shell grouping resolves to ('Airbrush' = Dots, for journal back-compat). [ADR 0006]
  String _airbrushMode = 'Airbrush';
  bool get _hasShapeDraft => _shapeA != null && _shapeB != null;

  // The unified "Select" tool's Rect/Oval DRAFT flow: drag → adjust reticles → Commit, like the
  // Shape tool but the payload is a selection (combined Replace/Add/Subtract/Intersect) rather
  // than drawn pixels. The Lasso mode is excluded: it forwards raw pointer events to the engine
  // (the immediate SelectFree path), like the other freehand selection tools.
  bool get _isSelDraftTool => _tool == 'SelectShape' && _selShapeKind != 'Lasso';
  bool get _hasSelDraft => _selA != null && _selB != null;

  // The Ruler is a pure measurement overlay (no engine tool, no drawing).
  bool get _isRuler => _tool == 'Ruler';
  bool get _hasRuler => _rulerA != null && _rulerB != null;

  // Copy & Paste tool: hosts clipboard ops; a pending paste floats as a movable, semi-transparent
  // draft until committed. `_hasPasteDraft` comes from the engine state JSON.
  bool get _isCopyPaste => _tool == 'CopyPaste';
  // Clipboard swatch (row-1, Copy tool): the clipboard rendered as a ui.Image, cached by the
  // engine's clipboard_gen (bumped on every copy/cut and on document load). -1 = nothing cached.
  ui.Image? _clipImage;
  int _clipImageGen = -1;
  bool _clipFetchInFlight = false;
  bool _hasPasteDraft = false;
  Offset? _pasteDragLast; // last canvas position while dragging the paste draft

  // Move tool draft: dragging the selected pixels (or the layer/move-group, with no selection) lifts
  // them into a relocatable, semi-transparently washed draft, committed via row-1. The draft begins
  // on the first drag MOVEMENT (a tap does nothing). `_hasMoveDraft` comes from the engine state JSON
  // ("move_draft" rect). The mask-only sub-mode (`_moveSelectionMode`) stays immediate.
  bool _hasMoveDraft = false;
  bool get _isMoveDrafting => _tool == 'Move' && !_moveSelectionMode;
  Offset? _moveDragLast; // last canvas position while dragging the move draft
  bool _moveDraftStarted = false; // whether this drag has begun the draft yet (begin on first move)

  // Rotate tool: 90°/180° act on the active layer (or the selected pixels). The "Angle" mode opens a
  // free-angle draft — the involved pixels show a semitransparent preview with a drag handle until
  // Commit. `_hasRotateDraft`/`_rotDraftRect`/`_rotDraftAngle` come from the engine state JSON
  // ("rotate_draft"). The whole-canvas rotation lives in the timeline ☰ menu instead.
  bool _hasRotateDraft = false;
  Rect? _rotDraftRect; // involved-region bbox in canvas pixels (pre-rotation), clamped to the canvas
  double _rotDraftAngle = 0; // current draft angle (radians, clockwise)
  bool _rotateDragging = false; // a finger is currently dragging the rotate handle
  Offset _rotDraftOff = Offset.zero; // whole-pixel drag-to-move offset (JSON "rotate_draft".ox/oy)
  Offset? _rotDraftMoveLast; // canvas pos while dragging the draft body (move mode)
  bool get _isRotateHandleActive => _tool == 'Rotate' && _hasRotateDraft;
  // Handle geometry in the painter's cell-index space (sc() adds +0.5 to reach the cell center, so
  // the geometric bbox center is bbox-center − 0.5), shifted by the drag-to-move offset so the
  // handle follows the moved draft. The handle's arm is half the bbox width, so at angle 0 the
  // reticle sits on the bbox's right border (see _rotDraftReticle).
  Offset get _rotDraftCenter => Offset(
      _rotDraftRect!.left + _rotDraftRect!.width / 2 - 0.5 + _rotDraftOff.dx,
      _rotDraftRect!.top + _rotDraftRect!.height / 2 - 0.5 + _rotDraftOff.dy);
  Offset get _rotDraftCorner =>
      Offset(_rotDraftRect!.right - 1 + _rotDraftOff.dx, _rotDraftRect!.bottom - 1 + _rotDraftOff.dy);

  // Resize tool: ½×/2× act instantly; the "Scale" mode opens a free-scale draft — the involved
  // pixels show a semitransparent preview with a corner knob until Commit.
  // `_hasResizeDraft`/`_resizeDraftRect`/`_resizeSx`/`_resizeSy` come from the engine state JSON
  // ("scale_draft"). The engine verb is Scale (ScaleDraft*/ScaleLayer/ScaleFrame).
  bool _hasResizeDraft = false;
  Rect? _resizeDraftRect; // involved-region bbox in canvas pixels (pre-scale), clamped to the canvas
  double _resizeSx = 1.0, _resizeSy = 1.0; // current draft factors
  bool _resizeDragging = false; // a finger is currently dragging the corner knob
  bool _resizeLockRatio = true; // uniform scaling by default; unlock for X/Y stretch
  Offset _resizeDraftOff = Offset.zero; // whole-pixel drag-to-move offset (JSON "scale_draft".ox/oy)
  Offset? _resizeDraftMoveLast; // canvas pos while dragging the draft body (move mode)
  bool get _isResizeHandleActive => _tool == 'Resize' && _hasResizeDraft;
  // Same cell-index-space convention as _rotDraftCenter (sc() adds +0.5 to reach cell centers),
  // shifted by the drag-to-move offset so the outline + knob follow the moved draft.
  Offset get _resizeDraftCenter => Offset(
      _resizeDraftRect!.left + _resizeDraftRect!.width / 2 - 0.5 + _resizeDraftOff.dx,
      _resizeDraftRect!.top + _resizeDraftRect!.height / 2 - 0.5 + _resizeDraftOff.dy);

  // Whether ANY draft is pending — drives the floating commit-menu over the canvas's bottom-left
  // corner. Mirrors the per-tool guards in _commitActiveDraft/_cancelActiveDraft; at most one draft
  // can exist at a time because every tool switch cancels the outgoing tool's draft.
  bool get _hasAnyDraft =>
      (_isDraftTool && _hasShapeDraft) ||
      (_isSelDraftTool && _hasSelDraft) ||
      (_isCopyPaste && _hasPasteDraft) ||
      (_tool == 'Move' && _hasMoveDraft) ||
      (_tool == 'Rotate' && _hasRotateDraft) ||
      (_tool == 'Resize' && _hasResizeDraft) ||
      (_tool == 'HsvShift' && _hasHsvDraft) ||
      (_tool == 'BrightnessContrast' && _hasBcDraft) ||
      (_tool == 'Levels' && _hasLevelsDraft);

  // A non-identity pending HSV / Brightness-Contrast / Levels adjustment is that tool's draft: it
  // exists as a display-only engine preview, and the commit-menu bakes (Commit = the old Apply) or
  // resets it to identity.
  bool get _hasHsvDraft => _hsvH != 0 || _hsvS != 0 || _hsvV != 0;
  bool get _hasBcDraft => _bcBright != 0 || _bcContrast != 0;
  bool get _hasLevelsDraft => _lvLow != 0 || _lvGammaTh != 1000 || _lvHigh != 255;

  bool get _engineReady => _error == null;

  // ---- Physical keyboard (DESIGN.md; ADR 0009): the Command registry, the default Binding
  // table, and the EditorAccess adapter the EditorKeyboard dispatcher drives. All fixed
  // defaults in v1; phase 6.B swaps _keyboardBindings for the stored/merged table.
  late final _EditorKeyboardHost _keyboardHost = _EditorKeyboardHost(this);
  final List<CommandDef> _keyboardCommands = buildCommands();
  // Defaults at construction; _initPersistence swaps in the stored/merged table (fail-soft).
  BindingTable _keyboardBindings = defaultBindings();

  @override
  void initState() {
    super.initState();
    // The ants timer starts stopped; _syncAntsAnimation() runs it only while marching ants
    // are actually on screen (a selection/eraser outline, the cursor footprint, or a
    // selection draft). [audit][battery F2]
    _loadToolOrder();
    try {
      engine = Engine(64, 64);
      _send('SelectTool(Pencil)');
      _refreshState();
      _redraw();
    } catch (e) {
      _error = '$e';
    }
    WidgetsBinding.instance.addObserver(this); // autosave-flush on app background (Android OS-kill)
    // Resolve the local library, silently restore the last drawing (or start a fresh one), wire
    // autosave, and consume any pending Club "Edit in Makapix" request. Async; the default 64×64
    // doc shows until the restore swaps in. See editor_page.persistence.dart.
    _initPersistence();
  }

  // Run the marching-ants clock only while something animated is on screen: the committed selection
  // / eraser outline (`_outlineEdges`), the precision cursor footprint (`_isCursorTool`), or a
  // selection draft. The `??=` keeps a repeated call from resetting the period mid-tick, and the
  // phase value itself is never reset (a reset would freeze the ants). Idempotent — safe to call
  // from build() and from per-move edge updates. [audit][battery F2]
  void _syncAntsAnimation() {
    final antsOnScreen =
        _outlineEdges.isNotEmpty || _isCursorTool || (_isSelDraftTool && _hasSelDraft);
    if (antsOnScreen) {
      _antTimer ??= Timer.periodic(const Duration(milliseconds: 175), (_) {
        _antPhase.value = (_antPhase.value + 1) & 3; // 700 ms period / 4 phases
      });
    } else {
      _antTimer?.cancel();
      _antTimer = null;
    }
  }

  // Dispose and drop every cached film-roll / layer thumbnail (and clear the in-flight guards).
  // Called on teardown AND on every document switch: the caches are keyed by frame/layer index, so
  // after loading a different drawing index 0's cached image is stale — it would be painted for one
  // frame before the content-hash mismatch regenerates it, and the previous document's ui.Images
  // would sit resident until evicted. Clearing on switch fixes both. [audit]
  void _resetThumbCaches() {
    for (final t in _frameThumbs.values) {
      t.img.dispose();
    }
    _frameThumbs.clear();
    _thumbInFlight.clear();
    for (final t in _layerThumbs.values) {
      t.img.dispose();
    }
    _layerThumbs.clear();
    _layerThumbInFlight.clear();
    // The clipboard swatch cache follows the same lifecycle (the engine bumps clipboard_gen on
    // load, so a stale image would be refetched anyway — this just frees it promptly).
    _clipImage?.dispose();
    _clipImage = null;
    _clipImageGen = -1;
  }

  /// The keyboard "Delete frame" command's second-press arm (ADR 0022; the sheet buttons carry
  /// their own inside [TapAgainDeleteButton]). Keyed by frame index; `_send` disarms it.
  final _frameDeleteArm = TapAgainArm();

  @override
  void dispose() {
    _frameDeleteArm.dispose();
    _playTicker?.dispose(); // legal while active; must precede super.dispose (mixin asserts)
    _playTimer?.cancel(); // the timer half of the hybrid playback clock [battery R3]
    WidgetsBinding.instance.removeObserver(this);
    // Flush the in-progress drawing to disk before the engine is freed so it survives this unmount
    // (Club switch) AND any later crash. flushNow() serializes + builds metadata SYNCHRONOUSLY (so
    // the async write below never touches the freed engine); stop() then cancels the timer and lets
    // that write complete. Replaces the old in-memory EditorSession snapshot.
    // [G-42] The write-ahead marker must land BEFORE the recorder detaches, so the detach is
    // chained onto the flush's own future rather than racing it. [G-41] The whole teardown runs
    // under the drawing folder's single-writer lock, so the next editor mount cannot read or
    // re-anchor underneath these writes.
    final teardownId = _drawingId;
    final teardownFlush = _engineReady ? _autosave?.flushNow() : null;
    _autosave?.stop();
    // The journal's lines were captured synchronously as strings at record() time, so this
    // fire-and-forget drain never touches the engine. The flushNow above already routed the
    // final marker through preWrite; this catches lines recorded since the last autosave delta.
    final teardownJournal = _journal;
    _journal = null;
    if (teardownId != null) {
      _withFolderLock(teardownId, () async {
        if (teardownFlush != null) await teardownFlush;
        teardownJournal?.detachSoon();
      });
    } else {
      teardownJournal?.detachSoon();
    }
    _antTimer?.cancel();
    _antPhase.dispose();
    _resetThumbCaches();
    _imageVN.value?.dispose(); // release the composited canvas image before the notifier [F-10]
    _imageVN.dispose();
    _overlayVN.dispose();
    _playheadVN.dispose();
    _filmCtrl.dispose();
    _layerStripCtrl.dispose();
    _optionsRowCtrl.dispose();
    _paletteStripCtrl.dispose();
    _toolGridCtrl.dispose();
    if (_engineReady) engine.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A backgrounded app stops producing frames but the play Ticker's clock keeps elapsing,
    // so resuming would leap the animation forward by the whole background span: auto-pause
    // instead. `inactive` (permission prompts, the notification shade) deliberately does NOT
    // pause; the _playing guard makes Android's hidden→paused walk idempotent.
    if (_playing &&
        (state == AppLifecycleState.paused || state == AppLifecycleState.hidden)) {
      _pause();
    }
    // The ants Timer, unlike a muted Ticker, keeps firing while backgrounded — stop it and
    // let the resume path re-arm it to whatever is on screen. [battery F2]
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _antTimer?.cancel();
      _antTimer = null;
    } else if (state == AppLifecycleState.resumed) {
      _syncAntsAnimation();
    }
    // Android can kill a backgrounded app with no further callback, so flush the moment we lose
    // foreground. flushNow() serializes synchronously; the write finishes in the background.
    // Android walks resumed→inactive→hidden→paused on a single backgrounding — the debounce
    // keeps that walk from serializing the whole document three times back-to-back (flushNow
    // itself already skips the WRITE when nothing changed). [battery F11]
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastLifecycleFlushMs > 2000) {
        _lastLifecycleFlushMs = now;
        _autosave?.flushNow();
      }
      // The 5 s autosave timer buys nothing while backgrounded (the flush above captured the
      // state); `inactive` keeps it — the app is still visible. [battery F12]
      if (state != AppLifecycleState.inactive) _autosave?.pause();
    } else if (state == AppLifecycleState.resumed) {
      _autosave?.resume();
    }
  }

  @override
  Widget build(BuildContext context) {
    // club → editor bridge: when the Club UI requests an edit, load it.
    ref.listen<ClubEditRequest?>(pendingClubEditProvider, (prev, next) {
      if (next != null) _consumeClubEdit(next);
    });
    // Start/stop the marching-ants clock to match what's on screen (catch-all for every
    // setState-driven change: selection, tool switch, draft). Side-effect-free re controller
    // listeners — it never markNeedsBuild, so no rebuild loop. [audit]
    _syncAntsAnimation();
    if (!_engineReady) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
                'Engine load failed:\n$_error\n\nBuild the DLL with:\n  cargo build -p makapix-ffi --release',
                textAlign: TextAlign.center),
          ),
        ),
      );
    }
    final layers = _layerList();
    // No top bar: the frame film-strip (with its leading ☰ menu) is the topmost area. SafeArea
    // keeps it clear of the status bar (and of landscape notches via its side insets); the bottom
    // inset is handled by the tooltip band. The body arrangement follows the viewport aspect —
    // a pure function of size, so desktop resizes and iPad Split View behave like rotations.
    final landscape = editorUsesLandscape(MediaQuery.sizeOf(context));
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: EditorKeyboard(
          access: _keyboardHost,
          commands: _keyboardCommands,
          bindings: _keyboardBindings,
          child: landscape ? _buildLandscapeBody(layers) : _buildPortraitBody(layers),
        ),
      ),
    );
  }

  // ClipRect so a zoomed canvas can't paint outside its region (the CustomPaint draws the
  // scaled image past its box otherwise) — it stays behind the film-strip and bottom rows.
  // Two compact pills float over the canvas area, ABOVE the canvas Listener, so their taps
  // never fall through and start a draw gesture beneath them: the selection-menu on the
  // bottom-right and the commit-menu (cancel/commit of the pending draft) on the bottom-left.
  Widget _buildCanvasStack() {
    return ClipRect(
      child: Stack(fit: StackFit.expand, children: [
        _buildCanvas(),
        if (_selectionEdges.isNotEmpty) Positioned(right: 10, bottom: 10, child: _selectionMenu()),
        if (_hasAnyDraft) Positioned(left: 10, bottom: 10, child: _commitMenu()),
      ]),
    );
  }

  Widget _buildPortraitBody(List<dynamic> layers) {
    return Column(
      children: [
        _buildFilmRoll(), // frame film-strip + ☰ menu — the topmost area
        Expanded(child: _buildCanvasStack()),
        const Divider(height: 1),
        _buildLayers(layers), // layers film-strip, directly above the tool options
        _buildToolOptions(), // row-1
        _buildPalette(), // row-2
        _buildToolBar(), // row-3 (also holds the pinned Undo/Redo and the Onion toggle)
        _buildTooltipBand(context),
      ],
    );
  }

  // Landscape: the horizontal bands become vertical panels flanking the canvas —
  // frames · palette | canvas / tool options / tooltip | layers · tools.
  Widget _buildLandscapeBody(List<dynamic> layers) {
    return Row(
      children: [
        _buildFilmRoll(axis: Axis.vertical), // frames + ☰ menu, outermost left
        _buildPalette(axis: Axis.vertical), // row-2, beside the canvas
        Expanded(
          child: Column(
            children: [
              Expanded(child: _buildCanvasStack()),
              const Divider(height: 1),
              _buildToolOptions(), // row-1 stays horizontal, under the canvas
              _buildTooltipBand(context, compact: true),
            ],
          ),
        ),
        _buildLayers(layers, axis: Axis.vertical), // right of the canvas
        _buildToolBar(axis: Axis.vertical), // row-3, outermost right
      ],
    );
  }
}
