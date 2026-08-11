/// Timelapse planning — pure math, no IO, no engine (CONTEXT.md "Timelapse").
///
/// A Timelapse is: a PROGRESS portion (uniform action sampling of the Journal at 30 fps
/// filling the chosen preset duration) followed by an APPENDED finale — the finished piece.
/// Animated drawings play whole cycles from frame 1 at their authored per-frame durations
/// (loop until ≥3 s AND ≥2 full plays, capped at 5 loops / ~8 s, a single full play never
/// truncated); static drawings hold 4.5 s. Cycles longer than 60 s are the caller's
/// per-export dialog (full play vs whole-frame excerpt — [excerptFrameCount]).
library;

/// One output frame of the timelapse, in order. Either a progress sample (replay to
/// [position], composite the artist's active frame) or a finale frame ([frameIndex] of the
/// finished document). [durationUs] is its display duration; PTS = running sum.
class TimelapseEntry {
  const TimelapseEntry.progress(this.position, this.durationUs) : frameIndex = null;
  const TimelapseEntry.finale(this.frameIndex, this.durationUs) : position = null;

  final int? position; // journal action position (progress entries)
  final int? frameIndex; // finished-document frame (finale entries)
  final int durationUs;

  bool get isFinale => frameIndex != null;
}

/// The progress portion's per-frame duration: 30 fps.
const int kProgressFrameUs = 33333;

/// The static drawing's finale hold.
const int kStaticHoldUs = 4_500_000;

/// Output shape presets (ADR 0004: even dimensions, safe on every OS encoder).
enum TimelapseShape {
  square(1080, 1080, 'Square 1080×1080'),
  portrait(1080, 1920, 'Portrait 1080×1920');

  const TimelapseShape(this.outW, this.outH, this.label);
  final int outW;
  final int outH;
  final String label;
}

/// Uniform sampling over a POOL of journal positions — the visible-change index, so the
/// video never freezes through draft fiddling or settings churn. [samples] entries,
/// monotonic non-decreasing, last == pool.last. Duplicates (a short pool) are legal —
/// repeated frames delta-encode to almost nothing.
List<int> samplePositions(List<int> pool, int samples) {
  if (samples <= 0 || pool.isEmpty) return const [];
  return [
    for (var k = 0; k < samples; k++)
      pool[(((k + 1) * pool.length / samples).ceil() - 1).clamp(0, pool.length - 1)],
  ];
}

/// The authored full-cycle length of the finished animation, µs.
int cycleUs(List<int> frameDurationsUs) => frameDurationsUs.fold(0, (a, b) => a + b);

/// The finale's loop count for a full-cycle finale: loop until ≥3 s AND ≥2 full plays,
/// capped at 5 loops and ~8 s — but a single full play is never truncated (C > 8 s ⇒ 1).
int finaleLoopCount(int cycleUs) {
  if (cycleUs <= 0) return 1;
  if (cycleUs > 8_000_000) return 1;
  var loops = (3_000_000 / cycleUs).ceil().clamp(2, 5);
  while (loops > 1 && loops * cycleUs > 8_000_000) {
    loops--;
  }
  return loops;
}

/// Whole frames from frame 1 until the cumulative authored duration first reaches ~60 s
/// (always ≥1) — the "excerpt" choice for very long cycles.
int excerptFrameCount(List<int> frameDurationsUs) {
  var sum = 0;
  for (var i = 0; i < frameDurationsUs.length; i++) {
    sum += frameDurationsUs[i];
    if (sum >= 60_000_000) return i + 1;
  }
  return frameDurationsUs.length;
}

/// Build the finale entries. [fullCycle] = false means the excerpt choice (only offered
/// when `cycleUs > 60 s`); a static drawing ignores both and holds.
List<TimelapseEntry> planFinale(List<int> frameDurationsUs, {bool fullCycle = true}) {
  if (frameDurationsUs.length <= 1) {
    return const [TimelapseEntry.finale(0, kStaticHoldUs)];
  }
  final frames = fullCycle ? frameDurationsUs.length : excerptFrameCount(frameDurationsUs);
  final durations = frameDurationsUs.sublist(0, frames);
  final loops = fullCycle ? finaleLoopCount(cycleUs(frameDurationsUs)) : 1;
  return [
    for (var l = 0; l < loops; l++)
      for (var i = 0; i < frames; i++) TimelapseEntry.finale(i, durations[i]),
  ];
}

/// The whole timelapse: progress samples for [seconds] at 30 fps drawn uniformly from
/// [visiblePositions] (the visible-change index), then the finale.
List<TimelapseEntry> planTimelapse({
  required List<int> visiblePositions,
  required int seconds,
  required List<int> frameDurationsUs,
  bool fullCycleFinale = true,
}) {
  return [
    for (final p in samplePositions(visiblePositions, seconds * 30))
      TimelapseEntry.progress(p, kProgressFrameUs),
    ...planFinale(frameDurationsUs, fullCycle: fullCycleFinale),
  ];
}

/// Total output duration, µs (for the dialog's length warnings).
int totalDurationUs(List<TimelapseEntry> entries) => entries.fold(0, (a, e) => a + e.durationUs);

/// The integer upscale factor: the largest N with `w·N ≤ outW` and `h·N ≤ outH` (≥1).
int letterboxScale(int w, int h, int outW, int outH) {
  final n = (outW ~/ w) < (outH ~/ h) ? outW ~/ w : outH ~/ h;
  return n < 1 ? 1 : n;
}

/// Where the wordmark goes: centered in the BOTTOM letterbox band, only when the band
/// clears the mark by ≥16 px — never over the pixels. Mirrors `center_pad_rgba`'s
/// even-floored content offset (I420 chroma alignment). Returns null to skip (e.g. the
/// square preset over square art leaves only slivers).
({int x, int y})? wordmarkPlacement({
  required int contentW,
  required int contentH,
  required int outW,
  required int outH,
  required int wmW,
  required int wmH,
}) {
  final oy = ((outH - contentH) ~/ 2) & ~1;
  final band = outH - oy - contentH;
  if (band < wmH + 16 || wmW > outW) return null;
  return (x: (outW - wmW) ~/ 2, y: oy + contentH + (band - wmH) ~/ 2);
}
