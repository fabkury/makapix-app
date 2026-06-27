import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/auth/pkce.dart';

void main() {
  group('PKCE', () {
    test('S256 challenge matches the RFC 7636 test vector', () {
      // RFC 7636, Appendix B.
      const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      const expected = 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM';
      expect(Pkce.challengeFor(verifier), expected);
    });

    test('challenge is base64url without padding', () {
      final c = Pkce.challengeFor('hello-world');
      expect(c.contains('='), isFalse);
      expect(c.contains('+'), isFalse);
      expect(c.contains('/'), isFalse);
    });

    test('generate() yields a bounded verifier and a matching challenge', () {
      final p = Pkce.generate();
      expect(p.verifier.length, inInclusiveRange(43, 128));
      expect(p.challenge, Pkce.challengeFor(p.verifier));
      expect(p.state, isNotEmpty);
      expect(Pkce.generate().verifier, isNot(p.verifier)); // random per call
    });
  });
}
