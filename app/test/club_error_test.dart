import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/models/club_error.dart';

void main() {
  group('ClubError.fromBody', () {
    test('parses the v1 envelope', () {
      final e = ClubError.fromBody(409, {
        'error': {'code': 'artwork_duplicate', 'message': 'Already exists.'}
      });
      expect(e.status, 409);
      expect(e.code, 'artwork_duplicate');
      expect(e.message, 'Already exists.');
    });

    test('parses the FastAPI detail shape', () {
      final e = ClubError.fromBody(422, {'detail': 'Validation failed'});
      expect(e.code, 'error');
      expect(e.message, 'Validation failed');
    });

    test('isAuth / isRateLimited flags', () {
      expect(ClubError.fromBody(401, const {}).isAuth, isTrue);
      expect(ClubError.fromBody(429, const {}).isRateLimited, isTrue);
      expect(ClubError.fromBody(200, const {}).isAuth, isFalse);
    });
  });
}
