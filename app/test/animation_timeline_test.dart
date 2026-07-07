// Pure unit tests for the clock→frame mapping — no engine, no network, no widgets.
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/anim/animation_timeline.dart';

void main() {
  group('clampDelayMs', () {
    test('delays at or below 10 ms clamp to 100 ms', () {
      expect(AnimationTimeline.clampDelayMs(0), 100);
      expect(AnimationTimeline.clampDelayMs(1), 100);
      expect(AnimationTimeline.clampDelayMs(10), 100);
    });
    test('delays above 10 ms pass through', () {
      expect(AnimationTimeline.clampDelayMs(11), 11);
      expect(AnimationTimeline.clampDelayMs(100), 100);
      expect(AnimationTimeline.clampDelayMs(5000), 5000);
    });
  });

  group('totalDurationMs', () {
    test('sums clamped delays', () {
      final t = AnimationTimeline([100, 200, 0]); // 0 → 100
      expect(t.totalDurationMs, 400);
      expect(t.delaysMs, [100, 200, 100]);
    });
    test('floors at kMinLoopDurationMs', () {
      // A single 11 ms frame sums below the 30 ms floor.
      final t = AnimationTimeline([11]);
      expect(t.totalDurationMs, kMinLoopDurationMs);
    });
    test('computeTotalDurationMs matches a constructed timeline', () {
      const raw = [0, 10, 11, 250, 3];
      expect(AnimationTimeline.computeTotalDurationMs(raw),
          AnimationTimeline(raw).totalDurationMs);
      expect(AnimationTimeline.computeTotalDurationMs([12]), kMinLoopDurationMs);
    });
  });

  group('frameIndexAt', () {
    // Frames: 100, 200, 300 → cumulative 100, 300, 600; loop 600 ms.
    final t = AnimationTimeline([100, 200, 300]);

    test('start of loop is frame 0', () {
      expect(t.frameIndexAt(0), 0);
      expect(t.frameIndexAt(99), 0);
    });
    test('a cumulative boundary belongs to the next frame', () {
      expect(t.frameIndexAt(100), 1);
      expect(t.frameIndexAt(299), 1);
      expect(t.frameIndexAt(300), 2);
      expect(t.frameIndexAt(599), 2);
      expect(t.frameIndexAt(600), 0); // wraps
    });
    test('modulo holds at large wall-clock values', () {
      // Realistic epoch-scale nowMs (year ~2026).
      const base = 1780000000000;
      final aligned = base - (base % 600);
      expect(t.frameIndexAt(aligned), 0);
      expect(t.frameIndexAt(aligned + 150), 1);
      expect(t.frameIndexAt(aligned + 599), 2);
    });
    test('two computations at the same instant always agree', () {
      final other = AnimationTimeline([100, 200, 300]);
      for (final now in [0, 12345, 999999999, 1780000000123]) {
        expect(t.frameIndexAt(now), other.frameIndexAt(now));
      }
    });

    test('positive phase offset shifts the loop', () {
      final shifted = AnimationTimeline([100, 200, 300], phaseOffsetMs: 100);
      expect(shifted.frameIndexAt(0), 1); // 0 + 100 lands in frame 1
      expect(shifted.frameIndexAt(500), 0); // 600 mod 600 = 0
    });
    test('negative phase offset never yields a negative position', () {
      final shifted = AnimationTimeline([100, 200, 300], phaseOffsetMs: -50);
      expect(shifted.frameIndexAt(0), 2); // -50 mod 600 → 550 → frame 2
      expect(shifted.frameIndexAt(49), 2);
      expect(shifted.frameIndexAt(50), 0);
    });

    test('min-loop padding zone maps to the last frame', () {
      // Two 11 ms frames sum to 22 < 30: positions 22..29 are padding.
      final tiny = AnimationTimeline([11, 11]);
      expect(tiny.totalDurationMs, kMinLoopDurationMs);
      expect(tiny.frameIndexAt(0), 0);
      expect(tiny.frameIndexAt(11), 1);
      expect(tiny.frameIndexAt(22), 1); // padding → last frame
      expect(tiny.frameIndexAt(29), 1);
      expect(tiny.frameIndexAt(30), 0); // wraps
    });

    test('single-frame animation always shows frame 0', () {
      final single = AnimationTimeline([500]);
      for (final now in [0, 1, 499, 500, 123456789]) {
        expect(single.frameIndexAt(now), 0);
      }
    });
  });
}
