// Geared draft drags (ADR 0020, editor/drag_gear.dart): the pure math the Move /
// Move-selection / Paste drag pathways apply before any DSL traffic. No engine binary, no
// widget pumping — the keyboard_constrain_test.dart precedent.
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/editor/drag_gear.dart';

void main() {
  group('draftGearDivisor (the zoom-cap curve)', () {
    test('coarse views get the full house ratio', () {
      expect(draftGearDivisor(1.5), kDraftGearRatio); // fit zoom on a 256 canvas, phone
      expect(draftGearDivisor(5.0), kDraftGearRatio);
      expect(draftGearDivisor(8.0), kDraftGearRatio); // the knee: 4 × 8 = 32 = the cap
    });

    test('between the knee and the cap the finger cost per pixel is flat at the cap', () {
      for (final scale in [8.0, 10.0, 16.0, 24.0, 32.0]) {
        expect(scale * draftGearDivisor(scale), closeTo(kDraftGearCapPx, 1e-9), reason: '$scale');
      }
    });

    test('past the cap gearing is fully off', () {
      expect(draftGearDivisor(32.0), 1.0);
      expect(draftGearDivisor(48.0), 1.0);
      expect(draftGearDivisor(200.0), 1.0);
    });

    test('the curve is monotone and continuous across the knee and the cap', () {
      var prev = draftGearDivisor(0.5);
      for (var s = 0.5; s <= 64; s += 0.25) {
        final d = draftGearDivisor(s);
        expect(d, lessThanOrEqualTo(prev + 1e-12), reason: 'non-increasing at $s');
        expect(d, inInclusiveRange(1.0, kDraftGearRatio));
        prev = d;
      }
    });

    test('degenerate scales never gear', () {
      expect(draftGearDivisor(0), 1.0);
      expect(draftGearDivisor(-3), 1.0);
      expect(draftGearDivisor(double.nan), 1.0);
    });
  });

  group('TotalDragTracker, ungeared (the historical 1:1 path)', () {
    test('sends corrective deltas so the accumulated total tracks the finger', () {
      final t = TotalDragTracker(const Offset(10, 10));
      expect(t.geared, isFalse);
      expect(t.step(const Offset(12, 10)), (2, 0));
      expect(t.step(const Offset(12, 13)), (0, 3));
      expect(t.step(const Offset(11, 13)), (-1, 0)); // reversing sends the difference only
      expect(t.step(const Offset(11, 13)), (0, 0)); // no movement → nothing to send
      expect((t.sentDx, t.sentDy), (1, 3));
    });

    test('a held Shift axis-locks the TOTAL, with no off-axis drift', () {
      final t = TotalDragTracker(Offset.zero);
      expect(t.step(const Offset(3, 0)), (3, 0));
      expect(t.step(const Offset(3, 2), axisLock: true), (0, 0));
      // Shift landing mid-drag re-targets the whole total: y that was never sent stays 0,
      // and a later dominant-y move pulls x back to 0.
      expect(t.step(const Offset(2, 9), axisLock: true), (-3, 9));
      expect((t.sentDx, t.sentDy), (0, 9));
    });
  });

  group('TotalDragTracker, geared (Slow)', () {
    test('the draft moves 1/divisor of the finger, with the remainder carried across events', () {
      final t = TotalDragTracker(Offset.zero, divisor: 4.0);
      expect(t.geared, isTrue);
      // Four 1-px finger moves add up to exactly one draft pixel (round-half-up at 2 px).
      expect(t.step(const Offset(1, 0)), (0, 0));
      expect(t.step(const Offset(2, 0)), (1, 0));
      expect(t.step(const Offset(3, 0)), (0, 0));
      expect(t.step(const Offset(4, 0)), (0, 0));
      expect(t.step(const Offset(8, 0)), (1, 0));
      expect(t.step(const Offset(40, 0)), (8, 0));
      expect((t.sentDx, t.sentDy), (10, 0));
    });

    test('reversing walks the draft back along the same geared totals', () {
      final t = TotalDragTracker(Offset.zero, divisor: 4.0);
      t.step(const Offset(40, 0));
      expect(t.step(const Offset(0, 0)), (-10, 0));
      expect((t.sentDx, t.sentDy), (0, 0));
    });

    test('gearing and axis-lock compose (scaling is linear, so the order is immaterial)', () {
      final t = TotalDragTracker(Offset.zero, divisor: 4.0);
      expect(t.step(const Offset(40, 12), axisLock: true), (10, 0));
      expect(t.step(const Offset(40, 100), axisLock: true), (-10, 25));
    });

    test('a sub-pixel origin is honored (no floor bias)', () {
      final t = TotalDragTracker(const Offset(0.75, 0.25), divisor: 2.0);
      expect(t.step(const Offset(1.75, 0.25)), (1, 0)); // exactly 0.5 canvas px → rounds up
      expect(t.step(const Offset(2.65, 0.25)), (0, 0)); // 0.95 → still 1
      expect(t.step(const Offset(3.8, 0.25)), (1, 0)); // 1.525 → 2
    });

    test('a divisor of 1 reproduces the ungeared tracker exactly', () {
      final a = TotalDragTracker(const Offset(3, 4));
      final b = TotalDragTracker(const Offset(3, 4), divisor: 1.0);
      for (final p in const [Offset(5, 4), Offset(5, 9), Offset(-2, 1), Offset(3, 4)]) {
        expect(b.step(p), a.step(p), reason: '$p');
      }
    });
  });
}
