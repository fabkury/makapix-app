import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'feed_providers.dart';

/// Re-rolled once per app session so cold starts don't repeat the same pick
/// for unchanged feed content.
final int _sessionSalt = Random().nextInt(1 << 30);

/// Deterministic page-1 index of the super post: stable for a given
/// (salt, feed, generation) so it survives load-more appends and rebuilds,
/// re-rolled whenever the feed's refresh generation bumps.
@visibleForTesting
int pickSuperIndex(
    {required int salt, required int kindIndex, required int generation, required int firstPageCount}) {
  if (firstPageCount <= 0) return -1;
  return Random(Object.hash(salt, kindIndex, generation)).nextInt(firstPageCount);
}

/// Post id shown as the 2×2 super tile of a home feed, or null when the feed
/// is empty/uninitialized. Random among page-1 posts for now; a future
/// moderator-designated post id would take precedence here.
final superPostIdProvider = Provider.family<int?, FeedKind>((ref, kind) {
  final s = ref.watch(feedProvider(kind));
  final i = pickSuperIndex(
      salt: _sessionSalt,
      kindIndex: kind.index,
      generation: s.generation,
      firstPageCount: s.firstPageCount);
  return (i < 0 || i >= s.items.length) ? null : s.items[i].id;
});
