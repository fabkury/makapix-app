// T4 sweeps: publishing, editing a post's details, My Posts (post management) with its dialogs
// and sheets, the moderator approval queue, and the community-rules gate (batch C6).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/edit/club_edit_request.dart';
import 'package:makapix_club/club/publish/publish_draft.dart';
import 'package:makapix_club/club/state/rules_gate.dart';
import 'package:makapix_club/club/ui/edit_post_details_page.dart';
import 'package:makapix_club/club/ui/pending_approval_page.dart';
import 'package:makapix_club/club/ui/post_management_page.dart';
import 'package:makapix_club/club/ui/publish_page.dart';
import 'package:makapix_club/club/ui/rules_gate_page.dart';
import 'package:makapix_club/l10n/rich.dart';

import 'club_fixtures.dart';
import 'sweep.dart';

const _rulesAccepted = <String, Object>{kRulesPrefKey: kRulesVersion};

// License identifiers and names are shown as the licenses name themselves; file formats and
// the fixture's user text read the same in any language.
final _fixture = <Pattern>[
  RegExp(r'CC BY'),
  'Creative Commons Attribution 4.0',
  'Sunset Tower',
  '8-bit',
  'out of disk',
  // The example hashtags in the empty field: hashtags are Latin-script in every language.
  'pixelart, animation, fantasy',
];

/// A 1×1 transparent PNG: the publish page previews the draft's bytes.
final Uint8List _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

PublishDraft _draft({
  int width = 64,
  int height = 64,
  int frames = 12,
  bool layers = true,
  ClubEditSource? source,
}) =>
    PublishDraft(
      bytes: _png,
      format: 'webp',
      filename: 'art.webp',
      width: width,
      height: height,
      frameCount: frames,
      source: source,
      mkpxBytes: layers ? Uint8List(2048) : null,
      totalDurationMs: frames > 1 ? 1500 : null,
    );

String _ago(Duration d) => DateTime.now().toUtc().subtract(d).toIso8601String();
String _ahead(Duration d) => DateTime.now().toUtc().add(d).toIso8601String();

FakeBackend _backend() => fixtureBackend()
  ..on('GET', r'/license', (_) => {
        'items': [
          {'id': 1, 'identifier': 'CC BY 4.0', 'title': 'Creative Commons Attribution 4.0'},
          {'id': 2, 'identifier': 'CC BY-ND 4.0', 'title': ''},
        ],
      })
  ..on('GET', r'/pmd/posts', (_) => {
        'items': [
          {...fixturePostJson(1, mine: true), 'view_count': 12345, 'reaction_count': 1},
          {
            ...fixturePostJson(2, mine: true, title: ''),
            'hidden_by_user': true,
            'view_count': 1,
            'reaction_count': 22,
            'license_identifier': 'CC BY 4.0',
          },
        ],
        'next_cursor': null,
      })
  ..on('GET', r'/pmd/bdr', (_) => {
        'items': [
          {
            'id': 'bdr-ready-0001',
            'status': 'ready',
            'artwork_count': 21,
            'created_at': _ago(const Duration(hours: 3)),
            'expires_at': _ahead(const Duration(days: 5, hours: 2)),
          },
          {
            'id': 'bdr-ready-0002',
            'status': 'ready',
            'artwork_count': 1,
            'created_at': _ago(const Duration(days: 6)),
            'expires_at': _ahead(const Duration(hours: 5, minutes: 30)),
          },
          {'id': 'b3', 'status': 'pending', 'artwork_count': 2, 'created_at': _ago(Duration.zero)},
          {'id': 'b4', 'status': 'processing', 'artwork_count': 5},
          {'id': 'b5', 'status': 'failed', 'artwork_count': 5, 'error_message': 'out of disk'},
          {'id': 'b6', 'status': 'expired', 'artwork_count': 128},
        ],
      })
  ..on('GET', r'/admin/pending-approval', (_) => {
        'items': [fixturePostJson(1), fixturePostJson(2, title: '')],
        'next_cursor': 'more',
      });

