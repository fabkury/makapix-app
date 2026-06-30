import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/account_validators.dart';
import '../models/club_error.dart';
import 'account_providers.dart';
import 'api_providers.dart' show authApiProvider;
import 'auth_controller.dart' show authControllerProvider, clubSessionProvider;

/// The steps of the in-app "create account" flow, hosted by one route.
enum RegStep { details, code, signIn, done }

class RegistrationState {
  final RegStep step;
  final String email;
  final bool busy;

  /// A blocking error for the current step (cleared on the next action).
  final String? error;

  /// A non-error notice (e.g. "code sent"), shown above the form.
  final String? notice;

  const RegistrationState({
    this.step = RegStep.details,
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

/// Drives details (email + chosen password) → verify-code → sign-in.
///
/// On the **A2** path (server returns `verification_method: "otp"`) the user's
/// chosen password is already set server-side, so after the code is verified we
/// sign in straight away — no temp-password screen, and the wizard skips its "set
/// password" step. On a **legacy/non-A2** server (`"link"`, or an unverified 409)
/// we fall back to: request an OTP, then have the user enter the emailed temporary
/// password (stashed for the wizard's set-password step).
///
/// Auto-disposed with its route so a new "Create account" always starts clean.
class RegistrationController extends StateNotifier<RegistrationState> {
  final Ref _ref;
  RegistrationController(this._ref) : super(const RegistrationState());

  /// The password the user chose at signup — held only in memory for the auto
  /// sign-in after verification; never persisted.
  String? _chosenPassword;

  /// True when the server did not take the chosen-password OTP path → fall back
  /// to the temp-password flow.
  bool _legacy = false;

  /// Visible for tests: whether the flow is on the legacy temp-password path.
  bool get isLegacy => _legacy;

  /// Step 1 — submit email + chosen password: register, then route by the
  /// server's `verification_method`. An already-exists 409 routes back to
  /// sign-in (via [onAlreadyExists]).
  Future<void> submitDetails(String rawEmail, String password,
      {void Function()? onAlreadyExists}) async {
    final email = rawEmail.trim().toLowerCase();
    if (!isValidEmail(email)) {
      state = state.copyWith(error: 'Enter a valid email address.', clearNotice: true);
      return;
    }
    final pwErr = validatePasswordError(password);
    if (pwErr != null) {
      state = state.copyWith(error: pwErr, clearNotice: true);
      return;
    }
    state = state.copyWith(email: email, busy: true, clearError: true, clearNotice: true);
    _chosenPassword = password;
    try {
      final res = await _ref.read(authApiProvider).register(email, password: password);
      _legacy = !res.isOtp;
      // Legacy/non-A2 server didn't email a code on its own — request one.
      if (_legacy) await _safeRequestOtp(email);
      state = state.copyWith(step: RegStep.code, busy: false, clearError: true, notice: _codeNotice());
    } on ClubError catch (e) {
      if (e.status == 409 && e.message.toLowerCase().contains('pending_verification')) {
        // A non-A2 server (no "resume sign-up") — fall back to the temp-password flow.
        _legacy = true;
        await _safeRequestOtp(email);
        state =
            state.copyWith(step: RegStep.code, busy: false, clearError: true, notice: _codeNotice());
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
    }
  }

  String _codeNotice() => _legacy
      ? 'We emailed a 6-digit code and a temporary password. Enter the code below.'
      : 'We emailed a 6-digit code to ${state.email}. Enter it below.';

  Future<void> _safeRequestOtp(String email) async {
    try {
      await _ref.read(authApiProvider).requestEmailOtp(email);
    } on ClubError {
      // Best-effort (a per-hour cap may apply on a retry); the user can resend.
    }
  }

  /// Go back to the details step (e.g. "Change email" from the code step).
  void editEmail() =>
      state = state.copyWith(step: RegStep.details, clearError: true, clearNotice: true);

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

  /// Step 2 — verify the 6-digit code. On the A2 path this also signs the user in
  /// with their chosen password; on the legacy path it advances to the
  /// temp-password sign-in step.
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
      if (!_legacy && _chosenPassword != null) {
        // A2: the password is already set — sign in now (no temp-password screen,
        // and no wizard "set password" step).
        await _completeSignIn(_chosenPassword!, stash: false);
      } else {
        state = state.copyWith(
          step: RegStep.signIn,
          busy: false,
          notice: 'Email verified. Enter the temporary password from your email to finish.',
        );
      }
    } on ClubError catch (e) {
      state = state.copyWith(busy: false, error: _friendly(e));
    }
  }

  /// Legacy step 3 — sign in with the emailed temporary password (the user types
  /// it). Stashed so the wizard's "set password" step can replace it.
  Future<void> firstSignIn(String tempPassword) async {
    final pw = tempPassword.trim();
    if (pw.isEmpty) {
      state = state.copyWith(error: 'Enter the temporary password from your email.');
      return;
    }
    await _completeSignIn(pw, stash: true);
  }

  /// Sign in + flip global auth state. [stash] keeps the password for the wizard's
  /// "set password" step (legacy temp-password path); false on A2 where the user
  /// already chose their password.
  Future<void> _completeSignIn(String password, {required bool stash}) async {
    state = state.copyWith(busy: true, clearError: true, clearNotice: true);
    _ref.read(pendingWelcomePasswordProvider.notifier).state = stash ? password : null;
    try {
      await _ref.read(clubSessionProvider).loginPassword(state.email, password);
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
