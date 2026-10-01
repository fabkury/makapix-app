// The glossary's distinctions, checked (docs/i18n/GLOSSARY.md). Two kinds:
// - pairs that mean different things and must read differently in every language (Flip vs.
//   Invert, Redo vs. Repeat, Open vs. Import, Discard vs. Delete, …), including pairs the
//   English itself spells the same way;
// - pairs that mean the same thing and must read the same.
// Found necessary by the independent review (L3): several of these had collapsed.
import 'package:flutter_test/flutter_test.dart';

import 'l10n_test_support.dart';

/// Keys whose texts must differ, with why. [enToo] = English must differ as well.
const _mustDiffer = <(String, String, String, bool)>[
  ('toolFlip', 'toolInvert', 'Flip mirrors the geometry, Invert the colors', true),
  ('toolRedo', 'toolRepeat', 'Redo replays an undone step; Repeat applies the last action again', true),
  ('fileOpen', 'ioImportImage', 'Open and Import are different gestures (CONTEXT.md)', true),
  ('commonDiscard', 'commonDelete', 'Discard drops unsaved work; Delete removes a saved thing', true),
  ('discardDrawingTitle', 'drawingDeleteTitle', 'the two dialogs must be told apart', true),
  ('optFlipSelection', 'selectInvert', 'mirroring the selected pixels vs. selecting everything else', true),
  ('optInvertSelection', 'selectInvert', 'inverting the colors inside the selection vs. selecting everything else', false),
  ('placeDroppedStorage', 'placeDroppedCanvas', 'two causes of loss on the place page', true),
  ('cropCanvasTitle', 'importCrop', 'cropping the canvas vs. cropping an import', true),
  ('toolMove', 'barShift', 'the Move tool vs. moving items one position', true),
];

/// Keys whose texts must be the same: one meaning, one wording.
const _mustMatch = <(String, String)>[
  ('engineRefused', 'engineRefusedFallback'),
];

void main() {
  for (final locale in allLocales) {
    final lang = locale.languageCode;
    final arb = readArb(lang);
    test('glossary distinctions hold in $lang', () {
      final problems = <String>[];
      for (final (a, b, why, enToo) in _mustDiffer) {
        if (lang == 'en' && !enToo) continue;
        if (arb[a] == arb[b]) problems.add('$a and $b both read "${arb[a]}" ($why)');
      }
      for (final (a, b) in _mustMatch) {
        if (arb[a] != arb[b]) problems.add('$a "${arb[a]}" differs from $b "${arb[b]}"');
      }
      expect(problems, isEmpty);
    });
  }
}
