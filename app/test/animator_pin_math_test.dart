// Pin math (lib/animator/model/pin_math.dart) against the ENGINE's worked examples
// (crates/scene/tests/compose.rs + eval.rs): parent-prop-top-left space, CW rotation,
// flip conjugation, and inverse∘forward round-trips.
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/animator/model/pin_math.dart';
import 'package:makapix_club/animator/model/scene_state.dart';

PoseState pose({
  int x = 0,
  int y = 0,
  int rot = 0,
  int scale = 1000,
  bool fh = false,
  bool fv = false,
  int pvx = 0,
  int pvy = 0,
}) =>
    PoseState(
        x: x,
        y: y,
        rotMdeg: rot,
        scaleMilli: scale,
        flipH: fh,
        flipV: fv,
        pivotXMilli: pvx,
        pivotYMilli: pvy);

void main() {
  // The engine's worked example: parent 2×2 at (16,16), pivot (1,1) px. A child at
  // parent-local (3,1) lands with its pivot on scene (18,16); rotating the parent a
  // quarter turn carries it to (16,18).
  final parent = pose(x: 16, y: 16, pvx: 1000, pvy: 1000);

  test("the engine's worked example, forward and inverse", () {
    final w = worldForLocal(parent: parent, local: pose(x: 3, y: 1));
    expect((w.x, w.y), (18, 16));
    final l = localForWorld(parent: parent, world: pose(x: 18, y: 16));
    expect((l.x, l.y), (3, 1));
  });

  test('quarter-turn parents are exact', () {
    final p90 = pose(x: 16, y: 16, rot: 90000, pvx: 1000, pvy: 1000);
    final w = worldForLocal(parent: p90, local: pose(x: 3, y: 1));
    expect((w.x, w.y), (16, 18), reason: 'CW quarter turn, integer-exact');
    final l = localForWorld(parent: p90, world: pose(x: 16, y: 18));
    expect((l.x, l.y), (3, 1));
  });

  test('rotation adds; one parent flip conjugates it', () {
    expect(worldForLocal(parent: pose(rot: 30000), local: pose(rot: 15000)).rotMdeg, 45000);
    expect(
        worldForLocal(parent: pose(rot: 30000, fh: true), local: pose(rot: 15000)).rotMdeg,
        15000,
        reason: 'flipH negates the child rotation: 30000 − 15000');
    expect(localForWorld(parent: pose(rot: 30000, fh: true), world: pose(rot: 15000)).rotMdeg,
        15000, reason: 'inverse of the conjugated sum');
  });

  test('scales multiply and clamp; flips XOR', () {
    final w = worldForLocal(parent: pose(scale: 2000), local: pose(scale: 1500, fh: true));
    expect(w.scaleMilli, 3000);
    expect(w.flipH, isTrue);
    final l = localForWorld(parent: pose(scale: 2000), world: pose(scale: 3000, fh: true));
    expect(l.scaleMilli, 1500);
    expect(l.flipH, isTrue);
    expect(localForWorld(parent: pose(scale: 8000), world: pose(scale: 100)).scaleMilli, 100,
        reason: 'clamped into 100..8000');
  });

  test('inverse∘forward round-trips within a pixel under arbitrary transforms', () {
    final p = pose(x: 40, y: 60, rot: 37000, scale: 1700, fh: true, pvx: 9000, pvy: 5000);
    const local = (x: 12, y: -7, rot: -52000, scale: 800);
    final w = worldForLocal(
        parent: p, local: pose(x: local.x, y: local.y, rot: local.rot, scale: local.scale));
    final back = localForWorld(
        parent: p,
        world: pose(x: w.x, y: w.y, rot: w.rotMdeg, scale: w.scaleMilli, fh: w.flipH));
    expect((back.x - local.x).abs() <= 1, isTrue, reason: 'x within rounding');
    expect((back.y - local.y).abs() <= 1, isTrue, reason: 'y within rounding');
    expect(back.rotMdeg, local.rot);
    expect((back.scaleMilli - local.scale).abs() <= 2, isTrue);
    expect(back.flipH, isFalse, reason: 'world flip XOR parent flip = the local flip');
  });
}
