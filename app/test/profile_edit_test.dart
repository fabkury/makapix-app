import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/edit/profile_edit.dart';
import 'package:makapix_club/club/models/user_profile.dart';

UserProfile _profile({String? tagline, String? bio}) => UserProfile.fromJson({
      'user_key': '00000000-0000-0000-0000-000000000001',
      'public_sqid': 'AbCd',
      'handle': 'tester',
      'tagline': tagline,
      'bio': bio,
    });

void main() {
  group('buildProfilePatch', () {
    test('unchanged fields produce an empty patch', () {
      final p = _profile(tagline: 'hi', bio: 'my bio');
      expect(buildProfilePatch(p, tagline: 'hi', bio: 'my bio'), isEmpty);
    });

    test('tagline-only change patches only tagline', () {
      final p = _profile(tagline: 'old', bio: 'same');
      expect(buildProfilePatch(p, tagline: 'new', bio: 'same'), {'tagline': 'new'});
    });

    test('clearing a set bio sends an empty string', () {
      final p = _profile(tagline: 't', bio: 'something');
      expect(buildProfilePatch(p, tagline: 't', bio: ''), {'bio': ''});
    });

    test('whitespace-only edits trim to unchanged', () {
      final p = _profile(tagline: 'hi', bio: 'my bio');
      expect(buildProfilePatch(p, tagline: '  hi ', bio: 'my bio\n'), isEmpty);
    });

    test('null baseline and emptied field are equivalent (no patch)', () {
      final p = _profile(tagline: null, bio: null);
      expect(buildProfilePatch(p, tagline: '', bio: '  '), isEmpty);
    });

    test('setting a field over a null baseline patches it', () {
      final p = _profile(tagline: null, bio: null);
      expect(buildProfilePatch(p, tagline: 'fresh', bio: ''), {'tagline': 'fresh'});
    });
  });

  group('validateCodePointLength', () {
    test('accepts at the limit', () {
      expect(validateCodePointLength('a' * 48, kTaglineMaxCodePoints, 'Tagline'), isNull);
    });

    test('rejects over the limit', () {
      expect(validateCodePointLength('a' * 49, kTaglineMaxCodePoints, 'Tagline'), isNotNull);
    });

    test('counts code points, not graphemes (emoji tagline)', () {
      // 25 flag emoji = 25 graphemes but 50 code points (regional-indicator pairs).
      final flags = '\u{1F1E7}\u{1F1F7}' * 25;
      expect(validateCodePointLength(flags, kTaglineMaxCodePoints, 'Tagline'), isNotNull);
    });

    test('trims before counting', () {
      expect(validateCodePointLength('${'a' * 48}   ', kTaglineMaxCodePoints, 'Tagline'), isNull);
    });
  });
}
