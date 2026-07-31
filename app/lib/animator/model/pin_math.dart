// Pin math — the Dart inverse/forward of the engine's compose_pin (crates/scene/src/
// eval.rs): a pinned child's x/y live in PARENT-PROP-top-left space, rotation composes
// CLOCKWISE, exactly one parent flip conjugates the child's rotation, scales multiply,
// flips XOR, and the parent's pivot anchors the frame. Pure and engine-free; used to keep
// an Actor's world pose unchanged across pin/unpin. The engine quantizes translation to
// Q8 (1/256 px), finer than the integer rounding here, so a pin round-trip costs at most
// half a pixel.
library;

import 'dart:math' as math;

import 'scene_state.dart';

/// The transform slice pin composition acts on (pivot excluded — a child keeps its own).
class PinXf {
  final int x, y, rotMdeg, scaleMilli;
  final bool flipH, flipV;
  const PinXf({
    required this.x,
    required this.y,
    required this.rotMdeg,
    required this.scaleMilli,
    required this.flipH,
    required this.flipV,
  });
}

const int _kRotMax = 7200000; // ±20 turns, the engine's clamp
const int _kScaleMin = 100, _kScaleMax = 8000;

/// (cos, sin) of a clockwise rotation in millidegrees — integer-exact at 90° multiples,
/// mirroring the engine's `rot_cos_sin` so quarter-turn parents place children exactly.
(double, double) _cosSin(int rotMdeg) {
  final k = ((rotMdeg % 360000) + 360000) % 360000;
  switch (k) {
    case 0:
      return (1, 0);
    case 90000:
      return (0, 1);
    case 180000:
      return (-1, 0);
    case 270000:
      return (0, -1);
  }
  final rad = rotMdeg * math.pi / 180000.0;
  return (math.cos(rad), math.sin(rad));
}

/// Where a child with parent-local transform [local] lands in the world, given the
/// parent's evaluated pose — the engine's compose_pin, forward. Used on unpin.
PinXf worldForLocal({required PoseState parent, required PoseState local}) {
  final (c, n) = _cosSin(parent.rotMdeg);
  final s = parent.scaleMilli / 1000.0;
  final sx = parent.flipH ? -1.0 : 1.0;
  final sy = parent.flipV ? -1.0 : 1.0;
  final sp = (parent.flipH != parent.flipV) ? -1 : 1;
  final lx = (local.x - parent.pivotXMilli / 1000.0) * sx * s;
  final ly = (local.y - parent.pivotYMilli / 1000.0) * sy * s;
  return PinXf(
    x: (parent.x + c * lx - n * ly).round(),
    y: (parent.y + n * lx + c * ly).round(),
    rotMdeg: (parent.rotMdeg + sp * local.rotMdeg).clamp(-_kRotMax, _kRotMax),
    scaleMilli: ((parent.scaleMilli * local.scaleMilli) / 1000)
        .round()
        .clamp(_kScaleMin, _kScaleMax),
    flipH: parent.flipH != local.flipH,
    flipV: parent.flipV != local.flipV,
  );
}

/// The parent-local transform that puts a child at world pose [world] — compose_pin
/// inverted at one instant. Used on pin so the actor stays put on screen.
PinXf localForWorld({required PoseState parent, required PoseState world}) {
  final (c, n) = _cosSin(parent.rotMdeg);
  final s = parent.scaleMilli / 1000.0;
  final sx = parent.flipH ? -1.0 : 1.0;
  final sy = parent.flipV ? -1.0 : 1.0;
  final sp = (parent.flipH != parent.flipV) ? -1 : 1;
  final dx = (world.x - parent.x).toDouble();
  final dy = (world.y - parent.y).toDouble();
  final lx = c * dx + n * dy; // inverse of the CW rotation
  final ly = -n * dx + c * dy;
  return PinXf(
    x: (lx / (sx * s) + parent.pivotXMilli / 1000.0).round(),
    y: (ly / (sy * s) + parent.pivotYMilli / 1000.0).round(),
    rotMdeg: (sp * (world.rotMdeg - parent.rotMdeg)).clamp(-_kRotMax, _kRotMax),
    scaleMilli: ((world.scaleMilli * 1000) / parent.scaleMilli)
        .round()
        .clamp(_kScaleMin, _kScaleMax),
    flipH: world.flipH != parent.flipH,
    flipV: world.flipV != parent.flipV,
  );
}
