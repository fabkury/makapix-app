import 'comment.dart';
import 'post.dart';
import 'user_profile.dart';
import 'package:makapix_club/l10n/l10n.dart';

/// A content report as returned by `POST /v1/report` (201). The app only needs
/// it for confirmation + tests; the moderator-only `reporter_handle`,
/// `mod_notes`, and `action_taken` fields are ignored.
class Report {
  final String id;
  final String targetType;
  final String targetId;
  final String reasonCode;
  final String? notes;
  final String status;
  final DateTime? createdAt;

  const Report({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.reasonCode,
    required this.notes,
    required this.status,
    required this.createdAt,
  });

  factory Report.fromJson(Map<String, dynamic> j) => Report(
        id: (j['id'] ?? '').toString(),
        targetType: (j['target_type'] ?? '').toString(),
        targetId: (j['target_id'] ?? '').toString(),
        reasonCode: (j['reason_code'] ?? '').toString(),
        notes: j['notes'] as String?,
        status: (j['status'] ?? 'open').toString(),
        createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()),
      );
}

/// A reportable target, built once at the entry point so the three surfaces
/// (post kebab, comment row, profile menu) share one [ReportPage]. The single
/// place the D9 `target_id` format mapping lives (ugc-safety §2 / A11):
/// post → decimal integer id as string · comment → UUID · user → `public_sqid`.
/// [offenderSqid]/[offenderHandle] drive the post-report "Also block" offer
/// (null when there is no stable identity to block, e.g. an anonymous comment).
class ReportTarget {
  final String type; // 'post' | 'comment' | 'user'
  final String id;

  /// A post target's title (may be empty); null for the other kinds.
  final String? postTitle;
  final String? offenderSqid;
  final String? offenderHandle;

  const ReportTarget({
    required this.type,
    required this.id,
    this.postTitle,
    this.offenderSqid,
    this.offenderHandle,
  });

  /// Shown as "Reporting ‹label›". Composed when read, in the app's current language — a
  /// target outlives a language switch, a stored sentence would not.
  String get label {
    final l10n = appL10n;
    return switch (type) {
      'post' => (postTitle ?? '').isEmpty
          ? l10n.reportTargetThisPost
          : l10n.reportTargetTitled(postTitle!),
      // "guest" matches how the comments UI renders anonymous authors.
      'comment' => l10n.reportTargetComment(offenderHandle ?? l10n.commentsGuest),
      _ => '@${offenderHandle ?? ''}',
    };
  }

  factory ReportTarget.post(Post p) => ReportTarget(
        type: 'post',
        id: p.id.toString(),
        postTitle: p.title,
        offenderSqid: p.owner.sqid.isEmpty ? null : p.owner.sqid,
        offenderHandle: p.owner.handle,
      );

  factory ReportTarget.comment(Comment c) => ReportTarget(
        type: 'comment',
        id: c.id,
        offenderSqid: c.author?.sqid,
        offenderHandle: c.author?.handle,
      );

  factory ReportTarget.user(UserProfile u) => ReportTarget(
        type: 'user',
        id: u.sqid,
        offenderSqid: u.sqid.isEmpty ? null : u.sqid,
        offenderHandle: u.handle,
      );
}
