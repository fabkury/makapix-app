// Feed bump (messages/0006-feed-bump): the replace flow's "Show as new in feeds" switch, the
// confirmation for owners without Trust, and the result screen that reads the server's answer.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/edit/club_edit_request.dart';
import 'package:makapix_club/club/models/replace_result.dart';
import 'package:makapix_club/club/publish/publish_draft.dart';
import 'package:makapix_club/club/state/rules_gate.dart';
import 'package:makapix_club/club/ui/publish_page.dart';
import 'package:makapix_club/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/club_fixtures.dart';
import 'l10n/l10n_test_support.dart';

/// A 1×1 transparent PNG: the publish page previews the draft's bytes.
final Uint8List _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

PublishDraft _replaceDraft({DateTime? listedAt}) => PublishDraft(
      bytes: _png,
      format: 'webp',
      filename: 'art.webp',
      width: 64,
      height: 64,
      frameCount: 1,
      source: ClubEditSource(
          postId: 1,
          sqid: 'p1',
          title: 'Sunset Tower',
          ownerHandle: 'pixel_ada',
          isOwner: true,
          listedAt: listedAt),
      mkpxBytes: null,
    );

/// The replace-artwork answer as the server sends it (a partial post).
Map<String, dynamic> _answer({
  bool? publicVisibility = true,
  bool bumped = false,
  String? reason,
  String? availableAt,
}) =>
    {
      'message': 'Artwork replaced successfully',
      'post': {
        'id': 1,
        'public_sqid': 'p1',
        'art_url': '',
        'width': 64,
        'height': 64,
        'frame_count': 1,
        'public_visibility': ?publicVisibility,
        'bumped': bumped,
        'bump_skipped_reason': reason,
        'bump_available_at': availableAt,
      },
    };

/// Every replace request's form fields, in order.
class _Replaces {
  final requests = <Map<String, String>>[];
  int get count => requests.length;
  Map<String, String> get last => requests.last;
}

FakeBackend _backend(_Replaces seen, Map<String, dynamic> answer) => fixtureBackend()
  ..on('GET', r'/license', (_) => {'items': const []})
  ..on('POST', r'/post/1/replace-artwork', (req) {
    seen.requests.add({for (final f in (req.data as FormData).fields) f.key: f.value});
    return answer;
  });

AppLocalizations get _en => l10nFor(const Locale('en'));

Future<void> _open(WidgetTester tester, _Replaces seen,
    {bool trusted = true, Map<String, dynamic>? answer, DateTime? listedAt}) async {
  SharedPreferences.setMockInitialValues(const {kRulesPrefKey: kRulesVersion});
  final backend = _backend(seen, answer ?? _answer());
  await pumpLocalized(tester, const Locale('en'), PublishPage(draft: _replaceDraft(listedAt: listedAt)),
      overrides: clubOverrides(me: fixtureMe(canPostPublic: trusted), backend: backend));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Scrolls the publish form until [finder] is built: the replace controls sit at its end,
/// below the fold of the lazily built list.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
  await tester.pump();
}

Future<void> _tapReplace(WidgetTester tester) async {
  final button = find.widgetWithText(FilledButton, _en.publishReplace);
  await _reveal(tester, button);
  await tester.tap(button);
  await _settle(tester);
}

