// Composited-scene-frame cache: `ui.Image`s under the Club's ByteBudgetLru, keyed by frame
// index, invalidated wholesale by the engine's cache_epoch (every mutating DSL send bumps
// it). Handle safety via `ui.Image.clone()` — the cache owns its handle; [get] returns a
// clone the caller owns and must dispose (the platform's refcount, no manual counting).
import 'dart:ui' as ui;

import 'package:makapix_club/club/anim/byte_budget_lru.dart';

/// 64 MiB ≈ 256 frames of a 256×256 scene — the whole loop region warm for most scenes.
const int kSceneFrameCacheBytes = 64 << 20;

class SceneFrameCache {
  final ByteBudgetLru<int, ui.Image> _lru;
  int _epoch = -1;

  SceneFrameCache({int maxBytes = kSceneFrameCacheBytes})
      : _lru = ByteBudgetLru(
          maxBytes: maxBytes,
          sizeOf: (img) => img.width * img.height * 4,
          onEvict: (img) => img.dispose(),
        );

  /// Drop everything when the document epoch moved (coarse by design for v0.1 — mid-gesture
  /// the cache is cold anyway and the current frame is composited directly per move).
  void syncEpoch(int epoch) {
    if (epoch != _epoch) {
      _epoch = epoch;
      _lru.clear();
    }
  }

  /// A CLONE of the cached frame (caller disposes), or null on miss.
  ui.Image? get(int frame) => _lru.get(frame)?.clone();

  bool contains(int frame) => _lru.containsKey(frame);

  /// Insert; the cache takes its own clone (disposed immediately if the entry can't fit).
  void put(int frame, ui.Image img) {
    final own = img.clone();
    if (!_lru.put(frame, own)) own.dispose();
  }

  void clear() => _lru.clear();

  void dispose() => _lru.clear();
}
