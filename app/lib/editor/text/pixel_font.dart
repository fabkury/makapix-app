// The Text tool's bitmap fonts (ADR 0039; CONTEXT.md "Font", "Native size").
//
// A Font is 1-bit glyph data at one native pixel size, read from the `.mkf` assets that
// tools/fonts/build_fonts.py writes (the format is documented there). Fonts are shell data: the
// engine never sees one, only the mask a laid-out text becomes (text_layout.dart).
//
// Pure Dart, no Flutter widgets: [PixelFontLayer.parse] takes bytes, so the tests read the real
// assets from disk and need neither the engine nor an asset bundle.
// l10n-ignore-file: asset paths, manifest keys and format tags; nothing here is shown.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

/// One glyph, resolved: its metrics and where its bits live.
class PixelGlyph {
  const PixelGlyph(this._layer, this._i);
  final PixelFontLayer _layer;
  final int _i;

  /// Pen advance in pixels.
  int get advance => _layer._advance[_i];

  /// Left edge of the bitmap, relative to the pen.
  int get xOffset => _layer._xoff[_i];

  /// Rows the bitmap's top edge sits above the baseline.
  int get top => _layer._top[_i];
  int get width => _layer._w[_i];
  int get height => _layer._h[_i];

  /// Whether pixel (x, y) of the bitmap is set (row-major, y down).
  bool bit(int x, int y) {
    final i = y * width + x;
    return (_layer._bytes[_layer._offset[_i] + (i >> 3)] >> (i & 7)) & 1 == 1;
  }
}

/// One `.mkf` file: a complete font, or a delta layer that overrides some glyphs of a base.
class PixelFontLayer {
  PixelFontLayer._(this.nativePx, this.ascent, this.descent, this.lineGap, this._cps, this._advance, this._xoff,
      this._top, this._w, this._h, this._offset, this._kernKeys, this._kernAdj, this._bytes);

  final int nativePx, ascent, descent, lineGap;
  final Uint32List _cps;
  final Uint8List _advance, _w, _h;
  final Int8List _xoff, _top;
  final Uint32List _offset;
  final Float64List _kernKeys; // left * 2^21 + right, ascending (exact in a double)
  final Int8List _kernAdj;
  final Uint8List _bytes;

  int get glyphCount => _cps.length;
  int get kernPairCount => _kernKeys.length;

  /// Every code point this layer draws, ascending.
  Uint32List get codePoints => _cps;

  static const _magic = [0x4D, 0x4B, 0x50, 0x46]; // "MKPF"

  /// Parse one `.mkf` file. Throws [FormatException] on anything that is not a well-formed
  /// version-1 file, so a damaged asset fails loudly instead of drawing garbage.
  static PixelFontLayer parse(Uint8List bytes) {
    if (bytes.length < 28) throw const FormatException('font: too short');
    for (var i = 0; i < 4; i++) {
      if (bytes[i] != _magic[i]) throw const FormatException('font: bad magic');
    }
    final d = ByteData.sublistView(bytes);
    if (bytes[4] != 1) throw FormatException('font: unknown version ${bytes[4]}');
    final px = d.getUint16(6, Endian.little);
    final ascent = d.getInt16(8, Endian.little);
    final descent = d.getInt16(10, Endian.little);
    final gap = d.getInt16(12, Endian.little);
    final n = d.getUint32(16, Endian.little);
    final k = d.getUint32(20, Endian.little);
    final bitmapLen = d.getUint32(24, Endian.little);
    final tables = 28 + n * 9 + k * 9;
    if (tables + bitmapLen != bytes.length) throw const FormatException('font: size mismatch');
    var o = 28;
    final cps = Uint32List(n);
    for (var i = 0; i < n; i++) {
      cps[i] = d.getUint32(o + i * 4, Endian.little);
      if (i > 0 && cps[i] <= cps[i - 1]) throw const FormatException('font: code points not ascending');
    }
    o += n * 4;
    final advance = Uint8List.sublistView(bytes, o, o + n);
    o += n;
    final xoff = Int8List.sublistView(bytes, o, o + n);
    o += n;
    final top = Int8List.sublistView(bytes, o, o + n);
    o += n;
    final w = Uint8List.sublistView(bytes, o, o + n);
    o += n;
    final h = Uint8List.sublistView(bytes, o, o + n);
    o += n;
    final kernKeys = Float64List(k);
    for (var i = 0; i < k; i++) {
      final left = d.getUint32(o + i * 4, Endian.little);
      final right = d.getUint32(o + k * 4 + i * 4, Endian.little);
      kernKeys[i] = left * 2097152.0 + right;
      if (i > 0 && kernKeys[i] <= kernKeys[i - 1]) throw const FormatException('font: kerning not ascending');
    }
    o += k * 8;
    final kernAdj = Int8List.sublistView(bytes, o, o + k);
    o += k;
    final offset = Uint32List(n);
    var at = o;
    for (var i = 0; i < n; i++) {
      offset[i] = at;
      at += (w[i] * h[i] + 7) >> 3;
    }
    if (at != bytes.length) throw const FormatException('font: bitmap size mismatch');
    return PixelFontLayer._(px, ascent, descent, gap, cps, advance, xoff, top, w, h, offset, kernKeys, kernAdj, bytes);
  }

