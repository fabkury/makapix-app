/// A social notification (`GET /social-notifications/`). Content fields are
/// denormalized so the list renders without extra fetches; content notifications
/// deep-link to `/p/{contentSqid}`.
class ClubNotification {
  final String id;
  final String type; // reaction | comment | comment_reply | comment_like | follow | post_promoted | ...
  final bool isRead;
  final DateTime? createdAt;
  final String? actorHandle;
  final String? actorAvatarUrl;
  final String? contentTitle;
  final String? contentSqid;
  final String? contentArtUrl;
  final String? emoji;
  final String? commentPreview;

  ClubNotification({
    required this.id,
    required this.type,
    required this.isRead,
    required this.createdAt,
    this.actorHandle,
    this.actorAvatarUrl,
    this.contentTitle,
    this.contentSqid,
    this.contentArtUrl,
    this.emoji,
    this.commentPreview,
  });

  bool get hasContentLink => contentSqid != null && contentSqid!.isNotEmpty;

  factory ClubNotification.fromJson(Map<String, dynamic> j) => ClubNotification(
        id: (j['id'] ?? '').toString(),
        type: (j['notification_type'] ?? j['type'] ?? '').toString(),
        isRead: j['is_read'] == true,
        createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()),
        actorHandle: j['actor_handle'] as String?,
        actorAvatarUrl: j['actor_avatar_url'] as String?,
        contentTitle: j['content_title'] as String?,
        contentSqid: j['content_sqid'] as String?,
        contentArtUrl: j['content_art_url'] as String?,
        emoji: j['emoji'] as String?,
        commentPreview: j['comment_preview'] as String?,
      );

  ClubNotification asRead() => ClubNotification(
        id: id,
        type: type,
        isRead: true,
        createdAt: createdAt,
        actorHandle: actorHandle,
        actorAvatarUrl: actorAvatarUrl,
        contentTitle: contentTitle,
        contentSqid: contentSqid,
        contentArtUrl: contentArtUrl,
        emoji: emoji,
        commentPreview: commentPreview,
      );
}
