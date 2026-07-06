// Makapix Editor — the animated pixel-art editor pillar. Smartphone-first three-row UI
// (SPEC §20) over the deterministic Rust engine: the engine owns the document; this shell
// captures input and presents composited buffers. One of the app's two co-equal pillars
// (see lib/shell/app_shell.dart); reachable without signing in.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:makapix_club/club/edit/club_edit_request.dart';
import 'package:makapix_club/club/publish/conformance.dart';
import 'package:makapix_club/club/publish/publish_draft.dart';
import 'package:makapix_club/club/state/edit_bridge.dart';
import 'package:makapix_club/club/ui/publish_page.dart';
import 'package:makapix_club/engine_ffi.dart';

import 'gallery/gallery_page.dart';
import 'persistence/autosave_controller.dart';
import 'persistence/drawing_meta.dart';
import 'persistence/drawing_store.dart';
import 'tools.dart';
import 'thumbnail.dart';
import 'widgets/painters.dart';
import 'dialogs/crop_dialog.dart';
import 'dialogs/color_picker_dialog.dart';

// The editor screen's implementation is split across part files (each a private
// `extension _Editor* on _EditorPageState`) to keep every file focused and under
// ~400 lines; this file holds the widget, state fields, lifecycle, and build().
part 'editor_page.engine.dart';
part 'editor_page.fileio.dart';
part 'editor_page.canvas.dart';
part 'editor_page.timeline.dart';
part 'editor_page.controls.dart';
part 'editor_page.toolgrid.dart';
part 'editor_page.persistence.dart';

const double _kMinZoom = 0.25, _kMaxZoom = 32.0;
// export-dialog: warn (red alert + explicit re-confirmation) when an export's total output —
// width × height × scale² × frames — exceeds this. ~64 million pixels ≈ 256 MB of RGBA work per
// pass, about where a mid-to-upper-range Android phone starts to struggle: 256² at 32× (67 MP)
// is just over the line; a 64² × 8-frame animation at 32× (34 MP) is comfortably under it.
const _kExportWarnPixels = 64 * 1000 * 1000;
const _prefsKey = 'tool_order_v1';
const _kCurrentDrawing = 'editor.currentDrawingId'; // last-open library drawing (silent restore)
const _kShareFormatPref = 'editor.shareFormat_v1'; // last-used Share format for animations (GIF/WebP)
const _kExportStillFormatPref = 'editor.exportStillFormat_v1'; // last-used frame/layer export format (PNG/WebP)
const _transformTools = {'Flip', 'Rotate', 'Invert'};
// Row-3 "action" tools in the reorderable grid: tapping fires an action/toggle immediately rather
// than selecting a draw tool (handled in _toolTile / _doToolAction). Undo/Redo are NOT here — they
// are pinned at the left of row-3 (see _buildToolBar / _pinnedActionTile). Play is NOT here either —
// it is a selectable tool group whose controls live in row-1 (see _isPlayTool / _buildToolOptions).
const _actionTools = {'Onion'};
// Paint tools that support a "Precision" mode (off-finger reticle + draw-by-button). Precision is
// a per-tool toggle, remembered independently per tool — see [_precisionTools].
const _precisionTools = {'Pencil', 'Brush', 'Airbrush', 'Eraser', 'Dodge', 'Burn', 'Eyedropper'};

