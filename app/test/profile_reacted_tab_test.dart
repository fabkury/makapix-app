import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/api/club_api_client.dart';
import 'package:makapix_club/club/api/profile_api.dart';
import 'package:makapix_club/club/auth/club_session.dart';
import 'package:makapix_club/club/config/club_config.dart';
import 'package:makapix_club/club/models/page.dart';
import 'package:makapix_club/club/models/post.dart';
import 'package:makapix_club/club/ui/profile_page.dart';

/// Minimal-but-real post shape (trimmed from a live feed response).
Map<String, dynamic> _post(int id) => {
      'id': id,
      'storage_key': 'f0efe607-ca35-4145-ab6e-4310cf22b5c2',
      'public_sqid': 'p$id',
      'kind': 'artwork',
      'title': 'post $id',
      'description': null,
      'hashtags': [],
      'art_url': 'https://vault-dev.makapix.club/11/04/f0efe607.webp',
      'width': 64,
      'height': 64,
      'frame_count': 1,
      'unique_colors': 4,
      'transparency_actual': false,
      'alpha_actual': false,
      'created_at': '2026-04-21T15:43:33.700608Z',
      'promoted': false,
      'promoted_category': null,
      'owner': {
        'id': 1,
        'user_key': '611753f6-9fcf-45fa-9276-aec88ce6490c',
        'public_sqid': 't5',
        'handle': 'Fab',
        'avatar_url': null,
        'tagline': null,
        'reputation': 500,
      },
      'reaction_count': 0,
      'comment_count': 0,
      'user_has_liked': false,
      'files': [],
      'license': null,
    };

/// Records the request and answers with a canned JSON body — no network.
class _FakeAdapter implements HttpClientAdapter {
  final Map<String, dynamic> body;
  RequestOptions? lastRequest;
  _FakeAdapter(this.body);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<void>? cancelFuture) async {
    lastRequest = options;
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

ProfileApi _api(_FakeAdapter adapter) {
  final client = ClubApiClient(ClubSession(config: ClubConfig.defaultConfig));
  client.dio.httpClientAdapter = adapter;
  return ProfileApi(client);
}

void main() {
  group('profileTabsFor', () {
    test('gallery always; reacted for signed-in (highlights live in the strip, not a tab)', () {
      expect(profileTabsFor(signedIn: false, ownProfile: false), [ProfileTab.gallery]);
      expect(profileTabsFor(signedIn: true, ownProfile: false),
          [ProfileTab.gallery, ProfileTab.reacted]);
    });

    test('Private leads your own signed-in profile; Gallery stays default (middle)', () {
      expect(profileTabsFor(signedIn: true, ownProfile: true),
          [ProfileTab.private, ProfileTab.gallery, ProfileTab.reacted]);
      // Gallery is never first once Private is present, but it is always present.
      expect(profileTabsFor(signedIn: true, ownProfile: true).indexOf(ProfileTab.gallery), 1);
    });

    test('Private requires both own-profile and signed-in (never leaks to other/signed-out views)',
        () {
      // own but signed-out (an artificial combo — own-profile implies signed-in in practice)
      expect(profileTabsFor(signedIn: false, ownProfile: true), [ProfileTab.gallery]);
      // signed-in but someone else's profile
      expect(profileTabsFor(signedIn: true, ownProfile: false).contains(ProfileTab.private), isFalse);
    });
  });

  group('reacted-posts response shapes', () {
    test('Page envelope with next_cursor', () {
      final page = Page<Post>.fromJson({
        'items': [_post(1), _post(2)],
        'next_cursor': 'abc',
      }, Post.fromJson);
      expect(page.items, hasLength(2));
      expect(page.nextCursor, 'abc');
      expect(page.atEnd, isFalse);
    });

    test('bare {items:[...]} (no cursor) → single page, atEnd', () {
      final page = Page<Post>.fromJson({
        'items': [_post(1)],
      }, Post.fromJson);
      expect(page.items, hasLength(1));
      expect(page.nextCursor, isNull);
      expect(page.atEnd, isTrue);
    });
  });

  group('ProfileApi.reactedPosts', () {
    test('hits /user/u/{sqid}/reacted-posts and parses the page', () async {
      final adapter = _FakeAdapter({
        'items': [_post(7)],
        'next_cursor': null,
      });
      final page = await _api(adapter).reactedPosts('t5');
      expect(adapter.lastRequest!.uri.path, endsWith('/user/u/t5/reacted-posts'));
      expect(adapter.lastRequest!.uri.queryParameters.containsKey('cursor'), isFalse);
      expect(page.items.single.id, 7);
      expect(page.atEnd, isTrue);
    });

    test('passes the cursor through as a query param', () async {
      final adapter = _FakeAdapter({'items': [], 'next_cursor': null});
      await _api(adapter).reactedPosts('t5', cursor: 'eyJpZCI6IDd9');
      expect(adapter.lastRequest!.uri.queryParameters['cursor'], 'eyJpZCI6IDd9');
    });
  });
}
