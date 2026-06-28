import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/club_api_client.dart';
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

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(
    session: ref.watch(clubSessionProvider),
    api: ref.watch(clubApiClientProvider),
    oauth: ref.watch(githubOAuthProvider),
  )..init();
});

// ---- state ----

enum AuthStatus { loading, signedOut, signingIn, signedIn, error }

class AuthState {
  final AuthStatus status;
  final ClubMe? me;
  final String? error;
  const AuthState(this.status, {this.me, this.error});

  const AuthState.loading() : this(AuthStatus.loading);
  const AuthState.signedOut() : this(AuthStatus.signedOut);
  const AuthState.signingIn() : this(AuthStatus.signingIn);
  AuthState.signedIn(ClubMe me) : this(AuthStatus.signedIn, me: me);
  const AuthState.failure(String message) : this(AuthStatus.error, error: message);

  bool get isSignedIn => status == AuthStatus.signedIn;
  bool get isBusy => status == AuthStatus.loading || status == AuthStatus.signingIn;
}

/// Orchestrates sign-in/out and exposes [AuthState] to the UI. The editor never
/// waits on this — auth runs in the background and gates only Club actions.
class AuthController extends StateNotifier<AuthState> {
  final ClubSession session;
  final ClubApiClient api;
  final GithubOAuth oauth;

  AuthController({required this.session, required this.api, required this.oauth})
      : super(const AuthState.loading()) {
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
      state = AuthState.failure(e.message);
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

  Future<void> logout() async {
    await session.logout();
    state = const AuthState.signedOut();
  }

  /// Dismiss an error back to the sign-in form.
  void reset() => state = const AuthState.signedOut();
}
