// Pure math for the Levels tool's three-thumb slider (low input / gamma / high input).
//
// Kept as top-level functions so they unit-test without the engine or any widget pumping
// (the toolGridShape / selectShapeEngineTool precedent). The engine receives only integers
// (SetLevels(low, gamma_thousandths, high)), so the Dart-side floating point here is purely
// presentational and platform variance in dart:math cannot fork engine goldens.
import 'dart:math';

/// Gamma bounds in engine thousandths: γ ∈ [0.1, 10], identity 1000.
const int kLevelsGammaMinTh = 100;
const int kLevelsGammaMaxTh = 10000;

/// GIMP's mid-thumb coupling: the gamma thumb sits at fraction `f` of the low→high span, and
/// the input value under it maps to mid-gray, so γ = ln(f) / ln(0.5) — f = 0.5 centers (γ = 1),
/// dragging toward low (smaller f) raises γ and brightens midtones.
double levelsGammaFromMid(double f) {
  if (f <= 0) return 10.0;
  if (f >= 1) return 0.1;
  return (log(f) / log(0.5)).clamp(0.1, 10.0);
}

/// Inverse of [levelsGammaFromMid]: the span fraction where the gamma thumb sits.
double levelsMidFromGamma(double gamma) => pow(0.5, gamma.clamp(0.1, 10.0)).toDouble();

/// The engine-wire gamma (thousandths) for a mid-thumb span fraction.
int levelsGammaThFromMid(double f) =>
    (levelsGammaFromMid(f) * 1000).round().clamp(kLevelsGammaMinTh, kLevelsGammaMaxTh);

/// "1.00"-style label for a thousandths gamma.
String levelsGammaLabel(int gammaTh) => (gammaTh / 1000).toStringAsFixed(2);

/// Track-x for a 0..255 level value on a track [trackWidth] px wide (0 at the left edge).
double levelsThumbX(int value, double trackWidth) => value / 255.0 * trackWidth;

/// The 0..255 level value at track-x [x] (clamped).
int levelsValueFromX(double x, double trackWidth) =>
    (x / trackWidth * 255).round().clamp(0, 255);

/// Mutual clamping: the low thumb stays in [0, high-1], the high thumb in [low+1, 255].
int levelsClampLow(int low, int high) => low.clamp(0, high - 1);
int levelsClampHigh(int high, int low) => high.clamp(low + 1, 255);

/// Which thumb a pan starting at track-x [x] grabs: 0 = low, 1 = mid (gamma), 2 = high.
/// Outside the low..high span the outer thumb always wins; inside it the nearest wins, the
/// mid thumb taking exact ties (it sits between the other two).
int levelsNearestThumb(double x, double xLow, double xMid, double xHigh) {
  if (x < xLow) return 0;
  if (x > xHigh) return 2;
  final dl = (x - xLow).abs(), dm = (x - xMid).abs(), dh = (x - xHigh).abs();
  if (dm <= dl && dm <= dh) return 1;
  return dl <= dh ? 0 : 2;
}
