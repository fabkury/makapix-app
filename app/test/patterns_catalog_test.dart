// The built-in pattern catalog (ADR 0025): its invariants — every pattern listed once (no two
// tiles paint the same pixels, none is another's inverse), no all-ON or all-OFF tile, tiles at
// their smallest repeating size and within 8×8, the Bayer tables canonical, the single Bayer
// ramp, and the catalog lookup by pixels. Pure Dart, no engine.
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/patterns/pattern_tile.dart';
import 'package:makapix_club/editor/patterns/patterns_catalog.dart';

void main() {
  test('Bayer matrices are the canonical recursive expansions', () {
    expect(bayerMatrix(2), [
      [0, 2],
      [3, 1],
    ]);
    expect(bayerMatrix(4), [
      [0, 8, 2, 10],
      [12, 4, 14, 6],
      [3, 11, 1, 9],
      [15, 7, 13, 5],
    ]);
    final b8 = bayerMatrix(8);
    expect(b8[0], [0, 32, 8, 40, 2, 34, 10, 42]);
    expect(b8[7], [63, 31, 55, 23, 61, 29, 53, 21]);
    final all = [for (final r in b8) ...r]..sort();
    expect(all, List.generate(64, (i) => i));
  });

  test('bayerTile turns on the k lowest thresholds; level 8 of 4×4 is the 2×2 checker expanded', () {
    expect(bayerTile(2, 1).hex, '1'); // only (0,0)
    expect(bayerTile(2, 2), PatternTile.rows(['#.', '.#']));
    final b4half = bayerTile(4, 8);
    final checker = PatternTile.rows(['#.', '.#'])!;
    for (var y = 0; y < 4; y++) {
      for (var x = 0; x < 4; x++) {
        expect(b4half.on(x, y), checker.on(x, y), reason: '($x,$y)');
      }
    }
    expect(bayerTile(8, 32).onCount, 32);
  });

  test('a coarse level of a Bayer matrix is the matching level of the next smaller one', () {
    // Why the catalog has ONE Bayer ramp: 8×8 at every 4th level is the 4×4 ladder, and 4×4 at
    // every 4th level is the 2×2 one.
    for (var k = 1; k < 16; k++) {
      expect(bayerTile(8, 4 * k).samePixels(bayerTile(4, k)), isTrue, reason: '8×8 level ${4 * k}');
    }
    for (var k = 1; k < 4; k++) {
      expect(bayerTile(4, 4 * k).samePixels(bayerTile(2, k)), isTrue, reason: '4×4 level ${4 * k}');
    }
    expect(bayerTile(8, 3).samePixels(bayerTile(4, 1)), isFalse, reason: 'the in-between levels are new');
  });

  test('every pattern is listed once: no two tiles paint the same pixels, none is another inverse', () {
    final entries = patternCatalogEntries.toList();
    expect(entries.length, 45);
    expect(entries.map((e) => e.id).toSet().length, entries.length, reason: 'duplicate ids');
    final seen = <PatternTile, String>{};
    for (final e in entries) {
      expect(e.tile.isAllOn, isFalse, reason: e.id);
      expect(e.tile.isAllOff, isFalse, reason: e.id);
      expect(e.tile.w, lessThanOrEqualTo(8), reason: e.id);
      expect(e.tile.h, lessThanOrEqualTo(8), reason: e.id);
      expect(e.tile.canonical, e.tile, reason: '${e.id} is not at its smallest repeating size');
      expect(e.name, isNotEmpty);
      expect(seen[e.tile], isNull, reason: '${e.id} paints the same pixels as ${seen[e.tile]}');
      seen[e.tile] = e.id;
    }
    // The Invert switch reaches every inverse, so an inverse must not also be an entry.
    for (final e in entries) {
      expect(seen[e.tile.inverse], isNull, reason: '${e.id} is the inverse of ${seen[e.tile.inverse]}');
    }
  });

  test('families come in the designed order; Bayer is one ramp, light to dark', () {
    final names = patternCatalog.map((f) => f.name).toList();
    expect(names, ['Bayer', 'Lines', 'Diagonals & crosshatch', 'Dots, grids, bricks & checkers']);
    expect([for (final f in patternCatalog) f.entries.length], [21, 6, 9, 9]);
    final bayer = patternCatalog[0].entries;
    expect(bayer.map((e) => e.name).toList(), [
      'Bayer · 1/64', 'Bayer · 2/64', 'Bayer · 3/64', //
      for (var k = 1; k < 16; k++) 'Bayer · $k/16',
      'Bayer · 61/64', 'Bayer · 62/64', 'Bayer · 63/64',
    ]);
    // Strictly denser tile by tile (density = ON cells over all cells, compared over 64).
    final density = [for (final e in bayer) e.tile.onCount * 64 ~/ e.tile.cellCount];
    expect(density, [1, 2, 3, for (var k = 1; k < 16; k++) 4 * k, 61, 62, 63]);
    // The levels that are a smaller matrix's are stored at that size.
    expect(bayer[3 + 7].tile, PatternTile.rows(['#.', '.#']), reason: '8/16 is the 1-px checker');
    expect(bayer[3 + 3].tile.w, 2, reason: '4/16 is a 2×2 tile');
    expect(bayer[0].tile.w, 8);
    // A lone dot every 4 px or every 8 px IS Bayer 1/16 and Bayer 1/64: the Dots family keeps
    // only the pitch the ramp doesn't have.
    final dots = [for (final e in patternCatalogEntries) if (e.shape == PatternShape.dots) e.a];
    expect(dots, [3]);
    expect(patternName(PatternTile.generate(4, 4, (x, y) => x == 0 && y == 0)!), 'Bayer · 1/16');
    expect(patternName(PatternTile.generate(8, 8, (x, y) => x == 0 && y == 0)!), 'Bayer · 1/64');
  });

  test('patternLookup finds a tile by its pixels at any stored size, and its inverse', () {
    final checker = PatternTile.rows(['#.', '.#'])!;
    expect(patternName(checker), 'Bayer · 8/16');
    expect(patternName(bayerTile(4, 8)), 'Bayer · 8/16', reason: 'stored 4×4');
    expect(patternName(bayerTile(8, 32)), 'Bayer · 8/16', reason: 'stored 8×8 by an older build');
    expect(patternLookup(bayerTile(8, 32))!.inverted, isFalse);
    expect(patternName(PatternTile.parse('4,4,5a5a')!), 'Bayer · 8/16 (inverse)');
    expect(patternLookup(checker.inverse)!.inverted, isTrue);
    expect(patternName(bayerTile(8, 16).inverse), 'Bayer · 4/16 (inverse)');
    expect(patternName(PatternTile.rows(['.', '#'])!), 'Horizontal · 2 px (inverse)');
    expect(patternName(PatternTile.parse('7,3,1')!), isNull);
    expect(patternLookup(PatternTile.parse('7,3,1')!), isNull);
    // Every tile an older build's catalog could have stored still has a name.
    for (final (n, step) in [(2, 1), (4, 1), (8, 4)]) {
      for (var level = step; level < n * n; level += step) {
        expect(patternName(bayerTile(n, level)), isNotNull, reason: '$n×$n level $level');
        expect(patternName(bayerTile(n, level).inverse), isNotNull, reason: '$n×$n level $level inverse');
      }
    }
  });
}
