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

  test('hex helpers round-trip the engine background format', () {
    expect(hexOfColor(0xFF102030), '#102030FF');
    expect(hexOfColor(0x80FF0000), '#FF000080');
    expect(colorOfHex('#102030FF'), 0xFF102030);
    expect(colorOfHex('102030'), 0xFF102030, reason: '6 digits imply opaque');
    expect(colorOfHex('#ff000080'), 0x80FF0000, reason: 'case-insensitive');
    expect(colorOfHex('nope'), isNull);
    expect(colorOfHex('#12345'), isNull);
    expect(hexOfColor(colorOfHex('#00000000')!), '#00000000',
        reason: 'the transparent default survives the round-trip');
  });

  test('easing chip cycle round-trips through engine tokens', () {
    for (final chip in kEasingCycle) {
      expect(chipForToken(easingToken(chip)), chip);
    }
    expect(easingToken('ease'), 'easeinout');
    expect(easingLabel('easeinout'), 'Ease');
  });
}
