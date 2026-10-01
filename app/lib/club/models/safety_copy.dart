import 'club_error.dart';
import 'club_notification.dart';
import 'server_config.dart';
import 'package:makapix_club/l10n/l10n.dart';

/// Shared user-facing copy for the UGC-safety flows, kept pure (no Flutter) so
/// it is unit-testable. Interpolates config-driven values (contact email, block
/// cap) rather than hardcoding them.

/// The `429 rate_limited` message on `POST /report` (contract §3 copy).
String reportRateLimitMessage(String contactEmail) => appL10n.reportRateLimited(contactEmail);

/// Maps a block/unblock [ClubError] to user-facing copy (ugc-safety §9). The
/// `bad_request`/self-block case is unreachable (the UI hides self-block) and
/// falls through to the generic message.
String blockErrorMessage(ClubError e, {required int maxBlocksPerUser}) {
  final l10n = appL10n;
  if (e.status == 409 || e.code == 'block_cap_reached') {
    return l10n.blockCapReached(maxBlocksPerUser);
  }
  if (e.status == 404 || e.code == 'not_found') return l10n.userNotFound;
  if (e.isAuth) return l10n.sessionExpiredSignIn;
  return l10n.blockUpdateFailed;
}

// ---------------------------------------------------------------------------
// Report notifications (`new_report` / `report_resolved`), report-artwork
// message 0001: the server ships the raw `reason_code` plus the reported
// post/comment/user, and the client composes the sentence — mirroring the
// website's copy.

/// The app's own label for a report reason code — the report form's `{code, label}` set as
/// of 2026-09-02, in the app's language. Null for a code the app does not know.
String? ownReportReasonLabel(AppLocalizations l10n, String code) => switch (code) {
      'spam' => l10n.reasonSpam,
      'harassment' => l10n.reasonHarassment,
      'hate' => l10n.reasonHate,
      'sexual_explicit' => l10n.reasonSexual,
      'violence_gore' => l10n.reasonViolence,
      'illegal_csam' => l10n.reasonIllegal,
      'self_harm' => l10n.reasonSelfHarm,
      'copyright' => l10n.reasonCopyright,
      'other' => l10n.reasonOther,
      _ => null,
    };

/// Human label for a report reason code. The live labels come from `GET /config` →
/// `moderation.report_reasons`, in English: in English they win (the server can reword them);
/// in any other language the app's translation of a known code wins, until the server sends
/// labels in the user's language (docs/i18n/PLAN.md, L4 server text). A code neither side
/// knows renders raw — more useful than nothing. Null/empty code → null.
String? reportReasonLabel(String? code, {Iterable<ReportReason>? reasons}) {
  if (code == null || code.isEmpty) return null;
  final l10n = appL10n;
  final own = ownReportReasonLabel(l10n, code);
  if (own != null && l10n.localeName != 'en') return own;
  for (final r in reasons ?? const <ReportReason>[]) {
    if (r.code == code && r.label.isNotEmpty) return r.label;
  }
  return own ?? code;
}

/// The reported thing as a noun phrase: `"Sunset"` (post title) · `a comment
/// on "Sunset"` · `@handle` (user). Null when nothing about the target survived
/// (deleted before the notification rendered → bare tile).
String? reportSubject(ClubNotification x) {
  final l10n = appL10n;
  final raw = x.contentTitle;
  final title = raw == null || raw.isEmpty ? null : raw;
  if (x.isAboutComment) {
    return title == null ? l10n.reportSubjectComment : l10n.reportSubjectCommentOn(title);
  }
  if (title != null) return l10n.reportSubjectTitled(title);
  if (x.hasContentLink) return l10n.reportSubjectPost;
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
  final l10n = appL10n;
  final subject = reportSubject(x);
  final reason = reportReasonLabel(x.reasonCode, reasons: reasons);
  final String line;
  if (subject == null) {
    line = reason == null ? l10n.newReportGeneric : l10n.newReportReason(reason);
  } else {
    final s = _capitalize(subject);
    line = reason == null ? l10n.newReportSubject(s) : l10n.newReportSubjectReason(s, reason);
  }
  final preview = x.commentPreview;
  return preview != null && preview.isNotEmpty ? '$line\n$preview' : line;
}

/// Tile copy for `report_resolved` (the reporter). No action details by
/// contract (ugc-safety D22) — only which report was reviewed.
String reportResolvedText(ClubNotification x) {
  final subject = reportSubject(x);
  return subject == null ? appL10n.reportResolved : appL10n.reportResolvedOn(subject);
}

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
