/// Feed filter/sort state — the website FilterButton's model (docs/club-gap
/// A4). Applies to the Recent feed, hashtag feeds, and profile galleries; all
/// of it maps onto `GET /post` query parameters. Session-only by design (the
/// website keeps it in the URL).
library;

/// The server's upload cap doubles as the file-size slider's right edge.
const int kFilterFileBytesCap = 5242880; // 5 MiB

/// The dimension badge values; 128 stands for "128+" (`*_gte=128`).
const List<int> kFilterDimensionBadges = [8, 16, 32, 64, 128];

/// At most this many Size badges may be active at once (server OR-logic cap).
const int kFilterMaxSizeBadges = 3;

class FeedFilters {
  final String sort; // created_at | reactions | file_bytes
  final String order; // desc | asc
  final int? base; // single badge: min(w,h) exact, 128 = "128+"; null = any
  final Set<int> sizes; // ≤3 badges: max(w,h) exact with OR logic, 128 = "128+"
  final int? fileBytesMin; // null/0 = unbounded
  final int? fileBytesMax; // null/≥cap = unbounded
  final Set<String> kinds; // subset of {static, animated}; empty or both = all

  const FeedFilters({
    this.sort = 'created_at',
    this.order = 'desc',
    this.base,
    this.sizes = const {},
    this.fileBytesMin,
    this.fileBytesMax,
    this.kinds = const {},
  });

  bool get _minActive => fileBytesMin != null && fileBytesMin! > 0;
  bool get _maxActive => fileBytesMax != null && fileBytesMax! < kFilterFileBytesCap;

  /// Default state fetches through the cheap dedicated feed endpoints instead
  /// of a filtered `GET /post`. Selecting BOTH kinds equals selecting none.
  bool get isDefault =>
      sort == 'created_at' &&
      order == 'desc' &&
      base == null &&
      sizes.isEmpty &&
      !_minActive &&
      !_maxActive &&
      kinds.length != 1;

  /// The `GET /post` query fragment (cursor/limit/feed-identity added by the
  /// caller). Mirrors `useFilters.ts::filtersToQuery`.
  Map<String, dynamic> toQuery() {
    final q = <String, dynamic>{'sort': sort, 'order': order};
    if (base != null) {
      if (base! >= 128) {
        q['base_gte'] = 128;
      } else {
        q['base'] = [base];
      }
    }
    if (sizes.isNotEmpty) {
      final regular = sizes.where((s) => s < 128).toList()..sort();
      if (regular.isNotEmpty) q['size'] = regular;
      if (sizes.any((s) => s >= 128)) q['size_gte'] = 128;
    }
    if (_minActive) q['file_bytes_min'] = fileBytesMin;
    if (_maxActive) q['file_bytes_max'] = fileBytesMax;
    if (kinds.length == 1) q['kind'] = kinds.toList();
    return q;
  }

  static String _canon(Iterable<Object> xs) => (xs.map((e) => e.toString()).toList()..sort()).join(',');

  @override
  bool operator ==(Object other) =>
      other is FeedFilters &&
      other.sort == sort &&
      other.order == order &&
      other.base == base &&
      _canon(other.sizes) == _canon(sizes) &&
      other.fileBytesMin == fileBytesMin &&
      other.fileBytesMax == fileBytesMax &&
      _canon(other.kinds) == _canon(kinds);

  @override
  int get hashCode => Object.hash(
      sort, order, base, _canon(sizes), fileBytesMin, fileBytesMax, _canon(kinds));
}
