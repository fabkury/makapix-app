// The built-in pattern catalog (ADR 0025): ~100 tiles up to 8×8, generated once from small
// generator functions and grouped by family for the Patterns page. Ids and names are UI-only —
// prefs and the journal store the TILE (`PatternTile.pref` / `.dsl`), so renaming, reordering,
// or extending this catalog never breaks a stored recent or a recorded session.
//
// Families (design decision 2026-09-03): the three Bayer ladders at coarse steps, lines,
// diagonals and crosshatch, then dots / grids / bricks / checkers. EVERY tile is listed with its
// exact inverse, so a two-color dither is two strokes with complementary tiles: the non-Bayer
// families pair each tile with its inverse, and the Bayer ladders run by density with both
// phases at each step (a Bayer level's inverse is NOT another level of the ladder — the
// thresholds are not symmetric — so the inverses are explicit entries). Tiles the ladders already
// contain (the 2×2 checker, the single-dot 2×2, the 2-px grid) are not repeated under a second
// name: the catalog has no duplicate tiles, no all-ON tile (that is Off), and no all-OFF tile (it
// would paint nothing).
import 'pattern_tile.dart';

class PatternEntry {
  const PatternEntry({required this.id, required this.name, required this.tile});

  /// Stable within a build of the app, UI-only.
  final String id;
  final String name;
  final PatternTile tile;
}

class PatternFamily {
  const PatternFamily(this.name, this.entries);
  final String name;
  final List<PatternEntry> entries;
}

/// The canonical Bayer thresholds `0..n²` for n ∈ {2, 4, 8} (the recursive expansion
/// `M(2n) = [[4M, 4M+2], [4M+3, 4M+1]]` of `[[0, 2], [3, 1]]`) — the same tables the engine
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

/// The Bayer n×n tile at density `level` (the `level` lowest thresholds ON), 1 ≤ level < n².
PatternTile bayerTile(int n, int level) {
  final m = bayerMatrix(n);
  return PatternTile.generate(n, n, (x, y) => m[y][x] < level)!;
}

/// The three Bayer families the Gradient's dither picks from, previewed at their 50 % level.
const List<int> kGradientDitherSizes = [2, 4, 8];

List<PatternFamily>? _catalog;

/// The catalog, built on first use.
List<PatternFamily> get patternCatalog => _catalog ??= _build();

/// Every tile in the catalog, in page order.
Iterable<PatternEntry> get patternCatalogEntries sync* {
  for (final f in patternCatalog) {
    yield* f.entries;
  }
}

/// The catalog name of [tile], or `null` for a tile the catalog doesn't carry (a journal can
/// carry any bits; the page shows such a tile as "Custom").
String? patternName(PatternTile tile) {
  for (final e in patternCatalogEntries) {
    if (e.tile == tile) return e.name;
  }
  return null;
}

List<PatternFamily> _build() {
  final seen = <PatternTile>{};
  final families = <PatternFamily>[];

  // Adds the family, dropping any tile already listed (by value) and any all-ON / all-OFF tile.
  void family(String name, List<PatternEntry> entries) {
    final kept = <PatternEntry>[];
    for (final e in entries) {
      if (e.tile.isAllOn || e.tile.isAllOff) continue;
      if (!seen.add(e.tile)) continue;
      kept.add(e);
    }
    if (kept.isNotEmpty) families.add(PatternFamily(name, kept));
  }

  // A tile followed by its inverse, both named.
  List<PatternEntry> pair(String id, String name, PatternTile t) => [
        PatternEntry(id: id, name: name, tile: t),
        PatternEntry(id: '$id.inv', name: '$name (inverse)', tile: t.inverse),
      ];

  // Bayer ladders at coarse steps: 2×2 every level, 4×4 every level, 8×8 every 4th level —
  // each level followed by its inverse, the whole ladder ordered by density (ON count).
  for (final (n, step) in [(2, 1), (4, 1), (8, 4)]) {
    final entries = <PatternEntry>[];
    for (var level = step; level < n * n; level += step) {
      final t = bayerTile(n, level);
      entries.add(PatternEntry(id: 'bayer$n.$level', name: '$n×$n · $level/${n * n}', tile: t));
      entries.add(PatternEntry(id: 'bayer$n.$level.inv', name: '$n×$n · $level/${n * n} (inverse)', tile: t.inverse));
    }
    // Stable sort by density; at equal density the level precedes its inverse.
    final indexed = entries.asMap().entries.toList()
      ..sort((a, b) {
        final d = a.value.tile.onCount.compareTo(b.value.tile.onCount);
        return d != 0 ? d : a.key.compareTo(b.key);
      });
    family('Bayer $n×$n', [for (final e in indexed) e.value]);
  }

  // Lines: one horizontal (or vertical) 1-px line per pitch.
  family('Lines', [
    for (final p in [2, 3, 4]) ...[
      ...pair('lines.h$p', 'Horizontal · $p px', PatternTile.generate(1, p, (x, y) => y == 0)!),
      ...pair('lines.v$p', 'Vertical · $p px', PatternTile.generate(p, 1, (x, y) => x == 0)!),
    ],
  ]);

  // Diagonals and crosshatch. Pitch 2 is the 2×2 checker (a Bayer tile) for both directions and
  // all-ON for the crosshatch, so the family starts at 3.
  family('Diagonals & crosshatch', [
    for (final p in [3, 4, 8]) ...[
      ...pair('diag.up$p', 'Diagonal ／ · $p px', PatternTile.generate(p, p, (x, y) => (x + y) % p == 0)!),
      ...pair('diag.down$p', 'Diagonal ＼ · $p px', PatternTile.generate(p, p, (x, y) => (x - y) % p == 0)!),
      ...pair('cross$p', 'Crosshatch · $p px', PatternTile.generate(p, p, (x, y) => (x + y) % p == 0 || (x - y) % p == 0)!),
    ],
  ]);

  // Dots, grids, bricks, and checkers.
  bool mortar(int x, int y, int bw, int bh) {
    final course = y ~/ bh;
    final shift = course.isOdd ? bw ~/ 2 : 0;
    return y % bh == 0 || (x + shift) % bw == 0;
  }

  family('Dots, grids, bricks & checkers', [
    for (final p in [3, 4, 8]) ...pair('dots$p', 'Dots · $p px', PatternTile.generate(p, p, (x, y) => x == 0 && y == 0)!),
    for (final p in [3, 4, 8]) ...pair('grid$p', 'Grid · $p px', PatternTile.generate(p, p, (x, y) => x == 0 || y == 0)!),
    ...pair('bricks4x2', 'Bricks · 4×2', PatternTile.generate(4, 4, (x, y) => mortar(x, y, 4, 2))!),
    ...pair('bricks8x4', 'Bricks · 8×4', PatternTile.generate(8, 8, (x, y) => mortar(x, y, 8, 4))!),
    for (final c in [2, 3, 4])
      ...pair('checker$c', 'Checker · $c×$c cells', PatternTile.generate(2 * c, 2 * c, (x, y) => (x ~/ c + y ~/ c).isEven)!),
  ]);

  return families;
}
