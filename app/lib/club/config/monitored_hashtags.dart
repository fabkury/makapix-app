/// The fixed set of **monitored hashtags** — a content filter, not a follow list
/// (`SPEC-CLUB.md` §21). Posts tagged with any of these are hidden by default,
/// everywhere, and shown only to members who have opted in (`approved_hashtags`).
///
/// This mirrors the server's `MONITORED_HASHTAGS` constant byte-for-byte
/// (`api/app/constants.py`); the server rejects a `PATCH /user/{id}` whose
/// `approved_hashtags` contains anything outside this set.
class MonitoredHashtag {
  final String tag;
  final String label;
  final String description;
  const MonitoredHashtag(this.tag, this.label, this.description);
}

/// Order matches the website's settings screen.
const List<MonitoredHashtag> kMonitoredHashtags = [
  MonitoredHashtag('politics', '#politics', 'Political content'),
  MonitoredHashtag('nsfw', '#nsfw', 'Not safe for work'),
  MonitoredHashtag('explicit', '#explicit', 'Explicit content'),
  MonitoredHashtag('13plus', '#13plus', 'Intended for ages 13 and up'),
  MonitoredHashtag('violence', '#violence', 'Depictions of violence'),
];

/// The bare tag strings, for membership checks / validation.
final Set<String> kMonitoredHashtagTags = {for (final h in kMonitoredHashtags) h.tag};
