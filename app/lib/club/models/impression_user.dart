/// One member whose screens showed an artwork: a row of the "Displayed on" list behind the 📺
/// number (`GET /post/{id}/impression-users`, server thread `messages/0009-impression-list/`).
///
/// One row per member, most recently shown first. The server never lists the artwork's author,
/// anonymous viewers, members the caller blocked, or members who switched the listing off, so
/// the rows do not add up to the post's `impression_count`.
class ImpressionUser {
  final String handle;
  final String? avatarUrl;
  final String? sqid;

  /// Models of the member's players that showed the artwork ("p3a"). May be empty; the
  /// member's own names for their players are never sent.
  final List<String> deviceModels;

  /// The member's Web Player showed it.
  final bool webPlayer;

  /// The mobile app showed it (reported as an Impression).
  final bool app;

  /// Showings counted for this member on this artwork.
  final int count;

  /// The UTC calendar day of the latest showing, as midnight UTC. **A day, never a time**: the
  /// server sends a date so that no client can tell when someone's player is running, and
  /// [parseDay] drops anything after the date should a time ever appear. Render it with
  /// `shownDayLabel` only.
  final DateTime? lastShownOn;

  const ImpressionUser({
    required this.handle,
    this.avatarUrl,
    this.sqid,
    this.deviceModels = const [],
    this.webPlayer = false,
    this.app = false,
    this.count = 0,
    this.lastShownOn,
  });

  factory ImpressionUser.fromJson(Map<String, dynamic> j) => ImpressionUser(
        handle: (j['user_handle'] ?? '').toString(),
        avatarUrl: j['user_avatar_url'] as String?,
        sqid: j['user_public_sqid'] as String?,
        deviceModels: [
          for (final m in (j['device_models'] as List?) ?? const [])
            if (m.toString().trim().isNotEmpty) m.toString().trim(),
        ],
        webPlayer: j['web_player'] == true,
        app: j['app'] == true,
        count: (j['count'] as num?)?.toInt() ?? 0,
        lastShownOn: parseDay(j['last_shown_on']),
      );

  /// `YYYY-MM-DD` → that day at midnight UTC; null when absent or malformed. Only the first ten
  /// characters are read.
  static DateTime? parseDay(Object? raw) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw?.toString() ?? '');
    if (m == null) return null;
    final (y, mo, d) = (int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
    return DateTime.utc(y, mo, d);
  }
}
