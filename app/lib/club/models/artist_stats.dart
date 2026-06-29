// Artist dashboard models (`GET /user/{key}/artist-dashboard`, SPEC-CLUB §19).
// Aggregate stats over the last 30 days plus a paged per-post table. Every
// metric has an "all" value and an authenticated-only twin; the UI toggles
// between them.

Map<String, int> _intMap(dynamic v) {
  if (v is! Map) return const {};
  final out = <String, int>{};
  v.forEach((k, val) => out[k.toString()] = (val as num?)?.toInt() ?? 0);
  return out;
}

class ArtistStats {
  final int totalPosts;
  // All viewers
  final int totalViews;
  final int uniqueViewers;
  final Map<String, int> viewsByCountry; // ISO 3166-1 alpha-2 → count (top 10)
  final Map<String, int> viewsByDevice; // desktop/mobile/tablet/player
  final int totalReactions;
  final Map<String, int> reactionsByEmoji;
  final int totalComments;
  // Authenticated-only twins
  final int totalViewsAuthenticated;
  final int uniqueViewersAuthenticated;
  final Map<String, int> viewsByCountryAuthenticated;
  final Map<String, int> viewsByDeviceAuthenticated;
  final int totalReactionsAuthenticated;
  final Map<String, int> reactionsByEmojiAuthenticated;
  final int totalCommentsAuthenticated;
  final DateTime? firstPostAt;
  final DateTime? latestPostAt;
  final DateTime? computedAt;

  const ArtistStats({
    required this.totalPosts,
    required this.totalViews,
    required this.uniqueViewers,
    required this.viewsByCountry,
    required this.viewsByDevice,
    required this.totalReactions,
    required this.reactionsByEmoji,
    required this.totalComments,
    required this.totalViewsAuthenticated,
    required this.uniqueViewersAuthenticated,
    required this.viewsByCountryAuthenticated,
    required this.viewsByDeviceAuthenticated,
    required this.totalReactionsAuthenticated,
    required this.reactionsByEmojiAuthenticated,
    required this.totalCommentsAuthenticated,
    this.firstPostAt,
    this.latestPostAt,
    this.computedAt,
  });

  int views(bool authedOnly) => authedOnly ? totalViewsAuthenticated : totalViews;
  int uniques(bool authedOnly) => authedOnly ? uniqueViewersAuthenticated : uniqueViewers;
  int reactions(bool authedOnly) => authedOnly ? totalReactionsAuthenticated : totalReactions;
  int comments(bool authedOnly) => authedOnly ? totalCommentsAuthenticated : totalComments;
  Map<String, int> countries(bool authedOnly) =>
      authedOnly ? viewsByCountryAuthenticated : viewsByCountry;
  Map<String, int> devices(bool authedOnly) =>
      authedOnly ? viewsByDeviceAuthenticated : viewsByDevice;
  Map<String, int> emoji(bool authedOnly) =>
      authedOnly ? reactionsByEmojiAuthenticated : reactionsByEmoji;

  factory ArtistStats.fromJson(Map<String, dynamic> j) => ArtistStats(
        totalPosts: (j['total_posts'] as num?)?.toInt() ?? 0,
        totalViews: (j['total_views'] as num?)?.toInt() ?? 0,
        uniqueViewers: (j['unique_viewers'] as num?)?.toInt() ?? 0,
        viewsByCountry: _intMap(j['views_by_country']),
        viewsByDevice: _intMap(j['views_by_device']),
        totalReactions: (j['total_reactions'] as num?)?.toInt() ?? 0,
        reactionsByEmoji: _intMap(j['reactions_by_emoji']),
        totalComments: (j['total_comments'] as num?)?.toInt() ?? 0,
        totalViewsAuthenticated: (j['total_views_authenticated'] as num?)?.toInt() ?? 0,
        uniqueViewersAuthenticated: (j['unique_viewers_authenticated'] as num?)?.toInt() ?? 0,
        viewsByCountryAuthenticated: _intMap(j['views_by_country_authenticated']),
        viewsByDeviceAuthenticated: _intMap(j['views_by_device_authenticated']),
        totalReactionsAuthenticated: (j['total_reactions_authenticated'] as num?)?.toInt() ?? 0,
        reactionsByEmojiAuthenticated: _intMap(j['reactions_by_emoji_authenticated']),
        totalCommentsAuthenticated: (j['total_comments_authenticated'] as num?)?.toInt() ?? 0,
        firstPostAt: DateTime.tryParse((j['first_post_at'] ?? '').toString()),
        latestPostAt: DateTime.tryParse((j['latest_post_at'] ?? '').toString()),
        computedAt: DateTime.tryParse((j['computed_at'] ?? '').toString()),
      );
}

