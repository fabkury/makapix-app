import 'package:dio/dio.dart';

import '../config/club_config.dart';
import '../models/auth_tokens.dart';
import '../models/club_error.dart';
import 'token_store.dart';

/// Owns the token lifecycle: in-memory [AuthTokens] + secure persistence, and the
/// `/auth/token` grant calls (password / authorization_code / refresh_token).
///
/// Uses a *plain* Dio (no interceptors) for grants so a refresh triggered by the
/// authed client's 401 handler can never recurse. Refresh is single-flight.
class ClubSession {
  final ClubConfig config;
  final SecureTokenStore store;
  final Dio _dio;

  AuthTokens? _tokens;
  Future<bool>? _refreshing;

  ClubSession({required this.config, SecureTokenStore? store, Dio? dio})
      : store = store ?? SecureTokenStore(),
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: config.apiBase,
              contentType: 'application/json',
              connectTimeout: ClubConfig.connectTimeout, // [audit F-7]
              receiveTimeout: ClubConfig.ioTimeout,
              sendTimeout: ClubConfig.ioTimeout,
            ));

  AuthTokens? get tokens => _tokens;
  String? get accessToken => _tokens?.accessToken;
  bool get isSignedIn => _tokens != null;

  /// Invoked when the session is invalidated involuntarily — a background refresh failed and the
  /// tokens were cleared. The auth controller listens so the UI flips to signed-out instead of
  /// rendering as signed-in with no token (a "zombie" session). [audit F-4b]
  void Function()? onSessionInvalidated;

  /// Load persisted tokens into memory (call once at startup).
  Future<void> load() async {
    _tokens = await store.read();
  }

  Future<AuthTokens> _grant(Map<String, dynamic> body) async {
    try {
      final resp = await _dio.post('/auth/token', data: body);
      final data = (resp.data as Map).cast<String, dynamic>();
      final tokens = AuthTokens.fromJson(data);
      _tokens = tokens;
      await store.write(tokens);
      return tokens;
    } on DioException catch (e) {
      throw ClubError.fromDio(e);
    } catch (_) {
      throw ClubError(code: 'parse_error', message: 'Unexpected token response from the server.');
    }
  }

  Future<AuthTokens> loginPassword(String email, String password) =>
      _grant({'grant_type': 'password', 'email': email, 'password': password});

  Future<AuthTokens> exchangeAuthCode(String code, String codeVerifier) =>
      _grant({'grant_type': 'authorization_code', 'code': code, 'code_verifier': codeVerifier});

  /// Single-flight refresh. Returns false (and clears tokens) on failure so the
  /// caller can route to signed-out.
  Future<bool> refresh() {
    final inflight = _refreshing;
    if (inflight != null) return inflight;
    final rt = _tokens?.refreshToken;
    if (rt == null) return Future.value(false);
    final fut = _doRefresh(rt).whenComplete(() => _refreshing = null);
    _refreshing = fut;
    return fut;
  }

  Future<bool> _doRefresh(String refreshToken) async {
    try {
      await _grant({'grant_type': 'refresh_token', 'refresh_token': refreshToken});
      return true;
    } on ClubError {
      await clear();
      // Tell the auth controller the session died under it (it can't observe `clear()`). [F-4b]
      onSessionInvalidated?.call();
      return false;
    }
  }

  Future<void> clear() async {
    _tokens = null;
    await store.clear();
  }

  /// Local sign-out. Server-side revoke-by-body is pending brief §3.6; the
  /// cookie-based `/auth/logout` doesn't apply to our body-delivered refresh token.
  Future<void> logout() => clear();
}