class EditorPage extends ConsumerStatefulWidget {
  const EditorPage({super.key});
  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends ConsumerState<EditorPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late Engine engine;
  // ---- Local persistence: the current library drawing + its autosave (see editor_page.persistence)
  DrawingStore? _store;
  SharedPreferences? _prefs;
  AutosaveController? _autosave;
  String? _drawingId;
  String _drawingTitle = 'Untitled';
  DateTime _drawingCreatedAt = DateTime.now();
  DateTime? _lastAutosaveWarn; // throttles the "couldn't autosave" toast
  // The composited canvas image. A ValueNotifier so playback can repaint just the canvas (30fps)
  // without a full-tree setState — that churn made the row-3 drag tiles' taps (e.g. Pause) flaky.
  final ValueNotifier<ui.Image?> _imageVN = ValueNotifier<ui.Image?>(null);
  // Bumped to repaint ONLY the canvas overlays (selection ants, reticle, handles, ruler) during a
  // freehand stroke, instead of a full-tree setState that would also rebuild the film-roll and
  // layer strips (each doing per-tile FFI hash calls) on every pointer move. [audit F-9]
  final ValueNotifier<int> _overlayVN = ValueNotifier<int>(0);
  late AnimationController _antCtrl; // marching-ants animation phase
  List<List<int>> _outlineEdges = const []; // each: [x1,y1,x2,y2,t] in canvas-corner coords
  // Cached selection-marquee boundary segments, refreshed only when the selection may have changed
  // (a selection tool acted) — NOT on every paint move; the live eraser footprint is recombined on
  // top cheaply each move. [audit F-11]
  List<List<int>> _selectionEdges = const [];
  String _tool = 'Pencil';
  Color _primary = const Color(0xFF000000);
  List<Color> _palette = [];
  // "Size" and "Spacing" are remembered PER TOOL (keyed by the active tool), not shared across
  // tools. Each map holds a tool's last value; the getters fall back to the defaults.
  final Map<String, int> _sizeByTool = {};
  final Map<String, int> _spacingByTool = {};
  // Default size when the user hasn't chosen one: 8px for the Airbrush (a 1px airbrush is useless),
  // 1px for everything else.
  int get _brushSize => _sizeByTool[_tool] ?? (_tool == 'Airbrush' ? 8 : 1);
  set _brushSize(int v) => _sizeByTool[_tool] = v;
  bool _round = true;
  bool _perfect = false; // Pencil pixel-perfect: drop L-corner doubles on a 1px stroke
  int _threshold = 16;
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
  // Shape-tool rotation (radians, around the box centre) + the rotate-handle drag origin.
  double _shapeRot = 0;
  Offset? _rotOrigA, _rotOrigB;
  double _rotOrigAngle = 0;
  // Triangle apex skew along its top edge, in [-1, 1] (0 = centred isosceles; ±1 = right triangle).
  double _triTip = 0;
  // ---- Select Shape draft (Rectangle/Ellipse): an uncommitted selection the user drafts on the
  // canvas before it becomes a real selection. PURELY shell-side — the engine's selection is
  // untouched until Commit (then replayed as one pointer drag, the engine's immediate-select path).
  // Two endpoints in canvas-pixel coords (or null when no draft is pending) plus the kind toggle.
  Offset? _selA, _selB;
  String _selShapeKind = 'Rectangle'; // 'Rectangle' | 'Ellipse' (row-1 toggle → engine SelectRect/SelectEllipse)
  // The Select Shape tool keeps its OWN aspect-ratio lock, independent of the Shape tool's _lockRatio
  // /_ratio (so locking a square selection never disturbs a locked shape-draw ratio, and vice versa).
  bool _selLockRatio = false; // constrain the selection draft's width:height to _selRatio
  double _selRatio = 1.0; // locked selection aspect ratio (width / height); 1 = square/circle
  // active gesture: 0=none, 1=dragging A, 2=dragging B, 3=drawing a new draft, 4=moving the whole draft
  int _selDrag = 0;
  Offset? _newSelStart; // deferred start of a not-yet-materialized new draft (a stray tap leaves any draft intact)
  Offset? _selMoveAnchor, _selMoveOrigA, _selMoveOrigB; // whole-draft reposition origins
  // Cached distinct marching-ants boundary segments of the draft (the exact rect/ellipse pixels it
  // would select), rebuilt only when the draft changes — NOT on every animation tick. Each segment
  // is [x1,y1,x2,y2,t] in canvas-corner coords, mirroring _selectionEdges.
  List<List<int>> _selDraftEdges = const [];
  // Ruler tool: a non-destructive measurement line (two draggable endpoints in canvas-pixel
  // coords). Never drawn to the canvas; cleared when switching tools.
  Offset? _rulerA, _rulerB;
  int _rulerDrag = 0; // 0=none, 1=dragging A, 2=dragging B, 3=new measurement, 4=moving both ends
  // Canvas-space offset from the finger to the grabbed endpoint, kept for the whole drag so the
  // endpoint stays visible beside the finger instead of snapping under it.
  Offset _rulerGrabOffset = Offset.zero;
  // Whole-ruler drag (off both reticles): the finger anchor and both endpoints at the move start,
  // so the move is a rigid translation clamped on-canvas.
  Offset? _rulerMoveAnchor, _rulerMoveOrigA, _rulerMoveOrigB;
  int _canvasW = 0, _canvasH = 0; // last-seen canvas size; a change auto-clears the stale ruler
  bool _radial = false;
  bool _gradSmooth = false; // Gradient: ease each colour transition with the smoothstep curve
  int _intensity = 128;
  int get _spacing => _spacingByTool[_tool] ?? 25; // Brush/Airbrush stamp spacing, % of brush size
  set _spacing(int v) => _spacingByTool[_tool] = v;
  String _selMode = 'Replace';
  int _alphaCutoff = 0; // Sel Lyr: alpha cutoff (0..254); pixels with alpha > this (opaque) are "selected"
  // Gradient: the first colour is ALWAYS the primary colour; the remaining (count-1) colours are
  // independent (_gradExtra). _gradCount is the total number of evenly-spaced colours (2/3/4).
  int _gradCount = 2;
  final List<Color> _gradExtra = [
    const Color(0xFFFFFFFF),
    const Color(0xFFFF8000),
    const Color(0xFF0080FF),
  ];
  // HSV-shift sliders: zero = no change, so entering the tool previews the document as-is.
  double _hsvH = 0, _hsvS = 0, _hsvV = 0;
  // Brightness/Contrast sliders: zero = no change too (the contrast slider is ±% around the 1.0×
  // factor, mapped to the engine's cf = 1 + v/100).
  double _bcBright = 0, _bcContrast = 0;
  // Flip/Rotate/Invert/HSV/BC scope toggles: false = the active layer (or selection), true = every
  // layer of the active frame (FlipFrame*/RotateFrame/InvertFrame/SetHsvScope/SetBcScope in the
  // engine). Layer is the default.
  bool _flipFrame = false, _rotateFrame = false, _invertFrame = false, _hsvFrame = false, _bcFrame = false;
  // Move tool layer-move edge modes (mutually exclusive; both off = Regular = pixels clip off):
  bool _protectPixels = false; // keep opaque pixels on-canvas (non-destructive)
  bool _wrap = false; // pixels leaving one edge re-enter the opposite edge
  // Move tool mode: false = move the layer/pixels (default); true = move only the selection mask.
  bool _moveSelectionMode = false;
  Offset? _moveSelDragLast; // last canvas position while dragging the selection mask
  bool _onion = false;
  bool _grid = false;
  bool _overscan = false; // show the off-canvas gutter (dimmed) around the canvas
  bool _playing = false;
  Timer? _playTimer;
  Map<String, dynamic> _state = {};
  String? _error;
  final Set<int> _selLayers = {}; // layers grouped to move together with the Move tool (no selection)
  ClubEditSource? _clubSource; // set when a Club artwork is opened (enables Replace / remix)
  // Precision mode is remembered per tool: a tool name is present here while its Precision toggle
  // is on. Only tools in [_precisionTools] are ever added.
  final Set<String> _precisionOn = {};
  // precision off-finger cursor (shared by whichever paint tool is in precision mode)
  bool _penDown = false;
  Offset? _lastTouch;
  double _accX = 0, _accY = 0;
  int _cursorX = 0, _cursorY = 0; // reticle position (canvas px), mirrored from the engine
  int? _eraserX, _eraserY; // eraser footprint centre (canvas px) during an active erase drag
  // Canvas view transform: _zoom is relative to fit-to-screen (1.0 = fit), _pan is an extra
  // screen-pixel offset. Two fingers pan/zoom; the app-bar Fit button resets both.
  double _zoom = 1.0;
  Offset _pan = Offset.zero;
  // Multi-touch on the canvas: one finger draws, two+ fingers pan/zoom. While pinching, drawing is
  // suspended until all fingers lift.
  final Map<int, Offset> _touchPos = {}; // live position of every finger on the canvas
  int? _drawPointer; // the finger that owns the in-progress draw (null = none/suspended)
  bool _pinching = false;
  double _pinchStartDist = 1, _pinchStartZoom = 1;
  Offset _pinchStartMid = Offset.zero, _pinchStartPan = Offset.zero;
  // configurable bottom toolbar
  List<String> _toolOrder = tools.map((t) => t.dsl).toList();
  String? _dragTool; // tool dsl being long-press-dragged in row-3 (null = not dragging)
  int? _dropIndex; // live insertion index among the non-dragged tools (for drag preview)
  // film-roll frame thumbnails (cached, invalidated by per-frame content hash)
  final Map<int, ThumbCache> _frameThumbs = {};
  final Set<int> _thumbInFlight = {};
  // layers film-strip thumbnails, keyed by (frame,layer) and invalidated by per-layer content hash
  final Map<int, ThumbCache> _layerThumbs = {};
  final Set<int> _layerThumbInFlight = {};
  int _layerKey(int frame, int layer) => frame * 100000 + layer;

