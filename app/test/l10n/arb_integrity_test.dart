// T1 (docs/i18n/TESTING.md): the translation files are complete and well-formed.
//
// gen-l10n falls back to English for a missing key and accepts a translation whose
// placeholders differ from the template's, so neither mistake fails the build. These checks
// make both fail the suite instead.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/l10n/app_locale.dart';

import 'l10n_test_support.dart';

/// What an ICU message asks for: its arguments, and the branches of each plural / select.
class IcuShape {
  final Set<String> placeholders = {};

  /// `count:plural` → {one, other}; `policy:select` → {following, nobody, other}.
  final Map<String, Set<String>> branches = {};
  bool wellFormed = true;
}

/// Parses the ICU subset gen-l10n accepts: `{name}`, `{name, plural|select, key{…} …}`,
/// `{name, number|date|time, …}`. No quoting (l10n.yaml: use-escaping is off).
IcuShape icuShape(String message) {
  final shape = IcuShape();
  var i = 0;

  void fail() {
    shape.wellFormed = false;
    i = message.length;
  }

  void skipSpace() {
    while (i < message.length && message[i].trim().isEmpty) {
      i++;
    }
  }

  // Parses message text up to (not including) the '}' that closes the enclosing branch.
  void parseText({required bool nested}) {
    while (i < message.length) {
      final c = message[i];
      if (c == '}') {
        if (!nested) fail();
        return;
      }
      if (c != '{') {
        i++;
        continue;
      }
      i++; // '{'
      skipSpace();
      final nameStart = i;
      while (i < message.length && RegExp(r'[A-Za-z0-9_]').hasMatch(message[i])) {
        i++;
      }
      final name = message.substring(nameStart, i);
      skipSpace();
      if (name.isEmpty || i >= message.length) return fail();
      shape.placeholders.add(name);
      if (message[i] == '}') {
        i++;
        continue;
      }
      if (message[i] != ',') return fail();
      i++;
      skipSpace();
      final typeStart = i;
      while (i < message.length && RegExp(r'[a-z]').hasMatch(message[i])) {
        i++;
      }
      final type = message.substring(typeStart, i);
      skipSpace();
      if (type != 'plural' && type != 'select') {
        // number / date / time: skip to the closing brace.
        while (i < message.length && message[i] != '}') {
          i++;
        }
        if (i >= message.length) return fail();
        i++;
        continue;
      }
      if (i >= message.length || message[i] != ',') return fail();
      i++;
      final keys = shape.branches.putIfAbsent('$name:$type', () => {});
      while (true) {
        skipSpace();
        if (i >= message.length) return fail();
        if (message[i] == '}') {
          i++;
          break;
        }
        final keyStart = i;
        while (i < message.length && message[i] != '{' && message[i] != '}' && message[i].trim().isNotEmpty) {
          i++;
        }
        final key = message.substring(keyStart, i);
        skipSpace();
        if (key.isEmpty || i >= message.length || message[i] != '{') return fail();
        keys.add(key);
        i++; // '{'
        parseText(nested: true);
        if (i >= message.length || message[i] != '}') return fail();
        i++;
      }
    }
    if (nested) fail(); // ran out of text inside a branch
  }

  parseText(nested: false);
  return shape;
}

/// CLDR plural categories each language needs for cardinal numbers.
const Map<String, Set<String>> kPluralCategories = {
  'en': {'one', 'other'},
  'de': {'one', 'other'},
  'es': {'one', 'other'}, // 'many' (millions) never occurs at the app's magnitudes
  'fr': {'one', 'other'},
  'pt': {'one', 'other'},
  'ru': {'one', 'few', 'many', 'other'},
  'ja': {'other'},
  'zh': {'other'},
};

