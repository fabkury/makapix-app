import 'post.dart';

/// The server's feed-bump limit: a post moves up at most once per this long, counted from
/// its `listed_at` (messages/0006-feed-bump, 0001 §1c).
const Duration kBumpCooldown = Duration(days: 7);

/// When a replace can next move the post up: [listedAt] plus [kBumpCooldown], or null when
/// that has already passed (a replace now can move it) or [listedAt] is unknown. A hint: after
/// a replace the server's `bump_available_at` is authoritative (0004 §1).
DateTime? nextBumpAt(DateTime? listedAt, {DateTime? now}) {
  if (listedAt == null) return null;
  final next = listedAt.add(kBumpCooldown);
  return next.isAfter(now ?? DateTime.now()) ? next : null;
}

/// The answer to `POST /post/{id}/replace-artwork`: the updated post plus what
/// happened to its place in the feeds (messages/0006-feed-bump, 0001 §2).
///
/// The bump fields describe this one replace, so they live here and not on
/// [Post]. A server from before the feed bump sends none of them, which reads
/// as "replaced, nothing else to say".
class ReplaceResult {
  final Post post;

  /// The post moved back to the top of the date-sorted feeds just now.
  final bool bumped;

  /// Why it didn't move: `opted_out`, `cooldown`, or `not_trusted` (the bump,
  /// if still eligible, happens when a moderator approves the replacement).
  final String? bumpSkippedReason;

  /// When the post can show as new again (set on `cooldown` and after a bump).
  final DateTime? bumpAvailableAt;

  /// The replacement went back to moderation and the post left public feeds.
  /// Only an explicit `public_visibility: false` counts: the field is absent
  /// on servers from before the feed bump.
  final bool pendingReview;

  const ReplaceResult({
    required this.post,
    this.bumped = false,
    this.bumpSkippedReason,
    this.bumpAvailableAt,
    this.pendingReview = false,
  });

  factory ReplaceResult.fromJson(Map<String, dynamic> j) => ReplaceResult(
        post: Post.fromJson(j),
        bumped: j['bumped'] == true,
        bumpSkippedReason: j['bump_skipped_reason'] as String?,
        bumpAvailableAt: DateTime.tryParse((j['bump_available_at'] ?? '').toString()),
        pendingReview: j['public_visibility'] == false,
      );

  /// The cooldown is what kept the post in place.
  bool get onCooldown => bumpSkippedReason == 'cooldown';
}
