// File → Open rules (open_file.dart): signature sniffing, title/format from the file name, and
// the oversize refusal. Pure Dart — no engine, no network.
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/editor/open_file.dart';

void main() {
  group('isMkpxBytes', () {
    const plain = [0x89, 0x4D, 0x4B, 0x50, 0x58, 0x0D, 0x0A, 0x1A];
    const compact = [0x89, 0x4D, 0x4B, 0x50, 0x5A, 0x0D, 0x0A, 0x1A];
    const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

    test('accepts the plain and compact signatures, with or without a body', () {
      expect(isMkpxBytes(plain), isTrue);
      expect(isMkpxBytes([...compact, 1, 2, 3]), isTrue);
    });

    test('rejects PNG, legacy MKPX text, short, and empty input', () {
      expect(isMkpxBytes(png), isFalse);
      expect(isMkpxBytes('MKPX....'.codeUnits), isFalse, reason: 'legacy magic lacks the 0x89 guard');
      expect(isMkpxBytes(plain.sublist(0, 7)), isFalse);
      expect(isMkpxBytes(const []), isFalse);
    });
  });

  group('titleFromFileName', () {
    test('strips an accepted extension, case-insensitively', () {
      expect(titleFromFileName('Sunset run.mkpx'), 'Sunset run');
      expect(titleFromFileName('walk.GIF'), 'walk');
      expect(titleFromFileName('archive.v2.png'), 'archive.v2');
    });

    test('leaves unknown or missing extensions alone', () {
      expect(titleFromFileName('notes.txt'), 'notes.txt');
      expect(titleFromFileName('README'), 'README');
      expect(titleFromFileName('.hidden'), '.hidden');
    });
  });

  group('importedFormatFromFileName', () {
    test('lowercases the extension and falls back to image', () {
      expect(importedFormatFromFileName('a.PNG'), 'png');
      expect(importedFormatFromFileName('a.jpeg'), 'jpeg');
      expect(importedFormatFromFileName('noext'), 'image');
      expect(importedFormatFromFileName('trailing.'), 'image');
    });
  });

  group('openRasterRefusal', () {
    test('accepts anything within the cap, including the cap itself', () {
      expect(openRasterRefusal(1, 1, maxDim: 512), isNull);
      expect(openRasterRefusal(512, 512, maxDim: 512), isNull);
      expect(openRasterRefusal(64, 512, maxDim: 512), isNull);
    });

    test('refuses a side over the cap and points to Import', () {
      final m = openRasterRefusal(1920, 1080, maxDim: 512)!;
      expect(m, contains('1920×1080'));
      expect(m, contains('512×512'));
      expect(m, contains('Import image'));
      expect(openRasterRefusal(513, 8, maxDim: 512), isNotNull);
    });

    test('refuses an empty image', () {
      expect(openRasterRefusal(0, 10, maxDim: 512), contains('empty'));
    });
  });

  test('the Open picker lists .mkpx first, then the raster formats', () {
    expect(kOpenExtensions.first, 'mkpx');
    expect(kOpenExtensions.sublist(1), kOpenImageExtensions);
    expect(kOpenImageExtensions, containsAll(['png', 'gif', 'apng', 'webp', 'jpg', 'jpeg', 'bmp']));
  });
}
