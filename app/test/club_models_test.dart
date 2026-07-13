import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/models/club_notification.dart';
import 'package:makapix_club/club/models/comment.dart';
import 'package:makapix_club/club/models/page.dart';
import 'package:makapix_club/club/models/post.dart';
import 'package:makapix_club/club/models/reactions.dart';

/// Trimmed but faithful copy of a real `GET /api/v1/post/recent` response.
final _recent = <String, dynamic>{
  'items': [
    {
      'id': 3416,
      'storage_key': 'f0efe607-ca35-4145-ab6e-4310cf22b5c2',
      'public_sqid': 'eDfc',
      'kind': 'artwork',
      'title': 'brown monster',
      'description': null,
      'hashtags': [],
      'art_url': 'https://vault-dev.makapix.club/11/04/f0efe607.webp',
      'width': 64,
      'height': 64,
      'frame_count': 50,
      'unique_colors': 214,
      'transparency_actual': false,
      'alpha_actual': false,
      'created_at': '2026-04-21T15:43:33.700608Z',
      'promoted': false,
      'promoted_category': null,
      'owner': {
        'id': 1,
        'user_key': '611753f6-9fcf-45fa-9276-aec88ce6490c',
        'public_sqid': 't5',
        'handle': 'Fab',
        'avatar_url': 'https://vault-dev.makapix.club/avatar/x.gif',
        'tagline': 'Founder @ MPX',
        'reputation': 500,
      },
      'reaction_count': 3,
      'comment_count': 1,
      'user_has_liked': true,
      'files': [
        {'format': 'webp', 'file_bytes': 41528, 'is_native': true},
        {'format': 'gif', 'file_bytes': 69716, 'is_native': false},
      ],
      'license': {
        'identifier': 'CC-BY-ND-4.0',
        'title': 'Creative Commons Attribution-NoDerivatives 4.0 International',
        'canonical_url': 'https://creativecommons.org/licenses/by-nd/4.0/',
        'badge_path': '/licenses/by-nd.svg',
      },
    }
  ],
  'next_cursor': 'eyJpZCI6ICIzNDE2In0=',
};

