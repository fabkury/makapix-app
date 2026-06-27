/// The curated reaction set surfaced in the app (SPEC-CLUB §12). The server
/// accepts any emoji, but the app presents these five for consistency with the
/// website.
const List<String> kReactionEmojis = ['👍', '❤️', '🔥', '😊', '💎'];

/// Per-post reaction aggregate: `GET /post/{id}/reactions`.
class ReactionTotals {
  final Map<String, int> totals;
  final Map<String, int> authenticatedTotals;
  final Map<String, int> anonymousTotals;
  final Set<String> mine;

  const ReactionTotals({
    this.totals = const {},
    this.authenticatedTotals = const {},
    this.anonymousTotals = const {},
    this.mine = const {},
  });

  static Map<String, int> _intMap(Object? v) {
    if (v is! Map) return const {};
    return v.map((k, val) => MapEntry(k.toString(), (val as num).toInt()));
  }

  factory ReactionTotals.fromJson(Map<String, dynamic> j) => ReactionTotals(
        totals: _intMap(j['totals']),
        authenticatedTotals: _intMap(j['authenticated_totals']),
        anonymousTotals: _intMap(j['anonymous_totals']),
        mine: ((j['mine'] as List?) ?? const []).map((e) => e.toString()).toSet(),
      );

  int countFor(String emoji) => totals[emoji] ?? 0;
  bool hasMine(String emoji) => mine.contains(emoji);
  int get mineCount => mine.length;

  /// Optimistic local toggle of one emoji (add/remove), respecting idempotency.
  /// Caller enforces the ≤5/user cap before adding.
  ReactionTotals withLocal({required String emoji, required bool add}) {
    final t = Map<String, int>.from(totals);
    final mn = Set<String>.from(mine);
    if (add && !mn.contains(emoji)) {
      mn.add(emoji);
      t[emoji] = (t[emoji] ?? 0) + 1;
    } else if (!add && mn.contains(emoji)) {
      mn.remove(emoji);
      final c = (t[emoji] ?? 1) - 1;
      if (c <= 0) {
        t.remove(emoji);
      } else {
        t[emoji] = c;
      }
    }
    return ReactionTotals(
      totals: t,
      authenticatedTotals: authenticatedTotals,
      anonymousTotals: anonymousTotals,
      mine: mn,
    );
  }
}
