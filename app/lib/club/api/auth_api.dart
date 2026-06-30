import 'package:dio/dio.dart';

import '../config/club_config.dart';
import '../models/account.dart';
import '../models/club_error.dart';

/// The **unauthenticated** account-lifecycle endpoints: registration, the email /
/// password numeric-OTP flows, and the public handle-availability check.
///
/// Uses a *plain* Dio (no bearer, no 401→refresh interceptor) — these calls are
/// pre-auth, so they must never touch the authed client's refresh machinery.
/// The authed counterparts (change-password/handle, complete-welcome, providers,
/// avatar/bio) live on [ClubApiClient].
class AuthApi {
  final ClubConfig config;
  final Dio _dio;

  AuthApi(this.config, {Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: config.apiBase,
              contentType: 'application/json',
              connectTimeout: ClubConfig.connectTimeout,
              receiveTimeout: ClubConfig.ioTimeout,
              sendTimeout: ClubConfig.ioTimeout,
            ));

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw ClubError.fromDio(e);
    }
  }

  /// `POST /auth/register { email, password? }` → `{ user_id, email, handle,
  /// verification_method }`. With a `password` (A2) the server emails a single OTP
  /// and `verification_method: "otp"`; without one it's the legacy link path.
  /// Throws [ClubError] (status 409) for already-exists; on a non-A2 server an
  /// unverified collision is `pending_verification` (A2 resumes with 200 instead).
  Future<RegisterResult> register(String email, {String? password}) => _guard(() async {
        final resp = await _dio.post('/auth/register',
            data: {'email': email, 'password': ?password});
        return RegisterResult.fromJson((resp.data as Map).cast<String, dynamic>());
      });

  /// `POST /auth/email-otp/request { email }` — emails a 6-digit verification code
  /// (existence-neutral 200, so callers can't enumerate accounts).
  Future<void> requestEmailOtp(String email) => _guard(() async {
        await _dio.post('/auth/email-otp/request', data: {'email': email});
      });

  /// `POST /auth/email-otp/verify { email, code }` → marks the email verified.
  Future<VerifyEmailResult> verifyEmailOtp(String email, String code) => _guard(() async {
        final resp =
            await _dio.post('/auth/email-otp/verify', data: {'email': email, 'code': code});
        return VerifyEmailResult.fromJson((resp.data as Map).cast<String, dynamic>());
      });

  /// `POST /auth/password-otp/request { email }` — emails a 6-digit reset code
  /// (existence-neutral 200).
  Future<void> requestPasswordOtp(String email) => _guard(() async {
        await _dio.post('/auth/password-otp/request', data: {'email': email});
      });

  /// `POST /auth/password-otp/confirm { email, code, new_password }`.
  Future<void> confirmPasswordOtp(String email, String code, String newPassword) =>
      _guard(() async {
        await _dio.post('/auth/password-otp/confirm',
            data: {'email': email, 'code': code, 'new_password': newPassword});
      });

  /// `POST /auth/check-handle-availability { handle }` (usable unauthenticated).
  Future<HandleAvailability> checkHandleAvailability(String handle) => _guard(() async {
        final resp = await _dio.post('/auth/check-handle-availability', data: {'handle': handle});
        return HandleAvailability.fromJson((resp.data as Map).cast<String, dynamic>());
      });
}
