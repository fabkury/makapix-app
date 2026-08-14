import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lineage.dart';
import '../models/post.dart';
import '../cache/artwork_cache.dart' show precacheArtworks;
import 'api_providers.dart';
import 'auth_controller.dart' show currentUserSubProvider;
import 'paged.dart';

/// Ordered Parent slots of a post (login-gated; the caller only shows lineage
/// UI to signed-in users). autoDispose: keyed by post id, unbounded key space.
final lineageParentsProvider =
    FutureProvider.autoDispose.family<List<LineageParentSlot>, int>((ref, postId) {
  ref.watch(currentUserSubProvider);
  return ref.read(lineageApiProvider).parents(postId);
});

/// Viewer-visible Remixes (Children) of a post, newest first, infinite scroll.
final lineageChildrenProvider = StateNotifierProvider.autoDispose
    .family<PagedNotifier<Post>, PagedState<Post>, int>((ref, postId) {
  ref.watch(currentUserSubProvider);
  final api = ref.watch(lineageApiProvider);
  final n = PagedNotifier<Post>((cursor) => api.children(postId, cursor: cursor),
      onPage: precacheArtworks);
  n.loadInitial();
  return n;
});

/// The private "Remixes of my works" aggregate, newest first.
final myRemixesProvider = StateNotifierProvider.autoDispose<PagedNotifier<RemixReceivedItem>,
    PagedState<RemixReceivedItem>>((ref) {
  ref.watch(currentUserSubProvider);
  final api = ref.watch(lineageApiProvider);
  final n = PagedNotifier<RemixReceivedItem>((cursor) => api.myRemixes(cursor: cursor),
      onPage: (items) => precacheArtworks([for (final i in items) i.post]));
  n.loadInitial();
  return n;
});
