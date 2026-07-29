// Website-parity batch (docs/club-gap/INVENTORY.md A1/A2/A3): pure logic for
// single-post management, per-post stats, and the follow lists.
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/club/models/post.dart';
import 'package:makapix_club/club/models/post_stats.dart';
import 'package:makapix_club/club/ui/edit_post_details_page.dart';

void main() {
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
