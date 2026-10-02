// The engine's own layer names ("Layer 3", "Import 2", "Layer 3 copy") are shown in the user's
// language (lib/editor/layers/layer_names.dart); a name the artist typed is shown as typed.
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/layers/layer_names.dart';

import 'l10n/l10n_test_support.dart';

void main() {
  test('the engine names, in Spanish', () {
    final es = l10nFor(const Locale('es'));
    expect(shownLayerName(es, 'Layer 3'), 'Capa 3');
    expect(shownLayerName(es, 'Import 2'), 'Importación 2');
    expect(shownLayerName(es, 'Layer 3 copy'), 'Capa 3 (copia)');
    expect(shownLayerName(es, 'Import 1 copy copy'), 'Importación 1 (copia) (copia)');
    expect(shownLayerName(es, ''), es.layerUnnamed);
  });

  test('English shows the engine names unchanged', () {
    final en = l10nFor(const Locale('en'));
    for (final name in ['Layer 3', 'Import 2', 'Layer 3 copy', 'Import 1 copy copy']) {
      expect(shownLayerName(en, name), name);
    }
  });

  test("the artist's names are never translated", () {
    final ja = l10nFor(const Locale('ja'));
    for (final name in ['Sky', 'Layer', 'Layer 3b', 'my Layer 3', 'Imported 2', 'Sky copy']) {
      expect(shownLayerName(ja, name), name);
    }
  });

  test('every language names the engine layers without English left in', () {
    for (final locale in allLocales.where((l) => l.languageCode != 'en')) {
      final l = l10nFor(locale);
      for (final name in ['Layer 3', 'Import 2', 'Layer 3 copy']) {
        expect(shownLayerName(l, name), isNot(contains(RegExp(r'Layer|copy'))), reason: '$locale $name');
      }
    }
  });
}
