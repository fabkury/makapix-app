part of 'animator_page.dart';
// ignore_for_file: invalid_use_of_protected_member
// (Part of _AnimatorPageState — the editor part files' rationale: extensions on a State
// subclass trip a false positive calling the @protected setState.)

// Playback — the Club feed's clock model, not the editor's FFI-per-tick timer: a vsync
// Ticker derives the loop frame from elapsed wall time (exact for every curated rate), the
// frame cache turns a tick into one array index, and a cooperative pre-warm fills the loop
// region behind playback. No FFI in the hot loop once warm.
extension _AnimatorPlayback on _AnimatorPageState {
  int _playbackFrame() {
    final a = _state.loopA;
    final b = math.max(_state.loopB, a);
    final len = b - a + 1;
    final elapsedUs =
        ((_ticker?.isActive ?? false) ? (_lastElapsed - _playStartElapsed) : Duration.zero)
            .inMicroseconds;
    final advanced = elapsedUs * _state.millifps ~/ 1000000000;
    final start = (_playStartFrame.clamp(a, b)) - a;
    return a + (start + advanced) % len;
  }

  void _togglePlay() => _playing ? _pause() : _play();

  void _play() {
    if (_playing || _state.frameCount <= 1) return;
    setState(() => _playing = true);
    _playStartFrame = _state.playhead;
    _ticker ??= createTicker(_onTick);
    _playStartElapsed = Duration.zero;
    _lastElapsed = Duration.zero;
    _ticker!.start();
    _warmLoopRegion();
  }

  void _pause() {
    if (!_playing) return;
    final parked = _playbackFrame();
    _ticker?.stop();
    setState(() => _playing = false);
    _sendSession('SetPlayhead($parked)');
    _state = SceneState.parse(engine.stateJson());
    _hintEnd();
    _showFrame(parked);
    _overlayVN.value++;
  }

  void _onTick(Duration elapsed) {
    _lastElapsed = elapsed;
    final f = _playbackFrame();
    if (f == _shownFrame) return;
    // Cache hit shows instantly; a miss composites (skipping a tick at 50 fps is invisible —
    // the in-flight guard is _showFrame's own stale-frame check).
    _showFrame(f);
    _hintLive('frame ${f + 1} / ${_state.frameCount}');
    _overlayVN.value++;
  }

  /// Cooperatively pre-decode the loop region behind playback; aborted by an epoch change,
  /// pause, or a newer warm request.
  Future<void> _warmLoopRegion() async {
    if (_warmInFlight) return;
    _warmInFlight = true;
    final epoch = engine.cacheEpoch;
    _warmEpoch = epoch;
    try {
      final a = _state.loopA;
      final b = math.max(_state.loopB, a);
      for (var f = a; f <= b; f++) {
        if (!mounted || !_playing || engine.cacheEpoch != epoch || _warmEpoch != epoch) {
          return;
        }
        if (!_frameCache.contains(f)) {
          final w = engine.width, h = engine.height;
          final rgba = engine.compositeFrame(f);
          if (rgba.isEmpty) continue;
          premultiplyRgbaInPlace(rgba);
          final completer = Completer<ui.Image>();
          ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, completer.complete);
          final img = await completer.future;
          _frameCache.put(f, img);
          img.dispose();
        }
        // Yield so the UI thread breathes between frames.
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      _warmInFlight = false;
    }
  }
}
