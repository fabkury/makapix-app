import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:makapix_club/l10n/l10n.dart';

import '../auth/account_validators.dart' show handleReasonMessage;
import '../ui/widgets/common.dart' show formatFileSize;

/// Shown wherever an interaction is refused with `403 blocked` (ugc-safety §5 /
/// A8). Direction-neutral by design: a block refuses interactions in **either**
/// direction (D11), so the copy must never disclose who blocked whom.
String get blockedInteractionMessage => appL10n.errBlockedInteraction;

/// What to show for a failed Club call: [e]'s own text under [headline] when it is a
/// [ClubError] ([ClubError.describe]), else [headline] alone.
String clubErrorText(Object e, String headline) =>
    e is ClubError ? e.describe(headline) : headline;

/// A normalized Club API error.
///
/// Maps both the v1 envelope `{ "error": { "code", "message" } }` and FastAPI's
/// legacy `{ "detail": ... }`, plus transport (network/timeout) failures.
///
/// The server writes its prose in English. For the codes the app knows, [message] is the
/// app's own sentence in the user's language and the prose is dropped. Otherwise the prose is
/// kept as [serverText] and shown under a translated headline, one per line: the screen's own
/// ("Could not save your profile.", via [describe]) or one by status class ([message]). Shown
/// with `ClubMessageText`, the second line is smaller and muted (docs/i18n/PLAN.md, L4).
class ClubError implements Exception {
  final int? status;
  final String code;

  /// The text to show when the screen has no headline of its own.
  final String message;

  /// The server's own prose, when the app has no message of its own for [code].
  final String? serverText;

  /// The server's `details` for [code] (limits, dates, reasons), when it sent any.
  final Map<String, dynamic>? details;
  final Duration? retryAfter;

  /// [message] says what went wrong on its own (a known code, a lost connection), so it
  /// beats a screen's generic headline.
  final bool specific;

  ClubError({
    this.status,
    required this.code,
    required this.message,
    this.serverText,
    this.details,
    this.retryAfter,
    this.specific = true,
  });

  factory ClubError.fromBody(int? status, Object? body, {Duration? retryAfter}) {
    // A download (`ResponseType.bytes`) hands its error body over undecoded.
    if (body is List<int>) body = _decodeBytes(body);
    var code = 'unknown';
    Map<String, dynamic>? details;
    String? own;
    String? prose;
    if (body is Map) {
      final err = body['error'];
      if (err is Map) {
        code = (err['code'] ?? code).toString();
        details = _asMap(err['details']);
        own = translatedCode(code, details);
        if (own == null) prose = _prose(err['message']);
      } else if (body['detail'] != null || body['code'] != null) {
        // Off `/v1` the code rides beside FastAPI's `detail` (messages/0005-localized-text/
        // 0003 §2); an older server sends `detail` alone.
        code = body['code']?.toString() ?? 'error';
        details = _asMap(body['details']);
        own = translatedCode(code, details);
        if (own == null) prose = _prose(body['detail']);
      }
    } else if (body is String) {
      prose = _prose(body);
    }
    final headline = _statusHeadline(status);
    return ClubError(
      status: status,
      code: code,
      message: own ?? (prose == null ? headline : '$headline\n$prose'),
      serverText: prose,
      details: details,
      retryAfter: retryAfter,
      specific: own != null,
    );
  }

  /// The account itself is refused (banned or deactivated): the session is over.
  bool get isAccountBlocked => code == 'account_banned' || code == 'account_deactivated';

  /// This error under the screen's own [headline] ("Could not save your profile."): the
  /// server's prose on a second line when there is some, else the app's specific message
  /// (a known code, a lost connection), or [headline] when the app has nothing better.
  String describe(String headline) {
    if (serverText != null) return '$headline\n$serverText';
    return specific ? message : headline;
  }

  /// Raw response bytes as the JSON object they usually are, else as text.
  static Object? _decodeBytes(List<int> bytes) {
    final text = utf8.decode(bytes, allowMalformed: true);
    try {
      return jsonDecode(text);
    } on FormatException {
      return text;
    }
  }

  /// The server's prose, cleaned for display: FastAPI's validation list becomes its `msg`
  /// lines; an HTML error page (a proxy's 502) and empty text become null; very long text is
  /// cut.
  static String? _prose(Object? raw) {
    String? text;
    if (raw is String) {
      text = raw;
    } else if (raw is List) {
      text = [
        for (final item in raw)
          if (item is Map && item['msg'] != null) item['msg'].toString() else if (item is String) item,
      ].join('\n');
    } else if (raw != null) {
      text = raw.toString();
    }
    text = text?.trim();
    if (text == null || text.isEmpty || text.startsWith('<')) return null;
    return text.length > 300 ? '${text.substring(0, 300)}…' : text;
  }

