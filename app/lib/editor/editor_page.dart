// Makapix Editor — the animated pixel-art editor pillar. Smartphone-first three-row UI
// (SPEC §20) over the deterministic Rust engine: the engine owns the document; this shell
// captures input and presents composited buffers. One of the app's two co-equal pillars
// (see lib/shell/app_shell.dart); reachable without signing in.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:makapix_club/club/edit/club_edit_request.dart';
import 'package:makapix_club/club/publish/publish_draft.dart';
import 'package:makapix_club/club/state/edit_bridge.dart';
import 'package:makapix_club/club/ui/publish_page.dart';
import 'package:makapix_club/engine_ffi.dart';

import 'editor_session.dart';
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

const double _kMinZoom = 0.25, _kMaxZoom = 32.0;
const _prefsKey = 'tool_order_v1';
const _transformTools = {'Flip', 'Rotate', 'Invert', 'Resize'};
// Row-3 "action" tools in the reorderable grid: tapping fires an action/toggle immediately rather
// than selecting a draw tool (handled in _toolTile / _doToolAction). Undo/Redo are NOT here — they
// are pinned at the left of row-3 (see _buildToolBar / _pinnedActionTile).
const _actionTools = {'PlayPause', 'Onion'};
// Paint tools that support a "Precision" mode (off-finger reticle + draw-by-button). Precision is
// a per-tool toggle, remembered independently per tool — see [_precisionTools].
const _precisionTools = {'Pencil', 'Brush', 'Airbrush', 'Eraser'};

class EditorPage extends ConsumerStatefulWidget {
  const EditorPage({super.key});
  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends ConsumerState<EditorPage> with SingleTickerProviderStateMixin {
  late Engine engine;
  ui.Image? _image;
  late AnimationController _antCtrl; // marching-ants animation phase
  List<List<int>> _outlineEdges = const []; // each: [x1,y1,x2,y2,t] in canvas-corner coords
  String _tool = 'Pencil';
  Color _primary = const Color(0xFF000000);
  List<Color> _palette = [];
  int _brushSize = 1;
  bool _round = true;
  int _threshold = 16;
  bool _contiguous = true;
  bool _shapeFill = true;
  int _lineWidth = 1; // stroke thickness for Line and outline Rectangle/Ellipse (engine line_width)
  bool _lockRatio = false; // Rect/Ellipse: constrain width:height to _ratio (1 = square/circle)
  double _ratio = 1.0; // locked aspect ratio (width / height)
  // Pending figure draft (Line/Rect/Ellipse): two endpoints in canvas-pixel coords, or null when
  // no uncommitted figure. While set, a live preview + draggable handles show and row-1 gets
  // Commit/Cancel; nothing is written to the layer until Commit.
  Offset? _shapeA, _shapeB;
  int _shapeDrag = 0; // active gesture: 0=none, 1=dragging A, 2=dragging B, 3=drawing a new figure
  // Start point of a not-yet-materialized new figure: when a press lands off the handles over an
  // existing draft, we defer replacing it until the finger actually moves, so a pinch-zoom or a
  // stray tap leaves the current draft intact.
  Offset? _newShapeStart;
  // Ruler tool: a non-destructive measurement line (two draggable endpoints in canvas-pixel
  // coords). Never drawn to the canvas; cleared when switching tools.
  Offset? _rulerA, _rulerB;
  int _rulerDrag = 0; // 0=none, 1=dragging A, 2=dragging B, 3=drawing a new measurement
  bool _radial = false;
  int _intensity = 128;
  int _spacing = 25; // Brush/Airbrush stamp spacing, % of brush size (engine spacing)
  String _selMode = 'Replace';
  Color _gradA = const Color(0xFF102040);
  Color _gradB = const Color(0xFFFFFFFF);
  double _hsvH = 60, _hsvS = 0, _hsvV = 0;
  bool _protectPixels = false; // Move-Layer: keep opaque pixels on-canvas (non-destructive)
  bool _onion = false;
  bool _grid = false;
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

  // Off-finger "reticle" mode: dragging moves a cursor (drawn as a screen-space marching-ants
  // overlay) rather than the finger, and an action button effects one operation at a time. This
  // is exactly the active tool being in precision mode.
  bool get _isCursorTool => _isPrecision;

  // Figure tools draw via the draft flow (drag → adjust handles → commit), not immediate-on-release.
  bool get _isShapeTool => _tool == 'Line' || _tool == 'Rectangle' || _tool == 'Ellipse';
  bool get _hasShapeDraft => _shapeA != null && _shapeB != null;

  // The Ruler is a pure measurement overlay (no engine tool, no drawing).
  bool get _isRuler => _tool == 'Ruler';
  bool get _hasRuler => _rulerA != null && _rulerB != null;

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
      // Restore the document the user was working on before they last left the editor
      // (the shell mounts one pillar at a time, so EditorPage is recreated on re-entry).
      final snap = EditorSession.docSnapshot;
      if (snap != null && snap.isNotEmpty) engine.load(snap);
      _refreshState();
      _redraw();
    } catch (e) {
      _error = '$e';
    }
  }

  @override
  void dispose() {
    // Leaving the editor (e.g. back to Club) lifts the portrait lock so the Club side can rotate.
    SystemChrome.setPreferredOrientations(const []);
    _playTimer?.cancel();
    // Snapshot the in-progress document so it survives this unmount (e.g. switching to
    // Club and back). Lossless .mkpx bytes; save before the engine is freed.
    if (_engineReady) {
      try {
        final bytes = engine.save();
        if (bytes.isNotEmpty) EditorSession.docSnapshot = bytes;
      } catch (_) {/* keep the previous snapshot if saving fails */}
    }
    _antCtrl.dispose();
    for (final t in _frameThumbs.values) {
      t.img.dispose();
    }
    _frameThumbs.clear();
    for (final t in _layerThumbs.values) {
      t.img.dispose();
    }
    _layerThumbs.clear();
    if (_engineReady) engine.dispose();
    super.dispose();
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
            Expanded(child: _buildCanvas()),
            const Divider(height: 1),
            _buildLayers(layers), // layers film-strip, directly above the tool options
            _buildToolOptions(), // row-1
            _buildPalette(), // row-2
            _buildToolBar(), // row-3 (now also holds Undo/Redo/Play-Pause/Onion)
            _buildTooltipBand(context),
          ],
        ),
      ),
    );
  }
}
