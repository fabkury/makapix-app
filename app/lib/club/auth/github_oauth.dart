import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../config/club_config.dart';
import '../models/club_error.dart';
import 'pkce.dart';

/// A successful authorize: the single-use Makapix code + the PKCE verifier to
/// exchange it with.
class GithubAuthResult {
  final String code;
  final String verifier;
  const GithubAuthResult(this.code, this.verifier);
}

/// Drives the server-brokered GitHub sign-in: opens `/auth/github/login` in an
/// in-app browser, captures the return (the dev **HTTPS App Link** or the prod
/// **custom scheme** — see `ClubConfig.oauthRedirectUri`), validates `state`, and
/// returns the code + verifier for the token exchange.
class GithubOAuth {
  final ClubConfig config;
  const GithubOAuth(this.config);

  /// Build the authorize URL. Pure — also exercised by tests.
  Uri buildAuthorizeUrl(Pkce pkce) =>
      Uri.parse('${config.apiBase}/auth/github/login').replace(queryParameters: {
        'redirect_uri': config.oauthRedirectUri,
        'code_challenge': pkce.challenge,
        'code_challenge_method': 'S256',
        'state': pkce.state,
      });

  Future<GithubAuthResult> authorize() async {
    final pkce = Pkce.generate();
    final url = buildAuthorizeUrl(pkce).toString();

    final String callback;
    try {
      callback = await FlutterWebAuth2.authenticate(
        url: url,
        callbackUrlScheme: config.oauthCallbackScheme,
        // Non-ephemeral so the server's HttpOnly oauth_state cookie persists from
        // /github/login to the callback (server gotcha #2).
        options: const FlutterWebAuth2Options(preferEphemeral: false),
      );
    } catch (e) {
      // flutter_web_auth_2 reports a user-dismissed browser as
      // PlatformException(code: "CANCELED"). Anything else (no browser/activity,
      // or an upstream failure the user gave up on) is a real error — don't
      // mislabel it as a deliberate cancel. (Note: when the *return* never reaches
      // the app — e.g. a broken server callback — the user still ends up closing
      // the tab, which surfaces here as CANCELED; that's a server-side problem,
      // not something the app can distinguish at this layer.)
      final cancelled = e is PlatformException &&
          (e.code.toUpperCase() == 'CANCELED' || e.code.toUpperCase() == 'CANCELLED');
      if (cancelled) {
        throw ClubError(code: 'oauth_cancelled', message: 'GitHub sign-in was cancelled.');
      }
      throw ClubError(
        code: 'oauth_failed',
        message: "Couldn't complete GitHub sign-in. Please try again.",
      );
    }

    final cb = Uri.parse(callback);
    final error = cb.queryParameters['error'];
    if (error != null) {
      throw ClubError(
        code: error,
        message: cb.queryParameters['error_description'] ?? 'GitHub sign-in failed.',
      );
    }
    if (cb.queryParameters['state'] != pkce.state) {
      throw ClubError(
        code: 'state_mismatch',
        message: 'Sign-in could not be verified (state mismatch). Please try again.',
      );
    }
    final code = cb.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw ClubError(code: 'no_code', message: 'No authorization code was returned.');
    }
    return GithubAuthResult(code, pkce.verifier);
  }
}
