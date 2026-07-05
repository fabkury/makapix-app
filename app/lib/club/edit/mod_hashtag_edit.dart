import '../config/monitored_hashtags.dart';

/// Client-side mirror of the server's hashtag normalization (server D12):
/// trim, strip **one** leading `#`, lowercase, drop empties, order-preserving
/// dedupe. Preview-only — the PUT response body remains the source of truth.
List<String> normalizeHashtags(Iterable<String> raw) {
  final out = <String>[];
  final seen = <String>{};
  for (final r in raw) {
    var t = r.trim();
    if (t.startsWith('#')) t = t.substring(1);
    t = t.trim().toLowerCase();
    if (t.isEmpty) continue;
    if (seen.add(t)) out.add(t);
  }
  return out;
}

/// Working state for the "Edit moderator hashtags" sheet. Pure Dart (no
/// Flutter imports) so the add/remove/toggle/cap/diff rules are unit-testable
/// without widgets.
class ModHashtagEdit {
  /// Per-tag length bound on the mod endpoint (contract §4 / server D16).
  static const int maxTagLength = 64;

  final List<String> _original;
  final List<String> _tags;
  final int cap;

  ModHashtagEdit({required List<String> initial, required this.cap})
      : _original = normalizeHashtags(initial),
        _tags = normalizeHashtags(initial);

  /// Current working list, insertion-ordered.
  List<String> get tags => List.unmodifiable(_tags);

  /// Why the last [add] was rejected (null after a successful add).
  String? lastRejection;

  /// Normalize [raw] and add it. Returns false (with [lastRejection] set) for
  /// empty input, an over-length tag, a duplicate, or a full set.
  bool add(String raw) {
    final normalized = normalizeHashtags([raw]);
    if (normalized.isEmpty) {
      lastRejection = 'Enter a hashtag.';
      return false;
    }
    final tag = normalized.first;
    if (tag.length > maxTagLength) {
      lastRejection = 'Hashtags are limited to $maxTagLength characters.';
      return false;
    }
    if (_tags.contains(tag)) {
      lastRejection = '#$tag is already on the list.';
      return false;
    }
    if (_tags.length >= cap) {
      lastRejection = 'Cap reached — $cap moderator hashtags max.';
      return false;
    }
    _tags.add(tag);
    lastRejection = null;
    return true;
  }

  void remove(String tag) => _tags.remove(tag);

  /// For the monitored quick-pick chips: remove if present, otherwise route
  /// through the guarded [add] so a chip cannot push the set past the cap.
  /// Returns whether the tag is in the set afterwards.
  bool toggle(String tag) {
    if (_tags.contains(tag)) {
      _tags.remove(tag);
      return false;
    }
    return add(tag);
  }

  bool contains(String tag) => _tags.contains(tag);

  /// Set-based diff vs the original, matching the server's semantics: a mere
  /// reorder is NOT a change (the PUT would return 200 without audit noise,
  /// so Save stays disabled).
  bool get changed {
    final a = _tags.toSet();
    final b = _original.toSet();
    return a.length != b.length || !a.containsAll(b);
  }

  /// Monitored tags that were in the original mod set but are missing from
  /// the working set — saving would remove them from the post entirely and
  /// re-expose it to non-opted-in users. Drives the confirmation dialog.
  List<String> get removedMonitored => _original
      .where((t) => kMonitoredHashtagTags.contains(t) && !_tags.contains(t))
      .toList();

  bool get removesMonitored => removedMonitored.isNotEmpty;
}
