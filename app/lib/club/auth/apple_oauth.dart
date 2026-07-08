import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../models/club_error.dart';

/// A successful "Sign in with Apple" grab.
///
/// - [identityToken] — the JWT the **server** verifies against Apple's public keys
///   (`iss=https://appleid.apple.com`, `aud=club.makapix.app` = our bundle id).
/// - [authorizationCode] — a one-time code the server can exchange with Apple.
/// - [rawNonce] — the server compares `sha256(rawNonce)` to the token's `nonce`
///   claim (replay protection); we send Apple the *hashed* nonce and the server the
///   *raw* one.
/// - [givenName]/[familyName]/[email] — Apple returns these **only on the very first
///   sign-in** for a given Apple ID, so the server must persist them then.
class AppleAuthResult {
  final String identityToken;
  final String? authorizationCode;
  final String rawNonce;
  final String? givenName;
  final String? familyName;
  final String? email;
  const AppleAuthResult({
    required this.identityToken,
    required this.rawNonce,
    this.authorizationCode,
    this.givenName,
    this.familyName,
    this.email,
  });
}

/// Drives the native Sign in with Apple sheet (`ASAuthorizationController`, via the
/// sign_in_with_apple plugin) and returns the identity token + raw nonce for the
/// server token exchange. iOS 13+ / macOS 10.15+ only — callers MUST gate on
/// [isAvailable] (the button self-hides on iOS 12 and non-Apple platforms).
///
/// This is the app-side half of Apple guideline 4.8 support. It stays dormant until
/// [ClubConfig.kAppleSignInEnabled] is flipped on (once the server `apple_identity_token`
/// grant ships — see docs/ios-release/apple-signin-server.md).
class AppleOAuth {
  const AppleOAuth();

  /// True only where the native flow exists. Cheap to call before rendering the button.
  Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    if (!Platform.isIOS && !Platform.isMacOS) return false;
    return SignInWithApple.isAvailable();
  }

  /// A cryptographically-random nonce (unreserved URL chars only).
  String _randomNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final rng = Random.secure();
    return List.generate(length, (_) => charset[rng.nextInt(charset.length)]).join();
  }

  Future<AppleAuthResult> authorize() async {
    final rawNonce = _randomNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
    try {
      final cred = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
      final idToken = cred.identityToken;
      if (idToken == null || idToken.isEmpty) {
        throw ClubError(
          code: 'apple_no_token',
          message: 'Apple did not return an identity token. Please try again.',
        );
      }
      return AppleAuthResult(
        identityToken: idToken,
        authorizationCode: cred.authorizationCode,
        rawNonce: rawNonce,
        givenName: cred.givenName,
        familyName: cred.familyName,
        email: cred.email,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw ClubError(code: 'apple_cancelled', message: 'Apple sign-in was cancelled.');
      }
      throw ClubError(
        code: 'apple_failed',
        message: "Couldn't complete Apple sign-in. Please try again.",
      );
    } on ClubError {
      rethrow;
    } catch (_) {
      throw ClubError(
        code: 'apple_failed',
        message: "Couldn't complete Apple sign-in. Please try again.",
      );
    }
  }
}
