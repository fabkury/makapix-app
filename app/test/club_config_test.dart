import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/config/club_config.dart';

void main() {
  group('resolveClubUrl', () {
    test('passes absolute URLs through untouched', () {
      const abs = 'https://cdn.example.com/a.png';
      expect(resolveClubUrl(abs), abs);
      expect(resolveClubUrl('http://x/y.png'), 'http://x/y.png');
    });

    test('prefixes relative paths with the API origin', () {
      final base = ClubConfig.defaultConfig.baseUrl;
      expect(resolveClubUrl('/api/vault/avatar/u/42.png'),
          '$base/api/vault/avatar/u/42.png');
    });
  });
}
