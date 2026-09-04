// PatternTile (ADR 0025): the shell twin of the engine's Pattern — bit layout, the `w,h,hex`
// prefs form, the `SetPattern(w,h,hex)` journal line, tiling with wraparound, the inverse, and
// value equality. Pure Dart, no engine.
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/patterns/pattern_tile.dart';

void main() {
  test('rows → bits follow the engine layout (bit y*w + x) and hex is fixed width', () {
    final checker = PatternTile.rows(['#.', '.#'])!;
    expect(checker.w, 2);
    expect(checker.h, 2);
    expect(checker.bits, BigInt.from(9)); // bits 0 and 3
    expect(checker.hex, '9');
    expect(checker.dsl, 'SetPattern(2,2,9)');
    expect(checker.pref, '2,2,9');
    final b4 = PatternTile.rows(['.#.#', '#.#.', '.#.#', '#.#.'])!;
    expect(b4.hex, '5a5a');
    expect(PatternTile.rows(['#..', '...', '...', '...', '...'])!.hex, '0001', reason: 'a 3×5 tile has 15 bits → 4 digits');
  });

  test('parse accepts the prefs form, optional leading zeros, and rejects junk', () {
    expect(PatternTile.parse('2,2,9'), PatternTile.rows(['#.', '.#']));
    expect(PatternTile.parse(' 4 , 4 , 00005A5A '), PatternTile.parse('4,4,5a5a'));
    expect(PatternTile.parse('2,2,10'), isNull, reason: 'bit 4 is beyond a 2×2 tile');
    expect(PatternTile.parse('0,2,1'), isNull);
    expect(PatternTile.parse('17,1,1'), isNull);
    expect(PatternTile.parse('2,2'), isNull);
    expect(PatternTile.parse('2,2,'), isNull);
    expect(PatternTile.parse('2,2,zz'), isNull);
    expect(PatternTile.parse('2,2,0x9'), isNull);
    expect(PatternTile.parse('16,16,${'f' * 64}')!.isAllOn, isTrue);
    expect(PatternTile.parse('16,16,${'f' * 65}'), isNull);
  });

  test('on() tiles over the canvas with wraparound for negative coordinates', () {
    final t = PatternTile.rows(['#..', '...'])!; // 3 wide, 2 tall
    expect(t.on(0, 0), isTrue);
    expect(t.on(1, 0), isFalse);
    expect(t.on(3, 2), isTrue);
    expect(t.on(-3, -2), isTrue);
    expect(t.on(-1, 0), isFalse);
    expect(t.on(300, 400), isTrue);
  });

  test('inverse flips every cell and round-trips; all-on / all-off are recognized', () {
    final t = PatternTile.rows(['##.', '.#.'])!;
    final inv = t.inverse;
    for (var y = 0; y < 2; y++) {
      for (var x = 0; x < 3; x++) {
        expect(inv.on(x, y), !t.on(x, y));
      }
    }
    expect(inv.inverse, t);
    expect(t.onCount, 3);
    expect(inv.onCount, 3);
    expect(PatternTile.rows(['##', '##'])!.isAllOn, isTrue);
    expect(PatternTile.rows(['..', '..'])!.isAllOff, isTrue);
    expect(t.isAllOn, isFalse);
    expect(t.isAllOff, isFalse);
  });

  test('equality is by value, whatever the tile is called', () {
    final a = PatternTile.parse('4,4,5a5a')!;
    final b = PatternTile.generate(4, 4, (x, y) => (x + y).isOdd)!;
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(PatternTile.parse('2,2,9')));
    expect({a, b}.length, 1);
  });

  test('the cap is 16×16 — 12×12 and 16×16 tiles are valid today', () {
    expect(kPatternMaxSide, 16);
    final twelve = PatternTile.generate(12, 12, (x, y) => x == y)!;
    expect(twelve.hex.length, 36);
    expect(PatternTile.parse(twelve.pref), twelve);
    expect(PatternTile.generate(17, 1, (x, y) => true), isNull);
  });

  test('pushRecentPattern keeps most-recent-first, dedupes, and caps at 10', () {
    final tiles = [for (var i = 1; i <= 12; i++) PatternTile.parse('4,1,${i.toRadixString(16)}')!];
    var recents = <PatternTile>[];
    for (final t in tiles) {
      recents = pushRecentPattern(recents, t);
    }
    expect(recents.length, 10);
    expect(recents.first, tiles[11]);
    expect(recents.last, tiles[2]);
    recents = pushRecentPattern(recents, tiles[5]);
    expect(recents.length, 10);
    expect(recents.first, tiles[5]);
    expect(recents.where((t) => t == tiles[5]).length, 1);
  });
}
