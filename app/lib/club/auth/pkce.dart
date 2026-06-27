import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// PKCE (RFC 7636) material for the server-brokered GitHub flow, plus a CSRF `state`.
///
/// GitHub itself has no PKCE; this protects the app↔server leg (SPEC-CLUB §6.3 /
/// the confirmed contract). S256 only.
class Pkce {
  final String verifier;
  final String challenge; // BASE64URL_NOPAD(SHA256(verifier))
  final String state;

  const Pkce({required this.verifier, required this.challenge, required this.state});

  static final Random _rng = Random.secure();

  /// base64url, no padding (RFC 4648 §5 without `=`).
  static String _b64u(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

  static String _randomString(int bytes) =>
      _b64u(List<int>.generate(bytes, (_) => _rng.nextInt(256)));

  /// S256 challenge for a verifier: `BASE64URL_NOPAD(SHA256(ASCII(verifier)))`.
  static String challengeFor(String verifier) =>
      _b64u(sha256.convert(ascii.encode(verifier)).bytes);

  /// Fresh verifier (43–128 chars), its S256 challenge, and a random state.
  factory Pkce.generate() {
    // 64 random bytes -> ~86 base64url chars, comfortably within 43..128.
    final verifier = _randomString(64);
    return Pkce(
      verifier: verifier,
      challenge: challengeFor(verifier),
      state: _randomString(24),
    );
  }
}
