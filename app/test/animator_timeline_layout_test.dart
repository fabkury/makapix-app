// The timeline's pure geometry (lib/animator/model/timeline_layout.dart): frame↔px
// round-trips, zoom-about-focal, tick aggregation, label cadence, frame snapping, and the
// gesture-safety additions — side gutters (originX/rightInset) and over-scroll.
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/animator/model/timeline_layout.dart';

void main() {
  test('fit layout spans the whole scene and round-trips frames', () {
    final l = TimelineLayout.fit(width: 250, frameCount: 25);
    expect(l.pxPerFrame, 10);
    expect(l.maxScroll, 0);
    for (final f in [0, 7, 24]) {
      expect(l.frameAtX(l.xAtFrame(f)), f, reason: 'frame $f round-trips');
    }
    expect(l.frameAtX(-50), 0, reason: 'clamped at the left edge');
    expect(l.frameAtX(9999), 24, reason: 'clamped at the right edge');
  });

  test('fit clamps px-per-frame into the zoom range', () {
    expect(TimelineLayout.fit(width: 100, frameCount: 1000).pxPerFrame, kMinPxPerFrame);
    expect(TimelineLayout.fit(width: 1000, frameCount: 2).pxPerFrame, kMaxPxPerFrame);
  });

  test('scroll clamps and shifts the visible range', () {
    final l = TimelineLayout(width: 100, frameCount: 100, pxPerFrame: 10, scroll: 0);
    expect(l.maxScroll, 900);
    final s = l.scrolledBy(10000);
    expect(s.scroll, 900);
    final (first, last) = s.visibleRange();
    expect(first, 90);
    expect(last, 99);
  });

  test('zoomedTo keeps the focal frame under the finger', () {
    final l = TimelineLayout(width: 200, frameCount: 100, pxPerFrame: 4, scroll: 120);
    const focalX = 80.0;
    final focalFrame = l.frameAtX(focalX);
    final z = l.zoomedTo(16, focalX);
    expect(z.pxPerFrame, 16);
    expect(z.frameAtX(focalX), focalFrame, reason: 'the frame under the focal point is stable');
  });

  test('aggregateTicks clusters close key frames', () {
    final l = TimelineLayout(width: 100, frameCount: 100, pxPerFrame: 2, scroll: 0);
    // Frames 0,1,2 are 2 px apart → cluster; frame 30 stands alone.
    final ticks = aggregateTicks([0, 1, 2, 30], l, minGapPx: 6);
    expect(ticks.length, 2);
  });

  test('label cadence grows as zoom shrinks', () {
    expect(
        TimelineLayout(width: 100, frameCount: 100, pxPerFrame: 48, scroll: 0).labelStep(), 1);
    expect(
        TimelineLayout(width: 100, frameCount: 100, pxPerFrame: 2, scroll: 0).labelStep(), 25);
  });

  test('snapFrame magnetizes within tolerance only', () {
    expect(snapFrame(10, [12], tolFrames: 2), 12);
    expect(snapFrame(10, [13], tolFrames: 2), 10);
    expect(snapFrame(10, [9, 11], tolFrames: 2), 9, reason: 'nearest magnet wins');
    expect(snapFrame(10, [], tolFrames: 2), 10);
  });

  // ---- gesture-safety geometry (docs/animator/06-gesture-safety.md §4.2) ----

  test('side gutters inset the lane and round-trip frames', () {
    final l = TimelineLayout.fit(
        width: 250 + 32 + 24, frameCount: 25, originX: 32, rightInset: 24);
    expect(l.laneWidth, 250);
    expect(l.pxPerFrame, 10, reason: 'fit divides the LANE width, not the band');
    expect(l.leftOfFrame(0), 32, reason: 'frame 0 starts inboard of the left gutter');
    for (final f in [0, 7, 24]) {
      expect(l.frameAtX(l.xAtFrame(f)), f, reason: 'frame $f round-trips with gutters');
    }
    expect(l.frameAtX(0), 0, reason: 'a gutter tap clamps to the nearest frame');
    expect(l.frameAtX(9999), 24);
  });

  test('over-scroll widens the scroll bounds on both ends', () {
    const l = TimelineLayout(
        width: 100, frameCount: 100, pxPerFrame: 10, overscroll: 40);
    expect(l.maxScroll, 940);
    expect(l.minScroll, -40);
    expect(l.clampScroll(-1e9), -40);
    expect(l.clampScroll(1e9), 940);
    // Without over-scroll the old bounds hold.
    const tight = TimelineLayout(width: 100, frameCount: 100, pxPerFrame: 10);
    expect(tight.clampScroll(-5), 0);
    expect(tight.maxScroll, 900);
  });

  test('zoomedTo keeps the focal frame stable with a nonzero origin', () {
    const l = TimelineLayout(
        width: 232, frameCount: 100, pxPerFrame: 4, scroll: 120, originX: 32);
    const focalX = 96.0;
    final focalFrame = l.frameAtX(focalX);
    final z = l.zoomedTo(16, focalX);
    expect(z.originX, 32, reason: 'gutters survive the zoom');
    expect(z.frameAtX(focalX), focalFrame);
  });

  test('aggregateTicks culls against the gutter-inset lane window', () {
    const l = TimelineLayout(
        width: 164, frameCount: 100, pxPerFrame: 2, originX: 32, rightInset: 32);
    // laneWidth = 100 → frames past x 32+100+6 are culled; frame 60 → x = 32+121 > 138.
    final ticks = aggregateTicks([0, 1, 2, 30, 60], l, minGapPx: 6);
    expect(ticks.length, 2, reason: 'cluster 0-2, keep 30, cull 60 past the right gutter');
    expect(ticks.first, greaterThanOrEqualTo(32), reason: 'ticks live inboard of the gutter');
  });
}
