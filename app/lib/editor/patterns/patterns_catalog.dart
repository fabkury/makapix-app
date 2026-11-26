// The built-in pattern catalog (ADR 0025): 45 tiles up to 8×8, generated once from small
// generator functions and grouped by family for the Patterns page. Ids and names are UI-only -
// prefs and the journal store the TILE (`PatternTile.pref` / `.dsl`), so renaming, reordering,
// or extending this catalog never breaks a stored recent or a recorded session.
//
// Every pattern is listed ONCE (user decision 2026-11-26). "The same pattern" means the same
// painted pixels, so tiles are compared at their smallest repeating size
// (`PatternTile.canonical`): the Bayer 8×8 matrix at every 4th level IS the 4×4 ladder, and the
// 4×4 ladder at every 4th level IS the 2×2 one, so the three ladders the catalog used to carry
// (116 tiles, 36 of them repeats) are one "Bayer" ramp, light to dark: 1/64 · 2/64 · 3/64, then
// 1/16 to 15/16, then 61/64 · 62/64 · 63/64 - the 4×4 steps plus the sparse and dense ends only
// the 8×8 matrix reaches. Inverses are not entries either: the page's Invert switch swaps ON
// and OFF for every tile, so a two-color dither is still two strokes with complementary tiles.
// No tile is all-ON (that is Off) or all-OFF (it would paint nothing), and no tile is the
// inverse of another (the switch already reaches it).
import 'package:makapix_club/l10n/l10n.dart';

import 'pattern_tile.dart';

/// What a catalog tile depicts: with [PatternEntry.a] and [PatternEntry.b] it is everything
/// the tile's name is made of, so the name can be said in the current language.
enum PatternShape { bayer, horizontal, vertical, diagUp, diagDown, crosshatch, dots, grid, bricks, checker }

class PatternEntry {
  const PatternEntry({
    required this.id,
    required this.shape,
    required this.a,
    this.b = 0,
    required this.tile,
  });

  /// Stable within a build of the app, UI-only.
  final String id;
  final PatternShape shape;

  /// The first number of the name: the Bayer density's numerator, the line pitch, the brick
  /// width, the checker cell.
  final int a;

  /// The second number of the name: the Bayer density's denominator (16 or 64), the brick
  /// height.
  final int b;

  /// At its canonical (smallest repeating) size.
  final PatternTile tile;

  /// The display name, in the current language.
  String get name {
    final l = appL10n;
    return switch (shape) {
      PatternShape.bayer => l.patBayer('$a/$b'),
      PatternShape.horizontal => l.patHorizontal(a),
      PatternShape.vertical => l.patVertical(a),
      PatternShape.diagUp => l.patDiagUp(a),
      PatternShape.diagDown => l.patDiagDown(a),
      PatternShape.crosshatch => l.patCrosshatch(a),
      PatternShape.dots => l.patDots(a),
      PatternShape.grid => l.patGrid(a),
      PatternShape.bricks => l.patBricks('$a×$b'),
      PatternShape.checker => l.patChecker(a),
    };
  }

  /// The name of this tile with ON and OFF swapped (what the page's Invert switch picks).
  String get inverseName => appL10n.patInverse(name);
}

enum PatternGroup { bayer, lines, diagonals, dots }

class PatternFamily {
  const PatternFamily(this.group, this.entries);
  final PatternGroup group;
  final List<PatternEntry> entries;

  /// The section heading, in the current language.
  String get name => switch (group) {
        PatternGroup.bayer => appL10n.patFamilyBayer,
        PatternGroup.lines => appL10n.patFamilyLines,
        PatternGroup.diagonals => appL10n.patFamilyDiagonals,
        PatternGroup.dots => appL10n.patFamilyDots,
      };
}

/// The canonical Bayer thresholds `0..n²` for n ∈ {2, 4, 8} (the recursive expansion
/// `M(2n) = [[4M, 4M+2], [4M+3, 4M+1]]` of `[[0, 2], [3, 1]]`): the same tables the engine
/// dithers gradients with.
List<List<int>> bayerMatrix(int n) {
  var m = [
    [0, 2],
    [3, 1],
  ];
  while (m.length < n) {
    final k = m.length;
    final out = List.generate(2 * k, (_) => List.filled(2 * k, 0));
    for (var y = 0; y < k; y++) {
      for (var x = 0; x < k; x++) {
        final v = 4 * m[y][x];
        out[y][x] = v;
        out[y][x + k] = v + 2;
        out[y + k][x] = v + 3;
        out[y + k][x + k] = v + 1;
      }
    }
    m = out;
  }
  return m;
}

/// The Bayer n×n tile at density `level` (the `level` lowest thresholds ON), 1 ≤ level < n²,
/// stored n×n. Level 4k of the 2n×2n matrix paints the same pixels as level k of the n×n one.
PatternTile bayerTile(int n, int level) {
  final m = bayerMatrix(n);
  return PatternTile.generate(n, n, (x, y) => m[y][x] < level)!;
}

List<PatternFamily>? _catalog;

/// The catalog, built on first use.
List<PatternFamily> get patternCatalog => _catalog ??= _build();

/// Every tile in the catalog, in page order.
Iterable<PatternEntry> get patternCatalogEntries sync* {
  for (final f in patternCatalog) {
    yield* f.entries;
  }
}

