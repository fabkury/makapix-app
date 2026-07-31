part of 'animator_page.dart';
// ignore_for_file: invalid_use_of_protected_member
// (Part of _AnimatorPageState — the editor part files' rationale: extensions on a State
// subclass trip a false positive calling the @protected setState.)

// The DSL/engine plumbing hub: every mutation funnels through [_send] (frame-cache epoch +
// autosave activity ride along), session-only state through [_sendSession], and the composited
// frame reaches the Stage via [_showFrame] (cache-first, scratch-buffer contract respected).
extension _AnimatorEngine on _AnimatorPageState {
  /// Send a DOCUMENT-mutating DSL script: invalidates the frame cache via the engine's
  /// cache_epoch, marks autosave activity, and surfaces engine errors as toasts (they should
  /// be impossible from UI-generated scripts — seeing one is a bug report, not user error).
  void _send(String dsl) {
    final err = engine.run(dsl);
    if (err != null) {
      debugPrint('animator dsl error: $err [$dsl]');
    }
    _autosave?.markActivity();
    _frameCache.syncEpoch(engine.cacheEpoch);
  }

  /// Send SESSION-only verbs (SetPlayhead / SelectActor / SetLoop / SetAutoKey): persisted in
  /// the .mkps session state, but no frame is invalidated.
  void _sendSession(String dsl) {
    final err = engine.run(dsl);
    if (err != null) debugPrint('animator dsl error: $err [$dsl]');
    _autosave?.markActivity();
  }

  /// Mutate + refresh + redraw + rebuild — the discrete-action path (sheet buttons, chips).
  void _act(String dsl) {
    _send(dsl);
    _refreshState();
    _redrawCurrent();
    if (mounted) setState(() {});
  }

  /// Re-parse state_json. Runs on gesture end / discrete acts — never per pointer move.
  void _refreshState() {
    if (!_engineReady) return;
    _state = SceneState.parse(engine.stateJson());
    // The pill's Move|Rotate mode auto-resets whenever the selection changes (06 §4.3).
    if (_state.selectedActor != _modeSelId) {
      _modeSelId = _state.selectedActor;
      _stageMode = _StageMode.move;
    }
    _syncMemBudgetUi();
  }

  /// Composite + decode + present one scene frame. Cache-first; a miss composites directly
  /// (the editor `_redraw` shape: premultiply the scratch view, then decode synchronously).
  Future<void> _showFrame(int frame) async {
    if (!_engineReady) return;
    _shownFrame = frame;
    final cached = _frameCache.get(frame);
    if (cached != null) {
      final old = _frameVN.value;
      _frameVN.value = cached;
      old?.dispose();
      return;
    }
    final w = engine.width, h = engine.height;
    final rgba = engine.compositeFrame(frame);
    if (rgba.isEmpty) return;
    premultiplyRgbaInPlace(rgba);
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, completer.complete);
    final img = await completer.future;
    if (!mounted) {
      img.dispose();
      return;
    }
    _frameCache.put(frame, img);
    // Present only if this is still the frame we want (scrub may have moved on).
    if (_shownFrame == frame) {
      final old = _frameVN.value;
      _frameVN.value = img;
      old?.dispose();
    } else {
      img.dispose();
    }
  }

  /// Redraw whatever frame the Stage currently shows (after a mutation).
  void _redrawCurrent() => _showFrame(_playing ? _playbackFrame() : _state.playhead);

  // ---- view transform (fit-relative zoom + pan; the editor's math) ------------------------

  double _fitScale(Size box) {
    if (!_engineReady) return 1;
    final w = engine.width, h = engine.height;
    if (w == 0 || h == 0 || box.isEmpty) return 1;
    return math.min(box.width / w, box.height / h);
  }

  /// (scale, offset) drawing the canvas into [box] under the current zoom/pan.
  (double, Offset) _view(Size box) {
    final s = _fitScale(box) * _zoom;
    final w = _engineReady ? engine.width : 1;
    final h = _engineReady ? engine.height : 1;
    final off = Offset(
      (box.width - w * s) / 2 + _pan.dx,
      (box.height - h * s) / 2 + _pan.dy,
    );
    return (s, off);
  }

  Offset _toCanvas(Offset screen, Size box) {
    final (s, off) = _view(box);
    return Offset((screen.dx - off.dx) / s, (screen.dy - off.dy) / s);
  }

  void _fitView() => setState(() {
        _zoom = 1;
        _pan = Offset.zero;
      });

  void _startViewPinch() {
    final ps = _touchPos.values.toList();
    _pinchStartDist = (ps[0] - ps[1]).distance.clamp(1, double.infinity);
    _pinchStartZoom = _zoom;
    _pinchStartMid = (ps[0] + ps[1]) / 2;
    _pinchStartPan = _pan;
  }

  void _updateViewPinch(Size box) {
    final ps = _touchPos.values.toList();
    if (ps.length < 2) return;
    final dist = (ps[0] - ps[1]).distance.clamp(1.0, double.infinity);
    final mid = (ps[0] + ps[1]) / 2;
    final newZoom = (_pinchStartZoom * dist / _pinchStartDist).clamp(_kMinZoom, _kMaxZoom);
    // Focal-point zoom: the canvas point under the start midpoint stays under the live mid.
    final fit = _fitScale(box);
    final s0 = fit * _pinchStartZoom;
    final s1 = fit * newZoom;
    final w = engine.width, h = engine.height;
    final off0 = Offset(
      (box.width - w * s0) / 2 + _pinchStartPan.dx,
      (box.height - h * s0) / 2 + _pinchStartPan.dy,
    );
    final canvasPt = Offset(
      (_pinchStartMid.dx - off0.dx) / s0,
      (_pinchStartMid.dy - off0.dy) / s0,
    );
    final newPan = Offset(
      mid.dx - canvasPt.dx * s1 - (box.width - w * s1) / 2,
      mid.dy - canvasPt.dy * s1 - (box.height - h * s1) / 2,
    );
    setState(() {
      _zoom = newZoom;
      _pan = newPan;
    });
  }

  // ---- memory-budget narration (the editor's banner/snackbar pattern) ----------------------

  void _syncMemBudgetUi() {
    if (!mounted) return;
    final refusals = _state.memRefusals;
    if (_memRefusalsSeen == -1) {
      _memRefusalsSeen = refusals; // a loaded session's old count must not toast
    } else if (refusals > _memRefusalsSeen) {
      _memRefusalsSeen = refusals;
      _toast(_state.memLastRefusal ?? 'That change exceeds the scene memory budget.');
    }
    final over = _state.memSoftExceeded;
    if (over && !_memBannerShown) {
      _memBannerShown = true;
      ScaffoldMessenger.of(context).showMaterialBanner(MaterialBanner(
        content: const Text(
            'This scene is close to the device memory limit — consider fewer or smaller props.'),
        leading: const Icon(Icons.data_saver_off, color: Colors.amber),
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
            },
            child: const Text('OK'),
          ),
        ],
      ));
    } else if (!over && _memBannerShown) {
      _memBannerShown = false;
      ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
    }
  }
}
