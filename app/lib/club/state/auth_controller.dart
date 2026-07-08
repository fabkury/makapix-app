import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/club_api_client.dart';
import '../auth/apple_oauth.dart';
import '../auth/club_session.dart';
import '../auth/github_oauth.dart';
import '../config/club_config.dart';
import '../models/club_error.dart';
import '../models/club_user.dart';

// ---- providers (single instances per ProviderContainer) ----

final clubConfigProvider = Provider<ClubConfig>((_) => ClubConfig.defaultConfig);

final clubSessionProvider =
    Provider<ClubSession>((ref) => ClubSession(config: ref.watch(clubConfigProvider)));

final clubApiClientProvider =
    Provider<ClubApiClient>((ref) => ClubApiClient(ref.watch(clubSessionProvider)));

final githubOAuthProvider =
    Provider<GithubOAuth>((ref) => GithubOAuth(ref.watch(clubConfigProvider)));

final appleOAuthProvider = Provider<AppleOAuth>((_) => const AppleOAuth());

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(
    session: ref.watch(clubSessionProvider),
    api: ref.watch(clubApiClientProvider),
    oauth: ref.watch(githubOAuthProvider),
    apple: ref.watch(appleOAuthProvider),
  )..init();
});

/// The signed-in user's stable id (`sub`), or null when signed out. Viewer-scoped keep-alive
/// providers (home feeds, grid-like overrides, notifications) watch this so an account switch
/// (A → signed out → B) rebuilds them, instead of leaking user A's server-filtered feed content
/// (e.g. monitored-hashtag posts), likes, or notifications into user B's session. The `select`
/// means token refreshes and same-user profile edits (`reloadMe`) rebuild nothing.
final currentUserSubProvider =
    Provider<String?>((ref) => ref.watch(authControllerProvider.select((s) => s.me?.user.sub)));

// ---- state ----

enum AuthStatus { loading, signedOut, signingIn, signedIn, error }

class AuthState {
  final AuthStatus status;
  final ClubMe? me;
  final String? error;

  /// The machine-readable [ClubError.code] for a failure (e.g.
  /// `email_not_verified`), so the UI can offer a tailored next step.
  final String? errorCode;

  const AuthState(this.status, {this.me, this.error, this.errorCode});

  const AuthState.loading() : this(AuthStatus.loading);
  const AuthState.signedOut() : this(AuthStatus.signedOut);
  const AuthState.signingIn() : this(AuthStatus.signingIn);
  AuthState.signedIn(ClubMe me) : this(AuthStatus.signedIn, me: me);
  const AuthState.failure(String message, {String? code})
      : this(AuthStatus.error, error: message, errorCode: code);

  bool get isSignedIn => status == AuthStatus.signedIn;
  bool get isBusy => status == AuthStatus.loading || status == AuthStatus.signingIn;

  /// True when a failure means the email is registered but unverified — the UI
  /// routes these to the verify-email screen. Tolerant of envelope differences.
  bool get isUnverified =>
      status == AuthStatus.error &&
      (errorCode == 'email_not_verified' ||
          (error?.toLowerCase().contains('not verified') ?? false));
}

/// Orchestrates sign-in/out and exposes [AuthState] to the UI. The editor never
/// waits on this — auth runs in the background and gates only Club actions.
class AuthController extends StateNotifier<AuthState> {
  final ClubSession session;
  final ClubApiClient api;
  final GithubOAuth oauth;
  final AppleOAuth apple;

  AuthController({
    required this.session,
    required this.api,
    required this.oauth,
    this.apple = const AppleOAuth(),
  }) : super(const AuthState.loading()) {
    // A background refresh failure clears tokens but can't drive our state directly; listen for it
    // so we leave the signed-in UI instead of becoming a zombie session with no token. [audit F-4b]
    session.onSessionInvalidated = _onSessionInvalidated;
  }

