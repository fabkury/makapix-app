// Pulse (messages/0008-pulse/): the card model, the `GET /pulse` call, and the Club home's
// landing rule. No engine, no network — a fake backend answers underneath the real API client.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/api/club_api_client.dart';
import 'package:makapix_club/club/api/pulse_api.dart';
import 'package:makapix_club/club/auth/club_session.dart';
import 'package:makapix_club/club/config/club_config.dart';
import 'package:makapix_club/club/models/pulse_card.dart';
import 'package:makapix_club/club/state/pulse_providers.dart';
import 'package:makapix_club/club/state/rules_gate.dart';
import 'package:makapix_club/club/ui/club_home_page.dart';
import 'package:makapix_club/club/ui/pulse_view.dart';
import 'package:makapix_club/club/ui/widgets/feed_grid.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/club_fixtures.dart';

Map<String, dynamic> _card(String kind, {Map<String, dynamic> extra = const {}}) => {
      'id': '$kind:b7:2026-11-25T11:40:02+00:00',
      'kind': kind,
      'actor': {'public_sqid': 'b7', 'handle': 'pixel_bob', 'avatar_url': null},
      'started_at': '2026-11-25T11:40:02+00:00',
      'updated_at': '2026-11-25T14:02:11+00:00',
      'count': 1,
      'posts': null,
      'comments': null,
      'player': null,
      'badges': null,
      'reputation': null,
      ...extra,
    };

PulseApi _api(FakeBackend backend) {
  final client = ClubApiClient(ClubSession(config: ClubConfig.defaultConfig));
  client.dio.httpClientAdapter = backend;
  return PulseApi(client);
}

