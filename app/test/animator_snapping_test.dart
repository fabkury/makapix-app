// Stage snapping math (lib/animator/model/snapping.dart): position magnets, 15° rotation
// stops, the 1.0 scale detent, and millidegree normalization.
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/animator/model/snapping.dart';

void main() {
  test('position snaps to edges and center within tolerance', () {
    expect(snapPosition(2, 64).value, 0);
    expect(snapPosition(2, 64).snapped, isTrue);
    expect(snapPosition(31, 64).value, 32);
    expect(snapPosition(63, 64).value, 64);
    expect(snapPosition(20, 64).value, 20);
    expect(snapPosition(20, 64).snapped, isFalse);
  });

  test('rotation snaps to 15-degree stops within 4 degrees', () {
    expect(snapRotation(14_000).value, 15_000);
    expect(snapRotation(14_000).snapped, isTrue);
    expect(snapRotation(46_500).value, 45_000);
    expect(snapRotation(52_000).value, 52_000, reason: '7° from a stop → free');
    expect(snapRotation(-14_200).value, -15_000, reason: 'negative angles snap too');
    expect(snapRotation(0).value, 0);
  });

  test('scale detents at 1.0 within 5 percent', () {
    expect(snapScale(1030).value, 1000);
    expect(snapScale(1030).snapped, isTrue);
    expect(snapScale(1100).value, 1100);
    expect(snapScale(1100).snapped, isFalse);
  });

  test('normalizeMdeg wraps into [-180°, 180°)', () {
    expect(normalizeMdeg(0), 0);
    expect(normalizeMdeg(190_000), -170_000);
    expect(normalizeMdeg(-190_000), 170_000);
    expect(normalizeMdeg(360_000), 0);
    expect(normalizeMdeg(720_000 + 30_000), 30_000);
  });
}
