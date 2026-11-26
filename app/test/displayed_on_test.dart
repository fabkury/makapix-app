// The Displayed on list (messages/0009-impression-list/): the row model, the day-only label,
// the paged `GET /post/{id}/impression-users` call, the page, and the privacy switch in
// Settings. No engine, no network — a fake backend answers underneath the real API client.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/api/club_api_client.dart';
import 'package:makapix_club/club/api/post_api.dart';
import 'package:makapix_club/club/auth/club_session.dart';
import 'package:makapix_club/club/config/club_config.dart';
import 'package:makapix_club/club/models/club_user.dart';
import 'package:makapix_club/club/models/impression_user.dart';
import 'package:makapix_club/club/state/auth_controller.dart';
import 'package:makapix_club/club/ui/displayed_on_page.dart';
import 'package:makapix_club/club/ui/settings_page.dart';
import 'package:makapix_club/club/ui/widgets/common.dart';

import 'l10n/club_fixtures.dart';

Map<String, dynamic> _row(String handle,
        {List<String> models = const [],
        bool web = false,
        bool app = false,
        int count = 1,
        String day = '2026-11-24'}) =>
    {
      'user_handle': handle,
      'user_avatar_url': null,
      'user_public_sqid': 'k3Xp',
      'device_models': models,
      'web_player': web,
      'app': app,
      'count': count,
      'last_shown_on': day,
    };