  void _onSessionInvalidated() {
    if (mounted && state.status != AuthStatus.signedOut) {
      state = const AuthState.signedOut();
    }
  }

  @override
  void dispose() {
    session.onSessionInvalidated = null;
    super.dispose();
  }

  /// Load persisted tokens; if present, verify by fetching /auth/me.
  Future<void> init() async {
    try {
      await session.load();
    } catch (_) {
      // Secure storage can throw (e.g. an Android Keystore reset). Degrade to signed-out rather
      // than hanging on the loading spinner forever; drop any corrupt entry. [audit F-5]
      try {
        await session.clear();
      } catch (_) {/* best-effort */}
      state = const AuthState.signedOut();
      return;
    }
    if (!session.isSignedIn) {
      state = const AuthState.signedOut();
      return;
    }
    await _loadMe();
  }

  /// Re-fetch `/auth/me` and flip to signed-in (or signed-out on an auth error).
  /// Used after the in-app registration sign-in and after onboarding /
  /// account-management changes so the UI reflects the server immediately.
  Future<void> reloadMe() => _loadMe();

  Future<void> _loadMe() async {
    try {
      final me = ClubMe.fromJson(await api.me());
      state = AuthState.signedIn(me);
    } on ClubError catch (e) {
      if (e.isAuth) {
        await session.clear();
        state = const AuthState.signedOut();
      } else {
        state = AuthState.failure(e.message);
      }
    } catch (_) {
      state = const AuthState.failure('Unexpected error loading your account.');
    }
  }

  Future<void> loginPassword(String email, String password) async {
    state = const AuthState.signingIn();
    try {
      await session.loginPassword(email.trim(), password);
      await _loadMe();
    } on ClubError catch (e) {
      state = AuthState.failure(e.message, code: e.code);
    } catch (_) {
      state = const AuthState.failure('Unexpected error. Please try again.');
    }
  }

  Future<void> loginGithub() async {
    state = const AuthState.signingIn();
    try {
      final res = await oauth.authorize();
      await session.exchangeAuthCode(res.code, res.verifier);
      await _loadMe();
    } on ClubError catch (e) {
      state = AuthState.failure(e.message);
    } catch (_) {
      state = const AuthState.failure('Unexpected error. Please try again.');
    }
  }

  /// Sign in with Apple (iOS 13+). Gated behind [ClubConfig.kAppleSignInEnabled] +
  /// [AppleOAuth.isAvailable]; the UI only shows the button when both hold. Mirrors
  /// [loginGithub]: grab the Apple credential, exchange it for Makapix tokens, load /me.
  Future<void> loginApple() async {
    state = const AuthState.signingIn();
    try {
      final r = await apple.authorize();
      await session.loginApple(
        identityToken: r.identityToken,
        rawNonce: r.rawNonce,
        authorizationCode: r.authorizationCode,
        givenName: r.givenName,
        familyName: r.familyName,
        email: r.email,
      );
      await _loadMe();
    } on ClubError catch (e) {
      // A user-cancelled sheet returns to the form quietly rather than as an error.
      if (e.code == 'apple_cancelled') {
        state = const AuthState.signedOut();
      } else {
        state = AuthState.failure(e.message, code: e.code);
      }
    } catch (_) {
      state = const AuthState.failure('Unexpected error. Please try again.');
    }
  }

  Future<void> logout() async {
    await session.logout();
    state = const AuthState.signedOut();
  }

  /// Reflect a settings change to the monitored-hashtag filter in the in-memory
  /// session, so the UI sees it without a full `/auth/me` round-trip. (Feeds are
  /// filtered server-side, so callers also re-fetch them after this.)
  void updateApprovedHashtags(List<String> tags) {
    final me = state.me;
    if (me == null) return;
    state = AuthState.signedIn(me.copyWith(user: me.user.copyWith(approvedHashtags: tags)));
  }

  /// Dismiss an error back to the sign-in form.
  void reset() => state = const AuthState.signedOut();
}
