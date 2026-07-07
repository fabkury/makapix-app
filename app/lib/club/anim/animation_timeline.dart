/// Pure clock→frame mapping for synchronized animation playback (no Flutter imports).
///
/// The displayed frame of an animated post is a pure function of the wall clock:
///
///   loopPosition = (nowMs + phaseOffsetMs) mod totalDurationMs
///   frame        = the frame whose cumulative duration spans loopPosition
///
/// with a fixed absolute epoch (Unix epoch). Synchrony is therefore not a state that can
/// be lost: any tile, mounted at any moment, computes the same answer — surviving scroll
/// remounts, cache eviction, grid ⇄ detail navigation, backgrounding, and app restarts.
library;

/// Per-frame delays at or below this are treated as "unspecified fast" and clamped up,
/// matching the browser convention (and how the same file plays on the website).
const int kDelayClampThresholdMs = 10;

/// What a clamped delay becomes.
const int kClampedDelayMs = 100;

/// Floor on the total loop duration so the modulo is always well-defined.
const int kMinLoopDurationMs = 30;

/// The frame timeline of one decoded animation: clamped per-frame delays, their prefix
/// sums, and the total loop duration. `phaseOffsetMs` is a per-artwork offset kept as a
/// parameter (not hard-coded to 0) so a future per-post phase-offset field stays cheap.
class AnimationTimeline {
  AnimationTimeline(List<int> rawDelaysMs, {this.phaseOffsetMs = 0})
      : assert(rawDelaysMs.isNotEmpty),
        delaysMs = List.unmodifiable(rawDelaysMs.map(clampDelayMs)) {
    var sum = 0;
    _cumulativeMs = List<int>.generate(delaysMs.length, (i) => sum += delaysMs[i]);
    totalDurationMs = sum < kMinLoopDurationMs ? kMinLoopDurationMs : sum;
  }

  /// Additive offset applied to the wall clock before the modulo.
  final int phaseOffsetMs;

  /// Clamped per-frame delays, one per frame.
  final List<int> delaysMs;

  /// Prefix sums of [delaysMs]; frame `i` spans `[_cumulativeMs[i-1], _cumulativeMs[i])`.
  late final List<int> _cumulativeMs;

  /// Loop period: `max(sum(delaysMs), kMinLoopDurationMs)`.
  late final int totalDurationMs;

  int get frameCount => delaysMs.length;

  /// The frame index shown at wall-clock time `nowMs` (ms since the Unix epoch).
  /// Positions inside the min-loop padding zone (when the delays sum to less than
  /// [kMinLoopDurationMs]) map to the last frame.
  int frameIndexAt(int nowMs) {
    // Double-mod so a negative offset (or a pre-epoch clock) can't go negative.
    final pos = ((nowMs + phaseOffsetMs) % totalDurationMs + totalDurationMs) % totalDurationMs;
    // First index whose cumulative end exceeds pos (upper bound over prefix sums).
    var lo = 0, hi = _cumulativeMs.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_cumulativeMs[mid] > pos) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo;
  }

  /// The clamp rule, shared with the publish flow so it lives in exactly one place.
  static int clampDelayMs(int raw) => raw <= kDelayClampThresholdMs ? kClampedDelayMs : raw;

  /// Total loop duration for a raw delay list, under the same clamp + floor rules.
  static int computeTotalDurationMs(Iterable<int> rawDelaysMs) {
    var sum = 0;
    for (final d in rawDelaysMs) {
      sum += clampDelayMs(d);
    }
    return sum < kMinLoopDurationMs ? kMinLoopDurationMs : sum;
  }
}