  int _indexOf(int cp) {
    var lo = 0, hi = _cps.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final v = _cps[mid];
      if (v == cp) return mid;
      if (v < cp) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return -1;
  }

  PixelGlyph? glyph(int cp) {
    final i = _indexOf(cp);
    return i < 0 ? null : PixelGlyph(this, i);
  }

  int kerning(int left, int right) {
    if (_kernKeys.isEmpty) return 0;
    final key = left * 2097152.0 + right;
    var lo = 0, hi = _kernKeys.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final v = _kernKeys[mid];
      if (v == key) return _kernAdj[mid];
      if (v < key) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return 0;
  }
}

/// A Font: its layers in lookup order (a delta layer first, then the base it overrides). The
/// metrics and the kerning are the first layer's.
class PixelFont {
  PixelFont(this.layers) : assert(layers.isNotEmpty);
  final List<PixelFontLayer> layers;

  int get nativePx => layers.first.nativePx;

  /// Pixels a line reserves above / below its baseline.
  int get ascent => layers.first.ascent;
  int get descent => layers.first.descent;

  /// The distance from one baseline to the next before any line-spacing adjustment.
  int get lineHeight => ascent + descent + layers.first.lineGap;

  PixelGlyph? glyph(int cp) {
    for (final l in layers) {
      final g = l.glyph(cp);
      if (g != null) return g;
    }
    return null;
  }

  int kerning(int left, int right) {
    for (final l in layers) {
      final k = l.kerning(left, right);
      if (k != 0) return k;
    }
    return 0;
  }

  /// How many characters of [text] this Font cannot draw (what would show a Missing-glyph
  /// marker). Line breaks and the invisible joiners are never counted.
  int missingIn(String text) {
    var n = 0;
    for (final cp in text.runes) {
      if (isLayoutControl(cp)) continue;
      if (glyph(cp) == null) n++;
    }
    return n;
  }
}

/// Code points the layout consumes itself or draws as nothing: line breaks, tabs (a space),
/// and the zero-width joiners and variation selectors keyboards attach to other characters.
bool isLayoutControl(int cp) =>
    cp == 0x0A ||
    cp == 0x0D ||
    cp == 0x09 ||
    cp == 0x200B ||
    cp == 0x200C ||
    cp == 0x200D ||
    cp == 0x2060 ||
    cp == 0xFEFF ||
    (cp >= 0xFE00 && cp <= 0xFE0F);

/// One Font as the manifest lists it: one row of the font picker.
class PixelFontEntry {
  const PixelFontEntry({
    required this.id,
    required this.name,
    required this.px,
    required this.scripts,
    required this.files,
    required this.source,
    this.lang,
  });

  final String id;

  /// The Font's own name. A proper noun: never translated.
  final String name;

  /// Native size: the one pixel height this Font is drawn at.
  final int px;

  /// 'latin', 'cyrillic', 'cjk' — what the picker's filter chips read.
  final Set<String> scripts;