void main() {
  group('Page', () {
    test('parses items + next_cursor; null cursor → atEnd', () {
      final page = Page<Post>.fromJson(_recent, Post.fromJson);
      expect(page.items, hasLength(1));
      expect(page.nextCursor, isNotNull);
      expect(page.atEnd, isFalse);

      final empty = Page<Post>.fromJson({'items': [], 'next_cursor': null}, Post.fromJson);
      expect(empty.items, isEmpty);
      expect(empty.atEnd, isTrue);
    });
  });

  group('Post', () {
    test('parses the real feed shape', () {
      final p = Page<Post>.fromJson(_recent, Post.fromJson).items.first;
      expect(p.id, 3416);
      expect(p.sqid, 'eDfc');
      expect(p.title, 'brown monster');
      expect(p.isAnimated, isTrue); // frame_count 50
      expect(p.owner.handle, 'Fab');
      expect(p.owner.userKey, '611753f6-9fcf-45fa-9276-aec88ce6490c');
      expect(p.reactionCount, 3);
      expect(p.commentCount, 1);
      expect(p.userHasLiked, isTrue);
      expect(p.files.where((f) => f.isNative).single.format, 'webp');
      expect(p.license?.identifier, 'CC-BY-ND-4.0');
    });
  });

  group('ReactionTotals', () {
    test('parses and toggles optimistically', () {
      final r = ReactionTotals.fromJson({
        'totals': {'👍': 2, '🔥': 1},
        'authenticated_totals': {'👍': 2},
        'anonymous_totals': {},
        'mine': ['👍'],
      });
      expect(r.countFor('👍'), 2);
      expect(r.hasMine('👍'), isTrue);
      expect(r.mineCount, 1);

      final added = r.withLocal(emoji: '❤️', add: true);
      expect(added.countFor('❤️'), 1);
      expect(added.hasMine('❤️'), isTrue);

      final removed = added.withLocal(emoji: '👍', add: false);
      expect(removed.countFor('👍'), 1);
      expect(removed.hasMine('👍'), isFalse);
    });

    test('curated emoji set has five entries', () => expect(kReactionEmojis, hasLength(5)));
  });

  group('ReactionUser', () {
    test('parses a reaction-users item', () {
      final r = ReactionUser.fromJson({
        'emoji': '🔥',
        'created_at': '2026-06-28T14:30:45Z',
        'user_handle': 'pixel_artist',
        'user_avatar_url': 'https://vault-dev.makapix.club/avatar/x.gif',
        'user_public_sqid': 'aB3x',
      });
      expect(r.emoji, '🔥');
      expect(r.handle, 'pixel_artist');
      expect(r.sqid, 'aB3x');
      expect(r.avatarUrl, isNotNull);
      expect(r.createdAt, isNotNull);
    });

    test('tolerates missing avatar/sqid and unparseable timestamp', () {
      final r = ReactionUser.fromJson({'emoji': '👍', 'user_handle': 'bob', 'created_at': ''});
      expect(r.avatarUrl, isNull);
      expect(r.sqid, isNull);
      expect(r.createdAt, isNull);
    });

    test('countEmojis tallies and orders curated emojis first', () {
      final reactors = [
        const ReactionUser(emoji: '🎉', createdAt: null, handle: 'a'), // non-curated
        const ReactionUser(emoji: '❤️', createdAt: null, handle: 'b'),
        const ReactionUser(emoji: '👍', createdAt: null, handle: 'c'),
        const ReactionUser(emoji: '❤️', createdAt: null, handle: 'd'),
      ];
      final counts = ReactionTotals.countEmojis(reactors);
      expect(counts['❤️'], 2);
      expect(counts['👍'], 1);
      expect(counts['🎉'], 1);
      // Curated set (👍 before ❤️) precedes any non-curated emoji (🎉).
      expect(counts.keys.toList(), ['👍', '❤️', '🎉']);
    });
  });

  group('Comment.assembleTree', () {
    test('builds a depth-2 tree and promotes orphans', () {
      final flat = [
        Comment.fromJson({'id': 'a', 'parent_id': null, 'depth': 0, 'body': 'root'}),
        Comment.fromJson({'id': 'b', 'parent_id': 'a', 'depth': 1, 'body': 'reply'}),
        Comment.fromJson({'id': 'c', 'parent_id': null, 'depth': 0, 'body': 'root2'}),
        Comment.fromJson({'id': 'd', 'parent_id': 'missing', 'depth': 1, 'body': 'orphan'}),
      ];
      final tree = Comment.assembleTree(flat);
      expect(tree.map((c) => c.id), containsAll(['a', 'c', 'd'])); // orphan promoted
      final a = tree.firstWhere((c) => c.id == 'a');
      expect(a.replies, hasLength(1));
      expect(a.replies.first.id, 'b');
    });

    test('parses anonymous vs authored (flat author_* fields, as the server sends)', () {
      final anon = Comment.fromJson({'id': '1', 'body': 'hi', 'author_handle': null});
      expect(anon.isAnonymous, isTrue);
      final authored = Comment.fromJson({
        'id': '2',
        'body': 'hey',
        'author_id': 1281,
        'author_handle': 'bob',
        'author_avatar_url': 'https://vault.example/a.jpg',
        'like_count': 4,
        'liked_by_me': true,
      });
      expect(authored.isAnonymous, isFalse);
      expect(authored.author!.handle, 'bob');
      expect(authored.author!.avatarUrl, 'https://vault.example/a.jpg');
      expect(authored.author!.sqid, isNull); // no author sqid in server payloads yet
      expect(authored.likeCount, 4);
      expect(authored.likedByMe, isTrue);
    });

    test('adopts author_public_sqid when the server ships it', () {
      final c = Comment.fromJson(
          {'id': '3', 'body': 'yo', 'author_handle': 'bob', 'author_public_sqid': 'bsq'});
      expect(c.author!.sqid, 'bsq');
    });

    test('deletion flags: owner vs moderator (ugc-safety msg 0008)', () {
      final live = Comment.fromJson({'id': '1', 'body': 'hi'});
      expect(live.deleted, isFalse);
      expect(live.deletedByMod, isFalse);

      final byOwner = Comment.fromJson(
          {'id': '2', 'body': '[deleted]', 'deleted_by_owner': true, 'deleted_by_mod': false});
      expect(byOwner.deleted, isTrue);
      expect(byOwner.deletedByMod, isFalse);

      // Mod take-downs no longer set deleted_by_owner — deleted must still be true.
      final byMod = Comment.fromJson({
        'id': '3',
        'body': '[deleted by moderator]',
        'deleted_by_owner': false,
        'deleted_by_mod': true,
      });
      expect(byMod.deleted, isTrue);
      expect(byMod.deletedByMod, isTrue);
    });
  });

  group('ClubNotification', () {
    test('parses and marks read', () {
      final n = ClubNotification.fromJson({
        'id': 'x',
        'notification_type': 'reaction',
        'is_read': false,
        'actor_handle': 'bob',
        'content_sqid': 'eDfc',
        'emoji': '🔥',
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(n.type, 'reaction');
      expect(n.isRead, isFalse);
      expect(n.hasContentLink, isTrue);
      expect(n.asRead().isRead, isTrue);
    });
  });
}
