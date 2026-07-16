// Pure palette I/O and layout logic for the palette page: .gpl/.json parsing, GPL export,
// DSL-safe name sanitising, state-JSON extraction, and swatch-grid math. No engine, no widgets —
// unit-testable without the native binary (the same split as tools.dart's restoreHiddenTool).

import 'dart:convert';
import 'dart:ui' show Color;

/// One palette as shown on the palette page: a name plus its swatch colors.
class PaletteInfo {
  const PaletteInfo(this.name, this.colors);
  final String name;
  final List<Color> colors;
}

/// '#RRGGBBAA' — the hex form the DSL and the engine state JSON use.
String hexRgba(Color c) {
  String two(int x) => x.toRadixString(16).padLeft(2, '0');
  final v = c.toARGB32(); // 8-bit ARGB, reordered to #RRGGBBAA
  return '#${two((v >> 16) & 0xFF)}${two((v >> 8) & 0xFF)}${two(v & 0xFF)}${two((v >> 24) & 0xFF)}'.toUpperCase();
}

/// Parses '#RRGGBB' or '#RRGGBBAA' (leading '#' optional).
Color parseHexColor(String h) {
  h = h.replaceAll('#', '');
  if (h.length == 6) h = '${h}FF';
  final v = int.parse(h, radix: 16);
  return Color.fromARGB(v & 0xFF, (v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF);
}

/// Makes a free-text palette name safe to embed in a DSL statement and in the engine's
/// hand-built state JSON: the engine splits scripts on newlines and ';', maps '"' to "'"
/// when emitting JSON, and does not escape backslashes at all.
String sanitizePaletteName(String raw, {String fallback = 'Palette'}) {
  var s = raw
      .replaceAll(RegExp(r'[;\r\n]'), ' ')
      .replaceAll('"', "'")
      .replaceAll(r'\', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (s.length > 64) s = s.substring(0, 64).trim();
  return s.isEmpty ? fallback : s;
}

/// Parses a palette file: a JSON array of hex strings, or a GIMP/Lospec .gpl. The name comes
/// from a 'Name:' or '#Palette Name:' header when present, else [fallbackName] (the caller
/// usually passes the filename stem). GPL rows are "R G B [hex [label]]"; alpha stays 255.
PaletteInfo parsePaletteFile(String text, {required String fallbackName}) {
  final t = text.trim();
  if (t.startsWith('[')) {
    try {
      final colors = [for (final h in json.decode(t) as List) parseHexColor(h.toString())];
      return PaletteInfo(fallbackName, colors);
    } catch (_) {} // not a usable JSON array — fall through to the line parser
  }
  var name = fallbackName;
  final lospecName = RegExp(r'^#\s*Palette\s+Name:\s*(.+)$', caseSensitive: false);
  final out = <Color>[];
  for (final line in text.split('\n')) {
    final l = line.trim();
    if (l.isEmpty) continue;
    if (l.startsWith('Name:')) {
      final n = l.substring('Name:'.length).trim();
      if (n.isNotEmpty) name = n;
      continue;
    }
    final m = lospecName.firstMatch(l);
    if (m != null) {
      final n = m.group(1)!.trim();
      if (n.isNotEmpty) name = n;
      continue;
    }
    if (l.startsWith('#') || l.startsWith('GIMP') || l.startsWith('Columns:')) continue;
    final parts = l.split(RegExp(r'\s+'));
    if (parts.length >= 3) {
      final r = int.tryParse(parts[0]), g = int.tryParse(parts[1]), b = int.tryParse(parts[2]);
      if (r != null && g != null && b != null) {
        out.add(Color.fromARGB(255, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255)));
      }
    }
  }
  return PaletteInfo(name, out);
}

/// GIMP .gpl text for [colors] (alpha is kept in a 4th hex column, ignored on re-import).
String encodeGpl(String name, List<Color> colors) {
  final sb = StringBuffer('GIMP Palette\nName: $name\nColumns: 0\n#\n');
  for (final c in colors) {
    sb.writeln('${(c.r * 255).round()}\t${(c.g * 255).round()}\t${(c.b * 255).round()}\t${hexRgba(c)}');
  }
  return sb.toString();
}

/// All palettes (name + colors) from the engine state JSON's 'palettes' key.
List<PaletteInfo> palettesFromState(Map<String, dynamic> state) {
  final raw = state['palettes'];
  if (raw is! List) return const [];
  return [
    for (final p in raw)
      if (p is Map)
        PaletteInfo(
          (p['name'] ?? 'Palette').toString(),
          [for (final h in (p['colors'] as List? ?? const [])) parseHexColor(h.toString())],
        ),
  ];
}

/// How many swatches fit in one row of [rowWidth] (never less than 1).
int swatchColumns(double rowWidth, {double swatch = 24, double spacing = 4}) {
  final n = ((rowWidth + spacing) / (swatch + spacing)).floor();
  return n < 1 ? 1 : n;
}

/// How many of [count] swatches a [columns] × [maxRows] preview shows; when it can't fit,
/// the last cell is given up for the '…' marker.
({int shown, bool trimmed}) swatchLayout(int count, int columns, {int maxRows = 3}) {
  final cap = columns * maxRows;
  if (count <= cap) return (shown: count, trimmed: false);
  return (shown: cap - 1, trimmed: true);
}

/// The batched DSL that creates a new palette and fills it — one engine.run call, so the
/// row-2 strip never observes a half-imported palette.
String buildImportScript(String name, List<Color> colors) {
  final sb = StringBuffer('NewPalette(${sanitizePaletteName(name)})');
  for (final c in colors) {
    sb.write('\nAddPaletteColor(${hexRgba(c)})');
  }
  return sb.toString();
}
