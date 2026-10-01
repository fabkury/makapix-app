// T4 sweeps: the Club home and its pages — Contribute, the feeds, search — plus notifications,
// the hashtag feed, the comments page, and the About dialog (batch C3).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/state/rules_gate.dart';
import 'package:makapix_club/club/ui/about_dialog.dart';
import 'package:makapix_club/club/ui/club_home_page.dart';
import 'package:makapix_club/club/ui/comments_page.dart';
import 'package:makapix_club/club/ui/contribute_page.dart';
import 'package:makapix_club/club/ui/hashtag_feed_page.dart';
import 'package:makapix_club/club/ui/notifications_page.dart';
import 'package:makapix_club/club/ui/search_page.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'club_fixtures.dart';
import 'sweep.dart';

const _commentBodies = ['8-bit', '16-bit', '32-bit', '64-bit'];

/// The community rules already accepted, so the home is not covered by the rules gate.
const _rulesAccepted = <String, Object>{kRulesPrefKey: kRulesVersion};

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Makapix Club',
      packageName: 'club.makapix.app',
      version: '1.11.0',
      buildNumber: '38',
      buildSignature: '',
    );
  });

  sweepScreen(
    'Club home, Recent feed',
    prefs: _rulesAccepted,
    build: () => const ClubHomePage(),
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(backend: b),
  );

  sweepScreen(
    'Club home, menu open (moderator)',
    prefs: _rulesAccepted,
    build: () => const ClubHomePage(),
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(me: fixtureModerator(), backend: b),
    act: (tester) => tester.tap(find.byIcon(Icons.menu)),
  );

  sweepScreen(
    'Club home, signed in from the cached identity while offline',
    prefs: _rulesAccepted,
    build: () => const ClubHomePage(),
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(offline: true, backend: b),
  );

  sweepScreen(
    'Contribute page',
    build: () => const Scaffold(body: ContributePage()),
    overrides: (b) => clubOverrides(),
  );

  sweepScreen(
    'Search, before a query',
    build: () => const Scaffold(body: SafeArea(child: SearchView())),
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(backend: b),
  );

  sweepScreen(
    'Search, users tab',
    build: () => const Scaffold(body: SafeArea(child: SearchView())),
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(backend: b),
    act: (tester) => tester.tap(find.byType(Tab).at(1)),
  );

  sweepScreen(
    'Search, hashtags tab',
    build: () => const Scaffold(body: SafeArea(child: SearchView())),
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(backend: b),
    act: (tester) => tester.tap(find.byType(Tab).at(2)),
  );

  sweepScreen(
    'Notifications',
    build: () => const NotificationsPage(),
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(backend: b),
    allowLatin: _commentBodies,
    // A notification is two lines, ellipsized by design; the long ones (trust, approval)
    // run past that in every language, English included.
    allowTruncated: [RegExp('.')],
  );

  sweepScreen(
    'Notifications, empty',
    build: () => const NotificationsPage(),
    backend: () =>
        fixtureBackend()..on('GET', r'/social-notifications/', (_) => {'items': const []}),
    overrides: (b) => clubOverrides(backend: b),
  );

  sweepScreen(
    'Hashtag feed, empty',
    build: () => const HashtagFeedPage(tag: 'wip'),
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(backend: b),
  );

  sweepScreen(
    'Comments page',
    build: () => CommentsPage(post: fixturePost(1, title: '')),
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(backend: b),
    allowLatin: _commentBodies,
  );

  sweepScreen(
    'About dialog',
    build: () => Opener((context, ref) => showMakapixAboutDialog(context)),
    overrides: (b) => clubOverrides(),
    act: tapOpener,
    // Repository addresses and the author's name are shown as written.
    allowLatin: const [
      'github.com/fabkury/makapix-app',
      'github.com/fabkury/makapix',
      'Fabrício Kury',
      'Google Play',
      'App Store',
    ],
  );
}
