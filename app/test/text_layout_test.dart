// The Text tool's fonts and layout (ADR 0039; editor/text/pixel_font.dart, text_layout.dart):
// the real bundled assets read from disk, laid out into the mask the engine stamps. No engine
// binary, no widget pumping.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/editor/text/pixel_font.dart';
import 'package:makapix_club/editor/text/text_layout.dart';

const _dir = 'assets/pixel_fonts';

PixelFontLibrary _library() => PixelFontLibrary.fromManifest(
    File('$_dir/fonts.json').readAsStringSync(), (f) async => File('$_dir/$f').readAsBytesSync());

/// The mask as rows of '#' and '.', for readable expectations.
List<String> _rows(TextLayout l) {
  final m = l.mask!;
  return [
    for (var y = 0; y < m.height; y++) [for (var x = 0; x < m.width; x++) m.get(x, y) ? '#' : '.'].join(),
  ];
}

void main() {
  late PixelFontLibrary lib;
  late PixelFont standard, fantasy, ja, hans;

  setUpAll(() async {
    lib = _library();
    standard = (await lib.load('vexed.everyday_standard'))!;
    fantasy = (await lib.load('vexed.font_fantasy'))!;
    ja = (await lib.load('fusion.12.ja'))!;
    hans = (await lib.load('fusion.12.zh-Hans'))!;
  });

  group('the font library', () {
    test('lists 59 VEXED fonts and 38 CJK entries, smallest first', () {
      expect(lib.entries.where((e) => e.source == 'vexed'), hasLength(59));
      expect(lib.entries.where((e) => e.source == 'fusion'), hasLength(12));
      expect(lib.entries.where((e) => e.id.startsWith('cjk.')), hasLength(26));
      expect(lib.entries.where((e) => e.isCjk), hasLength(38));
      for (final e in lib.entries) {
        expect(lib.credits, contains(e.source), reason: '${e.id} has no credit line');
      }
      final sizes = [for (final e in lib.entries) e.px];
      expect(sizes, [...sizes]..sort());
      expect(lib.entries.map((e) => e.id).toSet(), hasLength(lib.entries.length));
      expect(lib.entry('fusion.12.ja')!.name, 'Fusion Pixel 12 · 日本語');
    });

    test('every font parses and can write its own name', () async {
      await lib.loadAll();
      for (final e in lib.entries) {
        final f = lib.peek(e.id)!;
        expect(f.nativePx, e.px, reason: e.id);
        expect(f.ascent + f.descent, greaterThan(0), reason: e.id);
        expect(f.missingIn(e.name), 0, reason: '${e.id} cannot draw "${e.name}"');
        expect(f.glyph(0x41), isNotNull, reason: e.id);
      }
    });

    test('the CJK library fonts write their languages', () async {
      Future<PixelFont> font(String id) async => (await lib.load(id))!;
      // Read from embedded bitmaps, a BDF, and outlines on the pixel grid.
      expect((await font('cjk.shinonome.gothic16')).missingIn('永遠の夢を描くドット絵'), 0);
      expect((await font('cjk.k8x12')).missingIn('永遠の夢を描くドット絵'), 0);
      expect((await font('cjk.roundpix.12')).missingIn('永远的梦想，像素画编辑器'), 0);
      expect((await font('cjk.fashion.16')).missingIn('永遠的夢想，像素畫編輯器'), 0);
      expect((await font('cjk.dunggeun.16')).missingIn('영원한 꿈을 그리는 픽셀 아트'), 0);
      // A glyph with ink: the strike reader once produced blank pictures for a whole font.
      for (final id in ['cjk.khdot.hibiya24', 'cjk.fashion.16', 'cjk.boutique.9x9bold', 'cjk.galmuri.14']) {
        final g = (await font(id)).glyph(0x41)!;
        expect(g.width * g.height, greaterThan(0), reason: id);
      }
      // One file backs the Japanese and the Korean entry of MaruMinya.
      expect(lib.entry('cjk.maruminya.12.ja')!.files, lib.entry('cjk.maruminya.12.ko')!.files);
      expect((await font('cjk.maruminya.12.ko')).missingIn('한글 日本語 かな'), 0);
      // The two forms of one size share a base layer and differ where the scripts do.
      final hansSong = await font('cjk.changban.16.zh-Hans');
      final hantSong = await font('cjk.changban.16.zh-Hant');
      expect(lib.entry('cjk.changban.16.zh-Hans')!.files.last, lib.entry('cjk.changban.16.zh-Hant')!.files.last);
      final differing = [
        for (var cp = 0x4E00; cp < 0xA000; cp++)
          if (!identical(hansSong.glyph(cp), hantSong.glyph(cp))) cp,
      ];
      expect(differing, isNotEmpty);
    });

    test('the first font follows the app language', () {
      expect(lib.defaultFontId('en'), 'vexed.everyday_standard');
      expect(lib.defaultFontId('ru'), 'vexed.everyday_standard');
      expect(lib.defaultFontId('ja'), 'fusion.12.ja');
      expect(lib.defaultFontId('zh'), 'fusion.12.zh-Hans');
      expect(standard.missingIn('Привет, мир'), 0, reason: 'the Latin default must write Russian');
    });

    test('a damaged file is refused, not drawn', () {
      final good = File('$_dir/vexed_everyday_tiny.mkf').readAsBytesSync();
      expect(() => PixelFontLayer.parse(good.sublist(0, good.length - 1)), throwsFormatException);
      expect(() => PixelFontLayer.parse(good.sublist(0, 10)), throwsFormatException);
      final bad = [...good]..[0] = 0x58;
      expect(() => PixelFontLayer.parse(Uint8List.fromList(bad)), throwsFormatException);
    });

    test('a language form overrides its base glyph by glyph', () {
      // U+76F4 is drawn differently in Japanese and in Simplified Chinese.
      expect(_rows(layoutText('直', ja)), isNot(_rows(layoutText('直', hans))));
      expect(_rows(layoutText('A', ja)), _rows(layoutText('A', hans)));
    });
  });

  group('layout', () {
    test('one line is drawn glyph for glyph at whole pixels', () {
      final l = layoutText('Hi', standard);
      expect(_rows(l), [
        '#..#.#',
        '#..#..',
        '#..#.#',
        '####.#',
        '#..#.#',
        '#..#.#',
      ]);
      expect(l.lineCount, 1);
      expect(l.boxHeight, standard.ascent + standard.descent);
      expect(l.missing, isEmpty);
    });

    test('empty text is a one-line box with no mask', () {
      final l = layoutText('', standard);
      expect(l.mask, isNull);
      expect(l.lineCount, 1);
      expect(l.boxWidth, 0);
      expect(l.boxHeight, standard.ascent + standard.descent);
      expect(layoutText('   ', standard).mask, isNull);
    });

    test('kerning pairs tighten the advance', () {
      final av = layoutText('AV', fantasy);
      final a = layoutText('A', fantasy), v = layoutText('V', fantasy);
      expect(fantasy.kerning(0x41, 0x56), lessThan(0));
      expect(a.boxWidth, greaterThan(0));
      expect(av.boxWidth, fantasy.glyph(0x41)!.advance + fantasy.kerning(0x41, 0x56) + v.boxWidth);
    });

    test('letter spacing is added between glyphs, never after the last', () {
      final tight = layoutText('HH', standard);
      final loose = layoutText('HH', standard, const TextLayoutOptions(letterSpacing: 3));
      expect(loose.boxWidth, tight.boxWidth + 3);
      expect(loose.mask!.width, tight.mask!.width + 3);
    });

    test('typed line breaks and line spacing', () {
      final two = layoutText('A\nB', standard);
      expect(two.lineCount, 2);
      expect(two.boxHeight, standard.lineHeight + standard.ascent + standard.descent);
      final tight = layoutText('A\nB', standard, const TextLayoutOptions(lineSpacing: -4));
      expect(tight.boxHeight, two.boxHeight - 4);
      expect(layoutText('A\n\nB', standard).lineCount, 3, reason: 'an empty line keeps its height');
      expect(layoutText('A\r\nB', standard).lineCount, 2, reason: 'CR is ignored');
    });

    test('the Wrap width breaks at spaces and never hides text', () {
      final one = layoutText('AAAA BBBB', standard);
      final wrapped = layoutText('AAAA BBBB', standard, TextLayoutOptions(wrapWidth: one.boxWidth - 1));
      expect(wrapped.lineCount, 2);
      expect(wrapped.boxWidth, one.boxWidth - 1);
      final a = layoutText('AAAA', standard), b = layoutText('BBBB', standard);
      // The two lines are exactly the two words: the space at the break draws nothing.
      expect(_rows(wrapped).take(a.mask!.height).map((r) => r.substring(0, a.mask!.width)), _rows(a));
      expect(wrapped.mask!.width, a.mask!.width > b.mask!.width ? a.mask!.width : b.mask!.width);
    });

    test('a word wider than the Wrap width breaks where it stops fitting', () {
      final l = layoutText('AAAAAAAA', standard, const TextLayoutOptions(wrapWidth: 12));
      expect(l.lineCount, greaterThan(1));
      expect(l.mask!.width, lessThanOrEqualTo(12));
      // Even a Wrap width narrower than one glyph makes progress: one glyph per line.
      expect(layoutText('AAA', standard, const TextLayoutOptions(wrapWidth: 1)).lineCount, 3);
    });

    test('CJK text breaks between any two characters', () {
      final l = layoutText('日本語日本語', ja, const TextLayoutOptions(wrapWidth: 36));
      expect(l.lineCount, 2);
      expect(l.mask!.width, lessThanOrEqualTo(36));
    });

    test('alignment places each line within the box', () {
      const text = 'AAAA\nA';
      final left = layoutText(text, standard);
      final right = layoutText(text, standard, const TextLayoutOptions(align: TextAlignX.right));
      final center = layoutText(text, standard, const TextLayoutOptions(align: TextAlignX.center));
      expect(right.boxWidth, left.boxWidth);
      final lastRow = left.mask!.height - 1;
      int firstInk(TextLayout l) => _rows(l)[lastRow].indexOf('#');
      expect(firstInk(left), 0);
      expect(firstInk(right), greaterThan(firstInk(center)));
      expect(firstInk(center), greaterThan(0));
      // In a Wrap width wider than the text, right alignment moves the whole mask.
      final wide = layoutText('A', standard, const TextLayoutOptions(align: TextAlignX.right, wrapWidth: 40));
      expect(wide.maskX + wide.mask!.width, 40);
    });

    test('a character the font lacks becomes a marker and leaves a blank advance', () {
      final l = layoutText('A日B', standard);
      expect(l.missing, hasLength(1));
      final (w, h) = missingMarkerSize(standard);
      expect(l.missing.single.w, w);
      expect(l.missing.single.h, h);
      final ab = layoutText('AB', standard);
      expect(l.mask!.width, ab.mask!.width + w + 1, reason: 'the gap is the marker advance');
      // The marker itself is never in the mask: the columns under it are empty.
      final m = l.missing.single;
      for (var y = 0; y < l.mask!.height; y++) {
        for (var x = m.x - l.maskX; x < m.x - l.maskX + m.w; x++) {
          expect(l.mask!.get(x, y), isFalse);
        }
      }
      expect(layoutText('日', standard).mask, isNull, reason: 'only markers: nothing to stamp');
    });

    test('joiners and variation selectors draw nothing and are not missing', () {
      final plain = layoutText('AB', standard);
      final joined = layoutText('A‍️B', standard);
      expect(_rows(joined), _rows(plain));
      expect(joined.missing, isEmpty);
      expect(standard.missingIn('A‍\nB'), 0);
    });

    test('text past the character limit is cut, and a huge mask is clipped to the engine cap', () async {
      final megabit = (await lib.load('vexed.megabit_monolith'))!;
      final l = layoutText('W' * 5000, megabit);
      expect(l.clipped, isTrue);
      expect(l.mask!.width, kMaskMaxSide);
      final cut = layoutText('A' * (kTextMaxChars + 50), standard, const TextLayoutOptions(wrapWidth: 60));
      final exact = layoutText('A' * kTextMaxChars, standard, const TextLayoutOptions(wrapWidth: 60));
      expect(cut.lineCount, exact.lineCount);
    });
  });

  group('the mask on the wire', () {
    test('hex is the bytes in order, low bit first within a byte', () {
      final m = BitMask(3, 3)
        ..set(0, 0)
        ..set(2, 0)
        ..set(1, 1)
        ..set(0, 2)
        ..set(2, 2);
      // bits 0,2,4,6,8 → byte0 = 0b01010101, byte1 = 0b00000001
      expect(m.toHex(), '5501');
      expect(m.dslArgs, '3,3,5501');
    });

    test('a laid-out mask is canonical: no bit beyond w*h', () {
      final m = layoutText('Hi', standard).mask!;
      final tail = (m.width * m.height) % 8;
      if (tail != 0) expect(m.bytes.last >> tail, 0);
      expect(m.toHex().length, m.bytes.length * 2);
    });
  });
}
