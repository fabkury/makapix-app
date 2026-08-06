import 'dart:math' as math;

// Gearing between the reputation slider position and the delta it commits
// (UMD `POST /admin/user/{sqid}/reputation`). Pure Dart, no Flutter imports —
// unit-tested like mod_hashtag_edit.dart.
//
// The website's UMD panel biases its slider with a gamma of 1.5 so travel near
// the center maps to single digits (the common ±1…±20 adjustments) while the
// extremes still reach ±1000. The app keeps the same curve.

/// Server bound on one adjustment (`delta: ge=-1000 le=1000`).
const int kMaxReputationDelta = 1000;

/// Server minimum for the required reason (`min_length=8`).
const int kMinReputationReasonLength = 8;

const double _gamma = 1.5;

/// Slider position `t ∈ [-1, 1]` → signed delta. `t = ±1` maps to ±1000;
/// the gamma bias keeps the center fine-grained.
int deltaFromGear(double t) {
  final c = t.clamp(-1.0, 1.0);
  return (c.sign * (kMaxReputationDelta * math.pow(c.abs(), _gamma))).round();
}

/// Inverse of [deltaFromGear]: the slider position that displays [delta].
double gearFromDelta(int delta) {
  final c = delta.clamp(-kMaxReputationDelta, kMaxReputationDelta);
  return c.sign * math.pow(c.abs() / kMaxReputationDelta, 1 / _gamma).toDouble();
}

/// Whether [delta] + [reason] form a valid adjustment request.
bool reputationAdjustValid(int delta, String reason) =>
    delta != 0 &&
    delta >= -kMaxReputationDelta &&
    delta <= kMaxReputationDelta &&
    reason.trim().length >= kMinReputationReasonLength;
