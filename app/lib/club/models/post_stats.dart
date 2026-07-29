// Per-post statistics (`GET /post/{id}/stats`, SPEC-CLUB §19 drill-in).
// Same dual-metric convention as the artist dashboard: every metric has an
// "all" value and an authenticated-only twin; the UI toggles between them.

Map<String, int> _intMap(dynamic v) {
  if (v is! Map) return const {};
  final out = <String, int>{};
  v.forEach((k, val) => out[k.toString()] = (val as num?)?.toInt() ?? 0);
  return out;
}

/// One day of the 30-day views trend.
class DailyViews {
  final String date; // ISO YYYY-MM-DD
  final int views;
  final int uniqueViewers;
  const DailyViews({required this.date, required this.views, required this.uniqueViewers});

  factory DailyViews.fromJson(Map<String, dynamic> j) => DailyViews(
        date: (j['date'] ?? '').toString(),
        views: (j['views'] as num?)?.toInt() ?? 0,
        uniqueViewers: (j['unique_viewers'] as num?)?.toInt() ?? 0,
      );
}

class PostStats {
  final int postId;
  // All viewers
  final int totalViews;
  final int uniqueViewers; // 7-day window server-side
  final Map<String, int> viewsByCountry;
  final Map<String, int> viewsByDevice;
  final Map<String, int> viewsByType; // intentional/listing/search/…
  final List<DailyViews> dailyViews; // last 30 days
  final int totalReactions;
  final Map<String, int> reactionsByEmoji;
  final int totalComments;
  // Authenticated-only twins
  final int totalViewsAuthenticated;
  final int uniqueViewersAuthenticated;
  final Map<String, int> viewsByCountryAuthenticated;
  final Map<String, int> viewsByDeviceAuthenticated;
  final Map<String, int> viewsByTypeAuthenticated;
  final List<DailyViews> dailyViewsAuthenticated;
  final int totalReactionsAuthenticated;
  final Map<String, int> reactionsByEmojiAuthenticated;
  final int totalCommentsAuthenticated;
  // Timestamps
  final DateTime? firstViewAt;
  final DateTime? lastViewAt;
  final DateTime? computedAt;

  const PostStats({
    required this.postId,
    required this.totalViews,
    required this.uniqueViewers,
    required this.viewsByCountry,
    required this.viewsByDevice,
    required this.viewsByType,
    required this.dailyViews,
    required this.totalReactions,
    required this.reactionsByEmoji,
    required this.totalComments,
    required this.totalViewsAuthenticated,
    required this.uniqueViewersAuthenticated,
    required this.viewsByCountryAuthenticated,
    required this.viewsByDeviceAuthenticated,
    required this.viewsByTypeAuthenticated,
    required this.dailyViewsAuthenticated,
    required this.totalReactionsAuthenticated,
    required this.reactionsByEmojiAuthenticated,
    required this.totalCommentsAuthenticated,
    this.firstViewAt,
    this.lastViewAt,
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
  Map<String, int> types(bool authedOnly) =>
      authedOnly ? viewsByTypeAuthenticated : viewsByType;
  Map<String, int> emoji(bool authedOnly) =>
      authedOnly ? reactionsByEmojiAuthenticated : reactionsByEmoji;
  List<DailyViews> daily(bool authedOnly) =>
      authedOnly ? dailyViewsAuthenticated : dailyViews;

  static List<DailyViews> _dailyList(dynamic v) => (v as List?)
          ?.map((e) => DailyViews.fromJson((e as Map).cast<String, dynamic>()))
          .toList() ??
      const [];

  factory PostStats.fromJson(Map<String, dynamic> j) => PostStats(
        postId: (j['post_id'] as num?)?.toInt() ?? 0,
        totalViews: (j['total_views'] as num?)?.toInt() ?? 0,
        uniqueViewers: (j['unique_viewers'] as num?)?.toInt() ?? 0,
        viewsByCountry: _intMap(j['views_by_country']),
        viewsByDevice: _intMap(j['views_by_device']),
        viewsByType: _intMap(j['views_by_type']),
        dailyViews: _dailyList(j['daily_views']),
        totalReactions: (j['total_reactions'] as num?)?.toInt() ?? 0,
        reactionsByEmoji: _intMap(j['reactions_by_emoji']),
        totalComments: (j['total_comments'] as num?)?.toInt() ?? 0,
        totalViewsAuthenticated: (j['total_views_authenticated'] as num?)?.toInt() ?? 0,
        uniqueViewersAuthenticated: (j['unique_viewers_authenticated'] as num?)?.toInt() ?? 0,
        viewsByCountryAuthenticated: _intMap(j['views_by_country_authenticated']),
        viewsByDeviceAuthenticated: _intMap(j['views_by_device_authenticated']),
        viewsByTypeAuthenticated: _intMap(j['views_by_type_authenticated']),
        dailyViewsAuthenticated: _dailyList(j['daily_views_authenticated']),
        totalReactionsAuthenticated: (j['total_reactions_authenticated'] as num?)?.toInt() ?? 0,
        reactionsByEmojiAuthenticated: _intMap(j['reactions_by_emoji_authenticated']),
        totalCommentsAuthenticated: (j['total_comments_authenticated'] as num?)?.toInt() ?? 0,
        firstViewAt: DateTime.tryParse((j['first_view_at'] ?? '').toString()),
        lastViewAt: DateTime.tryParse((j['last_view_at'] ?? '').toString()),
        computedAt: DateTime.tryParse((j['computed_at'] ?? '').toString()),
      );
}
