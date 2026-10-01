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
          // The server labels are English; every known code is here so the report form
          // shows that the app replaces them with its own translations.
          {'code': 'spam', 'label': 'Spam or misleading'},
          {'code': 'harassment', 'label': 'Harassment or bullying'},
          {'code': 'hate', 'label': 'Hate or discrimination'},
          {'code': 'sexual_explicit', 'label': 'Sexual or explicit content'},
          {'code': 'violence_gore', 'label': 'Violence or gore'},
          {'code': 'illegal_csam', 'label': 'Illegal content or child endangerment'},
          {'code': 'self_harm', 'label': 'Self-harm or suicide'},
          {'code': 'copyright', 'label': 'Copyright or IP violation'},
          {'code': 'other', 'label': 'Something else'},
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

Post fixturePost(int id,
        {String title = 'Sunset Tower',
        List<String> modHashtags = const [],
        int parents = 0,
        int children = 0}) =>
    Post.fromJson({
      ...fixturePostJson(id, title: title, modHashtags: modHashtags),
      'parent_count': parents,
      'child_count': children,
    });

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

/// A non-200 answer from a [FakeBackend] route.
class FakeStatus {
  const FakeStatus(this.status, [this.detail = 'unavailable']);
  final int status;
  final String detail;
}

/// One notification of each type the app composes text for.
List<Map<String, dynamic>> fixtureNotificationsJson() {
  Map<String, dynamic> n(String type, [Map<String, dynamic> extra = const {}]) => {
        'id': 'n-$type-${extra.length}',
        'notification_type': type,
        'is_read': false,
        'created_at': _ago(const Duration(hours: 5)),
        'actor_handle': 'pixel_bob',
        'actor_public_sqid': 'b7',
        ...extra,
      };
  const titled = {'content_title': 'Sunset Tower', 'content_sqid': 'p1'};
  return [
    n('reaction', {...titled, 'emoji': '🔥'}),
    n('reaction', {'emoji': '🔥'}),
    n('comment', {...titled, 'comment_id': 'c1', 'comment_preview': '8-bit'}),
    n('comment_reply', {...titled, 'comment_id': 'c2', 'comment_preview': '16-bit'}),
    n('comment_like', titled),
    n('mention', titled),
    n('mention', {...titled, 'comment_id': 'c3', 'comment_preview': '32-bit'}),
    n('follow'),
    n('remix', titled),
    n('post_promoted', titled),
    n('post_approved', titled),
    n('trust_granted'),
    n('mod_hashtags_updated', {...titled, 'comment_preview': '+nsfw −wip'}),
    n('reputation_change'),
    n('moderator_granted'),
    n('moderator_revoked'),
  ];
}

/// Canned JSON for the real [ClubApiClient]: the first route whose method and path pattern
/// match answers with HTTP 200; anything else gets a 404 and is recorded in [unhandled], so a
/// sweep that forgot a route says which one.
class FakeBackend implements HttpClientAdapter {
  final List<(String, RegExp, FakeHandler)> _routes = [];
  final List<String> unhandled = [];

