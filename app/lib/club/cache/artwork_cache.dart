import 'dart:async';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../models/post.dart';

/// Persistent (disk) caches for Club images.
///
/// The server contract (reference/makapix-club/message/0003): a vault URL's bytes are immutable
/// forever, and `art_url` changes iff the artwork content changes — so cached artwork never goes
/// stale and never needs revalidation; the object cap below is the effective bound (the vault's
/// `Cache-Control: max-age=31536000` overrides `stalePeriod` for freshness). Do NOT append query
/// strings to vault URLs — explicitly out of contract (player firmware).
final CacheManager artImageCache = CacheManager(
  Config('mkpxArt', stalePeriod: const Duration(days: 90), maxNrOfCacheObjects: 1000),
);

/// Avatars hosted on the vault rotate their URL on change too, but GitHub-hosted avatar URLs can
/// change bytes in place — hence a short freshness window (GitHub's own short `max-age` applies
/// where sent; this is the fallback).
final CacheManager avatarImageCache = CacheManager(
  Config('mkpxAvatar', stalePeriod: const Duration(days: 7), maxNrOfCacheObjects: 400),
);

/// Fire-and-forget prefetch of a feed page's artwork into the disk cache, so tiles render without
/// a spinner when scrolled into view. Already-cached URLs are a no-op; errors are swallowed — the
/// tile's own load will surface them.
void precacheArtworks(List<Post> posts) {
  for (final p in posts) {
    if (p.artUrl.isEmpty) continue;
    unawaited(artImageCache.getSingleFile(p.artUrl).then((_) {}, onError: (_) {}));
  }
}
