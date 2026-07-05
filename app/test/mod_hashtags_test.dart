import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/edit/mod_hashtag_edit.dart';
import 'package:makapix_club/club/models/club_notification.dart';
import 'package:makapix_club/club/models/post.dart';
import 'package:makapix_club/club/models/server_config.dart';

/// Moderator hashtags (contract v1, frozen 2026-07-05) — client-side pieces:
/// Post payload parsing, config-key feature discovery, the client-side
/// normalization mirror, the sheet's working-set rules, and notification copy.
void main() {
  Map<String, dynamic> postJson({List<String>? hashtags, List<String>? mod}) => {
        'id': 7,
        'public_sqid': 'abc',
        'storage_key': 'k',
        'kind': 'artwork',
        'title': 't',
        'hashtags': ?hashtags,
        'mod_hashtags': ?mod,
        'art_url': 'https://x/y.png',
        'width': 32,
        'height': 32,
        'owner': {'user_key': 'u', 'public_sqid': 'o', 'handle': 'h'},
      };

  group('Post.mod_hashtags parsing', () {
    test('present → parsed, membership via isModTag', () {
      final p = Post.fromJson(postJson(hashtags: ['pixelart', 'nsfw'], mod: ['nsfw']));
      expect(p.modHashtags, ['nsfw']);
      expect(p.isModTag('nsfw'), isTrue);
      expect(p.isModTag('pixelart'), isFalse);
    });

    test('absent (old server / card payload) → empty', () {
      final p = Post.fromJson(postJson(hashtags: ['pixelart']));
      expect(p.modHashtags, isEmpty);
    });

    test('empty list → empty', () {
      final p = Post.fromJson(postJson(hashtags: ['a'], mod: []));
      expect(p.modHashtags, isEmpty);
      expect(p.isModTag('a'), isFalse);
    });
  });

  group('Config discovery (max_mod_hashtags_per_post)', () {
    test('key present → enabled with the advertised cap', () {
      final cfg = ClubServerConfig.fromJson({'max_mod_hashtags_per_post': 16});
      expect(cfg.modHashtagsEnabled, isTrue);
      expect(cfg.maxModHashtagsPerPost, 16);
    });

    test('key absent → null, feature off (no default!)', () {
      final cfg = ClubServerConfig.fromJson({'max_hashtags_per_post': 64});
      expect(cfg.maxModHashtagsPerPost, isNull);
      expect(cfg.modHashtagsEnabled, isFalse);
    });

    test('offline fallback → feature off', () {
      expect(ClubServerConfig.fallback.modHashtagsEnabled, isFalse);
    });
  });

  group('normalizeHashtags (mirror of server D12)', () {
    test('trim + strip one # + lowercase', () {
      expect(normalizeHashtags([' #NSFW ']), ['nsfw']);
    });

    test('only ONE leading # is stripped', () {
      expect(normalizeHashtags(['##x']), ['#x']);
    });

    test('empties dropped, order-preserving dedupe', () {
      expect(normalizeHashtags(['b', '', '  ', '#a', 'B', 'a']), ['b', 'a']);
      expect(normalizeHashtags(['#', ' # ']), isEmpty);
    });
  });

  group('ModHashtagEdit', () {
    test('add normalizes; duplicates rejected post-normalization', () {
      final e = ModHashtagEdit(initial: ['nsfw'], cap: 16);
      expect(e.add(' #NSFW '), isFalse); // duplicate of nsfw, not an extra tag
      expect(e.lastRejection, contains('already'));
      expect(e.add('politics'), isTrue);
      expect(e.tags, ['nsfw', 'politics']);
    });

    test('empty and over-length tags rejected', () {
      final e = ModHashtagEdit(initial: [], cap: 16);
      expect(e.add('  #  '), isFalse);
      expect(e.add('x' * 65), isFalse);
      expect(e.lastRejection, contains('64'));
      expect(e.add('x' * 64), isTrue);
    });

    test('cap enforced for add AND toggle (quick-pick cannot overflow)', () {
      final e = ModHashtagEdit(initial: List.generate(3, (i) => 'tag$i'), cap: 3);
      expect(e.add('extra'), isFalse);
      expect(e.lastRejection, contains('3'));
      expect(e.toggle('nsfw'), isFalse); // routed through guarded add → rejected
      expect(e.tags, hasLength(3));
      // Toggle-off still works at the cap, and frees a slot.
      expect(e.toggle('tag0'), isFalse);
      expect(e.toggle('nsfw'), isTrue);
    });

    test('changed is set-based: reorder is not a change', () {
      final e = ModHashtagEdit(initial: ['a', 'b'], cap: 16);
      expect(e.changed, isFalse);
      e.remove('a');
      expect(e.changed, isTrue);
      e.add('a'); // now [b, a] — same set, different order
      expect(e.changed, isFalse);
      e.add('c');
      expect(e.changed, isTrue);
    });

    test('removedMonitored flags only monitored tags dropped from the original set', () {
      final e = ModHashtagEdit(initial: ['nsfw', 'dragon'], cap: 16);
      expect(e.removesMonitored, isFalse);
      e.remove('dragon'); // not monitored
      expect(e.removesMonitored, isFalse);
      e.remove('nsfw');
      expect(e.removesMonitored, isTrue);
      expect(e.removedMonitored, ['nsfw']);
      e.add('nsfw'); // re-added → no longer being removed
      expect(e.removesMonitored, isFalse);
      // Removing a monitored tag that was never in the original is not flagged.
      e.add('violence');
      e.remove('violence');
      expect(e.removesMonitored, isFalse);
    });

    test('initial list is normalized too', () {
      final e = ModHashtagEdit(initial: [' #NSFW ', 'nsfw'], cap: 16);
      expect(e.tags, ['nsfw']);
    });
  });

  group('mod_hashtags_updated notification', () {
    test('parses with the diff in comment_preview', () {
      final n = ClubNotification.fromJson({
        'id': '1',
        'notification_type': 'mod_hashtags_updated',
        'content_title': 'Dragon',
        'content_sqid': 'abc',
        'comment_preview': '+nsfw −politics',
      });
      expect(n.type, 'mod_hashtags_updated');
      expect(n.commentPreview, '+nsfw −politics');
      expect(n.hasContentLink, isTrue);
    });
  });
}