Future<void> _pumpHome(WidgetTester tester, FakeBackend backend, {required bool landing}) async {
  SharedPreferences.setMockInitialValues({kRulesPrefKey: kRulesVersion});
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...clubOverrides(backend: backend),
      pulseLandingProvider.overrideWithValue(landing),
    ],
    child: const MaterialApp(home: ClubHomePage()),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('PulseCard.fromJson', () {
    test('a likes card carries its posts and counts the ones it does not', () {
      final card = PulseCard.fromJson(_card('likes', extra: {
        'count': 12,
        'posts': [for (var i = 1; i <= 6; i++) fixturePostJson(i)],
      }))!;
      expect(card.kind, PulseKind.likes);
      expect(card.actor.handle, 'pixel_bob');
      expect(card.posts.map((p) => p.sqid), ['p1', 'p2', 'p3', 'p4', 'p5', 'p6']);
      expect(card.count, 12);
      expect(card.more, 6);
      expect(card.updatedAt, DateTime.utc(2026, 11, 25, 14, 2, 11));
    });

    test('a comments card carries previews and their posts', () {
      final card = PulseCard.fromJson(_card('comments', extra: {
        'count': 5,
        'comments': [
          {'id': 'c1', 'preview': 'nice', 'is_reply': true, 'created_at': null, 'post': fixturePostJson(3)},
          {'id': 'c2', 'preview': 'no post'}, // malformed: dropped
        ],
      }))!;
      expect(card.comments, hasLength(1));
      expect(card.comments.single.preview, 'nice');
      expect(card.comments.single.isReply, isTrue);
      expect(card.comments.single.post.sqid, 'p3');
      expect(card.more, 4);
    });

    test('player, badge and reputation cards', () {
      final player = PulseCard.fromJson(_card('player', extra: {
        'player': {'device_model': null},
      }))!;
      expect(player.playerModel, isNull);
      expect(player.more, 0);

      final badge = PulseCard.fromJson(_card('badge', extra: {
        'badges': [
          {'badge': 'roots', 'label': 'Roots', 'icon_url_64': '/b/roots.png'},
        ],
      }))!;
      expect(badge.badges.single.badge, 'roots');

      final rep = PulseCard.fromJson(_card('reputation', extra: {
        'reputation': {'delta': 15, 'total': 240},
      }))!;
      expect(rep.reputationDelta, 15);
      expect(rep.reputationTotal, 240);
    });

    test('a card this build cannot show is skipped, not an error', () {
      expect(PulseCard.fromJson(_card('joined')), isNull, reason: 'a kind added later');
      expect(PulseCard.fromJson({..._card('likes'), 'actor': null}), isNull);
      expect(PulseCard.fromJson(_card('likes')), isNull, reason: 'no posts to show');
      expect(PulseCard.fromJson(_card('reputation', extra: {
        'reputation': {'delta': 0, 'total': 9},
      })), isNull);
    });
  });

  group('PulseApi', () {
    test('sends cursor, limit and kinds; drops unknown cards; keeps the cursor', () async {
      RequestOptions? seen;
      final backend = FakeBackend()
        ..on('GET', r'/pulse', (r) {
          seen = r;
          return {
            'items': [
              _card('joined'),
              _card('player', extra: {'player': {'device_model': 'p3a'}}),
            ],
            'next_cursor': 'abc',
          };
        });
      final page = await _api(backend)
          .cards(cursor: 'c0', kinds: {PulseKind.posts, PulseKind.remixes});
      expect(seen!.queryParameters, {'cursor': 'c0', 'limit': 20, 'kinds': 'posts,remixes'});
      expect(page.items.map((c) => c.kind), [PulseKind.player]);
      expect(page.nextCursor, 'abc');
    });

    test('no cursor and no filter send neither parameter', () async {
      RequestOptions? seen;
      final backend = FakeBackend()
        ..on('GET', r'/pulse', (r) {
          seen = r;
          return {'items': const [], 'next_cursor': null};
        });
      final page = await _api(backend).cards();
      expect(seen!.queryParameters, {'limit': 20});
      expect(page.items, isEmpty);
      expect(page.atEnd, isTrue);
    });
  });

  test('the filters cover every kind once, and "all" asks for everything', () {
    expect(PulseFilter.all.kinds, isEmpty);
    final covered = [for (final f in PulseFilter.values) ...f.kinds];
    expect(covered.toSet(), PulseKind.values.toSet());
    expect(covered, hasLength(PulseKind.values.length));
  });

  group('Club home', () {
    testWidgets('opens on Recent until this install has seen the server answer for Pulse',
        (tester) async {
      await _pumpHome(tester, fixtureBackend(), landing: false);
      expect(find.byType(FeedGrid), findsOneWidget);
      expect(find.byType(PulseView), findsNothing);
      // The home asked for Pulse anyway, and remembers the answer for the next launch.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(PulseLandingMemory.key), isTrue);
    });

    testWidgets('opens on Pulse after that, one card per known kind', (tester) async {
      await _pumpHome(tester, fixtureBackend(), landing: true);
      expect(find.byType(PulseView), findsOneWidget);
      expect(find.byIcon(kPulseIcon), findsOneWidget, reason: 'the selected top-bar icon');
      // The first cards are on screen; the unknown "joined" card is not among the eight.
      expect(find.byType(PulseCardTile), findsWidgets);
      final container = ProviderScope.containerOf(tester.element(find.byType(PulseView)));
      expect(container.read(pulseProvider).items.map((c) => c.kind).toSet(),
          PulseKind.values.toSet());
      expect(container.read(pulseAvailableProvider), isTrue);
    });

    testWidgets('a filter chip refetches with its kinds', (tester) async {
      final asked = <String?>[];
      final backend = fixtureBackend()
        ..on('GET', r'/pulse', (r) {
          asked.add(r.queryParameters['kinds'] as String?);
          return {'items': fixturePulseJson(), 'next_cursor': null};
        });
      await _pumpHome(tester, backend, landing: true);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Comments'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(asked, [null, 'comments']);
    });

    testWidgets('a server without Pulse (404) shows the page as coming, and is remembered',
        (tester) async {
      final backend = fixtureBackend()..on('GET', r'/pulse', (_) => const FakeStatus(404));
      await _pumpHome(tester, backend, landing: true);
      expect(find.byType(PulseCardTile), findsNothing);
      expect(find.textContaining('coming soon'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(PulseLandingMemory.key), isFalse);
    });

    testWidgets('coming back to Pulse refetches only once it is a minute old', (tester) async {
      var calls = 0;
      final backend = fixtureBackend()
        ..on('GET', r'/pulse', (_) {
          calls++;
          return {'items': fixturePulseJson(), 'next_cursor': null};
        });
      await _pumpHome(tester, backend, landing: true);
      expect(calls, 1);
      final container = ProviderScope.containerOf(tester.element(find.byType(PulseView)));

      // Leave for Recent and come straight back: still fresh.
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(kPulseIconOutlined));
      await tester.pumpAndSettle();
      expect(calls, 1);

      // The same trip once the page is over a minute old.
      container.read(pulseFetchedAtProvider.notifier).state =
          DateTime.now().subtract(const Duration(minutes: 2));
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(kPulseIconOutlined));
      await tester.pumpAndSettle();
      expect(calls, 2);
    });
  });
}
