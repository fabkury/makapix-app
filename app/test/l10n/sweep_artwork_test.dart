// T4 sweeps: the artwork page — as a visitor, as the owner, as a moderator, with its menus and
// confirmation dialogs — and the lineage page (batch C5).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/ui/artwork_detail_page.dart';
import 'package:makapix_club/club/ui/lineage_page.dart';

import 'club_fixtures.dart';
import 'sweep.dart';

// Fixture content that reads the same in any language: comment bodies, the description, and
// the license identifier (shown as the license names itself).
const _fixture = ['8-bit', '16-bit', '32-bit', '64-bit', 'CC BY 4.0'];

Widget _page(String sqid) => Scaffold(body: SafeArea(child: ArtworkDetailPage(sqid: sqid)));

/// Opens the artwork's ⋮ menu (the last one on the page: comment rows have none of this icon).
Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_vert).first);
  await settleOpen(tester);
}

void main() {
  sweepScreen(
    'Artwork, visitor signed in',
    build: () => _page('p1'),
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(backend: b),
    allowLatin: _fixture,
  );

  sweepScreen(
    'Artwork, signed out',
    build: () => _page('p1'),
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(signedIn: false, backend: b),
    allowLatin: _fixture,
  );

  sweepScreen(
    'Artwork, visitor menu',
    build: () => _page('p1'),
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(backend: b),
    allowLatin: _fixture,
    act: _openMenu,
  );

  sweepScreen(
    'Artwork, owner (hidden post, moderator tags)',
    build: () => _page('p2'),
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(backend: b),
    allowLatin: _fixture,
  );

  sweepScreen(
    'Artwork, owner menu',
    build: () => _page('p2'),
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(backend: b),
    allowLatin: _fixture,
    act: _openMenu,
  );

  sweepScreen(
    'Artwork, owner delete dialog',
    build: () => _page('p2'),
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(backend: b),
    allowLatin: _fixture,
    act: (tester) async {
      await _openMenu(tester);
      await tester.tap(find.byIcon(Icons.delete_outline).last);
    },
  );

  sweepScreen(
    'Artwork, moderator (hidden, promoted, awaiting approval, not remixable)',
    build: () => _page('p3'),
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(me: fixtureModerator(), backend: b),
    allowLatin: _fixture,
  );

  sweepScreen(
    'Artwork, moderator menu',
    build: () => _page('p3'),
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(me: fixtureModerator(), backend: b),
    allowLatin: _fixture,
    act: _openMenu,
  );

  sweepScreen(
    'Artwork, moderator demote dialog',
    build: () => _page('p3'),
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(me: fixtureModerator(), backend: b),
    allowLatin: _fixture,
    act: (tester) async {
      await _openMenu(tester);
      await tester.tap(find.byIcon(Icons.star_outline));
    },
  );

  sweepScreen(
    'Artwork, moderator permanent-delete dialog',
    build: () => _page('p3'),
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(me: fixtureModerator(), backend: b),
    allowLatin: _fixture,
    act: (tester) async {
      await _openMenu(tester);
      await tester.ensureVisible(find.byIcon(Icons.delete_forever_outlined));
      await tester.tap(find.byIcon(Icons.delete_forever_outlined));
    },
  );

  sweepScreen(
    'Use as profile photo dialog',
    build: () => Opener((context, ref) =>
        showUseAsProfilePhotoDialog(context, artUrl: '', handle: 'pixel_ada')),
    act: tapOpener,
  );

  sweepScreen(
    'Lineage',
    // The top-bar title is "Lineage — <artwork title>": user text, ellipsized by design.
    allowTruncated: [RegExp('[—–:：]')],
    build: () => LineagePage(post: fixturePost(1, title: '', parents: 3)),
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(backend: b),
  );

  sweepScreen(
    'Lineage, signed out',
    // The top-bar title is "Lineage — <artwork title>": user text, ellipsized by design.
    allowTruncated: [RegExp('[—–:：]')],
    build: () => LineagePage(post: fixturePost(1)),
    backend: fixtureBackend,
    overrides: (b) => clubOverrides(signedIn: false, backend: b),
  );
}
