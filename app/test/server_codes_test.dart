// The server's specific error codes and keys (messages/0005-localized-text/0003-0004): every
// code a user can meet reads in the app's own words, with the numbers from `details`; the code
// beside `detail` off `/v1` is read; a banned account ends the session with the reason; the
// handle check, badges, and download failures use their keys; the user's language is sent.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/api/club_api_client.dart';
import 'package:makapix_club/club/auth/club_session.dart';
import 'package:makapix_club/club/auth/github_oauth.dart';
import 'package:makapix_club/club/auth/token_store.dart';
import 'package:makapix_club/club/config/club_config.dart';
import 'package:makapix_club/club/models/account.dart';
import 'package:makapix_club/club/models/auth_tokens.dart';
import 'package:makapix_club/club/models/badge_text.dart';
import 'package:makapix_club/club/models/club_error.dart';
import 'package:makapix_club/club/models/pmd.dart';
import 'package:makapix_club/club/state/auth_controller.dart';
import 'package:makapix_club/l10n/l10n.dart';

/// Every code in the server's `ErrorCode` (api/app/errors.py, 2026-10-05) that the app shows in
/// its own words. A code the server adds later keeps the server's text until it is listed here.
const _userFacing = [
  'invalid_credentials', 'email_not_verified', 'account_banned', 'account_deactivated',
  'email_taken', 'pending_verification', 'apple_email_missing', 'apple_token_invalid',
  'github_failed', 'oauth_state_invalid', 'password_login_unsupported',
  'current_password_incorrect', 'last_auth_method', 'weak_password', 'token_invalid',
  'token_expired', 'handle_taken', 'handle_invalid', 'forbidden_role', 'not_owner',
  'artwork_duplicate', 'artwork_unchanged', 'dimensions_invalid', 'file_too_large',
  'quota_exceeded', 'image_empty', 'image_format_unsupported', 'image_invalid', 'storage_full',
  'storage_unavailable', 'post_has_no_artwork', 'mkpx_invalid', 'mkpx_too_large',
  'mkpx_not_attached', 'format_not_available', 'post_not_found', 'post_deleted',
  'post_not_visible', 'remixable_conflicts_with_license', 'not_remixable', 'too_many_parents',
  'parent_not_found', 'remix_not_allowed', 'lineage_cycle', 'reaction_cap_reached',
  'comment_not_found', 'comment_too_deep', 'comment_profanity', 'comment_cap_reached',
  'parent_comment_not_found', 'comment_not_deleted', 'user_not_found', 'blocked',
  'block_cap_reached', 'owner_protected', 'mod_hashtags_limit', 'hashtag_too_long',
  'player_not_found', 'player_limit_reached', 'registration_code_invalid',
  'player_already_registered', 'unsupported_command', 'invalid_value', 'posts_not_owned',
  'bdr_daily_limit', 'bdr_not_ready', 'bdr_expired', 'bdr_not_found', 'rate_limited',
];

/// Codes that keep the server's prose: generic ones (their text says what went wrong) and the
/// ones only an app bug or the silent restore path can cause.
const _keepProse = [
  'validation_error', 'bad_request', 'unauthorized', 'forbidden', 'not_found', 'conflict',
  'internal_error', 'restore_credential_invalid', 'restore_credential_unknown',
  'invalid_creation_method', 'invalid_source_details',
];

ClubError _v1(int status, String code, [Map<String, dynamic>? details]) => ClubError.fromBody(
    status, {
  'error': {'code': code, 'message': 'English prose', 'details': ?details}
});

