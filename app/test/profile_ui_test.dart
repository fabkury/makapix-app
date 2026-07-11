import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/club/api/club_api_client.dart';
import 'package:makapix_club/club/auth/club_session.dart';
import 'package:makapix_club/club/auth/github_oauth.dart';
import 'package:makapix_club/club/config/club_config.dart';
import 'package:makapix_club/club/models/page.dart' as club;
import 'package:makapix_club/club/models/post.dart';
import 'package:makapix_club/club/models/server_config.dart';
import 'package:makapix_club/club/models/user_profile.dart';
import 'package:makapix_club/club/state/auth_controller.dart';
import 'package:makapix_club/club/state/feed_providers.dart';
import 'package:makapix_club/club/state/paged.dart';
import 'package:makapix_club/club/state/profile_providers.dart';
import 'package:makapix_club/club/state/publish_providers.dart';
import 'package:makapix_club/club/ui/profile_page.dart';
import 'package:makapix_club/club/ui/widgets/common.dart';

/// A signed-out [AuthController] that performs no token load / network
/// (mirrors shell_test.dart).
class _SignedOutAuth extends AuthController {
  _SignedOutAuth._(ClubSession session, ClubConfig cfg)
      : super(session: session, api: ClubApiClient(session), oauth: GithubOAuth(cfg)) {
    state = const AuthState.signedOut();
  }

  factory _SignedOutAuth(ClubConfig cfg) => _SignedOutAuth._(ClubSession(config: cfg), cfg);

  @override
  Future<void> init() async {/* stay signed-out; no token load */}
}

/// A [ProfileController] pre-seeded with a profile; never touches the network.
class _FakeProfile extends ProfileController {
  _FakeProfile(super.ref, super.sqid, UserProfile p) {
    state = AsyncValue.data(p);
  }

  @override
  Future<void> load() async {}
  @override
  Future<void> reload() async {}
}

UserProfile _profile({required bool own}) => UserProfile(
      userKey: 'u-key-1',
      sqid: 't5',
      handle: 'PixelFab',
      bio: 'Pixel gardens.',
      tagline: 'making tiny art',
      website: 'https://example.com/',
      avatarUrl: null, // no image → no network; header falls back to the initial
      reputation: 500,
      tagBadges: const [],
      stats: const ProfileStats(
          totalPosts: 3,
          totalReactionsReceived: 999,
          totalViews: 1234567,
          followerCount: 12345),
      isFollowing: false,
      isOwnProfile: own,
      isBlockedByViewer: false,
      highlights: const [], // no highlights → the procedural backdrop (no network)
    );

/// A gallery post with an EMPTY art_url, so tiles render the no-image box
/// instead of attempting an HTTP fetch inside the test.
Post _galleryPost(int id) => Post.fromJson({
      'id': id,
      'storage_key': 'k$id',
      'public_sqid': 'p$id',
      'kind': 'artwork',
      'title': 'post $id',
      'hashtags': [],
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

Widget _harness(UserProfile profile, {List<Post> gallery = const []}) {
  final cfg = ClubConfig.defaultConfig;
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith((ref) => _SignedOutAuth(cfg)),
      serverConfigProvider.overrideWith((ref) async => ClubServerConfig.fallback),
      profileProvider('t5').overrideWith((ref) => _FakeProfile(ref, 't5', profile)),
      ownerFeedProvider('u-key-1').overrideWith((ref) {
        final n = PagedNotifier<Post>((_) async => club.Page<Post>(items: gallery));
        n.loadInitial();
        return n;
      }),
    ],
    child: const MaterialApp(home: ProfilePage(sqid: 't5')),
  );
}

void main() {
  group('compactCount', () {
    test('small numbers pass through', () {
      expect(compactCount(0), '0');
      expect(compactCount(7), '7');
      expect(compactCount(999), '999');
    });

    test('thousands: one decimal under 100k, whole k above', () {
      expect(compactCount(1000), '1k');
      expect(compactCount(1234), '1.2k');
      expect(compactCount(9949), '9.9k');
      expect(compactCount(12345), '12.3k');
      expect(compactCount(99940), '99.9k');
      expect(compactCount(100000), '100k');
      expect(compactCount(123456), '123k');
      expect(compactCount(999499), '999k');
    });

    test('millions: hand-off avoids the "1000k" rounding artifact', () {
      expect(compactCount(999500), '1M');
      expect(compactCount(1200000), '1.2M');
      expect(compactCount(34500000), '34.5M');
      expect(compactCount(123000000), '123M');
    });
  });

  group('formatFileSize', () {
    test('bytes below 1 KiB', () {
      expect(formatFileSize(0), '0 bytes');
      expect(formatFileSize(512), '512 bytes');
      expect(formatFileSize(1023), '1023 bytes');
    });

    test('KiB with one decimal, trailing .0 stripped', () {
      expect(formatFileSize(1024), '1 KiB');
      expect(formatFileSize(1536), '1.5 KiB');
      expect(formatFileSize(38214), '37.3 KiB');
    });

    test('MiB from 1024 KiB up', () {
      expect(formatFileSize(1048576), '1 MiB');
      expect(formatFileSize(5452595), '5.2 MiB');
    });
  });

  group('ProfilePage (widget)', () {
    testWidgets('own profile renders the new header and the creator CTA', (tester) async {
      await tester.pumpWidget(_harness(_profile(own: true)));
      await tester.pumpAndSettle();

      expect(find.text('@PixelFab'), findsOneWidget); // app bar title
      expect(find.text('PixelFab'), findsOneWidget); // header name row
      // Compact stats: Posts / Followers / Reactions / Views, plus the rep pill.
      expect(find.text('3'), findsOneWidget);
      expect(find.text('12.3k'), findsOneWidget);
      expect(find.text('999'), findsOneWidget);
      expect(find.text('1.2M'), findsOneWidget);
      expect(find.text('500'), findsOneWidget);
      expect(find.text('example.com'), findsOneWidget); // website link, scheme stripped
      expect(find.text('Edit profile'), findsOneWidget);
      expect(find.text('Follow'), findsNothing);
      // Your own empty gallery invites creating, not a bare "no posts".
      expect(find.text('Create your first pixel art'), findsOneWidget);
    });

    testWidgets("scrolling someone else's profile collapses the app bar into the mini-bar",
        (tester) async {
      Finder inAppBar(Finder inner) =>
          find.descendant(of: find.byType(AppBar), matching: inner);
      await tester.pumpWidget(_harness(_profile(own: false),
          gallery: [for (var i = 0; i < 24; i++) _galleryPost(i)]));
      await tester.pumpAndSettle();

      // Expanded: plain @handle title; Follow and avatar live in the header only.
      expect(find.byKey(const ValueKey('title-plain')), findsOneWidget);
      expect(find.byKey(const ValueKey('title-mini')), findsNothing);
      expect(inAppBar(find.text('Follow')), findsNothing);
      expect(inAppBar(find.byType(HandleAvatar)), findsNothing);
      expect(find.text('Follow'), findsOneWidget); // the header's button

      await tester.drag(find.byType(NestedScrollView), const Offset(0, -1000));
      await tester.pumpAndSettle();

      // Collapsed: the mini-bar title (small avatar + @handle) and a compact
      // Follow appear in the app bar. (The header's own copies scroll
      // offstage, so default finders no longer see them.)
      expect(find.byKey(const ValueKey('title-mini')), findsOneWidget);
      expect(find.byKey(const ValueKey('title-plain')), findsNothing);
      expect(inAppBar(find.text('Follow')), findsOneWidget);
      expect(inAppBar(find.byType(HandleAvatar)), findsOneWidget);
    });
  });
}
