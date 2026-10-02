import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:makapix_club/l10n/l10n.dart';

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
  final Duration? retryAfter;

  /// [message] says what went wrong on its own (a known code, a lost connection), so it
  /// beats a screen's generic headline.
  final bool specific;

  ClubError({
    this.status,
    required this.code,
    required this.message,
    this.serverText,
    this.retryAfter,
    this.specific = true,
  });

  factory ClubError.fromBody(int? status, Object? body, {Duration? retryAfter}) {
    // A download (`ResponseType.bytes`) hands its error body over undecoded.
    if (body is List<int>) body = _decodeBytes(body);
    var code = 'unknown';
    String? own;
    String? prose;
    if (body is Map) {
      final err = body['error'];
      if (err is Map) {
        code = (err['code'] ?? code).toString();
        own = _translatedCode(code);
        if (own == null) prose = _prose(err['message']);
      } else if (body['detail'] != null) {
        code = 'error';
        prose = _prose(body['detail']);
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
      retryAfter: retryAfter,
      specific: own != null,
    );
  }

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
