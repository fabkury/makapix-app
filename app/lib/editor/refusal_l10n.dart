// What the user reads when the engine refuses a change (ADR 0031: a refused verb changes
// nothing and says why). The engine says why in English ("RemoveFrames: cannot delete every
// frame"), and stays that way: its state JSON is part of its tests, and it knows nothing about
// languages. The shell recognizes each of its sentences here and shows the translated message;
// a sentence it does not recognize shows as is in English and as the generic message elsewhere.
//
// The patterns mirror the format strings in crates/engine/src/session.rs, session/frames.rs,
// and session/layers.rs. test/refusal_l10n_test.dart pins them with the engine's exact
// sentences; change both together.
// l10n-ignore-file: engine sentences matched, never shown
import 'package:makapix_club/l10n/l10n.dart';

typedef _Rule = (RegExp, String Function(AppLocalizations l, RegExpMatch m));

final List<_Rule> _rules = [
  (RegExp(r'^\w+: frame (\d+) is out of range \(the animation has (\d+) frames\)$'),
      (l, m) => l.framesErrBeyond(int.parse(m[1]!), int.parse(m[2]!))),
  (RegExp(r'^\w+: \d+ \+ \d+ frames would exceed the (\d+)-frame cap$'),
      (l, m) => l.refuseFrameCap(int.parse(m[1]!))),
  (RegExp(r'^RemoveFrames: cannot delete every frame$'), (l, m) => l.refuseDeleteAllFrames),
  (RegExp(r'^CopyLayerToFrames: frame \d+ already has (\d+) layers$'),
      (l, m) => l.framesAtLayerCap(int.parse(m[1]!))),
  (RegExp(r'^CopyLayersToFrames: frame \d+ would exceed the (\d+)-layer cap \(\d+ \+ \d+ layers\)$'),
      (l, m) => l.framesAtLayerCap(int.parse(m[1]!))),
  (RegExp(r'^\w+: layer (\d+) is out of range \(the frame has (\d+) layers\)$'),
      (l, m) => l.layersErrBeyond(int.parse(m[1]!), int.parse(m[2]!))),
  (RegExp(r'^\w+: \d+ \+ \d+ layers would exceed the (\d+)-layer cap$'),
      (l, m) => l.layersAtCap(int.parse(m[1]!))),
  (RegExp(r'^\w+: this frame already has (\d+) layers$'), (l, m) => l.layersAtCap(int.parse(m[1]!))),
  (RegExp(r'^\w+: (\d+) selected layers? (?:is|are) locked — unlock (?:it|them) first$'),
      (l, m) => l.layersLockedFirst(int.parse(m[1]!))),
  (RegExp(r'^MergeLayers: the selection has a gap'), (l, m) => l.layersMergeGap),
  (RegExp(r'exceeds the document memory budget$'), (l, m) => l.memBlocked),
];

/// The message to show for the engine's refusal sentence [raw].
String shownRefusal(AppLocalizations l, String raw) {
  for (final (re, text) in _rules) {
    final m = re.firstMatch(raw);
    if (m != null) return text(l, m);
  }
  return l.localeName == 'en' ? raw : l.engineRefusedFallback;
}
