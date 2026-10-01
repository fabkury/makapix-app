// Fake Club state for the i18n screen sweeps (docs/i18n/TESTING.md, T4): a signed-in or
// signed-out account and a server config with every optional feature switched on, so a sweep
// renders each screen at its fullest. No secure storage, no network.
//
// Fixture content the tests put on screen (handles, titles, emails) is deliberately short and
// recognizable, and is listed in [kFixtureText] so the leftover-English check can ignore it.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:makapix_club/club/api/club_api_client.dart';
import 'package:makapix_club/club/auth/club_session.dart';
import 'package:makapix_club/club/auth/github_oauth.dart';
import 'package:makapix_club/club/config/club_config.dart';
import 'package:makapix_club/club/models/club_user.dart';
import 'package:makapix_club/club/models/server_config.dart';
import 'package:makapix_club/club/state/auth_controller.dart';
import 'package:makapix_club/club/state/publish_providers.dart';

/// Fixture strings that legitimately appear in Latin script on any screen.
const List<Pattern> kFixtureText = [
  'pixel_ada',
  'ada@example.com',
  'acme@makapix.club',
];

/// An [AuthController] pinned to one state: no token load, no network.
class FakeAuth extends AuthController {
  FakeAuth._(ClubSession session, ClubConfig cfg, AuthState initial)
      : super(session: session, api: ClubApiClient(session), oauth: GithubOAuth(cfg)) {
    state = initial;
  }

  factory FakeAuth(AuthState initial) {
    final cfg = ClubConfig.defaultConfig;
    return FakeAuth._(ClubSession(config: cfg), cfg, initial);
  }

  @override
  Future<void> init() async {}
}

ClubMe fixtureMe({
  List<String> roles = const [],
  List<String> approvedHashtags = const ['nsfw', 'politics'],
  String mentionPolicy = 'following',
}) =>
    ClubMe.fromJson({
      'user': {
        'public_sqid': 't5',
        'user_key': 'u-key-1',
        'handle': 'pixel_ada',
        'email': 'ada@example.com',
        'approved_hashtags': approvedHashtags,
        'mention_policy': mentionPolicy,
      },
      'roles': roles,
      'needs_welcome': false,
    });

/// A server config with the optional feature blocks present (moderation, mentions).
ClubServerConfig fixtureServerConfig() => ClubServerConfig.fromJson({
      'mentions_enabled': true,
      'moderation': {
        'report_reasons': [
          {'code': 'spam', 'label': 'Spam or misleading'},
          {'code': 'harassment', 'label': 'Harassment or bullying'},
        ],
        'contact_email': 'acme@makapix.club',
        'guidelines_url': 'https://makapix.club/about?tab=rules',
        'terms_url': 'https://makapix.club/terms',
        'moderation_policy_url': 'https://makapix.club/about?tab=moderation',
        'max_blocks_per_user': 1000,
      },
    });

/// Overrides for a signed-in ([signedIn] true) or signed-out Club with the full config.
List<Override> clubOverrides({bool signedIn = true, ClubMe? me}) => [
      authControllerProvider.overrideWith((ref) => FakeAuth(
          signedIn ? AuthState.signedIn(me ?? fixtureMe()) : const AuthState.signedOut())),
      serverConfigProvider.overrideWith((ref) async => fixtureServerConfig()),
    ];
