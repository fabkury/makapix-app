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
    final w = engine.width, h = engine.height;
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

  String _hex(Color c) =>
      '#${c.red.toRadixString(16).padLeft(2, '0')}${c.green.toRadixString(16).padLeft(2, '0')}${c.blue.toRadixString(16).padLeft(2, '0')}${c.alpha.toRadixString(16).padLeft(2, '0')}'
          .toUpperCase();

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
    final w = engine.width, h = engine.height;
    final frame = _playing ? engine.playFrame : engine.activeFrame;
    final bytes = _playing
        ? engine.compositeFrame(frame)
        : engine.display(onion: _onion, grid: _grid, checker: true);
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
    if (_playing) _pause(); // selecting another tool stops the animation preview
    if (_penDown) {
      _send('CursorPenUp()');
      _penDown = false;
    }
    // Navigating away mid-draft (changing tools) cancels the pending figure and erases its preview
    // — same as the row-1 Cancel button (this also redraws, so the outline doesn't linger).
    if (_hasShapeDraft) _cancelShapeDraft();
    // The Ruler keeps its measurement across tool switches (its overlay just hides while another
    // tool is active and reappears on return); clear it with the Ruler's row-1 "Clear" button.
    _rulerDrag = 0;
    setState(() => _tool = t);
    if (_transformTools.contains(t)) return; // UI-only action group: no engine tool change
    if (t != 'Ruler') _send('SelectTool($t)'); // Ruler is a pure overlay; no engine draw tool
    // Entering a tool that remembers precision-on re-centres the reticle.
    if (_precisionOn.contains(t)) {
      _setCursor(engine.width ~/ 2, engine.height ~/ 2);
      _redraw();
    }
    _send('SetBrushSize($_brushSize); SetBrushShape(${_round ? 'Round' : 'Square'})');
    _send('SetThreshold($_threshold); SetContiguous($_contiguous); SetAlphaCutoff($_alphaCutoff)');
    _send('SetIntensity($_intensity); SetShapeFill($_shapeFill); SetLineWidth($_lineWidth)');
    _send('SetSpacing($_spacing)');
    _send('SetSelectionMode($_selMode); SetProtectPixels($_protectPixels); SetWrap($_wrap)');
    if (t == 'Gradient') {
      _send('SetGradientType(${_radial ? 'Radial' : 'Linear'})');
      _send('SetGradientStops([${_hex(_gradA)}@0, ${_hex(_gradB)}@1])');
    }
    if (t == 'SelectLayer') _redraw(); // show the alpha-selection preview overlay immediately
  }

  // Rasterize the pending figure draft into the active layer, then clear the handles/buttons.
  void _commitShape() {
    _send('ShapeCommit()');
    setState(() {
      _shapeA = null;
      _shapeB = null;
      _shapeDrag = 0;
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
    });
    _redraw();
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

  Offset _toCanvas(Offset local, Size box) {
    final (s, off) = _view(box);
    return Offset(((local.dx - off.dx) / s).floorToDouble(), ((local.dy - off.dy) / s).floorToDouble());
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

}
