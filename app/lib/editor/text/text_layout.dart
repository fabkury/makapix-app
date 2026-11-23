// Text layout for the Text tool (ADR 0039): words in one Font → a 1-bit mask.
//
// Everything is whole pixels: glyphs sit at integer positions, kerning and spacing are integer
// adjustments, and nothing is ever scaled or anti-aliased. The result is the mask the engine
// stamps (`MaskStamp`), tight around the ink, plus where the Missing-glyph markers go.
//
// Pure Dart: no Flutter, no engine. Covered by test/editor/text_layout_test.dart.
// l10n-ignore-file: no display text.
import 'dart:typed_data';

import 'pixel_font.dart';

enum TextAlignX { left, center, right }

/// Limits (docs/text-tool/DESIGN.md): the words a Text Draft may hold, and the largest side of
/// a mask — the engine's storage side at the canvas cap (`MASK_MAX_SIDE`, 3 × 512).
const int kTextMaxChars = 2000;
const int kMaskMaxSide = 1536;

/// A rectangular 1-bit mask in the engine's wire convention: bit `i = y*w + x` at
/// `bytes[i ~/ 8] >> (i % 8)`; hex is the bytes in order, two digits each.
class BitMask {
  BitMask(this.width, this.height) : bytes = Uint8List((width * height + 7) >> 3);
  final int width, height;
  final Uint8List bytes;

  bool get(int x, int y) {
    final i = y * width + x;
    return (bytes[i >> 3] >> (i & 7)) & 1 == 1;
  }

  void set(int x, int y) {
    final i = y * width + x;
    bytes[i >> 3] |= 1 << (i & 7);
  }

  static const _digits = '0123456789abcdef';

  String toHex() {
    final out = Uint8List(bytes.length * 2);
    for (var i = 0; i < bytes.length; i++) {
      out[i * 2] = _digits.codeUnitAt(bytes[i] >> 4);
      out[i * 2 + 1] = _digits.codeUnitAt(bytes[i] & 15);
    }
    return String.fromCharCodes(out);
  }

  /// `w,h,hex` — the three arguments `MaskDraft` / `MaskStamp` take after the position.
  String get dslArgs => '$width,$height,${toHex()}';
}

/// A rectangle in whole pixels, relative to the layout box's top-left.
class PxRect {
  const PxRect(this.x, this.y, this.w, this.h);
  final int x, y, w, h;
  @override
  bool operator ==(Object other) => other is PxRect && other.x == x && other.y == y && other.w == w && other.h == h;
  @override
  int get hashCode => Object.hash(x, y, w, h);
  @override
  String toString() => 'PxRect($x,$y,$w,$h)';
}

class TextLayoutOptions {
  const TextLayoutOptions({
    this.align = TextAlignX.left,
    this.letterSpacing = 0,
    this.lineSpacing = 0,
    this.wrapWidth,
  });

  final TextAlignX align;

  /// Whole pixels added after every glyph (may be negative).
  final int letterSpacing;

  /// Whole pixels added to the Font's line height (may be negative; a line never advances less
  /// than one pixel).
  final int lineSpacing;

  /// The Wrap width, or null to break only where the artist typed a line break.
  final int? wrapWidth;
}

/// The laid-out text. The layout BOX starts at (0, 0): its width is the Wrap width (or the
/// widest line), its height the lines' extent. The mask is the ink's tight bounding box, placed
/// at ([maskX], [maskY]) within the box — ink may reach slightly outside it.
class TextLayout {
  TextLayout({
    required this.boxWidth,
    required this.boxHeight,
    required this.lineCount,
    required this.mask,
    required this.maskX,
    required this.maskY,
    required this.missing,
    required this.clipped,
  });

  final int boxWidth, boxHeight, lineCount;

  /// Null when the text has no ink (empty, only spaces, or only characters the Font lacks).
  final BitMask? mask;
  final int maskX, maskY;

