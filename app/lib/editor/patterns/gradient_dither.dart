// The Gradient's dither families (ADR 0025 for Bayer, ADR 0028 for the rest): the shell's mirror
// of the engine's `DitherKind`. Each kind carries its DSL token (what `SetGradientDither(...)`
// puts on the wire and what the preference stores), a display name, the family that groups it on
// the Dither page, its number of density steps, and a threshold function used ONLY for previews:
// the row-1 swatch renders the family at its 50 % density, the page as a full OFF→ON ramp
// (every density step, left to right — [DitherRampPainter], 2026-09-16). The engine evaluates
// its own copy of the same tables and formulas when it fills — `dither_tables.g.dart` and
// `crates/engine/src/tool/dither_tables.g.rs` come from one generator run
// (`tools/dither/gen_tables.py`), and the formula kinds are pinned to the same values in both
// test suites — so what the page shows is what the fill does.
import 'package:flutter/material.dart';

import 'dither_tables.g.dart';
import 'patterns_catalog.dart' show bayerMatrix;

enum _Family { off, bayer, blue, halftone, hlines, vlines, diag, noise, ign }

/// One dither family/size the Gradient can use. Compare by identity or `==` (value semantics
/// over the DSL token).
class DitherKind {
  const DitherKind._(this._fam, this.n, this.dsl, this.name, this.family, this.levels, this.hint);

  final _Family _fam;

  /// The matrix size or line period for the periodic kinds (0 for the noises and Off).
  final int n;

  /// The token `SetGradientDither(...)` carries: the Bayer sizes stay the bare numbers they have
  /// been since ADR 0025 (`0` = off), the other families are words.
  final String dsl;
  final String name;

  /// The Dither page section this kind is listed under (empty for Off).
  final String family;

  /// The number of density steps: thresholds run `0..levels`.
  final int levels;

  /// The page's one-line subtitle.
  final String hint;

  bool get isOff => _fam == _Family.off;

  static const String familyBayer = 'Bayer ordered dither';
  static const String familyHalftone = 'Halftone';
  static const String familyLines = 'Lines';
  static const String familyNoise = 'Noise';

  /// The page's section order. Blue noise lists under Noise (user decision 2026-09-06), so the
  /// page order differs from [all] there.
  static const List<String> families = [familyBayer, familyHalftone, familyLines, familyNoise];

  static const off = DitherKind._(_Family.off, 0, '0', 'Off', '', 1, 'A smooth ramp between the colors');
  static const bayer2 = DitherKind._(_Family.bayer, 2, '2', 'Bayer 2×2', familyBayer, 4, '4 density steps');
  static const bayer4 = DitherKind._(_Family.bayer, 4, '4', 'Bayer 4×4', familyBayer, 16, '16 density steps');
  static const bayer8 = DitherKind._(_Family.bayer, 8, '8', 'Bayer 8×8', familyBayer, 64, '64 density steps');
  static const blueNoise =
      DitherKind._(_Family.blue, 64, 'blue', 'Blue noise', familyNoise, 4096, '4096 steps, no visible pattern');
  static const halftone4 =
      DitherKind._(_Family.halftone, 4, 'halftone4', 'Halftone 4×4', familyHalftone, 16, 'Dots growing from the cell center');
  static const halftone8 =
      DitherKind._(_Family.halftone, 8, 'halftone8', 'Halftone 8×8', familyHalftone, 64, 'Bigger dots, 64 steps');
  static const hlines2 = DitherKind._(_Family.hlines, 2, 'hlines2', 'Horizontal 2 px', familyLines, 4, 'Every other row at 50 %');
  static const hlines4 = DitherKind._(_Family.hlines, 4, 'hlines4', 'Horizontal 4 px', familyLines, 16, 'Rows fill in, 16 steps');
  static const hlines8 = DitherKind._(_Family.hlines, 8, 'hlines8', 'Horizontal 8 px', familyLines, 64, 'Rows fill in, 64 steps');
  static const vlines2 = DitherKind._(_Family.vlines, 2, 'vlines2', 'Vertical 2 px', familyLines, 4, 'Every other column at 50 %');
  static const vlines4 = DitherKind._(_Family.vlines, 4, 'vlines4', 'Vertical 4 px', familyLines, 16, 'Columns fill in, 16 steps');
  static const vlines8 = DitherKind._(_Family.vlines, 8, 'vlines8', 'Vertical 8 px', familyLines, 64, 'Columns fill in, 64 steps');
  static const diag4 = DitherKind._(_Family.diag, 4, 'diag4', 'Diagonal 4 px', familyLines, 16, 'Hatching, 16 steps');
  static const diag8 = DitherKind._(_Family.diag, 8, 'diag8', 'Diagonal 8 px', familyLines, 64, 'Hatching, 64 steps');
  static const whiteNoise = DitherKind._(_Family.noise, 0, 'noise', 'White noise', familyNoise, 256, 'Random grain, 256 steps');
  static const ign =
      DitherKind._(_Family.ign, 0, 'ign', 'Gradient noise', familyNoise, 256, 'Interleaved gradient noise, 256 steps');

