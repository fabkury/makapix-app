import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../anim/animation_decoder.dart';
import '../../anim/frame_cache.dart';
import '../../cache/artwork_cache.dart';
import '../../state/animation_clock.dart';

/// The shared loading/error looks for artwork, used by both the CachedNetworkImage
/// path and the synced player so animated and static posts stay visually identical.
const Widget kArtLoadingPlaceholder = Center(
    child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)));
const Widget kArtErrorWidget = ColoredBox(
  color: Color(0xFF15171A),
  child: Center(child: Icon(Icons.broken_image, color: Colors.white24)),
);

/// Today's decode-and-paint path: Flutter's built-in codec over the artwork disk cache.
/// Static posts always render through this.
Widget cachedNetworkArtImage(String url, BoxFit fit) => CachedNetworkImage(
      imageUrl: url,
      cacheManager: artImageCache,
      fit: fit,
      filterQuality: FilterQuality.none,
      // No fades: cached pixel art should pop in crisp, like the old gapless Image.network did.
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      useOldImageOnUrlChange: true,
      errorWidget: (_, _, _) => kArtErrorWidget,
      placeholder: (_, _) => kArtLoadingPlaceholder,
    );

/// THE designated fallback seam: every animated post that is not pre-decoded (over the
/// per-post cap — whether detected up front from server metadata or mid-decode from the
/// codec's authoritative frame count) renders through this. Today it is native unsynced
/// playback; the recorded upgrade is a just-in-time catch-up decoder that keeps even
/// over-cap posts on the shared clock (docs/plans/feed-animation-sync.md). Keep the
/// signature stable and route ALL over-cap paths through here.
Widget buildUnsyncedAnimatedFallback(String url, BoxFit fit) => cachedNetworkArtImage(url, fit);

/// An animated artwork whose displayed frame is a pure function of the wall clock
/// (see `club/anim/animation_timeline.dart`), so every tile showing loop-compatible
/// artworks is frame-locked with every other — across scroll remounts, grid ⇄ detail
/// navigation, backgrounding, and even across devices.
///
/// Fetching/disk-caching stays on the existing `artImageCache`; this widget replaces
/// only the decode/paint stage. With `playing: false` (reduce-motion or the autoplay
/// setting off) it shows frame 0 from a cheap one-frame decode and never registers
/// with the clock.
class SyncedPixelArtImage extends ConsumerStatefulWidget {
  const SyncedPixelArtImage({
    super.key,
    required this.url,
    this.fit = BoxFit.contain,
    this.playing = true,
  });

  final String url;
  final BoxFit fit;
  final bool playing;

  @override
  ConsumerState<SyncedPixelArtImage> createState() => _SyncedPixelArtImageState();
}

class _SyncedPixelArtImageState extends ConsumerState<SyncedPixelArtImage> {
  DecodedAnimation? _anim; // retained; released on replacement/dispose
  bool _error = false;
  bool _overCap = false;
  bool _registered = false;

  // Captured once so dispose() never has to touch `ref` during scope teardown.
  late final SyncFrameClock _clock;

  @override
  void initState() {
    super.initState();
    _clock = ref.read(syncFrameClockProvider.notifier);
    _updateRegistration();
    _load();
  }

  @override
  void didUpdateWidget(SyncedPixelArtImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      // Keep painting the old animation until the new decode lands (parity with
      // CachedNetworkImage's useOldImageOnUrlChange).
      _error = false;
      _overCap = false;
      _load();
    } else if (!old.playing && widget.playing && (_anim?.isPartial ?? false)) {
      _load(); // upgrade the frame-0 partial to a full decode
    }
    _updateRegistration();
  }

  @override
  void dispose() {
    if (_registered) _clock.unregister();
    _anim?.release();
    super.dispose();
  }

  /// The clock ticks only for widgets that can actually change frames: playing, not in
  /// a terminal fallback/error state, and not a known single-frame animation (a post
  /// whose server hint said "animated" but whose file decoded to one frame).
  void _updateRegistration() {
    final a = _anim;
    final want = widget.playing &&
        !_error &&
        !_overCap &&
        (a == null || a.isPartial || a.frames.length > 1);
    if (want == _registered) return;
    _registered = want;
    want ? _clock.register() : _clock.unregister();
  }

  Future<void> _load() async {
    final url = widget.url;
    final firstFrameOnly = !widget.playing;
    final cache = ref.read(animationFrameCacheProvider);
    final hit = cache.get(url);
    if (hit != null && (!hit.isPartial || firstFrameOnly)) {
      _adopt(hit);
      return;
    }
    final result = await ref
        .read(animationDecoderProvider)
        .request(url, firstFrameOnly: firstFrameOnly);
    if (!mounted || widget.url != url) return; // stale response
    switch (result.status) {
      case DecodeStatus.success:
        _adopt(result.animation!);
      case DecodeStatus.overCap:
        setState(() => _overCap = true);
        _updateRegistration();
      case DecodeStatus.error:
        setState(() => _error = true);
        _updateRegistration();
    }
  }

  void _adopt(DecodedAnimation anim) {
    anim.retain();
    final old = _anim;
    setState(() {
      _anim = anim;
      _error = false;
      _overCap = false;
    });
    old?.release();
    _updateRegistration();
    // If playback was turned on while a frame-0 partial was still in flight, the
    // didUpdateWidget upgrade found nothing to upgrade — kick the full decode now.
    if (widget.playing && anim.isPartial) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_overCap) return buildUnsyncedAnimatedFallback(widget.url, widget.fit);
    if (_error) return kArtErrorWidget;
    final anim = _anim;
    if (anim == null) return kArtLoadingPlaceholder;
    final int index;
    if (widget.playing && !anim.isPartial && anim.frames.length > 1) {
      // Rebuild only when the computed frame index changes — `select` memoizes across
      // the clock's per-tick notifications, and synced tiles flip on the same tick.
      index = ref.watch(
          syncFrameClockProvider.select((now) => anim.timeline.frameIndexAt(now)));
    } else {
      index = 0;
    }
    return RawImage(
      image: anim.frames[index],
      fit: widget.fit,
      filterQuality: FilterQuality.none,
    );
  }
}