void main() {
  group('ReplaceResult', () {
    test('reads the feed-bump fields', () {
      final r = ReplaceResult.fromJson(_answer(
        reason: 'cooldown',
        availableAt: '2026-10-09T12:00:00+00:00',
      )['post'] as Map<String, dynamic>);
      expect(r.bumped, isFalse);
      expect(r.onCooldown, isTrue);
      expect(r.bumpAvailableAt, DateTime.utc(2026, 10, 9, 12));
      expect(r.pendingReview, isFalse);
      expect(r.post.sqid, 'p1');
    });

    test('only an explicit public_visibility false means pending review', () {
      ReplaceResult read(bool? v) =>
          ReplaceResult.fromJson(_answer(publicVisibility: v)['post'] as Map<String, dynamic>);
      expect(read(false).pendingReview, isTrue);
      expect(read(true).pendingReview, isFalse);
      // A server from before the feed bump sends no such field: nothing to report.
      expect(read(null).pendingReview, isFalse);
    });
  });

  group('the next bump date (listed_at, 0004 §1)', () {
    final now = DateTime.utc(2026, 10, 5, 12);
    test('a week after the listing, or null once that has passed', () {
      expect(nextBumpAt(null, now: now), isNull);
      expect(nextBumpAt(DateTime.utc(2026, 10, 1), now: now), DateTime.utc(2026, 10, 8));
      expect(nextBumpAt(DateTime.utc(2026, 9, 28, 12), now: now), isNull, reason: 'exactly due');
      expect(nextBumpAt(DateTime.utc(2026, 9, 1), now: now), isNull);
    });

    test('Post reads listed_at', () {
      final post = ReplaceResult.fromJson({
        ...(_answer()['post'] as Map<String, dynamic>),
        'listed_at': '2026-10-01T00:00:00+00:00',
      }).post;
      expect(post.listedAt, DateTime.utc(2026, 10, 1));
    });

    String subtitle(WidgetTester tester) {
      final tile = tester.widget<SwitchListTile>(
          find.widgetWithText(SwitchListTile, _en.publishBump));
      return (tile.subtitle! as Text).data!;
    }

    testWidgets('no listing date: the weekly rule', (tester) async {
      await _open(tester, _Replaces());
      await _reveal(tester, find.text(_en.publishBump));
      expect(subtitle(tester), _en.publishBumpSubtitle);
    });

    testWidgets('bumped recently: the date it can move up again', (tester) async {
      final listed = DateTime.now().subtract(const Duration(days: 2));
      await _open(tester, _Replaces(), listedAt: listed);
      await _reveal(tester, find.text(_en.publishBump));
      expect(subtitle(tester),
          _en.publishBumpAvailableOn(listed.add(kBumpCooldown).toLocal()));
    });

    testWidgets('without Trust the date is checked at approval', (tester) async {
      final listed = DateTime.now().subtract(const Duration(days: 2));
      await _open(tester, _Replaces(), trusted: false, listedAt: listed);
      await _reveal(tester, find.text(_en.publishBump));
      expect(subtitle(tester),
          _en.publishBumpAvailableOnReview(listed.add(kBumpCooldown).toLocal()));
    });

    testWidgets('the week has passed: the weekly rule again', (tester) async {
      await _open(tester, _Replaces(),
          listedAt: DateTime.now().subtract(const Duration(days: 30)));
      await _reveal(tester, find.text(_en.publishBump));
      expect(subtitle(tester), _en.publishBumpSubtitle);
    });
  });

  group('replace flow', () {
    testWidgets('the switch starts on and is sent as bump=true', (tester) async {
      final seen = _Replaces();
      await _open(tester, seen, answer: _answer(bumped: true));
      await _reveal(tester, find.text(_en.publishBump));
      final tile = tester.widget<SwitchListTile>(
          find.widgetWithText(SwitchListTile, _en.publishBump));
      expect(tile.value, isTrue);

      await _tapReplace(tester);
      expect(seen.count, 1);
      expect(seen.last['bump'], 'true');
      expect(find.text(_en.replacedTitle), findsOneWidget);
      expect(find.text(_en.replacedBumped), findsOneWidget);
    });

    testWidgets('turning the switch off sends bump=false', (tester) async {
      final seen = _Replaces();
      await _open(tester, seen, answer: _answer(reason: 'opted_out'));
      await _reveal(tester, find.text(_en.publishBump));
      await tester.tap(find.text(_en.publishBump));
      await tester.pump();
      await _tapReplace(tester);
      expect(seen.last['bump'], 'false');
      // Opted out: a plain "replaced", no line about the feeds.
      expect(find.text(_en.replacedBody), findsOneWidget);
      expect(find.text(_en.replacedBumped), findsNothing);
    });

    testWidgets('a trusted owner replaces without a confirmation', (tester) async {
      final seen = _Replaces();
      await _open(tester, seen);
      await _tapReplace(tester);
      expect(find.text(_en.publishReplaceReviewTitle), findsNothing);
      expect(seen.count, 1);
    });

    testWidgets('an owner without Trust confirms first; Cancel sends nothing', (tester) async {
      final seen = _Replaces();
      await _open(tester, seen,
          trusted: false, answer: _answer(publicVisibility: false, reason: 'not_trusted'));
      await _tapReplace(tester);
      expect(find.text(_en.publishReplaceReviewTitle), findsOneWidget);
      await tester.tap(find.text(_en.commonCancel));
      await _settle(tester);
      expect(seen.count, 0);

      await _tapReplace(tester);
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text(_en.publishReplace)));
      await _settle(tester);
      expect(seen.count, 1);
      expect(find.text(_en.replacedReviewTitle), findsOneWidget);
      expect(find.text(_en.replacedPendingReview), findsOneWidget);
    });

    testWidgets('the cooldown names the date the post can move up again', (tester) async {
      final seen = _Replaces();
      final at = DateTime.now().add(const Duration(days: 5));
      await _open(tester, seen,
          answer: _answer(reason: 'cooldown', availableAt: at.toUtc().toIso8601String()));
      await _tapReplace(tester);
      expect(find.text(_en.replacedCooldown(at)), findsOneWidget);
    });
  });
}
