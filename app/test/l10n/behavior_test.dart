// Behavior that depends on the language, beyond what a screen shows.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/ui/auth/delete_account_page.dart';

import 'club_fixtures.dart';
import 'l10n_test_support.dart';

void main() {
  group('delete account: the confirmation word is the language\'s own', () {
    FilledButton deleteButton(WidgetTester tester) =>
        tester.widget<FilledButton>(find.bySubtype<FilledButton>());

    for (final (locale, word) in const [
      ('en', 'DELETE'),
      ('es', 'ELIMINAR'),
      ('pt', 'EXCLUIR'),
      ('fr', 'SUPPRIMER'),
      ('de', 'LÖSCHEN'),
      ('ru', 'УДАЛИТЬ'),
      ('ja', '削除'),
      ('zh', '删除'),
    ]) {
      testWidgets('$locale: typing "$word" arms the button', (tester) async {
        await pumpLocalized(tester, Locale(locale), const DeleteAccountPage(),
            overrides: clubOverrides());
        expect(l10nFor(Locale(locale)).deleteAccountConfirmWord, word);
        expect(deleteButton(tester).onPressed, isNull);

        await tester.enterText(find.byType(TextField), 'nope');
        await tester.pump();
        expect(deleteButton(tester).onPressed, isNull);

        await tester.enterText(find.byType(TextField), word);
        await tester.pump();
        expect(deleteButton(tester).onPressed, isNotNull);
      });
    }

    testWidgets('the English word does not arm it in another language', (tester) async {
      await pumpLocalized(tester, const Locale('ru'), const DeleteAccountPage(),
          overrides: clubOverrides());
      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pump();
      expect(deleteButton(tester).onPressed, isNull);
    });
  });
}
