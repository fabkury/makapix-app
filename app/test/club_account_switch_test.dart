// Regression test for the account-switch leak: viewer-scoped keep-alive providers (home feeds,
// grid-like overrides) must rebuild when the signed-in user changes. The observed bug: user A had
// monitored hashtags enabled; after signing out and signing in as user B, the warm feed still
// showed A's server-filtered content (monitored-hashtag posts). Feeds are filtered server-side,
// so the client fix is to refetch on identity change (currentUserSubProvider).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/club/api/club_api_client.dart';
import 'package:makapix_club/club/api/feed_api.dart';
import 'package:makapix_club/club/auth/club_session.dart';
import 'package:makapix_club/club/auth/github_oauth.dart';
import 'package:makapix_club/club/config/club_config.dart';
import 'package:makapix_club/club/models/club_user.dart';
import 'package:makapix_club/club/models/page.dart' as club;
import 'package:makapix_club/club/models/post.dart';
import 'package:makapix_club/club/state/api_providers.dart';
import 'package:makapix_club/club/state/auth_controller.dart';
import 'package:makapix_club/club/state/feed_providers.dart';
import 'package:makapix_club/club/state/post_providers.dart';

/// An [AuthController] the test drives directly — no token load, no network.
class _FakeAuth extends AuthController {
  _FakeAuth._(ClubSession session, ClubConfig cfg)
      : super(session: session, api: ClubApiClient(session), oauth: GithubOAuth(cfg)) {
    state = const AuthState.signedOut();
  }

  factory _FakeAuth() {
    final cfg = ClubConfig.defaultConfig;
    return _FakeAuth._(ClubSession(config: cfg), cfg);
  }

  @override
  Future<void> init() async {/* stay as driven by the test */}

  void signInAs(String sub) => state = AuthState.signedIn(ClubMe(
        user: ClubUser(sub: sub, userKey: 'key-$sub', handle: sub),
        roles: const [],
        capabilities: const {},
        quotas: const {},
        needsWelcome: false,
      ));

  void signOutNow() => state = const AuthState.signedOut();
}

/// Serves one post per page, titled for the viewer signed in at fetch time — so a feed's items
/// reveal which account they were fetched for. (Posts have no artUrl → the precache no-ops.)
class _FakeFeedApi extends FeedApi {
  final _FakeAuth auth;
  int fetches = 0;
  _FakeFeedApi(this.auth) : super(ClubApiClient(ClubSession(config: ClubConfig.defaultConfig)));

  @override
  Future<club.Page<Post>> recent({String? cursor, int limit = 30}) async {
    fetches++;
    final viewer = auth.state.me?.user.sub ?? 'anon';
    return club.Page<Post>(items: [
      Post.fromJson({'id': 1, 'title': 'feed-for-$viewer'})
    ]);
  }
}

void main() {
  test('switching accounts refetches the home feed (no cross-user leak)', () async {
    final auth = _FakeAuth();
    final feedApi = _FakeFeedApi(auth);
    final c = ProviderContainer(overrides: [
      authControllerProvider.overrideWith((ref) => auth),
      feedApiProvider.overrideWithValue(feedApi),
    ]);
    addTearDown(c.dispose);

    // User A (e.g. with monitored hashtags approved) loads the Recent feed.
    auth.signInAs('userA');
    final nA = c.read(feedProvider(FeedKind.recent).notifier);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(feedProvider(FeedKind.recent)).items.single.title, 'feed-for-userA');

    // A signs out, B signs in. The warm feed must be rebuilt and refetched as B —
    // A's server-filtered content must not survive the switch.
    auth.signOutNow();
    auth.signInAs('userB');
    final nB = c.read(feedProvider(FeedKind.recent).notifier);
    await Future<void>.delayed(Duration.zero);

    expect(identical(nA, nB), isFalse, reason: 'the feed notifier must be recreated on switch');
    expect(c.read(feedProvider(FeedKind.recent)).items.single.title, 'feed-for-userB',
        reason: "user B's feed must be fetched fresh, not user A's warm items");
    expect(feedApi.fetches, greaterThanOrEqualTo(2));
  });

  test('same-user auth updates (reloadMe) do NOT drop the warm feed', () async {
    final auth = _FakeAuth();
    final feedApi = _FakeFeedApi(auth);
    final c = ProviderContainer(overrides: [
      authControllerProvider.overrideWith((ref) => auth),
      feedApiProvider.overrideWithValue(feedApi),
    ]);
    addTearDown(c.dispose);

    auth.signInAs('userA');
    final n1 = c.read(feedProvider(FeedKind.recent).notifier);
    await Future<void>.delayed(Duration.zero);

    // A fresh ClubMe instance for the same sub (what reloadMe produces after onboarding or
    // account-management edits) must not reset feeds or scroll positions.
    auth.signInAs('userA');
    final n2 = c.read(feedProvider(FeedKind.recent).notifier);
    expect(identical(n1, n2), isTrue, reason: 'same user → keep the warm feed');
  });

  test("switching accounts drops the viewer's grid-like overrides", () async {
    final auth = _FakeAuth();
    final feedApi = _FakeFeedApi(auth);
    final c = ProviderContainer(overrides: [
      authControllerProvider.overrideWith((ref) => auth),
      feedApiProvider.overrideWithValue(feedApi),
    ]);
    addTearDown(c.dispose);

    auth.signInAs('userA');
    c.read(gridLikesProvider.notifier).set(42, const GridLikeState(true, 7));
    expect(c.read(gridLikesProvider)[42]!.liked, isTrue);

    auth.signOutNow();
    auth.signInAs('userB');
    expect(c.read(gridLikesProvider), isEmpty,
        reason: "user A's like overrides must not color user B's grid");
  });
}
