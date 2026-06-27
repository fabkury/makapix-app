import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/models/auth_tokens.dart';

void main() {
  final now = DateTime.utc(2026, 1, 1, 12);

  group('AuthTokens', () {
    test('fromJson maps fields and computes expiresAt', () {
      final t = AuthTokens.fromJson({
        'access_token': 'a',
        'token_type': 'Bearer',
        'refresh_token': 'r',
        'expires_in': 3600,
      }, now: now);
      expect(t.accessToken, 'a');
      expect(t.refreshToken, 'r');
      expect(t.tokenType, 'Bearer');
      expect(t.expiresAt, now.add(const Duration(seconds: 3600)));
    });

    test('isExpired honors skew', () {
      final t = AuthTokens(
        accessToken: 'a',
        tokenType: 'Bearer',
        refreshToken: 'r',
        expiresAt: now.add(const Duration(seconds: 20)),
      );
      expect(t.isExpired(now: now, skew: const Duration(seconds: 30)), isTrue);
      expect(t.isExpired(now: now, skew: const Duration(seconds: 5)), isFalse);
    });

    test('storage round-trip', () {
      final t = AuthTokens.fromJson(
          {'access_token': 'a', 'refresh_token': 'r', 'expires_in': 60}, now: now);
      final back = AuthTokens.fromStorage(t.toStorage());
      expect(back, isNotNull);
      expect(back!.accessToken, 'a');
      expect(back.refreshToken, 'r');
      expect(back.expiresAt, t.expiresAt);
    });

    test('fromStorage returns null when fields are missing', () {
      expect(AuthTokens.fromStorage({'access_token': 'a'}), isNull);
    });
  });
}
