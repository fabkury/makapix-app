/// Author of a comment (null for anonymous comments, which the server attributes
/// to an IP rather than a user).
class CommentAuthor {
  final String handle;

  /// Only set on optimistic local comments (from the signed-in user). Server
  /// comment payloads carry no author sqid — just flat `author_*` fields.
  final String? sqid;
  final String? avatarUrl;
  const CommentAuthor({required this.handle, this.sqid, this.avatarUrl});

  /// From the flat `author_handle`/`author_avatar_url` fields of a comment
  /// payload (unlike reaction-users there is no `*_public_sqid`). A null
  /// `author_handle` means anonymous.
  static CommentAuthor? fromCommentJson(Map<String, dynamic> j) {
    final h = j['author_handle'];
    if (h == null) return null;
    return CommentAuthor(
      handle: h.toString(),
      avatarUrl: j['author_avatar_url'] as String?,
    );
  }
}

/// A comment on a post. Threads are at most 2 deep (top-level + replies).
class Comment {
  final String id;
  final String? parentId;
  final int depth;
  final String body;
  final DateTime? createdAt;
  final CommentAuthor? author;
  final int likeCount;
  final bool likedByMe;
  final bool deleted;
  final List<Comment> replies;

  const Comment({
    required this.id,
    required this.parentId,
    required this.depth,
    required this.body,
    required this.createdAt,
    required this.author,
    required this.likeCount,
    required this.likedByMe,
    required this.deleted,
    this.replies = const [],
  });

  bool get isAnonymous => author == null;

  factory Comment.fromJson(Map<String, dynamic> j) => Comment(
        id: (j['id'] ?? '').toString(),
        parentId: j['parent_id']?.toString(),
        depth: (j['depth'] as num?)?.toInt() ?? 0,
        body: (j['body'] ?? '').toString(),
        createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()),
        author: CommentAuthor.fromCommentJson(j),
        likeCount: (j['like_count'] as num?)?.toInt() ?? 0,
        likedByMe: j['liked_by_me'] == true,
        deleted: j['deleted'] == true || j['deleted_by_owner'] == true,
      );

  /// A soft-deleted copy (keeps replies visible, as the server does). Used for optimistic deletes.
  Comment markDeleted() => Comment(
        id: id,
        parentId: parentId,
        depth: depth,
        body: body,
        createdAt: createdAt,
        author: author,
        likeCount: likeCount,
        likedByMe: likedByMe,
        deleted: true,
        replies: replies,
      );

  Comment withReplies(List<Comment> r) => Comment(
        id: id,
        parentId: parentId,
        depth: depth,
        body: body,
        createdAt: createdAt,
        author: author,
        likeCount: likeCount,
        likedByMe: likedByMe,
        deleted: deleted,
        replies: r,
      );

  /// Assemble a flat list (each with `parentId`) into a depth-≤2 tree: top-level
  /// comments in order, each carrying its direct replies. Replies whose parent is
  /// missing are promoted to top-level so nothing is dropped.
  static List<Comment> assembleTree(List<Comment> flat) {
    final ids = {for (final c in flat) c.id};
    final childrenOf = <String, List<Comment>>{};
    final roots = <Comment>[];
    for (final c in flat) {
      final p = c.parentId;
      if (p != null && ids.contains(p)) {
        (childrenOf[p] ??= []).add(c);
      } else {
        roots.add(c);
      }
    }
    return [for (final r in roots) r.withReplies(childrenOf[r.id] ?? const [])];
  }
}