void main() {
  tearDown(debugResetAppL10n);

  group('codes', () {
    test('every user-facing code has the app\'s own sentence', () {
      for (final code in _userFacing) {
        final e = _v1(400, code);
        expect(e.specific, isTrue, reason: code);
        expect(e.serverText, isNull, reason: code);
        expect(e.message, isNot(contains('English prose')), reason: code);
      }
    });

    test('generic and app-bug codes keep the server text', () {
      for (final code in _keepProse) {
        expect(_v1(400, code).serverText, 'English prose', reason: code);
      }
    });

    test('off /v1 the code beside detail is read', () {
      final e = ClubError.fromBody(404, {
        'detail': 'Player not found',
        'code': 'player_not_found',
      });
      expect(e.code, 'player_not_found');
      expect(e.message, "This player isn't registered anymore.");
      expect(e.serverText, isNull);
      // A plain error there carries a status fallback code; its detail still shows.
      final plain = ClubError.fromBody(400, {'detail': 'Some reason', 'code': 'bad_request'});
      expect(plain.serverText, 'Some reason');
      // An older server sends detail alone.
      expect(ClubError.fromBody(400, {'detail': 'Old'}).code, 'error');
    });

    test('details fill in the numbers and reasons', () {
      expect(_v1(413, 'file_too_large', {'max_bytes': 5 * 1024 * 1024}).message,
          'The file is too large. The limit is 5 MiB.');
      expect(_v1(413, 'quota_exceeded', {'used_bytes': 1024, 'limit_bytes': 1024}).message,
          'Your storage space is full (1 KiB of 1 KiB used).');
      expect(_v1(413, 'quota_exceeded').message, 'Your storage space is full.');
      expect(_v1(400, 'dimensions_invalid', {'width': 300, 'height': 200, 'max': 256}).message,
          "The Club doesn't accept this image size (300×200).");
      expect(_v1(400, 'weak_password', {'reason': 'no_digit'}).message,
          'Include at least one number.');
      expect(_v1(400, 'handle_invalid', {'reason': 'too_long'}).message,
          appL10n.handleTooLong);
      expect(_v1(400, 'image_format_unsupported', {'allowed': ['png', 'webp']}).message,
          "This image format isn't supported. Use PNG, WEBP.");
      expect(_v1(422, 'hashtag_too_long', {'max_length': 64}).message,
          'A hashtag is too long. The limit is 64 characters.');
      expect(_v1(409, 'email_taken', {'provider': 'github'}).message,
          'An account with this email already exists and signs in with GitHub.');
      expect(_v1(409, 'email_taken', {'provider': 'password'}).message, appL10n.authEmailExists);
      expect(_v1(429, 'bdr_daily_limit', {'limit': 8}).message,
          "You've reached today's download limit (8). Try again tomorrow.");
    });

    test('a ban shows its end date; a permanent one does not', () {
      final until = _v1(403, 'account_banned',
          {'banned_until': '2026-10-12T14:00:00Z', 'permanent': false});
      expect(until.message, startsWith('This account is banned until '));
      expect(until.message, contains('2026'));
      expect(until.isAccountBlocked, isTrue);
      expect(_v1(403, 'account_banned', {'banned_until': '9999-12-31T23:59:59Z'}).message,
          'This account is banned.');
      expect(_v1(403, 'account_banned', {'permanent': true}).message, 'This account is banned.');
      expect(_v1(403, 'account_deactivated').isAccountBlocked, isTrue);
    });
  });

  group('keys beside the errors', () {
    test('the handle check speaks from its reason', () {
      HandleAvailability parse(Map<String, dynamic> j) =>
          HandleAvailability.fromJson({'handle': 'x', 'message': 'English', ...j});
      expect(parse({'available': true}).message, appL10n.handleAvailable);
      expect(parse({'available': false, 'reason': 'taken'}).message, appL10n.srvHandleTaken);
      expect(parse({'available': false, 'reason': 'bad_edge'}).message, appL10n.handleEdgeChars);
      expect(parse({'available': false, 'reason': 'reserved'}).message, appL10n.handleUnavailable);
      expect(parse({'available': false}).message, appL10n.handleUnavailable);
    });

    test('known badges are named by slug; a new one keeps the server text', () {
      expect(badgeLabel('master', 'Server Master'), 'Master');
      expect(badgeDescription('roots', 'x'), 'Original community member');
      expect(badgeLabel('new-badge', 'New Badge'), 'New Badge');
      expect(badgeDescription('new-badge', null), isNull);
    });

    test('a failed download request explains itself by code', () {
      Bdr bdr(Map<String, dynamic> j) =>
          Bdr.fromJson({'id': '1', 'status': 'failed', 'artwork_count': 0, ...j});
      expect(bdr({'error_code': 'no_posts', 'error_message': 'No posts found'}).failureText,
          appL10n.bdrErrorNoPosts);
      expect(bdr({'error_message': 'Legacy text'}).failureText, 'Legacy text');
      expect(bdr({}).failureText, isNull);
    });

    test('the language tag the server gets', () {
      expect(appLanguageTag(), 'en');
    });
  });

  group('account refused mid-session', () {
    test('a 403 account_banned clears the session and says why', () async {
      final store = _MemoryStore(tokens: _tokens);
      final session = ClubSession(config: ClubConfig.defaultConfig, store: store);
      await session.load();
      ClubError? cause;
      session.onSessionInvalidated = ([c]) => cause = c;
      final client = ClubApiClient(session);
      client.dio.httpClientAdapter = _JsonAdapter(403, {
        'error': {'code': 'account_banned', 'message': 'Account banned', 'details': {'permanent': true}}
      });

      await expectLater(client.me(), throwsA(isA<ClubError>()));
      expect(session.isSignedIn, isFalse);
      expect(store.tokens, isNull);
      expect(cause?.code, 'account_banned');
    });

    test('any other 403 leaves the session alone', () async {
      final store = _MemoryStore(tokens: _tokens);
      final session = ClubSession(config: ClubConfig.defaultConfig, store: store);
      await session.load();
      final client = ClubApiClient(session);
      client.dio.httpClientAdapter = _JsonAdapter(403, {
        'error': {'code': 'not_owner', 'message': 'Not yours'}
      });
      await expectLater(client.me(), throwsA(isA<ClubError>()));
      expect(session.isSignedIn, isTrue);
    });

    test('the auth controller lands on the sign-in form with the reason', () async {
      final store = _MemoryStore(tokens: _tokens);
      final session = ClubSession(config: ClubConfig.defaultConfig, store: store);
      final api = _ScriptedApi(session, () async => throw _v1(403, 'account_banned', {'permanent': true}));
      final auth = AuthController(session: session, api: api, oauth: GithubOAuth(session.config));
      await auth.init();
      expect(auth.state.status, AuthStatus.error);
      expect(auth.state.error, 'This account is banned.');
      expect(auth.state.errorCode, 'account_banned');
      expect(store.tokens, isNull);
      auth.dispose();
    });
  });

  group('locale sync', () {
    test("sends the app's language once, and not when the server already has it", () async {
      final store = _MemoryStore(tokens: _tokens);
      final session = ClubSession(config: ClubConfig.defaultConfig, store: store);
      final api = _ScriptedApi(session, () async => _meJson(locale: null));
      final auth = AuthController(session: session, api: api, oauth: GithubOAuth(session.config));
      await auth.init();
      expect(api.localeCalls, [('k1', 'en')]);
      auth.syncLocale();
      expect(api.localeCalls, hasLength(1), reason: 'sent once');
      auth.dispose();

      final api2 = _ScriptedApi(ClubSession(config: ClubConfig.defaultConfig, store: _MemoryStore(tokens: _tokens)),
          () async => _meJson(locale: 'en'));
      final auth2 =
          AuthController(session: api2.session, api: api2, oauth: GithubOAuth(api2.session.config));
      await auth2.init();
      expect(api2.localeCalls, isEmpty);
      auth2.dispose();
    });
  });
}

