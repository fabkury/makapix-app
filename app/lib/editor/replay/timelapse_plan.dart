/// Timelapse planning — pure math, no IO, no engine (CONTEXT.md "Timelapse").
///
/// A Timelapse is: a PROGRESS portion (the Journal's timeline paced into the chosen preset
/// duration at 30 fps — [paceTimeline], ADR 0029) followed by an APPENDED finale — the
/// finished piece. Animated drawings play whole cycles from frame 1 at their authored
/// per-frame durations (loop until ≥3 s AND ≥2 full plays, capped at 5 loops / ~8 s, a single
/// full play never truncated); static drawings hold 4.5 s. Cycles longer than 60 s are the
/// caller's per-export dialog (full play vs whole-frame excerpt — [excerptFrameCount]).
///
/// Pacing (ADR 0029): each tick of the timeline dwells in proportion to its WORKING TIME
/// (`visible_index.dart`), under a fixed total. Event ticks are clamped into a floor (the eye
/// must register a fill, an apply, a commit even after a fast tap) and a ceiling (a long tuning
/// session must never freeze the video); stream ticks scale linearly. The remaining budget is
/// water-filled: one scale factor `s` with `Σ dwell == total` is found by bisection over the
/// event ticks only (stream mass is a closed form), so the cost is a few dozen passes over the
/// events — microseconds at realistic counts — and the result is deterministic. The same
/// cumulative axis drives the Replay viewer's sweep and slider, so scrubbing the viewer
/// previews the exported Timelapse frame for frame.
library;

import 'dart:typed_data';

import 'visible_index.dart';

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

/// An event tick dwells at least this many progress frames (0.2 s) …
const int kEventFloorFrames = 6;

/// … or 1/100 of the progress duration, whichever is longer (0.3 s at 30 s, 0.6 s at 60 s, so
/// the presets scale together).
const int kEventFloorDivisor = 100;

/// An event tick dwells at most 1/12 of the progress duration (2.5 s at 30 s): an apply never
/// freezes the video, however long it was tuned.
const int kEventCeilDivisor = 12;

/// Floors may claim at most this share (3/5) of the progress duration; past it the floor
/// shrinks so a journal of hundreds of fills still fits and stays proportional.
const int kFloorShareNum = 3;
const int kFloorShareDen = 5;

/// The progress portion's total duration for a preset, µs: exactly `seconds × 30` frames of
/// [kProgressFrameUs], so the paced axis and the emitted frames agree to the microsecond.
int progressDurationUs(int seconds) => seconds * 30 * kProgressFrameUs;

