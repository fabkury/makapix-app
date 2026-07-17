import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/api/player_api.dart';

void main() {
  group('normalizeRegistrationCode', () {
    test('uppercases and strips non-alphanumerics', () {
      expect(normalizeRegistrationCode('a3f8x2'), 'A3F8X2');
      expect(normalizeRegistrationCode('a3-f8 x2'), 'A3F8X2');
      expect(normalizeRegistrationCode('  a3f8x2  '), 'A3F8X2');
    });

    test('caps at 6 characters', () {
      expect(normalizeRegistrationCode('ABC234EXTRA'), 'ABC234');
    });

    test('drops symbols and accents, keeping only [A-Z0-9]', () {
      expect(normalizeRegistrationCode('a!b@c#2'), 'ABC2');
      expect(normalizeRegistrationCode('éàü12'), '12');
    });

    test('empty stays empty', () {
      expect(normalizeRegistrationCode(''), '');
      expect(normalizeRegistrationCode('----'), '');
    });
  });
}
