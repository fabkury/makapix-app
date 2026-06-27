/// OAuth2-style token set returned by `POST /api/v1/auth/token` (all grants).
class AuthTokens {
  final String accessToken;
  final String tokenType; // "Bearer"
  final String refreshToken;
  final DateTime expiresAt;

  AuthTokens({
    required this.accessToken,
    required this.tokenType,
    required this.refreshToken,
    required this.expiresAt,
  });

  /// Parse a token response. `expiresAt` = [now] (default DateTime.now()) +
  /// `expires_in` seconds. `now` is injectable for deterministic tests.
  factory AuthTokens.fromJson(Map<String, dynamic> j, {DateTime? now}) {
    final expiresIn = (j['expires_in'] as num?)?.toInt() ?? 3600;
    return AuthTokens(
      accessToken: j['access_token'] as String,
      tokenType: (j['token_type'] as String?) ?? 'Bearer',
      refreshToken: j['refresh_token'] as String,
      expiresAt: (now ?? DateTime.now()).add(Duration(seconds: expiresIn)),
    );
  }

  /// True when the access token is within [skew] of expiry (proactive refresh).
  bool isExpired({Duration skew = const Duration(seconds: 30), DateTime? now}) =>
      (now ?? DateTime.now()).isAfter(expiresAt.subtract(skew));

  Map<String, String> toStorage() => {
        'access_token': accessToken,
        'token_type': tokenType,
        'refresh_token': refreshToken,
        'expires_at': expiresAt.toIso8601String(),
      };

  static AuthTokens? fromStorage(Map<String, String?> m) {
    final a = m['access_token'], r = m['refresh_token'], e = m['expires_at'];
    if (a == null || r == null || e == null) return null;
    final exp = DateTime.tryParse(e);
    if (exp == null) return null;
    return AuthTokens(
      accessToken: a,
      tokenType: m['token_type'] ?? 'Bearer',
      refreshToken: r,
      expiresAt: exp,
    );
  }
}