/// Pace [timeline] into the [seconds] preset: the cumulative video time (µs) at the END of
/// each tick — non-decreasing, `last == progressDurationUs(seconds)`. Empty in, empty out.
///
/// A journal with no timing at all (every working time 0: synthetic scripts, `+0` content)
/// paces uniformly, exactly like the pre-ADR-0029 visible index.
Uint32List paceTimeline(ReplayTimeline timeline, int seconds) {
  final n = timeline.length;
  final out = Uint32List(n);
  if (n == 0) return out;
  final total = progressDurationUs(seconds);
  var work = 0, streamWork = 0, events = 0;
  for (var k = 0; k < n; k++) {
    final w = timeline.workMs[k];
    work += w;
    if (timeline.isEvent[k] != 0) {
      events++;
    } else {
      streamWork += w;
    }
  }
  final dwell = Float64List(n);
  if (work == 0) {
    final each = total / n;
    for (var k = 0; k < n; k++) {
      dwell[k] = each;
    }
  } else {
    var floor = kEventFloorFrames * kProgressFrameUs > total ~/ kEventFloorDivisor
        ? (kEventFloorFrames * kProgressFrameUs).toDouble()
        : (total ~/ kEventFloorDivisor).toDouble();
    var ceil = (total ~/ kEventCeilDivisor).toDouble();
    final floorBudget = total * kFloorShareNum / kFloorShareDen;
    if (events > 0 && events * floor > floorBudget) floor = floorBudget / events;
    if (ceil < floor) ceil = floor;
    // Working time is ms; s converts it to video µs.
    double eventDwell(int k, double s) {
      final d = s * timeline.workMs[k] * 1000;
      return d < floor ? floor : (d > ceil ? ceil : d);
    }

    double sum(double s) {
      var t = s * streamWork * 1000;
      for (var k = 0; k < n; k++) {
        if (timeline.isEvent[k] != 0) t += eventDwell(k, s);
      }
      return t;
    }

    // Bracket, then bisect: sum(s) is continuous and non-decreasing in s.
    var lo = 0.0, hi = 1.0;
    var doublings = 0;
    while (sum(hi) < total && doublings < 64) {
      hi *= 2;
      doublings++;
    }
    if (sum(hi) < total) {
      // Unreachable total: no stream mass and every event saturates below the budget (a
      // journal of a few fills and nothing else). Scale the saturated dwells up to fill it.
      final scale = total / sum(hi);
      for (var k = 0; k < n; k++) {
        dwell[k] = (timeline.isEvent[k] != 0 ? eventDwell(k, hi) : 0) * scale;
      }
    } else {
      for (var i = 0; i < 60; i++) {
        final mid = (lo + hi) / 2;
        if (sum(mid) < total) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      for (var k = 0; k < n; k++) {
        dwell[k] = timeline.isEvent[k] != 0 ? eventDwell(k, hi) : hi * timeline.workMs[k] * 1000;
      }
    }
  }
  var cum = 0.0;
  var prev = 0;
  for (var k = 0; k < n; k++) {
    cum += dwell[k];
    var v = cum.round();
    if (v > total) v = total;
    if (v < prev) v = prev;
    out[k] = v;
    prev = v;
  }
  out[n - 1] = total;
  return out;
}

/// The tick in progress at video instant [us]: the first index whose cumulative time reaches
/// it (binary search over [cumUs]). −1 for `us ≤ 0` (the starting state); the last index for
/// `us ≥ total`. Ticks whose dwell rounded to nothing are never returned (their interval is
/// empty), except the last one, which the final instant always reaches.
int tickIndexAt(Uint32List cumUs, int us) {
  final n = cumUs.length;
  if (n == 0 || us <= 0) return -1;
  if (us >= cumUs[n - 1]) return n - 1;
  var lo = 0, hi = n - 1; // invariant: cumUs[hi] >= us
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (cumUs[mid] < us) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// Output shape presets (ADR 0004: even dimensions, safe on every OS encoder).
enum TimelapseShape {
  square(1080, 1080, 'Square 1080×1080'),
  portrait(1080, 1920, 'Portrait 1080×1920');

  const TimelapseShape(this.outW, this.outH, this.label);
  final int outW;
  final int outH;
  final String label;
}

/// Sample [samples] frames over a paced timeline: frame `f` shows the tick in progress at the
/// end of its window, `(f+1)/samples` of the way through the progress portion. Monotonic
/// non-decreasing; the last frame is always `positions.last` (the finished state, even when a
/// trailing tick has no dwell); ticks whose dwell rounded to nothing are skipped; duplicates
/// (fewer ticks than frames) are legal — repeated frames delta-encode to almost nothing.
List<int> samplePositions(List<int> positions, Uint32List cumUs, int samples) {
  if (samples <= 0 || positions.isEmpty) return const [];
  final total = cumUs[cumUs.length - 1];
  final out = List<int>.filled(samples, positions.last);
  var k = 0;
  for (var f = 0; f < samples - 1; f++) {
    final t = (f + 1) * total; // the frame's end instant, scaled by `samples`
    while (k < positions.length - 1 && cumUs[k] * samples < t) {
      k++;
    }
    out[f] = positions[k];
  }
  return out;
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

/// The whole timelapse: the paced [timeline] sampled at 30 fps for [seconds], then the finale.
List<TimelapseEntry> planTimelapse({
  required ReplayTimeline timeline,
  required int seconds,
  required List<int> frameDurationsUs,
  bool fullCycleFinale = true,
}) {
  final cum = paceTimeline(timeline, seconds);
  return [
    for (final p in samplePositions(timeline.positions, cum, seconds * 30))
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