  /// Every kind, Off first, in the page's order (the engine's `DitherKind::ALL`).
  static const List<DitherKind> all = [
    off,
    bayer2,
    bayer4,
    bayer8,
    blueNoise,
    halftone4,
    halftone8,
    hlines2,
    hlines4,
    hlines8,
    vlines2,
    vlines4,
    vlines8,
    diag4,
    diag8,
    whiteNoise,
    ign,
  ];

  /// The kinds listed under [family], in page order.
  static Iterable<DitherKind> inFamily(String family) => all.where((k) => k.family == family);

  /// Parse a DSL/preference token (case-insensitive; `off` and `bayerN` are accepted spellings,
  /// like the engine). `null` for anything else.
  static DitherKind? parse(String s) {
    final t = s.trim().toLowerCase();
    if (t == 'off') return off;
    for (final k in all) {
      if (k.dsl == t) return k;
      if (k._fam == _Family.bayer && t == 'bayer${k.n}') return k;
    }
    return null;
  }

  static final Map<int, List<List<int>>> _bayer = {2: bayerMatrix(2), 4: bayerMatrix(4), 8: bayerMatrix(8)};

  /// The engine's `util::hash_xy` seed for the white-noise dither ("MKPXDITH").
  static const int _whiteNoiseSeed = 0x4D4B505844495448;

  /// The threshold at canvas coordinate (x, y), in `0..levels` — the engine's expression, so a
  /// preview at 50 % shows exactly the cells the fill flips first.
  int threshold(int x, int y) {
    switch (_fam) {
      case _Family.off:
        return 0;
      case _Family.bayer:
        return _bayer[n]![y % n][x % n];
      case _Family.blue:
        return kBlueNoise[(y % kBlueNoiseSide) * kBlueNoiseSide + (x % kBlueNoiseSide)];
      case _Family.halftone:
        return n == 8 ? kHalftone8[y % 8][x % 8] : kHalftone4[y % 4][x % 4];
      case _Family.hlines:
        return _bitrevRank(y, n) * n + _bitrevRank(x, n);
      case _Family.vlines:
        return _bitrevRank(x, n) * n + _bitrevRank(y, n);
      case _Family.diag:
        return _bitrevRank(x + y, n) * n + _bitrevRank(x, n);
      case _Family.noise:
        return _hashXy(x, y, _whiteNoiseSeed) >>> 56;
      case _Family.ign:
        // fract(52.9829189 · fract(0.06711056·x + 0.00583715·y)) in 0.32 fixed point, exactly as
        // the engine computes it (the three constants times 2³², products wrapped mod 2³²).
        final f = ((x & 0xFFFFFFFF) * 288237660 + (y & 0xFFFFFFFF) * 25070368) & 0xFFFFFFFF;
        final g = (f * 52 + ((f * 4221604530) >>> 32)) & 0xFFFFFFFF;
        return g >>> 24;
    }
  }

  /// The bit-reversal rank of `v mod n` for n ∈ {2, 4, 8}: the order lines fill in.
  static int _bitrevRank(int v, int n) {
    final r = v % n;
    switch (n) {
      case 8:
        return ((r & 1) << 2) | (r & 2) | ((r & 4) >> 2);
      case 4:
        return ((r & 1) << 1) | ((r & 2) >> 1);
      default:
        return r & 1;
    }
  }