class PostStatsListItem {
  final int postId;
  final String sqid;
  final String title;
  final DateTime? createdAt;
  final int totalViews;
  final int uniqueViewers;
  final int totalReactions;
  final int totalComments;
  final int totalViewsAuthenticated;
  final int uniqueViewersAuthenticated;
  final int totalReactionsAuthenticated;
  final int totalCommentsAuthenticated;

  const PostStatsListItem({
    required this.postId,
    required this.sqid,
    required this.title,
    this.createdAt,
    required this.totalViews,
    required this.uniqueViewers,
    required this.totalReactions,
    required this.totalComments,
    required this.totalViewsAuthenticated,
    required this.uniqueViewersAuthenticated,
    required this.totalReactionsAuthenticated,
    required this.totalCommentsAuthenticated,
  });

  int views(bool authedOnly) => authedOnly ? totalViewsAuthenticated : totalViews;
  int reactions(bool authedOnly) => authedOnly ? totalReactionsAuthenticated : totalReactions;
  int comments(bool authedOnly) => authedOnly ? totalCommentsAuthenticated : totalComments;

  factory PostStatsListItem.fromJson(Map<String, dynamic> j) => PostStatsListItem(
        postId: (j['post_id'] as num?)?.toInt() ?? 0,
        sqid: (j['public_sqid'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()),
        totalViews: (j['total_views'] as num?)?.toInt() ?? 0,
        uniqueViewers: (j['unique_viewers'] as num?)?.toInt() ?? 0,
        totalReactions: (j['total_reactions'] as num?)?.toInt() ?? 0,
        totalComments: (j['total_comments'] as num?)?.toInt() ?? 0,
        totalViewsAuthenticated: (j['total_views_authenticated'] as num?)?.toInt() ?? 0,
        uniqueViewersAuthenticated: (j['unique_viewers_authenticated'] as num?)?.toInt() ?? 0,
        totalReactionsAuthenticated: (j['total_reactions_authenticated'] as num?)?.toInt() ?? 0,
        totalCommentsAuthenticated: (j['total_comments_authenticated'] as num?)?.toInt() ?? 0,
      );
}

class ArtistDashboard {
  final ArtistStats stats;
  final List<PostStatsListItem> posts;
  final int totalPosts;
  final int page;
  final int pageSize;
  final bool hasMore;

  const ArtistDashboard({
    required this.stats,
    required this.posts,
    required this.totalPosts,
    required this.page,
    required this.pageSize,
    required this.hasMore,
  });

  factory ArtistDashboard.fromJson(Map<String, dynamic> j) => ArtistDashboard(
        stats: ArtistStats.fromJson(
            ((j['artist_stats'] as Map?) ?? const {}).cast<String, dynamic>()),
        posts: (j['posts'] as List?)
                ?.map((e) => PostStatsListItem.fromJson((e as Map).cast<String, dynamic>()))
                .toList() ??
            const [],
        totalPosts: (j['total_posts'] as num?)?.toInt() ?? 0,
        page: (j['page'] as num?)?.toInt() ?? 1,
        pageSize: (j['page_size'] as num?)?.toInt() ?? 20,
        hasMore: j['has_more'] == true,
      );
}
