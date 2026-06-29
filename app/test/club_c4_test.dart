import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/config/monitored_hashtags.dart';
import 'package:makapix_club/club/models/artist_stats.dart';
import 'package:makapix_club/club/models/club_user.dart';
import 'package:makapix_club/club/models/pmd.dart';
import 'package:makapix_club/club/state/pmd_providers.dart';

void main() {
  group('ClubUser (settings groundwork)', () {
    test('parses user_key and approved_hashtags', () {
      final u = ClubUser.fromJson({
        'public_sqid': 'abc123',
        'user_key': '11111111-2222-3333-4444-555555555555',
        'handle': 'pixel',
        'approved_hashtags': ['politics', 'nsfw'],
      });
      expect(u.sub, 'abc123');
      expect(u.userKey, '11111111-2222-3333-4444-555555555555');
      expect(u.approvedHashtags, ['politics', 'nsfw']);
    });

    test('defaults approved_hashtags to empty when absent', () {
      final u = ClubUser.fromJson({'public_sqid': 'x', 'handle': 'h'});
      expect(u.approvedHashtags, isEmpty);
      expect(u.userKey, '');
    });

    test('copyWith replaces only approved_hashtags', () {
      final u = ClubUser.fromJson({'public_sqid': 'x', 'user_key': 'k', 'handle': 'h'});
      final v = u.copyWith(approvedHashtags: ['violence']);
      expect(v.approvedHashtags, ['violence']);
      expect(v.userKey, 'k');
      expect(v.sub, 'x');
    });
  });

  group('monitored hashtags constant', () {
    test('mirrors the server set exactly', () {
      expect(kMonitoredHashtagTags, {'politics', 'nsfw', 'explicit', '13plus', 'violence'});
      expect(kMonitoredHashtags.length, 5);
    });

    test('tag set is derived from the labelled list', () {
      expect(kMonitoredHashtagTags, {for (final h in kMonitoredHashtags) h.tag});
    });
  });

  group('ArtistDashboard parsing', () {
    final json = {
      'artist_stats': {
        'total_posts': 12,
        'total_views': 3400,
        'unique_viewers': 900,
        'views_by_country': {'US': 200, 'BR': 150},
        'views_by_device': {'mobile': 220, 'desktop': 130},
        'total_reactions': 80,
        'reactions_by_emoji': {'❤️': 50, '😮': 30},
        'total_comments': 14,
        'total_views_authenticated': 1200,
        'unique_viewers_authenticated': 400,
        'views_by_country_authenticated': {'US': 100},
        'views_by_device_authenticated': {'mobile': 90},
        'total_reactions_authenticated': 40,
        'reactions_by_emoji_authenticated': {'❤️': 25},
        'total_comments_authenticated': 7,
        'first_post_at': '2026-01-01T00:00:00Z',
        'latest_post_at': '2026-06-01T00:00:00Z',
        'computed_at': '2026-06-29T00:00:00Z',
      },
      'posts': [
        {
          'post_id': 1,
          'public_sqid': 'p1',
          'title': 'First',
          'created_at': '2026-01-01T00:00:00Z',
          'total_views': 100,
          'unique_viewers': 60,
          'total_reactions': 5,
          'total_comments': 2,
          'total_views_authenticated': 40,
          'unique_viewers_authenticated': 25,
          'total_reactions_authenticated': 3,
          'total_comments_authenticated': 1,
        },
      ],
      'total_posts': 12,
      'page': 1,
      'page_size': 20,
      'has_more': true,
    };

    test('aggregate stats + auth toggle helpers', () {
      final d = ArtistDashboard.fromJson(json);
      expect(d.totalPosts, 12);
      expect(d.hasMore, isTrue);
      final s = d.stats;
      expect(s.views(false), 3400);
      expect(s.views(true), 1200);
      expect(s.uniques(false), 900);
      expect(s.reactions(true), 40);
      expect(s.countries(false)['US'], 200);
      expect(s.countries(true)['US'], 100);
      expect(s.emoji(false)['❤️'], 50);
      expect(s.firstPostAt, isNotNull);
    });

    test('per-post list item + auth toggle', () {
      final d = ArtistDashboard.fromJson(json);
      expect(d.posts, hasLength(1));
      final p = d.posts.first;
      expect(p.sqid, 'p1');
      expect(p.views(false), 100);
      expect(p.views(true), 40);
      expect(p.reactions(false), 5);
      expect(p.comments(true), 1);
    });

    test('tolerates missing maps and fields', () {
      final d = ArtistDashboard.fromJson({'artist_stats': {}, 'posts': []});
      expect(d.stats.views(false), 0);
      expect(d.stats.viewsByCountry, isEmpty);
      expect(d.posts, isEmpty);
      expect(d.page, 1);
    });
  });

  group('PMD models', () {
    test('PmdPostItem parses and derives native file format/size', () {
      final p = PmdPostItem.fromJson({
        'id': 7,
        'public_sqid': 'sq7',
        'title': 'Art',
        'created_at': '2026-05-01T00:00:00Z',
        'width': 64,
        'height': 64,
        'frame_count': 3,
        'art_url': 'https://x/y.gif',
        'hidden_by_user': true,
        'reaction_count': 4,
        'comment_count': 1,
        'view_count': 99,
        'license_identifier': 'CC-BY-4.0',
        'files': [
          {'format': 'webp', 'file_bytes': 1000, 'is_native': false},
          {'format': 'gif', 'file_bytes': 2048, 'is_native': true},
        ],
      });
      expect(p.id, 7);
      expect(p.hiddenByUser, isTrue);
      expect(p.format, 'gif');
      expect(p.fileBytes, 2048);
      expect(p.licenseIdentifier, 'CC-BY-4.0');
    });

    test('PmdPostItem.copyWith toggles hidden and clears license', () {
      final p = PmdPostItem.fromJson({'id': 1, 'public_sqid': 's', 'hidden_by_user': false, 'license_identifier': 'CC0-1.0'});
      expect(p.copyWith(hiddenByUser: true).hiddenByUser, isTrue);
      expect(p.copyWith(clearLicense: true).licenseIdentifier, isNull);
      expect(p.copyWith(licenseIdentifier: 'CC-BY-4.0').licenseIdentifier, 'CC-BY-4.0');
    });

    test('Bdr status helpers', () {
      Bdr b(String s) => Bdr.fromJson({'id': 'i', 'status': s, 'artwork_count': 3});
      expect(b('pending').inProgress, isTrue);
      expect(b('processing').inProgress, isTrue);
      expect(b('ready').isReady, isTrue);
      expect(b('ready').inProgress, isFalse);
      expect(b('failed').isFailed, isTrue);
      expect(b('expired').isExpired, isTrue);
    });

    test('BatchActionResult and CreateBdrResult parse', () {
      final r = BatchActionResult.fromJson({'success': true, 'affected_count': 5, 'message': 'ok'});
      expect(r.success, isTrue);
      expect(r.affectedCount, 5);
      final c = CreateBdrResult.fromJson({'id': 'u', 'status': 'pending', 'artwork_count': 2, 'message': 'queued'});
      expect(c.id, 'u');
      expect(c.status, 'pending');
    });
  });

  group('pmdChunk', () {
    test('splits at the batch cap', () {
      final ids = List.generate(300, (i) => i);
      final chunks = pmdChunk(ids, kPmdBatchMax);
      expect(chunks.map((c) => c.length).toList(), [128, 128, 44]);
      expect(chunks.expand((c) => c).toList(), ids);
    });

    test('exact multiples and small lists', () {
      expect(pmdChunk(List.generate(128, (i) => i), 128).length, 1);
      expect(pmdChunk([1, 2, 3], 128), [
        [1, 2, 3],
      ]);
      expect(pmdChunk(<int>[], 128), isEmpty);
    });
  });
}
