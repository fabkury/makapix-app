int _int(Object? v) => v is num ? v.toInt() : 0;

/// A hashtag with aggregate counts (`GET /hashtags/stats`). Field names are
/// parsed defensively since the exact server keys may vary.
class HashtagStat {
  final String tag;
  final int artworkCount;
  final int reactionCount;
  final int commentCount;
  const HashtagStat({
    required this.tag,
    this.artworkCount = 0,
    this.reactionCount = 0,
    this.commentCount = 0,
  });

  factory HashtagStat.fromJson(Map<String, dynamic> j) => HashtagStat(
        tag: (j['tag'] ?? j['hashtag'] ?? '').toString(),
        artworkCount: _int(j['artwork_count'] ?? j['post_count'] ?? j['count']),
        reactionCount: _int(j['reaction_count'] ?? j['total_reactions']),
        commentCount: _int(j['comment_count'] ?? j['total_comments']),
      );
}
