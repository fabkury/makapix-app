/// Playback tick accounting for the vsync-driven preview loop.
///
/// Converts a [Ticker]'s measured elapsed time (µs) into the whole-millisecond
/// `AdvanceClock` amounts the engine's virtual clock accepts, carrying the sub-ms
/// remainder so no time is ever lost to rounding: Σ(returned ms) == elapsed ~/ 1000
/// at every tick. (The old Timer.periodic(33) advanced a FIXED 33 ms per callback,
/// so late or skipped callbacks silently slowed playback.)
///
/// Pure and engine-free — unit-tested standalone, like levels_math.dart.
class PlaybackClock {
  /// Stall clamp: a single tick never advances the animation by more than this.
  /// A muted ticker (opaque route covering the editor) or a long UI stall keeps
  /// elapsing time, and an unclamped first tick afterwards would teleport the
  /// animation to its wall-clock position; capping it makes playback resume
  /// roughly where it left off, with at most this much forward nudge. (App
  /// backgrounding doesn't even get that far — it auto-pauses playback.)
  static const int maxTickUs = 500000; // 500 ms

  int _lastElapsedUs = 0;
  int _carryUs = 0;

  /// Forget accumulated state. Call when the ticker (re)starts: a stopped Ticker's
  /// elapsed restarts near zero, so stale [_lastElapsedUs] would yield a negative dt.
  void reset() {
    _lastElapsedUs = 0;
    _carryUs = 0;
  }

  /// [elapsedUs] is the ticker's elapsed time since start in µs (monotonic within
  /// one start). Returns the whole milliseconds to advance the engine clock by now
  /// (>= 0; 0 means skip the send). The remainder stays carried, in [0, 1000);
  /// time beyond [maxTickUs] in one tick is deliberately discarded, so the
  /// no-drift invariant (Σ returned ms == elapsed ~/ 1000) holds between stalls.
  int advance(int elapsedUs) {
    var dt = elapsedUs - _lastElapsedUs;
    _lastElapsedUs = elapsedUs;
    if (dt > maxTickUs) dt = maxTickUs;
    _carryUs += dt;
    final ms = _carryUs ~/ 1000;
    _carryUs -= ms * 1000;
    return ms;
  }

  /// Like [advance], WITHOUT the stall clamp: for the timer-driven playback mode
  /// (battery R3), where a long delta is a PLANNED wait to the next frame boundary,
  /// not a stall — clamping it would slow slow-fps content. Shares the µs carry with
  /// [advance], so hybrid ticker↔timer switches lose no time. (Unplanned long gaps
  /// don't reach here: backgrounding auto-pauses, and menus/routes pause playback.)
  int advanceUnclamped(int elapsedUs) {
    final dt = elapsedUs - _lastElapsedUs;
    _lastElapsedUs = elapsedUs;
    _carryUs += dt;
    final ms = _carryUs ~/ 1000;
    _carryUs -= ms * 1000;
    return ms;
  }
}
