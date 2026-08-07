// Pure-math tests for the Levels three-thumb slider, plus the tool-catalog contract.
// No engine binary, no widget pumping.
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/levels_math.dart';
import 'package:makapix_club/editor/tools.dart';

void main() {
  group('gamma <-> mid-thumb coupling (the GIMP contract)', () {
    test('gamma 1 sits at the span center', () {
      expect(levelsGammaFromMid(0.5), closeTo(1.0, 1e-12));
      expect(levelsMidFromGamma(1.0), closeTo(0.5, 1e-12));
      expect(levelsGammaThFromMid(0.5), 1000);
    });

    test('dragging toward low (smaller f) brightens: gamma rises', () {
      expect(levelsGammaFromMid(0.25), closeTo(2.0, 1e-12));
      expect(levelsGammaFromMid(0.4), greaterThan(1.0));
      expect(levelsGammaFromMid(0.6), lessThan(1.0));
    });

    test('roundtrips across the whole clamped range', () {
      for (final gamma in [0.1, 0.3, 0.5, 1.0, 2.2, 5.0, 10.0]) {
        expect(levelsGammaFromMid(levelsMidFromGamma(gamma)), closeTo(gamma, 1e-9));
      }
    });

    test('clamps to [0.1, 10] at the extremes', () {
      expect(levelsGammaFromMid(0.0), 10.0);
      expect(levelsGammaFromMid(1.0), 0.1);
      expect(levelsGammaThFromMid(0.0), kLevelsGammaMaxTh);
      expect(levelsGammaThFromMid(1.0), kLevelsGammaMinTh);
    });

    test('label renders thousandths as two decimals', () {
      expect(levelsGammaLabel(1000), '1.00');
      expect(levelsGammaLabel(2200), '2.20');
      expect(levelsGammaLabel(100), '0.10');
    });
  });

  group('thumb <-> value mapping', () {
    test('value -> x -> value roundtrips for every level at a real track width', () {
      for (var v = 0; v <= 255; v++) {
        expect(levelsValueFromX(levelsThumbX(v, 200), 200), v);
      }
    });

    test('x clamps into 0..255', () {
      expect(levelsValueFromX(-50, 200), 0);
      expect(levelsValueFromX(999, 200), 255);
    });

    test('mutual clamping keeps low < high', () {
      expect(levelsClampLow(300, 255), 254);
      expect(levelsClampLow(-5, 255), 0);
      expect(levelsClampLow(200, 100), 99);
      expect(levelsClampHigh(0, 10), 11);
      expect(levelsClampHigh(300, 0), 255);
    });
  });

  group('thumb grab-zone hit test', () {
    test('inside a +-16 band the nearest thumb wins, mid on ties', () {
      expect(levelsHitThumb(50, 40, 100, 180, 16), 0);
      expect(levelsHitThumb(95, 40, 100, 180, 16), 1);
      expect(levelsHitThumb(170, 40, 100, 180, 16), 2);
      expect(levelsHitThumb(70, 40, 100, 180, 30), 1); // exact tie low/mid -> mid
    });

    test('outside every band the gradient is inert (-1)', () {
      expect(levelsHitThumb(70, 40, 100, 180, 16), -1); // mid-gradient gap
      expect(levelsHitThumb(140, 40, 100, 180, 16), -1);
      expect(levelsHitThumb(0, 40, 100, 180, 16), -1); // outside the span too
      expect(levelsHitThumb(220, 40, 100, 180, 16), -1);
    });

    test('overlapping bands still resolve to the nearest thumb', () {
      expect(levelsHitThumb(43, 40, 50, 180, 16), 0);
      expect(levelsHitThumb(48, 40, 50, 180, 16), 1);
    });
  });

  group('text entry pushes the other input point', () {
    test('low entered past high pushes high up', () {
      expect(levelsEnterLow(200, 150), (200, 201));
      expect(levelsEnterLow(100, 150), (100, 150)); // no conflict, no push
      expect(levelsEnterLow(300, 150), (254, 255)); // clamped to 254, still pushes
      expect(levelsEnterLow(-5, 150), (0, 150));
    });

    test('high entered under low pushes low down', () {
      expect(levelsEnterHigh(120, 180), (119, 120));
      expect(levelsEnterHigh(200, 180), (180, 200)); // no conflict, no push
      expect(levelsEnterHigh(0, 180), (0, 1)); // clamped to 1, low pushed to 0
      expect(levelsEnterHigh(400, 180), (180, 255));
    });
  });

  group('tool catalog', () {
    test('Levels is a real catalog tool with a help tip', () {
      expect(tools.any((t) => t.dsl == 'Levels'), isTrue);
      expect(toolTips.containsKey('Levels'), isTrue);
    });
  });
}
