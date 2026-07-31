// Motion presets — real, editable keys dropped at the playhead (design 03 §5: the preset
// is scaffolding, not a black box; opening what it made IS the keyframe tutorial). Pure
// DSL builders, engine-free and unit-tested. Each expands to one gesture-bracketed batch,
// so applying a preset is ONE undo step. Always SetKeyTween, never SetKey — an existing
// key at a colliding frame would silently keep its stale tween.
library;

import 'dart:math' as math;

import 'scene_state.dart';

enum PresetKind { bounce, slideIn, spin, shake, pop }

String presetLabel(PresetKind k) => switch (k) {
      PresetKind.bounce => 'Bounce',
      PresetKind.slideIn => 'Slide in',
      PresetKind.spin => 'Spin',
      PresetKind.shake => 'Shake',
      PresetKind.pop => 'Pop',
    };

/// Frames a preset spans at this rate (~1 second), before end-of-scene clamping.
int presetFrames(int millifps) => (millifps / 1000).round();

/// The preset's DSL batch anchored at [playhead], relative to the actor's current
/// [pose]; null when fewer than 4 frames remain before the scene end.
String? buildPreset(
  PresetKind k, {
  required int actorId,
  required int playhead,
  required int millifps,
  required int frameCount,
  required PoseState pose,
  required int canvasW,
  required int canvasH,
}) {
  final last = frameCount - 1;
  var n = presetFrames(millifps);
  if (playhead + n > last) n = last - playhead;
  if (n < 4) return null;
  final f = playhead;
  final parts = <String>['BeginGesture()'];
  void key(String prop, int frame, int v, String tw) =>
      parts.add('SetKeyTween($actorId, $prop, $frame, $v, $tw)');
  switch (k) {
    case PresetKind.bounce:
      // Drop with gravity (easein), rebound decelerating (easeout), settle.
      final amp = math.max(6, canvasH ~/ 8);
      key('y', f, pose.y, 'easein');
      key('y', f + n ~/ 2, pose.y + amp, 'easeout');
      key('y', f + n, pose.y, 'linear');
    case PresetKind.slideIn:
      // Arrive from off-left, decelerating into the current position.
      final off = math.max(32, canvasW ~/ 2);
      key('x', f, pose.x - off, 'easeout');
      key('x', f + n, pose.x, 'linear');
    case PresetKind.spin:
      // One full clockwise turn from the current angle.
      key('rot', f, pose.rotMdeg, 'linear');
      key('rot', f + n, (pose.rotMdeg + 360000).clamp(-7200000, 7200000), 'linear');
    case PresetKind.shake:
      // A quick ±3 px jitter, settling back where it started.
      final step = (n / 8).ceil();
      key('x', f, pose.x, 'linear');
      var frame = f + step;
      var sign = 1;
      while (frame < f + n) {
        key('x', frame, pose.x + 3 * sign, 'linear');
        sign = -sign;
        frame += step;
      }
      key('x', f + n, pose.x, 'linear');
    case PresetKind.pop:
      // Grow from tiny, overshoot, settle at the current scale.
      final over = (pose.scaleMilli * 115 ~/ 100).clamp(100, 8000);
      key('scale', f, 300, 'easeout');
      key('scale', f + (n * 7) ~/ 10, over, 'easein');
      key('scale', f + n, pose.scaleMilli, 'easeinout');
  }
  parts.add('EndGesture()');
  return parts.join('; ');
}
