// The Club `User-Agent` header (messages/0001-app-device-type): the pure formatter, the
// platform-only fallback, and the header actually reaching the wire on every Club Dio client —
// plus the explicit `intent: "view"` on view registration. No engine, no network, no plugins.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/api/club_api_client.dart';
import 'package:makapix_club/club/api/club_user_agent.dart';
import 'package:makapix_club/club/api/post_api.dart';
import 'package:makapix_club/club/auth/club_session.dart';
import 'package:makapix_club/club/config/club_config.dart';

/// Records the request and answers with a canned JSON body — no network.
class _FakeAdapter implements HttpClientAdapter {
  final int status;
  RequestOptions? lastRequest;
  _FakeAdapter({this.status = 200});

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<void>? cancelFuture) async {
    lastRequest = options;
    return ResponseBody.fromString(jsonEncode(<String, dynamic>{}), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('ClubUserAgent.format', () {
    test("matches the server's Android example", () {
      expect(
          ClubUserAgent.format(
              version: '1.9.0', build: '36', platform: 'Android', osVersion: '14', model: 'Pixel 8'),
          'MakapixClub/1.9.0+36 (Android 14; Pixel 8)');
    });

    test("matches the server's iOS example", () {
      expect(
          ClubUserAgent.format(
              version: '1.9.0', platform: 'iOS', osVersion: '18.5', model: 'iPhone15,3'),
          'MakapixClub/1.9.0 (iOS 18.5; iPhone15,3)');
    });

    test('drops empty optional parts and keeps the platform word first', () {
      expect(ClubUserAgent.format(version: '1.9.0', platform: 'Windows'),
          'MakapixClub/1.9.0 (Windows)');
      expect(ClubUserAgent.format(version: '1.9.0', platform: 'Windows', osVersion: '10.0.26200'),
          'MakapixClub/1.9.0 (Windows 10.0.26200)');
      expect(ClubUserAgent.format(version: '1.9.0', build: '', platform: 'Android', model: 'Pixel 8'),
          'MakapixClub/1.9.0 (Android; Pixel 8)');
    });

    test('an empty version reads unknown', () {
      expect(ClubUserAgent.format(version: '', platform: 'Android'), 'MakapixClub/unknown (Android)');
    });

    test('sanitizes the free-form parts: reserved chars, non-ASCII, control chars, runs of space', () {
      expect(
          ClubUserAgent.format(
              version: '1.9.0',
              platform: 'Android',
              osVersion: '14',
              model: '  Pixel (8); Pró\tmax\n  '),
          'MakapixClub/1.9.0 (Android 14; Pixel 8 Pr max)');
    });

    test('caps an absurd model string', () {
      final ua = ClubUserAgent.format(
          version: '1.9.0', platform: 'Android', model: 'M' * 200);
      expect(ua, 'MakapixClub/1.9.0 (Android; ${'M' * 64})');
    });
  });

  group('ClubUserAgent.value', () {
    setUp(ClubUserAgent.resetForTest);

    test('is the platform-only fallback before init (and with no plugins)', () {
      expect(ClubUserAgent.value, 'MakapixClub/unknown (${ClubUserAgent.platformWord})');
      expect(ClubUserAgent.headers, {'User-Agent': ClubUserAgent.value});
    });

    test('init never throws without platform channels and leaves the fallback', () async {
      await ClubUserAgent.init();
      expect(ClubUserAgent.value, startsWith('MakapixClub/unknown ('));
    });
  });

  group('every Club Dio client sends the header', () {
    test('ClubApiClient.dio and dioRoot carry it in their BaseOptions', () {
      final client = ClubApiClient(ClubSession(config: ClubConfig.defaultConfig));
      expect(client.dio.options.headers['User-Agent'], ClubUserAgent.value);
      expect(client.dioRoot.options.headers['User-Agent'], ClubUserAgent.value);
    });

    test('the header and the explicit intent reach the wire on view registration', () async {
      final client = ClubApiClient(ClubSession(config: ClubConfig.defaultConfig));
      final adapter = _FakeAdapter();
      client.dio.httpClientAdapter = adapter;
      await PostApi(client).registerView(42, channel: 'artwork', intent: 'view');
      final req = adapter.lastRequest!;
      expect(req.path, '/post/42/view');
      expect(req.headers['User-Agent'], startsWith('MakapixClub/'));
      expect(req.data, {'channel': 'artwork', 'intent': 'view'});
    });

    test('a failed view registration still never surfaces', () async {
      final client = ClubApiClient(ClubSession(config: ClubConfig.defaultConfig));
      client.dio.httpClientAdapter = _FakeAdapter(status: 429);
      await PostApi(client).registerView(42, channel: 'artwork', intent: 'view');
    });
  });
}
