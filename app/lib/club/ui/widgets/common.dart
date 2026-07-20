import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../anim/frame_cache.dart';
import '../../cache/artwork_cache.dart';
import '../../config/club_config.dart';
import '../../state/animation_settings.dart';
import 'synced_pixel_art_image.dart';

/// Backdrop painted behind letterboxed/pillarboxed artwork (grid tiles, thumbnails),
/// so the square display area reads as a frame around non-square art.
const Color kArtworkBackdrop = Color(0xFF15171A);

/// Compact count for stat rows, e.g. 999 → "999", 12345 → "12.3k", 3400000 → "3.4M".
String compactCount(int n) {
  if (n < 1000) return '$n';
  // 999500+ rounds to "1000k" in the k branch — hand it to M ("1M") instead.
  final (v, suffix) = n < 999500 ? (n / 1000.0, 'k') : (n / 1000000.0, 'M');
  final txt = v >= 99.95
      ? v.round().toString()
      : v.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
  return '$txt$suffix';
}

/// File size in the nearest of bytes/KiB/MiB, e.g. 512 → "512 bytes",
/// 38214 → "37.3 KiB", 5452595 → "5.2 MiB".
String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes bytes';
  final (v, unit) =
      bytes < 1024 * 1024 ? (bytes / 1024.0, 'KiB') : (bytes / (1024.0 * 1024.0), 'MiB');
  return '${v.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')} $unit';
}

/// Compact relative time, e.g. "3h", "2d".
String timeAgo(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().toUtc().difference(t.toUtc());
  if (d.inSeconds < 60) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  if (d.inDays < 30) return '${(d.inDays / 7).floor()}w';
  if (d.inDays < 365) return '${(d.inDays / 30).floor()}mo';
  return '${(d.inDays / 365).floor()}y';
}

class ClubErrorRetry extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const ClubErrorRetry({super.key, required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 40, color: Colors.white30),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ]),
        ),
      );
}

class ClubEmpty extends StatelessWidget {
  final String message;
  final IconData icon;
  const ClubEmpty({super.key, required this.message, this.icon = Icons.inbox_outlined});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 40, color: Colors.white24),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: Colors.white38)),
        ]),
      );
}

class SignInPrompt extends StatelessWidget {
  final String message;
  final VoidCallback onSignIn;
  const SignInPrompt({super.key, required this.message, required this.onSignIn});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.lock_outline, size: 40, color: Colors.white30),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
            const SizedBox(height: 12),
            FilledButton(onPressed: onSignIn, child: const Text('Sign in')),
          ]),
        ),
      );
}

/// Pixel-art image with nearest-neighbor scaling and graceful loading/error.
///
/// Static artworks (`frameCount <= 1`, the default) render through today's
/// CachedNetworkImage path, untouched. Call sites that pass a `Post`'s
/// `frameCount`/`width`/`height` opt animated artworks into clock-synchronized playback
/// (`SyncedPixelArtImage`) — unless the post's estimated decoded size is over the
/// per-post cap (or dimensions are unknown), in which case it takes the unsynced
/// fallback seam. The server's frame_count/width/height are routing hints only; the
/// decoder re-verifies against the actual file.
class PixelArtImage extends ConsumerWidget {
  final String url;
  final BoxFit fit;

  /// Server-reported frame count (`Post.frameCount`); 1 = static.
  final int frameCount;

  /// Artwork pixel dimensions, for the pre-decode size check. 0 = unknown.
  final int width;
  final int height;

  /// Detail-page override: play even when autoplay/reduce-motion says frozen.
  final bool forcePlay;

  const PixelArtImage({
    super.key,
    required this.url,
    this.fit = BoxFit.contain,
    this.frameCount = 1,
    this.width = 0,
    this.height = 0,
    this.forcePlay = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (url.isEmpty) {
      return const ColoredBox(
        color: kArtworkBackdrop,
        child: Center(child: Icon(Icons.image_not_supported, color: Colors.white24)),
      );
    }
    if (frameCount <= 1) return cachedNetworkArtImage(url, fit);
    if (width <= 0 ||
        height <= 0 ||
        !AnimationFrameCache.underPerPostCap(width: width, height: height, frameCount: frameCount)) {
      return buildUnsyncedAnimatedFallback(url, fit);
    }
    final autoplay = ref.watch(animationAutoplayProvider);
    final playing = forcePlay || (autoplay && !MediaQuery.disableAnimationsOf(context));
    return SyncedPixelArtImage(url: url, fit: fit, playing: playing);
  }
}

/// A small circular avatar from a URL, falling back to the handle's initial.
class HandleAvatar extends StatelessWidget {
  final String? url;
  final String handle;
  final double radius;
  const HandleAvatar({super.key, required this.url, required this.handle, this.radius = 16});
  @override
  Widget build(BuildContext context) {
    final has = url != null && url!.isNotEmpty;
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFF2A2D31),
      backgroundImage: has
          ? CachedNetworkImageProvider(resolveClubUrl(url!), cacheManager: avatarImageCache)
          : null,
      child: has ? null : Text(handle.isNotEmpty ? handle[0].toUpperCase() : '?', style: TextStyle(fontSize: radius)),
    );
  }
}
