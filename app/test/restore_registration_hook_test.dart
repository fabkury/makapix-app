import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/auth/club_session.dart';
import 'package:makapix_club/club/auth/token_store.dart';
import 'package:makapix_club/club/config/club_config.dart';
import 'package:makapix_club/club/models/auth_tokens.dart';

/// Zero-Tap Sign-In: *when* the restore credential gets registered.
///
/// Regression guard for the orphan-row defect found in production testing (server message 0007).
/// Credential Manager mints a NEW credential on every call, so `credential_id` differs each time
/// and the server's upsert never fires — it inserts. Android keeps one restore key per app per
/// device, so every superfluous registration permanently orphans the previous row. Registering on
/// each app launch produced one dead row per launch, forever.
///
/// The hook therefore lives on ClubSession._grant, which is the single funnel every sign-in passes
/// through (RegistrationController and the email-OTP verify flow call loginPassword on the session
/// directly, bypassing AuthController). These tests pin which grants fire it.

class _FakeAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
          Future<void>? cancelFuture) async =>
      ResponseBody.fromString(
        '{"access_token":"a","token_type":"Bearer","refresh_token":"r","expires_in":3600}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        },
      );

  @override
  void close({bool force = false}) {}
}

/// Token store that keeps everything in memory — no secure storage, no platform channel.
/// Extends rather than implements: SecureTokenStore holds a private field, which an
/// `implements` from another library cannot satisfy. All three methods are overridden, so the
/// inherited FlutterSecureStorage is never touched.
class _MemoryStore extends SecureTokenStore {
  AuthTokens? _t;
  @override
  Future<AuthTokens?> read() async => _t;
  @override
  Future<void> write(AuthTokens t) async => _t = t;
  @override
  Future<void> clear() async => _t = null;
}

ClubSession _session() {
  final dio = Dio(BaseOptions(baseUrl: ClubConfig.defaultConfig.apiBase))
    ..httpClientAdapter = _FakeAdapter();
  return ClubSession(config: ClubConfig.defaultConfig, store: _MemoryStore(), dio: dio);
}

void main() {
  test('an interactive password sign-in registers exactly once', () async {
    var fired = 0;
    final s = _session()..onInteractiveSignIn = () => fired++;

    await s.loginPassword('a@b.c', 'pw');
    expect(fired, 1);
  });

  test('the GitHub authorization_code exchange registers', () async {
    var fired = 0;
    final s = _session()..onInteractiveSignIn = () => fired++;

    await s.exchangeAuthCode('code', 'verifier');
    expect(fired, 1);
  });

  test('Sign in with Apple registers', () async {
    var fired = 0;
    final s = _session()..onInteractiveSignIn = () => fired++;

    await s.loginApple(identityToken: 'jwt', rawNonce: 'n');
    expect(fired, 1);
  });

  test('a token refresh does NOT register — it would orphan a row on every rotation', () async {
    var fired = 0;
    final s = _session()..onInteractiveSignIn = () => fired++;

    await s.loginPassword('a@b.c', 'pw'); // establishes a refresh token
    fired = 0;

    expect(await s.refresh(), isTrue);
    expect(fired, 0);
  });

  test('a Zero-Tap restore does NOT re-register the credential it just used', () async {
    var fired = 0;
    final s = _session()..onInteractiveSignIn = () => fired++;

    await s.loginRestoreCredential('{"id":"cred-1"}');
    expect(fired, 0);
  });

  test('reloading tokens from storage at launch does not register', () async {
    final store = _MemoryStore();
    final dio = Dio(BaseOptions(baseUrl: ClubConfig.defaultConfig.apiBase))
      ..httpClientAdapter = _FakeAdapter();
    final first = ClubSession(config: ClubConfig.defaultConfig, store: store, dio: dio);
    await first.loginPassword('a@b.c', 'pw');

    // A fresh launch: same persisted store, new session object.
    var fired = 0;
    final relaunched = ClubSession(config: ClubConfig.defaultConfig, store: store, dio: dio)
      ..onInteractiveSignIn = () => fired++;
    await relaunched.load();

    expect(relaunched.isSignedIn, isTrue);
    expect(fired, 0, reason: 'the orphan-row defect: every launch used to mint a new credential');
  });
}
