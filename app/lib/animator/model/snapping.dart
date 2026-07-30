// Stage snapping — how a thumb achieves pointer precision (design 03 §6). Pure math,
// engine-free, unit-tested. The pixel grid is the floor (positions are integers by the
// model); these helpers add the OPTIONAL magnets: canvas center/edges, 15° rotation stops,
// and the 1.0 scale detent — each reporting engagement so the caller can haptic-tick.
library;

/// A snap outcome: the (possibly adjusted) value plus whether a magnet engaged.
class Snap<T> {
  final T value;
  final bool snapped;
  const Snap(this.value, this.snapped);
}

/// Snap a dragged Actor position to canvas center/edge alignment when within [tolPx].
/// Magnets per axis: 0 (left/top edge of the actor bounds at the canvas edge is the caller's
/// concern — this snaps the POSITION value), canvas center, canvas extent.
Snap<int> snapPosition(int value, int canvasExtent, {int tolPx = 3}) {
  final magnets = [0, canvasExtent ~/ 2, canvasExtent];
  for (final m in magnets) {
    if ((value - m).abs() <= tolPx) return Snap(m, true);
  }
  return Snap(value, false);
}

/// Snap a rotation (millidegrees) to the nearest 15° stop when within [tolMdeg]
/// (default 4°). Values are normalized into [-180°, 180°) for display elsewhere; the raw
/// track value keeps turns, so snapping works on the raw value's nearest stop.
Snap<int> snapRotation(int mdeg, {int tolMdeg = 4000}) {
  const step = 15000;
  final nearest = ((mdeg + (mdeg >= 0 ? step ~/ 2 : -step ~/ 2)) ~/ step) * step;
  if ((mdeg - nearest).abs() <= tolMdeg) return Snap(nearest, mdeg != nearest);
  return Snap(mdeg, false);
}

/// Snap a scale (thousandths) to the 1.0 detent within [tolMilli] (default 5%).
Snap<int> snapScale(int milli, {int tolMilli = 50}) {
  if ((milli - 1000).abs() <= tolMilli) return Snap(1000, milli != 1000);
  return Snap(milli, false);
}

/// Normalize millidegrees into [-180000, 180000) for readouts.
int normalizeMdeg(int mdeg) {
  var m = mdeg % 360000;
  if (m >= 180000) m -= 360000;
  if (m < -180000) m += 360000;
  return m;
}
