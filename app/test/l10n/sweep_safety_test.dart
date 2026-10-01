// T4 sweeps: reporting, blocked users, mention and monitored-hashtag settings, and the
// moderator tools (moderation hub, user management and its dialogs) — batch C7. Plus the
// report notifications' sentences, which are composed in code.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/models/club_notification.dart';
import 'package:makapix_club/club/models/comment.dart';
import 'package:makapix_club/club/models/report.dart';
import 'package:makapix_club/club/models/safety_copy.dart';
import 'package:makapix_club/club/ui/blocked_users_page.dart';
import 'package:makapix_club/club/ui/mentions_settings_page.dart';
import 'package:makapix_club/club/ui/moderation_hub_page.dart';
import 'package:makapix_club/club/ui/monitored_hashtags_page.dart';
import 'package:makapix_club/club/ui/report_page.dart';
import 'package:makapix_club/club/ui/user_management_page.dart';

import 'club_fixtures.dart';
import 'l10n_test_support.dart';
import 'sweep.dart';

String _ago(Duration d) => DateTime.now().toUtc().subtract(d).toIso8601String();
String _ahead(Duration d) => DateTime.now().toUtc().add(d).toIso8601String();

Map<String, dynamic> _umd({bool banned = false, bool hidden = false}) => {
      'id': 7,
      'user_key': 'u-key-b7',
      'public_sqid': 'b7',
      'handle': 'pixel_bob',
      'reputation': 1234,
      'auto_public_approval': hidden,
      'hidden_by_mod': hidden,
      'banned_until': banned ? _ahead(const Duration(days: 30)) : null,
      'roles': const ['user'],
      'created_at': '2025-03-09T10:00:00Z',
    };

FakeBackend _backend({bool banned = false, bool hidden = false}) => fixtureBackend()
  ..on('GET', r'/me/blocks', (_) => {
        'items': [
          {'public_sqid': 'b7', 'handle': 'pixel_bob', 'blocked_at': _ago(const Duration(days: 3))},
          {'public_sqid': 'c9', 'handle': 'pixel_cy', 'blocked_at': _ago(Duration.zero)},
        ],
        'next_cursor': null,
      })
  ..on('POST', r'/report', (_) => const <String, dynamic>{})
  ..on('GET', r'/admin/user/b7/manage', (_) => _umd(banned: banned, hidden: hidden));

