// Flutter's own UI text — the back button's tooltip, the text-selection menu (Copy, Paste,
// Select all), the label a screen reader gives a sheet's barrier — comes from Material's
// localizations, not the app's ARB files. It follows the app's language only if the global
// delegates are wired and Material knows the language; this checks both, for every language.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'l10n_test_support.dart';

Future<MaterialLocalizations> _materialFor(WidgetTester tester, Locale locale) async {
  late MaterialLocalizations found;
  await pumpLocalized(tester, locale, Builder(builder: (context) {
    found = MaterialLocalizations.of(context);
    return const SizedBox();
  }));
  return found;
}

void main() {
  for (final locale in allLocales.where((l) => l.languageCode != 'en')) {
    testWidgets("Material's own strings are in the language — $locale", (tester) async {
      final en = await _materialFor(tester, const Locale('en'));
      expect(en.backButtonTooltip, 'Back');
      final m = await _materialFor(tester, locale);
      final pairs = {
        'back button': (m.backButtonTooltip, en.backButtonTooltip),
        'copy': (m.copyButtonLabel, en.copyButtonLabel),
        'paste': (m.pasteButtonLabel, en.pasteButtonLabel),
        'select all': (m.selectAllButtonLabel, en.selectAllButtonLabel),
        'close': (m.closeButtonTooltip, en.closeButtonTooltip),
        'dismiss a sheet': (m.modalBarrierDismissLabel, en.modalBarrierDismissLabel),
      };
      final untranslated = [
        for (final e in pairs.entries)
          if (e.value.$1 == e.value.$2) '${e.key}: "${e.value.$1}"',
      ];
      expect(untranslated, isEmpty, reason: 'Material strings still in English for $locale');
    });
  }
}