Future<void> _pump(WidgetTester tester, Widget page, FakeBackend backend,
    {bool signedIn = true}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: clubOverrides(backend: backend, signedIn: signedIn),
    child: MaterialApp(home: page),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('ImpressionUser.fromJson', () {
    test('reads the row the server documents', () {
      final u = ImpressionUser.fromJson(
          _row('ana', models: ['p3a', 'Pixel Jukebox'], count: 14));
      expect(u.handle, 'ana');
      expect(u.sqid, 'k3Xp');
      expect(u.deviceModels, ['p3a', 'Pixel Jukebox']);
      expect(u.webPlayer, isFalse);
      expect(u.app, isFalse);
      expect(u.count, 14);
      expect(u.lastShownOn, DateTime.utc(2026, 11, 24));
    });

    test('keeps only the day should a time ever be sent', () {
      final day = ImpressionUser.parseDay('2026-11-24T21:37:05+00:00');
      expect(day, DateTime.utc(2026, 11, 24));
      expect((day!.hour, day.minute, day.second), (0, 0, 0));
    });

    test('tolerates missing and malformed fields', () {
      final u = ImpressionUser.fromJson({'user_handle': 'ana', 'device_models': ['', ' p3a ']});
      expect(u.deviceModels, ['p3a']);
      expect(u.count, 0);
      expect(u.lastShownOn, isNull);
      expect(ImpressionUser.parseDay('yesterday'), isNull);
      expect(ImpressionUser.parseDay('2026-13-40'), isNull);
    });
  });

  group('shownDayLabel', () {
    // 01:30 UTC on the 26th: a showing on the 25th is "yesterday" although only hours old,
    // and nothing finer than the day is ever shown.
    final now = DateTime.utc(2026, 11, 26, 1, 30);

    test('speaks in whole UTC days', () {
      expect(shownDayLabel(DateTime.utc(2026, 11, 26), now: now), 'today');
      expect(shownDayLabel(DateTime.utc(2026, 11, 25), now: now), 'yesterday');
      expect(shownDayLabel(DateTime.utc(2026, 11, 24), now: now), '2 days ago');
      expect(shownDayLabel(DateTime.utc(2026, 8, 28), now: now), '90 days ago');
    });

    test('compares with the UTC day, whatever the device time zone', () {
      // The same instant as [now], expressed in local time.
      expect(shownDayLabel(DateTime.utc(2026, 11, 26), now: now.toLocal()), 'today');
    });

    test('a day ahead of ours reads as today; no day reads as nothing', () {
      expect(shownDayLabel(DateTime.utc(2026, 11, 27), now: now), 'today');
      expect(shownDayLabel(null, now: now), '');
    });
  });

  group('ClubUser.showInImpressionLists', () {
    Map<String, dynamic> user([Object? flag]) => {
          'public_sqid': 't5',
          'user_key': 'u-key-1',
          'handle': 'pixel_ada',
          'show_in_impression_lists': ?flag,
        };

    test('listed unless the server says otherwise', () {
      expect(ClubUser.fromJson(user()).showInImpressionLists, isTrue);
      expect(ClubUser.fromJson(user(true)).showInImpressionLists, isTrue);
      expect(ClubUser.fromJson(user(false)).showInImpressionLists, isFalse);
    });

    test('copyWith keeps it unless given', () {
      final off = ClubUser.fromJson(user(false));
      expect(off.copyWith(approvedHashtags: const ['nsfw']).showInImpressionLists, isFalse);
      expect(off.copyWith(showInImpressionLists: true).showInImpressionLists, isTrue);
    });
  });

  test('PostApi.impressionUsers sends the cursor and reads the page', () async {
    final seen = <Map<String, dynamic>>[];
    final backend = FakeBackend()
      ..on('GET', r'/post/7/impression-users', (r) {
        seen.add(r.queryParameters);
        return {
          'items': [_row('ana')],
          'next_cursor': r.queryParameters['cursor'] == null ? 'c2' : null,
        };
      });
    final client = ClubApiClient(ClubSession(config: ClubConfig.defaultConfig));
    client.dio.httpClientAdapter = backend;
    final api = PostApi(client);

    final first = await api.impressionUsers(7);
    expect(first.items.single.handle, 'ana');
    expect(first.nextCursor, 'c2');
    final second = await api.impressionUsers(7, cursor: first.nextCursor);
    expect(second.atEnd, isTrue);
    expect(seen[0].containsKey('cursor'), isFalse);
    expect(seen[0]['limit'], 50);
    expect(seen[1]['cursor'], 'c2');
  });

  group('DisplayedOnPage', () {
    testWidgets('lists members with their sources, count and day, then the note',
        (tester) async {
      final backend = fixtureBackend()
        ..on('GET', r'/post/1/impression-users', (_) => {
              'items': [
                _row('ana', models: ['p3a', 'Pixel Jukebox'], count: 14, day: fixtureDay(2)),
                _row('bia', web: true, app: true, count: 1, day: fixtureDay(0)),
                _row('caio', count: 3, day: fixtureDay(1)),
              ],
              'next_cursor': null,
            });
      await _pump(tester, DisplayedOnPage(post: fixturePost(1)), backend);

      expect(find.text('Displayed on'), findsOneWidget);
      expect(find.text('p3a, Pixel Jukebox · shown 14 times'), findsOneWidget);
      expect(find.text('2 days ago'), findsOneWidget);
      expect(find.text('Web Player, App · shown 1 time'), findsOneWidget);
      expect(find.text('today'), findsOneWidget);
      // No model, no Web Player, no app: a player that did not report its model.
      expect(find.text('Player · shown 3 times'), findsOneWidget);
      expect(find.text('yesterday'), findsOneWidget);
      expect(find.textContaining('Anonymous and private showings are not listed.'),
          findsOneWidget);
    });

    testWidgets('follows next_cursor to the end of the list', (tester) async {
      final cursors = <String?>[];
      final backend = fixtureBackend()
        ..on('GET', r'/post/1/impression-users', (r) {
          final cursor = r.queryParameters['cursor'] as String?;
          cursors.add(cursor);
          return cursor == null
              ? {
                  'items': [_row('ana')],
                  'next_cursor': 'page2',
                }
              : {
                  'items': [_row('bia')],
                  'next_cursor': null,
                };
        });
      await _pump(tester, DisplayedOnPage(post: fixturePost(1)), backend);

      // The first page does not fill the screen, so the page asks for the next one itself.
      expect(cursors, [null, 'page2']);
      expect(find.text('ana'), findsOneWidget);
      expect(find.text('bia'), findsOneWidget);
    });

    testWidgets('an empty list says so and still explains who is listed', (tester) async {
      final backend = fixtureBackend()
        ..on('GET', r'/post/1/impression-users',
            (_) => {'items': const <Object>[], 'next_cursor': null});
      await _pump(tester, DisplayedOnPage(post: fixturePost(1)), backend);

      expect(find.text('No members to list yet.'), findsOneWidget);
      expect(find.textContaining('in the last 90 days'), findsOneWidget);
    });

    testWidgets('signed out: a sign-in prompt, and no request', (tester) async {
      final backend = FakeBackend();
      await _pump(tester, DisplayedOnPage(post: fixturePost(1)), backend, signedIn: false);

      expect(find.text('Sign in to see whose screens displayed this artwork.'), findsOneWidget);
      expect(backend.unhandled, isEmpty);
    });

    testWidgets('a failed load offers a retry', (tester) async {
      final backend = fixtureBackend()
        ..on('GET', r'/post/1/impression-users', (_) => const FakeStatus(404, 'Not found'));
      await _pump(tester, DisplayedOnPage(post: fixturePost(1)), backend);

      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('Settings: Show me in Displayed on lists', () {
    final label = find.text('Show me in Displayed on lists');
    bool switchValue(WidgetTester tester) => tester
        .widget<SwitchListTile>(find.ancestor(of: label, matching: find.byType(SwitchListTile)))
        .value;

    testWidgets('on by default; turning it off saves and sticks', (tester) async {
      final sent = <Object?>[];
      final backend = fixtureBackend()
        ..on('PATCH', r'/user/u-key-1', (r) {
          sent.add(r.data);
          return {'show_in_impression_lists': false};
        });
      await _pump(tester, const SettingsPage(), backend);
      expect(switchValue(tester), isTrue);

      await tester.tap(label);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(sent.length, 1);
      final body = sent.single is String ? jsonDecode(sent.single as String) : sent.single;
      expect(body, {'show_in_impression_lists': false});
      expect(switchValue(tester), isFalse);
      final container = ProviderScope.containerOf(tester.element(find.byType(SettingsPage)));
      expect(container.read(authControllerProvider).me!.user.showInImpressionLists, isFalse);
    });

    testWidgets('a refused save puts the switch back and says so', (tester) async {
      final backend = fixtureBackend()
        ..on('PATCH', r'/user/u-key-1', (_) => const FakeStatus(503));
      await _pump(tester, const SettingsPage(), backend);

      await tester.tap(label);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(switchValue(tester), isTrue);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });
}
