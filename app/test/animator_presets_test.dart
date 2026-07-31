// Motion-preset DSL builders (lib/animator/model/presets.dart): key placement, fps-aware
// duration, end-of-scene clamping, the too-short refusal, and the SetKeyTween-only rule.
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/animator/model/presets.dart';
import 'package:makapix_club/animator/model/scene_state.dart';

String? build(PresetKind k,
        {int playhead = 0,
        int millifps = 25000,
        int frameCount = 100,
        PoseState pose = const PoseState(x: 40, y: 30, scaleMilli: 1000)}) =>
    buildPreset(k,
        actorId: 7,
        playhead: playhead,
        millifps: millifps,
        frameCount: frameCount,
        pose: pose,
        canvasW: 128,
        canvasH: 128);

void main() {
  test('one second of frames at each rate', () {
    expect(presetFrames(25000), 25);
    expect(presetFrames(12500), 13);
    expect(presetFrames(10000), 10);
    expect(presetFrames(50000), 50);
  });

  test('bounce dips by canvas-scaled amplitude and returns', () {
    final dsl = build(PresetKind.bounce)!;
    expect(dsl, startsWith('BeginGesture()'));
    expect(dsl, endsWith('EndGesture()'));
    expect(dsl, contains('SetKeyTween(7, y, 0, 30, easein)'));
    expect(dsl, contains('SetKeyTween(7, y, 12, 46, easeout)'),
        reason: '128/8 = 16 px dip at the midpoint');
    expect(dsl, contains('SetKeyTween(7, y, 25, 30, linear)'));
  });

  test('slide-in arrives from off-left, spin adds a full turn', () {
    expect(build(PresetKind.slideIn), contains('SetKeyTween(7, x, 0, -24, easeout)'));
    expect(build(PresetKind.slideIn), contains('SetKeyTween(7, x, 25, 40, linear)'));
    final spin = build(PresetKind.spin,
        pose: const PoseState(rotMdeg: 15000))!;
    expect(spin, contains('SetKeyTween(7, rot, 0, 15000, linear)'));
    expect(spin, contains('SetKeyTween(7, rot, 25, 375000, linear)'));
  });

  test('shake jitters ±3 and settles; pop overshoots then settles', () {
    final shake = build(PresetKind.shake)!;
    expect(shake, contains('SetKeyTween(7, x, 0, 40, linear)'));
    expect(shake, contains(', 43, linear)'));
    expect(shake, contains(', 37, linear)'));
    expect(shake, contains('SetKeyTween(7, x, 25, 40, linear)'));
    final pop = build(PresetKind.pop, pose: const PoseState(scaleMilli: 2000))!;
    expect(pop, contains('SetKeyTween(7, scale, 0, 300, easeout)'));
    expect(pop, contains('SetKeyTween(7, scale, 17, 2300, easein)'),
        reason: '115% overshoot at 70% of the duration');
    expect(pop, contains('SetKeyTween(7, scale, 25, 2000, easeinout)'));
  });

  test('clamps to the scene end and refuses when too short', () {
    final clamped = build(PresetKind.spin, playhead: 90)!;
    expect(clamped, contains('SetKeyTween(7, rot, 99, 360000, linear)'),
        reason: 'duration shrinks so the last key lands on the final frame');
    expect(build(PresetKind.bounce, playhead: 96), isNull,
        reason: 'fewer than 4 remaining frames');
    expect(build(PresetKind.bounce, playhead: 95), isNotNull);
  });

  test('only SetKeyTween is emitted, never SetKey or hold', () {
    for (final k in PresetKind.values) {
      final dsl = build(k)!;
      expect(dsl, isNot(contains('SetKey(')));
      expect(dsl, isNot(contains('hold')));
    }
  });
}