  // Whether the current tool offers a Precision toggle at all.
  bool get _precisionCapable => _precisionTools.contains(_tool);
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
  bool get _hasShapeDraft => _shapeA != null && _shapeB != null;

  // The unified "Select Shape" tool: drag → adjust reticles → Commit, like the Shape tool but the
  // payload is a selection (combined Replace/Add/Subtract/Intersect) rather than drawn pixels.
  bool get _isSelShapeTool => _tool == 'SelectShape';
  bool get _hasSelDraft => _selA != null && _selB != null;

  // The Ruler is a pure measurement overlay (no engine tool, no drawing).
  bool get _isRuler => _tool == 'Ruler';
  bool get _hasRuler => _rulerA != null && _rulerB != null;

  // Copy & Paste tool: hosts clipboard ops; a pending paste floats as a movable, semi-transparent
  // draft until committed. `_hasPasteDraft` comes from the engine state JSON.
  bool get _isCopyPaste => _tool == 'CopyPaste';
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
  bool get _isRotateHandleActive => _tool == 'Rotate' && _hasRotateDraft;
  // Handle geometry in the painter's cell-index space (sc() adds +0.5 to reach the cell centre, so
  // the geometric bbox centre is bbox-centre − 0.5). The handle's arm is half the bbox width, so
  // at angle 0 the reticle sits on the bbox's right border (see _rotDraftReticle).
  Offset get _rotDraftCenter =>
      Offset(_rotDraftRect!.left + _rotDraftRect!.width / 2 - 0.5, _rotDraftRect!.top + _rotDraftRect!.height / 2 - 0.5);
  Offset get _rotDraftCorner => Offset(_rotDraftRect!.right - 1, _rotDraftRect!.bottom - 1);

