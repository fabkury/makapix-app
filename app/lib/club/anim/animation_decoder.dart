import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cache/artwork_cache.dart';
import 'animation_timeline.dart';
import 'frame_cache.dart';

/// How a decode request ended.
enum DecodeStatus {
  /// [DecodeResult.animation] is set (cache reference held by the cache; callers must
  /// `retain()` before use).
  success,

  /// The file's real size (from the codec's authoritative frame count) exceeds the
  /// per-post cap — the server's `frame_count` hint was only a hint. Render the
  /// unsynced fallback, NOT the error widget.
  overCap,

  /// Fetch or decode failed; render the error widget.
  error,
}

class DecodeResult {
  const DecodeResult.success(DecodedAnimation this.animation) : status = DecodeStatus.success;
  const DecodeResult.overCap()
      : status = DecodeStatus.overCap,
        animation = null;
  const DecodeResult.error()
      : status = DecodeStatus.error,
        animation = null;

  final DecodeStatus status;
  final DecodedAnimation? animation;
}

/// The bytes seam: how the decoder obtains an artwork's file bytes. The default reads
/// through the existing disk cache (downloading on miss); tests override this provider
/// with an in-memory fixture — no network, no cache manager.
final animationBytesFetcherProvider = Provider<Future<Uint8List> Function(String url)>(
  (_) => (url) async => (await artImageCache.getSingleFile(url)).readAsBytes(),
);

/// Decodes animated artworks into the frame cache.
///
/// Byte fetches run concurrently (the disk cache / network layer handles parallelism),
/// but codec walks are serialized through a single FIFO worker so a grid page mounting
/// a dozen animated tiles doesn't stampede the UI isolate. Requests for the same URL
/// are deduped onto one in-flight future. There is no cancellation: a decode whose tile
/// disposed still lands in the cache and is almost certainly reused on scroll-back.
///
/// A later just-in-time catch-up decoder (the designated over-cap upgrade — see
/// docs/plans/feed-animation-sync.md) slots in behind [request] without touching widgets.
class AnimationDecoder {
  AnimationDecoder({
    required this.cache,
    required this.fetchBytes,
    this.perPostCapBytes = kPerPostCapBytes,
    this.instantiateCodec = ui.instantiateImageCodec,
  });

  final AnimationFrameCache cache;
  final Future<Uint8List> Function(String url) fetchBytes;
  final int perPostCapBytes;

  /// Injectable for tests: dart:ui codec futures are unreliable under flutter_test's
  /// fake-async zone, so orchestration tests substitute a fake codec. Production
  /// always uses [ui.instantiateImageCodec].
  final Future<ui.Codec> Function(Uint8List bytes) instantiateCodec;

  // Keyed by "$firstFrameOnly:$url" — a full request never piggybacks on a partial one.
  final Map<String, Completer<DecodeResult>> _inFlight = {};

  // Async mutex serializing codec walks (non-null while a walk is in progress).
  Completer<void>? _walkGate;

  /// Decode `url` (all frames, or just frame 0 when [firstFrameOnly] — the
  /// animations-off path). On success the result is already in the cache; a full decode
  /// replaces a cached partial entry for the same URL.
  ///
  /// Deliberately flat future plumbing: explicit Completers completed directly, no
  /// `.then` queue chains, no `whenComplete`, no async return-future flattening —
  /// those shapes stall future delivery under flutter_test's zones (empirically
  /// bisected; plain awaited async functions and direct Completer completion do not).
  Future<DecodeResult> request(String url, {required bool firstFrameOnly}) {
    final cached = cache.get(url);
    if (cached != null && (!cached.isPartial || firstFrameOnly)) {
      return Future.value(DecodeResult.success(cached));
    }
    final key = '$firstFrameOnly:$url';
    final existing = _inFlight[key];
    if (existing != null) return existing.future;
    final completer = Completer<DecodeResult>();
    _inFlight[key] = completer;
    _process(key, url, firstFrameOnly, completer);
    return completer.future;
  }

  Future<void> _process(
      String key, String url, bool firstFrameOnly, Completer<DecodeResult> completer) async {
    DecodeResult result;
    try {
      final bytes = await fetchBytes(url); // concurrent across URLs
      // Serialize the codec walk so a grid page mounting a dozen animated tiles
      // doesn't stampede the UI isolate.
      while (_walkGate != null) {
        await _walkGate!.future;
      }
      final gate = _walkGate = Completer<void>();
      try {
        result = await _decode(url, bytes, firstFrameOnly: firstFrameOnly);
      } finally {
        _walkGate = null;
        gate.complete();
      }
    } catch (_) {
      result = const DecodeResult.error();
    }
    _inFlight.remove(key);
    completer.complete(result);
  }

  Future<DecodeResult> _decode(String url, Uint8List bytes, {required bool firstFrameOnly}) async {
    // Another request may have filled the cache while this job sat in the queue.
    final cached = cache.get(url);
    if (cached != null && (!cached.isPartial || firstFrameOnly)) {
      return DecodeResult.success(cached);
    }
    try {
      final codec = await instantiateCodec(bytes);
      final first = await codec.getNextFrame();
      final w = first.image.width, h = first.image.height;
      final frameCount = codec.frameCount;

      if (firstFrameOnly) {
        codec.dispose();
        // Partial entries are always tiny (one frame) — no cap check.
        final anim = DecodedAnimation(
          frames: [first.image],
          timeline: AnimationTimeline([first.duration.inMilliseconds]),
          byteSize: AnimationFrameCache.estimateBytes(width: w, height: h, frameCount: 1),
          isPartial: true,
        );
        cache.put(url, anim);
        return DecodeResult.success(anim);
      }

      // Re-verify the cap against the codec's authoritative count — the widget's
      // pre-check ran on the server's frame_count, which can disagree with the file
      // (e.g. encoders that merge equal sequential frames).
      final realSize = AnimationFrameCache.estimateBytes(width: w, height: h, frameCount: frameCount);
      if (realSize > perPostCapBytes) {
        first.image.dispose();
        codec.dispose();
        return const DecodeResult.overCap();
      }

      final frames = <ui.Image>[first.image];
      final delaysMs = <int>[first.duration.inMilliseconds];
      for (var i = 1; i < frameCount; i++) {
        final fi = await codec.getNextFrame();
        frames.add(fi.image);
        delaysMs.add(fi.duration.inMilliseconds);
      }
      codec.dispose();

      final anim = DecodedAnimation(
        frames: frames,
        timeline: AnimationTimeline(delaysMs),
        byteSize: realSize,
        isPartial: false,
      );
      cache.put(url, anim); // replaces a partial entry (LRU releases the old one)
      return DecodeResult.success(anim);
    } catch (_) {
      return const DecodeResult.error();
    }
  }
}

final animationDecoderProvider = Provider<AnimationDecoder>(
  (ref) => AnimationDecoder(
    cache: ref.watch(animationFrameCacheProvider),
    fetchBytes: ref.watch(animationBytesFetcherProvider),
  ),
);
