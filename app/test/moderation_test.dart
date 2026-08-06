// Unit tests for the in-app moderation features (SPEC-CLUB C6): model parsing
// and pure logic. Runs without the engine binary or network, like all Dart tests.
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/club/models/comment.dart';
import 'package:makapix_club/club/models/post.dart';
import 'package:makapix_club/club/models/umd.dart';

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

  group('UmdUserData', () {
    test('parses the full manage payload', () {
      final u = UmdUserData.fromJson({
        'id': 42,
        'user_key': 'uuid-1',
        'public_sqid': 'aB3x',
        'handle': 'artist',
        'avatar_url': null,
        'reputation': 120,
        'badges': [
          {'badge': 'early-bird', 'granted_at': '2026-01-01T00:00:00Z'},
        ],
        'auto_public_approval': true,
        'hidden_by_mod': false,
        'banned_until': null,
        'roles': ['user'],
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(u.sqid, 'aB3x');
      expect(u.reputation, 120);
      expect(u.badges, ['early-bird']);
      expect(u.autoPublicApproval, isTrue);
      expect(u.isBanned, isFalse);
      expect(u.isPermanentlyBanned, isFalse);
    });

    test('reads the year-9999 sentinel as a permanent ban', () {
      final u = UmdUserData.fromJson({
        'id': 1,
        'user_key': 'k',
        'public_sqid': 's',
        'handle': 'h',
        'reputation': 0,
        'auto_public_approval': false,
        'hidden_by_mod': false,
        'banned_until': '9999-12-31T23:59:59Z',
      });
      expect(u.isBanned, isTrue);
      expect(u.isPermanentlyBanned, isTrue);
    });

    test('an expired temporary ban reads as not banned', () {
      final u = UmdUserData.fromJson({
        'id': 1,
        'user_key': 'k',
        'public_sqid': 's',
        'handle': 'h',
        'reputation': 0,
        'auto_public_approval': false,
        'hidden_by_mod': false,
        'banned_until': '2020-01-01T00:00:00Z',
      });
      expect(u.isBanned, isFalse);
    });
  });
}
