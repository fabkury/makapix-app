import 'post.dart';

/// One declared Parent of a post, in declaration order
/// (`GET /post/{id}/parents` — artwork-provenance PLAN §5.5).
///
/// Non-available slots carry no identity: `unavailable` means the parent
/// exists but is not visible to the viewer; `deleted` is the tombstone for a
/// deleted parent. Only `available` slots have a [post].
class LineageParentSlot {
  final int position;
  final String state; // 'available' | 'unavailable' | 'deleted'
  final Post? post;

  const LineageParentSlot({required this.position, required this.state, this.post});

  bool get isAvailable => state == 'available' && post != null;
  bool get isDeleted => state == 'deleted';

  factory LineageParentSlot.fromJson(Map<String, dynamic> j) => LineageParentSlot(
        position: (j['position'] as num?)?.toInt() ?? 0,
        state: (j['state'] ?? 'unavailable').toString(),
        post: j['post'] is Map ? Post.fromJson((j['post'] as Map).cast<String, dynamic>()) : null,
      );
}

/// A viewer-visible Remix of one of the caller's works (`GET /me/remixes`),
/// with the sqids of the caller's own works it declares as Parents.
class RemixReceivedItem {
  final Post post;
  final List<String> myParentSqids;

  const RemixReceivedItem({required this.post, this.myParentSqids = const []});

  factory RemixReceivedItem.fromJson(Map<String, dynamic> j) => RemixReceivedItem(
        post: Post.fromJson(((j['post'] as Map?) ?? const {}).cast<String, dynamic>()),
        myParentSqids:
            (j['my_parent_sqids'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );
}