void main() {
  final en = readArb('en');
  final meta = readArbMeta();
  final locales = [for (final l in kAppLanguages) l.locale.languageCode];

  test('one ARB file per language, and no stray ones', () {
    final onDisk = Directory('lib/l10n')
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.endsWith('.arb'))
        .map((n) => n.substring('app_'.length, n.length - '.arb'.length))
        .toSet();
    expect(onDisk, locales.toSet());
    expect(kAppLanguages.map((l) => l.locale).toSet().length, kAppLanguages.length);
    expect(kAppLanguages.any((l) => l.locale == const Locale('en')), isTrue);
  });

  test('every English message has a description for the translator', () {
    final bare = [
      for (final k in en.keys)
        if ((meta[k]?['description'] as String? ?? '').trim().length < 10) k,
    ];
    expect(bare, isEmpty, reason: 'messages with no (or a trivial) @description');
  });

  test('every placeholder used by an English message is declared, and vice versa', () {
    final problems = <String>[];
    for (final e in en.entries) {
      final used = icuShape(e.value).placeholders;
      final declared = ((meta[e.key]?['placeholders'] as Map?) ?? const {}).keys.cast<String>().toSet();
      if (used.difference(declared).isNotEmpty || declared.difference(used).isNotEmpty) {
        problems.add('${e.key}: used $used, declared $declared');
      }
    }
    expect(problems, isEmpty);
  });

  for (final locale in locales.where((l) => l != 'en')) {
    group('app_$locale.arb', () {
      final tr = readArb(locale);

      test('has exactly the template\'s keys', () {
        expect(en.keys.toSet().difference(tr.keys.toSet()), isEmpty, reason: 'untranslated');
        expect(tr.keys.toSet().difference(en.keys.toSet()), isEmpty, reason: 'orphaned');
      });

      test('no empty translation, no stray whitespace', () {
        // listSeparator is the one message whose space is its content (", " between items).
        const spaced = {'listSeparator'};
        final bad = [
          for (final e in tr.entries)
            if (e.value.trim().isEmpty || (e.value != e.value.trim() && !spaced.contains(e.key))) e.key,
        ];
        expect(bad, isEmpty);
      });

      test('placeholders match the template', () {
        final problems = <String>[];
        for (final e in tr.entries) {
          final want = icuShape(en[e.key] ?? '').placeholders;
          final got = icuShape(e.value).placeholders;
          if (want.difference(got).isNotEmpty || got.difference(want).isNotEmpty) {
            problems.add('${e.key}: template $want, translation $got');
          }
        }
        expect(problems, isEmpty);
      });

      test('every message parses as ICU', () {
        expect([for (final e in tr.entries) if (!icuShape(e.value).wellFormed) e.key], isEmpty);
      });

      test('plurals carry this language\'s categories; selects keep the template\'s cases', () {
        final problems = <String>[];
        for (final e in tr.entries) {
          final want = icuShape(en[e.key] ?? '').branches;
          final got = icuShape(e.value).branches;
          // A language with a single plural category (Japanese, Chinese) may write a plain
          // message where the template has a plural. A select may never be dropped.
          final lost = want.keys.toSet().difference(got.keys.toSet());
          final onlyOther = kPluralCategories[locale]!.length == 1;
          if (lost.any((arg) => arg.endsWith(':select') || !onlyOther)) {
            problems.add('${e.key}: lost an ICU argument ($lost)');
            continue;
          }
          for (final arg in got.keys) {
            final branches = got[arg]!;
            if (arg.endsWith(':plural')) {
              final categories = branches.where((b) => !b.startsWith('=')).toSet();
              final needed = kPluralCategories[locale]!;
              if (!categories.containsAll(needed)) {
                problems.add('${e.key}: plural needs $needed, has $categories');
              }
            } else if (want[arg] != null && !branches.containsAll(want[arg]!)) {
              problems.add('${e.key}: select needs ${want[arg]}, has $branches');
            }
          }
        }
        expect(problems, isEmpty);
      });
    });
  }

  group('punctuation style (docs/i18n/GLOSSARY.md "Voice")', () {
    test('French: a no-break space before : ; ! ?', () {
      final fr = readArb('fr');
      // A plain space (or none) before the mark lets the line break orphan it.
      final bad = [
        for (final e in fr.entries)
          if (RegExp(r'[^  {,][:;!?](\s|$)').hasMatch(e.value.replaceAll(RegExp(r'\{[^{}]*\}'), 'x')))
            e.key,
      ];
      expect(bad, isEmpty);
    });

    for (final locale in const ['ja', 'zh']) {
      test('$locale: full-width punctuation after CJK text', () {
        final tr = readArb(locale);
        final cjk = r'[぀-ヿ㐀-鿿]';
        final bad = [
          for (final e in tr.entries)
            if (RegExp('$cjk[:;!?,.]( |\$)').hasMatch(e.value)) e.key,
        ];
        expect(bad, isEmpty, reason: 'use ： ； ！ ？ ， 。 after Japanese / Chinese text');
      });
    }

    test('no language uses three dots for the ellipsis', () {
      final bad = [
        for (final locale in locales)
          for (final e in readArb(locale).entries)
            if (e.value.contains('...')) '$locale:${e.key}',
      ];
      expect(bad, isEmpty, reason: 'use the single character …');
    });
  });

  test('icuShape reads placeholders and branches, not branch text', () {
    final s = icuShape('{count, plural, =0{none} one{{count} frame of {total}} other{frames}} by {who}');
    expect(s.wellFormed, isTrue);
    expect(s.placeholders, {'count', 'total', 'who'});
    expect(s.branches, {'count:plural': {'=0', 'one', 'other'}});
    expect(icuShape('a {b').wellFormed, isFalse);
    expect(icuShape('a } b').wellFormed, isFalse);
    expect(icuShape('{n, plural, one{x}').wellFormed, isFalse);
  });

  test('English messages parse, and plurals carry an "other" branch', () {
    final problems = <String>[];
    for (final e in en.entries) {
      if (!icuShape(e.value).wellFormed) problems.add('${e.key}: malformed');
      for (final arg in icuShape(e.value).branches.entries.where((a) => a.key.endsWith(':plural'))) {
        final categories = arg.value.where((b) => !b.startsWith('=')).toSet();
        if (!categories.contains('other')) problems.add('${e.key}: no "other" branch');
      }
    }
    expect(problems, isEmpty);
  });

  test('the generated classes are up to date with the ARB files', () {
    // `flutter test` does not re-run gen-l10n when an ARB changes, so a stale
    // app_localizations*.dart would quietly test the old strings.
    final generated = File('lib/l10n/app_localizations.dart');
    expect(generated.existsSync(), isTrue, reason: 'run `flutter gen-l10n`');
    final stale = [
      for (final locale in locales)
        if (File('lib/l10n/app_$locale.arb').lastModifiedSync().isAfter(
            File('lib/l10n/app_localizations_$locale.dart').lastModifiedSync()))
          'app_$locale.arb',
    ];
    expect(stale, isEmpty, reason: 'ARB newer than its generated class — run `flutter gen-l10n`');
    for (final locale in locales) {
      final arb = readArb(locale);
      final l = l10nFor(Locale(locale));
      expect(l.settingsTitle, arb['settingsTitle'], reason: locale);
      expect(l.toolPencilShort, arb['toolPencilShort'], reason: locale);
    }
  });
}
