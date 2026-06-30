import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/account_validators.dart';
import '../models/club_error.dart';
import 'api_providers.dart' show authApiProvider;

enum ResetStep { request, confirm, done }

class PasswordResetState {
  final ResetStep step;
  final String email;
  final bool busy;
  final String? error;
  final String? notice;

  const PasswordResetState({
    this.step = ResetStep.request,
    this.email = '',
    this.busy = false,
    this.error,
    this.notice,
  });

  PasswordResetState copyWith({
    ResetStep? step,
    String? email,
    bool? busy,
    String? error,
    String? notice,
    bool clearError = false,
    bool clearNotice = false,
  }) =>
      PasswordResetState(
        step: step ?? this.step,
        email: email ?? this.email,
        busy: busy ?? this.busy,
        error: clearError ? null : (error ?? this.error),
        notice: clearNotice ? null : (notice ?? this.notice),
      );
}

/// Forgot-password reset over the numeric-OTP endpoints. The request step is
/// existence-neutral (the server never reveals whether the email exists), so we
/// always advance to the code step.
class PasswordResetController extends StateNotifier<PasswordResetState> {
  final Ref _ref;
  PasswordResetController(this._ref) : super(const PasswordResetState());

  Future<void> requestCode(String rawEmail) async {
    final email = rawEmail.trim().toLowerCase();
    if (!isValidEmail(email)) {
      state = state.copyWith(error: 'Enter a valid email address.', clearNotice: true);
      return;
    }
    state = state.copyWith(email: email, busy: true, clearError: true, clearNotice: true);
    try {
      await _ref.read(authApiProvider).requestPasswordOtp(email);
      state = state.copyWith(
        step: ResetStep.confirm,
        busy: false,
        notice: 'If an account exists for this email, we sent a 6-digit reset code.',
      );
    } on ClubError catch (e) {
      state = state.copyWith(
          busy: false,
          error: e.isRateLimited
              ? 'Too many requests. Please wait a moment and try again.'
              : e.message);
    }
  }

  Future<void> resendCode() async {
    if (state.email.isEmpty) return;
    state = state.copyWith(busy: true, clearError: true, clearNotice: true);
    try {
      await _ref.read(authApiProvider).requestPasswordOtp(state.email);
      state = state.copyWith(busy: false, notice: 'New code sent.');
    } on ClubError catch (e) {
      state = state.copyWith(busy: false, error: e.message);
    }
  }

  Future<void> confirm(String rawCode, String newPassword) async {
    final code = rawCode.trim();
    if (code.length != 6 || int.tryParse(code) == null) {
      state = state.copyWith(error: 'Enter the 6-digit code from your email.', clearNotice: true);
      return;
    }
    final pwError = validatePasswordError(newPassword);
    if (pwError != null) {
      state = state.copyWith(error: pwError, clearNotice: true);
      return;
    }
    state = state.copyWith(busy: true, clearError: true, clearNotice: true);
    try {
      await _ref.read(authApiProvider).confirmPasswordOtp(state.email, code, newPassword);
      state = state.copyWith(
          step: ResetStep.done,
          busy: false,
          notice: 'Password updated. You can now sign in with your new password.');
    } on ClubError catch (e) {
      state = state.copyWith(busy: false, error: e.message);
    }
  }
}

final passwordResetControllerProvider =
    StateNotifierProvider.autoDispose<PasswordResetController, PasswordResetState>(
        (ref) => PasswordResetController(ref));
