import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/playback_clock.dart';

void main() {
  group('PlaybackClock', () {
    test('60 Hz cadence loses no time to ms rounding', () {
      final c = PlaybackClock();
      var sum = 0;
      for (var i = 1; i <= 600; i++) {
        final ms = c.advance(i * 16667); // ideal 60 Hz vsync stamps
        expect(ms, inInclusiveRange(16, 17));
        sum += ms;
      }
      expect(sum, (600 * 16667) ~/ 1000); // exactly floor(elapsed/1000): zero drift
    });

    test('30 Hz cadence alternates 33/34 and stays exact', () {
      final c = PlaybackClock();
      var sum = 0;
      for (var i = 1; i <= 90; i++) {
        final ms = c.advance(i * 33333);
        expect(ms, inInclusiveRange(33, 34));
        sum += ms;
      }
      expect(sum, (90 * 33333) ~/ 1000);
    });

    test('sub-ms ticks return 0 until the carry crosses a millisecond', () {
      final c = PlaybackClock();
      expect(c.advance(400), 0);
      expect(c.advance(800), 0);
      expect(c.advance(1200), 1); // carry reached 1200 µs
      expect(c.advance(1200), 0); // zero dt
    });

    test('a stall (route-cover unmute) is clamped to maxTickUs', () {
      final c = PlaybackClock();
      expect(c.advance(16667), 16);
      // 5 s gap: only the clamp's worth advances; the rest is discarded.
      expect(c.advance(16667 + 5000000), PlaybackClock.maxTickUs ~/ 1000);
      // The 667 µs carry from the first tick survives the clamped tick.
      expect(c.advance(16667 + 5000000 + 333), 1); // 667 + 333 = 1 ms
    });

    test('a gap at exactly maxTickUs passes through unclamped', () {
      final c = PlaybackClock();
      expect(c.advance(PlaybackClock.maxTickUs), PlaybackClock.maxTickUs ~/ 1000);
      expect(c.advance(PlaybackClock.maxTickUs + 16667), 16);
    });

    test('reset forgets the carry and the last stamp', () {
      final c = PlaybackClock();
      c.advance(999); // 999 µs carried
      c.reset();
      expect(c.advance(0), 0); // restart at zero: no dt, no leftover carry
      expect(c.advance(16667), 16);
    });

    test('running sum equals floor(elapsed / 1000) over an irregular sequence', () {
      final c = PlaybackClock();
      var sum = 0;
      var elapsed = 0;
      // Jittery deltas: vsync-ish, dropped frames, a stall, sub-ms noise.
      for (final dt in [16667, 8333, 33334, 250, 750, 100000, 16667, 1, 999, 16667]) {
        elapsed += dt;
        sum += c.advance(elapsed);
        expect(sum, elapsed ~/ 1000);
      }
    });
  });
}
