// Timeline geometry — the pure frame↔pixel math behind every zoom level of the one-timeline
// surface (Strip / Tracks / Focus). Engine-free and unit-tested; the painters and gesture
// handlers consume this so hit zones and drawing can never disagree.
//
// Gesture safety (docs/animator/06-gesture-safety.md): [originX]/[rightInset] are the
// adaptive side gutters — frame 0 and the last frame live inboard of the OS Back-gesture
// zones — and [overscroll] lets Tracks/Focus scroll past both ends so edge keys can be
// dragged from mid-screen.
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
  /// Full band width in px (gutters included).
  final double width;
  final int frameCount;
  final double pxPerFrame;

  /// Horizontal scroll offset in px (0 = frame 0 at the lane's left edge).
  final double scroll;

  /// Left gutter: frame 0's cell starts at this band-x.
  final double originX;

  /// Right gutter width.
  final double rightInset;

  /// Extra scrollable px allowed past both ends of the content.
  final double overscroll;

  const TimelineLayout({
    required this.width,
    required this.frameCount,
    required this.pxPerFrame,
    this.scroll = 0,
    this.originX = 0,
    this.rightInset = 0,
    this.overscroll = 0,
  });

  /// A layout that fits the whole scene between the gutters (the Strip's default).
  factory TimelineLayout.fit({
    required double width,
    required int frameCount,
    double originX = 0,
    double rightInset = 0,
  }) {
    final lane = math.max(1.0, width - originX - rightInset);
    final ppf = frameCount <= 0
        ? kMinPxPerFrame
        : (lane / frameCount).clamp(kMinPxPerFrame, kMaxPxPerFrame).toDouble();
    return TimelineLayout(
      width: width,
      frameCount: frameCount,
      pxPerFrame: ppf,
      originX: originX,
      rightInset: rightInset,
    );
  }

  /// Drawable lane width between the gutters.
  double get laneWidth => math.max(1.0, width - originX - rightInset);

  double get contentWidth => frameCount * pxPerFrame;

  /// Scroll bounds: content pinned to the lane, extended by [overscroll] on both ends.
  double get maxScroll => math.max(0, contentWidth - laneWidth) + overscroll;
  double get minScroll => -overscroll;

  double clampScroll(double s) => s.clamp(minScroll, maxScroll);

  /// Center-x of a frame's cell, in band px.
  double xAtFrame(int frame) =>
      originX + frame * pxPerFrame - scroll + pxPerFrame / 2;

  /// Left edge of a frame's cell, in band px.
  double leftOfFrame(int frame) => originX + frame * pxPerFrame - scroll;

  /// The frame whose cell contains band-x (clamped into range).
  int frameAtX(double x) {
    if (frameCount <= 0) return 0;
    final f = ((x - originX + scroll) / pxPerFrame).floor();
    return f.clamp(0, frameCount - 1);
  }

  /// Visible frame range [first, last] (inclusive; empty scene → (0, -1)).
  (int, int) visibleRange() {
    if (frameCount <= 0) return (0, -1);
    final first = (scroll / pxPerFrame).floor().clamp(0, frameCount - 1);
    final last =
        (((scroll + laneWidth) / pxPerFrame).ceil() - 1).clamp(0, frameCount - 1);
    return (first, last);
  }

  /// The continuous (unclamped, fractional) frame index under band-x — the anchor a
  /// two-finger gesture holds on to.
  double continuousFrameAt(double x) => (x - originX + scroll) / pxPerFrame;

  /// The unified two-finger pan+zoom: the layout at [newPxPerFrame] with scroll set so
  /// continuous [focusFrame] sits under band-x [focalX]. Zoom comes from the finger
  /// distance, pan from the moving midpoint — same formula, no separate modes.
  TimelineLayout panZoomedTo(double newPxPerFrame, double focusFrame, double focalX) {
    final ppf = newPxPerFrame.clamp(kMinPxPerFrame, kMaxPxPerFrame).toDouble();
    final probe = TimelineLayout(
      width: width,
      frameCount: frameCount,
      pxPerFrame: ppf,
      originX: originX,
      rightInset: rightInset,
      overscroll: overscroll,
    );
    return TimelineLayout(
      width: width,
      frameCount: frameCount,
      pxPerFrame: ppf,
      scroll: probe.clampScroll(focusFrame * ppf - (focalX - originX)),
      originX: originX,
      rightInset: rightInset,
      overscroll: overscroll,
    );
  }

  /// Zoom about a band-x focal point: returns the layout at [newPxPerFrame] with scroll
  /// adjusted so the frame under [focalX] stays put.
  TimelineLayout zoomedTo(double newPxPerFrame, double focalX) {
    final ppf = newPxPerFrame.clamp(kMinPxPerFrame, kMaxPxPerFrame).toDouble();
    final laneX = focalX - originX;
    final focusFrame = (laneX + scroll) / pxPerFrame; // continuous frame index
    final newScroll = focusFrame * ppf - laneX;
    final zoomed = TimelineLayout(
      width: width,
      frameCount: frameCount,
      pxPerFrame: ppf,
      originX: originX,
      rightInset: rightInset,
      overscroll: overscroll,
    );
    return TimelineLayout(
      width: width,
      frameCount: frameCount,
      pxPerFrame: ppf,
      scroll: zoomed.clampScroll(newScroll),
      originX: originX,
      rightInset: rightInset,
      overscroll: overscroll,
    );
  }

  TimelineLayout scrolledBy(double dx) => TimelineLayout(
        width: width,
        frameCount: frameCount,
        pxPerFrame: pxPerFrame,
        scroll: clampScroll(scroll + dx),
        originX: originX,
        rightInset: rightInset,
        overscroll: overscroll,
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
/// (the Strip's aggregated view at low zoom). Returns the band-x of each drawn tick.
List<double> aggregateTicks(Iterable<int> frames, TimelineLayout layout,
    {double minGapPx = 6}) {
  final xs = frames.map(layout.xAtFrame).toList()..sort();
  final lo = layout.originX - minGapPx;
  final hi = layout.originX + layout.laneWidth + minGapPx;
  final out = <double>[];
  for (final x in xs) {
    if (x < lo || x > hi) continue;
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
