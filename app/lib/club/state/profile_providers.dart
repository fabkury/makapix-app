import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/club_error.dart';
import '../models/user_profile.dart';
import 'api_providers.dart';

class ProfileController extends StateNotifier<AsyncValue<UserProfile>> {
  final Ref ref;
  final String sqid;
  ProfileController(this.ref, this.sqid) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      state = AsyncValue.data(await ref.read(profileApiProvider).profile(sqid));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
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
      return e.message;
    } catch (_) {
      state = AsyncValue.data(cur);
      return 'Could not update follow.';
    }
  }
}

final profileProvider =
    StateNotifierProvider.family<ProfileController, AsyncValue<UserProfile>, String>(
        (ref, sqid) => ProfileController(ref, sqid));
