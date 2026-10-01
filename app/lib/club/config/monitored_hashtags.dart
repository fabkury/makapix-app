import 'package:makapix_club/l10n/l10n.dart';

/// The fixed set of **monitored hashtags** — a content filter, not a follow list
/// (`SPEC-CLUB.md` §21). Posts tagged with any of these are hidden by default,
/// everywhere, and shown only to members who have opted in (`approved_hashtags`).
///
/// This mirrors the server's `MONITORED_HASHTAGS` constant byte-for-byte
/// (`api/app/constants.py`); the server rejects a `PATCH /user/{id}` whose
/// `approved_hashtags` contains anything outside this set.
class MonitoredHashtag {
  final String tag;
  const MonitoredHashtag(this.tag);

  /// The tag as written, `#nsfw` — the same in every language.
  String get label => '#$tag';

  /// What the tag covers, in the app's language.
  String description(AppLocalizations l) => switch (tag) {
        'politics' => l.monitoredPolitics,
        'nsfw' => l.monitoredNsfw,
        'explicit' => l.monitoredExplicit,
        '13plus' => l.monitored13plus,
        'violence' => l.monitoredViolence,
        _ => label,
      };
}

/// Order matches the website's settings screen.
const List<MonitoredHashtag> kMonitoredHashtags = [
  MonitoredHashtag('politics'),
  MonitoredHashtag('nsfw'),
  MonitoredHashtag('explicit'),
  MonitoredHashtag('13plus'),
  MonitoredHashtag('violence'),
];

/// The bare tag strings, for membership checks / validation.
final Set<String> kMonitoredHashtagTags = {for (final h in kMonitoredHashtags) h.tag};
