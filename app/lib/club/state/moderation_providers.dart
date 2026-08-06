import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/post.dart';
import '../models/umd.dart';
import 'api_providers.dart';
import 'auth_controller.dart';
import 'paged.dart';

/// The UMD payload for one user (moderator-only; the page invalidates this
/// after every action so the UI stays server-true).
// autoDispose: released when the User Management page closes.
final umdUserProvider = FutureProvider.autoDispose.family<UmdUserData, String>((ref, sqid) {
  // Account switches must not leak one moderator session's view into another.
  ref.watch(currentUserSubProvider);
  return ref.watch(moderationApiProvider).getUserManagement(sqid);
});

/// Posts awaiting public-visibility approval (`GET /admin/pending-approval`,
/// newest first). Only instantiated for moderators (UI gate).
// autoDispose: released when the queue page closes.
final pendingApprovalProvider =
    StateNotifierProvider.autoDispose<PagedNotifier<Post>, PagedState<Post>>((ref) {
  ref.watch(currentUserSubProvider);
  final api = ref.watch(moderationApiProvider);
  final n = PagedNotifier<Post>((cursor) => api.pendingApproval(cursor: cursor));
  n.loadInitial();
  return n;
});
