import 'package:flutter/material.dart';

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
class PixelArtImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  const PixelArtImage({super.key, required this.url, this.fit = BoxFit.contain});
  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return const ColoredBox(
        color: Color(0xFF15171A),
        child: Center(child: Icon(Icons.image_not_supported, color: Colors.white24)),
      );
    }
    return Image.network(
      url,
      fit: fit,
      filterQuality: FilterQuality.none,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => const ColoredBox(
        color: Color(0xFF15171A),
        child: Center(child: Icon(Icons.broken_image, color: Colors.white24)),
      ),
      loadingBuilder: (c, child, p) => p == null
          ? child
          : const Center(child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))),
    );
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
      backgroundImage: has ? NetworkImage(url!) : null,
      child: has ? null : Text(handle.isNotEmpty ? handle[0].toUpperCase() : '?', style: TextStyle(fontSize: radius)),
    );
  }
}
