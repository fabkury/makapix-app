import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/account_validators.dart';
import '../models/club_error.dart';
import 'account_providers.dart';
import 'api_providers.dart' show authApiProvider;
import 'auth_controller.dart' show authControllerProvider, clubSessionProvider;

/// The steps of the in-app "create account" flow, hosted by one route.
enum RegStep { email, code, signIn, done }

class RegistrationState {
  final RegStep step;
  final String email;
  final bool busy;

  /// A blocking error for the current step (cleared on the next action).
  final String? error;

  /// A non-error notice (e.g. "code sent"), shown above the form.
  final String? notice;

  const RegistrationState({
    this.step = RegStep.email,
    this.email = '',
    this.busy = false,
    this.error,
    this.notice,
  });

  RegistrationState copyWith({
    RegStep? step,
    String? email,
    bool? busy,
    String? error,
    String? notice,
    bool clearError = false,
    bool clearNotice = false,
  }) =>
      RegistrationState(
        step: step ?? this.step,
        email: email ?? this.email,
        busy: busy ?? this.busy,
        error: clearError ? null : (error ?? this.error),
        notice: clearNotice ? null : (notice ?? this.notice),
      );
}

/// Drives email → verify-code → first-sign-in. Holds the in-flight email and,
/// transiently, the temporary password (stashed in [pendingWelcomePasswordProvider]
/// for the onboarding wizard, never kept here). Auto-disposed with its route so a
/// new "Create account" always starts clean.
class RegistrationController extends StateNotifier<RegistrationState> {
  final Ref _ref;
  RegistrationController(this._ref) : super(const RegistrationState());

  /// Step 1 — submit the email: register, then request the verification code.
  /// Routes a `pending_verification` 409 straight to the code step, and an
  /// already-exists 409 back to the sign-in screen (via [onAlreadyExists]).
  Future<void> submitEmail(String rawEmail, {void Function()? onAlreadyExists}) async {
    final email = rawEmail.trim().toLowerCase();
    if (!isValidEmail(email)) {
      state = state.copyWith(error: 'Enter a valid email address.', clearNotice: true);
      return;
    }
    state = state.copyWith(email: email, busy: true, clearError: true, clearNotice: true);
    final api = _ref.read(authApiProvider);
    try {
      await api.register(email);
    } on ClubError catch (e) {
      if (e.status == 409 && e.message.toLowerCase().contains('pending_verification')) {
        // Account exists but is unverified — just (re)send a code and continue.
        await _sendCodeAndAdvance(email);
        return;
      }
      if (e.status == 409) {
        state = state.copyWith(
          busy: false,
          error: 'An account with this email already exists. Try signing in instead.',
        );
        onAlreadyExists?.call();
        return;
      }
      state = state.copyWith(busy: false, error: _friendly(e));
      return;
    }
    await _sendCodeAndAdvance(email);
  }

  Future<void> _sendCodeAndAdvance(String email) async {
    final api = _ref.read(authApiProvider);
    try {
      await api.requestEmailOtp(email);
    } on ClubError catch (e) {
      // The account exists; surface a soft notice but still let them enter a code
      // (e.g. a per-hour cap may apply if they retried).
      state = state.copyWith(
        step: RegStep.code,
        busy: false,
        notice: e.isRateLimited
            ? 'Too many requests — wait a moment before resending.'
            : 'We emailed a 6-digit code and a temporary password.',
      );
      return;
    }
    state = state.copyWith(
      step: RegStep.code,
      busy: false,
      clearError: true,
      notice: 'We emailed a 6-digit code and a temporary password. '
          'Enter the code below.',
    );
  }

  /// Go back to the email step (e.g. "Change email" from the code step).
  void editEmail() =>
      state = state.copyWith(step: RegStep.email, clearError: true, clearNotice: true);

  /// Resend the verification code (rate-limit aware).
  Future<void> resendCode() async {
    if (state.email.isEmpty) return;
    state = state.copyWith(busy: true, clearError: true, clearNotice: true);
    try {
      await _ref.read(authApiProvider).requestEmailOtp(state.email);
      state = state.copyWith(busy: false, notice: 'New code sent.');
    } on ClubError catch (e) {
      state = state.copyWith(busy: false, error: _friendly(e));
    }
  }

  /// Step 2 — verify the 6-digit code.
  Future<void> submitCode(String rawCode) async {
    final code = rawCode.trim();
    if (code.length != 6 || int.tryParse(code) == null) {
      state = state.copyWith(error: 'Enter the 6-digit code from your email.', clearNotice: true);
      return;
    }
    state = state.copyWith(busy: true, clearError: true, clearNotice: true);
    try {
      final res = await _ref.read(authApiProvider).verifyEmailOtp(state.email, code);
      if (!res.verified) {
        state = state.copyWith(busy: false, error: 'Invalid or expired code.');
        return;
      }
      state = state.copyWith(
        step: RegStep.signIn,
        busy: false,
        notice: 'Email verified. Enter the temporary password from your email to finish.',
      );
    } on ClubError catch (e) {
      state = state.copyWith(busy: false, error: _friendly(e));
    }
  }

  /// Step 3 — first sign-in with the emailed temporary password. On success,
  /// stashes it for the wizard and flips the global auth state to signed-in.
  Future<void> firstSignIn(String tempPassword) async {
    final pw = tempPassword.trim();
    if (pw.isEmpty) {
      state = state.copyWith(error: 'Enter the temporary password from your email.');
      return;
    }
    state = state.copyWith(busy: true, clearError: true, clearNotice: true);
    // Stash before the round-trip so the wizard can pre-fill current_password.
    _ref.read(pendingWelcomePasswordProvider.notifier).state = pw;
    try {
      await _ref.read(clubSessionProvider).loginPassword(state.email, pw);
      await _ref.read(authControllerProvider.notifier).reloadMe();
      state = state.copyWith(step: RegStep.done, busy: false);
    } on ClubError catch (e) {
      _ref.read(pendingWelcomePasswordProvider.notifier).state = null;
      state = state.copyWith(busy: false, error: _friendly(e));
    }
  }

  String _friendly(ClubError e) {
    if (e.isRateLimited) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    return e.message;
  }
}

/// Auto-disposed: each "Create account" route gets a fresh controller/state.
final registrationControllerProvider =
    StateNotifierProvider.autoDispose<RegistrationController, RegistrationState>(
        (ref) => RegistrationController(ref));
