import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cache/artwork_cache.dart';
import '../models/club_error.dart';
import '../models/post.dart';
import '../models/user_profile.dart';
import 'api_providers.dart';
import 'auth_controller.dart' show currentUserSubProvider;
import 'paged.dart';

class ProfileController extends StateNotifier<AsyncValue<UserProfile>> {
  final Ref ref;
  final String sqid;
  ProfileController(this.ref, this.sqid) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    await _fetch();
  }

  /// Refetch without flipping to loading, so the page (tabs, scroll) stays
  /// mounted — used by pull-to-refresh and the Edit-profile return.
  Future<void> reload() async {
    if (state.value == null) return load(); // nothing to preserve
    await _fetch();
  }

  Future<void> _fetch() async {
    try {
      state = AsyncValue.data(await ref.read(profileApiProvider).profile(sqid));
    } catch (e, st) {
      // A silent reload keeps showing the stale profile rather than erroring out.
      if (state.value == null) state = AsyncValue.error(e, st);
    }
  }

  /// Optimistic follow/unfollow; reconciles `follower_count` from the response.
  Future<String?> toggleFollow() async {
    final cur = state.value;
    if (cur == null) return null;
    final follow = !cur.isFollowing;
    state = AsyncValue.data(cur.copyWith(
      isFollowing: follow,
      stats: cur.stats.copyWith(followerCount: cur.stats.followerCount + (follow ? 1 : -1)),
    ));
    try {
      final api = ref.read(profileApiProvider);
      final count = follow ? await api.follow(sqid) : await api.unfollow(sqid);
      final latest = state.value;
      if (count >= 0 && latest != null) {
        state = AsyncValue.data(latest.copyWith(stats: latest.stats.copyWith(followerCount: count)));
      }
      return null;
    } on ClubError catch (e) {
      state = AsyncValue.data(cur); // rollback
      return e.isBlocked ? kBlockedInteractionMessage : e.message;
    } catch (_) {
      state = AsyncValue.data(cur);
      return 'Could not update follow.';
    }
  }
}

final profileProvider =
    StateNotifierProvider.autoDispose.family<ProfileController, AsyncValue<UserProfile>, String>(
        (ref, sqid) => ProfileController(ref, sqid)); // [audit F-19]

/// Posts a user reacted to (the profile's ⚡ Reacted tab), keyed by the
/// profile's public sqid. Only instantiated for signed-in viewers (UI gate).
final reactedFeedProvider =
    StateNotifierProvider.autoDispose.family<PagedNotifier<Post>, PagedState<Post>, String>((ref, sqid) {
  ref.watch(currentUserSubProvider); // account switch must refetch [audit 4e1ff81]
  final api = ref.watch(profileApiProvider);
  final n = PagedNotifier<Post>((cursor) => api.reactedPosts(sqid, cursor: cursor),
      onPage: precacheArtworks);
  n.loadInitial();
  return n;
});
