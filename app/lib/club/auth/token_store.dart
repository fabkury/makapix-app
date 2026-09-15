import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/auth_tokens.dart';

/// Persists [AuthTokens] in platform secure storage (Android Keystore /
/// iOS Keychain / Windows credential store), plus the cached identity: the raw JSON of the
/// last successful `GET /auth/me`, so a cold start can enter the signed-in state before (or
/// without) the network. It lives beside the tokens because it carries the email and the
/// roles, and it is cleared with them — one code path, no orphaned identity.
class SecureTokenStore {
  static const _prefix = 'club.';
  static const _keys = ['access_token', 'token_type', 'refresh_token', 'expires_at'];
  static const _meKey = '${_prefix}me_json';

  final FlutterSecureStorage _s;
  SecureTokenStore([FlutterSecureStorage? s]) : _s = s ?? const FlutterSecureStorage();

  Future<AuthTokens?> read() async {
    final m = <String, String?>{};
    for (final k in _keys) {
      m[k] = await _s.read(key: '$_prefix$k');
    }
    return AuthTokens.fromStorage(m);
  }

  Future<void> write(AuthTokens t) async {
    final m = t.toStorage();
    for (final e in m.entries) {
      await _s.write(key: '$_prefix${e.key}', value: e.value);
    }
  }

  /// The cached `/auth/me` JSON, or null when never cached (or cleared).
  Future<String?> readMe() => _s.read(key: _meKey);

  Future<void> writeMe(String json) => _s.write(key: _meKey, value: json);

  /// Clears the tokens AND the cached identity.
  Future<void> clear() async {
    for (final k in _keys) {
      await _s.delete(key: '$_prefix$k');
    }
    await _s.delete(key: _meKey);
  }
}