void main() {
  group('report notifications are composed in the language', () {
    ClubNotification post({String? title = 'Sunset'}) => ClubNotification.fromJson({
          'id': '1',
          'notification_type': 'new_report',
          'reason_code': 'copyright',
          'content_title': title,
          'content_sqid': 'eDfc',
        });
    ClubNotification comment() => ClubNotification.fromJson({
          'id': '2',
          'notification_type': 'new_report',
          'reason_code': 'harassment',
          'content_title': 'Sunset',
          'content_sqid': 'eDfc',
          'comment_id': 'c-uuid',
        });

    testWidgets('Japanese', (tester) async {
      await pumpLocalized(tester, const Locale('ja'), const SizedBox());
      expect(newReportText(post()), '新しい通報：「Sunset」（理由：著作権または知的財産権の侵害）');
      expect(newReportText(comment()), '新しい通報：「Sunset」へのコメント（理由：嫌がらせまたはいじめ）');
      expect(reportResolvedText(post(title: null)), 'ご協力ありがとうございます。通報（投稿）を確認しました。');
    });

    testWidgets('Spanish capitalizes the subject after the colon', (tester) async {
      await pumpLocalized(tester, const Locale('es'), const SizedBox());
      expect(newReportText(comment()),
          'Nueva denuncia: Un comentario en «Sunset». Motivo: Acoso o intimidación');
    });

    testWidgets('the English reason label from the server loses to the translation',
        (tester) async {
      final reasons = fixtureServerConfig().moderation!.reportReasons;
      await pumpLocalized(tester, const Locale('de'), const SizedBox());
      expect(reportReasonLabel('spam', reasons: reasons), 'Spam oder irreführend');
      // A code the app does not know still shows as the server named it.
      expect(reportReasonLabel('new_code', reasons: reasons), 'new_code');
    });
  });

  sweepScreen(
    'Report a post',
    build: () => ReportPage(target: ReportTarget.post(fixturePost(1))),
    backend: _backend,
    overrides: (b) => clubOverrides(backend: b),
  );

  sweepScreen(
    'Report a comment, sent dialog',
    build: () => ReportPage(
        target: ReportTarget.comment(Comment.fromJson(fixtureCommentsJson().first))),
    backend: _backend,
    overrides: (b) => clubOverrides(backend: b),
    act: (tester) async {
      await tester.tap(find.byType(RadioListTile<String>).first);
      await tester.pump();
      // The form is a lazy list: on a short phone the submit button is not built yet.
      await tester.scrollUntilVisible(find.byType(FilledButton), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(AlertDialog), findsOneWidget, reason: 'the report was not sent');
    },
  );

  sweepScreen(
    'Blocked users',
    // A handle is user text, ellipsized by design when the row runs out of room.
    allowTruncated: [RegExp('^@')],
    allowLatin: const ['pixel_cy'],
    build: () => const BlockedUsersPage(),
    backend: _backend,
    overrides: (b) => clubOverrides(backend: b),
  );

  sweepScreen(
    'Mentions settings',
    build: () => const MentionsSettingsPage(),
    backend: _backend,
    overrides: (b) => clubOverrides(backend: b),
  );

  sweepScreen(
    'Monitored hashtags settings',
    build: () => const MonitoredHashtagsPage(),
    backend: _backend,
    overrides: (b) => clubOverrides(backend: b),
  );

  sweepScreen(
    'Moderation hub',
    build: () => const ModerationHubPage(),
    backend: _backend,
    overrides: (b) => clubOverrides(me: fixtureModerator(), backend: b),
  );

  sweepScreen(
    'User management',
    build: () => const UserManagementPage(sqid: 'b7', handle: 'pixel_bob'),
    backend: _backend,
    overrides: (b) => clubOverrides(me: fixtureModerator(), backend: b),
  );

  sweepScreen(
    'User management, banned and hidden user',
    build: () => const UserManagementPage(sqid: 'b7', handle: 'pixel_bob'),
    backend: () => _backend(banned: true, hidden: true),
    overrides: (b) => clubOverrides(me: fixtureModerator(), backend: b),
  );

  sweepScreen(
    'User management, reputation change',
    build: () => const UserManagementPage(sqid: 'b7', handle: 'pixel_bob'),
    backend: _backend,
    overrides: (b) => clubOverrides(me: fixtureModerator(), backend: b),
    act: (tester) async {
      // A lazy list: the reputation card is not built on a short phone until scrolled to.
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.byType(Slider), 200, scrollable: list);
      await tester.enterText(find.byType(TextField).first, '-25');
      await tester.pump();
      await tester.drag(list, const Offset(0, -600));
    },
  );

  sweepScreen(
    'User management, hide profile dialog',
    build: () => const UserManagementPage(sqid: 'b7', handle: 'pixel_bob'),
    backend: _backend,
    overrides: (b) => clubOverrides(me: fixtureModerator(), backend: b),
    act: (tester) => tester.tap(find.byIcon(Icons.visibility_off_outlined)),
  );

  sweepScreen(
    'User management, unban dialog',
    build: () => const UserManagementPage(sqid: 'b7', handle: 'pixel_bob'),
    backend: () => _backend(banned: true),
    overrides: (b) => clubOverrides(me: fixtureModerator(), backend: b),
    act: (tester) async {
      await tester.ensureVisible(find.byIcon(Icons.lock_open));
      await tester.tap(find.byIcon(Icons.lock_open));
    },
  );

  sweepScreen(
    'User management, reveal email dialog',
    build: () => const UserManagementPage(sqid: 'b7', handle: 'pixel_bob'),
    backend: _backend,
    overrides: (b) => clubOverrides(me: fixtureModerator(), backend: b),
    act: (tester) => tester.tap(find.byIcon(Icons.alternate_email)),
  );

  sweepScreen(
    'Ban length dialog',
    build: () =>
        Opener((context, ref) => showBanDurationDialog(context, handle: 'pixel_bob')),
    act: tapOpener,
  );
}
