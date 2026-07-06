import 'comment.dart';
import 'post.dart';
import 'user_profile.dart';

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
  final String label; // shown as "Reporting ‹label›"
  final String? offenderSqid;
  final String? offenderHandle;

  const ReportTarget({
    required this.type,
    required this.id,
    required this.label,
    this.offenderSqid,
    this.offenderHandle,
  });

  factory ReportTarget.post(Post p) => ReportTarget(
        type: 'post',
        id: p.id.toString(),
        label: p.title.isEmpty ? 'this post' : '“${p.title}”',
        offenderSqid: p.owner.sqid.isEmpty ? null : p.owner.sqid,
        offenderHandle: p.owner.handle,
      );

  factory ReportTarget.comment(Comment c) => ReportTarget(
        type: 'comment',
        id: c.id,
        // "guest" matches how the comments UI renders anonymous authors.
        label: 'comment by @${c.author?.handle ?? 'guest'}',
        offenderSqid: c.author?.sqid,
        offenderHandle: c.author?.handle,
      );

  factory ReportTarget.user(UserProfile u) => ReportTarget(
        type: 'user',
        id: u.sqid,
        label: '@${u.handle}',
        offenderSqid: u.sqid.isEmpty ? null : u.sqid,
        offenderHandle: u.handle,
      );
}
