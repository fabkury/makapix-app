/// A byte-budgeted LRU map (pure Dart, no Flutter imports).
///
/// Backs the decoded-animation frame cache: entries carry a byte size, the cache holds a
/// hard budget, and inserting past the budget evicts least-recently-used entries first.
library;

class ByteBudgetLru<K, V> {
  ByteBudgetLru({required this.maxBytes, required this.sizeOf, this.onEvict})
      : assert(maxBytes > 0);

  /// Hard budget. An entry is never stored if it alone exceeds this.
  final int maxBytes;

  /// Byte size of a value; charged on put, credited on evict/remove.
  final int Function(V value) sizeOf;

  /// Called for every value that leaves the cache (eviction, overwrite, remove, clear).
  final void Function(V value)? onEvict;

  // LinkedHashMap iteration order == insertion order; re-inserting on access makes the
  // first key the least recently used.
  final Map<K, V> _map = <K, V>{};
  int _totalBytes = 0;

  int get totalBytes => _totalBytes;
  int get length => _map.length;
  bool containsKey(K key) => _map.containsKey(key);

  /// Returns the value and marks it most-recently-used.
  V? get(K key) {
    final v = _map.remove(key);
    if (v == null) return null;
    _map[key] = v;
    return v;
  }

  /// Stores [value], evicting LRU entries until it fits. Returns false (storing
  /// nothing, evicting nothing) if the value alone exceeds [maxBytes]. Overwriting an
  /// existing key evicts the old value via [onEvict].
  bool put(K key, V value) {
    final size = sizeOf(value);
    if (size > maxBytes) return false;
    final old = _map.remove(key);
    if (old != null) {
      _totalBytes -= sizeOf(old);
      onEvict?.call(old);
    }
    while (_totalBytes + size > maxBytes && _map.isNotEmpty) {
      final lruKey = _map.keys.first;
      final evicted = _map.remove(lruKey) as V;
      _totalBytes -= sizeOf(evicted);
      onEvict?.call(evicted);
    }
    _map[key] = value;
    _totalBytes += size;
    return true;
  }

  void remove(K key) {
    final v = _map.remove(key);
    if (v == null) return;
    _totalBytes -= sizeOf(v);
    onEvict?.call(v);
  }

  void clear() {
    final values = _map.values.toList();
    _map.clear();
    _totalBytes = 0;
    for (final v in values) {
      onEvict?.call(v);
    }
  }
}
