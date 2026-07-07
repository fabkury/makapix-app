import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'animation_timeline.dart';
import 'byte_budget_lru.dart';

/// Global budget for decoded animation frames (RGBA in memory). Tunable.
const int kAnimationCacheBudgetBytes = 96 << 20; // 96 MiB

/// Per-post cap: an animation whose full decode would exceed this is not pre-decoded at
/// all — it renders through the unsynced fallback instead. Tunable.
const int kPerPostCapBytes = 32 << 20; // 32 MiB

/// One decoded animation: frames as ready-to-paint images plus its clock timeline.
///
/// Reference-counted because an LRU eviction can fire while a mounted tile is still
/// painting these `ui.Image`s: the cache holds one reference, every widget using the
/// animation holds one, and the images are disposed only when the count reaches zero.
class DecodedAnimation {
  DecodedAnimation({
    required this.frames,
    required this.timeline,
    required this.byteSize,
    required this.isPartial,
  }) : assert(frames.isNotEmpty);

  final List<ui.Image> frames;
  final AnimationTimeline timeline;

  /// Bytes charged to the cache budget — computed from the actually-decoded frames
  /// (width × height × 4 × frameCount), never from server metadata.
  final int byteSize;

  /// True for a frame-0-only entry (the animations-off path). Replaced in the cache by
  /// a full decode when playback is requested.
  final bool isPartial;

  int _refs = 1; // the creator's reference; transferred to the cache on put

  void retain() {
    assert(_refs > 0, 'retain() after the animation was disposed');
    _refs++;
  }

  void release() {
    assert(_refs > 0, 'release() after the animation was disposed');
    if (--_refs == 0) {
      for (final f in frames) {
        f.dispose();
      }
    }
  }
}

/// The in-memory frame cache, keyed by artwork URL so every tile showing the same
/// artwork shares one decode (and duplicate tiles stay trivially in sync).
class AnimationFrameCache {
  AnimationFrameCache({int maxBytes = kAnimationCacheBudgetBytes})
      : _lru = ByteBudgetLru<String, DecodedAnimation>(
          maxBytes: maxBytes,
          sizeOf: (a) => a.byteSize,
          onEvict: (a) => a.release(),
        );

  final ByteBudgetLru<String, DecodedAnimation> _lru;

  int get totalBytes => _lru.totalBytes;

  DecodedAnimation? get(String url) => _lru.get(url);

  /// Stores [animation], transferring the creator's reference to the cache (the LRU
  /// releases it on eviction/overwrite). Returns false — and releases immediately — in
  /// the never-expected case that the entry alone exceeds the whole budget.
  bool put(String url, DecodedAnimation animation) {
    final stored = _lru.put(url, animation);
    if (!stored) animation.release();
    return stored;
  }

  void remove(String url) => _lru.remove(url);
  void clear() => _lru.clear();

  /// Estimated decoded size; used as a pre-decode routing hint from server metadata and
  /// re-verified by the decoder against the codec's authoritative frame count.
  static int estimateBytes({required int width, required int height, required int frameCount}) =>
      width * height * 4 * frameCount;

  static bool underPerPostCap({
    required int width,
    required int height,
    required int frameCount,
    int capBytes = kPerPostCapBytes,
  }) =>
      estimateBytes(width: width, height: height, frameCount: frameCount) <= capBytes;
}

final animationFrameCacheProvider = Provider<AnimationFrameCache>((_) => AnimationFrameCache());
