// Shift-constrain geometry rows (keyboard/constrain.dart): the pure math the canvas drag
// pathways apply under a held Shift. The drag handlers live inside _EditorPageState (engine-
// bound), so the math is pinned here — the levels_math_test.dart precedent.
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/editor/keyboard/constrain.dart';

void main() {
  const o = Offset.zero;

  group('snapToOctant', () {
    test('near-horizontal flattens to the x axis', () {
      final s = snapToOctant(o, const Offset(40, 3));
      expect(s.dy, closeTo(0, 1e-9));
      expect(s.dx, closeTo(40, 3.5)); // projection keeps the reach along the axis
    });

    test('near-vertical flattens to the y axis', () {
      final s = snapToOctant(o, const Offset(-2, -30));
      expect(s.dx, closeTo(0, 1e-9));
      expect(s.dy, closeTo(-30, 2.5));
    });

    test('near-diagonal equalizes the components', () {
      final s = snapToOctant(o, const Offset(10, 12));
      expect(s.dx, closeTo(s.dy, 1e-9));
      expect(s.dx, closeTo(11, 1e-9)); // projection onto the 45° line: (10+12)/2
    });

    test('every octant is reachable and sign-correct', () {
      for (final (v, expected) in [
        (const Offset(10, 1), const Offset(10, 0)),
        (const Offset(8, 7), const Offset(7.5, 7.5)),
        (const Offset(1, 10), const Offset(0, 10)),
        (const Offset(-7, 8), const Offset(-7.5, 7.5)),
        (const Offset(-10, 1), const Offset(-10, 0)),
        (const Offset(-8, -7), const Offset(-7.5, -7.5)),
        (const Offset(-1, -10), const Offset(0, -10)),
        (const Offset(7, -8), const Offset(7.5, -7.5)),
      ]) {
        final s = snapToOctant(o, v);
        expect(s.dx, closeTo(expected.dx, 1e-9), reason: '$v');
        expect(s.dy, closeTo(expected.dy, 1e-9), reason: '$v');
      }
    });

    test('a non-zero anchor translates, never skews', () {
      const anchor = Offset(5, 9);
      final s = snapToOctant(anchor, anchor + const Offset(20, 1));
      expect(s.dy, closeTo(9, 1e-9));
    });

    test('the zero vector is left untouched', () {
      expect(snapToOctant(const Offset(3, 4), const Offset(3, 4)), const Offset(3, 4));
    });
  });

  group('axisLockTotal', () {
    test('dominant x wins', () {
      expect(axisLockTotal(const Offset(9, -4)), const Offset(9, 0));
    });
    test('dominant y wins', () {
      expect(axisLockTotal(const Offset(3, -14)), const Offset(0, -14));
    });
    test('ties go horizontal', () {
      expect(axisLockTotal(const Offset(5, 5)), const Offset(5, 0));
    });
    test('zero stays zero', () {
      expect(axisLockTotal(Offset.zero), Offset.zero);
    });
  });
}
