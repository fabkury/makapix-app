// Timeline geometry — the pure frame↔pixel math behind every zoom level of the one-timeline
// surface (Strip / Tracks / Focus). Engine-free and unit-tested; the painters and gesture
// handlers consume this so hit zones and drawing can never disagree.
library;

import 'dart:math' as math;

/// Zoom clamp: pixels of lane per scene frame.
const double kMinPxPerFrame = 2.0;
const double kMaxPxPerFrame = 48.0;

/// Hit tolerance around a key tick, in lane px (a fat-finger half-target).
const double kKeyHitPx = 11.0;

/// Loop-region edge-handle hit zone, in lane px.
const double kLoopHandleHitPx = 22.0;

class TimelineLayout {
  /// Lane width in px.
  final double width;
  final int frameCount;
  final double pxPerFrame;

  /// Horizontal scroll offset in px (0 = frame 0 at the left edge).
  final double scroll;

  const TimelineLayout({
    required this.width,
    required this.frameCount,
    required this.pxPerFrame,
    this.scroll = 0,
  });

  /// A layout that fits the whole scene in [width] (the Strip's default).
  factory TimelineLayout.fit({required double width, required int frameCount}) {
    final ppf = frameCount <= 0
        ? kMinPxPerFrame
        : (width / frameCount).clamp(kMinPxPerFrame, kMaxPxPerFrame).toDouble();
    return TimelineLayout(width: width, frameCount: frameCount, pxPerFrame: ppf);
  }

  double get contentWidth => frameCount * pxPerFrame;

  /// Max scroll keeping content pinned to the lane.
  double get maxScroll => math.max(0, contentWidth - width);

  double clampScroll(double s) => s.clamp(0.0, maxScroll);

  /// Center-x of a frame's cell, in lane px.
  double xAtFrame(int frame) => frame * pxPerFrame - scroll + pxPerFrame / 2;

  /// Left edge of a frame's cell.
  double leftOfFrame(int frame) => frame * pxPerFrame - scroll;

  /// The frame whose cell contains lane-x (clamped into range).
  int frameAtX(double x) {
    if (frameCount <= 0) return 0;
    final f = ((x + scroll) / pxPerFrame).floor();
    return f.clamp(0, frameCount - 1);
  }

  /// Visible frame range [first, last] (inclusive; empty scene → (0, -1)).
  (int, int) visibleRange() {
    if (frameCount <= 0) return (0, -1);
    final first = (scroll / pxPerFrame).floor().clamp(0, frameCount - 1);
    final last =
        (((scroll + width) / pxPerFrame).ceil() - 1).clamp(0, frameCount - 1);
    return (first, last);
  }

  /// Zoom about a lane-x focal point: returns the layout at [newPxPerFrame] with scroll
  /// adjusted so the frame under [focalX] stays put.
  TimelineLayout zoomedTo(double newPxPerFrame, double focalX) {
    final ppf = newPxPerFrame.clamp(kMinPxPerFrame, kMaxPxPerFrame).toDouble();
    final focusFrame = (focalX + scroll) / pxPerFrame; // continuous frame index
    final newScroll = focusFrame * ppf - focalX;
    final zoomed = TimelineLayout(
        width: width, frameCount: frameCount, pxPerFrame: ppf, scroll: 0);
    return TimelineLayout(
      width: width,
      frameCount: frameCount,
      pxPerFrame: ppf,
      scroll: zoomed.clampScroll(newScroll),
    );
  }

  TimelineLayout scrolledBy(double dx) => TimelineLayout(
        width: width,
        frameCount: frameCount,
        pxPerFrame: pxPerFrame,
        scroll: clampScroll(scroll + dx),
      );

  /// Ruler label cadence: a frame number every ⌈32 px⌉ worth of frames, in 1/5/10/25/50/100
  /// steps so labels stay round.
  int labelStep() {
    final minFrames = (32 / pxPerFrame).ceil();
    for (final step in [1, 5, 10, 25, 50, 100, 250]) {
      if (step >= minFrames) return step;
    }
    return 500;
  }
}

/// Cluster key-frame ticks that would land closer than [minGapPx] apart into single marks
/// (the Strip's aggregated view at low zoom). Returns the lane-x of each drawn tick.
List<double> aggregateTicks(Iterable<int> frames, TimelineLayout layout,
    {double minGapPx = 6}) {
  final xs = frames.map(layout.xAtFrame).toList()..sort();
  final out = <double>[];
  for (final x in xs) {
    if (x < -minGapPx || x > layout.width + minGapPx) continue;
    if (out.isEmpty || (x - out.last) >= minGapPx) {
      out.add(x);
    }
  }
  return out;
}

/// Snap a dragged key's candidate frame to magnets (other keys, loop edges) within
/// [tolFrames]; otherwise return the candidate itself.
int snapFrame(int candidate, Iterable<int> magnets, {int tolFrames = 1}) {
  int best = candidate;
  int bestDist = tolFrames + 1;
  for (final m in magnets) {
    final d = (m - candidate).abs();
    if (d < bestDist) {
      bestDist = d;
      best = m;
    }
  }
  return bestDist <= tolFrames ? best : candidate;
}
