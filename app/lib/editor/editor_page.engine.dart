part of 'editor_page.dart';
// ignore_for_file: invalid_use_of_protected_member
// (These extensions are part of _EditorPageState — a State subclass — so calling the
// @protected setState here is safe; the analyzer's check is a false positive for the
// part/extension split that keeps each editor file focused and under ~400 lines.)

// Engine/DSL plumbing, document state sync, tool selection, cursor, color helpers,
// view transform (fit/pan/zoom), playback, and tool-order persistence.
extension _EditorEngine on _EditorPageState {

  ToolDef _toolDef(String dsl) => tools.firstWhere((t) => t.dsl == dsl, orElse: () => tools.first);

  Future<void> _loadToolOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_prefsKey);
      final threeRow = prefs.getBool(_prefs3RowKey); // null = never chosen → 2-row default
      final pinned3 = prefs.getString(_prefsPinnedThirdKey);
      final aa = prefs.getBool(_kAaPref) ?? false;
      final all = tools.map((t) => t.dsl).toList();
      List<String>? reconciled;
      if (saved != null) {
        // keep saved order, drop unknown tools, append any new tools at the end
        reconciled = <String>[for (final d in saved) if (all.contains(d)) d];
        for (final d in all) {
          if (!reconciled.contains(d)) reconciled.add(d);
        }
      }
      if (mounted) {
        setState(() {
          if (reconciled != null) _toolOrder = reconciled;
          _threeRowPref = threeRow;
          // validate against the catalog — a stale/removed dsl in old prefs falls back to the default
          if (pinned3 != null && tools.any((t) => t.dsl == pinned3)) _pinnedThirdTool = pinned3;
          if (aa != _aa) {
            _aa = aa;
            // The prefs read is async and can land after engine boot already pushed the
            // default — re-send so the engine agrees with the restored chip state.
            _send('SetAA($_aa)');
          }
        });
      }
    } catch (_) {/* prefs unavailable → keep defaults */}
  }

  Future<void> _persistOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKey, _toolOrder);
    } catch (_) {}
  }

  Future<void> _persistThreeRowToolbar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefs3RowKey, _threeRowToolbar);
    } catch (_) {}
  }

  Future<void> _persistPinnedThirdTool() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsPinnedThirdKey, _pinnedThirdTool);
    } catch (_) {}
  }

  Future<void> _persistAa() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kAaPref, _aa);
    } catch (_) {}
  }

  // The row-3 grid's order in *visible* space: in 3-row mode the configured pinned tool is pinned
  // beside Undo/Redo, so its tile is filtered out of the grid (it stays in _toolOrder). All drag/drop
  // indexes (_dropIndex, `others`) live in this space; in 2-row mode it is the identity.
  List<String> _visibleOrder(List<String> order) =>
      _threeRowToolbar ? order.where((d) => d != _pinnedThirdTool).toList() : order;

  // The row-3 order to display (visible space): while dragging, the dragged tool is placed at the
  // live drop index among the other tools, so the menu rearranges in real time as a preview.
  List<String> _displayToolOrder() {
    final visible = _visibleOrder(_toolOrder);
    if (_dragTool == null) return visible;
    final others = visible.where((t) => t != _dragTool).toList();
    final drop = (_dropIndex ?? others.length).clamp(0, others.length);
    return [...others.sublist(0, drop), _dragTool!, ...others.sublist(drop)];
  }

  // Commit the live-previewed order when the drag ends. The preview is in visible space, so in
  // 3-row mode the grid-hidden pinned tile is reinserted at its former index to keep the full order
  // (2-row mode must NOT reinsert: there the pinned tool is itself draggable in the grid).
  void _commitToolDrag() {
    if (_dragTool == null) return;
    // No release haptic by design: it proved unfeelable in device testing — Android can drop
    // performHapticFeedback effects (all of HapticFeedback.*) once the touch has ended. The
    // drag's haptic story is the pick-up tick plus the per-reflow ticks; don't re-add one here.
    final display = _displayToolOrder();
    final order = _threeRowToolbar ? restoreHiddenTool(display, _toolOrder, _pinnedThirdTool) : display;
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
    final w = _dispW, h = _dispH; // cached in _refreshState [battery F20]
    final mask = engine.outlineMask(); // presence-gated: empty is free [battery F13]
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
    // This path runs on per-move redraws that only bump _overlayVN (no setState/build), so sync the
    // ants clock here too — otherwise a selection appearing mid-stroke wouldn't start it. [audit]
    _syncAntsAnimation();
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
    if (_tool == 'Eyedropper' || _tool == 'SelectByColor') {
      add(ex, ey); // samples/seeds exactly the reticle pixel (ignores brush size)
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

  void _send(String dsl, {bool activity = true}) {
    if (!_engineReady) return;
    _sendSeq++; // playback decode-on-change stamp (see _onPlayTick)
    _journal?.record(dsl); // the Journal tap: verbatim, before run (record what was SENT)
    final err = engine.run(dsl);
    if (err != null) debugPrint('DSL error: $err  <- $dsl');
    // Playback verbs pass activity:false — AdvanceClock at vsync rate must not re-arm the
    // autosave 60-120×/s (docs/memory-audit/REPORT.md hotspot). Every document mutation
    // still funnels through here with the default (gates the autosave).
    if (activity) _autosave?.markActivity();
  }

  // Request a canvas recomposite + overlay refresh. [battery R1: the redraw scheduler]
  //   full            — true: setState (rebuild the whole tree incl. film-roll/layer strips);
  //                      false: bump _overlayVN only (repaint canvas + overlays, leave the strips).
  //                      Freehand strokes use false so the per-tile-FFI strips don't rebuild on
  //                      every pointer move; the strips refresh once on stroke end. [audit F-9]
  //   refetchSelection — true: re-pull the selection mask (FFI + O(w·h) scan); false: just recombine
  //                      the cached marquee with the live eraser footprint (cheap). [audit F-11]
  //
  // This only marks dirty flags; _present() does the work. An idle canvas presents
  // IMMEDIATELY (leading edge — first-touch latency unchanged); requests arriving while a
  // present is in flight or booked coalesce into one trailing present aligned to the next
  // frame. Net: ≤1 engine fetch + premultiply + decode + GPU upload per display frame, no
  // matter the input rate (before R1: one full chain per raw pointer event, 2-4× per frame
  // on fast digitizers, the surplus decoded then discarded). The presenter also setStates
  // when a full request was pending, so call sites no longer follow _redraw() with their own
  // setState(() {}) — that double rebuild re-ran the per-tile FFI hashes twice per
  // action. [battery F16] Playback frame changes route through here too (was
  // _decodePlayFrame): one publisher means decodes can't land out of order by construction,
  // which is what retired the _imageGen staleness stamp.
  void _redraw({bool full = true, bool refetchSelection = true}) {
    if (!_engineReady) return;
    _dirtyImage = true;
    _dirtyFull |= full;
    _dirtySelection |= refetchSelection;
    if (_presentInFlight || _presentBooked) return; // coalesce into the pending present
    unawaited(_present()); // leading edge: idle → present now
  }

  // The single presentation worker (see _redraw). Consumes the dirty flags at start, so
  // requests landing during the async decode gap accumulate for exactly one trailing
  // present, aligned to the next frame via scheduleFrameCallback — that alignment is what
  // bounds presents to the display rate under sustained input.
  Future<void> _present() async {
    _presentInFlight = true;
    try {
      final full = _dirtyFull;
      final refetch = _dirtySelection;
      _dirtyImage = false;
      _dirtyFull = false;
      _dirtySelection = false;
      if (refetch) {
        _updateOutline();
      } else {
        _rebuildOutlineEdges();
      }
      // Playback composites the canvas; editing uses the display, which is storage-sized (canvas +
      // gutter) under the overscan view. Size the decode to whichever we asked for.
      final playing = _playing;
      final bytes = playing
          ? engine.compositeFrame(engine.playFrame)
          // grid:false — the pixel grid is drawn as a thin screen-space overlay (GridPainter), not
          // baked into the upscaled canvas where it would render as thick lines.
          // checker:false — likewise the transparency checker: CanvasPainter draws it in screen
          // space at a fixed cell size, so it does not zoom with the artwork (which is what lets
          // painted gray checkers be distinguished from true transparency).
          : engine.display(onion: _onion, grid: false, checker: false);
      final (w, h) = playing ? (_canvasW, _canvasH) : (_dispW, _dispH); // cached [battery F20]
      final img = await _decode(bytes, w, h);
      if (!mounted) {
        img.dispose(); // we navigated away mid-decode; don't leak the GPU image [audit F-10]
        return;
      }
      final old = _imageVN.value;
      _imageIsCanvasSized = playing; // [G-23] the painter picks its offset from this
      _imageVN.value = img;
      old?.dispose(); // release the previous composited image (was leaked every redraw) [audit F-10]
      if (full) {
        setState(() {}); // rebuild the whole tree (overlays + strips + tool rows)
      } else {
        _overlayVN.value++; // repaint just the canvas overlays; leave the strips/rows alone [F-9]
      }
    } finally {
      _presentInFlight = false;
      if (_dirtyImage && mounted) {
        // Trailing edge: requests arrived while this present was in flight. Book exactly one
        // follow-up on the next frame; its flag snapshot sees the very latest engine state.
        _presentBooked = true;
        SchedulerBinding.instance.scheduleFrameCallback((_) {
          _presentBooked = false;
          if (_dirtyImage && !_presentInFlight && mounted) unawaited(_present());
        });
      }
    }
  }

  /// Surface the engine's memory-budget telemetry (SPEC §8.2b): a persistent banner while the
  /// document is over the soft budget, and a snackbar each time the engine rolled a mutation
  /// back at the hard budget. The engine is authoritative — the shell only narrates.
  void _syncMemBudgetUi() {
    final soft = _state['mem_soft_exceeded'] == true;
    final refusals = (_state['mem_refusals'] as num?)?.toInt() ?? 0;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    if (soft != _memBannerShown) {
      _memBannerShown = soft;
      messenger.hideCurrentMaterialBanner();
      if (soft) {
        final used = ((_state['mem_unique_bytes'] as num?) ?? 0) / (1024 * 1024);
        final hard = ((_state['mem_hard_budget'] as num?) ?? 1) / (1024 * 1024);
        messenger.showMaterialBanner(MaterialBanner(
          content: Text(
              'This drawing is very large (${used.toStringAsFixed(0)} of ${hard.toStringAsFixed(0)} MB). '
              'Near the limit, changes that grow it further will be blocked.'),
          leading: const Icon(Icons.data_usage),
          actions: [
            TextButton(
              onPressed: () => messenger.hideCurrentMaterialBanner(),
              child: const Text('Dismiss'),
            ),
          ],
        ));
      }
    }
    if (_memRefusalsSeen >= 0 && refusals > _memRefusalsSeen) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Blocked: that change would push the drawing over the memory limit. '
            'Reduce frames, layers or canvas size to continue growing it.'),
      ));
    }
    _memRefusalsSeen = refusals;
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
        _rulerC = null; // _rulerAngle stays: it's a UI preference, not a coordinate
        _rulerDrag = 0;
        _rulerPinned = false; // a pin never outlives its ruler (matches the Clear button)
      }
      _canvasW = w;
      _canvasH = h;
      _dispW = engine.displayWidth; // cached for the per-event hot paths [battery F20]
      _dispH = engine.displayHeight;
      _hasPasteDraft = _state['paste'] != null; // [x,y,w,h] when a paste draft is floating, else null
      _hasMoveDraft = _state['move_draft'] != null; // [x,y,w,h] when a move draft is pending, else null
      _syncMemBudgetUi();
      // {x,y,w,h,angle_mrad} while a Rotate "Angle" draft is open, else null.
      final rd = _state['rotate_draft'];
      if (rd is Map) {
        _hasRotateDraft = true;
        // A whole-layer rotate lifts the entire STORAGE (canvas + overscan gutter), so the engine's
        // rect can extend past the canvas. The handle should relate to the visible canvas — clamp.
        // The center is unaffected: the gutter is centered, so the storage center (the engine's
        // pivot) and the clamped rect's center are both the canvas center.
        _rotDraftRect = Rect.fromLTWH(
          (rd['x'] as num).toDouble(),
          (rd['y'] as num).toDouble(),
          (rd['w'] as num).toDouble(),
          (rd['h'] as num).toDouble(),
        ).intersect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
        _rotDraftAngle = ((rd['angle_mrad'] as num?)?.toDouble() ?? 0) / 1000.0;
        _rotDraftOff = Offset(
            ((rd['ox'] as num?) ?? 0).toDouble(), ((rd['oy'] as num?) ?? 0).toDouble());
      } else {
        _hasRotateDraft = false;
        _rotDraftRect = null;
        _rotateDragging = false;
        _rotDraftOff = Offset.zero;
        _rotDraftMoveLast = null;
      }
      // {x,y,w,h,sx_milli,sy_milli} while a Resize "Scale" draft is open, else null.
      final sd = _state['scale_draft'];
      if (sd is Map) {
        _hasResizeDraft = true;
        // Same canvas clamp as the rotate draft: a whole-layer lift spans the storage, and the
        // centered gutter keeps the clamped rect's center == the engine's pivot.
        _resizeDraftRect = Rect.fromLTWH(
          (sd['x'] as num).toDouble(),
          (sd['y'] as num).toDouble(),
          (sd['w'] as num).toDouble(),
          (sd['h'] as num).toDouble(),
        ).intersect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
        _resizeSx = ((sd['sx_milli'] as num?)?.toDouble() ?? 1000) / 1000.0;
        _resizeSy = ((sd['sy_milli'] as num?)?.toDouble() ?? 1000) / 1000.0;
        _resizeDraftOff = Offset(
            ((sd['ox'] as num?) ?? 0).toDouble(), ((sd['oy'] as num?) ?? 0).toDouble());
      } else {
        _hasResizeDraft = false;
        _resizeDraftRect = null;
        _resizeDragging = false;
        _resizeDraftOff = Offset.zero;
        _resizeDraftMoveLast = null;
      }
      final pal = (_state['palette'] as List?)?.cast<String>() ?? [];
      _palette = pal.map(_parseHex).toList();
      // Optional per-entry display names, aligned with _palette ('' = unnamed → null).
      final palNames = (_state['palette_color_names'] as List?)?.cast<String>() ?? [];
      _paletteNames = [
        for (var i = 0; i < _palette.length; i++)
          (i < palNames.length && palNames[i].isNotEmpty) ? palNames[i] : null,
      ];
      _primary = _colorFromPacked(engine.primaryColor);
    } catch (_) {}
  }

  Color _colorFromPacked(int pc) =>
      Color.fromARGB(pc & 0xFF, (pc >> 24) & 0xFF, (pc >> 16) & 0xFF, (pc >> 8) & 0xFF);

  // Live eyedropper feedback: pull the primary back after each pointer pick so the row-2 swatch
  // tracks the finger during a drag. The scalar FFI getter is cheap; the full-page setState is
  // gated on an actual color change so uniform areas don't rebuild the strips per move event.
  void _syncPickedPrimary() {
    final c = _colorFromPacked(engine.primaryColor);
    if (c == _primary) return;
    // [G-48] An engine-side pick IS a primary change: record the outgoing color, so the swap
    // Command restores what the artist was actually using rather than a stale earlier color.
    _previousPrimary = _primary;
    setState(() => _primary = c);
    // [G-47] The Gradient tool keeps its stops in the engine. A pick changed the first swatch,
    // so push them again or the gradient keeps drawing the colour that was replaced.
    if (_tool == 'Gradient') _sendGradientStops();
  }

  Future<ui.Image> _decode(Uint8List bytes, int w, int h) {
    BatteryStats.decode();
    final c = Completer<ui.Image>();
    // The engine emits straight alpha; the raw decode expects premultiplied. Matters now that
    // the display buffer carries real transparency (the checker is no longer baked into it).
    premultiplyRgbaInPlace(bytes);
    ui.decodeImageFromPixels(bytes, w, h, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  }

  Future<ui.Image> _decodeBytes(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose(); // release the codec's decode state (a whole animation for GIF/APNG) [audit]
    }
  }

  /// The single funnel every Command's DSL passes through — and therefore where two policies
  /// live (ADR 0010 gesture atomicity, ADR 0012 playback-as-a-mode) instead of at ~40 call sites.
  ///
  ///  * an in-flight Gesture is FINISHED first, as if the artist lifted, and only then does the
  ///    Command run (Esc/Undo/Redo take _cancelInteraction instead — see the dispatcher);
  ///  * playback pauses before any editing intent, so nothing lands on a frame that is not the
  ///    one on screen. Transport and pure-view verbs are the only exemptions.
  ///
  /// Gesture traffic itself uses [_send] directly and so never re-enters this gate.
  void _act(String dsl) {
    _finishInteraction();
    if (_isContextChangeVerb(dsl)) {
      _cancelDraftsForContextChange();
    } else if (_isBlankLayerVerb(dsl)) {
      _cancelLayerBoundDraftsForBlankLayer();
    }
    if (_playing && !_isTransportOrViewVerb(dsl)) _pause();
    _send(dsl);
    _refreshState();
    _redraw();
    // A frame-structure verb may move the active frame (or leave it partially scrolled out of the
    // film-roll, e.g. a frame inserted at the strip's trailing edge). Reveal it once the roll has
    // laid out the new tile count — the same ease/snap rule the Play tool's frame jumps use.
    if (_isFrameStructureVerb(dsl)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureActiveFrameVisible();
      });
    }
  }

  /// Verbs that add, duplicate, remove, or reorder animation frames — after any of these the
  /// film-roll scrolls just enough to keep the active frame fully visible.
  static bool _isFrameStructureVerb(String dsl) {
    for (final part in dsl.split(';')) {
      final name = part.trim().split('(').first.trim();
      if (name == 'AddFrame' ||
          name == 'AddFrameAt' ||
          name == 'DuplicateFrame' ||
          name == 'RemoveFrame' ||
          name == 'ReorderFrame') {
        return true;
      }
    }
    return false;
  }

  /// Verbs that may run while playback is running (ADR 0012). Everything else is editing intent
  /// and pauses first; the default direction is deliberately "pauses", so a new verb is safe.
  static bool _isTransportOrViewVerb(String dsl) {
    for (final part in dsl.split(';')) {
      final t = part.trim();
      if (t.isEmpty) continue;
      final name = t.split('(').first.trim();
      if (name != 'Play' && name != 'Pause' && name != 'AdvanceClock' && name != 'Stop') {
        return false;
      }
    }
    return true;
  }

  /// Verbs that move the artist to another frame or layer. ADR 0011 makes those context
  /// changes, so every open Draft dies with them — nothing can commit onto a surface the artist
  /// is no longer looking at [G-13, G-15, G-16]. Besides the explicit activations, every verb
  /// that creates, duplicates, removes, or merges a frame/layer counts: the engine activates the
  /// new frame/layer (or retargets after a removal), so a Draft would otherwise survive onto a
  /// surface the artist never drew it on. Reorders keep the same content active and are not
  /// context changes. The layer-strip RESYNC deliberately uses _send, not _act, so it is not a
  /// context change either. Adding a *blank* layer is the one carve-out (ADR 0016) — see
  /// [_isBlankLayerVerb].
  static bool _isContextChangeVerb(String dsl) {
    for (final part in dsl.split(';')) {
      final name = part.trim().split('(').first.trim();
      if (const {
        'SetActiveFrame',
        'SetActiveLayer',
        'AddFrame',
        'AddFrameAt',
        'DuplicateFrame',
        'RemoveFrame',
        'DuplicateLayer',
        'RemoveLayer',
        'MergeDown',
      }.contains(name)) {
        return true;
      }
    }
    return false;
  }

  /// ADR 0016: inserting a blank layer into the current frame is *preparation for a commit*, not
  /// a context change. The composited preview is unchanged and the new (empty, active) layer is
  /// exactly where "draw this on its own layer" wants the Draft to land — so the retargeting
  /// families (figure, paste, Select marquee) survive. Only the two blank-layer verbs qualify:
  /// DuplicateLayer activates a layer that already has content under the Draft, and stays a
  /// context change.
  static bool _isBlankLayerVerb(String dsl) {
    for (final part in dsl.split(';')) {
      final name = part.trim().split('(').first.trim();
      if (name == 'AddLayer' || name == 'AddLayerAt') return true;
    }
    return false;
  }

  /// ADR 0011: cancel whatever Draft is open — silently and irrecoverably. Tool switches have
  /// always done this in _selectTool; this is the same contract extended to frame, layer, and
  /// document changes. At most one Draft can exist at a time, so one call is enough.
  void _cancelDraftsForContextChange() {
    if (_hasAnyDraft) _cancelActiveDraft();
  }

  /// ADR 0016: on a blank-layer insert, cancel only the Drafts bound to the *old* layer's content.
  /// Transform Drafts (Move/Rotate/Scale) hold lifted pixels pinned by layer id, so surviving would
  /// let the commit pill land on a layer that is no longer active — the hidden off-surface commit
  /// ADR 0011 exists to forbid. Adjust Drafts (HSV/Brightness-Contrast/Levels) preview the active
  /// layer, which is now blank — a stuck slider adjusting nothing. Everything else stays open.
  void _cancelLayerBoundDraftsForBlankLayer() {
    final layerBound = (_tool == 'Move' && _hasMoveDraft) ||
        (_tool == 'Rotate' && _hasRotateDraft) ||
        (_tool == 'Resize' && _hasResizeDraft) ||
        (_tool == 'HsvShift' && _hasHsvDraft) ||
        (_tool == 'BrightnessContrast' && _hasBcDraft) ||
        (_tool == 'Levels' && _hasLevelsDraft);
    if (layerBound) _cancelActiveDraft();
  }

  /// ADR 0010: end an in-flight Gesture as if the artist lifted. Value gestures (control drags)
  /// commit where they are; view gestures (pinch, trackpad) simply end; a stroke gets its
  /// PointerUp so the engine records one undo step for it.
  void _finishInteraction() {
    if (_endingInteraction || !_interactionActive) return;
    _endingInteraction = true;
    try {
      if (_drawPointer != null) _endDraw();
      if (_pinching) {
        _pinching = false;
        _touchPos.clear();
      }
      if (_penDown) {
        _send('CursorPenUp()');
        _penDown = false;
      }
      _trackpadGesture = false;
      if (_controlDragTool != null) {
        _controlDragTool = null;
        _controlDragRevert = null;
        _controlDragDead = true; // ignore the rest of the still-held drag
      }
    } finally {
      _endingInteraction = false;
    }
  }

  /// ADR 0010: abort an in-flight Gesture — Esc and Undo/Redo mean "not this", so they discard
  /// the stroke, revert a control drag to its pre-drag value, and consume the keystroke rather
  /// than reaching the engine's history. View gestures have nothing to revert and just end.
  void _cancelInteraction() {
    if (_endingInteraction || !_interactionActive) return;
    _endingInteraction = true;
    try {
      if (_drawPointer != null) {
        _send('CancelStroke()');
        _drawPointer = null;
      }
      if (_pinching) {
        _pinching = false;
        _touchPos.clear();
      }
      if (_penDown) {
        _send('CursorPenUp()');
        _penDown = false;
      }
      _trackpadGesture = false;
      if (_controlDragTool != null) {
        _controlDragRevert?.call();
        _controlDragTool = null;
        _controlDragRevert = null;
        _controlDragDead = true;
      }
      _refreshState();
      _redraw();
    } finally {
      _endingInteraction = false;
    }
  }

  // ---- control-drag latch (ADR 0010) -----------------------------------------------------

  void _beginControlDrag(double pre, ValueChanged<double> onChanged) {
    if (_controlDragTool != null || _controlDragDead) return;
    _controlDragTool = _tool;
    _controlDragRevert = () => onChanged(pre);
  }

  void _endControlDrag() {
    _controlDragTool = null;
    _controlDragRevert = null;
    _controlDragDead = false;
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
    // Likewise, a pending paste draft is canceled & erased when leaving the Copy & Paste tool.
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
    // A pending resize (Scale) draft is likewise discarded when leaving the Resize tool.
    if (_hasResizeDraft) {
      _send('ScaleDraftCancel()');
      _hasResizeDraft = false;
      _resizeDragging = false;
      _redraw();
    }
    // A pending HSV / Brightness-Contrast / Levels adjustment (a display-only preview, like the
    // drafts above) is likewise canceled when leaving its tool, so returning starts clean instead
    // of resuming a stale draft — same as the commit-menu's Cancel.
    if (_tool == 'HsvShift' && t != 'HsvShift' && _hasHsvDraft) _resetHsvDraft();
    if (_tool == 'BrightnessContrast' && t != 'BrightnessContrast' && _hasBcDraft) _resetBcDraft();
    if (_tool == 'Levels' && t != 'Levels' && _hasLevelsDraft) _resetLevelsDraft();
    // The Ruler keeps its measurement across tool switches (its full overlay hides while another
    // tool is active — unless pinned, when a simplified echo stays — and reappears on return);
    // clear it with the Ruler's row-1 "Clear" button.
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
    } else if (t == 'Airbrush') {
      // 'Airbrush' is a shell grouping over the engine's Airbrush/AirbrushSoft/AirbrushMist.
      _send('SelectTool($_airbrushMode)');
    } else if (t == 'SelectShape') {
      // 'SelectShape' is a shell grouping over the engine's SelectRect/SelectEllipse/SelectFree.
      _send('SelectTool(${selectShapeEngineTool(_selShapeKind)})');
    } else if (t != 'Ruler') {
      _send('SelectTool($t)'); // Ruler is a pure overlay; no engine draw tool
    } else if (leavingSelectLayer) {
      _send('SelectTool(Move)'); // Ruler sends no draw tool — clear the Select Layer overlay
    }
    // Entering a tool that remembers precision-on re-centers the reticle.
    if (_precisionOn.contains(t)) {
      _setCursor(engine.width ~/ 2, engine.height ~/ 2);
      _redraw();
    }
    _pushToolSettings();
    if (t == 'Gradient') {
      _send('SetGradientType(${_radial ? 'Radial' : 'Linear'})');
      _send('SetGradientSmoothstep($_gradSmooth)');
      _send(_gradStopsDsl());
    }
    // Show Select Layer's overlay immediately on entry; clear it (redraw) when leaving it.
    if (t == 'SelectLayer' || leavingSelectLayer) _redraw();
  }

  // Re-push every shell-side tool setting to the engine. One block shared by _selectTool and
  // the Journal's replay baseline (_emitReplayBaseline) so the two can never drift. [replay]
  void _pushToolSettings() {
    _send('SetBrushSize($_brushSize); SetBrushShape(${_round ? 'Round' : 'Square'})');
    _send('SetThreshold($_threshold); SetContiguous($_contiguous); SetAlphaCutoff($_alphaCutoff)');
    _send('SetIntensity($_intensity); SetShapeFill($_shapeFill); SetLineWidth($_lineWidth)');
    _send('SetFillAllLayers($_fillAllLayers)');
    _send('SetSelectionMode($_selMode); SetProtectPixels($_protectPixels); SetWrap($_wrap)');
    _send('SetPixelPerfect($_perfect); SetOverscanView(${_overscan ? 1 : 0})');
    // On its own line: under the replay line-skip an old app drops exactly the unknown verb's
    // line, so SetAA must not carry siblings it would take down with it.
    _send('SetAA($_aa)');
    _send('SetEyedropSource(${_eyedropLayer ? 'Layer' : 'Frame'})');
    _send('SetSelectColorSource(${_selColorLayer ? 'Layer' : 'Frame'})');
    _send('SetCleanEdge($_cleanEdge); SetCleanEdgeWidth(${(_cleanEdgeWidth * 1000).round()})');
    _send('SetScaleCleanEdge($_resizeCleanEdge); SetScaleCleanEdgeWidth(${(_resizeCleanEdgeWidth * 1000).round()})');
  }

  // The engine ToolKind name for the current shell tool, or null for UI-only tools (the transform
  // groups, Play, Ruler) that have no engine draw tool. Resolves the shell groupings ('Shape',
  // 'SelectShape') to the concrete engine tool their mode toggle points at.
  String? get _engineToolName {
    if (_transformTools.contains(_tool) || _tool == 'PlayPause' || _tool == 'Ruler') return null;
    if (_tool == 'Shape') return _shapeKind;
    if (_tool == 'Airbrush') return _airbrushMode;
    if (_tool == 'SelectShape') return selectShapeEngineTool(_selShapeKind);
    return _tool;
  }

  // Re-point the engine at the current tool (used after NewDocument/load, when the session's tool
  // may have reset). UI-only tools send nothing — the engine has no ToolKind for them.
  void _resendEngineTool() {
    final t = _engineToolName;
    if (t != null) _send('SelectTool($t)');
  }

  // ---- HSV / Brightness-Contrast / Levels drafts (a non-identity pending adjustment) -----------
  // Commit bakes the adjustment into the document (one undo step, the row-1 Apply of old). The
  // engine consumes the pending settings inside Apply* — its display can never show the adjustment
  // twice, even to a fetch landing before our reset — so on commit the reset's identity re-send is
  // a harmless no-op that just zeroes the slider state. Reset alone is the cancel: it zeroes the
  // settings so the display-only preview reverts. Both are driven by the floating commit-menu,
  // and Reset also fires on the implicit cancel when switching tools in row-3.

  void _commitHsvDraft() {
    _send('SetHsvShift($_hsvH, $_hsvS, $_hsvV)');
    _act('ApplyHsvShift()');
    _resetHsvDraft();
  }

  void _resetHsvDraft() {
    setState(() {
      _hsvH = 0;
      _hsvS = 0;
      _hsvV = 0;
    });
    _send('SetHsvShift(0, 0, 0)');
    _redraw();
  }

  void _commitBcDraft() {
    _send('SetBrightnessContrast(${_bcBright.round()}, ${1.0 + _bcContrast / 100})');
    _act('ApplyBrightnessContrast()');
    _resetBcDraft();
  }

  void _resetBcDraft() {
    setState(() {
      _bcBright = 0;
      _bcContrast = 0;
    });
    _send('SetBrightnessContrast(0, 1)');
    _redraw();
  }

  void _commitLevelsDraft() {
    _send('SetLevels($_lvLow, $_lvGammaTh, $_lvHigh)');
    _act('ApplyLevels()');
    _resetLevelsDraft();
  }

  void _resetLevelsDraft() {
    // NB the Levels identity is (0, 1000, 255), not zeros.
    setState(() {
      _lvLow = 0;
      _lvGammaTh = 1000;
      _lvHigh = 255;
    });
    _send('SetLevels(0, 1000, 255)');
    _redraw();
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
  }

  // Discard the pending move draft, restoring the pixels (and marquee) to where they were.
  void _cancelMoveDraft() {
    _send('MoveDraftCancel()');
    _moveDragLast = null;
    _moveDraftStarted = false;
    _refreshState();
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
    if (on) _setCursor(engine.width ~/ 2, engine.height ~/ 2); // park the reticle in the center
    _redraw();
  }

  void _setPrimary(Color c) {
    // Remember the outgoing primary for the X Command's swap (only on a real change, so
    // re-picking the current color never collapses previous onto current).
    if (c != _primary) _previousPrimary = _primary;
    setState(() => _primary = c);
    _send('SetPrimaryColor(${_hex(c)})');
    if (_tool == 'Gradient') {
      // The gradient's first color IS the primary, so re-push the stops (refreshes a draft too).
      _sendGradientStops();
    } else if (_hasShapeDraft) {
      // A pending figure draft (Line/Rect/Ellipse) is drawn in the primary color — refresh its
      // preview now instead of waiting for the next drag.
      _redraw();
    }
  }

  // The gradient's colors: the primary first, then the independent extras, evenly spaced 0..1.
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
    if (_penDown) {
      // While Hold is on a nudge paints, and each nudge is its own undo step (like a drag).
      _send('CursorStrokeBegin()');
      _moveCursor(dx, dy);
      _send('CursorStrokeEnd()');
      _refreshState();
    } else {
      _moveCursor(dx, dy);
    }
    _redraw();
  }

  // ---- canvas view transform (fit + two-finger pan/zoom) ----

  // Screen pixels per canvas pixel when fit-to-screen (zoom == 1). Uses the cached canvas
  // size — _toCanvas runs per pointer event and used to make 3 FFI crossings each. [battery F20]
  double _fitScale(Size box) {
    final sx = box.width / _canvasW, sy = box.height / _canvasH;
    return sx < sy ? sx : sy;
  }

  // Top-left of the canvas, in screen pixels, if it were centered at scale [s].
  Offset _centeredOffset(Size box, double s) =>
      Offset((box.width - _canvasW * s) / 2, (box.height - _canvasH * s) / 2);

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
    final gx = (_dispW - _canvasW) / 2.0;
    final gy = (_dispH - _canvasH) / 2.0;
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

  // Focal-point zoom: the canvas point under [focalScreen] stays put while the zoom moves to
  // [targetZoom] (clamped). The keyboard zoom steps aim at the box center; the mouse wheel and
  // trackpad pinch aim at the cursor. Pan is left unclamped, matching the pinch.
  void _zoomAt(Size box, Offset focalScreen, double targetZoom) {
    final z = targetZoom.clamp(_kMinZoom, _kMaxZoom).toDouble();
    final (s0, off0) = _view(box);
    final c = (focalScreen - off0) / s0; // focal point in canvas space
    final s1 = _fitScale(box) * z;
    setState(() {
      _zoom = z;
      _pan = (focalScreen - c * s1) - _centeredOffset(box, s1);
    });
  }

  // One vsync tick of the playback preview: send the MEASURED elapsed ms to the engine's
  // virtual clock (real time never enters the engine — the shell picks the deltas), then
  // decode only when there is something new to show. Frames shorter than a vsync period
  // are skipped, never stretched: the preview is a refresh-rate sampling of the animation's
  // true timeline, so pacing stays wall-clock accurate up to the engine's 60 fps content
  // ceiling. While an opaque route covers the editor the ticker is muted (no sends, no
  // decodes) but its clock keeps elapsing — PlaybackClock clamps the tick after popping
  // back to maxTickUs, so playback resumes near where it left off instead of teleporting
  // (app backgrounding doesn't rely on the clamp: it auto-pauses, see
  // didChangeAppLifecycleState).
  void _onPlayTick(Duration elapsed) {
    if (!_engineReady || !_playing) return;
    // TEMPORARY: edits are still legal during playback, so any _send since our previous
    // tick (stamp mismatch) must refresh the composite even when the play frame index
    // didn't move. Snapshot BEFORE our own AdvanceClock send below (which also bumps
    // _sendSeq). Remove once edit-during-playback is made illegal. (Ticker mode only —
    // in timer mode an edit's own _redraw refreshes the composite through the R1
    // presenter, which composites the play frame while playing.)
    final editsSeen = _sendSeq != _playSeenSendSeq;
    // The shared stopwatch — not the Ticker's own elapsed — is the time source, so
    // ticker↔timer mode switches keep one continuous timeline. [battery R3]
    final ms = _playClock.advance(_playStopwatch.elapsedMicroseconds);
    if (ms > 0) _send('AdvanceClock($ms)', activity: false);
    _playSeenSendSeq = _sendSeq;
    final (frame, nextUs) = engine.playStatus; // one O(log n) scalar [battery F15]
    if (frame != _playShownFrame || editsSeen) _showPlayFrame(frame);
    _maybeParkOnTimer(nextUs);
  }

  // [battery R3] The hybrid clock's slow half: when the next visible frame change is
  // further away than ~2 display frames, vsync frame production buys nothing — stop the
  // ticker and arm a one-shot timer to the boundary (the always-on ticker measured
  // ~750 mW for a 2 fps animation on the 120 Hz Pixel, docs/battery/BASELINE.md). Fast
  // content stays on the ticker with its device-verified wall-clock pacing untouched.
  // The engine's reported wait is a lower bound, so a frame can never show late; at
  // worst the timer fires just before the boundary and re-arms once.
  static const int _kPlayTimerModeUs = 34000; // ≈2×60 Hz frames; >~29 fps content stays vsync

  /// The ONE place a newly displayed Playhead frame is published. Playback advances through two
  /// paths — the vsync ticker for fast content and a parked timer for anything slower than
  /// ~29 fps [battery R3] — and ordinary pixel-art timing (100 ms/frame) spends nearly all its
  /// time on the TIMER path. Wiring row-1's live frame counter into only one of them left the
  /// counter frozen for every realistic animation, so both now route through here.
  void _showPlayFrame(int frame) {
    _playShownFrame = frame;
    _playheadVN.value = frame; // row-1's live frame counter (no full-tree rebuild)
    // Route through the presenter (single _imageVN publisher; no full-tree setState, so the
    // row-3 tiles stay stable and tappable during playback). [battery R1]
    _redraw(full: false, refetchSelection: false);
  }

  void _maybeParkOnTimer(int nextUs) {
    if (nextUs <= _kPlayTimerModeUs) return;
    _playTicker?.stop();
    _playTimer?.cancel();
    _playTimer = Timer(Duration(microseconds: nextUs), _onPlayTimerFire);
  }

  void _onPlayTimerFire() {
    if (!_engineReady || !_playing) return;
    // A planned wait to a frame boundary, not a stall — unclamped, or slow content
    // would be paced at maxTickUs and drift off the wall clock. [battery R3]
    final ms = _playClock.advanceUnclamped(_playStopwatch.elapsedMicroseconds);
    if (ms > 0) _send('AdvanceClock($ms)', activity: false);
    _playSeenSendSeq = _sendSeq;
    final (frame, nextUs) = engine.playStatus;
    if (frame != _playShownFrame) _showPlayFrame(frame);
    if (nextUs > _kPlayTimerModeUs) {
      _playTimer = Timer(Duration(microseconds: nextUs), _onPlayTimerFire);
    } else if (!(_playTicker?.isActive ?? true)) {
      _playTicker?.start(); // content sped up — back to vsync pacing
    }
  }

  void _play() {
    if (engine.frameCount <= 1) return;
    setState(() => _playing = true);
    _send('Play()', activity: false);
    _playClock.reset();
    _playStopwatch
      ..reset()
      ..start(); // the run's single time source, across ticker AND timer modes [battery R3]
    _playShownFrame = -1; // force the first tick to decode the starting frame's composite
    _playheadVN.value = engine.playFrame; // starts at the Active target (engine contract)
    _playSeenSendSeq = _sendSeq; // the Play() send itself is not an "edit"
    _playTicker ??= createTicker(_onPlayTick);
    _playTicker!
      ..stop() // defensive restart guard (start() asserts if active), mirrors the old cancel()
      ..start();
  }

  void _pause() {
    _playTicker?.stop();
    _playTimer?.cancel(); // the hybrid clock's timer half [battery R3]
    _playTimer = null;
    _playStopwatch.stop();
    setState(() => _playing = false);
    _send('Pause()', activity: false);
    _redraw();
  }

  // Step to the previous (delta = -1) or next (delta = +1) animation frame, wrapping around the
  // ends. Pressing either auto-pauses playback first (the Play tool's contract).
  void _stepFrame(int delta) {
    if (_playing) _pause();
    final n = engine.frameCount;
    if (n <= 1) return;
    final next = ((engine.activeFrame + delta) % n + n) % n;
    _clearLayerGroup(); // the move-group indexed the previous frame's layer stack
    _act('SetActiveFrame($next)');
    _ensureActiveFrameVisible();
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
    final target = (entered - 1).clamp(0, n - 1);
    if (target != engine.activeFrame) _clearLayerGroup();
    _act('SetActiveFrame($target)');
    _ensureActiveFrameVisible();
  }

}