  static int _splitmix64(int z) {
    var v = z;
    v = (v ^ (v >>> 30)) * 0xBF58476D1CE4E5B9;
    v = (v ^ (v >>> 27)) * 0x94D049BB133111EB;
    return v ^ (v >>> 31);
  }

  static int _hashXy(int x, int y, int seed) {
    final p = ((x & 0xFFFFFFFF) << 32) | (y & 0xFFFFFFFF);
    return _splitmix64(seed + _splitmix64(p));
  }

  @override
  bool operator ==(Object other) => other is DitherKind && other.dsl == dsl;

  @override
  int get hashCode => dsl.hashCode;

  @override
  String toString() => 'DitherKind($dsl)';
}

/// Paints [kind] at its 50 % density over the whole box at [scale] logical px per cell (the row-1
/// swatch), anchored
/// at the box's top-left (canvas coordinate (0, 0)): OFF cells in [offColor] (the whole box
/// first), the cells the fill flips first in [onColor] over it.
class DitherTilePainter extends CustomPainter {
  const DitherTilePainter({required this.kind, required this.onColor, required this.offColor, required this.scale});
  final DitherKind kind;
  final Color onColor, offColor;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = offColor);
    if (kind.isOff) return;
    final paint = Paint()..color = onColor;
    final half = kind.levels ~/ 2;
    final cols = (size.width / scale).ceil();
    final rows = (size.height / scale).ceil();
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        if (kind.threshold(x, y) < half) {
          canvas.drawRect(Rect.fromLTWH(x * scale, y * scale, scale, scale), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(DitherTilePainter old) =>
      old.kind != kind || old.onColor != onColor || old.offColor != offColor || old.scale != scale;
}

/// Paints a two-color gradient ramp through [kind] over the whole box (the Dither page's wide
/// previews, 2026-09-16): [offColor] at the left edge to [onColor] at the right, one canvas cell
/// per [scale] logical px, anchored at canvas (0, 0). Each cell is exactly one of the two colors,
/// picked by the engine's rule (`gradient_sample_sorted`): ON when `floor(t · levels) >
/// threshold(x, y)`, with `t` the cell's column fraction — so the strip walks every density step
/// the fill can produce, in order. Off paints the smooth ramp the undithered fill makes.
class DitherRampPainter extends CustomPainter {
  const DitherRampPainter({required this.kind, required this.onColor, required this.offColor, required this.scale});
  final DitherKind kind;
  final Color onColor, offColor;
  final double scale;

  /// The ramp fraction of column [x] in a strip [cols] cells wide: 0 at the left edge, 1 at the
  /// right (a one-column strip is all ON).
  static double fractionAt(int x, int cols) => cols <= 1 ? 1 : x / (cols - 1);

  /// Whether the cell at ([x], [y]) of a [cols]-wide ramp through [kind] takes the ON color —
  /// the engine's pick for a pixel whose local fraction is [fractionAt]. Always false for Off.
  static bool cellOn(DitherKind kind, int x, int y, int cols) {
    if (kind.isOff) return false;
    final q = (fractionAt(x, cols) * kind.levels).floor();
    return q > kind.threshold(x, y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = offColor);
    final cols = (size.width / scale).ceil();
    final rows = (size.height / scale).ceil();
    if (kind.isOff) {
      // The smooth ramp, one lerped column per cell.
      for (var x = 0; x < cols; x++) {
        final c = Color.lerp(offColor, onColor, fractionAt(x, cols))!;
        canvas.drawRect(Rect.fromLTWH(x * scale, 0, scale, size.height), Paint()..color = c);
      }
      return;
    }
    // One path for every ON cell: a single fill instead of thousands of draw calls.
    final path = Path();
    for (var x = 0; x < cols; x++) {
      for (var y = 0; y < rows; y++) {
        if (cellOn(kind, x, y, cols)) path.addRect(Rect.fromLTWH(x * scale, y * scale, scale, scale));
      }
    }
    canvas.drawPath(path, Paint()..color = onColor);
  }

  @override
  bool shouldRepaint(DitherRampPainter old) =>
      old.kind != kind || old.onColor != onColor || old.offColor != offColor || old.scale != scale;
}
