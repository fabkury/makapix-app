import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/account_validators.dart';
import '../models/club_error.dart';
import 'account_providers.dart';
import 'auth_controller.dart' show authControllerProvider, clubApiClientProvider;

/// Live availability status for the handle field.
enum HandleCheck { idle, checking, available, taken, invalid }

class OnboardingState {
  final bool busy;
  final HandleCheck handleCheck;
  final String handleMessage;
  const OnboardingState({
    this.busy = false,
    this.handleCheck = HandleCheck.idle,
    this.handleMessage = '',
  });

  OnboardingState copyWith({bool? busy, HandleCheck? handleCheck, String? handleMessage}) =>
      OnboardingState(
        busy: busy ?? this.busy,
        handleCheck: handleCheck ?? this.handleCheck,
        handleMessage: handleMessage ?? this.handleMessage,
      );
}

/// Backs the welcome wizard: live handle checks plus the step-submit actions.
/// Each action returns a user-facing error string, or null on success, so the
/// widget stays free of try/catch. Mutating actions re-load `/auth/me` so the
/// rest of the app reflects the change immediately.
class OnboardingController extends StateNotifier<OnboardingState> {
  final Ref _ref;
  OnboardingController(this._ref) : super(const OnboardingState());

  /// The handle whose check is currently in flight — used to drop stale results
  /// when the user keeps typing (the widget debounces and calls with the latest).
  String _inflight = '';

  /// Live availability check. Validates locally first to avoid a pointless call.
  Future<void> checkHandle(String raw, {String? currentHandle}) async {
    final handle = raw.trim();
    if (currentHandle != null && handle.toLowerCase() == currentHandle.toLowerCase()) {
      state = state.copyWith(handleCheck: HandleCheck.idle, handleMessage: '');
      return;
    }
    final localErr = validateHandleError(handle);
    if (localErr != null) {
      state = state.copyWith(handleCheck: HandleCheck.invalid, handleMessage: localErr);
      return;
    }
    _inflight = handle;
    state = state.copyWith(handleCheck: HandleCheck.checking, handleMessage: 'Checking…');
    try {
      final res = await _ref.read(clubApiClientProvider).checkHandle(handle);
      if (_inflight != handle) return; // a newer keystroke superseded this one
      state = state.copyWith(
        handleCheck: res.available ? HandleCheck.available : HandleCheck.taken,
        handleMessage: res.message,
      );
    } on ClubError catch (e) {
      if (_inflight != handle) return;
      state = state.copyWith(handleCheck: HandleCheck.idle, handleMessage: e.message);
    }
  }

  void resetHandleCheck() =>
      state = state.copyWith(handleCheck: HandleCheck.idle, handleMessage: '');

  /// "Set your password" step. [current] is the emailed temporary password.
  ///
  /// Note: the stashed temp password is **not** cleared here — doing so would
  /// shrink the wizard's step list (the password step is gated on it) and skip
  /// the next step. It is cleared in [finish] instead.
  Future<String?> setPassword(String current, String next) async {
    final err = validatePasswordError(next);
    if (err != null) return err;
    return _run(() async {
      await _ref.read(clubApiClientProvider).changePassword(current, next);
    });
  }

  Future<String?> saveHandle(String handle) async {
    final err = validateHandleError(handle);
    if (err != null) return err;
    return _run(() async {
      await _ref.read(clubApiClientProvider).changeHandle(handle.trim());
      await _ref.read(authControllerProvider.notifier).reloadMe();
    });
  }

  /// Save the optional profile fields. Either or both may be provided.
  Future<String?> saveProfile(
    String userKey, {
    String? bio,
    List<int>? avatarBytes,
    String? avatarFilename,
  }) =>
      _run(() async {
        final client = _ref.read(clubApiClientProvider);
        if (avatarBytes != null && avatarBytes.isNotEmpty) {
          await client.uploadAvatar(userKey, avatarBytes, avatarFilename ?? 'avatar.png');
        }
        if (bio != null) {
          await client.updateBio(userKey, bio.trim());
        }
        await _ref.read(authControllerProvider.notifier).reloadMe();
      });

  /// Finish onboarding: mark welcome complete, clear any stashed temp password,
  /// and refresh `/auth/me` (flips `needs_welcome`, dropping the wizard gate).
  Future<String?> finish() => _run(() async {
        await _ref.read(clubApiClientProvider).completeWelcome();
        _ref.read(pendingWelcomePasswordProvider.notifier).state = null;
        await _ref.read(authControllerProvider.notifier).reloadMe();
      });

  Future<String?> _run(Future<void> Function() action) async {
    state = state.copyWith(busy: true);
    try {
      await action();
      if (mounted) state = state.copyWith(busy: false);
      return null;
    } on ClubError catch (e) {
      if (mounted) state = state.copyWith(busy: false);
      return e.message;
    } catch (_) {
      if (mounted) state = state.copyWith(busy: false);
      return 'Something went wrong. Please try again.';
    }
  }
}

final onboardingControllerProvider =
    StateNotifierProvider.autoDispose<OnboardingController, OnboardingState>(
        (ref) => OnboardingController(ref));
