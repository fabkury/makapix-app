// T4 sweeps: profiles, the profile editor, follows, reactions, remixes, the artist dashboard,
// and post statistics (batch C4).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/models/user_profile.dart';
import 'package:makapix_club/club/ui/artist_dashboard_page.dart';
import 'package:makapix_club/club/ui/edit_profile_page.dart';
import 'package:makapix_club/club/ui/follows_page.dart';
import 'package:makapix_club/club/ui/my_remixes_page.dart';
import 'package:makapix_club/club/ui/post_stats_page.dart';
import 'package:makapix_club/club/ui/profile_page.dart';
import 'package:makapix_club/club/ui/reactions_page.dart';

import 'club_fixtures.dart';
import 'sweep.dart';

// Fixture bio / tagline / stats content that reads the same in any language.
const _fixture = ['8-bit', '16-bit', 'BR', 'JP', 'Intentional', 'Listing'];

void main() {
  sweepScreen(
    'Profile, someone else',
    build: () => const ProfilePage(sqid: 'b7'),
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(backend: b),
    allowLatin: _fixture,
  );

  sweepScreen(
    'Profile, someone else, menu open (moderator)',
    build: () => const ProfilePage(sqid: 'b7'),
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(me: fixtureModerator(), backend: b),
    allowLatin: _fixture,
    act: (tester) => tester.tap(find.byIcon(Icons.more_vert)),
  );

  sweepScreen(
    'Profile, block dialog',
    build: () => const ProfilePage(sqid: 'b7'),
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(backend: b),
    allowLatin: _fixture,
    act: (tester) async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byIcon(Icons.block));
    },
  );

  sweepScreen(
    'Profile, blocked user',
    build: () => const ProfilePage(sqid: 'b7'),
    backend: () => fixtureBackend()
      ..on('GET', r'/user/u/b7/profile', (_) => fixtureProfileJson(blocked: true)),
    overrides: (b) => clubOverrides(backend: b),
    allowLatin: _fixture,
  );

  sweepScreen(
    'Profile, own (empty gallery)',
    build: () => const ProfilePage(sqid: 't5'),
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(backend: b),
    allowLatin: _fixture,
  );

  sweepScreen(
    'Profile, signed out',
    build: () => const ProfilePage(sqid: 'b7'),
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(signedIn: false, backend: b),
    allowLatin: _fixture,
  );

  sweepScreen(
    'Edit profile',
    build: () => EditProfilePage(profile: UserProfile.fromJson(fixtureProfileJson(own: true))),
    overrides: (b) => clubOverrides(),
    allowLatin: _fixture,
  );

  sweepScreen(
    'Followers and following',
    build: () => const FollowsPage(sqid: 'b7', handle: 'pixel_bob'),
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(backend: b),
  );

  sweepScreen(
    'Reactions',
    build: () => ReactionsPage(post: fixturePost(1, title: '')),
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(backend: b),
  );

  sweepScreen(
    'Remixes of my works',
    build: () => const MyRemixesPage(),
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(backend: b),
    // One-line rows, ellipsized by design.
    allowTruncated: [RegExp('@pixel_bob')],
  );

  sweepScreen(
    'Remixes of my works, empty',
    build: () => const MyRemixesPage(),
    backend: () => fixtureBackend()..on('GET', r'/me/remixes', (_) => {'items': const []}),
    overrides: (b) => clubOverrides(backend: b),
  );

  sweepScreen(
    'Artist dashboard',
    build: () => const ArtistDashboardPage(userKey: 't5'),
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(backend: b),
    allowLatin: _fixture,
  );

  sweepScreen(
    'Artist dashboard, bottom (post table, pager)',
    build: () => const ArtistDashboardPage(userKey: 't5'),
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(backend: b),
    allowLatin: _fixture,
    act: (tester) => tester.drag(find.byType(ListView), const Offset(0, -900)),
  );

  sweepScreen(
    'Post statistics',
    build: () => PostStatsPage(post: fixturePost(1)),
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(backend: b),
    allowLatin: _fixture,
  );

  sweepScreen(
    'Post statistics, bottom (breakdowns, footer)',
    build: () => PostStatsPage(post: fixturePost(1, title: '')),
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(backend: b),
    allowLatin: _fixture,
    act: (tester) => tester.drag(find.byType(ListView), const Offset(0, -900)),
  );
}
