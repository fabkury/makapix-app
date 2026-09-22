/// Mentions — the `<@SQID>` markup that comment bodies and post descriptions may
/// carry, and the two conversions the app needs around it.
///
/// Design: `docs/mentions/README.md` (§4 representation, §6.1 test vectors);
/// decisions in `docs/mentions/DECISIONS.md` (D2, D17, D18, D19). The contract
/// sent to the server team is `messages/0004-mentions/0001-app-mentions-proposal.md`.
///
/// Why the markup carries a sqid and not a handle: handles are mutable and
/// unique only by confusable skeleton, so a stored handle goes stale on rename.
/// `public_sqid` is the stable identity, and the server resolves it to the
/// current handle on every read (the `mentions` array beside each markup field).
///
/// Nothing here talks to the network or the engine, so it runs in plain
/// `flutter test`.
library;

/// Cap on how many mentions one comment or description may carry.
///
/// The server is the authority (`max_mentions_per_text` on `GET /config`, which
/// is also the feature's launch signal) and flattens the extras on write rather
/// than rejecting the text. This constant is the app's default for the same
/// rule, so the composer's cap hint and what we serialize always agree.
const int kMaxMentionsPerText = 16;

/// Handle shown for a sqid that resolves to no account. The server writes this
/// same placeholder into the plain rendering when it flattens an unresolvable
/// mention on write; we use it when a `mentions` array is missing an entry
/// (a deleted account, most often).
const String kUnknownMentionHandle = 'user';

/// Characters a sqid may contain.
///
/// `SQIDS_ALPHABET` is environment-configured on the server and is not in any
/// repo, so no client can match the real alphabet. We match a base62 superset
/// and let the server be the only party that decides whether a syntactically
/// valid sqid resolves to anyone. Confirming this class is item 1 of §12 in the
/// contract message.
final RegExp _mentionPattern = RegExp(r'<@([A-Za-z0-9]{1,32})>');

/// Characters a handle may contain, mirroring the server's rule and
/// `auth/account_validators.dart`. Used to decide whether an `@handle` token in
/// composer text is still intact.
final RegExp _handleChar = RegExp(r'[\p{L}\p{Nd}\p{Mn}\p{Mc}_-]', unicode: true);

/// One entry of the `mentions` array the server sends beside `body_markup` /
/// `description_markup`: the sqids that text contains, resolved at read time.
class MentionRef {
  final String sqid;
  final String handle;
  final String? avatarUrl;

  const MentionRef({required this.sqid, required this.handle, this.avatarUrl});

  factory MentionRef.fromJson(Map<String, dynamic> j) => MentionRef(
        sqid: (j['public_sqid'] ?? '').toString(),
        handle: (j['handle'] ?? kUnknownMentionHandle).toString(),
        avatarUrl: j['avatar_url'] as String?,
      );

  /// Parses the `mentions` array of a comment or post payload. Entries without
  /// a sqid are dropped.
  static List<MentionRef> listFromJson(dynamic raw) {
    if (raw is! List) return const [];
    final out = <MentionRef>[];
    for (final e in raw) {
      if (e is Map<String, dynamic>) {
        final m = MentionRef.fromJson(e);
        if (m.sqid.isNotEmpty) out.add(m);
      }
    }
    return out;
  }

  /// A `sqid → handle` lookup for [parseMentionMarkup].
  static Map<String, String> handlesOf(List<MentionRef> refs) => {
        for (final r in refs) r.sqid: r.handle,
      };

  @override
  String toString() => 'MentionRef($sqid → @$handle)';
}

/// One piece of a parsed text: either literal text or a resolved mention.
sealed class MentionSegment {
  const MentionSegment();
}

/// Literal text, rendered as-is.
final class PlainSegment extends MentionSegment {
  final String text;
  const PlainSegment(this.text);

  @override
  String toString() => 'Plain(${text.replaceAll('\n', r'\n')})';

  @override
  bool operator ==(Object other) => other is PlainSegment && other.text == text;

  @override
  int get hashCode => text.hashCode;
}

/// A mention, rendered as a tappable `@handle` that opens the profile for [sqid].
final class MentionedSegment extends MentionSegment {
  final String sqid;
  final String handle;
  const MentionedSegment({required this.sqid, required this.handle});

  /// What this mention looks like in the plain rendering.
  String get display => '@$handle';

  @override
  String toString() => 'Mention($sqid → @$handle)';

  @override
  bool operator ==(Object other) =>
      other is MentionedSegment && other.sqid == sqid && other.handle == handle;

  @override
  int get hashCode => Object.hash(sqid, handle);
}

/// A pick the composer recorded: the user chose [handle] from the candidates
/// list, and it stands for [sqid].
class PickedMention {
  final String handle;
  final String sqid;
  const PickedMention({required this.handle, required this.sqid});

  @override
  String toString() => 'PickedMention(@$handle → $sqid)';

  @override
  bool operator ==(Object other) =>
      other is PickedMention && other.handle == handle && other.sqid == sqid;

  @override
  int get hashCode => Object.hash(handle, sqid);
}