Future<void> _selectFirst(WidgetTester tester) async {
  await tester.tap(find.byType(Checkbox).first);
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  test('boldSpans splits a message at its <b> tags', () {
    String text(InlineSpan s) => (s as TextSpan).text!;
    bool bold(InlineSpan s) => s.style?.fontWeight == FontWeight.bold;

    final mid = boldSpans('We have <b>zero tolerance</b> for it.');
    expect(mid.map(text), ['We have ', 'zero tolerance', ' for it.']);
    expect(mid.map(bold), [false, true, false]);

    final edges = boldSpans('<b>零容忍</b>');
    expect(edges.map(text), ['零容忍']);
    expect(edges.map(bold), [true]);

    expect(boldSpans('No emphasis.').map(text), ['No emphasis.']);
    expect(boldSpans('').length, 0);
  });

  sweepScreen(
    'Publish, animated drawing with layers',
    build: () => PublishPage(draft: _draft()),
    backend: _backend,
    prefs: _rulesAccepted,
    overrides: (b) => clubOverrides(backend: b),
    allowLatin: _fixture,
  );

  sweepScreen(
    'Publish, size not allowed',
    build: () => PublishPage(draft: _draft(width: 300, height: 300, frames: 1, layers: false)),
    backend: _backend,
    prefs: _rulesAccepted,
    overrides: (b) => clubOverrides(backend: b),
    allowLatin: _fixture,
  );

  sweepScreen(
    'Publish, size not allowed, drawing with layers',
    build: () => PublishPage(draft: _draft(width: 100, height: 100, frames: 1)),
    backend: _backend,
    prefs: _rulesAccepted,
    overrides: (b) => clubOverrides(backend: b),
    allowLatin: _fixture,
  );

  sweepScreen(
    'Publish, editing my own post (replace or post as new)',
    build: () => PublishPage(
      draft: _draft(
        source: const ClubEditSource(
            postId: 1,
            sqid: 'p1',
            title: 'Sunset Tower',
            ownerHandle: 'pixel_ada',
            isOwner: true,
            hasMkpx: true),
      ),
    ),
    backend: _backend,
    prefs: _rulesAccepted,
    overrides: (b) => clubOverrides(backend: b),
    allowLatin: _fixture,
    act: (tester) async {
      // The two publish buttons and their notes sit at the end of the form.
      await tester.drag(find.byType(ListView).first, const Offset(0, -900));
    },
  );

  sweepScreen(
    'Publish, signed out',
    build: () => PublishPage(draft: _draft()),
    backend: _backend,
    prefs: _rulesAccepted,
    overrides: (b) => clubOverrides(signedIn: false, backend: b),
  );

  sweepScreen(
    'Community rules gate',
    build: () => const RulesGatePage(),
    backend: _backend,
    overrides: (b) => clubOverrides(backend: b),
  );

  sweepScreen(
    'Edit post details',
    build: () => EditPostDetailsPage(post: fixturePost(2, modHashtags: const ['nsfw'])),
    backend: _backend,
    overrides: (b) => clubOverrides(backend: b),
    allowLatin: _fixture,
  );

  sweepScreen(
    'Pending approval',
    // "@handle · age" under each title: user text, ellipsized by design on a narrow phone.
    allowTruncated: [RegExp('^@')],
    build: () => const PendingApprovalPage(),
    backend: _backend,
    overrides: (b) => clubOverrides(me: fixtureModerator(), backend: b),
    allowLatin: _fixture,
  );

  sweepScreen(
    'My Posts',
    build: () => const PostManagementPage(),
    backend: _backend,
    overrides: (b) => clubOverrides(backend: b),
    allowLatin: _fixture,
  );

  sweepScreen(
    'My Posts, selection',
    build: () => const PostManagementPage(),
    backend: _backend,
    overrides: (b) => clubOverrides(backend: b),
    allowLatin: _fixture,
    act: _selectFirst,
  );

  sweepScreen(
    'My Posts, delete dialog',
    build: () => const PostManagementPage(),
    backend: _backend,
    overrides: (b) => clubOverrides(backend: b),
    allowLatin: _fixture,
    act: (tester) async {
      await _selectFirst(tester);
      await tester.tap(find.byIcon(Icons.delete_outline));
    },
  );

  sweepScreen(
    'My Posts, license picker',
    build: () => const PostManagementPage(),
    backend: _backend,
    overrides: (b) => clubOverrides(backend: b),
    allowLatin: _fixture,
    act: (tester) async {
      await _selectFirst(tester);
      await tester.tap(find.byIcon(Icons.copyright_outlined));
    },
  );

  sweepScreen(
    'My Posts, request download dialog',
    build: () => const PostManagementPage(),
    backend: _backend,
    overrides: (b) => clubOverrides(backend: b),
    allowLatin: _fixture,
    act: (tester) async {
      await _selectFirst(tester);
      await tester.tap(find.byIcon(Icons.archive_outlined));
    },
  );

  sweepScreen(
    'My Posts, downloads sheet',
    build: () => const PostManagementPage(),
    backend: _backend,
    overrides: (b) => clubOverrides(backend: b),
    allowLatin: _fixture,
    act: (tester) => tester.tap(find.byIcon(Icons.download_outlined)),
    // The list polls every 5 s while a download is pending or processing.
    drain: const Duration(seconds: 6),
  );
}
