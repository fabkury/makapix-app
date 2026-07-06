import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/blocked_user.dart';
import 'api_providers.dart';
import 'auth_controller.dart' show currentUserSubProvider;
import 'feed_providers.dart';
import 'paged.dart';
import 'profile_providers.dart';

/// The blocked-users list, with an extra [remove] for optimistic row deletion
/// on unblock (the base [PagedNotifier.state] is protected, so a subclass is
/// the clean way to touch it — ugc-safety A10/R8).
class BlockedUsersNotifier extends PagedNotifier<BlockedUser> {
  BlockedUsersNotifier(super.fetch);

  /// Drop the row for [sqid] from local state after a successful unblock,
  /// avoiding a full reload of the list.
  void remove(String sqid) {
    state = state.copyWith(items: state.items.where((b) => b.publicSqid != sqid).toList());
  }
}

/// The caller's blocked users (`GET /me/blocks`), paginated. Watches the
/// signed-in identity so an account switch drops and refetches the list.
final blockedUsersProvider =
    StateNotifierProvider.autoDispose<BlockedUsersNotifier, PagedState<BlockedUser>>((ref) {
  ref.watch(currentUserSubProvider);
  final api = ref.watch(safetyApiProvider);
  final n = BlockedUsersNotifier((cursor) => api.blocks(cursor: cursor));
  n.loadInitial();
  return n;
});

/// Block [sqid], then refresh the surfaces the server now filters. Keeps
/// invalidation in one place (ugc-safety §6). Throws [ClubError] on failure —
/// the caller maps it to user-facing copy.
Future<void> blockUser(WidgetRef ref, String sqid) async {
  await ref.read(safetyApiProvider).block(sqid);
  ref.invalidate(profileProvider(sqid));
  ref.invalidate(feedProvider);
  ref.invalidate(blockedUsersProvider);
}

/// Unblock [sqid]. Leaves [blockedUsersProvider] to the caller (the blocked
/// list removes its own row; the profile page has no list open).
Future<void> unblockUser(WidgetRef ref, String sqid) async {
  await ref.read(safetyApiProvider).unblock(sqid);
  ref.invalidate(profileProvider(sqid));
  ref.invalidate(feedProvider);
}
