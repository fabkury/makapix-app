// Website-parity batch (docs/club-gap/INVENTORY.md A1/A2/A3): pure logic for
// single-post management, per-post stats, and the follow lists.
import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/club/models/feed_filters.dart';
import 'package:makapix_club/club/models/post.dart';
import 'package:makapix_club/club/models/post_stats.dart';
import 'package:makapix_club/club/ui/edit_post_details_page.dart';
import 'package:makapix_club/club/ui/widgets/markdown_bio.dart';

void main() {
  group('parseBioMarkdown (website MarkdownBio parity)', () {
    test('plain text passes through as one segment', () {
      final s = parseBioMarkdown('hello world');
      expect(s.length, 1);
      expect(s.single.type, 'text');
      expect(s.single.text, 'hello world');
    });

    test('bold, italic, code, link, color', () {
      final s = parseBioMarkdown(
          'a *i* **b** `c` [l](https://x.example) [r]{color:red} z');
      expect(s.map((e) => e.type).toList(),
          ['text', 'italic', 'text', 'bold', 'text', 'code', 'text', 'link', 'text', 'color', 'text']);
      expect(s[7].url, 'https://x.example');
      expect(s[9].color, const Color(0xFFFF0000));
    });

    test('QUIRK (website parity): italic right after bold is lost', () {
      // The italic regex's own non-overlapping scan eats "* *" between the
      // bold closer and the italic opener, so `**b** *i*` renders the italic
      // as literal text — exactly like MarkdownBio.tsx. Locked in on purpose:
      // change this only together with the website.
      final s = parseBioMarkdown('**b** *i*');
      expect(s.map((e) => e.type).toList(), ['bold', 'text']);
      expect(s[1].text, ' *i*');
    });

    test('bold wins over italic at the same site', () {
      final s = parseBioMarkdown('**strong**');
      expect(s.single.type, 'bold');
      expect(s.single.text, 'strong');
    });

    test('color pattern wins over link at the same start', () {
      final s = parseBioMarkdown('[x]{color:#ff0000}');
      expect(s.single.type, 'color');
      expect(s.single.color, const Color(0xFFFF0000));
    });

    test('invalid color renders as plain text', () {
      final s = parseBioMarkdown('[x]{color:url(evil)}');
      expect(s.single.type, 'text');
      expect(s.single.text, '[x]{color:url(evil)}');
    });

    test('non-http link renders as plain text (stricter than the website)', () {
      final s = parseBioMarkdown('[x](javascript:alert(1)');
      expect(s.every((e) => e.type != 'link'), isTrue);
      final s2 = parseBioMarkdown('[x](ftp://host/file)');
      expect(s2.single.type, 'text');
    });

    test('#rgb shorthand expands', () {
      expect(parseBioColor('#f00'), const Color(0xFFFF0000));
      expect(parseBioColor('#0f0'), const Color(0xFF00FF00));
      expect(parseBioColor('not-a-color'), isNull);
    });

    test('newlines survive inside plain segments', () {
      final s = parseBioMarkdown('line1\nline2');
      expect(s.single.text, 'line1\nline2');
    });
  });

  group('EditPostDetailsPage.parseHashtags', () {
    test('trims, lowercases, strips #, drops empties and duplicates', () {
      expect(
        EditPostDetailsPage.parseHashtags(' #PixelArt, fantasy ,, FANTASY, #8bit '),
        ['pixelart', 'fantasy', '8bit'],
      );
    });

    test('empty input → empty list', () {
      expect(EditPostDetailsPage.parseHashtags('   '), isEmpty);
      expect(EditPostDetailsPage.parseHashtags(''), isEmpty);
    });

    test('a lone # is dropped', () {
      expect(EditPostDetailsPage.parseHashtags('#, #x'), ['x']);
    });
  });

  group('FeedFilters (website FilterButton parity)', () {
    test('defaults are default and produce the bare sort query', () {
      const f = FeedFilters();
      expect(f.isDefault, isTrue);
      expect(f.toQuery(), {'sort': 'created_at', 'order': 'desc'});
    });

    test('both kinds selected equals none (still default)', () {
      const f = FeedFilters(kinds: {'static', 'animated'});
      expect(f.isDefault, isTrue);
      expect(f.toQuery().containsKey('kind'), isFalse);
      const one = FeedFilters(kinds: {'animated'});
      expect(one.isDefault, isFalse);
      expect(one.toQuery()['kind'], ['animated']);
    });

    test('base and size split their 128+ variants into *_gte', () {
      const f = FeedFilters(base: 128, sizes: {16, 128, 64});
      final q = f.toQuery();
      expect(q['base_gte'], 128);
      expect(q.containsKey('base'), isFalse);
      expect(q['size'], [16, 64]);
      expect(q['size_gte'], 128);
    });

    test('small base goes as a list value', () {
      expect(const FeedFilters(base: 32).toQuery()['base'], [32]);
    });

    test('file-size bounds only appear when they actually bound', () {
      const unbounded = FeedFilters(fileBytesMin: 0, fileBytesMax: kFilterFileBytesCap);
      expect(unbounded.isDefault, isTrue);
      expect(unbounded.toQuery().containsKey('file_bytes_min'), isFalse);
      const bounded = FeedFilters(fileBytesMin: 1024, fileBytesMax: 2048);
      final q = bounded.toQuery();
      expect(q['file_bytes_min'], 1024);
      expect(q['file_bytes_max'], 2048);
      expect(bounded.isDefault, isFalse);
    });

    test('value equality ignores set ordering', () {
      const a = FeedFilters(sizes: {8, 64}, kinds: {'static'});
      const b = FeedFilters(sizes: {64, 8}, kinds: {'static'});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == const FeedFilters(sizes: {8}), isFalse);
    });
  });

  group('Post.hiddenByUser', () {
    test('parses hidden_by_user and defaults to false', () {
      final hidden = Post.fromJson({'id': 1, 'hidden_by_user': true});
      final visible = Post.fromJson({'id': 2});
      expect(hidden.hiddenByUser, isTrue);
      expect(visible.hiddenByUser, isFalse);
    });
  });

  group('PostStats.fromJson', () {
    test('parses dual metrics, breakdowns, and the daily trend', () {
      final s = PostStats.fromJson({
        'post_id': 7,
        'total_views': 100,
        'unique_viewers': 40,
        'views_by_country': {'US': 60, 'BR': 40},
        'views_by_device': {'mobile': 70, 'desktop': 30},
        'views_by_type': {'intentional': 90, 'listing': 10},
        'daily_views': [
          {'date': '2026-07-28', 'views': 5, 'unique_viewers': 3},
        ],
        'total_reactions': 12,
        'reactions_by_emoji': {'👍': 8, '❤️': 4},
        'total_comments': 3,
        'total_views_authenticated': 50,
        'unique_viewers_authenticated': 20,
        'views_by_country_authenticated': {'US': 50},
        'views_by_device_authenticated': {'mobile': 50},
        'views_by_type_authenticated': {'intentional': 50},
        'daily_views_authenticated': [
          {'date': '2026-07-28', 'views': 2, 'unique_viewers': 1},
        ],
        'total_reactions_authenticated': 6,
        'reactions_by_emoji_authenticated': {'👍': 6},
        'total_comments_authenticated': 2,
        'computed_at': '2026-07-29T12:00:00Z',
      });
      expect(s.postId, 7);
      // The authenticated-only toggle flips every accessor.
      expect(s.views(false), 100);
      expect(s.views(true), 50);
      expect(s.countries(false), {'US': 60, 'BR': 40});
      expect(s.countries(true), {'US': 50});
      expect(s.daily(false).single.views, 5);
      expect(s.daily(true).single.uniqueViewers, 1);
      expect(s.emoji(true), {'👍': 6});
      expect(s.computedAt, isNotNull);
      expect(s.firstViewAt, isNull);
    });

    test('tolerates a minimal payload', () {
      final s = PostStats.fromJson({'post_id': 1});
      expect(s.views(false), 0);
      expect(s.daily(true), isEmpty);
      expect(s.types(false), isEmpty);
    });
  });
}
