// A small id-keyed LRU for the Frames page's thumbnails (ADR 0031): keyed by FRAME ID so a
// structural batch keeps every thumb it can, sized for a page of tiles (not the whole roll),
// disposing what it evicts. Generic over the value so it is testable without images.

import 'dart:collection';

import '../thumbnail.dart';

class LruById<V> {
  LruById({required this.capacity, required this.onEvict});

  final int capacity;
  final void Function(V) onEvict;
  final LinkedHashMap<int, V> _map = LinkedHashMap<int, V>();

  int get length => _map.length;

  bool contains(int id) => _map.containsKey(id);

  /// Fetch and mark as most recently used.
  V? get(int id) {
    final v = _map.remove(id);
    if (v == null) return null;
    _map[id] = v;
    return v;
  }

  /// Peek without touching the recency order.
  V? peek(int id) => _map[id];

  void put(int id, V v) {
    final old = _map.remove(id);
    if (old != null) onEvict(old);
    _map[id] = v;
    while (_map.length > capacity) {
      final victim = _map.keys.first;
      final evicted = _map.remove(victim);
      if (evicted != null) onEvict(evicted);
    }
  }

  void invalidate(Iterable<int> ids) {
    for (final id in ids) {
      final v = _map.remove(id);
      if (v != null) onEvict(v);
    }
  }

  void clear() {
    final all = _map.values.toList();
    _map.clear();
    for (final v in all) {
      onEvict(v);
    }
  }
}

/// The page's cache: `ThumbCache` (hash + image) per frame id; eviction disposes the image.
typedef FrameThumbCache = LruById<ThumbCache>;
