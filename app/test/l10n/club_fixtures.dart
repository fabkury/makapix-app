// Fake Club state for the i18n screen sweeps (docs/i18n/TESTING.md, T4): a signed-in or
// signed-out account, a server config with every optional feature switched on, and a fake
// backend — canned JSON answered underneath the REAL API client — so the real providers,
// controllers, and pages run unmodified. No secure storage, no network.
//
// Fixture content the tests put on screen (handles, titles, emails) is deliberately short and
// recognizable, and is listed in [kFixtureText] so the leftover-English check can ignore it.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:makapix_club/club/api/club_api_client.dart';
import 'package:makapix_club/club/auth/club_session.dart';
import 'package:makapix_club/club/auth/github_oauth.dart';
import 'package:makapix_club/club/config/club_config.dart';
import 'package:makapix_club/club/models/club_user.dart';
import 'package:makapix_club/club/models/post.dart';
import 'package:makapix_club/club/models/server_config.dart';
import 'package:makapix_club/club/state/auth_controller.dart';
import 'package:makapix_club/club/state/publish_providers.dart';

/// Fixture strings that legitimately appear in Latin script on any screen.
const List<Pattern> kFixtureText = [
  'pixel_ada',
  'pixel_bob',
  'ada@example.com',
  'acme@makapix.club',
  'Sunset Tower',
  'Desk Matrix',
  'Shelf Panel',
  'nsfw',
  'politics',
  'violence',
  'explicit',
  '13plus',
  'wip',
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
  Map<String, dynamic> quotas = const {},
}) =>
    ClubMe.fromJson({
      'quotas': quotas,
      'capabilities': const {'can_post_public': false},
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

/// The signed-in account as a moderator.
ClubMe fixtureModerator() => fixtureMe(roles: const ['moderator']);

/// A server config with the optional feature blocks present (moderation, mentions, .mkpx).
ClubServerConfig fixtureServerConfig() => ClubServerConfig.fromJson({
      'max_mentions_per_text': 5,
      'max_mod_hashtags_per_post': 8,
      'upload': {
        'mkpx': {'enabled': true},
      },
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

Map<String, dynamic> fixtureOwnerJson({String handle = 'pixel_bob', String sqid = 'b7'}) => {
      'user_key': 'u-key-$sqid',
      'public_sqid': sqid,
      'handle': handle,
      'avatar_url': null,
      'tagline': null,
      'reputation': 500,
    };

/// A post as the feed endpoints return it. No image URLs: the sweeps never touch the image
/// cache plugins.
Map<String, dynamic> fixturePostJson(
  int id, {
  String title = 'Sunset Tower',
  int frames = 1,
  List<String> hashtags = const ['wip'],
  List<String> modHashtags = const [],
  bool hasMkpx = true,
  bool mine = false,
}) =>
    {
      'id': id,
      'public_sqid': 'p$id',
      'storage_key': 'k$id',
      'kind': 'artwork',
      'title': title,
      'description': null,
      'hashtags': hashtags,
      'mod_hashtags': modHashtags,
      'art_url': '',
      'width': 64,
      'height': 64,
      'frame_count': frames,
      'unique_colors': 12,
      'created_at': DateTime.now().toUtc().subtract(const Duration(hours: 3)).toIso8601String(),
      'owner': mine ? fixtureOwnerJson(handle: 'pixel_ada', sqid: 't5') : fixtureOwnerJson(),
      'reaction_count': 12,
      'comment_count': 3,
      'view_count': 1234,
      'files': [
        {'format': 'png', 'file_bytes': 38214, 'is_native': true},
        {'format': 'gif', 'file_bytes': 5452595, 'is_native': false},
      ],
      'has_mkpx': hasMkpx,
      'mkpx_file_bytes': hasMkpx ? 20480 : null,
      'public_visibility': true,
    };

Post fixturePost(int id, {String title = 'Sunset Tower', List<String> modHashtags = const []}) =>
    Post.fromJson(fixturePostJson(id, title: title, modHashtags: modHashtags));

String _ago(Duration d) => DateTime.now().toUtc().subtract(d).toIso8601String();

/// A flat comment list covering every tile state: plain, liked, a reply, a guest author,
/// deleted by its owner, deleted by a moderator, and hidden by a moderator.
List<Map<String, dynamic>> fixtureCommentsJson() => [
      {
        'id': 'c1',
        'depth': 0,
        'body': '8-bit',
        'created_at': _ago(const Duration(minutes: 5)),
        'author_handle': 'pixel_bob',
        'author_public_sqid': 'b7',
        'like_count': 2,
        'liked_by_me': true,
      },
      {
        'id': 'c2',
        'parent_id': 'c1',
        'depth': 1,
        'body': '16-bit',
        'created_at': _ago(const Duration(hours: 2)),
        'author_handle': 'pixel_ada',
        'author_public_sqid': 't5',
        'like_count': 0,
      },
      {
        'id': 'c3',
        'depth': 0,
        'body': '32-bit',
        'created_at': _ago(const Duration(days: 3)),
        'like_count': 0,
      },
      {
        'id': 'c4',
        'depth': 0,
        'body': '',
        'created_at': _ago(const Duration(days: 15)),
        'author_handle': 'pixel_bob',
        'author_public_sqid': 'b7',
        'deleted_by_owner': true,
      },
      {
        'id': 'c5',
        'depth': 0,
        'body': '',
        'created_at': _ago(const Duration(days: 70)),
        'author_handle': 'pixel_bob',
        'author_public_sqid': 'b7',
        'deleted_by_mod': true,
      },
      {
        'id': 'c6',
        'depth': 0,
        'body': '64-bit',
        'created_at': _ago(const Duration(days: 800)),
        'author_handle': 'pixel_bob',
        'author_public_sqid': 'b7',
        'hidden_by_mod': true,
      },
    ];

/// Two online player devices with every adjustment capability.
List<Map<String, dynamic>> fixturePlayersJson() => [
      for (final (i, name) in const ['Desk Matrix', 'Shelf Panel'].indexed)
        {
          'id': 'pl$i',
          'player_key': 'key$i',
          'name': name,
          'device_model': 'p3a',
          'connection_status': 'online',
          'registration_status': 'registered',
          'is_paused': false,
          'brightness': 60,
          'rotation': 0,
          'mirror': 'none',
          'capabilities': {
            'pause': <String, dynamic>{},
            'brightness': {'min': 0, 'max': 100, 'step': 5},
            'rotation': {
              'values': [0, 90, 180, 270],
            },
            'mirror': {
              'values': ['none', 'h', 'v', 'both'],
            },
          },
        },
    ];

typedef FakeHandler = Object? Function(RequestOptions request);

/// Canned JSON for the real [ClubApiClient]: the first route whose method and path pattern
/// match answers with HTTP 200; anything else gets a 404 and is recorded in [unhandled], so a
/// sweep that forgot a route says which one.
class FakeBackend implements HttpClientAdapter {
  final List<(String, RegExp, FakeHandler)> _routes = [];
  final List<String> unhandled = [];

  /// Answers [method] requests whose path matches [path] (a regular expression, matched
  /// against the path after `/api` or `/api/v1`) with the JSON [body] returns.
  void on(String method, String path, FakeHandler body) =>
      _routes.insert(0, (method, RegExp('^$path\$'), body));

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<void>? cancelFuture) async {
    final path = options.uri.path.replaceFirst(RegExp(r'^/api(/v1)?'), '');
    for (final (method, pattern, body) in _routes) {
      if (method == options.method && pattern.hasMatch(path)) {
        return ResponseBody.fromString(jsonEncode(body(options)), 200, headers: {
          Headers.contentTypeHeader: ['application/json'],
        });
      }
    }
    unhandled.add('${options.method} $path');
    return ResponseBody.fromString(jsonEncode({'detail': 'Not found'}), 404, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// A [FakeBackend] with the routes most screens touch. A sweep adds its own with [FakeBackend.on].
FakeBackend fixtureBackend() => FakeBackend()
  ..on('GET', r'/post/\d+/comments', (_) => {'items': fixtureCommentsJson()})
  ..on('GET', r'/post/comments/[^/]+/like-users', (_) => {'items': const []})
  ..on('GET', r'/u/[^/]+/player', (_) => {'items': fixturePlayersJson()});

/// Overrides for a signed-in ([signedIn] true) or signed-out Club with the full config and,
/// when [backend] is given, the fake backend under the real API client.
List<Override> clubOverrides({bool signedIn = true, ClubMe? me, FakeBackend? backend}) => [
      authControllerProvider.overrideWith((ref) => FakeAuth(
          signedIn ? AuthState.signedIn(me ?? fixtureMe()) : const AuthState.signedOut())),
      serverConfigProvider.overrideWith((ref) async => fixtureServerConfig()),
      if (backend != null)
        clubApiClientProvider.overrideWith((ref) {
          final client = ClubApiClient(ref.watch(clubSessionProvider));
          client.dio.httpClientAdapter = backend;
          client.dioRoot.httpClientAdapter = backend;
          return client;
        }),
    ];