  /// The headline for server prose when the screen gives none, by status class.
  static String _statusHeadline(int? status) {
    final l = appL10n;
    if (status == null) return l.commonSomethingWrong;
    if (status == 403) return l.srvNotAllowed;
    if (status == 404) return l.srvNotFound;
    if (status >= 500) return l.srvServerProblem;
    if (status >= 400) return l.srvRefused;
    return l.commonSomethingWrong;
  }

  static Map<String, dynamic>? _asMap(Object? raw) =>
      raw is Map ? raw.cast<String, dynamic>() : null;

  /// The user's-language message for one of the server's specific error codes (`ErrorCode` in
  /// the server's `api/app/errors.py`), with the numbers and reasons from its [details], or null
  /// to keep the server's own text. Generic codes (bad_request, conflict, not_found,
  /// internal_error, …) carry varying server prose and keep it; so do the provenance codes,
  /// which only a bug in the app can cause (messages/0005-localized-text/).
  static String? translatedCode(String code, [Map<String, dynamic>? details]) {
    final l = appL10n;
    int? number(String key) => (details?[key] as num?)?.toInt();
    String? text(String key) => details?[key]?.toString();
    return switch (code) {
      // Signing in and the account
      'invalid_credentials' => l.authWrongCredentials,
      'email_not_verified' => l.srvEmailNotVerified,
      'account_banned' => _banned(details),
      'account_deactivated' => l.srvAccountDeactivated,
      'email_taken' => switch (text('provider')) {
          'github' => l.srvEmailTakenWith('GitHub'), // l10n-ignore: brand name
          'apple' => l.srvEmailTakenWith('Apple'), // l10n-ignore: brand name
          _ => l.authEmailExists,
        },
      'pending_verification' => l.srvPendingVerification,
      'apple_email_missing' => l.srvAppleEmailMissing,
      'apple_token_invalid' => l.appleFailed,
      'github_failed' => l.githubFailedRetry,
      'oauth_state_invalid' => l.srvOauthStateInvalid,
      'password_login_unsupported' => l.srvPasswordLoginUnsupported,
      'current_password_incorrect' => l.srvCurrentPasswordWrong,
      'last_auth_method' => l.srvLastLoginMethod,
      'weak_password' => switch (text('reason')) {
          'required' || 'too_short' => l.passwordTooShort,
          'no_letter' => l.passwordNeedsLetter,
          'no_digit' => l.passwordNeedsNumber,
          _ => l.srvWeakPassword,
        },
      'token_invalid' || 'token_expired' => l.authInvalidCode,
      'handle_taken' => l.srvHandleTaken,
      'handle_invalid' => handleReasonMessage(text('reason')),
      'forbidden_role' || 'not_owner' => l.srvNotAllowed,
      // Images, uploads, and storage
      'artwork_duplicate' => l.srvArtworkDuplicate,
      'artwork_unchanged' => l.srvArtworkUnchanged,
      'dimensions_invalid' => number('width') != null && number('height') != null
          ? l.srvDimensionsInvalidSize('${number('width')}×${number('height')}')
          : l.srvDimensionsInvalid,
      'file_too_large' => number('max_bytes') != null
          ? l.srvFileTooLargeMax(formatFileSize(number('max_bytes')!))
          : l.srvFileTooLarge,
      'quota_exceeded' => number('used_bytes') != null && number('limit_bytes') != null
          ? l.srvQuotaExceededUsage(
              formatFileSize(number('used_bytes')!), formatFileSize(number('limit_bytes')!))
          : l.srvQuotaExceeded,
      'image_empty' => l.srvImageEmpty,
      'image_format_unsupported' => details?['allowed'] is List
          ? l.srvImageFormatAllowed([
              for (final f in details!['allowed'] as List) f.toString().toUpperCase()
            ].join(', '))
          : l.srvImageFormat,
      'image_invalid' => l.srvImageInvalid,
      'storage_full' => l.serverStorageFull,
      'storage_unavailable' => l.srvStorageUnavailable,
      'post_has_no_artwork' => l.srvPostNoArtwork,
      'mkpx_invalid' => l.layersNotMkpx,
      'mkpx_too_large' => l.srvMkpxTooLarge,
      'mkpx_not_attached' => l.layersGone,
      'format_not_available' => l.downloadUnavailable,
      // Posts, remixes, and comments
      'post_not_found' => l.srvPostNotFound,
      'post_deleted' => l.srvPostDeleted,
      'post_not_visible' => l.srvPostNotVisible,
      'remixable_conflicts_with_license' => l.srvLicenseConflict,
      'not_remixable' => l.layersNotRemixable,
      'too_many_parents' => l.srvTooManyParents,
      'parent_not_found' => l.srvParentNotFound,
      'remix_not_allowed' => l.srvRemixNotAllowed,
      'lineage_cycle' => l.srvLineageCycle,
      'reaction_cap_reached' => l.reactionsLimit,
      'comment_not_found' => l.srvCommentNotFound,
      'comment_too_deep' => l.srvCommentTooDeep,
      'comment_profanity' => l.srvCommentProfanity,
      'comment_cap_reached' => number('max') != null
          ? l.srvCommentCapMax('${number('max')}')
          : l.srvCommentCap,
      'parent_comment_not_found' => l.srvParentCommentGone,
      'comment_not_deleted' => l.srvCommentNotDeleted,
      // People and safety
      'user_not_found' => l.userNotFound,
      'blocked' => l.errBlockedInteraction,
      'block_cap_reached' => l.srvBlockCap,
      'owner_protected' => l.umdOwnerProtected,
      'mod_hashtags_limit' => number('max') != null
          ? l.srvModTagsLimit('${number('max')}')
          : l.srvRefused,
      'hashtag_too_long' => number('max_length') != null
          ? l.srvHashtagTooLong(number('max_length')!)
          : l.srvRefused,
      // Players
      'player_not_found' => l.srvPlayerNotFound,
      'player_limit_reached' => l.playersMaxReached,
      'registration_code_invalid' => l.playersCodeInvalid,
      'player_already_registered' => l.playersAlreadyRegistered,
      'unsupported_command' => l.srvPlayerUnsupported,
      'invalid_value' => l.srvPlayerInvalidValue,
      // Post Management downloads
      'posts_not_owned' => l.srvPostsNotOwned,
      'bdr_daily_limit' => number('limit') != null
          ? l.srvBdrDailyLimit('${number('limit')}')
          : l.authTooManyRequests,
      'bdr_not_ready' => l.srvBdrNotReady,
      'bdr_expired' => l.srvBdrExpired,
      'bdr_not_found' => l.srvBdrNotFound,
      'rate_limited' => l.authTooManyRequests,
      _ => null,
    };
  }

