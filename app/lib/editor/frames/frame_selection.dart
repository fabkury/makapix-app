// The Frames page's selection (ADR 0031): an immutable set of FRAME IDS plus the anchor the
// next Shift-click / "Select to here" ranges from. Ids, never indices, so the selection
// survives reorders, undo, and redo (restored frames keep their ids); a member whose frame is
// gone simply drops out on the next [retain]. Transient: discarded when the page closes.

import 'dart:collection';

class FrameSelection {
  FrameSelection({Set<int> ids = const {}, this.anchorId}) : ids = UnmodifiableSetView(Set.of(ids));

  static final FrameSelection empty = FrameSelection();

  final Set<int> ids;

  /// The last tile the artist touched — the start of a Shift-range. Kept across toggles so
  /// "select to here" reads naturally; dropped by [retain] when its frame is gone.
  final int? anchorId;

  bool contains(int id) => ids.contains(id);
  int get length => ids.length;
  bool get isEmpty => ids.isEmpty;
  bool get isNotEmpty => ids.isNotEmpty;

  /// Tap: flip one membership; the tile becomes the anchor either way.
  FrameSelection toggle(int id) {
    final next = Set.of(ids);
    if (!next.remove(id)) next.add(id);
    return FrameSelection(ids: next, anchorId: id);
  }

  /// A sweep's first tile (or a plain single selection): exactly this one, anchored here.
  FrameSelection setOnly(int id) => FrameSelection(ids: {id}, anchorId: id);

  /// Union with [more]; the anchor moves to [anchor] when given, else stays.
  FrameSelection addAll(Iterable<int> more, {int? anchor}) =>
      FrameSelection(ids: {...ids, ...more}, anchorId: anchor ?? anchorId);

  /// Difference with [gone] (a deselecting sweep); the anchor moves to [anchor] when given,
  /// else stays even when it is among the removed — it is a position, not a member.
  FrameSelection removeAll(Iterable<int> gone, {int? anchor}) {
    final next = Set.of(ids)..removeAll(gone);
    return FrameSelection(ids: next, anchorId: anchor ?? anchorId);
  }

  /// Shift-click / "Select to here": add every id between the anchor and [id] in roll
  /// [order] (inclusive, either direction); the anchor stays. Without a usable anchor this is
  /// a plain [toggle].
  FrameSelection rangeTo(int id, List<int> order) {
    final a = anchorId == null ? -1 : order.indexOf(anchorId!);
    final b = order.indexOf(id);
    if (a < 0 || b < 0) return toggle(id);
    final lo = a < b ? a : b;
    final hi = a < b ? b : a;
    return FrameSelection(ids: {...ids, ...order.sublist(lo, hi + 1)}, anchorId: anchorId);
  }

  FrameSelection selectAll(List<int> order) => FrameSelection(ids: order.toSet(), anchorId: anchorId);

  FrameSelection invert(List<int> order) =>
      FrameSelection(ids: order.where((id) => !ids.contains(id)).toSet(), anchorId: anchorId);

  FrameSelection cleared() => FrameSelection();

  /// After a refresh, undo, or redo: keep only members that still exist; the anchor too.
  FrameSelection retain(Set<int> live) => FrameSelection(
        ids: ids.where(live.contains).toSet(),
        anchorId: anchorId != null && live.contains(anchorId) ? anchorId : null,
      );

  /// Post-Duplicate / Repeat / Range entry: exactly these ids; the anchor survives when it is
  /// among them, else the first of the new set.
  FrameSelection replaceWith(Iterable<int> next) {
    final set = Set.of(next);
    final anchor = anchorId != null && set.contains(anchorId) ? anchorId : (set.isEmpty ? null : set.first);
    return FrameSelection(ids: set, anchorId: anchor);
  }

  /// The members as ascending roll indices, given the live id → index map; unknown ids are
  /// skipped (they vanished since the last [retain]).
  List<int> toIndices(Map<int, int> indexOf) {
    final out = <int>[];
    for (final id in ids) {
      final i = indexOf[id];
      if (i != null) out.add(i);
    }
    out.sort();
    return out;
  }

  /// A stable identity of the membership (sorted ids), the delete button's arm key half.
  String get signature => (ids.toList()..sort()).join(',');

  @override
  bool operator ==(Object other) =>
      other is FrameSelection && other.anchorId == anchorId && other.ids.length == ids.length && other.ids.containsAll(ids);

  @override
  int get hashCode => Object.hash(anchorId, signature);

  @override
  String toString() => 'FrameSelection($signature, anchor: $anchorId)';
}
