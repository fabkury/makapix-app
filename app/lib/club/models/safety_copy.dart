import 'club_error.dart';
import 'club_notification.dart';
import 'server_config.dart';

/// Shared user-facing copy for the UGC-safety flows, kept pure (no Flutter) so
/// it is unit-testable. Interpolates config-driven values (contact email, block
/// cap) rather than hardcoding them.

/// The `429 rate_limited` message on `POST /report` (contract §3 copy).
String reportRateLimitMessage(String contactEmail) =>
    "You're reporting too fast — try again later, or email $contactEmail.";

/// Maps a block/unblock [ClubError] to user-facing copy (ugc-safety §9). The
/// `bad_request`/self-block case is unreachable (the UI hides self-block) and
/// falls through to the generic message.
String blockErrorMessage(ClubError e, {required int maxBlocksPerUser}) {
  if (e.status == 409 || e.code == 'block_cap_reached') {
    return "You've reached the limit of $maxBlocksPerUser blocked users.";
  }
  if (e.status == 404 || e.code == 'not_found') return 'User not found.';
  if (e.isAuth) return 'Your session has expired. Please sign in again.';
  return 'Could not update the block — try again.';
}

// ---------------------------------------------------------------------------
// Report notifications (`new_report` / `report_resolved`), report-artwork
// message 0001: the server ships the raw `reason_code` plus the reported
// post/comment/user, and the client composes the sentence — mirroring the
// website's copy.

/// Fallback reason labels — a copy of the report form's `{code, label}` set as
/// of 2026-09-02. The live labels come from `GET /config` → `moderation.
/// report_reasons` and win when loaded ([reportReasonLabel]).
const Map<String, String> kReportReasonLabels = {
  'spam': 'Spam or misleading',
  'harassment': 'Harassment or bullying',
  'hate': 'Hate or discrimination',
  'sexual_explicit': 'Sexual or explicit content',
  'violence_gore': 'Violence or gore',
  'illegal_csam': 'Illegal content or child endangerment',
  'self_harm': 'Self-harm or suicide',
  'copyright': 'Copyright or IP violation',
  'other': 'Something else',
};

/// Human label for a report reason code: the server config's label when it
/// knows the code, else the baked-in table, else the raw code (an unknown or
/// legacy code is still more useful than nothing). Null/empty code → null.
String? reportReasonLabel(String? code, {Iterable<ReportReason>? reasons}) {
  if (code == null || code.isEmpty) return null;
  for (final r in reasons ?? const <ReportReason>[]) {
    if (r.code == code && r.label.isNotEmpty) return r.label;
  }
  return kReportReasonLabels[code] ?? code;
}

/// The reported thing as a noun phrase: `"Sunset"` (post title) · `a comment
/// on "Sunset"` · `@handle` (user). Null when nothing about the target survived
/// (deleted before the notification rendered → bare tile).
String? reportSubject(ClubNotification x) {
  final title = x.contentTitle;
  final quoted = title == null || title.isEmpty ? null : '"$title"';
  if (x.isAboutComment) {
    return quoted == null ? 'a comment' : 'a comment on $quoted';
  }
  if (quoted != null || x.hasContentLink) return quoted ?? 'a post';
  final handle = x.targetUserHandle;
  if (handle != null && handle.isNotEmpty) return '@$handle';
  return null;
}

/// Tile copy for `new_report` (moderators). Historical rows (before 2026-09-02)
/// carry the server's old pre-formatted summary in `content_title` and nothing
/// else, so a title with no reason, no link, and no target renders verbatim.
/// A comment report appends the excerpt on a second line.
String newReportText(ClubNotification x, {Iterable<ReportReason>? reasons}) {
  final legacySummary = x.contentTitle != null &&
      x.reasonCode == null &&
      !x.hasContentLink &&
      !x.hasTargetUser &&
      !x.isAboutComment;
  if (legacySummary) return x.contentTitle!;
  final subject = reportSubject(x);
  final reason = reportReasonLabel(x.reasonCode, reasons: reasons);
  if (subject == null && reason == null) return 'New content report';
  final buf = StringBuffer('New report');
  if (subject != null) buf.write(': ${_capitalize(subject)} was reported');
  if (reason != null) buf.write(subject == null ? ': $reason' : ' for $reason');
  final preview = x.commentPreview;
  if (preview != null && preview.isNotEmpty) buf.write('\n$preview');
  return buf.toString();
}

/// Tile copy for `report_resolved` (the reporter). No action details by
/// contract (ugc-safety D22) — only which report was reviewed.
String reportResolvedText(ClubNotification x) {
  final subject = reportSubject(x);
  return subject == null
      ? "Thanks — we've reviewed your report."
      : "Thanks — we've reviewed your report on $subject.";
}

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
