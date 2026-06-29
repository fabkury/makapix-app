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

  /// Per-emoji counts derived from a fetched reactor list, ordered by the curated
  /// set first (then any others), so a summary header stays consistent with the rows.
  static Map<String, int> countEmojis(List<ReactionUser> reactors) {
    final raw = <String, int>{};
    for (final r in reactors) {
      raw[r.emoji] = (raw[r.emoji] ?? 0) + 1;
    }
    final out = <String, int>{};
    for (final e in kReactionEmojis) {
      if (raw.containsKey(e)) out[e] = raw.remove(e)!;
    }
    out.addAll(raw); // any non-curated emojis the server returned, in encounter order
    return out;
  }

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

/// One authenticated reactor for the Reactions page: `GET /post/{id}/reaction-users`.
/// Anonymous reactions are excluded by the server, and the list is capped at the 200
/// most recent (no pagination).
class ReactionUser {
  final String emoji;
  final DateTime? createdAt;
  final String handle;
  final String? avatarUrl;
  final String? sqid;

  const ReactionUser({
    required this.emoji,
    required this.createdAt,
    required this.handle,
    this.avatarUrl,
    this.sqid,
  });

  factory ReactionUser.fromJson(Map<String, dynamic> j) => ReactionUser(
        emoji: (j['emoji'] ?? '').toString(),
        createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()),
        handle: (j['user_handle'] ?? '').toString(),
        avatarUrl: j['user_avatar_url'] as String?,
        sqid: j['user_public_sqid'] as String?,
      );
}
