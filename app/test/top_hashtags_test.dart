import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/api/search_api.dart';

/// The `/hashtags/top` response parser that backs the home trending-hashtag bar.
/// The server sends `{ "hashtags": [...], "cached_until": ... }`; we only read
/// the bare tag list and parse it defensively.
void main() {
  group('parseTopHashtags', () {
    test('extracts the tag list from the real response shape', () {
      final data = {
        'hashtags': ['pixelart', 'cat', 'retro', '8bit'],
        'cached_until': '2026-07-17T14:32:10.123456+00:00',
      };
      expect(parseTopHashtags(data), ['pixelart', 'cat', 'retro', '8bit']);
    });

    test('empty list stays empty', () {
      expect(parseTopHashtags({'hashtags': <String>[]}), isEmpty);
    });

    test('missing hashtags key → empty', () {
      expect(parseTopHashtags({'cached_until': 'x'}), isEmpty);
    });

    test('non-map / null payloads → empty, no throw', () {
      expect(parseTopHashtags(null), isEmpty);
      expect(parseTopHashtags('oops'), isEmpty);
      expect(parseTopHashtags(42), isEmpty);
    });

    test('accepts a bare list and drops blank entries', () {
      expect(parseTopHashtags(['a', '', 'b']), ['a', 'b']);
    });

    test('coerces non-string entries', () {
      expect(parseTopHashtags({'hashtags': [1, 'two']}), ['1', 'two']);
    });
  });
}
