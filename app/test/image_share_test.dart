import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/share/image_share.dart';

void main() {
  group('shareCaption', () {
    test('title + url when both present', () {
      expect(shareCaption('My Art', 'https://makapix.club/p/abc'), '"My Art" — https://makapix.club/p/abc');
    });
    test('url only when title empty', () {
      expect(shareCaption('  ', 'https://makapix.club/p/abc'), 'https://makapix.club/p/abc');
    });
    test('title only when url missing', () {
      expect(shareCaption('My Art', null), 'My Art');
      expect(shareCaption('My Art', ''), 'My Art');
    });
    test('empty when neither present', () {
      expect(shareCaption('', null), '');
    });
  });

  group('sanitizeShareFilename', () {
    test('keeps safe chars, replaces the rest with underscores', () {
      expect(sanitizeShareFilename('Hello World!'), 'Hello_World');
      expect(sanitizeShareFilename('a/b:c*d'), 'a_b_c_d');
    });
    test('trims leading/trailing underscores', () {
      expect(sanitizeShareFilename('  spaced  '), 'spaced');
      expect(sanitizeShareFilename('***'), 'makapix');
    });
    test('falls back to makapix when empty', () {
      expect(sanitizeShareFilename(''), 'makapix');
      expect(sanitizeShareFilename('   '), 'makapix');
    });
    test('preserves unicode-free alnum with dashes/underscores', () {
      expect(sanitizeShareFilename('pixel-art_42'), 'pixel-art_42');
    });
  });
}