  /// The `.mkf` layers in lookup order.
  final List<String> files;

  /// 'vexed' or 'fusion' (which credit and license apply).
  final String source;

  /// The language form of a CJK face ('ja', 'zh-Hans', 'zh-Hant', 'ko'); null otherwise.
  final String? lang;

  bool get isCjk => scripts.contains('cjk');

  static PixelFontEntry fromJson(Map<String, dynamic> j) => PixelFontEntry(
        id: j['id'] as String,
        name: j['name'] as String,
        px: (j['px'] as num).toInt(),
        scripts: {...(j['scripts'] as List).cast<String>()},
        files: [...(j['files'] as List).cast<String>()],
        source: j['source'] as String,
        lang: j['lang'] as String?,
      );
}

/// The bundled Fonts: the manifest, plus lazily loaded and cached glyph data.
class PixelFontLibrary {
  PixelFontLibrary._(this.entries, this.credits, this._read);

  static const assetDir = 'assets/pixel_fonts';

  /// Every Font, in manifest order (smallest native size first).
  final List<PixelFontEntry> entries;

  /// Credit line per source ('vexed', 'fusion').
  final Map<String, String> credits;
  final Future<Uint8List> Function(String file) _read;
  final Map<String, Future<PixelFontLayer>> _layers = {};
  final Map<String, PixelFont> _fonts = {};

  /// Build a library from a manifest and a byte reader (the tests read from disk).
  static PixelFontLibrary fromManifest(String manifestJson, Future<Uint8List> Function(String file) read) {
    final j = json.decode(manifestJson) as Map<String, dynamic>;
    final entries = [for (final e in (j['fonts'] as List).cast<Map<String, dynamic>>()) PixelFontEntry.fromJson(e)];
    final credits = {
      for (final e in ((j['credits'] as Map?) ?? const {}).entries) e.key as String: e.value as String,
    };
    return PixelFontLibrary._(entries, credits, read);
  }

  static Future<PixelFontLibrary>? _shared;

  /// The app's library, loaded once from the asset bundle.
  static Future<PixelFontLibrary> shared({AssetBundle? bundle}) {
    return _shared ??= () async {
      final b = bundle ?? rootBundle;
      // `load`, not `loadString`: the bundle caches loadString's FUTURE, and a cached future is
      // one more thing that could outlive the zone it completed in (widget tests).
      final raw = await b.load('$assetDir/fonts.json');
      final manifest = utf8.decode(raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes));
      return fromManifest(manifest, (file) async {
        final data = await b.load('$assetDir/$file');
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      });
    }();
  }

  /// Forget the shared library. Widget tests only: each test runs in its own fake-async zone,
  /// and a future completed in a finished test's zone never delivers to the next one.
  @visibleForTesting
  static void debugResetShared() => _shared = null;

  PixelFontEntry? entry(String id) {
    for (final e in entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// A Font already loaded by [load], or null.
  PixelFont? peek(String id) => _fonts[id];

  /// Load (once) and return the Font [id]; null for an id the manifest does not list.
  Future<PixelFont?> load(String id) async {
    final hit = _fonts[id];
    if (hit != null) return hit;
    final e = entry(id);
    if (e == null) return null;
    final layers = await Future.wait([
      for (final f in e.files) _layers[f] ??= _read(f).then(PixelFontLayer.parse),
    ]);
    return _fonts[id] = PixelFont(layers);
  }

  /// Load every Font (the picker draws each row in its own glyphs and sorts by coverage).
  Future<void> loadAll() => Future.wait([for (final e in entries) load(e.id)]);

  /// The Font a first-time user starts with: one that can write their language (user decision
  /// 2026-11-19). [languageCode] is the app's language.
  String defaultFontId(String languageCode) {
    final want = switch (languageCode) {
      'ja' => 'fusion.12.ja',
      'zh' => 'fusion.12.zh-Hans',
      'ko' => 'fusion.12.ko',
      _ => 'vexed.everyday_standard',
    };
    return entry(want) != null ? want : entries.first.id;
  }
}
