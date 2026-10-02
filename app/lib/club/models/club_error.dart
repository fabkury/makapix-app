import 'package:dio/dio.dart';
import 'package:makapix_club/l10n/l10n.dart';

/// Shown wherever an interaction is refused with `403 blocked` (ugc-safety §5 /
/// A8). Direction-neutral by design: a block refuses interactions in **either**
/// direction (D11), so the copy must never disclose who blocked whom.
String get blockedInteractionMessage => appL10n.errBlockedInteraction;

/// A normalized Club API error.
///
/// Maps both the v1 envelope `{ "error": { "code", "message" } }` and FastAPI's
/// legacy `{ "detail": ... }`, plus transport (network/timeout) failures.
class ClubError implements Exception {
  final int? status;
  final String code;
  final String message;
  final Duration? retryAfter;

  ClubError({
    this.status,
    required this.code,
    required this.message,
    this.retryAfter,
  });

  factory ClubError.fromBody(int? status, Object? body, {Duration? retryAfter}) {
    var code = 'unknown';
    var message = appL10n.commonSomethingWrong;
    if (body is Map) {
      final err = body['error'];
      if (err is Map) {
        code = (err['code'] ?? code).toString();
        message = _translatedCode(code) ?? (err['message'] ?? message).toString();
      } else if (body['detail'] != null) {
        code = 'error';
        message = body['detail'].toString();
      }
    } else if (body is String && body.isNotEmpty) {
      message = body;
    }
    return ClubError(status: status, code: code, message: message, retryAfter: retryAfter);
  }

  /// The user's-language message for one of the server's specific error codes (api/app/
  /// errors.py `ErrorCode`), or null to keep the server's own text. Generic codes
  /// (bad_request, conflict, not_found, internal_error, …) carry varying server prose and keep
  /// it (messages/0005-localized-text/).
  static String? _translatedCode(String code) {
    final l = appL10n;
    return switch (code) {
      'email_not_verified' => l.srvEmailNotVerified,
      'weak_password' => l.srvWeakPassword,
      'token_invalid' || 'token_expired' => l.authInvalidCode,
      'account_banned' => l.srvAccountBanned,
      'apple_token_invalid' => l.appleFailed,
      'forbidden_role' || 'not_owner' => l.srvNotAllowed,
      'handle_taken' => l.srvHandleTaken,
      'artwork_duplicate' => l.srvArtworkDuplicate,
      'dimensions_invalid' => l.srvDimensionsInvalid,
      'file_too_large' => l.srvFileTooLarge,
      'quota_exceeded' => l.srvQuotaExceeded,
      'reaction_cap_reached' => l.reactionsLimit,
      'comment_too_deep' => l.srvCommentTooDeep,
      'mkpx_invalid' => l.layersNotMkpx,
      'mkpx_too_large' => l.srvMkpxTooLarge,
      'remixable_conflicts_with_license' => l.srvLicenseConflict,
      'not_remixable' => l.layersNotRemixable,
      'too_many_parents' => l.srvTooManyParents,
      'parent_not_found' => l.srvParentNotFound,
      'remix_not_allowed' => l.srvRemixNotAllowed,
      'lineage_cycle' => l.srvLineageCycle,
      'blocked' => l.errBlockedInteraction,
      'block_cap_reached' => l.srvBlockCap,
      'rate_limited' => l.authTooManyRequests,
      _ => null,
    };
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