  /// "This account is banned", with the end date when the ban has one. The server marks a
  /// permanent ban with `permanent: true` and a year-9999 `banned_until`.
  static String _banned(Map<String, dynamic>? details) {
    final l = appL10n;
    final until = DateTime.tryParse(details?['banned_until']?.toString() ?? '');
    if (details?['permanent'] == true || until == null || until.year >= 9999) {
      return l.srvAccountBanned;
    }
    final local = until.toLocal();
    String date;
    try {
      date = DateFormat.yMMMd(l.localeName).format(local);
    } catch (_) {
      // Date names load with the app's localizations; before them, the numeric form.
      date = local.toIso8601String().substring(0, 10);
    }
    return l.srvAccountBannedUntil(date);
  }

  factory ClubError.fromDio(DioException e) {
    final resp = e.response;
    if (resp != null) {
      Duration? retry;
      final ra = resp.headers.value('retry-after');
      if (ra != null) {
        final secs = int.tryParse(ra);
        if (secs != null) retry = Duration(seconds: secs);
      }
      return ClubError.fromBody(resp.statusCode, resp.data, retryAfter: retry);
    }
    final isTimeout = e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout;
    return ClubError(
      code: isTimeout ? 'timeout' : 'network',
      message: isTimeout ? appL10n.errTimeout : appL10n.errNetwork,
    );
  }

  /// 401 — token expired/invalid, or account banned/deactivated.
  bool get isAuth => status == 401;

  /// 429 — rate limited.
  bool get isRateLimited => status == 429;

  /// 403 with the stable `blocked` code — an interaction refused because a
  /// block exists between the two users, in either direction (ugc-safety §5).
  bool get isBlocked => status == 403 && code == 'blocked';

  @override
  String toString() => 'ClubError(${status ?? '-'}, $code): $message'; // l10n-ignore: debug text
}
