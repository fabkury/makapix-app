// The optimistic cold start (offline-editor reachability, ADR 0035): an install with tokens
// enters the signed-in state from the cached `/auth/me` BEFORE the network answers, keeps it
// (flagged) when the server can't be reached, drops the cache with the tokens on a 401, and
// refreshes the cache on every successful revalidation. A cached moderator role never unlocks
// moderation until the server has confirmed it.
//
// No flutter_secure_storage and no Dio/network: the store is an in-memory fake and `/auth/me`
// is scripted per test.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/club/api/club_api_client.dart';
import 'package:makapix_club/club/auth/club_session.dart';
import 'package:makapix_club/club/auth/github_oauth.dart';
import 'package:makapix_club/club/auth/token_store.dart';
import 'package:makapix_club/club/config/club_config.dart';
import 'package:makapix_club/club/models/auth_tokens.dart';
import 'package:makapix_club/club/models/club_error.dart';
import 'package:makapix_club/club/state/auth_controller.dart';

class _MemoryStore extends SecureTokenStore {
  AuthTokens? tokens;
  String? me;
  _MemoryStore({this.tokens, this.me});

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

/// `/auth/me` scripted per test: a JSON answer, or a thrown [ClubError].
class _ScriptedApi extends ClubApiClient {
  final Future<Map<String, dynamic>> Function() script;
  int calls = 0;
  _ScriptedApi(super.session, this.script);

  @override
  Future<Map<String, dynamic>> me() {
    calls++;
    return script();
  }
}

final _tokens = AuthTokens(
  accessToken: 'a',
  tokenType: 'Bearer',
  refreshToken: 'r',
  expiresAt: DateTime(2030),
);

Map<String, dynamic> _meJson({String handle = 'pat', List<String> roles = const []}) => {
      'user': {'public_sqid': 'u1', 'user_key': 'k1', 'handle': handle},
      'roles': roles,
      'capabilities': {},
      'quotas': {},
      'needs_welcome': false,
    };

final _network = ClubError(code: 'network', message: 'No connection.');
final _unauthorized = ClubError(status: 401, code: 'unauthorized', message: 'Unauthorized.');

({AuthController auth, _MemoryStore store, _ScriptedApi api}) _rig({
  required _MemoryStore store,
  required Future<Map<String, dynamic>> Function() me,
}) {
  final cfg = ClubConfig.defaultConfig;
  final session = ClubSession(config: cfg, store: store);
  final api = _ScriptedApi(session, me);
  final auth = AuthController(session: session, api: api, oauth: GithubOAuth(cfg));
  return (auth: auth, store: store, api: api);
}

void main() {
  test('tokens + cache: signed in from the cache first, revalidated after', () async {
    final states = <AuthState>[];
    final r = _rig(
      store: _MemoryStore(tokens: _tokens, me: jsonEncode(_meJson(handle: 'cached'))),
      me: () async => _meJson(handle: 'fresh'),
    );
    r.auth.addListener(states.add, fireImmediately: false);
    await r.auth.init();

    // First the optimistic state (cached handle, stale), then the server's answer (fresh, not).
    final stale = states.firstWhere((s) => s.isSignedIn);
    expect(stale.stale, isTrue);
    expect(stale.me!.user.handle, 'cached');
    expect(r.auth.state.isSignedIn, isTrue);
    expect(r.auth.state.stale, isFalse);
    expect(r.auth.state.me!.user.handle, 'fresh');
    // The cache now holds the fresh identity for the next cold start.
    await Future<void>.delayed(Duration.zero);
    expect(jsonDecode(r.store.me!)['user']['handle'], 'fresh');
  });

  test('tokens + cache, server unreachable: stays signed in, flagged offline', () async {
    final r = _rig(
      store: _MemoryStore(tokens: _tokens, me: jsonEncode(_meJson(handle: 'cached'))),
      me: () async => throw _network,
    );
    await r.auth.init();

    final s = r.auth.state;
    expect(s.isSignedIn, isTrue, reason: 'the elevator case must not sign the user out');
    expect(s.stale, isTrue);
    expect(s.error, 'No connection.');
    expect(s.isOfflineSignedIn, isTrue);
    expect(r.store.tokens, isNotNull, reason: 'a network failure never clears tokens');
    expect(r.store.me, isNotNull);
  });

  test('tokens + cache, 401: signed out, cache dropped with the tokens', () async {
    final r = _rig(
      store: _MemoryStore(tokens: _tokens, me: jsonEncode(_meJson())),
      me: () async => throw _unauthorized,
    );
    await r.auth.init();

    expect(r.auth.state.status, AuthStatus.signedOut);
    expect(r.store.tokens, isNull);
    expect(r.store.me, isNull, reason: 'the identity must not outlive the tokens');
  });

  test('tokens, no cache, server unreachable: the plain failure (today\'s path)', () async {
    final r = _rig(
      store: _MemoryStore(tokens: _tokens),
      me: () async => throw _network,
    );
    await r.auth.init();

    expect(r.auth.state.status, AuthStatus.error);
    expect(r.auth.state.isSignedIn, isFalse);
  });

  test('a corrupt cache is ignored, not fatal', () async {
    final r = _rig(
      store: _MemoryStore(tokens: _tokens, me: '{not json'),
      me: () async => _meJson(handle: 'fresh'),
    );
    await r.auth.init();
    expect(r.auth.state.isSignedIn, isTrue);
    expect(r.auth.state.me!.user.handle, 'fresh');
  });

  test('a cached moderator role unlocks nothing until revalidated', () async {
    final r = _rig(
      store: _MemoryStore(tokens: _tokens, me: jsonEncode(_meJson(roles: ['moderator']))),
      me: () async => throw _network,
    );
    final c = ProviderContainer(overrides: [
      authControllerProvider.overrideWith((ref) => r.auth),
    ]);
    addTearDown(c.dispose);
    await r.auth.init();

    expect(r.auth.state.me!.canModerate, isTrue, reason: 'the cached role itself is intact');
    expect(c.read(isModeratorProvider), isFalse, reason: 'stale identity: moderation stays hidden');
  });

  test('a revalidated moderator role unlocks moderation', () async {
    final r = _rig(
      store: _MemoryStore(tokens: _tokens, me: jsonEncode(_meJson(roles: ['moderator']))),
      me: () async => _meJson(roles: ['moderator']),
    );
    final c = ProviderContainer(overrides: [
      authControllerProvider.overrideWith((ref) => r.auth),
    ]);
    addTearDown(c.dispose);
    await r.auth.init();
    expect(c.read(isModeratorProvider), isTrue);
  });
}
