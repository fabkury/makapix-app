import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/share/image_share.dart';

void main() {
  group('shareCaption', () {
    test('title + url when both present', () {
      expect(shareCaption('My Art', 'https://makapix.club/p/abc'), '"My Art" — https://makapix.club/p/abc');
    });
    test('url only when title empty', () {
      expect(shareCaption('  ', 'https://makapix.club/p/abc'), 'https://makapix.club/p/abc');
    });
    test('title only when url missing', () {
      expect(shareCaption('My Art', null), 'My Art');
      expect(shareCaption('My Art', ''), 'My Art');
    });
    test('empty when neither present', () {
      expect(shareCaption('', null), '');
    });
  });

  group('sanitizeShareFilename', () {
    test('keeps safe chars, replaces the rest with underscores', () {
      expect(sanitizeShareFilename('Hello World!'), 'Hello_World');
      expect(sanitizeShareFilename('a/b:c*d'), 'a_b_c_d');
    });
    test('trims leading/trailing underscores', () {
      expect(sanitizeShareFilename('  spaced  '), 'spaced');
      expect(sanitizeShareFilename('***'), 'makapix');
    });
    test('falls back to makapix when empty', () {
      expect(sanitizeShareFilename(''), 'makapix');
      expect(sanitizeShareFilename('   '), 'makapix');
    });
    test('preserves unicode-free alnum with dashes/underscores', () {
      expect(sanitizeShareFilename('pixel-art_42'), 'pixel-art_42');
    });
  });

  group('smartDefaultExportScale', () {
    // Factor set is 1/2/4/8/16/32; target longest side is 1024 px.
    test('power-of-2 canvases land exactly on target', () {
      expect(smartDefaultExportScale(width: 256, height: 256, frames: 1), 4); // 1024
      expect(smartDefaultExportScale(width: 128, height: 128, frames: 1), 8); // 1024
      expect(smartDefaultExportScale(width: 64, height: 64, frames: 1), 16); // 1024
      expect(smartDefaultExportScale(width: 32, height: 32, frames: 1), 32); // 1024
    });

    test('matches the user example: quarter-size art picks 4x', () {
      // A 256 px target artwork at 64 px → 4× brings it back to ~256; but with a 1024 target the
      // same "quarter of target" relationship holds: 256 px art → 4× = 1024.
      expect(smartDefaultExportScale(width: 256, height: 256, frames: 1), 4);
    });

    test('uses the LONGEST side for non-square canvases', () {
      // 256 wide → 4× = 1024 on the long side (short side just follows).
      expect(smartDefaultExportScale(width: 256, height: 64, frames: 1), 4);
      expect(smartDefaultExportScale(width: 64, height: 256, frames: 1), 4);
    });

    test('picks the CLOSEST factor when the target is straddled', () {
      // 100 px canvas: candidates 100,200,400,800,1600,3200. Closest to 1024 is 800 (8×, dist 224)
      // vs 1600 (16×, dist 576) → 8×.
      expect(smartDefaultExportScale(width: 100, height: 100, frames: 1), 8);
      // 200 px canvas: 800 (4×, dist 224) vs 1600 (8×, dist 576) → 4×.
      expect(smartDefaultExportScale(width: 200, height: 200, frames: 1), 4);
    });

    test('tiny canvases pick the largest factor (still short of target)', () {
      // 16 px → max 32× = 512, still under 1024, so the biggest safe factor wins.
      expect(smartDefaultExportScale(width: 16, height: 16, frames: 1), 32);
    });

    test('never auto-picks a factor that trips the very-large-export warning', () {
      // 256×256 × 64 frames: the on-target 4× (1024²×64 ≈ 67M px) trips the 64M warn, so the smart
      // default steps down to the largest SAFE factor, 2× (512²×64 ≈ 16.8M, dist 512), rather than
      // silently defaulting to a size that immediately shows the red re-confirm.
      final s = smartDefaultExportScale(width: 256, height: 256, frames: 64);
      final safePx = 256 * s * 256 * s * 64;
      expect(safePx <= kExportWarnPixels, isTrue);
      expect(s, 2);
    });

    test('falls back to the smallest factor when even 1x is too large', () {
      // 256×256 × 1024 frames at 1× ≈ 68.7M px > 64M: nothing is safe, fall back to 1×.
      expect(smartDefaultExportScale(width: 256, height: 256, frames: 1024), 1);
    });
  });
}
