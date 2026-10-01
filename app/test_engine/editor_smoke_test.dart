// The real editor starts under the test harness, in each language, and shows its toolbar.
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/widgets/tool_tile.dart';

import 'editor_harness.dart';

void main() {
  for (final locale in allLocales) {
    testWidgets('the real EditorPage mounts with the engine — $locale', (tester) async {
      await pumpEditor(tester, locale);
      expect(find.byType(ToolTile), findsWidgets);
      expect(find.text(l10nFor(locale).toolPencilShort), findsWidgets);
      await screenshot(tester, 'editor_${locale.languageCode}_phone-large');
      await closeEditor(tester);
    });
  }
}
