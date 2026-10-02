// Every refusal sentence the engine can produce is recognized and shown in the user's language
// (lib/editor/refusal_l10n.dart). The sentences are the engine's exact format strings
// (crates/engine/src/session.rs, session/frames.rs, session/layers.rs) with sample numbers.
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/refusal_l10n.dart';

import 'l10n/l10n_test_support.dart';

const _engineSentences = [
  'RemoveFrames: frame 9 is out of range (the animation has 5 frames)',
  'DuplicateFrames: 1020 + 8 frames would exceed the 1024-frame cap',
  'RemoveFrames: cannot delete every frame',
  'CopyLayerToFrames: frame 3 already has 128 layers',
  'CopyLayersToFrames: frame 2 would exceed the 128-layer cap (127 + 2 layers)',
  'ShiftLayers: layer 9 is out of range (the frame has 4 layers)',
  'DuplicateLayers: 127 + 2 layers would exceed the 128-layer cap',
  'AddLayer: this frame already has 128 layers',
  'MergeLayers: 1 selected layer is locked — unlock it first',
  'FlipLayersH: 3 selected layers are locked — unlock them first',
  'MergeLayers: the selection has a gap — Merge needs one contiguous run',
  'edit exceeds the document memory budget',
  'frame change exceeds the document memory budget',
  "'DuplicateFrames' exceeds the document memory budget",
];

void main() {
  test('every engine refusal has its own translated message', () {
    for (final locale in allLocales) {
      final l = l10nFor(locale);
      for (final s in _engineSentences) {
        final shown = shownRefusal(l, s);
        expect(shown, isNot(l.engineRefusedFallback), reason: '$locale: not recognized: $s');
        expect(shown, isNot(s), reason: '$locale: shown untranslated: $s');
      }
    }
  });

  test('the numbers come through', () {
    final en = l10nFor(const Locale('en'));
    expect(shownRefusal(en, _engineSentences[0]), 'Frame 9 is beyond the last frame (5)');
    expect(shownRefusal(en, _engineSentences[9]), '3 selected layers are locked. Unlock them first.');
  });

  test('an unknown sentence: as is in English, the generic message elsewhere', () {
    const unknown = 'SomeVerb: something new';
    expect(shownRefusal(l10nFor(const Locale('en')), unknown), unknown);
    final de = l10nFor(const Locale('de'));
    expect(shownRefusal(de, unknown), de.engineRefusedFallback);
  });
}