  /// Answers [method] requests whose path matches [path] (a regular expression, matched
  /// against the path after `/api` or `/api/v1`) with the JSON [body] returns. A handler that
  /// returns a [FakeStatus] answers with that HTTP status instead of 200.
  void on(String method, String path, FakeHandler body) =>
      _routes.insert(0, (method, RegExp('^$path\$'), body));

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<void>? cancelFuture) async {
    final path = options.uri.path.replaceFirst(RegExp(r'^/api(/v1)?'), '');
    for (final (method, pattern, body) in _routes) {
      if (method == options.method && pattern.hasMatch(path)) {
        final answer = body(options);
        final status = answer is FakeStatus ? answer.status : 200;
        final json = answer is FakeStatus ? {'detail': answer.detail} : answer;
        return ResponseBody.fromString(jsonEncode(json), status, headers: {
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

/// A profile as `GET /user/u/{sqid}/profile` returns it.
Map<String, dynamic> fixtureProfileJson({bool own = false, bool blocked = false}) => {
      'user_key': own ? 'u-key-1' : 'u-key-b7',
      'public_sqid': own ? 't5' : 'b7',
      'handle': own ? 'pixel_ada' : 'pixel_bob',
      'bio': '8-bit',
      'tagline': '16-bit',
      'reputation': 1234,
      'stats': {
        'total_posts': 12,
        'total_reactions_received': 3456,
        'total_views': 78901,
        'follower_count': 23,
      },
      'is_following': !own,
      'is_own_profile': own,
      'is_blocked_by_viewer': blocked,
      'highlights': const [],
    };

Map<String, dynamic> _statsJson() => {
      'post_id': 1,
      'total_posts': 12,
      'total_views': 78901,
      'unique_viewers': 2345,
      'views_by_country': {'BR': 40, 'JP': 12},
      'views_by_device': {'desktop': 30, 'mobile': 20, 'tablet': 2, 'player': 1},
      'views_by_type': {'intentional': 30, 'listing': 22},
      'daily_views': [
        for (var d = 1; d <= 30; d++)
          {'date': '2026-09-${d.toString().padLeft(2, '0')}', 'views': d * 3, 'unique_viewers': d},
      ],
      'total_reactions': 3456,
      'reactions_by_emoji': {'🔥': 20, '👍': 5},
      'total_comments': 67,
      'first_view_at': _ago(const Duration(days: 40)),
      'last_view_at': _ago(const Duration(hours: 2)),
      'computed_at': _ago(const Duration(minutes: 10)),
    };

/// A [FakeBackend] with the routes most screens touch. A sweep adds its own with [FakeBackend.on].
FakeBackend fixtureBackend() => FakeBackend()
  ..on('GET', r'/post/\d+/comments', (_) => {'items': fixtureCommentsJson()})
  ..on('GET', r'/post/comments/[^/]+/like-users', (_) => {'items': const []})
  ..on('GET', r'/u/[^/]+/player', (_) => {'items': fixturePlayersJson()})
  // The live notification stream: unavailable, so the app stays on its poll fallback.
  ..on('GET', r'/realtime/notifications', (_) => const FakeStatus(503))
  ..on('GET', r'/social-notifications/unread-count', (_) => {'unread_count': 3, 'count': 3})
  ..on('GET', r'/social-notifications/', (_) => {'items': fixtureNotificationsJson()})
  ..on('POST', r'/social-notifications/mark-(all-)?read', (_) => const <String, dynamic>{})
  ..on('GET', r'/feed/promoted', (_) => {'items': const []})
  ..on('GET', r'/feed/following', (_) => {'items': const []})
  ..on('GET', r'/post/recent', (_) => {'items': const []})
  ..on('GET', r'/post', (_) => {'items': const []})
  ..on('GET', r'/hashtags/top', (_) => {
        'hashtags': ['wip', 'nsfw'],
        'items': ['wip', 'nsfw'],
      })
  ..on('GET', r'/hashtags/stats', (_) => {
        'items': [
          {'tag': 'wip', 'artwork_count': 1, 'reaction_count': 5},
          {'tag': 'nsfw', 'artwork_count': 42, 'reaction_count': 1},
        ],
      })
  ..on('GET', r'/hashtags/[^/]+/posts', (_) => {'items': const []})
  ..on('GET', r'/user/browse', (_) => {
        'items': [fixtureOwnerJson(), fixtureOwnerJson(handle: 'pixel_ada', sqid: 't5')],
      })
  ..on('GET', r'/search', (_) => {'items': const []})
  // Artwork pages. p1: someone else's animated remix with a layers file. p2: the signed-in
  // user's own post, hidden, with moderator hashtags. p3: not remixable, promoted, hidden by
  // moderators, awaiting approval — every moderator chip at once.
  ..on('GET', r'/p/p1', (_) => {
        ...fixturePostJson(1, frames: 12),
        'description': '8-bit',
        'parent_count': 2,
        'child_count': 3,
        'license': {'identifier': 'CC BY 4.0', 'title': 'CC BY 4.0'},
      })
  ..on('GET', r'/p/p2', (_) => {
        ...fixturePostJson(2, mine: true, hashtags: const ['wip', 'nsfw'], modHashtags: const ['nsfw']),
        'hidden_by_user': true,
        'child_count': 1,
      })
  ..on('GET', r'/p/p3', (_) => {
        ...fixturePostJson(3, title: '', hasMkpx: false),
        'remixable': false,
        'promoted': true,
        'promoted_category': 'frontpage',
        'hidden_by_mod': true,
        'public_visibility': false,
      })
  ..on('GET', r'/post/\d+/reactions', (_) => {
        'totals': {'🔥': 7, '👍': 5},
        'mine': ['🔥'],
      })
  ..on('POST', r'/post/\d+/view', (_) => const <String, dynamic>{})
  ..on('GET', r'/post/\d+/parents', (_) => {
        'items': [
          {'position': 0, 'state': 'available', 'post': fixturePostJson(11, title: '')},
          {'position': 1, 'state': 'deleted'},
          {'position': 2, 'state': 'unavailable'},
        ],
        'parents': [
          {'position': 0, 'state': 'available', 'post': fixturePostJson(11, title: '')},
          {'position': 1, 'state': 'deleted'},
          {'position': 2, 'state': 'unavailable'},
        ],
      })
  ..on('GET', r'/post/\d+/children', (_) => {'items': const []})
  ..on('GET', r'/user/u/t5/profile', (_) => fixtureProfileJson(own: true))
  ..on('GET', r'/user/u/b7/profile', (_) => fixtureProfileJson())
  ..on('GET', r'/user/u/[^/]+/reacted-posts', (_) => {'items': const []})
  ..on('GET', r'/user/u/[^/]+/(followers|following)', (_) => {
        'items': [fixtureOwnerJson(), fixtureOwnerJson(handle: 'pixel_ada', sqid: 't5')],
      })
  ..on('GET', r'/badge', (_) => {'items': const [], 'badges': const []})
  ..on('GET', r'/post/\d+/reaction-users', (_) => {
        'items': [
          {
            'emoji': '🔥',
            'created_at': _ago(const Duration(hours: 1)),
            'user_handle': 'pixel_bob',
            'user_public_sqid': 'b7',
          },
          {'emoji': '👍', 'created_at': _ago(const Duration(days: 2)), 'user_handle': ''},
        ],
      })
  ..on('GET', r'/me/remixes', (_) => {
        'items': [
          {
            'post': fixturePostJson(7, title: ''),
            'my_parent_sqids': ['p1'],
          },
          {
            'post': fixturePostJson(8),
            'my_parent_sqids': ['p1', 'p2', 'p3'],
          },
        ],
      })
  ..on('GET', r'/post/\d+/stats', (_) => _statsJson())
  ..on('GET', r'/user/[^/]+/artist-dashboard', (_) => {
        'artist_stats': _statsJson(),
        'posts': [
          {
            'post_id': 1,
            'public_sqid': 'p1',
            'title': 'Sunset Tower',
            'created_at': _ago(const Duration(days: 3)),
            'total_views': 12345,
            'total_reactions': 678,
            'total_comments': 9,
          },
          {'post_id': 2, 'public_sqid': 'p2', 'title': '', 'created_at': _ago(const Duration(days: 9))},
        ],
        'total_posts': 2,
        'page': 2,
        'page_size': 20,
        'has_more': true,
      });

/// Overrides for a signed-in ([signedIn] true) or signed-out Club with the full config and,
/// when [backend] is given, the fake backend under the real API client.
///
/// [offline] is the "signed in from the cached identity, server unreachable" state.
List<Override> clubOverrides(
        {bool signedIn = true, ClubMe? me, FakeBackend? backend, bool offline = false}) =>
    [
      authControllerProvider.overrideWith((ref) => FakeAuth(signedIn
          ? AuthState.signedIn(me ?? fixtureMe(),
              stale: offline, error: offline ? 'offline' : null)
          : const AuthState.signedOut())),
      serverConfigProvider.overrideWith((ref) async => fixtureServerConfig()),
      if (backend != null)
        clubApiClientProvider.overrideWith((ref) {
          final client = ClubApiClient(ref.watch(clubSessionProvider));
          client.dio.httpClientAdapter = backend;
          client.dioRoot.httpClientAdapter = backend;
          return client;
        }),
    ];
