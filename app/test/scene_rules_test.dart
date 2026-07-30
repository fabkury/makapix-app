// The Scene-domain constants (lib/animator/model/scene_rules.dart) — chiefly the ADR-0001
// invariant: every curated rate is an exact whole number of GIF centiseconds.
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/animator/model/scene_rules.dart';

void main() {
  test('every curated fps maps to exact centiseconds and microseconds', () {
    expect(kSceneFpsMilli.length, kSceneFrameCs.length);
    for (var i = 0; i < kSceneFpsMilli.length; i++) {
      final us = frameUs(kSceneFpsMilli[i]);
      expect(us, kSceneFrameCs[i] * 10000,
          reason: '${fpsLabel(kSceneFpsMilli[i])} must be exact GIF centiseconds');
      expect(1000000000 % kSceneFpsMilli[i], 0,
          reason: 'frame duration divides evenly (no drift)');
    }
  });

  test('labels read naturally', () {
    expect(fpsLabel(12500), '12.5 fps');
    expect(fpsLabel(25000), '25 fps');
  });

  test('default duration is two seconds of frames', () {
    expect(defaultFrameCount(12500), 25);
    expect(defaultFrameCount(50000), 100);
  });

  test('easing chip cycle round-trips through engine tokens', () {
    for (final chip in kEasingCycle) {
      expect(chipForToken(easingToken(chip)), chip);
    }
    expect(easingToken('ease'), 'easeinout');
    expect(easingLabel('easeinout'), 'Ease');
  });
}
