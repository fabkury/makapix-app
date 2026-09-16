// The Gradient's dither families (ADR 0028), shell side: the token round trip (numbers for Bayer,
// words for the rest, `off`/`bayerN` spellings), the generated tables (pinned by the same
// checksum the engine pins), the formula kinds pinned to the engine's values, every periodic
// family a permutation of its levels over one period, lines solid every other line at 50 %, the
// page grouping, and the preview painter's repaint rule. No engine.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/patterns/dither_tables.g.dart';
import 'package:makapix_club/editor/patterns/gradient_dither.dart';
import 'package:makapix_club/editor/patterns/patterns_catalog.dart';

void main() {
  test('every kind round-trips through its token; Bayer keeps the bare numbers of ADR 0025', () {
    expect(DitherKind.all.length, 17);
    expect(DitherKind.all.first, DitherKind.off);
    for (final k in DitherKind.all) {
      expect(DitherKind.parse(k.dsl), k);
      expect(DitherKind.parse(k.dsl.toUpperCase()), k, reason: 'case-insensitive like the engine');
    }
    expect(DitherKind.off.dsl, '0');
    expect(DitherKind.bayer2.dsl, '2');
    expect(DitherKind.bayer4.dsl, '4');
    expect(DitherKind.bayer8.dsl, '8');
    expect(DitherKind.parse('off'), DitherKind.off);
    expect(DitherKind.parse('bayer8'), DitherKind.bayer8);
    expect(DitherKind.parse(' Blue '), DitherKind.blueNoise);
    for (final bad in ['3', '16', 'bayer3', 'blue64', 'halftone2', 'hlines3', 'diag2', '', 'on']) {
      expect(DitherKind.parse(bad), isNull, reason: bad);
    }
    expect(DitherKind.all.map((k) => k.dsl).toSet().length, 17, reason: 'tokens are unique');
    expect(DitherKind.all.map((k) => k.name).toSet().length, 17, reason: 'names are unique');
    expect(DitherKind.off.isOff, isTrue);
    expect(DitherKind.all.where((k) => k.isOff).length, 1);
  });

  test('the tables are the generated ones the engine ships', () {
    // FNV-1a 32 over the little-endian u16 stream, as tools/dither/gen_tables.py prints it and
    // crates/engine/src/tool.rs pins it.
    var h = 0x811C9DC5;
    for (final v in kBlueNoise) {
      for (final b in [v & 0xFF, v >> 8]) {
        h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF;
      }
    }
    expect(h, kBlueNoiseChecksum);
    expect(h, 0xE2B26121);
    expect(kBlueNoise.length, 64 * 64);
    expect(kHalftone4, [
      [12, 5, 6, 13],
      [4, 0, 1, 7],
      [11, 3, 2, 8],
      [15, 10, 9, 14],
    ]);
    expect(kHalftone8[3][3], 0, reason: 'the 8×8 dot grows from the center');
    expect(kHalftone8[7][0], 63, reason: 'the corners come last');
  });

  test('the formula kinds compute the engine\'s thresholds', () {
    // Pinned in crates/engine/src/tool.rs (line_dithers_are_solid_alternate_lines_at_half_density).
    const at = [(0, 0), (1, 0), (0, 1), (7, 3)];
    expect([for (final (x, y) in at) DitherKind.ign.threshold(x, y)], [0, 142, 79, 209]);
    expect([for (final (x, y) in at) DitherKind.whiteNoise.threshold(x, y)], [114, 139, 224, 175]);
    // Bayer is the catalog's matrix (the engine's BAYER tables).
    for (final k in [DitherKind.bayer2, DitherKind.bayer4, DitherKind.bayer8]) {
      final m = bayerMatrix(k.n);
      for (var y = 0; y < k.n; y++) {
        for (var x = 0; x < k.n; x++) {
          expect(k.threshold(x, y), m[y][x]);
        }
      }
    }
    // The noises stay in range everywhere, negative coordinates included.
    for (final k in [DitherKind.whiteNoise, DitherKind.ign]) {
      for (final (x, y) in [(-1, -1), (511, 511), (-100000, 100000)]) {
        expect(k.threshold(x, y), inInclusiveRange(0, 255), reason: '$k ($x,$y)');
      }
    }
  });

  test('every periodic family is a permutation of its levels over one period and wraps', () {
    for (final k in DitherKind.all.where((k) => !k.isOff && k != DitherKind.whiteNoise && k != DitherKind.ign)) {
      final n = k.n;
      expect(k.levels, n * n, reason: '$k');
      final seen = List.filled(k.levels, false);
      for (var y = 0; y < n; y++) {
        for (var x = 0; x < n; x++) {
          final th = k.threshold(x, y);
          expect(th, inInclusiveRange(0, k.levels - 1), reason: '$k ($x,$y)');
          expect(seen[th], isFalse, reason: '$k threshold $th repeats');
          seen[th] = true;
          expect(k.threshold(x - n, y - n), th, reason: '$k wraps');
          expect(k.threshold(x + 3 * n, y + 5 * n), th, reason: '$k is periodic');
        }
      }
    }
  });

  test('line dithers are solid every-other lines at half density', () {
    for (final (h, v) in [
      (DitherKind.hlines2, DitherKind.vlines2),
      (DitherKind.hlines4, DitherKind.vlines4),
      (DitherKind.hlines8, DitherKind.vlines8),
    ]) {
      final n = h.n;
      final half = h.levels ~/ 2;
      for (var y = 0; y < n; y++) {
        final rowOn = h.threshold(0, y) < half;
        expect(rowOn, y.isEven, reason: '$h row $y');
        for (var x = 0; x < n; x++) {
          expect(h.threshold(x, y) < half, rowOn, reason: '$h ($x,$y) whole rows');
          expect(v.threshold(y, x) < half, rowOn, reason: '$v is $h transposed');
        }
      }
    }
    for (final d in [DitherKind.diag4, DitherKind.diag8]) {
      final half = d.levels ~/ 2;
      for (var y = 0; y < d.n; y++) {
        for (var x = 0; x < d.n; x++) {
          expect(d.threshold(x, y) < half, (x + y).isEven, reason: '$d ($x,$y)');
        }
      }
    }
  });

  test('the page grouping covers every kind but Off exactly once; blue noise lists under Noise', () {
    final listed = [for (final f in DitherKind.families) ...DitherKind.inFamily(f)];
    expect(listed.toSet(), DitherKind.all.where((k) => !k.isOff).toSet());
    expect(listed.length, 16);
    expect(DitherKind.families, [DitherKind.familyBayer, DitherKind.familyHalftone, DitherKind.familyLines, DitherKind.familyNoise]);
    expect(DitherKind.inFamily(DitherKind.familyLines).length, 8);
    expect(DitherKind.inFamily(DitherKind.familyNoise), [DitherKind.blueNoise, DitherKind.whiteNoise, DitherKind.ign]);
  });

  test('DitherTilePainter repaints only when the kind, a color, or the scale changes', () {
    const a = DitherTilePainter(kind: DitherKind.bayer4, onColor: Colors.black, offColor: Colors.white, scale: 4);
    expect(a.shouldRepaint(const DitherTilePainter(kind: DitherKind.bayer4, onColor: Colors.black, offColor: Colors.white, scale: 4)), isFalse);
    expect(a.shouldRepaint(const DitherTilePainter(kind: DitherKind.blueNoise, onColor: Colors.black, offColor: Colors.white, scale: 4)), isTrue);
    expect(a.shouldRepaint(const DitherTilePainter(kind: DitherKind.bayer4, onColor: Colors.blue, offColor: Colors.white, scale: 4)), isTrue);
    expect(a.shouldRepaint(const DitherTilePainter(kind: DitherKind.bayer4, onColor: Colors.black, offColor: Colors.grey, scale: 4)), isTrue);
    expect(a.shouldRepaint(const DitherTilePainter(kind: DitherKind.bayer4, onColor: Colors.black, offColor: Colors.white, scale: 2)), isTrue);
  });

  test('DitherRampPainter.cellOn is the engine\'s pick: floor(t · levels) > threshold', () {
    const cols = 128, rows = 16;
    for (final k in DitherKind.all) {
      for (var y = 0; y < rows; y++) {
        expect(DitherRampPainter.cellOn(k, 0, y, cols), isFalse, reason: '$k: the left edge is all OFF');
        expect(DitherRampPainter.cellOn(k, cols - 1, y, cols), !k.isOff, reason: '$k: the right edge is all ON');
      }
      if (k.isOff) continue;
      var on = 0;
      for (var x = 0; x < cols; x++) {
        for (var y = 0; y < rows; y++) {
          final t = x / (cols - 1);
          final expected = (t * k.levels).floor() > k.threshold(x, y);
          expect(DitherRampPainter.cellOn(k, x, y, cols), expected, reason: '$k at ($x,$y)');
          if (expected) on++;
        }
      }
      // A linear ramp through evenly spread thresholds averages 1/2 − 1/(2·levels) ON: the
      // engine's floor truncation of t·levels (the fill has the same bias, so the strip must too).
      expect(on / (cols * rows), closeTo(0.5 - 0.5 / k.levels, 0.06), reason: '$k: the ramp average');
    }
    expect(DitherRampPainter.fractionAt(0, 1), 1, reason: 'a one-column strip is all ON');
  });

  test('DitherRampPainter repaints only when the kind, a color, or the scale changes', () {
    const a = DitherRampPainter(kind: DitherKind.bayer4, onColor: Colors.black, offColor: Colors.white, scale: 3);
    expect(a.shouldRepaint(const DitherRampPainter(kind: DitherKind.bayer4, onColor: Colors.black, offColor: Colors.white, scale: 3)), isFalse);
    expect(a.shouldRepaint(const DitherRampPainter(kind: DitherKind.off, onColor: Colors.black, offColor: Colors.white, scale: 3)), isTrue);
    expect(a.shouldRepaint(const DitherRampPainter(kind: DitherKind.bayer4, onColor: Colors.blue, offColor: Colors.white, scale: 3)), isTrue);
    expect(a.shouldRepaint(const DitherRampPainter(kind: DitherKind.bayer4, onColor: Colors.black, offColor: Colors.grey, scale: 3)), isTrue);
    expect(a.shouldRepaint(const DitherRampPainter(kind: DitherKind.bayer4, onColor: Colors.black, offColor: Colors.white, scale: 2)), isTrue);
  });

  testWidgets('ramp strips paint through the ramp painter in the two colors, Off included', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(children: [
          SizedBox(
            width: 300,
            height: 48,
            child: CustomPaint(
                painter: DitherRampPainter(kind: DitherKind.hlines2, onColor: Colors.red, offColor: Colors.blue, scale: 3)),
          ),
          SizedBox(
            width: 300,
            height: 48,
            child: CustomPaint(painter: DitherRampPainter(kind: DitherKind.off, onColor: Colors.red, offColor: Colors.blue, scale: 3)),
          ),
        ]),
      ),
    ));
    expect(t.takeException(), isNull);
    final painters = t.widgetList<CustomPaint>(find.byType(CustomPaint)).map((w) => w.painter).whereType<DitherRampPainter>();
    expect(painters.map((p) => p.kind), [DitherKind.hlines2, DitherKind.off]);
    expect(painters.first.onColor, Colors.red);
  });
}