/// Splits [markup] into text and mention segments.
///
/// [handles] maps sqid → current handle, built from the server's `mentions`
/// array ([MentionRef.handlesOf]). A sqid with no entry renders as plain
/// `@user` text and is never tappable, which is what a deleted account looks
/// like.
///
/// Malformed markup is literal text: `<@t5`, `<@>`, `<@ t5>` and `< @t5>` all
/// render exactly as written. There is no word-boundary rule, so `a<@t5>b`
/// yields `a`, the mention, `b`.
///
/// At most [maxMentions] mentions are linked; any beyond that render as plain
/// `@handle` text. The server flattens the extras on write, so in practice this
/// only fires on text from a server that has not (D12 ordering) or on our own
/// optimistic text.
///
/// Adjacent plain pieces are merged, so the result never holds two consecutive
/// [PlainSegment]s and never holds an empty one.
List<MentionSegment> parseMentionMarkup(
  String markup, {
  Map<String, String> handles = const {},
  int maxMentions = kMaxMentionsPerText,
}) {
  if (markup.isEmpty) return const [];

  final out = <MentionSegment>[];
  final buffer = StringBuffer();
  var linked = 0;
  var cursor = 0;

  void flush() {
    if (buffer.isNotEmpty) {
      out.add(PlainSegment(buffer.toString()));
      buffer.clear();
    }
  }

  for (final m in _mentionPattern.allMatches(markup)) {
    buffer.write(markup.substring(cursor, m.start));
    cursor = m.end;

    final sqid = m.group(1)!;
    final handle = handles[sqid];

    if (handle == null) {
      // Unresolvable: plain text, never tappable.
      buffer.write('@$kUnknownMentionHandle');
    } else if (linked >= maxMentions) {
      buffer.write('@$handle');
    } else {
      flush();
      out.add(MentionedSegment(sqid: sqid, handle: handle));
      linked++;
    }
  }

  buffer.write(markup.substring(cursor));
  flush();
  return out;
}

/// The plain rendering of [markup]: every `<@SQID>` replaced by `@handle`.
///
/// This is what the server serves in `body` / `description` for clients that do
/// not know the markup. The app needs it for optimistic local text, where it
/// holds the markup it just sent but not yet the server's plain field, and for
/// anything that wants an unstyled copy (share text, the report sheet).
String plainFromMarkup(
  String markup, {
  Map<String, String> handles = const {},
  int maxMentions = kMaxMentionsPerText,
}) {
  final segments =
      parseMentionMarkup(markup, handles: handles, maxMentions: maxMentions);
  return segments
      .map((s) => switch (s) {
            PlainSegment(:final text) => text,
            MentionedSegment() => s.display,
          })
      .join();
}

/// True when [markup] contains at least one syntactically valid mention.
bool hasMentionMarkup(String markup) => _mentionPattern.hasMatch(markup);

/// Turns composer text into the markup to send.
///
/// The composer's text fields always show plain `@handle` — the user never sees
/// a sqid (D2) — so the composer keeps the display string plus the list of
/// [picked] pairs and calls this on send.
///
/// A pick becomes `<@sqid>` only where its `@handle` token still appears intact
/// in [displayText]: the `@` must start the text or follow a non-handle
/// character, and the handle must not run straight into more handle characters.
/// So editing `@fab` into `@fabx`, or deleting it, quietly drops that mention —
/// which is the behavior we want, since the user no longer sees the handle they
/// picked.
///
/// Each occurrence consumes one pick, so picking the same person twice mentions
/// them at both of the first two occurrences. Where two picked handles both
/// match at one position (`@fab` and `@fabkury`), the longer one wins.
///
/// At most [maxMentions] replacements are made; later matches stay plain text,
/// matching what the server would do on write.
///
/// Text the user typed that already looks like markup is left alone. Pasted
/// valid markup is an accepted way to mention (D19), and the server's
/// mentionability check is what decides whether it survives.
String serializeMentions(
  String displayText,
  List<PickedMention> picked, {
  int maxMentions = kMaxMentionsPerText,
}) {
  if (displayText.isEmpty || picked.isEmpty) return displayText;

  // Longest handle first, so `@fabkury` is not eaten by a pick of `@fab`.
  final remaining = [...picked]
    ..sort((a, b) => b.handle.length.compareTo(a.handle.length));

  final out = StringBuffer();
  var i = 0;
  var used = 0;

  while (i < displayText.length) {
    final ch = displayText[i];
    if (ch != '@' || used >= maxMentions || remaining.isEmpty) {
      out.write(ch);
      i++;
      continue;
    }

    // The `@` must open a token: start of text, or after a non-handle char.
    final precededByHandleChar =
        i > 0 && _handleChar.hasMatch(displayText[i - 1]);
    if (precededByHandleChar) {
      out.write(ch);
      i++;
      continue;
    }

    PickedMention? hit;
    for (final p in remaining) {
      final end = i + 1 + p.handle.length;
      if (end > displayText.length) continue;
      if (displayText.substring(i + 1, end) != p.handle) continue;
      // The token must end here, not run into more handle characters.
      if (end < displayText.length && _handleChar.hasMatch(displayText[end])) {
        continue;
      }
      hit = p;
      break;
    }

    if (hit == null) {
      out.write(ch);
      i++;
      continue;
    }

    out.write('<@${hit.sqid}>');
    i += 1 + hit.handle.length;
    used++;
    remaining.remove(hit);
  }

  return out.toString();
}
