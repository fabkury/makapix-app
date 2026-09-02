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
  final String? actorPublicSqid; // null: anonymous actor, deleted account, or legacy row
  final String? contentTitle;
  final String? contentSqid;
  final String? contentArtUrl;
  final String? emoji;
  final String? commentId;
  final String? commentPreview;

  // Report notifications only (`new_report` / `report_resolved`; report-artwork
  // message 0001, additive). `reasonCode` is the D3 report reason; the
  // `targetUser*` trio describes a reported *user* (resolved at read time, all
  // three null together once the account is deleted). A reported post or
  // comment rides in the content_* fields instead (comment → its parent post).
  final String? reasonCode;
  final String? targetUserHandle;
  final String? targetUserPublicSqid;
  final String? targetUserAvatarUrl;

  ClubNotification({
    required this.id,
    required this.type,
    required this.isRead,
    required this.createdAt,
    this.actorHandle,
    this.actorAvatarUrl,
    this.actorPublicSqid,
    this.contentTitle,
    this.contentSqid,
    this.contentArtUrl,
    this.emoji,
    this.commentId,
    this.commentPreview,
    this.reasonCode,
    this.targetUserHandle,
    this.targetUserPublicSqid,
    this.targetUserAvatarUrl,
  });

  bool get hasContentLink => contentSqid != null && contentSqid!.isNotEmpty;

  /// A reported user with a live profile to open. False once the account is
  /// deleted (the server nulls the trio) and on every non-report type.
  bool get hasTargetUser => targetUserPublicSqid != null && targetUserPublicSqid!.isNotEmpty;

  /// Set when the notification is about a comment (the report-artwork comment
  /// target, or the comment/reply types).
  bool get isAboutComment =>
      (commentId != null && commentId!.isNotEmpty) ||
      (commentPreview != null && commentPreview!.isNotEmpty);

  /// Where the whole tile opens: the post when there is one, else the reported
  /// user's profile, else nowhere (the tile stays inert). Post wins because the
  /// server never sends both (content_* and target_user_* are exclusive by
  /// report target).
  NotificationLink? get link {
    if (hasContentLink) return NotificationLink.post(contentSqid!);
    if (hasTargetUser) return NotificationLink.profile(targetUserPublicSqid!);
    return null;
  }

  factory ClubNotification.fromJson(Map<String, dynamic> j) => ClubNotification(
        id: (j['id'] ?? '').toString(),
        type: (j['notification_type'] ?? j['type'] ?? '').toString(),
        isRead: j['is_read'] == true,
        createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()),
        actorHandle: j['actor_handle'] as String?,
        actorAvatarUrl: j['actor_avatar_url'] as String?,
        actorPublicSqid: j['actor_public_sqid'] as String?,
        contentTitle: j['content_title'] as String?,
        contentSqid: j['content_sqid'] as String?,
        contentArtUrl: j['content_art_url'] as String?,
        emoji: j['emoji'] as String?,
        commentId: j['comment_id']?.toString(),
        commentPreview: j['comment_preview'] as String?,
        reasonCode: j['reason_code'] as String?,
        targetUserHandle: j['target_user_handle'] as String?,
        targetUserPublicSqid: j['target_user_public_sqid'] as String?,
        targetUserAvatarUrl: j['target_user_avatar_url'] as String?,
      );

  ClubNotification asRead() => ClubNotification(
        id: id,
        type: type,
        isRead: true,
        createdAt: createdAt,
        actorHandle: actorHandle,
        actorAvatarUrl: actorAvatarUrl,
        actorPublicSqid: actorPublicSqid,
        contentTitle: contentTitle,
        contentSqid: contentSqid,
        contentArtUrl: contentArtUrl,
        emoji: emoji,
        commentId: commentId,
        commentPreview: commentPreview,
        reasonCode: reasonCode,
        targetUserHandle: targetUserHandle,
        targetUserPublicSqid: targetUserPublicSqid,
        targetUserAvatarUrl: targetUserAvatarUrl,
      );
}

/// The in-app destination a notification tile opens (see [ClubNotification.link]).
class NotificationLink {
  final NotificationLinkKind kind;
  final String sqid;
  const NotificationLink._(this.kind, this.sqid);
  const NotificationLink.post(String sqid) : this._(NotificationLinkKind.post, sqid);
  const NotificationLink.profile(String sqid) : this._(NotificationLinkKind.profile, sqid);
  bool get isPost => kind == NotificationLinkKind.post;
  bool get isProfile => kind == NotificationLinkKind.profile;
}

enum NotificationLinkKind { post, profile }
