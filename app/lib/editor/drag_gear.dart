// Geared draft drags (ADR 0020): the pure math behind the Move / Move-selection / Paste drags.
//
// Those three drags are incremental — the engine takes integer deltas (`MoveDraftMove`,
// `MoveSelection`, `PasteMove`) and never sees a pointer position — so gearing is an INPUT-SPACE
// transform applied here, before any DSL traffic. The Journal records the same deltas whether
// Slow was on or off; replays are faithful by construction and "Slow" is never a verb (the
// FZ-4 doctrine: record content, never input-space proxies). Top-level and pure for testability
// (the levels_math.dart / keyboard/constrain.dart precedent): the drag pathways live inside
// _EditorPageState, but the rows are pinned in drag_gear_test.dart.
import 'dart:ui';

import 'keyboard/constrain.dart' show axisLockTotal;

/// Finger travel per draft travel while Slow is ON and the view is coarser than the cap.
/// Lower than the row-1 sliders' 6× (`_kSliderGearRatio`): a canvas drag covers far more
/// distance than a slider thumb, and long moves must stay reachable in a few swipes.
const double kDraftGearRatio = 4.0;

/// Zoom cap: the effective finger cost of one canvas pixel, in screen px, never exceeds this.
/// Gearing exists for the coarse view (fit zoom on a big canvas, a few screen px per canvas
/// px); zoomed in past the cap a pixel is already a fingertip wide and a fixed 4× would read
/// as broken (128 screen px per pixel at 32 px/px). So the cost per pixel is
/// `min(kDraftGearRatio × scale, max(scale, kDraftGearCapPx))`: full 4× below 8 px/px, a flat
/// 32 screen px per pixel from 8 to 32 px/px, and plain 1:1 beyond.
const double kDraftGearCapPx = 32.0;

/// The divisor applied to finger travel (in canvas px) for a Slow drag at [scale] screen px
/// per canvas px. 1.0 means "not geared" — callers take the ordinary floored path then.
double draftGearDivisor(double scale) {
  if (!(scale > 0)) return 1.0; // degenerate / NaN view: never gear
  return (kDraftGearCapPx / scale).clamp(1.0, kDraftGearRatio);
}

/// Corrective-delta tracker for one incremental drag.
///
/// The engine accumulates the deltas it is sent, so the tracker keeps the drag's ORIGIN and
/// the integer total already sent, and every [step] returns the delta that brings the engine's
/// position to the intended total: `round((p − origin) / divisor)`, axis-locked first when
/// asked. The fractional remainder therefore carries across events (four 1-px finger moves at
/// 4× add up to exactly one draft pixel), a held Shift landing mid-drag can't drift off-axis,
/// and a divisor of 1 reproduces the historical 1:1 behavior exactly.
class TotalDragTracker {
  TotalDragTracker(this.origin, {this.divisor = 1.0}) : assert(divisor >= 1.0);

  /// Drag origin in canvas coordinates (floored for 1:1 drags, sub-pixel when geared — a
  /// floored origin under a raw current position would bias the geared total by up to 1 px).
  final Offset origin;

  /// Finger canvas-px per draft canvas-px; 1.0 = ungeared.
  final double divisor;

  int sentDx = 0, sentDy = 0;

  /// Whether this drag is geared (needs sub-pixel canvas positions from the caller).
  bool get geared => divisor > 1.0;

  /// The corrective (dx, dy) to send so the accumulated total matches the finger at [p]
  /// (canvas coordinates, same flooring as [origin]). Returns (0, 0) when nothing changed.
  (int, int) step(Offset p, {bool axisLock = false}) {
    var total = (p - origin) / divisor;
    if (axisLock) total = axisLockTotal(total);
    final dx = total.dx.round() - sentDx;
    final dy = total.dy.round() - sentDy;
    sentDx += dx;
    sentDy += dy;
    return (dx, dy);
  }
}
