// Scene-domain constants shared by the Animator UI — pure Dart, engine-free (unit-tested
// without the native binary). Mirrors crates/scene/src/model.rs; the engine is the enforcer,
// these are the UI's advisory copies.
library;

/// The curated GIF-safe frame-rate list (ADR-0001), in milli-fps. Every rate is an exact
/// whole number of GIF centiseconds, so preview timing == export timing by construction.
const List<int> kSceneFpsMilli = [10000, 12500, 20000, 25000, 50000];

/// Exact centiseconds per frame for each entry of [kSceneFpsMilli].
const List<int> kSceneFrameCs = [10, 8, 5, 4, 2];

String fpsLabel(int millifps) {
  final whole = millifps ~/ 1000;
  final frac = millifps % 1000;
  return frac == 0 ? '$whole fps' : '$whole.${frac ~/ 100} fps';
}

/// Microseconds per frame at `millifps` (exact for every listed rate).
int frameUs(int millifps) => 1000000000 ~/ millifps;

/// Scene canvas limits — Editor parity (1..256 per side).
const int kSceneMinDim = 1;
const int kSceneMaxDim = 256;

/// Props may exceed the Scene canvas (pans, scrolling backgrounds) up to this per side.
const int kPropMaxDim = 1024;

const int kMaxSceneFrames = 1024;
const int kMaxActors = 64;

/// Default new-scene duration: two seconds of frames at the given rate.
int defaultFrameCount(int millifps) =>
    (2 * millifps ~/ 1000).clamp(1, kMaxSceneFrames);

/// `'#RRGGBBAA'` (uppercase, always 8 digits) for a color — the engine's exact
/// `state_json` background format, valid as a `SetBackground` argument.
String hexOfColor(int argb) {
  final a = (argb >> 24) & 0xFF, r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF, b = argb & 0xFF;
  String h(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
  return '#${h(r)}${h(g)}${h(b)}${h(a)}';
}

/// Parse `'#RRGGBB[AA]'` (case-insensitive, `#` optional) into 0xAARRGGBB;
/// null when malformed. Mirrors the engine's `Rgba8::from_hex` leniency.
int? colorOfHex(String s) {
  var t = s.trim();
  if (t.startsWith('#')) t = t.substring(1);
  if (t.length != 6 && t.length != 8) return null;
  final v = int.tryParse(t, radix: 16);
  if (v == null) return null;
  if (t.length == 6) return 0xFF000000 | v;
  final rgb = v >> 8, a = v & 0xFF;
  return (a << 24) | rgb;
}

/// The five easing names, in the chip's cycling order (engine tween tokens).
const List<String> kEasingCycle = ['linear', 'ease', 'easein', 'easeout', 'hold'];

/// UI label for an engine tween token.
String easingLabel(String tween) => switch (tween) {
      'linear' => 'Linear',
      'easeinout' || 'ease' => 'Ease',
      'easein' => 'Ease in',
      'easeout' => 'Ease out',
      'hold' => 'Hold',
      _ => tween,
    };

/// The DSL token sent for a chip choice ('ease' is UI shorthand for easeinout).
String easingToken(String chip) => chip == 'ease' ? 'easeinout' : chip;

/// The chip value for an engine token.
String chipForToken(String tween) => tween == 'easeinout' ? 'ease' : tween;