class _MemoryStore extends SecureTokenStore {
  AuthTokens? tokens;
  String? me;
  _MemoryStore({this.tokens});

  @override
  Future<AuthTokens?> read() async => tokens;
  @override
  Future<void> write(AuthTokens t) async => tokens = t;
  @override
  Future<String?> readMe() async => me;
  @override
  Future<void> writeMe(String json) async => me = json;
  @override
  Future<void> clear() async {
    tokens = null;
    me = null;
  }
}

class _ScriptedApi extends ClubApiClient {
  final Future<Map<String, dynamic>> Function() script;
  final localeCalls = <(String, String)>[];
  _ScriptedApi(super.session, this.script);

  @override
  Future<Map<String, dynamic>> me() => script();

  @override
  Future<void> setLocale(String userKey, String locale) async => localeCalls.add((userKey, locale));
}

class _JsonAdapter implements HttpClientAdapter {
  final int status;
  final Map<String, dynamic> body;
  _JsonAdapter(this.status, this.body);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
          Future<void>? cancelFuture) async =>
      ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: ['application/json'],
      });

  @override
  void close({bool force = false}) {}
}

final _tokens = AuthTokens(
  accessToken: 'a',
  tokenType: 'Bearer',
  refreshToken: 'r',
  expiresAt: DateTime(2030),
);

Map<String, dynamic> _meJson({String? locale}) => {
      'user': {'public_sqid': 'u1', 'user_key': 'k1', 'handle': 'pat', 'locale': locale},
      'roles': const <String>[],
      'capabilities': const <String, dynamic>{},
      'quotas': const <String, dynamic>{},
      'needs_welcome': false,
    };
