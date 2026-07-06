import 'package:dio/dio.dart';

/// Shown wherever an interaction is refused with `403 blocked` (ugc-safety §5 /
/// A8). Direction-neutral by design: a block refuses interactions in **either**
/// direction (D11), so the copy must never disclose who blocked whom.
const String kBlockedInteractionMessage = "You can't interact with this user.";

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
    var message = 'Something went wrong.';
    if (body is Map) {
      final err = body['error'];
      if (err is Map) {
        code = (err['code'] ?? code).toString();
        message = (err['message'] ?? message).toString();
      } else if (body['detail'] != null) {
        code = 'error';
        message = body['detail'].toString();
      }
    } else if (body is String && body.isNotEmpty) {
      message = body;
    }
    return ClubError(status: status, code: code, message: message, retryAfter: retryAfter);
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
      message: isTimeout
          ? 'The request timed out. Please try again.'
          : 'Network error — check your connection.',
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
  String toString() => 'ClubError(${status ?? '-'}, $code): $message';
}