/// A catalog tile found by its pixels: the entry, and whether the tile is the entry's inverse.
typedef PatternMatch = ({PatternEntry entry, bool inverted});

/// The catalog entry that paints the same pixels as [tile] (whatever size it is stored at), or
/// whose inverse does; `null` for a tile the catalog doesn't carry.
PatternMatch? patternLookup(PatternTile tile) {
  final c = tile.canonical;
  for (final e in patternCatalogEntries) {
    if (e.tile == c) return (entry: e, inverted: false);
  }
  final ci = c.inverse;
  for (final e in patternCatalogEntries) {
    if (e.tile == ci) return (entry: e, inverted: true);
  }
  return null;
}

/// The catalog name of [tile], or `null` for a tile the catalog doesn't carry (a journal can
/// carry any bits; the page shows such a tile as "Custom").
String? patternName(PatternTile tile) {
  final m = patternLookup(tile);
  if (m == null) return null;
  return m.inverted ? m.entry.inverseName : m.entry.name;
}

List<PatternFamily> _build() {
  final seen = <PatternTile>{};
  final families = <PatternFamily>[];

  // Adds the family with every tile at its canonical size, dropping any all-ON / all-OFF tile
  // and any tile that paints the same pixels as one already listed, or as its inverse.
  void family(PatternGroup group, List<PatternEntry> entries) {
    final kept = <PatternEntry>[];
    for (final e in entries) {
      final t = e.tile.canonical;
      if (t.isAllOn || t.isAllOff) continue;
      if (seen.contains(t) || seen.contains(t.inverse)) continue;
      seen.add(t);
      kept.add(PatternEntry(id: e.id, shape: e.shape, a: e.a, b: e.b, tile: t));
    }
    if (kept.isNotEmpty) families.add(PatternFamily(group, kept));
  }

  PatternEntry one(String id, PatternShape shape, int a, PatternTile t, {int b = 0}) =>
      PatternEntry(id: id, shape: shape, a: a, b: b, tile: t);

  // l10n-ignore-start: catalog ids, never shown
  // The Bayer ramp, light to dark: the 4×4 ladder, with the three sparsest and the three densest
  // 8×8 levels at its ends. (Every 8×8 level that is a multiple of 4 is a 4×4 level; the other
  // 8×8 levels in between are left out: 42 near-identical tiles.)
  family(PatternGroup.bayer, [
    for (final level in [1, 2, 3]) one('bayer.$level/64', PatternShape.bayer, level, bayerTile(8, level), b: 64),
    for (var level = 1; level < 16; level++) one('bayer.$level/16', PatternShape.bayer, level, bayerTile(4, level), b: 16),
    for (final level in [61, 62, 63]) one('bayer.$level/64', PatternShape.bayer, level, bayerTile(8, level), b: 64),
  ]);

  // Lines: one horizontal (or vertical) 1-px line per pitch.
  family(PatternGroup.lines, [
    for (final p in [2, 3, 4]) ...[
      one('lines.h$p', PatternShape.horizontal, p, PatternTile.generate(1, p, (x, y) => y == 0)!),
      one('lines.v$p', PatternShape.vertical, p, PatternTile.generate(p, 1, (x, y) => x == 0)!),
    ],
  ]);

  // Diagonals and crosshatch. Pitch 2 is the 1-px checker (Bayer 8/16) for both directions and
  // all-ON for the crosshatch, so the family starts at 3.
  family(PatternGroup.diagonals, [
    for (final p in [3, 4, 8]) ...[
      one('diag.up$p', PatternShape.diagUp, p, PatternTile.generate(p, p, (x, y) => (x + y) % p == 0)!),
      one('diag.down$p', PatternShape.diagDown, p, PatternTile.generate(p, p, (x, y) => (x - y) % p == 0)!),
      one('cross$p', PatternShape.crosshatch, p, PatternTile.generate(p, p, (x, y) => (x + y) % p == 0 || (x - y) % p == 0)!),
    ],
  ]);

  // Dots, grids, bricks, and checkers. A lone dot at pitch 4 or 8 is Bayer 1/16 or 1/64, so the
  // dedupe keeps only the 3-px dots here.
  bool mortar(int x, int y, int bw, int bh) {
    final course = y ~/ bh;
    final shift = course.isOdd ? bw ~/ 2 : 0;
    return y % bh == 0 || (x + shift) % bw == 0;
  }

  family(PatternGroup.dots, [
    for (final p in [3, 4, 8]) one('dots$p', PatternShape.dots, p, PatternTile.generate(p, p, (x, y) => x == 0 && y == 0)!),
    for (final p in [3, 4, 8]) one('grid$p', PatternShape.grid, p, PatternTile.generate(p, p, (x, y) => x == 0 || y == 0)!),
    one('bricks4x2', PatternShape.bricks, 4, PatternTile.generate(4, 4, (x, y) => mortar(x, y, 4, 2))!, b: 2),
    one('bricks8x4', PatternShape.bricks, 8, PatternTile.generate(8, 8, (x, y) => mortar(x, y, 8, 4))!, b: 4),
    for (final c in [2, 3, 4])
      one('checker$c', PatternShape.checker, c, PatternTile.generate(2 * c, 2 * c, (x, y) => (x ~/ c + y ~/ c).isEven)!),
  ]);
  // l10n-ignore-end

  return families;
}
