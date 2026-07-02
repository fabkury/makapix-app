part of 'editor_page.dart';
// ignore_for_file: invalid_use_of_protected_member
// (These extensions are part of _EditorPageState — a State subclass — so calling the
// @protected setState here is safe; the analyzer's check is a false positive for the
// part/extension split that keeps each editor file focused and under ~400 lines.)

// Engine/DSL plumbing, document state sync, tool selection, cursor, colour helpers,
// view transform (fit/pan/zoom), playback, and tool-order persistence.
extension _EditorEngine on _EditorPageState {

  ToolDef _toolDef(String dsl) => tools.firstWhere((t) => t.dsl == dsl, orElse: () => tools.first);

  Future<void> _loadToolOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_prefsKey);
      final all = tools.map((t) => t.dsl).toList();
      if (saved != null) {
        // keep saved order, drop unknown tools, append any new tools at the end
        final reconciled = <String>[for (final d in saved) if (all.contains(d)) d];
        for (final d in all) {
          if (!reconciled.contains(d)) reconciled.add(d);
        }
        if (mounted) setState(() => _toolOrder = reconciled);
      }
    } catch (_) {/* prefs unavailable → keep default order */}
  }

  Future<void> _persistOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKey, _toolOrder);
    } catch (_) {}
  }

  // The row-3 order to display: while dragging, the dragged tool is placed at the live drop index
  // among the other tools, so the menu rearranges in real time as a preview.
  List<String> _displayToolOrder() {
    if (_dragTool == null) return _toolOrder;
    final others = _toolOrder.where((t) => t != _dragTool).toList();
    final drop = (_dropIndex ?? others.length).clamp(0, others.length);
    return [...others.sublist(0, drop), _dragTool!, ...others.sublist(drop)];
  }

  // Commit the live-previewed order when the drag ends.
  void _commitToolDrag() {
    if (_dragTool == null) return;
    final order = _displayToolOrder();
    setState(() {
      _toolOrder = order;
      _dragTool = null;
      _dropIndex = null;
    });
    _persistOrder();
  }

  // Pull the selection (or live drag-preview) mask and turn it into thin boundary segments
  // for the screen-space marching-ants overlay.
  // Refetch the selection mask (FFI + O(w·h) scan) and cache its boundary segments. Call this only
  // when the selection may have changed (a selection tool acted, or a discrete action ran) — NOT on
  // every paint move; the cheap [_rebuildOutlineEdges] handles per-move footprint updates. [F-11]
  void _updateOutline() {
    if (!_engineReady) return;
    // Trace in display coordinates (storage-sized under overscan); the outline overlay is drawn at
    // the same image offset as the display, so gutter marquees line up with the shown pixels.
    final w = engine.displayWidth, h = engine.displayHeight;
    final mask = engine.outlineMask();
    final edges = <List<int>>[];
    if (mask.isNotEmpty && mask.length >= w * h) {
      bool sel(int x, int y) => x >= 0 && y >= 0 && x < w && y < h && mask[y * w + x] != 0;
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          if (mask[y * w + x] == 0) continue;
          final t = x + y;
          if (!sel(x - 1, y)) edges.add([x, y, x, y + 1, t]);
          if (!sel(x + 1, y)) edges.add([x + 1, y, x + 1, y + 1, t]);
          if (!sel(x, y - 1)) edges.add([x, y, x + 1, y, t]);
          if (!sel(x, y + 1)) edges.add([x, y + 1, x + 1, y + 1, t]);
        }
      }
    }
    _selectionEdges = edges;
    _rebuildOutlineEdges();
  }

  // Recompose the overlay edge list from the cached selection marquee plus the live eraser
  // footprint. Cheap (no FFI, no full-canvas scan): safe to call on every eraser move. [F-11]
  void _rebuildOutlineEdges() {
    if (_eraserX != null && _eraserY != null) {
      // While erasing, outline the eraser footprint at its current position so the user sees
      // exactly which pixels are being erased.
      _outlineEdges = [..._selectionEdges, ..._footprintEdges(_eraserX!, _eraserY!, airbrush: false)];
    } else {
      _outlineEdges = _selectionEdges;
    }
  }

  // The exact set of canvas pixels a stamp/spray at (ex,ey) would cover with the current Size and
  // Shape, clipped to the canvas — mirrors the engine so an outline of these pixels is faithful.
  // `airbrush` uses the spray disc (radius == size, an approximation of the random dab); otherwise
  // it's the brush/eraser stamp footprint (radius == (size-1)/2, Round disc or Square).
  Set<int> _footprintCells(int ex, int ey, {required bool airbrush}) {
    final w = engine.width, h = engine.height;
    final size = _brushSize < 1 ? 1 : _brushSize;
    final covered = <int>{};
    void add(int x, int y) {
      if (x < 0 || y < 0 || x >= w || y >= h) return;
      covered.add(y * w + x);
    }
    if (_tool == 'Eyedropper') {
      add(ex, ey); // samples exactly the reticle pixel (ignores brush size)
      return covered;
    }
    if (airbrush) {
      final r = size; // engine airbrush_dab sprays within radius == size
      for (var dy = -r; dy <= r; dy++) {
        for (var dx = -r; dx <= r; dx++) {
          if (dx * dx + dy * dy <= r * r) add(ex + dx, ey + dy);
        }
      }
    } else if (_round) {
      if (size <= 1) {
        add(ex, ey);
      } else {
        final r = ((size - 1) ~/ 2).clamp(1, size);
        for (var dy = -r; dy <= r; dy++) {
          for (var dx = -r; dx <= r; dx++) {
            if (dx * dx + dy * dy <= r * r) add(ex + dx, ey + dy);
          }
        }
      }
    } else {
      final r = (size - 1) ~/ 2;
      for (var dy = -r; dy <= r; dy++) {
        for (var dx = -r; dx <= r; dx++) {
          add(ex + dx, ey + dy);
        }
      }
    }
    return covered;
  }

  // Boundary segments (canvas-corner coords, with a marching-ants phase `t`) around a footprint.
  List<List<int>> _footprintEdges(int ex, int ey, {required bool airbrush}) {
    final w = engine.width;
    final covered = _footprintCells(ex, ey, airbrush: airbrush);
    final edges = <List<int>>[];
    bool cov(int x, int y) => covered.contains(y * w + x);
    for (final key in covered) {
      final x = key % w, y = key ~/ w;
      final t = x + y;
      if (!cov(x - 1, y)) edges.add([x, y, x, y + 1, t]);
      if (!cov(x + 1, y)) edges.add([x + 1, y, x + 1, y + 1, t]);
      if (!cov(x, y - 1)) edges.add([x, y, x + 1, y, t]);
      if (!cov(x, y + 1)) edges.add([x, y + 1, x + 1, y + 1, t]);
    }
    return edges;
  }

  String _hex(Color c) {
    String two(int x) => x.toRadixString(16).padLeft(2, '0');
    final v = c.toARGB32(); // 8-bit ARGB, reordered to #RRGGBBAA
    return '#${two((v >> 16) & 0xFF)}${two((v >> 8) & 0xFF)}${two(v & 0xFF)}${two((v >> 24) & 0xFF)}'.toUpperCase();
  }

  Color _parseHex(String h) {
    h = h.replaceAll('#', '');
    if (h.length == 6) h = '${h}FF';
    final v = int.parse(h, radix: 16);
    return Color.fromARGB(v & 0xFF, (v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF);
  }

  void _send(String dsl) {
    if (!_engineReady) return;
    final err = engine.run(dsl);
    if (err != null) debugPrint('DSL error: $err  <- $dsl');
    _autosave?.markActivity(); // every document mutation funnels through here (gates the autosave)
  }

  // Recomposite the canvas and refresh overlays.
  //   full            — true: setState (rebuild the whole tree incl. film-roll/layer strips);
  //                      false: bump _overlayVN only (repaint canvas + overlays, leave the strips).
  //                      Freehand strokes use false so the per-tile-FFI strips don't rebuild on
  //                      every pointer move; the strips refresh once on stroke end. [audit F-9]
  //   refetchSelection — true: re-pull the selection mask (FFI + O(w·h) scan); false: just recombine
  //                      the cached marquee with the live eraser footprint (cheap). [audit F-11]
  Future<void> _redraw({bool full = true, bool refetchSelection = true}) async {
    if (!_engineReady) return;
    if (refetchSelection) {
      _updateOutline();
    } else {
      _rebuildOutlineEdges();
    }
    final frame = _playing ? engine.playFrame : engine.activeFrame;
    // Playback composites the canvas; editing uses the display, which is storage-sized (canvas +
    // gutter) under the overscan view. Size the decode to whichever we asked for.
    final bytes = _playing
        ? engine.compositeFrame(frame)
        // grid:false — the pixel grid is drawn as a thin screen-space overlay (GridPainter), not
        // baked into the upscaled canvas where it would render as thick lines.
        : engine.display(onion: _onion, grid: false, checker: true);
    final (w, h) = _playing ? (engine.width, engine.height) : (engine.displayWidth, engine.displayHeight);
    final img = await _decode(bytes, w, h);
    if (!mounted) {
      img.dispose(); // we navigated away mid-decode; don't leak the GPU image [audit F-10]
      return;
    }
    final old = _imageVN.value;
    _imageVN.value = img;
    old?.dispose(); // release the previous composited image (was leaked every redraw) [audit F-10]
    if (full) {
      setState(() {}); // rebuild the whole tree (overlays + strips + tool rows)
    } else {
      _overlayVN.value++; // repaint just the canvas overlays; leave the strips/rows alone [F-9]
    }
  }

  // Playback frame advance: repaints ONLY the canvas (via the image notifier), with no full-tree
  // setState — so the row-3 tiles stay stable and tappable (e.g. to Pause) during playback.
  Future<void> _advancePlayFrame() async {
    if (!_engineReady || !_playing) return;
    _send('AdvanceClock(33)');
    final img = await _decode(engine.compositeFrame(engine.playFrame), engine.width, engine.height);
    if (mounted && _playing) {
      final old = _imageVN.value;
      _imageVN.value = img;
      old?.dispose(); // [audit F-10] — was orphaning ~30 GPU images/sec during playback
    } else {
      img.dispose(); // paused/unmounted during decode: dispose the unused frame [audit F-10]
    }
  }

  void _refreshState() {
    if (!_engineReady) return;
    try {
      _state = json.decode(engine.stateJson()) as Map<String, dynamic>;
      // The Ruler's endpoints are canvas pixels; if the canvas dimensions changed (New / resize /
      // crop / open / import / a loaded Club artwork), the line is stale, so clear it.
      final w = engine.width, h = engine.height;
      if (_hasRuler && (w != _canvasW || h != _canvasH)) {
        _rulerA = null;
        _rulerB = null;
        _rulerDrag = 0;
      }
      _canvasW = w;
      _canvasH = h;
      _hasPasteDraft = _state['paste'] != null; // [x,y,w,h] when a paste draft is floating, else null
      _hasMoveDraft = _state['move_draft'] != null; // [x,y,w,h] when a move draft is pending, else null
      // {x,y,w,h,angle_mrad} while a Rotate "Angle" draft is open, else null.
      final rd = _state['rotate_draft'];
      if (rd is Map) {
        _hasRotateDraft = true;
        _rotDraftRect = Rect.fromLTWH(
          (rd['x'] as num).toDouble(),
          (rd['y'] as num).toDouble(),
          (rd['w'] as num).toDouble(),
          (rd['h'] as num).toDouble(),
        );
        _rotDraftAngle = ((rd['angle_mrad'] as num?)?.toDouble() ?? 0) / 1000.0;
      } else {
        _hasRotateDraft = false;
        _rotDraftRect = null;
        _rotateDragging = false;
      }
      final pal = (_state['palette'] as List?)?.cast<String>() ?? [];
      _palette = pal.map(_parseHex).toList();
      final pc = engine.primaryColor;
      _primary = Color.fromARGB(pc & 0xFF, (pc >> 24) & 0xFF, (pc >> 16) & 0xFF, (pc >> 8) & 0xFF);
    } catch (_) {}
  }

  Future<ui.Image> _decode(Uint8List bytes, int w, int h) {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(bytes, w, h, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  }

  Future<ui.Image> _decodeBytes(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  void _act(String dsl) {
    _send(dsl);
    _refreshState();
    _redraw();
    setState(() {});
  }

  void _selectTool(String t) {
    // Select Layer paints a live cyan alpha overlay into the composited image while it is the active
    // engine tool; leaving it must drop the engine off Select Layer and redraw so the shading clears.
    final leavingSelectLayer = _tool == 'SelectLayer' && t != 'SelectLayer';
    if (_playing) _pause(); // selecting another tool stops the animation preview
    if (_penDown) {
      _send('CursorPenUp()');
      _penDown = false;
    }
    // Navigating away mid-draft (changing tools) cancels the pending figure and erases its preview
    // — same as the row-1 Cancel button (this also redraws, so the outline doesn't linger).
    if (_hasShapeDraft) _cancelShapeDraft();
    // Likewise, a pending Select Shape draft is discarded (and its ants erased) when leaving the tool.
    if (_hasSelDraft) _cancelSelDraft();
    // Likewise, a pending paste draft is cancelled & erased when leaving the Copy & Paste tool.
    if (_hasPasteDraft) {
      _send('PasteCancel()');
      _hasPasteDraft = false;
      _pasteDragLast = null;
      _redraw();
    }
    // A pending move draft is discarded when navigating away (same as its row-1 Cancel button).
    if (_hasMoveDraft) {
      _send('MoveDraftCancel()');
      _hasMoveDraft = false;
      _moveDragLast = null;
      _moveDraftStarted = false;
      _redraw();
    }
    // A pending rotate (Angle) draft is likewise discarded when leaving the Rotate tool.
    if (_hasRotateDraft) {
      _send('RotateDraftCancel()');
      _hasRotateDraft = false;
      _rotateDragging = false;
      _redraw();
    }
    // The Ruler keeps its measurement across tool switches (its overlay just hides while another
    // tool is active and reappears on return); clear it with the Ruler's row-1 "Clear" button.
    _rulerDrag = 0;
    setState(() => _tool = t);
    if (_transformTools.contains(t) || t == 'PlayPause') {
      // UI-only group (the transform groups and the Play tool): no engine draw-tool change — the
      // engine has no such ToolKind and the canvas is inert. But if we left Select Layer, move the
      // engine off it (any non-preview tool) and redraw so its cyan overlay clears.
      if (leavingSelectLayer) {
        _send('SelectTool(Move)');
        _redraw();
      }
      return;
    }
    if (t == 'Shape') {
      _send('SelectTool($_shapeKind)'); // 'Shape' is a shell grouping; engine draws by ToolKind
    } else if (t == 'SelectShape') {
      // 'SelectShape' is a shell grouping over the engine's SelectRect/SelectEllipse selection tools.
      _send('SelectTool(${_selShapeKind == 'Ellipse' ? 'SelectEllipse' : 'SelectRect'})');
    } else if (t != 'Ruler') {
      _send('SelectTool($t)'); // Ruler is a pure overlay; no engine draw tool
    } else if (leavingSelectLayer) {
      _send('SelectTool(Move)'); // Ruler sends no draw tool — clear the Select Layer overlay
    }
    // Entering a tool that remembers precision-on re-centres the reticle.
    if (_precisionOn.contains(t)) {
      _setCursor(engine.width ~/ 2, engine.height ~/ 2);
      _redraw();
    }
    _send('SetBrushSize($_brushSize); SetBrushShape(${_round ? 'Round' : 'Square'})');
    _send('SetThreshold($_threshold); SetContiguous($_contiguous); SetAlphaCutoff($_alphaCutoff)');
    _send('SetIntensity($_intensity); SetShapeFill($_shapeFill); SetLineWidth($_lineWidth)');
    _send('SetSpacing($_spacing); SetFillAllLayers($_fillAllLayers)');
    _send('SetSelectionMode($_selMode); SetProtectPixels($_protectPixels); SetWrap($_wrap)');
    _send('SetPixelPerfect($_perfect); SetOverscanView(${_overscan ? 1 : 0})');
    if (t == 'Gradient') {
      _send('SetGradientType(${_radial ? 'Radial' : 'Linear'})');
      _send('SetGradientSmoothstep($_gradSmooth)');
      _send(_gradStopsDsl());
    }
    // Show Select Layer's overlay immediately on entry; clear it (redraw) when leaving it.
    if (t == 'SelectLayer' || leavingSelectLayer) _redraw();
  }

  // Rasterize the pending figure draft into the active layer, then clear the handles/buttons.
  void _commitShape() {
    _send('ShapeCommit()');
    setState(() {
      _shapeA = null;
      _shapeB = null;
      _shapeDrag = 0;
      _shapeRot = 0;
      _triTip = 0;
    });
    _refreshState();
    _redraw();
  }

  // Discard the pending figure draft without drawing anything.
  void _cancelShapeDraft() {
    _send('ShapeCancel()');
    setState(() {
      _shapeA = null;
      _shapeB = null;
      _shapeDrag = 0;
      _shapeRot = 0;
      _triTip = 0;
    });
    _redraw();
  }

  // Commit the pending selection draft into the real selection. The engine tool is already
  // SelectRect/SelectEllipse, so replaying the draft as one pointer drag runs the engine's immediate
  // selection path — combining the rect/ellipse into the current selection (Replace/Add/Subtract/
  // Intersect) as one undo step — exactly as before, just deferred behind the draft.
  void _commitSelDraft() {
    if (!_hasSelDraft) return;
    final a = _selA!, b = _selB!;
    _send('PointerDown(${a.dx.round()},${a.dy.round()})');
    _send('PointerMove(${b.dx.round()},${b.dy.round()})');
    _send('PointerUp()');
    setState(() {
      _selA = null;
      _selB = null;
      _selDrag = 0;
      _selDraftEdges = const [];
    });
    _refreshState(); // pick up the new selection + undo/redo availability
    _redraw(); // the committed selection's marching ants replace the draft's
  }

  // Discard the pending selection draft without changing the selection (just drops the draft ants).
  void _cancelSelDraft() {
    setState(() {
      _selA = null;
      _selB = null;
      _selDrag = 0;
      _selDraftEdges = const [];
    });
  }

  // Finalize the pending move draft as one undo step (drops the "pending" wash).
  void _commitMoveDraft() {
    _send('MoveDraftCommit()');
    _moveDragLast = null;
    _moveDraftStarted = false;
    _refreshState(); // clears _hasMoveDraft (move_draft → null)
    _redraw();
    setState(() {});
  }

  // Discard the pending move draft, restoring the pixels (and marquee) to where they were.
  void _cancelMoveDraft() {
    _send('MoveDraftCancel()');
    _moveDragLast = null;
    _moveDraftStarted = false;
    _refreshState();
    _redraw();
    setState(() {});
  }

  // Toggle the active paint tool's precision (off-finger reticle) mode. Remembered per tool.
  void _setPrecision(bool on) {
    if (!_precisionCapable) return;
    // Leaving precision while a pen line is mid-stroke commits it cleanly.
    if (!on && _penDown) {
      _send('CursorPenUp()');
      _penDown = false;
    }
    setState(() {
      if (on) {
        _precisionOn.add(_tool);
      } else {
        _precisionOn.remove(_tool);
      }
    });
    if (on) _setCursor(engine.width ~/ 2, engine.height ~/ 2); // park the reticle in the centre
    _redraw();
  }

  void _setPrimary(Color c) {
    setState(() => _primary = c);
    _send('SetPrimaryColor(${_hex(c)})');
    if (_tool == 'Gradient') {
      // The gradient's first colour IS the primary, so re-push the stops (refreshes a draft too).
      _sendGradientStops();
    } else if (_hasShapeDraft) {
      // A pending figure draft (Line/Rect/Ellipse) is drawn in the primary colour — refresh its
      // preview now instead of waiting for the next drag.
      _redraw();
    }
  }

  // The gradient's colours: the primary first, then the independent extras, evenly spaced 0..1.
  List<Color> _gradColors() => [_primary, ..._gradExtra.take(_gradCount - 1)];

  String _gradStopsDsl() {
    final colors = _gradColors();
    final n = colors.length;
    final parts = [for (var i = 0; i < n; i++) '${_hex(colors[i])}@${(i / (n - 1)).toStringAsFixed(4)}'];
    return 'SetGradientStops([${parts.join(', ')}])';
  }

  void _sendGradientStops() {
    _send(_gradStopsDsl());
    if (_hasShapeDraft) _redraw(); // a pending gradient draft updates its preview live
  }

  // Place the reticle at an absolute canvas pixel, mirroring the engine's clamping.
  void _setCursor(int x, int y) {
    _cursorX = x.clamp(0, engine.width - 1);
    _cursorY = y.clamp(0, engine.height - 1);
    _send('SetCursor($_cursorX,$_cursorY)');
  }

  // Move the reticle by a pixel delta. Uses MoveCursor so the engine still paints the precision
  // pen line while the pen is down; the local mirror clamps identically to stay in sync.
  void _moveCursor(int dx, int dy) {
    _cursorX = (_cursorX + dx).clamp(0, engine.width - 1);
    _cursorY = (_cursorY + dy).clamp(0, engine.height - 1);
    _send('MoveCursor($dx,$dy)');
  }

  void _nudgeCursor(int dx, int dy) {
    _moveCursor(dx, dy);
    _redraw();
  }

  // ---- canvas view transform (fit + two-finger pan/zoom) ----

  // Screen pixels per canvas pixel when fit-to-screen (zoom == 1).
  double _fitScale(Size box) {
    final sx = box.width / engine.width, sy = box.height / engine.height;
    return sx < sy ? sx : sy;
  }

  // Top-left of the canvas, in screen pixels, if it were centred at scale [s].
  Offset _centeredOffset(Size box, double s) =>
      Offset((box.width - engine.width * s) / 2, (box.height - engine.height * s) / 2);

  // The effective view: (scale = screen px per canvas px, topLeft = canvas origin in screen px),
  // for a given zoom/pan. Defaults to the current _zoom/_pan.
  (double, Offset) _view(Size box, {double? zoom, Offset? pan}) {
    final z = zoom ?? _zoom;
    final s = _fitScale(box) * z;
    return (s, _centeredOffset(box, s) + (pan ?? _pan));
  }

  // Screen-space top-left of the (storage-sized under overscan) display image. The view transform
  // keeps the *canvas* fixed; the image's origin sits `gutter` canvas-pixels up-and-left of the
  // canvas so the canvas lands at the same place either way. Equals `off` in the normal view.
  Offset _imageOffset(double scale, Offset off) {
    final gx = (engine.displayWidth - engine.width) / 2.0;
    final gy = (engine.displayHeight - engine.height) / 2.0;
    return off - Offset(gx * scale, gy * scale);
  }

  Offset _toCanvas(Offset local, Size box) {
    final (s, off) = _view(box);
    return Offset(((local.dx - off.dx) / s).floorToDouble(), ((local.dy - off.dy) / s).floorToDouble());
  }

  // Like _toCanvas but un-floored (sub-pixel canvas coords) — for smooth handle projection.
  Offset _toCanvasRaw(Offset local, Size box) {
    final (s, off) = _view(box);
    return Offset((local.dx - off.dx) / s, (local.dy - off.dy) / s);
  }

  void _fitView() => setState(() {
        _zoom = 1.0;
        _pan = Offset.zero;
      });

  void _startPinch() {
    final pts = _touchPos.values.toList();
    if (pts.length < 2) return;
    _pinching = true;
    _pinchStartDist = ((pts[1] - pts[0]).distance).clamp(1.0, double.infinity);
    _pinchStartMid = (pts[0] + pts[1]) / 2;
    _pinchStartZoom = _zoom;
    _pinchStartPan = _pan;
  }

  // Focal-point pinch: the canvas point under the start midpoint stays under the live midpoint,
  // while the distance ratio drives the zoom. Pan is left unclamped (zoom-out with margins is OK).
  void _updatePinch(Size box) {
    final pts = _touchPos.values.toList();
    if (pts.length < 2) return;
    final dist = (pts[1] - pts[0]).distance;
    final mid = (pts[0] + pts[1]) / 2;
    final sFit = _fitScale(box);
    final newZoom = (_pinchStartZoom * (dist / _pinchStartDist)).clamp(_kMinZoom, _kMaxZoom);
    final (s0, off0) = _view(box, zoom: _pinchStartZoom, pan: _pinchStartPan);
    final c = (_pinchStartMid - off0) / s0; // focal point in canvas space
    final s1 = sFit * newZoom;
    final off1 = mid - c * s1; // desired top-left so the focal point sits under the live midpoint
    setState(() {
      _zoom = newZoom;
      _pan = off1 - _centeredOffset(box, s1);
    });
  }

  void _play() {
    if (engine.frameCount <= 1) return;
    setState(() => _playing = true);
    _send('Play()');
    _playTimer?.cancel();
    _playTimer = Timer.periodic(const Duration(milliseconds: 33), (_) => _advancePlayFrame());
  }

  void _pause() {
    _playTimer?.cancel();
    setState(() => _playing = false);
    _send('Pause()');
    _redraw();
  }

  // Step to the previous (delta = -1) or next (delta = +1) animation frame, wrapping around the
  // ends. Pressing either auto-pauses playback first (the Play tool's contract).
  void _stepFrame(int delta) {
    if (_playing) _pause();
    final n = engine.frameCount;
    if (n <= 1) return;
    final next = ((engine.activeFrame + delta) % n + n) % n;
    _act('SetActiveFrame($next)');
  }

  // "Go to…" — prompt for a 1-based frame number and jump to it. Auto-pauses playback first; an
  // empty/out-of-range entry is clamped, and Cancel leaves the active frame unchanged.
  Future<void> _gotoFrameDialog() async {
    if (_playing) _pause();
    final n = engine.frameCount;
    final ctrl = TextEditingController(text: '${engine.activeFrame + 1}');
    ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
    final entered = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Go to frame'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: 'Frame (1 – $n)'),
          onSubmitted: (s) => Navigator.pop(ctx, int.tryParse(s.trim())),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text.trim())), child: const Text('Go')),
        ],
      ),
    );
    if (entered == null || !mounted) return;
    _act('SetActiveFrame(${(entered - 1).clamp(0, n - 1)})');
  }

}