  /// One box per character the Font cannot draw: the Missing-glyph markers. Draft-only — the
  /// mask never contains them.
  final List<PxRect> missing;

  /// True when the ink was larger than [kMaskMaxSide] and had to be cut.
  final bool clipped;
}

class _Item {
  _Item(this.cp, this.glyph, this.advance);
  final int cp;
  final PixelGlyph? glyph; // null = a Missing-glyph marker (or a space the Font lacks)
  final int advance;
  int x = 0; // pen position within its line, set by the line breaker
  bool get isSpace => cp == 0x20 || cp == 0x3000 || cp == 0x09;
}

class _Line {
  _Line(this.items, this.width);
  final List<_Item> items;
  final int width; // where the line's ink ends (trailing spaces and side bearing excluded)
}

/// Whether a line may break between two adjacent characters without a space: East Asian text
/// has no spaces between words, so any boundary next to an ideograph, kana, or Hangul syllable
/// is a break opportunity.
bool _isCjkBreakable(int cp) =>
    (cp >= 0x2E80 && cp <= 0x9FFF) || // radicals, kana, CJK symbols, unified ideographs
    (cp >= 0xAC00 && cp <= 0xD7AF) || // Hangul syllables
    (cp >= 0xF900 && cp <= 0xFAFF) || // compatibility ideographs
    (cp >= 0xFF00 && cp <= 0xFFEF) || // full-width forms
    (cp >= 0x20000 && cp <= 0x3FFFF); // extension planes

/// The size of a Missing-glyph marker for [font]: about one capital letter.
(int w, int h) missingMarkerSize(PixelFont font) {
  final h = font.nativePx.clamp(3, 1 << 20);
  final w = ((font.nativePx * 3) ~/ 5).clamp(3, 1 << 20);
  return (w, h);
}

