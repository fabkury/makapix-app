// The built-in pattern catalog (ADR 0025): its invariants — no duplicate tiles, no all-ON or
// all-OFF tile, every non-Bayer tile listed with its inverse, sizes within 8×8 for v1, the
// Bayer tables canonical, and the catalog-name lookup. Pure Dart, no engine.
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

  test('the catalog has no duplicates, no all-on/off tiles, and stays within 8×8 for v1', () {
    final entries = patternCatalogEntries.toList();
    expect(entries.length, greaterThan(80));
    final tiles = entries.map((e) => e.tile).toList();
    expect(tiles.toSet().length, tiles.length, reason: 'duplicate tiles');
    expect(entries.map((e) => e.id).toSet().length, entries.length, reason: 'duplicate ids');
    for (final e in entries) {
      expect(e.tile.isAllOn, isFalse, reason: e.id);
      expect(e.tile.isAllOff, isFalse, reason: e.id);
      expect(e.tile.w, lessThanOrEqualTo(8), reason: e.id);
      expect(e.tile.h, lessThanOrEqualTo(8), reason: e.id);
      expect(e.name, isNotEmpty);
    }
  });

  test('every non-Bayer tile has its inverse somewhere in the catalog; the ladders contain theirs', () {
    final all = patternCatalogEntries.map((e) => e.tile).toSet();
    for (final f in patternCatalog) {
      for (final e in f.entries) {
        expect(all.contains(e.tile.inverse), isTrue, reason: '${f.name}: ${e.name} lacks its inverse');
      }
    }
  });

  test('families come in the designed order with the Bayer ladders first', () {
    final names = patternCatalog.map((f) => f.name).toList();
    expect(names.take(3), ['Bayer 2×2', 'Bayer 4×4', 'Bayer 8×8']);
    expect(names, contains('Lines'));
    expect(names, contains('Diagonals & crosshatch'));
    expect(names, contains('Dots, grids, bricks & checkers'));
    expect(patternCatalog[0].entries.length, 6, reason: '2×2: levels 1..3 and their inverses');
    expect(patternCatalog[1].entries.length, 30, reason: '4×4: levels 1..15 and their inverses');
    expect(patternCatalog[2].entries.length, 30, reason: '8×8: every 4th level, 4..60, and their inverses');
    // Ladders run by density, the level ahead of its inverse at equal density.
    final counts = [for (final e in patternCatalog[1].entries) e.tile.onCount];
    expect(counts, List.of(counts)..sort());
    expect(patternCatalog[0].entries.map((e) => e.name).toList(),
        ['2×2 · 1/4', '2×2 · 3/4 (inverse)', '2×2 · 2/4', '2×2 · 2/4 (inverse)', '2×2 · 1/4 (inverse)', '2×2 · 3/4']);
  });

  test('patternName finds a catalog tile by value and returns null for a custom one', () {
    expect(patternName(PatternTile.rows(['#.', '.#'])!), '2×2 · 2/4');
    expect(patternName(PatternTile.parse('4,4,5a5a')!), '4×4 · 8/16 (inverse)');
    expect(patternName(PatternTile.parse('7,3,1')!), isNull);
  });
}
