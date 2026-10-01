// T4 sweeps: the Club's shared widgets (batch C1) — comments, the feed filter sheet, the
// download sheet, the moderator hashtags sheet, the player bar and its options sheet.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/state/player_providers.dart';
import 'package:makapix_club/club/ui/widgets/comments_section.dart';
import 'package:makapix_club/club/ui/widgets/download_sheet.dart';
import 'package:makapix_club/club/ui/widgets/feed_filter.dart';
import 'package:makapix_club/club/ui/widgets/mod_hashtags_sheet.dart';
import 'package:makapix_club/club/ui/widgets/player_bar.dart';

import 'club_fixtures.dart';
import 'sweep.dart';

Widget _comments() => const Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.all(12),
        child: CommentsSection(postId: 1),
      ),
    );

// Comment bodies in the fixture are digits and "-bit", which reads the same in any language.
const _commentBodies = ['8-bit', '16-bit', '32-bit', '64-bit'];

void main() {
  sweepScreen(
    'Comments, signed in',
    build: _comments,
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(backend: b),
    allowLatin: _commentBodies,
  );

  sweepScreen(
    'Comments, signed out',
    build: _comments,
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(signedIn: false, backend: b),
    allowLatin: _commentBodies,
  );

  sweepScreen(
    'Comments, moderator menu open on a deleted comment',
    build: _comments,
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(me: fixtureModerator(), backend: b),
    allowLatin: _commentBodies,
    // The fifth comment is the moderator-deleted one: its menu offers Undelete and Purge.
    act: (tester) async {
      final menus = find.byIcon(Icons.shield_outlined);
      await tester.ensureVisible(menus.at(4));
      await tester.tap(menus.at(4));
    },
  );

  sweepScreen(
    'Comments, moderator delete dialog',
    build: _comments,
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(me: fixtureModerator(), backend: b),
    allowLatin: _commentBodies,
    act: (tester) async {
      await tester.tap(find.byIcon(Icons.shield_outlined).first);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byType(PopupMenuItem<String>).first);
    },
  );

  sweepScreen(
    'Feed filter sheet',
    build: () => Opener((context, ref) => showFeedFilterSheet(context, ref, 'recent')),
    act: tapOpener,
  );

  sweepScreen(
    'Download sheet',
    build: () => Opener((context, ref) => showDownloadSheet(context, ref, post: fixturePost(1))),
    overrides: (b) => clubOverrides(),
    act: tapOpener,
  );

  sweepScreen(
    'Moderator hashtags sheet',
    build: () => Opener((context, ref) => showModHashtagsSheet(context,
        post: fixturePost(1, modHashtags: const ['nsfw', 'wip']), cap: 8)),
    overrides: (b) => clubOverrides(me: fixtureModerator()),
    act: tapOpener,
  );

  sweepScreen(
    'Player bar',
    build: () => const Scaffold(bottomNavigationBar: PlayerBar()),
    backend: fixtureBackend,
    overrides: (b) => [
      ...clubOverrides(backend: b),
      playerSendTargetProvider
          .overrideWith((ref) => const ArtworkTarget(postId: 1, title: 'Sunset Tower')),
    ],
    // The device name and the artwork title are user content, ellipsized by design.
    allowTruncated: const ['Desk Matrix', 'Sunset Tower'],
  );

  sweepScreen(
    'Player options sheet',
    build: () => const Scaffold(bottomNavigationBar: PlayerBar()),
    backend: fixtureBackend,
    overrides: (b) => [
      ...clubOverrides(backend: b),
      playerSendTargetProvider
          .overrideWith((ref) => const ArtworkTarget(postId: 1, title: 'Sunset Tower')),
    ],
    allowTruncated: const ['Desk Matrix', 'Sunset Tower'],
    act: (tester) => tester.tap(find.byIcon(Icons.more_vert)),
  );
}