  // Whether ANY draft is pending — drives the floating commit-menu over the canvas's bottom-left
  // corner. Mirrors the per-tool guards in _commitActiveDraft/_cancelActiveDraft; at most one draft
  // can exist at a time because every tool switch cancels the outgoing tool's draft.
  bool get _hasAnyDraft =>
      (_isDraftTool && _hasShapeDraft) ||
      (_isSelShapeTool && _hasSelDraft) ||
      (_isCopyPaste && _hasPasteDraft) ||
      (_tool == 'Move' && _hasMoveDraft) ||
      (_tool == 'Rotate' && _hasRotateDraft) ||
      (_tool == 'HsvShift' && _hasHsvDraft) ||
      (_tool == 'BrightnessContrast' && _hasBcDraft);

  // A non-identity pending HSV / Brightness-Contrast adjustment is that tool's draft: it exists as
  // a display-only engine preview, and the commit-menu bakes (Commit = the old Apply) or zeroes it.
  bool get _hasHsvDraft => _hsvH != 0 || _hsvS != 0 || _hsvV != 0;
  bool get _hasBcDraft => _bcBright != 0 || _bcContrast != 0;

  bool get _engineReady => _error == null;

  @override
  void initState() {
    super.initState();
    // The editor is portrait-only (the Club side is unaffected). The shell mounts one pillar at a
    // time, so locking here / unlocking in dispose scopes the lock to the editor.
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    _antCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat();
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

  @override
  void dispose() {
    // Leaving the editor (e.g. back to Club) lifts the portrait lock so the Club side can rotate.
    SystemChrome.setPreferredOrientations(const []);
    _playTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    // Flush the in-progress drawing to disk before the engine is freed so it survives this unmount
    // (Club switch) AND any later crash. flushNow() serializes + builds metadata SYNCHRONOUSLY (so
    // the async write below never touches the freed engine); stop() then cancels the timer and lets
    // that write complete. Replaces the old in-memory EditorSession snapshot.
    if (_engineReady) _autosave?.flushNow();
    _autosave?.stop();
    _antCtrl.dispose();
    for (final t in _frameThumbs.values) {
      t.img.dispose();
    }
    _frameThumbs.clear();
    for (final t in _layerThumbs.values) {
      t.img.dispose();
    }
    _layerThumbs.clear();
    _imageVN.value?.dispose(); // release the composited canvas image before the notifier [F-10]
    _imageVN.dispose();
    _overlayVN.dispose();
    if (_engineReady) engine.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android can kill a backgrounded app with no further callback, so flush the moment we lose
    // foreground. flushNow() serializes synchronously; the write finishes in the background.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _autosave?.flushNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    // club → editor bridge: when the Club UI requests an edit, load it.
    ref.listen<ClubEditRequest?>(pendingClubEditProvider, (prev, next) {
      if (next != null) _consumeClubEdit(next);
    });
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
    // keeps it clear of the status bar; the bottom inset is handled by the tooltip band.
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildFilmRoll(), // frame film-strip + ☰ menu — the topmost area
            // ClipRect so a zoomed canvas can't paint outside its region (the CustomPaint draws the
            // scaled image past its box otherwise) — it stays behind the film-strip and bottom rows.
            // Two compact pills float over the canvas area, ABOVE the canvas Listener, so their taps
            // never fall through and start a draw gesture beneath them: the selection-menu on the
            // bottom-right and the commit-menu (cancel/commit of the pending draft) on the bottom-left.
            Expanded(
              child: ClipRect(
                child: Stack(fit: StackFit.expand, children: [
                  _buildCanvas(),
                  if (_selectionEdges.isNotEmpty)
                    Positioned(right: 10, bottom: 10, child: _selectionMenu()),
                  if (_hasAnyDraft)
                    Positioned(left: 10, bottom: 10, child: _commitMenu()),
                ]),
              ),
            ),
            const Divider(height: 1),
            _buildLayers(layers), // layers film-strip, directly above the tool options
            _buildToolOptions(), // row-1
            _buildPalette(), // row-2
            _buildToolBar(), // row-3 (also holds the pinned Undo/Redo and the Onion toggle)
            _buildTooltipBand(context),
          ],
        ),
      ),
    );
  }
}
