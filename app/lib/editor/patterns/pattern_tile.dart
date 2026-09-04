// A pattern tile (ADR 0025): the shell-side twin of the engine's `Pattern`: a small repeating
// bitmask that gates painting. Pure Dart, no engine: the editor, the Patterns page, the catalog,
// the prefs, and the widget tests all share this one value type. A tile is its bits: two tiles
// with the same size and bits are equal whatever a catalog calls them, which is what lets the
// journal carry `SetPattern(w,h,hex)` and never a name.

/// The engine's hard cap on a tile side (`PATTERN_MAX_SIDE` in `crates/engine/src/tool.rs`).
/// The v1 catalog stops at 8×8; 12×12 and 16×16 tiles are already valid on the wire.
const int kPatternMaxSide = 16;

class PatternTile {
  /// Width and height in cells, each 1..=[kPatternMaxSide].
  final int w, h;

  /// Bit `y*w + x` is the cell at (x, y): the engine's layout. Always < 2^(w*h).
  final BigInt bits;

  const PatternTile._(this.w, this.h, this.bits);

  /// Build from raw bits; `null` when a side is out of range or a bit at or beyond `w*h` is set.
  static PatternTile? tryCreate(int w, int h, BigInt bits) {
    if (w < 1 || w > kPatternMaxSide || h < 1 || h > kPatternMaxSide) return null;
    if (bits.isNegative || bits >= (BigInt.one << (w * h))) return null;
    return PatternTile._(w, h, bits);
  }

  /// Build from ASCII rows (`#` = ON, anything else = OFF); rows must be equal length.
  static PatternTile? rows(List<String> rows) {
    if (rows.isEmpty) return null;
    final w = rows.first.length;
    if (w == 0) return null;
    var bits = BigInt.zero;
    for (var y = 0; y < rows.length; y++) {
      if (rows[y].length != w) return null;
      for (var x = 0; x < w; x++) {
        if (rows[y][x] == '#') bits |= BigInt.one << (y * w + x);
      }
    }
    return tryCreate(w, rows.length, bits);
  }

  /// Build from a predicate over cells.
  static PatternTile? generate(int w, int h, bool Function(int x, int y) on) {
    var bits = BigInt.zero;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (on(x, y)) bits |= BigInt.one << (y * w + x);
      }
    }
    return tryCreate(w, h, bits);
  }

  /// The prefs / DSL-argument form `w,h,hex` (the same three arguments `SetPattern` takes);
  /// `null` for anything malformed, so a stale or hand-edited preference reads as "no pattern".
  static PatternTile? parse(String s) {
    final parts = s.split(',');
    if (parts.length != 3) return null;
    final w = int.tryParse(parts[0].trim());
    final h = int.tryParse(parts[1].trim());
    final hex = parts[2].trim();
    if (w == null || h == null || hex.isEmpty || hex.length > 64) return null;
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) return null;
    return tryCreate(w, h, BigInt.parse(hex, radix: 16));
  }

  /// The cell at canvas coordinate (x, y), tiled (negative coordinates wrap like positive ones).
  bool on(int x, int y) {
    final cx = x % w, cy = y % h; // Dart's % is non-negative for a positive divisor
    return (bits >> (cy * w + cx)).isOdd;
  }

  int get cellCount => w * h;

  bool get isAllOn => bits == (BigInt.one << cellCount) - BigInt.one;
  bool get isAllOff => bits == BigInt.zero;

  /// The number of ON cells.
  int get onCount {
    var n = 0;
    for (var i = 0; i < cellCount; i++) {
      if ((bits >> i).isOdd) n++;
    }
    return n;
  }

  /// The complementary tile (every cell flipped).
  PatternTile get inverse => PatternTile._(w, h, bits ^ ((BigInt.one << cellCount) - BigInt.one));

  /// Fixed-width lowercase hex, `ceil(w*h/4)` digits: the engine's `Pattern::hex()`.
  String get hex => bits.toRadixString(16).padLeft((cellCount + 3) ~/ 4, '0');

  /// The journal line that puts this tile in force.
  String get dsl => 'SetPattern($w,$h,$hex)';

  /// The prefs form (`parse` reads it back).
  String get pref => '$w,$h,$hex';

  @override
  bool operator ==(Object other) => other is PatternTile && other.w == w && other.h == h && other.bits == bits;

  @override
  int get hashCode => Object.hash(w, h, bits);

  @override
  String toString() => 'PatternTile($pref)';
}

/// Keep [tile] at the front of a most-recent-first list, deduplicated and capped at [cap].
List<PatternTile> pushRecentPattern(List<PatternTile> recents, PatternTile tile, {int cap = 10}) {
  final out = <PatternTile>[tile, for (final t in recents) if (t != tile) t];
  return out.length > cap ? out.sublist(0, cap) : out;
}
