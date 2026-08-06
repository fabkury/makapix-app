// Unit tests for the in-app moderation features (SPEC-CLUB C6): model parsing
// and pure logic. Runs without the engine binary or network, like all Dart tests.
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/club/models/post.dart';

void main() {
  group('Post moderation fields', () {
    Map<String, dynamic> basePost() => {
          'id': 7,
          'public_sqid': 'aB3x',
          'title': 'x',
          'width': 32,
          'height': 32,
          'frame_count': 1,
          'owner': {'handle': 'fab', 'public_sqid': 'u1', 'user_key': 'k'},
        };

    test('default to safe values when the server omits them', () {
      final p = Post.fromJson(basePost());
      expect(p.hiddenByMod, isFalse);
      expect(p.publicVisibility, isFalse);
      expect(p.promoted, isFalse);
      expect(p.promotedCategory, isNull);
    });

    test('parse the moderation state', () {
      final p = Post.fromJson({
        ...basePost(),
        'hidden_by_mod': true,
        'hidden_by_user': true,
        'public_visibility': true,
        'promoted': true,
        'promoted_category': 'frontpage',
      });
      expect(p.hiddenByMod, isTrue);
      expect(p.hiddenByUser, isTrue);
      expect(p.publicVisibility, isTrue);
      expect(p.promoted, isTrue);
      expect(p.promotedCategory, 'frontpage');
    });
  });
}
