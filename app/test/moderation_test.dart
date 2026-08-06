// Unit tests for the in-app moderation features (SPEC-CLUB C6): model parsing
// and pure logic. Runs without the engine binary or network, like all Dart tests.
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/club/models/comment.dart';
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

  group('Comment hidden_by_mod', () {
    test('parses and survives markDeleted/withReplies copies', () {
      final c = Comment.fromJson({
        'id': 'c1',
        'body': 'hi',
        'hidden_by_mod': true,
      });
      expect(c.hiddenByMod, isTrue);
      expect(c.deleted, isFalse);
      expect(c.markDeleted().hiddenByMod, isTrue);
      expect(c.withReplies(const []).hiddenByMod, isTrue);
    });

    test('defaults to false when omitted (public payloads)', () {
      expect(Comment.fromJson({'id': 'c2', 'body': 'x'}).hiddenByMod, isFalse);
    });
  });
}