TextLayout layoutText(String text, PixelFont font, [TextLayoutOptions options = const TextLayoutOptions()]) {
  final (markW, markH) = missingMarkerSize(font);
  final sp = options.letterSpacing;
  final wrap = options.wrapWidth == null ? null : (options.wrapWidth! < 1 ? 1 : options.wrapWidth!);

  // 1. Split into paragraphs at the typed line breaks, and resolve every character.
  final paragraphs = <List<_Item>>[[]];
  var count = 0;
  for (final cp in text.runes) {
    if (cp == 0x0A) {
      paragraphs.add([]);
      continue;
    }
    if (cp != 0x09 && isLayoutControl(cp)) continue;
    if (++count > kTextMaxChars) break;
    final c = cp == 0x09 ? 0x20 : cp;
    final g = font.glyph(c);
    final advance = g != null ? g.advance : (c == 0x20 ? (font.nativePx / 2).ceil() : markW + 1);
    paragraphs.last.add(_Item(c, g, advance));
  }

  // 2. Break each paragraph into lines.
  final lines = <_Line>[];
  for (final para in paragraphs) {
    if (para.isEmpty) {
      lines.add(_Line(const [], 0));
      continue;
    }
    var start = 0;
    while (start < para.length) {
      var pen = 0;
      var end = start; // exclusive end of the line being built
      var breakAt = -1; // a break opportunity: the line may end before item [breakAt]
      var widthAtBreak = 0; // the line's width if it ends there (trailing spaces excluded)
      var inkEnd = 0; // right edge of the ink placed so far
      _Item? prev;
      while (end < para.length) {
        final it = para[end];
        var x = pen;
        if (prev != null && prev.glyph != null && it.glyph != null) x += font.kerning(prev.cp, it.cp);
        final after = x + it.advance;
        // Where this item's ink ends: what the Wrap width and the alignment measure, so a
        // right-aligned line is flush with the edge instead of one side bearing short of it.
        final g = it.glyph;
        final inkRight = g == null ? x + (it.isSpace ? 0 : markW) : (g.width == 0 ? x : x + g.xOffset + g.width);
        // A break may fall before this item when it follows a space, or at a CJK boundary.
        if (end > start && !it.isSpace && (prev!.isSpace || _isCjkBreakable(it.cp) || _isCjkBreakable(prev.cp))) {
          breakAt = end;
          widthAtBreak = inkEnd;
        }
        if (wrap != null && !it.isSpace && inkRight > wrap && end > start) {
          break; // this item does not fit: end the line before it
        }
        it.x = x;
        pen = after + sp;
        if (!it.isSpace && inkRight > inkEnd) inkEnd = inkRight;
        prev = it;
        end++;
      }
      if (end == para.length) {
        lines.add(_Line(para.sublist(start, end), inkEnd));
        break;
      }
      // Overflow. Prefer the last break opportunity; with none, the word itself is wider than
      // the Wrap width and breaks where it stops fitting.
      if (breakAt > start) {
        lines.add(_Line(para.sublist(start, breakAt), widthAtBreak));
        start = breakAt;
      } else {
        lines.add(_Line(para.sublist(start, end), inkEnd));
        start = end;
      }
      // Spaces at a wrapped line's start belong to the break: swallow them.
      while (start < para.length && para[start].isSpace) {
        start++;
      }
      if (start == para.length) break;
    }
  }

  // 3. Place the lines.
  final step = (font.lineHeight + options.lineSpacing) < 1 ? 1 : font.lineHeight + options.lineSpacing;
  var widest = 0;
  for (final l in lines) {
    if (l.width > widest) widest = l.width;
  }
  final boxW = wrap ?? widest;
  final boxH = (lines.length - 1) * step + font.ascent + font.descent;

  // 4. Measure the ink, then draw it.
  final placed = <(PixelGlyph, int, int)>[]; // glyph, left, top (box coordinates)
  final missing = <PxRect>[];
  var x0 = 1 << 30, y0 = 1 << 30, x1 = -(1 << 30), y1 = -(1 << 30);
  for (var li = 0; li < lines.length; li++) {
    final line = lines[li];
    final lineX = switch (options.align) {
      TextAlignX.left => 0,
      TextAlignX.center => (boxW - line.width) ~/ 2,
      TextAlignX.right => boxW - line.width,
    };
    final baseline = li * step + font.ascent;
    for (final it in line.items) {
      final g = it.glyph;
      if (g == null) {
        if (!it.isSpace) missing.add(PxRect(lineX + it.x, baseline - markH, markW, markH));
        continue;
      }
      if (g.width == 0 || g.height == 0) continue;
      final gx = lineX + it.x + g.xOffset, gy = baseline - g.top;
      placed.add((g, gx, gy));
      if (gx < x0) x0 = gx;
      if (gy < y0) y0 = gy;
      if (gx + g.width > x1) x1 = gx + g.width;
      if (gy + g.height > y1) y1 = gy + g.height;
    }
  }
  if (placed.isEmpty) {
    return TextLayout(
        boxWidth: boxW,
        boxHeight: boxH,
        lineCount: lines.length,
        mask: null,
        maskX: 0,
        maskY: 0,
        missing: missing,
        clipped: false);
  }
  var w = x1 - x0, h = y1 - y0;
  final clipped = w > kMaskMaxSide || h > kMaskMaxSide;
  if (w > kMaskMaxSide) w = kMaskMaxSide;
  if (h > kMaskMaxSide) h = kMaskMaxSide;
  final mask = BitMask(w, h);
  for (final (g, gx, gy) in placed) {
    for (var y = 0; y < g.height; y++) {
      final my = gy - y0 + y;
      if (my < 0 || my >= h) continue;
      for (var x = 0; x < g.width; x++) {
        if (!g.bit(x, y)) continue;
        final mx = gx - x0 + x;
        if (mx < 0 || mx >= w) continue;
        mask.set(mx, my);
      }
    }
  }
  return TextLayout(
      boxWidth: boxW,
      boxHeight: boxH,
      lineCount: lines.length,
      mask: mask,
      maskX: x0,
      maskY: y0,
      missing: missing,
      clipped: clipped);
}
