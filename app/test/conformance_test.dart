import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/models/server_config.dart';
import 'package:makapix_club/club/publish/conformance.dart';

void main() {
  const c = ClubConformance(ClubServerConfig.fallback);
  ConformanceResult chk(int w, int h, {int bytes = 1000, String fmt = 'png'}) =>
      c.check(width: w, height: h, frameCount: 1, byteLength: bytes, format: fmt);

  test('free-form 128..256 accepted', () {
    expect(chk(128, 128).ok, isTrue);
    expect(chk(256, 256).ok, isTrue);
    expect(chk(200, 150).ok, isTrue);
  });

  test('whitelisted small sizes accepted incl. rotations', () {
    expect(chk(32, 32).ok, isTrue);
    expect(chk(64, 128).ok, isTrue);
    expect(chk(128, 64).ok, isTrue);
    expect(chk(8, 16).ok, isTrue);
  });

  test('under-min non-whitelisted rejected with a suggestion', () {
    final r = chk(100, 100);
    expect(r.ok, isFalse);
    expect(r.issues, contains(ConformanceIssue.underMinNotWhitelisted));
    expect(r.nearestSize, isNotNull);
  });

  test('over-max rejected with a suggestion', () {
    final r = chk(300, 300);
    expect(r.ok, isFalse);
    expect(r.issues, contains(ConformanceIssue.overMax));
    expect(r.nearestSize, isNotNull);
  });

  test('every suggested size is itself conformant', () {
    for (final dims in [
      [100, 100],
      [300, 300],
      [300, 100],
      [30, 30],
      [257, 64],
    ]) {
      final r = chk(dims[0], dims[1]);
      expect(r.ok, isFalse, reason: '$dims should be non-conformant');
      final s = r.nearestSize!;
      expect(c.check(width: s[0], height: s[1], frameCount: 1, byteLength: 1000, format: 'png').ok, isTrue,
          reason: '$dims -> suggested $s is not conformant');
    }
  });

  test('file too large rejected', () => expect(chk(128, 128, bytes: 6 * 1024 * 1024).ok, isFalse));
  test('unsupported format rejected', () => expect(chk(128, 128, fmt: 'jpg').ok, isFalse));
}
