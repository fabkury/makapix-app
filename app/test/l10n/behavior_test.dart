// Behavior that depends on the language, beyond what a screen shows.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/models/club_error.dart';
import 'package:makapix_club/club/models/mention_candidate.dart';
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

  group('text made outside widgets follows the language', () {
    testWidgets('errors the app words itself', (tester) async {
      await pumpLocalized(tester, const Locale('ru'), const SizedBox());
      final l10n = l10nFor(const Locale('ru'));
      // No usable body from the server: the app's own wording, in Russian.
      expect(ClubError.fromBody(500, null).message, l10n.commonSomethingWrong);
      expect(ClubError.fromBody(500, null).message, isNot(contains('Something')));
      expect(blockedInteractionMessage, l10n.errBlockedInteraction);
      // What the server did say is shown as it came.
      expect(ClubError.fromBody(400, {'detail': 'Handle already taken'}).message,
          'Handle already taken');
    });

    testWidgets('mention picker labels', (tester) async {
      await pumpLocalized(tester, const Locale('ja'), const SizedBox());
      expect(MentionReason.owner.label, '作者');
      expect(MentionReason.search.label, '');
    });

    testWidgets('a language switch changes them without a restart', (tester) async {
      await pumpLocalized(tester, const Locale('de'), const SizedBox());
      final german = MentionReason.follower.label;
      await pumpLocalized(tester, const Locale('fr'), const SizedBox());
      expect(MentionReason.follower.label, isNot(german));
    });
  });
}
