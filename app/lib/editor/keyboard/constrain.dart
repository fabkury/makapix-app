// Shift-constrain geometry (DESIGN.md §2.4): pure functions the canvas drag pathways apply to
// POINTER COORDINATES before they become DSL cursor traffic — the engine and the Journal only
// ever see ordinary coordinates, so replays are faithful by construction. Shift-constrain is
// fixed gesture grammar, not a Binding (CONTEXT.md "Hold binding" avoids it too).
//
// Top-level and pure for testability (the levels_math.dart precedent): the drag pathways live
// inside _EditorPageState, but the math rows are pinned here.
import 'dart:math' as math;
import 'dart:ui';

/// Snap `moving` so the anchor→moving vector lies on the nearest of the eight 45° directions,
/// by projecting the vector onto that direction (the pointer's reach is preserved along the
/// snapped axis). Returns `moving` unchanged for a zero vector. Un-rounded — callers round
/// once at the end, so snapping raw (sub-pixel) input never jitters near the 22.5° boundaries.
Offset snapToOctant(Offset anchor, Offset moving) {
  final v = moving - anchor;
  if (v == Offset.zero) return moving;
  const step = math.pi / 4;
  final snapped = (math.atan2(v.dy, v.dx) / step).round() * step;
  final dir = Offset(math.cos(snapped), math.sin(snapped));
  final len = v.dx * dir.dx + v.dy * dir.dy; // projection onto the snapped direction
  return anchor + dir * len;
}

/// Axis-lock a drag's TOTAL delta (from its origin) to the dominant axis; ties go horizontal.
/// Applied to totals — never to incremental deltas, which would drift off-axis.
Offset axisLockTotal(Offset total) =>
    total.dx.abs() >= total.dy.abs() ? Offset(total.dx, 0) : Offset(0, total.dy);
