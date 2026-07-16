import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/palette_io.dart';

void main() {
  group('parsePaletteFile', () {
    test('classic GIMP .gpl with Name: header (tabs and spaces)', () {
      const gpl = 'GIMP Palette\n'
          'Name: Warm Trio\n'
          'Columns: 0\n'
          '#\n'
          '255\t0\t0\tred\n'
          '0 255 0  green\n'
          '  0   0 255\n';
      final p = parsePaletteFile(gpl, fallbackName: 'file-stem');
      expect(p.name, 'Warm Trio');
      expect(p.colors, [
        const Color(0xFFFF0000),
        const Color(0xFF00FF00),
        const Color(0xFF0000FF),
      ]);
    });

    test('Lospec export with #Palette Name: comment header (PICO-8 snippet)', () {
      const gpl = 'GIMP Palette\n'
          '#Palette Name: PICO-8\n'
          '#Description: The PICO-8 is a virtual video game console.\n'
          '#Colors: 3\n'
          '0\t0\t0\t000000\n'
          '29\t43\t83\t1D2B53\n'
          '126\t37\t83\t7E2553\n';
      final p = parsePaletteFile(gpl, fallbackName: 'pico-8');
      expect(p.name, 'PICO-8');
      expect(p.colors, [
        const Color(0xFF000000),
        const Color(0xFF1D2B53),
        const Color(0xFF7E2553),
      ]);
    });

    test('JSON array of hex strings, 6- and 8-digit forms', () {
      final p = parsePaletteFile('["#FF0000", "#00FF0080"]', fallbackName: 'mine');
      expect(p.name, 'mine');
      expect(p.colors, [const Color(0xFFFF0000), const Color(0x8000FF00)]);
    });

    test('malformed rows and comments are skipped, out-of-range channels clamp', () {
      const gpl = 'GIMP Palette\n'
          '# just a comment\n'
          'not a row\n'
          '12 34\n'
          '999 -1 128\n';
      final p = parsePaletteFile(gpl, fallbackName: 'f');
      expect(p.colors, [const Color(0xFFFF0080)]);
    });

    test('encodeGpl roundtrips through parsePaletteFile (name + RGB)', () {
      final colors = [const Color(0xFF102030), const Color(0xFFFFEE00)];
      final p = parsePaletteFile(encodeGpl('Round Trip', colors), fallbackName: 'x');
      expect(p.name, 'Round Trip');
      expect(p.colors, colors);
    });
  });

  group('sanitizePaletteName', () {
    test('strips DSL statement separators and JSON hazards', () {
      expect(sanitizePaletteName('a;b\nc\rd'), 'a b c d');
      expect(sanitizePaletteName('say "hi"'), "say 'hi'");
      expect(sanitizePaletteName(r'back\slash'), 'backslash');
    });
    test('collapses whitespace, trims, clamps, falls back when empty', () {
      expect(sanitizePaletteName('  a   b  '), 'a b');
      expect(sanitizePaletteName(';;;'), 'Palette');
      expect(sanitizePaletteName('', fallback: 'F'), 'F');
      expect(sanitizePaletteName('x' * 100).length, 64);
    });
    test('keeps commas and parens (safe in the DSL)', () {
      expect(sanitizePaletteName('Warm, cosy (tones)'), 'Warm, cosy (tones)');
    });
  });

  group('swatch grid math', () {
    test('swatchColumns floors to fitting count and never drops below 1', () {
      // 5 swatches of 24 + 4 gaps of 4 = 136.
      expect(swatchColumns(136), 5);
      expect(swatchColumns(135), 4);
      expect(swatchColumns(0), 1);
    });
    test('swatchLayout: fits exactly → untrimmed; one over → trades a cell for …', () {
      expect(swatchLayout(15, 5), (shown: 15, trimmed: false));
      expect(swatchLayout(16, 5), (shown: 14, trimmed: true));
      expect(swatchLayout(0, 5), (shown: 0, trimmed: false));
    });
  });

  group('state and DSL helpers', () {
    test('palettesFromState reads the palettes key, tolerates absence', () {
      final state = {
        'palettes': [
          {
            'name': 'Default',
            'colors': ['#FF0000FF', '#00FF00FF'],
          },
          {'name': 'Empty', 'colors': []},
        ],
      };
      final ps = palettesFromState(state);
      expect(ps.length, 2);
      expect(ps[0].name, 'Default');
      expect(ps[0].colors, [const Color(0xFFFF0000), const Color(0xFF00FF00)]);
      expect(ps[1].colors, isEmpty);
      expect(palettesFromState({}), isEmpty);
    });

    test('buildImportScript batches NewPalette + AddPaletteColor with sanitised name', () {
      final script = buildImportScript('bad;name', [const Color(0xFFFF0000)]);
      expect(script, 'NewPalette(bad name)\nAddPaletteColor(#FF0000FF)');
    });

    test('hexRgba/parseHexColor roundtrip including alpha', () {
      const c = Color(0x80102030);
      expect(hexRgba(c), '#10203080');
      expect(parseHexColor(hexRgba(c)), c);
    });
  });
}
