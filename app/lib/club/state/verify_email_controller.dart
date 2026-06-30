import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/club_error.dart';
import 'api_providers.dart' show authApiProvider;
import 'auth_controller.dart' show authControllerProvider, clubSessionProvider;

class VerifyEmailState {
  final bool busy;
  final bool verified;
  final String? error;
  final String? notice;
  const VerifyEmailState({this.busy = false, this.verified = false, this.error, this.notice});

  VerifyEmailState copyWith({
    bool? busy,
    bool? verified,
    String? error,
    String? notice,
    bool clearError = false,
    bool clearNotice = false,
  }) =>
      VerifyEmailState(
        busy: busy ?? this.busy,
        verified: verified ?? this.verified,
        error: clearError ? null : (error ?? this.error),
        notice: clearNotice ? null : (notice ?? this.notice),
      );
}

/// Standalone email verification — entering the 6-digit OTP (and resending it)
/// outside the create-account flow. Reached from the sign-in screen when a login
/// fails with `email_not_verified`. When a [password] is known (the one the user
/// just typed on the sign-in form), a successful verify signs them straight in.
class VerifyEmailController extends StateNotifier<VerifyEmailState> {
  final Ref _ref;
  VerifyEmailController(this._ref) : super(const VerifyEmailState());

  /// (Re)send a verification code to [email].
  Future<void> resend(String email) async {
    state = state.copyWith(busy: true, clearError: true, clearNotice: true);
    try {
      await _ref.read(authApiProvider).requestEmailOtp(email);
      state = state.copyWith(busy: false, notice: 'New code sent.');
    } on ClubError catch (e) {
      state = state.copyWith(
          busy: false,
          error: e.isRateLimited
              ? 'Too many requests. Please wait a moment and try again.'
              : e.message);
    }
  }

  /// Verify [code]. On success, if [password] is provided, sign in (flipping the
  /// global auth state); otherwise just record that the email is verified so the
  /// user can return to the sign-in screen.
  Future<void> submitCode(String email, String rawCode, {String? password}) async {
    final code = rawCode.trim();
    if (code.length != 6 || int.tryParse(code) == null) {
      state = state.copyWith(error: 'Enter the 6-digit code from your email.', clearNotice: true);
      return;
    }
    state = state.copyWith(busy: true, clearError: true, clearNotice: true);
    try {
      final res = await _ref.read(authApiProvider).verifyEmailOtp(email, code);
      if (!res.verified) {
        state = state.copyWith(busy: false, error: 'Invalid or expired code.');
        return;
      }
      if (password != null && password.isNotEmpty) {
        try {
          await _ref.read(clubSessionProvider).loginPassword(email, password);
          await _ref.read(authControllerProvider.notifier).reloadMe();
          state = state.copyWith(busy: false, verified: true);
          return;
        } on ClubError {
          // Verified, but the saved password didn't work — let them sign in manually.
          state = state.copyWith(
              busy: false,
              verified: true,
              notice: 'Email verified. Please sign in with your password.');
          return;
        }
      }
      state = state.copyWith(
          busy: false, verified: true, notice: 'Email verified. You can now sign in.');
    } on ClubError catch (e) {
      state = state.copyWith(busy: false, error: e.message);
    }
  }
}

final verifyEmailControllerProvider =
    StateNotifierProvider.autoDispose<VerifyEmailController, VerifyEmailState>(
        (ref) => VerifyEmailController(ref));
