import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cache/artwork_cache.dart';
import '../models/post.dart';
import 'api_providers.dart';
import 'auth_controller.dart' show currentUserSubProvider;
import 'paged.dart';

enum FeedKind { recent, promoted, following }

/// The three home feeds, each an auto-loading paged list of posts. Deliberately NOT autoDispose:
/// there are exactly three keys and we keep their loaded items + scroll position warm across
/// navigation. (The unbounded keyed feeds below — hashtag/owner — do autoDispose.) [audit F-19]
/// All feeds watch the signed-in identity: their content is viewer-filtered server-side
/// (monitored hashtags, following, userHasLiked), so an account switch must refetch it.
final feedProvider =
    StateNotifierProvider.family<PagedNotifier<Post>, PagedState<Post>, FeedKind>((ref, kind) {
  ref.watch(currentUserSubProvider);
  final api = ref.watch(feedApiProvider);
  final n = PagedNotifier<Post>(
      (cursor) => switch (kind) {
            FeedKind.recent => api.recent(cursor: cursor),
            FeedKind.promoted => api.promoted(cursor: cursor),
            FeedKind.following => api.following(cursor: cursor),
          },
      onPage: precacheArtworks);
  n.loadInitial();
  return n;
});

/// Posts for a hashtag.
final hashtagFeedProvider =
    StateNotifierProvider.autoDispose.family<PagedNotifier<Post>, PagedState<Post>, String>((ref, tag) {
  ref.watch(currentUserSubProvider);
  final api = ref.watch(feedApiProvider);
  final n = PagedNotifier<Post>((cursor) => api.hashtag(tag, cursor: cursor), onPage: precacheArtworks);
  n.loadInitial();
  return n;
});

/// A user's gallery, keyed by the owner's `user_key` (UUID).
final ownerFeedProvider =
    StateNotifierProvider.autoDispose.family<PagedNotifier<Post>, PagedState<Post>, String>((ref, userKey) {
  ref.watch(currentUserSubProvider);
  final api = ref.watch(feedApiProvider);
  final n = PagedNotifier<Post>((cursor) => api.byOwner(userKey, cursor: cursor), onPage: precacheArtworks);
  n.loadInitial();
  return n;
});
