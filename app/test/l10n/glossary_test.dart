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
  ('toolMoveShort', 'barShift', 'the Move tile vs. moving items one position', true),
  ('profileTabReacted', 'statReactions', 'works this person reacted to vs. reactions they received', true),
];

/// Keys whose texts must be the same: one meaning, one wording.
const _mustMatch = <(String, String)>[
  ('engineRefused', 'engineRefusedFallback'),
];

/// Glossary terms a message must use whenever its English names the thing, by language. The
/// test checks every message whose description says it is about that thing: a "tag" in a
/// hashtag message is still the glossary's hashtag word (GLOSSARY.md).
const _term = <String, Map<String, String>>{
  'hashtag': {
    'es': 'hashtag', 'pt': 'hashtag', 'fr': 'hashtag', 'de': 'hashtag',
    'ru': 'хештег', 'ja': 'ハッシュタグ', 'zh': '话题标签',
  },
};

void main() {
  for (final locale in allLocales.where((l) => l.languageCode != 'en')) {
    final lang = locale.languageCode;
    test('hashtag messages use the glossary word in $lang', () {
      final en = readArb('en');
      final meta = readArbMeta();
      final arb = readArb(lang);
      final word = _term['hashtag']![lang]!;
      final problems = <String>[
        for (final key in en.keys)
          // A message about hashtags whose text names one ("tag" or "hashtag"), unless its
          // only mention is a placeholder such as #{tag}.
          if ('${meta[key]?['description'] ?? ''}'.toLowerCase().contains('hashtag') &&
              RegExp(r'\b(hash)?tags?\b', caseSensitive: false).hasMatch(en[key]!.replaceAll(RegExp(r'\{[^}]*\}'), '')) &&
              !(arb[key] ?? '').toLowerCase().contains(word))
            '$key: "${arb[key]}"',
      ];
      expect(problems, isEmpty, reason: 'say "$word" for hashtag in $lang');
    });
  }
  test('Russian never says a bare "Club" (it cannot decline)', () {
    final ru = readArb('ru');
    final bare = RegExp(r'(?<!Makapix )\bClub\b');
    expect([for (final e in ru.entries) if (bare.hasMatch(e.value)) '${e.key}: "${e.value}"'], isEmpty,
        reason: 'write "Makapix Club" in Russian (GLOSSARY.md)');
  });
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
