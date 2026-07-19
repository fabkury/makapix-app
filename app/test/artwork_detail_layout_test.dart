// Artwork detail page: single-column on phones, two-pane (stage left, 400dp info pane right)
// at ≥ kWideDetailBreakpoint. Pure-Dart: the post/reactions/comments come from a fake PostApi,
// art_url is empty (no image fetch), and the post is static (no animation providers involved).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/club/api/club_api_client.dart';
import 'package:makapix_club/club/api/post_api.dart';
import 'package:makapix_club/club/auth/club_session.dart';
import 'package:makapix_club/club/auth/github_oauth.dart';
import 'package:makapix_club/club/config/club_config.dart';
import 'package:makapix_club/club/models/comment.dart';
import 'package:makapix_club/club/models/post.dart';
import 'package:makapix_club/club/models/reactions.dart';
import 'package:makapix_club/club/models/server_config.dart';
import 'package:makapix_club/club/state/api_providers.dart';
import 'package:makapix_club/club/state/auth_controller.dart';
import 'package:makapix_club/club/state/publish_providers.dart';
import 'package:makapix_club/club/ui/artwork_detail_page.dart';
import 'package:makapix_club/ui/layout.dart';

/// Signed-out auth that performs no token load / network (mirrors profile_ui_test).
class _SignedOutAuth extends AuthController {
  _SignedOutAuth._(ClubSession session, ClubConfig cfg)
      : super(session: session, api: ClubApiClient(session), oauth: GithubOAuth(cfg)) {
    state = const AuthState.signedOut();
  }

  factory _SignedOutAuth(ClubConfig cfg) => _SignedOutAuth._(ClubSession(config: cfg), cfg);

  @override
  Future<void> init() async {/* stay signed-out */}
}

/// Serves one canned post; every engagement call is a no-op / empty.
class _FakePostApi extends PostApi {
  final Post post;
  _FakePostApi(super.client, this.post);

  @override
  Future<Post> getBySqid(String sqid) async => post;
  @override
  Future<void> registerView(int postId, {String? channel, String? channelContext}) async {}
  @override
  Future<ReactionTotals> reactions(int postId) async => const ReactionTotals();
  @override
  Future<List<Comment>> comments(int postId) async => const [];
}

/// Static post with an EMPTY art_url so no HTTP fetch happens inside the test.
Post _post() => Post.fromJson({
      'id': 1,
      'storage_key': 'k1',
      'public_sqid': 'p1',
      'kind': 'artwork',
      'title': 'Tiny Garden',
      'hashtags': ['pixelart'],
      'art_url': '',
      'width': 64,
      'height': 64,
      'frame_count': 1,
      'created_at': '2026-04-21T15:43:33.700608Z',
      'owner': {
        'id': 1,
        'user_key': 'u-key-1',
        'public_sqid': 't5',
        'handle': 'PixelFab',
        'reputation': 500,
      },
      'reaction_count': 0,
      'comment_count': 0,
      'user_has_liked': false,
      'files': [],
    });

Widget _harness() {
  final cfg = ClubConfig.defaultConfig;
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith((ref) => _SignedOutAuth(cfg)),
      serverConfigProvider.overrideWith((ref) async => ClubServerConfig.fallback),
      postApiProvider.overrideWithValue(_FakePostApi(ClubApiClient(ClubSession(config: cfg)), _post())),
    ],
    child: const MaterialApp(home: ArtworkDetailPage(sqid: 'p1')),
  );
}

void main() {
  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();
  }

  testWidgets('phone width: single column — title renders below the stage, at the left edge',
      (tester) async {
    await pumpAt(tester, const Size(400, 800));
    final title = tester.getRect(find.text('Tiny Garden'));
    expect(title.left, lessThan(100), reason: 'info block spans the full width');
  });

  testWidgets('wide viewport: two panes — info in a right-hand 400dp pane', (tester) async {
    await pumpAt(tester, const Size(1200, 800));
    expect(1200, greaterThanOrEqualTo(kWideDetailBreakpoint));
    final title = tester.getRect(find.text('Tiny Garden'));
    expect(title.left, greaterThanOrEqualTo(1200 - 400),
        reason: 'title lives in the fixed-width right pane');
    // The owner header moved into the right pane too.
    final owner = tester.getRect(find.text('PixelFab'));
    expect(owner.left, greaterThanOrEqualTo(1200 - 400));
  });

  testWidgets('just below the breakpoint stays single-column', (tester) async {
    await pumpAt(tester, Size(kWideDetailBreakpoint - 1, 800));
    final title = tester.getRect(find.text('Tiny Garden'));
    expect(title.left, lessThan(100));
  });
}
