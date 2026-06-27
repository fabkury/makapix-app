import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/auth_tokens.dart';

/// Persists [AuthTokens] in platform secure storage (Android Keystore /
/// iOS Keychain / Windows credential store).
class SecureTokenStore {
  static const _prefix = 'club.';
  static const _keys = ['access_token', 'token_type', 'refresh_token', 'expires_at'];

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

  Future<void> clear() async {
    for (final k in _keys) {
      await _s.delete(key: '$_prefix$k');
    }
  }
}
